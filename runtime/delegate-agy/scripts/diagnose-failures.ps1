# diagnose-failures.ps1
# WP-Doctor CLI: 최근 위임 실패·취소를 자동 분류해 DB 에 기록하고, 미처리 원인 요약·처리 표시(-Ack)·자가 개선 브리프를 제공합니다.
#
# 사용법:
#   diagnose-failures.ps1 [-Days 14] [-Limit 200] [-Json] [-FixBrief] [-OutBriefPath <경로>]
#   diagnose-failures.ps1 -Ack -Category quota_exhausted -Note "폴백 건너뛰기 수정"
#   diagnose-failures.ps1 -Ack -TaskId claude_1000000000_1 -Note "브리프 수정 완료"
#   diagnose-failures.ps1 -Ack -All -Note "일괄 확인"

param(
    [string]$DbPath = '',
    [int]$Days = 14,
    [int]$Limit = 200,
    [switch]$Json,
    [switch]$FixBrief,
    [string]$OutBriefPath = '',
    [switch]$Ack,
    [string[]]$TaskId = @(),
    [string[]]$Category = @(),
    [switch]$All,
    [string]$Note = '',
    [ValidateSet('resolved', 'failed', 'open')]
    [string]$Status = 'resolved'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if (-not $DbPath) {
    if ($env:AGY_DELEGATE_DB) {
        $DbPath = $env:AGY_DELEGATE_DB
    } else {
        $DbPath = Join-Path $env:USERPROFILE '.samjil\delegate-agy\data\delegate.db'
    }
}

. (Join-Path $PSScriptRoot 'sub\agy-db.ps1')
. (Join-Path $PSScriptRoot 'sub\agy-failure-doctor.ps1')

try { [void](Update-AgyFailureRecords -DbPath $DbPath) } catch {}

if ($Ack) {
    $ackedCount = Set-AgyFailureAck -DbPath $DbPath -TaskId $TaskId -Category $Category -All:$All -Note $Note -Status $Status
    Write-Output ("처리 표시: {0}건" -f $ackedCount)
    exit 0
}

$diag = Invoke-AgyFailureDiagnostics -DbPath $DbPath -Days $Days -Limit $Limit

if ($OutBriefPath) {
    $outParent = Split-Path -Path $OutBriefPath -Parent
    if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
        New-Item -ItemType Directory -Force -Path $outParent | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutBriefPath, [string]$diag.fix_brief, $utf8NoBom)
}

if ($Json) {
    $diag | ConvertTo-Json -Depth 6
    exit 0
}

if ($FixBrief) {
    Write-Output ([string]$diag.fix_brief)
    exit 0
}

$unackedTotal = if ($null -ne $diag.unacked_total) { [int]$diag.unacked_total } else { 0 }
$unackedCats = @($diag.unacked_by_category)
Write-Host ("[처리 안 한 실패 원인] {0}건" -f $unackedTotal) -ForegroundColor Magenta
foreach ($uc in $unackedCats) {
    $uIds = (@($uc.task_ids) | Select-Object -First 3) -join ', '
    Write-Host ("- {0} ({1}): {2}건 · 최근 {3}" -f $uc.label, $uc.category, $uc.count, $uc.latest_at)
    if ($uc.recommendation) { Write-Host ("    조치: {0}" -f $uc.recommendation) }
    if ($uIds) { Write-Host ("    작업 ID: {0}" -f $uIds) }
}
Write-Host ""

Write-Host ("=== WP-Doctor 위임 실패 진단 (최근 {0}일, DB: {1}) ===" -f $diag.days, $DbPath) -ForegroundColor Cyan
Write-Host ("총 실패/취소/차단: {0}건 (ERROR={1}, CANCELLED={2}, BLOCKED={3})" -f $diag.total_failed, $diag.counts_by_status.ERROR, $diag.counts_by_status.CANCELLED, $diag.counts_by_status.BLOCKED)
Write-Host ""

$cats = @($diag.by_category)
if ($cats.Count -eq 0) {
    Write-Host "실패/취소/차단된 위임 기록이 없습니다." -ForegroundColor Green
    exit 0
}

Write-Host "[카테고리별 집계]" -ForegroundColor Yellow
foreach ($c in $cats) {
    $ids = @($c.sample_ids) -join ', '
    Write-Host ("- {0} ({1}, {2}): {3}건" -f $c.label, $c.category, $c.severity, $c.count)
    Write-Host ("    원인: {0}" -f $c.root_cause)
    Write-Host ("    조치: {0}" -f $c.recommendation)
    if ($ids) { Write-Host ("    예시: {0}" -f $ids) }
}
