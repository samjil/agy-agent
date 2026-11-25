# session-start-hook.ps1
# Claude Code SessionStart 훅: 새 세션이 시작될 때 Claude 에게 samjil-delegate-agy 스킬의 위임 규칙 한 줄과 워처 상태를 알립니다(표준 출력이 세션 문맥이 됩니다).
#   - 세션 시작 시에는 워처를 켜지 않습니다(꺼져 있어도 위임할 때 submit-task.ps1 이 자동으로 켜고, 켜지지 않으면 작업자를 직접 실행합니다).
# 어떤 경우에도 오류로 세션 시작을 막지 않도록 항상 종료 코드 0 으로 끝납니다.
# -Event UserPromptSubmit: 질문을 보낼 때마다, 컨텍스트가 기준을 넘었으면 "위임하면 agy 제출을 서브에이전트에" 한 줄만 출력한다
#   (표준 입력 JSON 의 transcript_path 로 크기를 읽는다). Node 가 있으면 같은 일을 하는 prompt-hook.js 가 대신 등록된다.
# -Event PreToolUse: Agent/Task 도구 호출 시 세션마다 처음 한 번 agy 위임 관문(deny), 두 번째부터는 참고 안내(additionalContext).
param(
    [string]$RuntimeDir = "",
    [string]$EnsureScript = "",
    [string]$Event = "SessionStart",
    [string]$TranscriptPath = "",     # 시험용. 없으면 Claude Code 가 표준 입력으로 주는 JSON 의 transcript_path 를 쓴다
    [string]$HookInputPath = "",      # 시험용. PreToolUse 에서 표준 입력 대신 읽을 JSON 파일 경로
    [string]$InstallRoot = ""         # 시험용. 없으면 ~/.samjil 을 쓴다
)

# 창과 파이프 상속 없이 백그라운드 PowerShell 을 띄운다(agy-spawn.ps1 없으면 WScript.Shell 로 폴백).
function Start-HookHiddenPowerShell([string[]]$ArgumentList) {
    try {
        $spawnLib = Join-Path $PSScriptRoot "agy-spawn.ps1"
        if (Test-Path -LiteralPath $spawnLib) {
            . $spawnLib
            [void](Start-AgyHiddenDetachedProcess -FilePath "powershell.exe" -ArgumentList $ArgumentList)
            return
        }
        $sh = New-Object -ComObject WScript.Shell
        $q = [char]34
        $cmd = "powershell.exe " + ((@($ArgumentList) | ForEach-Object {
            $s = [string]$_
            if ($s -match '[\s"]') { $q + ($s -replace '"', '\"') + $q } else { $s }
        }) -join " ")
        [void]$sh.Run($cmd, 0, $false)
    } catch {}
}

# 표준 입력을 한도 시간 안에 끝까지 읽어 UTF-8 문자열로 돌려준다(BOM 제거).
# Windows PowerShell 5.1 의 [Console]::In 은 SyncTextReader 라 ReadToEndAsync 가 동기로 막힌다.
# 대신 OpenStandardInput 스트림을 CopyToAsync 로 비동기 복사해, 입력이 닫히지 않아도 한도에서 빠져나온다.
function Read-HookStdinText([int]$TimeoutMs = 2000) {
    try {
        if (-not [Console]::IsInputRedirected) { return "" }
        $in = [Console]::OpenStandardInput()
        $ms = New-Object System.IO.MemoryStream
        $t = $in.CopyToAsync($ms)
        if (-not $t.Wait($TimeoutMs)) { return "" }
        return ([System.Text.Encoding]::UTF8.GetString($ms.ToArray())).TrimStart([char]0xFEFF)
    } catch { return "" }
}

