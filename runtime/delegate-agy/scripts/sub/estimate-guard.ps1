# estimate-guard.ps1
# 질문마다 예상(record-estimate)이 반드시 남게 하는 Claude Code 명령 훅. stdin 의 hook_event_name 으로 UserPromptSubmit · PreToolUse · Stop 을 구분한다.
# 규칙의 본체는 estimate-guard-lib.ps1 이다(뷰어의 PreToolUse HTTP 훅과 같은 판정을 쓴다).
# 훅이 어떤 이유로든 실패하면 세션을 막지 않고 조용히 통과시킨다(항상 exit 0, 막을 때만 PreToolUse 는 exit 2, Stop 은 decision block).
# 등록: register-estimate-guard.ps1 (install.ps1 이 부른다).
param(
    [string]$RuntimeDir = ""
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
    . (Join-Path $PSScriptRoot "estimate-guard-lib.ps1")
    $raw = [Console]::In.ReadToEnd()
    $r = Invoke-EstimateGuard -EventJson $raw -RuntimeDir $RuntimeDir
    switch ($r.Action) {
        'context' {
            $out = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = "UserPromptSubmit"; additionalContext = [string]$r.Message } }
            Write-Output ($out | ConvertTo-Json -Compress -Depth 5)
        }
        'deny' {
            [Console]::Error.WriteLine([string]$r.Message)
            exit 2
        }
        'block' {
            Write-Output (([ordered]@{ decision = "block"; reason = [string]$r.Message }) | ConvertTo-Json -Compress)
        }
    }
    exit 0
} catch {
    exit 0
}
