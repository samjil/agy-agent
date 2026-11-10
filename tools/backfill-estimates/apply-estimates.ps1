# apply-estimates.ps1
# run-agy-batches.ps1 가 받은 질문별 "호출 수 · 난이도" 어림을 토큰 · 시간 예상으로 바꿔 token_estimates 에 kind='backfill' 로 넣는다.
# 식은 지금 쓰는 예상 식(calibration.json 의 직접 · 위임 a, b 와 시간 식, agy 수준별 중앙값)을 그대로 쓴다:
#   직접 토큰 = a + b × direct_calls,  위임 토큰 = a + b × delegate_calls
#   직접 시간 = a_s + b_s × direct_calls,  위임 시간 = 15초 × delegate_calls + agy 중앙값(수준별)
# 보정 계수는 곱하지 않았으므로 계수 1.0 으로 기록한다(통계가 보정 전 값으로 다음 계수를 계산한다). 이미 예상이 붙은 질문은 건드리지 않는다.
# 수집기(token-stats.ps1 -Update)가 이 기록을 각 질문 행에 붙인다(est_kind = backfill).
#   powershell -File apply-estimates.ps1 -RowsPath rows.json -OutDir out [-DbPath ...] [-CalibrationPath ...] [-WhatIf]
param(
    [Parameter(Mandatory = $true)][string]$RowsPath,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$DbPath = "",
    [string]$CalibrationPath = "",
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$dataDir = Join-Path $home_ ".samjil\delegate-agy\data"
if (-not $DbPath) { $DbPath = Join-Path $dataDir "delegate.db" }
if (-not $CalibrationPath) { $CalibrationPath = Join-Path $dataDir "calibration.json" }
. (Join-Path $home_ ".samjil\delegate-agy\scripts\sub\agy-db.ps1")

function Read-JsonArray([string]$Path) {
    $v = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $a = @($v)
    if ($a.Count -eq 1 -and $a[0] -is [System.Array]) { $a = @($a[0]) }
    return $a
}

$cal = [System.IO.File]::ReadAllText($CalibrationPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
$dirA = [double]$cal.direct.a; $dirB = [double]$cal.direct.b
$delA = [double]$cal.delegate.a; $delB = [double]$cal.delegate.b
$tA = [double]$cal.time.direct.a_s; $tB = [double]$cal.time.direct.b_s
$agyMed = @{ low = [double]$cal.time.agy_median_s.low; medium = [double]$cal.time.agy_median_s.medium; high = [double]$cal.time.agy_median_s.high }
Write-Host ("식: 직접 {0}+{1}×호출 · 위임 {2}+{3}×호출 · 시간 직접 {4}+{5}×호출 · agy 중앙값 {6}/{7}/{8}초" -f $dirA, $dirB, $delA, $delB, $tA, $tB, $agyMed.low, $agyMed.medium, $agyMed.high)

$rows = @{}
foreach ($r in (Read-JsonArray $RowsPath)) { $rows[[int]$r.id] = $r }

$results = @{}
$bad = 0
foreach ($f in @(Get-ChildItem -LiteralPath $OutDir -Filter "b*.out.txt")) {
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($text, '\{[^{}]*\}')) {
        try {
            $o = $m.Value | ConvertFrom-Json
            if ($null -eq $o.id -or $null -eq $o.direct_calls -or $null -eq $o.delegate_calls) { $bad++; continue }
            $lv = ([string]$o.level).ToLowerInvariant()
            if (-not $agyMed.ContainsKey($lv)) { $lv = "medium" }
            $results[[int]$o.id] = @{ dc = [Math]::Max(0, [int]$o.direct_calls); gc = [Math]::Max(0, [int]$o.delegate_calls); level = $lv }
        } catch { $bad++ }
    }
}
Write-Host ("받은 어림 {0}건(읽지 못한 {1}건), 대상 행 {2}건" -f $results.Count, $bad, $rows.Count)

$db = Open-AgyDb $DbPath
$cnt = @{ ins = 0; skip = 0 }   # 트랜잭션 블록 안에서 바꿔야 해서 해시 표에 센다
try {
    Invoke-AgyDbTransaction $db {
        foreach ($id in ($results.Keys | Sort-Object)) {
            if (-not $rows.ContainsKey($id)) { continue }
            $r = $rows[$id]; $x = $results[$id]
            $have = @($db.Query("SELECT 1 AS x FROM token_turns WHERE file = ? AND turn_ts = ? AND (est_direct IS NOT NULL OR est_delegate IS NOT NULL)", [object[]]@([string]$r.file, [string]$r.turn_ts)))
            if ($have.Count -gt 0) { $cnt.skip++; continue }
            $estD = [int][Math]::Round($dirA + $dirB * $x.dc)
            $estG = [int][Math]::Round($delA + $delB * $x.gc)
            $tD = [int][Math]::Round($tA + $tB * $x.dc)
            $tG = [int][Math]::Round(15.0 * $x.gc + $agyMed[$x.level])
            $choice = if ([string]$r.path -eq "delegate") { "delegate" } else { "direct" }
            if ($WhatIf) { $cnt.ins++; continue }
            [void]$db.Execute("DELETE FROM token_estimates WHERE kind = 'backfill' AND project = ? AND recorded_at = ?", [object[]]@([string]$r.project, [string]$r.turn_ts))
            [void]$db.Execute("INSERT INTO token_estimates (recorded_at, project, est_direct, est_delegate, est_time_direct, est_time_delegate, choice, level, factor_direct, factor_delegate, kind) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                [object[]]@([string]$r.turn_ts, [string]$r.project, [double]$estD, [double]$estG, [long]$tD, [long]$tG, $choice, $x.level, 1.0, 1.0, "backfill"))
            $cnt.ins++
        }
    }
} finally { $db.Dispose() }
Write-Host ("기록 {0}건, 이미 예상이 있어 건너뜀 {1}건{2}" -f $cnt.ins, $cnt.skip, $(if ($WhatIf) { " (WhatIf: 실제로는 쓰지 않음)" } else { "" }))
