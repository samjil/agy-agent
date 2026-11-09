# 위임 기록 DB(delegate-agy\data\delegate.db)의 사용량을 CSV 로 내보낸다. 평소에는 CSV 를 쓰지 않고, 필요할 때만 이 스크립트로 만든다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\export-usage-csv.ps1                          # 작업별 사용량 -> .\usage-export-<시각>.csv
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\export-usage-csv.ps1 -Summary                 # 모델별 집계   -> .\usage-summary-<시각>.csv
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\export-usage-csv.ps1 -Since 2026-10-01 -Out D:\x\usage.csv
# 워처가 실제 agy CLI 를 부른 작업(source 칸이 빈 행)만 센다. log-qa.ps1 이 남긴 MCP·bridge 기록(source 가 있는 행)은 토큰 칸이 비어
# 집계를 왜곡하므로 뺀다(예전 usage.csv 도 워처가 쓴 행만 담았다).

param(
    [string]$RuntimeDir = "",
    [string]$Since = "",
    [string]$Out = "",
    [switch]$Summary
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if (-not $RuntimeDir) {
    $RuntimeDir = if ($env:AGY_DELEGATE_RUNTIME) { $env:AGY_DELEGATE_RUNTIME } else { Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime" }
}
. (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime\delegate-agy\scripts\sub\agy-layout.ps1")
$dbPath = (Get-AgyLayout $RuntimeDir).DbPath
# 아직 새 배치로 옮기기 전인 옛 위치(logs\agy.db)에 있으면 그것을 쓴다.
$legacyDb = Join-Path (Join-Path $RuntimeDir "logs") "agy.db"
if (-not (Test-Path -LiteralPath $dbPath) -and (Test-Path -LiteralPath $legacyDb)) { $dbPath = $legacyDb }
if (-not (Test-Path -LiteralPath $dbPath)) { Write-Host "[x] 위임 기록 DB 가 없습니다: $dbPath" -ForegroundColor Red; exit 1 }

$repoRoot = Split-Path $PSScriptRoot -Parent
$module = @((Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1"), (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\agy-db.ps1")) |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $module) { Write-Host "[x] agy-db.ps1 을 찾지 못했습니다." -ForegroundColor Red; exit 1 }
. $module

$cols = @('timestamp', 'computer_name', 'task_id', 'model', 'attempts', 'tried_models', 'input_tokens', 'output_tokens', 'thinking_tokens', 'total_tokens', 'elapsed_sec', 'status', 'session', 'session_id')
$sql = "SELECT " + ($cols -join ',') + " FROM tasks WHERE (source IS NULL OR source = '')"
$bind = @()
if ($Since) {
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParse($Since, [ref]$d)) { Write-Host "[x] -Since 는 yyyy-MM-dd 모양이어야 합니다: $Since" -ForegroundColor Red; exit 1 }
    $sql += " AND timestamp >= ?"
    $bind += $d.ToString('yyyy-MM-dd HH:mm:ss')
}
$sql += " ORDER BY timestamp"
$db = Open-AgyDb $dbPath
try { $dbRows = $db.Query($sql, [object[]]$bind) } finally { $db.Dispose() }

$rows = @(foreach ($r in $dbRows) {
    $o = [ordered]@{}
    foreach ($c in $cols) { $o[$c] = $(if ($null -eq $r[$c]) { '' } else { [string]$r[$c] }) }
    [pscustomobject]$o
})

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ($Summary) {
    if (-not $Out) { $Out = Join-Path (Get-Location) "usage-summary-$stamp.csv" }
    $groups = @($rows | Group-Object { if ($_.model) { $_.model } else { "(모델 미확정/실패)" } })
    $summaryRows = foreach ($g in $groups) {
        # 참고: Windows PowerShell 5.1에서는 Where-Object 결과가 1건뿐이면 배열이 아니라 단일 객체로 풀려서
        # .Count 가 없어지므로 @(...)로 감싸 항상 배열이 되게 한다.
        $okRows  = @($g.Group | Where-Object { $_.status -eq 'OK' })
        $errRows = @($g.Group | Where-Object { $_.status -eq 'ERROR' })
        $inSum    = ($okRows | Where-Object { $_.input_tokens }    | Measure-Object -Property input_tokens    -Sum).Sum
        $outSum   = ($okRows | Where-Object { $_.output_tokens }   | Measure-Object -Property output_tokens   -Sum).Sum
        $thinkSum = ($okRows | Where-Object { $_.thinking_tokens } | Measure-Object -Property thinking_tokens -Sum).Sum
        $totSum   = ($okRows | Where-Object { $_.total_tokens }    | Measure-Object -Property total_tokens    -Sum).Sum
        $elapsedVals = $okRows | Where-Object { $_.elapsed_sec } | ForEach-Object { [double]$_.elapsed_sec }
        $avgElapsed  = if ($elapsedVals) { [math]::Round((($elapsedVals | Measure-Object -Average).Average), 1) } else { $null }
        $lastUsed = ($g.Group | Sort-Object timestamp -Descending | Select-Object -First 1).timestamp
        [PSCustomObject]@{
            model                 = $g.Name
            tasks_ok              = $okRows.Count
            tasks_error           = $errRows.Count
            total_input_tokens    = $inSum
            total_output_tokens   = $outSum
            total_thinking_tokens = $thinkSum
            total_tokens          = $totSum
            avg_elapsed_sec       = $avgElapsed
            last_used_at          = $lastUsed
        }
    }
    @($summaryRows) | Sort-Object -Property total_tokens -Descending | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8 -Force
    Write-Host ("모델별 집계 {0}개를 저장했습니다: {1}" -f @($summaryRows).Count, $Out)
} else {
    if (-not $Out) { $Out = Join-Path (Get-Location) "usage-export-$stamp.csv" }
    $rows | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8 -Force
    Write-Host ("작업별 사용량 {0}건을 저장했습니다: {1}" -f $rows.Count, $Out)
}
