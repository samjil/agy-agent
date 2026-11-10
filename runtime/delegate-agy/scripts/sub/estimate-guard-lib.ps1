# estimate-guard-lib.ps1
# 질문마다 예상(record-estimate)이 반드시 남게 하는 규칙의 본체. estimate-guard.ps1(Claude Code 명령 훅)과 serve-viewer.ps1(PreToolUse HTTP 훅 /api/estimate-guard)이
# 함께 쓴다. 두 곳이 같은 판정을 하도록 한 함수로 모았다.
#   UserPromptSubmit : 새 질문이 들어오면 "예상 미기록" 표시(estimate-pending/<세션>.json)를 남기고 기록 안내를 Claude 에게 준다.
#   PreToolUse       : 표시가 남아 있는 동안 일을 시작하는 도구(Bash · Edit · Write 등)를 막고 기록 명령을 알려 준다. record-estimate 호출은 통과시키고 표시를 지운다.
#                      (Skill · ToolSearch · AskUserQuestion · 읽기 전용 도구 · mcp__ccd_ 화면 도구는 막지 않는다. 예상을 내려면 먼저 스킬을 읽고 살펴봐야 해서)
#   Stop             : 표시가 남은 채 답변을 끝내려 하면 막고 기록하게 한다. 일하는 도중 도착한 질문(queued_command)이 마지막 기록 뒤에 있으면 그것도 막는다.
# 위임 여부를 예상으로 결정하므로 예상이 없는 질문은 통계에 쓸 수 없다. 판정 중 오류가 나면 막지 않고 통과시킨다.

