# session-start-hook.ps1
# Claude Code SessionStart 훅: 새 세션이 시작될 때 agy 워처를 창 없이 켜고,
# Claude 에게 samjil-delegate-agy 스킬의 위임 규칙 한 줄과 워처 상태를 알립니다(표준 출력이 세션 문맥이 됩니다).
#   - 워처가 이미 켜져 있으면 아무것도 켜지 않습니다.
#   - 사용자가 stop-agy 로 일부러 끈 상태(manual_stop.flag)면 켜지 않습니다.
#   - 켜는 일은 기다리지 않고 백그라운드로 맡겨, 세션 시작을 늦추지 않습니다.
# 어떤 경우에도 오류로 세션 시작을 막지 않도록 항상 종료 코드 0 으로 끝납니다.
# -Event UserPromptSubmit: 질문을 보낼 때마다 한도 균형 한 줄(quota-balance.ps1, 계산해 둔 파일만 읽는다)만 출력한다.
#   agy 한도 파일이 없거나 10분이 넘었으면 창 없이 새로 고침만 시작하고 기다리지 않는다(질문을 늦추지 않는다).
param(
    [string]$RuntimeDir = "",
    [string]$EnsureScript = "",
    [string]$Event = "SessionStart",
    [string]$QuotaScript = ""
)

# 한도 균형 두 줄(모드 줄 + 할 일). agy 한도 파일이 오래됐으면 백그라운드 새로 고침을 시작한다. 실패하면 아무것도 출력하지 않는다.
function Write-QuotaBalanceLines([string]$RuntimeDir, [string]$QuotaScript) {
    try {
        if (-not $QuotaScript) { $QuotaScript = Join-Path $PSScriptRoot "quota-balance.ps1" }
        if (-not (Test-Path -LiteralPath $QuotaScript)) { return }
        $agyFile = Join-Path $RuntimeDir "agy-quota.json"
        $stale = $true
        if (Test-Path -LiteralPath $agyFile) { $stale = (((Get-Date) - (Get-Item -LiteralPath $agyFile).LastWriteTime).TotalMinutes -gt 10) }
        if ($stale -and -not $env:AGY_QUOTA_NO_REFRESH) {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$QuotaScript`"", "-RuntimeDir", "`"$RuntimeDir`"", "-RefreshAgy", "-Quiet") | Out-Null
        }
        if (-not (Test-Path -LiteralPath $agyFile)) { return }
        # quota-balance.ps1 을 dot-source 하면 그 param(-RuntimeDir 등)이 여기의 같은 이름 변수를 빈 값으로 덮어쓰므로 미리 다른 이름에 담아 둔다
        $hookRuntimeDir = $RuntimeDir
        . $QuotaScript
        $b = Get-QuotaBalance -RuntimeDir $hookRuntimeDir
        if ($b -and $b.Line) { Write-Output $b.Line; if ($b.Advice) { Write-Output $b.Advice } }
    } catch {}
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $EnsureScript) { $EnsureScript = Join-Path $PSScriptRoot "ensure-agy-running.ps1" }
    if ($Event -eq "UserPromptSubmit") {
        Write-QuotaBalanceLines $RuntimeDir $QuotaScript
        exit 0
    }

    $state = "UNKNOWN"
    if (Test-Path -LiteralPath $EnsureScript) {
        $check = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EnsureScript -RuntimeDir $RuntimeDir -CheckOnly -StaleThresholdSeconds 0 2>$null)
        $word = ((@($check) -join "").Trim())
        if ($word -in @("ALIVE", "DEAD", "MANUAL_STOP")) { $state = $word }
    }

    $watcherLine = switch ($state) {
        "ALIVE"       { "agy 워처: 켜져 있음." }
        "DEAD" {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$EnsureScript`"",
                "-RuntimeDir", "`"$RuntimeDir`"", "-ConfirmDelaySeconds", "0", "-StaleThresholdSeconds", "0") | Out-Null
            "agy 워처: 꺼져 있어 세션 시작 훅이 창 없이 켜는 중. 위임 직전에 ensure-agy-running.ps1 -CheckOnly 로 ALIVE 인지 다시 본다."
        }
        "MANUAL_STOP" { "agy 워처: 사용자가 일부러 꺼 둔 상태라 켜지 않았다. 위임하려면 켜도 되는지 먼저 묻는다." }
        default       { "agy 워처: 상태를 확인하지 못했다(런타임이 설치돼 있지 않을 수 있다). 위임 없이 직접 처리하고 install.ps1 실행을 안내한다." }
    }

    Write-Output "[samjil-delegate-agy] 명세를 정할 수 있는 구현 · 수정 · 시험과 양 많은 단순 작업은 Hydrogen 단계(@model: quick · build · build-hard · deep)로 위임하고, 맥락이 필요한 일 · 한두 줄 수정은 직접 처리. 매우 복잡한 결정은 Argon(think)과 상의한다(스킬 참고)."
    Write-Output $watcherLine
    Write-QuotaBalanceLines $RuntimeDir $QuotaScript
} catch {
    # 훅 오류가 세션 시작을 막으면 안 된다.
}
exit 0