# Claude Code 가 훅에 표준 입력으로 주는 JSON(session_id · transcript_path 등). 입력이 없으면(손으로 실행 · 시험) 기다리지 않고 $null.
function Read-HookInput {
    try {
        $text = Read-HookStdinText 2000
        if (-not $text.Trim()) { return $null }
        # 필요한 칸(transcript_path)만 정규식으로 꺼낸다(ConvertFrom-Json 은 PowerShell 5.1 에서 처음 쓸 때 0.2초쯤 든다). JSON 이스케이프는 [regex]::Unescape 로 푼다.
        $m = [regex]::Match($text, '"transcript_path"\s*:\s*"((?:[^"\\]|\\.)*)"')
        $path = if ($m.Success) { [regex]::Unescape($m.Groups[1].Value) } else { "" }
        return [PSCustomObject]@{ transcript_path = $path }
    } catch { return $null }
}

# 컨텍스트가 크면 "이번 작업을 위임하면 agy 제출을 서브에이전트에 맡긴다"는 한 줄. 제출한 뒤에 알면 늦어서, 질문을 보낼 때 미리 알린다.
# 기준: AGY_CTX_SUBAGENT_THRESHOLD > 200k (submit-task.ps1 과 같은 규칙)
function Write-ContextLine([string]$TranscriptPath) {
    try {
        if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath)) { return }
        $lib = Join-Path $PSScriptRoot "claude-transcript.ps1"
        if (-not (Test-Path -LiteralPath $lib)) { return }
        . $lib
        $u = Get-ClaudeTranscriptLastUsage -TranscriptPath $TranscriptPath
        if (-not $u -or -not $u.ctx) { return }
        $threshold = 200000
        if ($env:AGY_CTX_SUBAGENT_THRESHOLD -match '^\d+$') { $threshold = [int]$env:AGY_CTX_SUBAGENT_THRESHOLD }
        if ([long]$u.ctx -le $threshold) { return }
        Write-Output ("[컨텍스트 {0}k] 기준 {1}k 를 넘었다: 이번 작업을 위임하면 samjil-delegate-agy 로 agy 에 제출한다. 제출 · 대기 · diff 검토 · 시험은 서브에이전트 하나(저렴한 모델)가 대신 맡고, 본 세션은 5줄 보고(통과 여부 · 바뀐 파일 · 걱정)만 받는다. agy 로 못 하는 일(DB · VPN · 브라우저 · 메일)만 서브에이전트가 직접 하고, 대화 맥락이 필요한 판단은 본 세션이 한다." -f [int][math]::Round([long]$u.ctx / 1000.0), [int]($threshold / 1000))
    } catch {}
}