# 결과: @{ Action = 'allow' | 'deny' | 'block' | 'context'; Message = <글자> }
#   deny    : PreToolUse 에서 이 도구 호출을 막는다(Message 는 Claude 에게 보이는 이유)
#   block   : Stop 에서 끝내지 못하게 한다(Message 는 이유)
#   context : UserPromptSubmit 에서 Claude 에게 줄 안내(Message)
function Invoke-EstimateGuard {
    param([string]$EventJson, [string]$RuntimeDir)
    $allow = @{ Action = 'allow'; Message = '' }
    try {
        if (-not $EventJson -or -not $EventJson.Trim()) { return $allow }
        $evt = $EventJson | ConvertFrom-Json
        $evName = [string]$evt.hook_event_name
        if (-not $evName) { return $allow }

        $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
        $pendDir = Join-Path $RuntimeDir "estimate-pending"
        $sid = ([string]$evt.session_id) -replace '[^A-Za-z0-9_-]', ''
        if (-not $sid) { return $allow }
        $flag = Join-Path $pendDir ($sid + ".json")
        $recordScript = Join-Path (Split-Path -Parent $RuntimeDir) "scripts\record-estimate.ps1"

        $howTo = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -Direct <토큰> -Delegate <토큰> -TimeDirect <시간> -TimeDelegate <시간> -Choice direct|delegate -Level low|medium|high -FactorDirect <직접 계수> -FactorDelegate <위임 계수> -Reason "<직접/위임을 고른 이유 한 줄>"' -f $recordScript)
        $why = "위임할지 직접 할지는 예상 토큰으로 정하므로, 예상이 없는 질문은 통계에 쓸 수 없습니다. 세션 시작 안내의 [토큰 예상] · [예상 보정] 식에 호출 수를 넣어 구하세요."

        $flagFresh = {
            param([string]$Path)
            if (-not (Test-Path -LiteralPath $Path)) { return $false }
            # 12시간 넘은 표시는 낡은 것으로 보고 지운다(세션이 기록 없이 끝난 경우)
            $age = (Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime
            if ($age.TotalHours -gt 12) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue; return $false }
            return $true
        }

        # 기록 명령을 통과시킨 뒤(표시에 record_started 가 있다) 그 기록이 실제로 성공했는지: record-estimate 가 성공하면 남기는 _last-record.json 의 시각으로 본다.
        #   ok      : 성공 표시가 있다 -> 표시를 지우고 통과
        #   wait    : 아직 성공 표시가 없지만 기록 명령을 막 통과시켰다(같은 메시지의 다른 도구 호출이 먼저 온 경우) -> 이번만 통과
        #   failed  : 20초가 지나도 성공 표시가 없다(값 형식 오류 등으로 기록이 실패) -> 다시 기록하게 막는다
        #   pending : 기록 명령을 아직 부르지 않았다
        $recordState = {
            param([string]$Path)
            $startedAt = $null
            try {
                $fo = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($fo.PSObject.Properties['record_started'] -and $fo.record_started) { $startedAt = [datetime]::Parse([string]$fo.record_started, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
            } catch {}
            if ($null -eq $startedAt) { return 'pending' }
            $marker = Join-Path $pendDir "_last-record.json"
            if ((Test-Path -LiteralPath $marker) -and (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ge $startedAt.AddSeconds(-2)) { return 'ok' }
            if (((Get-Date).ToUniversalTime() - $startedAt).TotalSeconds -lt 20) { return 'wait' }
            return 'failed'
        }
        $failMsg = "예상 기록 명령이 실패해 예상이 남지 않았습니다(출력의 record-estimate FAILED 를 확인). 값 형식을 고쳐 다시 기록하세요. 토큰은 1.3k, 시간은 14s · 1m30s 형식입니다. "

        switch ($evName) {
            'UserPromptSubmit' {
                $prompt = ([string]$evt.prompt).Trim()
                # 슬래시 명령 · 압축 뒤 자동 이어짐 메시지 · 백그라운드 작업 알림 같은 시스템 메시지는 질문이 아니다
                if (-not $prompt -or $prompt.StartsWith('/') -or $prompt.StartsWith('This session is being continued')) { return $allow }
                foreach ($sysPrefix in @('[SYSTEM NOTIFICATION', '<task-notification', '<system-reminder', '<command-', '<local-command', '<side-sessions-event', '<ci-monitor-event')) {
                    if ($prompt.StartsWith($sysPrefix)) { return $allow }
                }
                if (-not (Test-Path -LiteralPath $pendDir)) { New-Item -ItemType Directory -Force -Path $pendDir | Out-Null }
                if (-not (& $flagFresh $flag)) {
                    $obj = [ordered]@{ prompt_ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); cwd = [string]$evt.cwd }
                    [System.IO.File]::WriteAllText($flag, ($obj | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
                }
                return @{ Action = 'context'; Message = ("[예상 기록 필수] 이 질문을 처리하기 전에 먼저 record-estimate 로 예상을 기록한다(기록 전에는 Bash · Edit · Write 같은 도구가 막힌다). 첫 작업이 Bash 면 그 명령 앞에 붙여 한 번에 실행한다(예: record-estimate … ; git status). 따로 부르면 모델이 한 번 더 돌며 대화 전체를 다시 읽는다. " + $why + " 명령: " + $howTo) }
            }
            'PreToolUse' {
                if (-not (& $flagFresh $flag)) { return $allow }
                $tool = [string]$evt.tool_name
                $isRecordCall = $false
                if ($tool -in @('Bash', 'PowerShell')) {
                    $cmdR = [string]$evt.tool_input.command
                    if ($cmdR -match 'record-estimate\.ps1' -and $cmdR -match '-Choice') { $isRecordCall = $true }
                }
                if ($isRecordCall) {
                    # 기록 명령은 통과시키되 표시는 아직 지우지 않는다. 기록이 실제로 성공했는지는 다음 도구 호출 · 답변 끝에서 확인한다
                    try {
                        $prevTs = ""
                        try { $prevTs = [string]([System.IO.File]::ReadAllText($flag, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).prompt_ts } catch {}
                        $objR = [ordered]@{ prompt_ts = $prevTs; cwd = [string]$evt.cwd; record_started = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
                        [System.IO.File]::WriteAllText($flag, ($objR | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
                    } catch {}
                    return $allow
                }
                $stR = & $recordState $flag
                if ($stR -eq 'ok') { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue; return $allow }
                if ($stR -eq 'wait') { return $allow }
                if ($tool -in @('Skill', 'ToolSearch', 'AskUserQuestion', 'Read', 'Grep', 'Glob', 'LSP', 'NotebookRead', 'TodoWrite') -or $tool.StartsWith('mcp__ccd_')) { return $allow }
                if ($stR -eq 'failed') { return @{ Action = 'deny'; Message = ($failMsg + "명령: " + $howTo) } }
                return @{ Action = 'deny'; Message = ("[예상 기록 필수] 이 질문의 예상을 먼저 기록해야 일을 시작할 수 있습니다. 첫 작업이 Bash 면 그 명령 앞에 붙여 한 번에 실행한다(예: record-estimate … ; git status). 따로 부르면 모델이 한 번 더 돌며 대화 전체를 다시 읽는다. " + $why + " 명령: " + $howTo) }
            }
            'Stop' {
                if ($evt.stop_hook_active) { return $allow }
                if (& $flagFresh $flag) {
                    $stS = & $recordState $flag
                    if ($stS -eq 'failed') { return @{ Action = 'block'; Message = ($failMsg + "명령: " + $howTo) } }
                }
                if ((& $flagFresh $flag) -and ((& $recordState $flag) -in @('ok', 'wait'))) {
                    Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
                } elseif (& $flagFresh $flag) {
                    return @{ Action = 'block'; Message = ("이 질문의 예상을 기록하지 않았습니다. 지금 record-estimate 로 기록한 뒤 끝내세요. " + $why + " 명령: " + $howTo) }
                }
                # 일하는 도중 도착한 질문이 마지막 기록 뒤에 있으면(질문마다 기록해야 한다) 알린다
                $tp = [string]$evt.transcript_path
                if ($tp -and (Test-Path -LiteralPath $tp)) {
                    $fsT = [System.IO.File]::Open($tp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $len = $fsT.Length
                        $take = [int][Math]::Min($len, 6MB)
                        [void]$fsT.Seek($len - $take, [System.IO.SeekOrigin]::Begin)
                        $buf = New-Object byte[] $take
                        [void]$fsT.Read($buf, 0, $take)
                    } finally { $fsT.Dispose() }
                    $text = [System.Text.Encoding]::UTF8.GetString($buf)
                    $arrivals = 0
                    $sawAnchor = $false
                    foreach ($ln in ($text -split "`n")) {
                        if ($ln.Contains('"queued_command"') -and $ln -match '"origin"\s*:\s*\{\s*"kind"\s*:\s*"human"') { if ($sawAnchor) { $arrivals++ } }
                        elseif ($ln.Contains('"toolu_') -and $ln -match 'record-estimate\.ps1' -and $ln -match '-Choice') { $sawAnchor = $true; $arrivals = 0 }
                    }
                    if ($sawAnchor -and $arrivals -gt 0) {
                        return @{ Action = 'block'; Message = (("작업 도중 도착한 질문 {0}건의 예상이 기록되지 않았습니다. 질문마다 record-estimate 로 기록하세요(앞 질문 일로 돌아왔다면 -Switch <질문 번호> 도 남긴다). " -f $arrivals) + $why + " 명령: " + $howTo) }
                    }
                }
                return $allow
            }
            default { return $allow }
        }
    } catch {
        return $allow
    }
}
