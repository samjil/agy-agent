# session-start-hook.ps1
# Claude Code SessionStart 훅: 새 세션이 시작될 때 agy 워처를 창 없이 켜고,
# Claude 에게 samjil-delegate-agy 스킬의 위임 규칙 한 줄과 워처 상태를 알립니다(표준 출력이 세션 문맥이 됩니다).
#   - 워처가 이미 켜져 있으면 아무것도 켜지 않습니다.
#   - 사용자가 stop-agy 로 일부러 끈 상태(manual_stop.flag)면 켜지 않습니다.
#   - 켜는 일은 기다리지 않고 CREATE_NO_WINDOW 무창 분리 실행으로 백그라운드에 맡겨, 세션 시작을 늦추거나 창을 깜빡이지 않습니다.
# 어떤 경우에도 오류로 세션 시작을 막지 않도록 항상 종료 코드 0 으로 끝납니다.
# -Event UserPromptSubmit: 질문을 보낼 때마다, 컨텍스트가 기준을 넘었으면 "위임하면 처음부터 서브에이전트에" 한 줄만 출력한다
#   (표준 입력 JSON 의 transcript_path 로 크기를 읽는다). Node 가 있으면 같은 일을 하는 prompt-hook.js 가 대신 등록된다.
param(
    [string]$RuntimeDir = "",
    [string]$EnsureScript = "",
    [string]$Event = "SessionStart",
    [string]$TranscriptPath = ""      # 시험용. 없으면 Claude Code 가 표준 입력으로 주는 JSON 의 transcript_path 를 쓴다
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

# Claude Code 가 훅에 표준 입력으로 주는 JSON(session_id · transcript_path 등). 입력이 없으면(손으로 실행 · 시험) 기다리지 않고 $null.
function Read-HookInput {
    try {
        if (-not [Console]::IsInputRedirected) { return $null }
        $task = [Console]::In.ReadToEndAsync()
        if (-not $task.Wait(2000)) { return $null }
        $text = [string]$task.Result
        if (-not $text.Trim()) { return $null }
        # 필요한 칸(transcript_path)만 정규식으로 꺼낸다(ConvertFrom-Json 은 PowerShell 5.1 에서 처음 쓸 때 0.2초쯤 든다). JSON 이스케이프는 [regex]::Unescape 로 푼다.
        $m = [regex]::Match($text, '"transcript_path"\s*:\s*"((?:[^"\\]|\\.)*)"')
        $path = if ($m.Success) { [regex]::Unescape($m.Groups[1].Value) } else { "" }
        return [PSCustomObject]@{ transcript_path = $path }
    } catch { return $null }
}

# 컨텍스트가 크면 "이번 질문에서 위임하면 처음부터 서브에이전트에 맡긴다"는 한 줄. 제출한 뒤에 알면 늦어서, 질문을 보낼 때 미리 알린다.
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
        Write-Output ("[컨텍스트 {0}k] 기준 {1}k 를 넘었다: 이번 질문에서 위임하게 되면 처음부터 서브에이전트 하나(저렴한 모델)에 브리프를 넘겨 제출 · 대기 · diff 검토 · 시험까지 맡기고, 본 세션은 5줄 보고(통과 여부 · 바뀐 파일 · 걱정)만 받는다." -f [int][math]::Round([long]$u.ctx / 1000.0), [int]($threshold / 1000))
    } catch {}
}

try {
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $EnsureScript) { $EnsureScript = Join-Path $PSScriptRoot "ensure-agy-running.ps1" }
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
        "DEAD" {
            Start-HookHiddenPowerShell @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $EnsureScript, "-RuntimeDir", $RuntimeDir, "-ConfirmDelaySeconds", "0", "-StaleThresholdSeconds", "0")
            "agy 워처: 꺼져 있어 세션 시작 훅이 창 없이 켜는 중. 위임 직전에 ensure-agy-running.ps1 -CheckOnly 로 ALIVE 인지 다시 본다."
        }
        "MANUAL_STOP" { "agy 워처: 사용자가 일부러 꺼 둔 상태라 켜지 않았다. 위임하려면 켜도 되는지 먼저 묻는다." }
        default       { "agy 워처: 상태를 확인하지 못했다(런타임이 설치돼 있지 않을 수 있다). 위임 없이 직접 처리하고 install.ps1 실행을 안내한다." }
    }

    Write-Output "[samjil-delegate-agy] 명세를 정할 수 있는 구현 · 수정 · 시험과 양 많은 단순 작업은 Hydrogen/Neon/Argon 단계(@model: quick · build · build-hard · feature · feature-argon · deep, 필요 시 @cmd: goal · swarm · run-workflow · boost · browser · plan)로 위임하고, 맥락이 필요한 일 · 한두 줄 수정은 직접 처리. 매우 복잡한 결정은 Neon(think) 또는 Argon(think-argon)과 상의한다(스킬 참고)."
    Write-Output $watcherLine
} catch {
    # 훅 오류가 세션 시작을 막으면 안 된다.
}
exit 0