# PreToolUse(Agent/Task 도구) 관문: 세션마다 처음 한 번은 deny 로 agy 위임을 알리고, 두 번째부터는 additionalContext 만 붙인다.
function Invoke-PreToolUseGate([string]$InputFilePath) {
    try {
        $mode = if ($env:AGY_AGENT_GATE) { $env:AGY_AGENT_GATE.Trim().ToLowerInvariant() } else { "" }
        if ($mode -eq "off") { return }

        $raw = ""
        if ($InputFilePath) {
            if (-not (Test-Path -LiteralPath $InputFilePath -PathType Leaf)) { return }
            $raw = [System.IO.File]::ReadAllText($InputFilePath, [System.Text.Encoding]::UTF8)
        } else {
            $raw = Read-HookStdinText 2000
        }
        $raw = $raw.TrimStart([char]0xFEFF).Trim()
        if (-not $raw) { return }

        $j = $null
        try { $j = $raw | ConvertFrom-Json } catch { return }
        if (-not $j) { return }

        $tool = if ($j.PSObject.Properties["tool_name"]) { [string]$j.tool_name } else { "" }
        if ($tool -ne "Agent" -and $tool -ne "Task") { return }

        $ti = if ($j.PSObject.Properties["tool_input"]) { $j.tool_input } else { $null }
        $sub = if ($ti -and $ti.PSObject.Properties["subagent_type"]) { ([string]$ti.subagent_type).Trim() } else { "" }
        $roSet = @("explore", "plan", "claude-code-guide", "web-fetch", "statusline-setup")
        if ($sub -and (($roSet -contains $sub.ToLowerInvariant()) -or ($sub -match '(?i)explor|review|analyz|guide'))) { return }

        $prompt = if ($ti -and $ti.PSObject.Properties["prompt"]) { [string]$ti.prompt } else { "" }
        $desc = if ($ti -and $ti.PSObject.Properties["description"]) { [string]$ti.description } else { "" }
        $passRe = '(?i)submit-task|samjil-delegate-agy|\bagy\b'
        if (($prompt -match $passRe) -or ($desc -match $passRe)) { return }

        $denyMsg = "[samjil-delegate-agy] Agent 도구 관문(세션마다 처음 한 번): 코드 · 문서 · 설정 파일 · xlsx/pptx 를 고치거나 만드는 일은 samjil-delegate-agy 규칙상 agy 위임이 먼저다. agy 대상이면 samjil-delegate-agy 스킬을 불러와 submit-task 로 제출한다(컨텍스트가 크면 서브에이전트에게 agy 제출 · 대기 · 검토를 맡긴다). agy 로 못 하는 일(DB 조회 · VPN · 브라우저 · 메일 · 대화 맥락 판단)이거나 agy 가 실패 · 시간 초과했으면 같은 Agent 호출을 다시 하면 통과한다."
        $noteMsg = "[samjil-delegate-agy] 참고: 파일을 고치거나 만드는 일은 Agent 도구보다 agy 위임(samjil-delegate-agy)이 먼저다. Agent 도구는 agy 로 못 하는 일이거나 agy 가 실패 · 시간 초과했을 때만 쓴다."

        $outObj = $null
        if ($mode -eq "note") {
            $outObj = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = "PreToolUse"; additionalContext = $noteMsg } }
        } else {
            $rawSid = if ($j.PSObject.Properties["session_id"]) { [string]$j.session_id } else { "" }
            $sid = $rawSid -replace '[^A-Za-z0-9_-]', ''
            if (-not $sid) {
                $outObj = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = "PreToolUse"; additionalContext = $noteMsg } }
            } else {
                $dir = if ($env:AGY_AGENT_GATE_DIR) { $env:AGY_AGENT_GATE_DIR } else { Join-Path ([IO.Path]::GetTempPath()) "samjil-agent-gate" }
                $marker = Join-Path $dir $sid
                if (Test-Path -LiteralPath $marker -PathType Leaf) {
                    $outObj = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = "PreToolUse"; additionalContext = $noteMsg } }
                } else {
                    try {
                        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                        $cutoff = (Get-Date).AddDays(-7)
                        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
                            if ($f.LastWriteTime -lt $cutoff) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
                        }
                        [System.IO.File]::WriteAllText($marker, "", (New-Object System.Text.UTF8Encoding($false)))
                    } catch {}
                    $outObj = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = "PreToolUse"; permissionDecision = "deny"; permissionDecisionReason = $denyMsg } }
                }
            }
        }

        $json = $outObj | ConvertTo-Json -Depth 5 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json + "`n")
        $stdout = [Console]::OpenStandardOutput()
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    } catch {}
}

