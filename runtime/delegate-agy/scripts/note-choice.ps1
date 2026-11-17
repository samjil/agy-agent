# note-choice.ps1
# Claude 가 "이 질문을 왜 직접 처리했는지"(사유) 한 줄을 남기는 가벼운 도구입니다. 뷰어의 실측 통계(#/stats)가 이 기록을 질문에 붙여 보입니다.
#
# 쓰는 법: 그 질문의 첫 셸 명령 앞에 붙여 한 번에 실행한다(따로 부르지 않는다. 호출 하나가 대화 전체를 다시 읽는다).
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/note-choice.ps1" -Mode direct -Reason "두 줄 수정" ; <원래 명령>
#
# 동작: 세션 ID(CLAUDE_CODE_SESSION_ID) · UTC 시각 · 방식 · 사유(200자까지)를 위임 DB 의 usage_notes 에 한 행 넣고 "noted" 한 줄을 찍는다.
#   어떤 경우에도 종료 코드는 0 이다(뒤에 붙은 명령을 막지 않는다). 못 남겼으면 "note-choice: <이유>" 한 줄만 찍는다.
#   위임의 사유는 여기가 아니라 브리프의 "@reason: <한 줄>" 로 남긴다(submit-task.ps1).
# 테스트: tests\delegate-agy\note-choice.tests.ps1

param(
    [string]$Mode = "direct",
    [string]$Reason = "",
    [string]$Session = "",
    [string]$RuntimeDir = ""
)

try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try { [Console]::OutputEncoding = $utf8 } catch {}
    if (-not $Session) { $Session = [string]$env:CLAUDE_CODE_SESSION_ID }
    $Session = ($Session -replace '[^A-Za-z0-9_-]', '')
    if (-not $Session) { Write-Output "note-choice: 세션 ID 가 없어 남기지 않았습니다."; exit 0 }
    $modeText = ([string]$Mode).Trim().ToLowerInvariant()
    if (@('direct', 'delegate') -notcontains $modeText) { Write-Output "note-choice: -Mode 는 direct 또는 delegate 입니다."; exit 0 }
    $reasonText = (([string]$Reason) -replace '\s+', ' ').Trim()
    if (-not $reasonText) { Write-Output "note-choice: 사유가 비어 남기지 않았습니다."; exit 0 }
    if ($reasonText.Length -gt 200) { $reasonText = $reasonText.Substring(0, 200) }

    . (Join-Path $PSScriptRoot "sub\agy-layout.ps1")
    if (-not $RuntimeDir) {
        if ($env:AGY_DELEGATE_RUNTIME) { $RuntimeDir = $env:AGY_DELEGATE_RUNTIME }
        else { $RuntimeDir = Join-Path (Split-Path $PSScriptRoot -Parent) "runtime" }
    }
    $dbPath = (Get-AgyLayout $RuntimeDir).DbPath
    . (Join-Path $PSScriptRoot "sub\agy-db.ps1")
    $db = Open-AgyDb $dbPath 3000
    try {
        [void]$db.Execute("INSERT INTO usage_notes (session, noted_at, mode, reason) VALUES (?, ?, ?, ?)",
            [object[]]@($Session, [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"), $modeText, $reasonText))
    } finally { $db.Dispose() }
    Write-Output "noted"
} catch {
    Write-Output ("note-choice: 남기지 못했습니다(" + (([string]$_.Exception.Message) -replace '\s+', ' ') + ")")
}
exit 0