try {
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $EnsureScript) { $EnsureScript = Join-Path $PSScriptRoot "ensure-agy-running.ps1" }
    if ($Event -eq "PreToolUse") {
        Invoke-PreToolUseGate $HookInputPath
        exit 0
    }
    if ($Event -eq "UserPromptSubmit") {
        # 질문마다 도는 길이라 빠르게: [Console]::OutputEncoding 을 바꾸면 0.15초쯤 더 들어서, 줄을 모아 UTF-8 바이트로 표준 출력에 바로 쓴다.
        $hookInput = Read-HookInput
        if (-not $TranscriptPath -and $hookInput -and $hookInput.PSObject.Properties["transcript_path"]) { $TranscriptPath = [string]$hookInput.transcript_path }
        $outLines = New-Object System.Collections.Generic.List[string]
        foreach ($o in @(Write-ContextLine $TranscriptPath)) { if ($o -is [string]) { $outLines.Add($o) } }
        if ($outLines.Count -gt 0) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes((($outLines.ToArray()) -join "`n") + "`n")
            $stdout = [Console]::OpenStandardOutput()
            $stdout.Write($bytes, 0, $bytes.Length)
            $stdout.Flush()
        }
        exit 0
    }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $state = "UNKNOWN"
    if (Test-Path -LiteralPath $EnsureScript) {
        $check = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EnsureScript -RuntimeDir $RuntimeDir -CheckOnly -StaleThresholdSeconds 0 2>$null)
        $word = ((@($check) -join "").Trim())
        if ($word -in @("ALIVE", "DEAD", "MANUAL_STOP")) { $state = $word }
    }

    $watcherLine = switch ($state) {
        "ALIVE"       { "agy 워처: 켜져 있음." }
        "DEAD"        { "agy 워처: 꺼져 있음. 위임하면 submit-task 가 자동으로 켜고, 켜지지 않으면 작업자를 직접 실행한다." }
        "MANUAL_STOP" { "agy 워처: 꺼져 있음. 위임하면 submit-task 가 자동으로 켜고, 켜지지 않으면 작업자를 직접 실행한다." }
        default       { "agy 워처: 상태를 확인하지 못했다(런타임이 설치돼 있지 않을 수 있다). 위임 없이 직접 처리하고 install.ps1 실행을 안내한다." }
    }

    Write-Output "[samjil-delegate-agy] 명세를 정할 수 있는 구현 · 수정 · 시험과 양 많은 단순 작업은 Hydrogen/Neon/Carbon 단계(@model: quick · build · build-hard · feature · feature-carbon · deep, 필요 시 @cmd: goal · swarm · run-workflow · boost · browser · plan)로 위임하고, 맥락이 필요한 일 · 한두 줄 수정은 직접 처리. 매우 복잡한 결정은 Neon(think) 또는 Carbon(think-carbon)과 상의한다(스킬 참고). 코드 · 문서 · 설정 파일 · xlsx/pptx 를 고치거나 만드는 일은 사용자가 위임이라고 말하지 않아도, 직접 시작하거나 Agent 도구로 넘기기 전에 samjil-delegate-agy 스킬을 먼저 불러온다. Agent 도구(Claude 서브에이전트)는 agy 로 못 하는 일(DB 조회 · VPN · 브라우저 · 메일 · 대화 맥락 판단)이거나 agy 가 실패 · 시간 초과했을 때만 쓴다."
    Write-Output $watcherLine

    # 새 버전 안내(캐시만 읽음)와 백그라운드 확인 예약(완료는 기다리지 않고 다음 세션에서 반영)
    try {
        $effectiveInstallRoot = if ($InstallRoot) { $InstallRoot } elseif ($env:SAMJIL_INSTALL_ROOT) { $env:SAMJIL_INSTALL_ROOT } else { Join-Path $home_ ".samjil" }
        $updateLib = Join-Path $PSScriptRoot "update-check.ps1"
        if (Test-Path -LiteralPath $updateLib -PathType Leaf) {
            . $updateLib
            $notice = Get-SamjilUpdateNotice -InstallRoot $effectiveInstallRoot -ForSession
            if ($notice -and $notice.Available) {
                Write-Output ("agy-agent 새 버전 {0} 이 나왔다(설치본 {1}). 이번 답변에서 사용자에게 한 번만 짧게 알리고 업데이트 방법을 안내한다: PowerShell 에서 irm https://raw.githubusercontent.com/samjil/agy-agent/main/install.ps1 | iex, 또는 새 압축 팩의 Install.cmd. 확인을 끄려면 설치 때 -NoUpdateCheck." -f $notice.Latest, $notice.Installed)
                Set-SamjilUpdateNotified -InstallRoot $effectiveInstallRoot -Version $notice.Latest
            }
            if ($env:AGY_TEST_NO_UPDATE_FETCH -ne "1" -and (Test-SamjilUpdateFetchDue -InstallRoot $effectiveInstallRoot)) {
                Start-HookHiddenPowerShell @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $updateLib, "-Fetch", "-InstallRoot", $effectiveInstallRoot)
            }
        }
    } catch {}
} catch {
    # 훅 오류가 세션 시작을 막으면 안 된다.
}
exit 0
