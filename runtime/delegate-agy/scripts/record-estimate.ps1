# record-estimate.ps1
# 직접 할지 위임할지 정하는 순간의 예상을 DB(token_estimates)에 남긴다. Claude 가 결정 직후 한 턴에 한 번 부른다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File record-estimate.ps1 -Direct 1.3k -Delegate 5.0k -TimeDirect 14s -TimeDelegate 1m -Choice direct -Level low
# 토큰 통계 수집기(token-stats.ps1)가 이 기록을 같은 프로젝트에서 그 시각에 진행 중이던 턴에 붙인다(답변 끝의 예상 줄을 대신한다).
# 기록 호출은 호출 수에 세지 않는다(수집기가 이 스크립트를 부르는 도구 호출을 건너뛴다). 실패해도 턴을 막지 않고 항상 0 으로 끝낸다.
param(
    [string]$Direct = "",         # 직접 처리 예상 토큰: 1300, 1.3k
    [string]$Delegate = "",       # 위임 예상 토큰
    [string]$TimeDirect = "",     # 직접 처리 예상 시간: 90, 14s, 1m, 1m30s, 1분 30초
    [string]$TimeDelegate = "",   # 위임 예상 시간
    [string]$Choice = "",         # direct | delegate
    [string]$Level = "",          # low | medium | high (낮음 · 보통 · 높음도 받는다)
    [string]$Cwd = "",            # 비우면 현재 폴더(프로젝트 이름은 Claude 의 세션 폴더 이름 규칙으로 만든다)
    [string]$DbPath = ""          # 시험용. 비우면 delegate-agy\data\delegate.db
)
$ErrorActionPreference = "Stop"

function ConvertTo-EstTokens([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { return $null }
    $m = [regex]::Match($t, '^~?\s*([\d.,]+)\s*([kK]?)$')
    if (-not $m.Success) { throw "bad token value: $Text" }
    $n = [double]::Parse(($m.Groups[1].Value -replace ',', ''), [System.Globalization.CultureInfo]::InvariantCulture)
    if ($m.Groups[2].Value) { $n = $n * 1000 }
    return [int][Math]::Round($n)
}

function ConvertTo-EstSeconds([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { return $null }
    if ($t -match '^~?\s*(\d+(?:\.\d+)?)$') { return [int][Math]::Round([double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)) }
    $sec = 0.0; $found = $false
    foreach ($m in [regex]::Matches($t, '(\d+(?:\.\d+)?)\s*(시간|h|분|m|초|s)', 'IgnoreCase')) {
        $v = [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        switch -Regex ($m.Groups[2].Value.ToLowerInvariant()) {
            '^(시간|h)$' { $sec += $v * 3600 }
            '^(분|m)$'   { $sec += $v * 60 }
            default      { $sec += $v }
        }
        $found = $true
    }
    if (-not $found) { throw "bad time value: $Text" }
    return [int][Math]::Round($sec)
}

try {
    $subDir = Join-Path $PSScriptRoot "sub"
    . (Join-Path $subDir "agy-db.ps1")
    . (Join-Path $subDir "agy-layout.ps1")

    $choiceVal = $null
    switch -Regex (([string]$Choice).Trim().ToLowerInvariant()) {
        '^(direct|직접)$'     { $choiceVal = "direct" }
        '^(delegate|위임)$'   { $choiceVal = "delegate" }
        '^$'                   { $choiceVal = $null }
        default                { throw "bad -Choice (direct or delegate): $Choice" }
    }
    $levelVal = $null
    switch -Regex (([string]$Level).Trim().ToLowerInvariant()) {
        '^(low|낮음)$'        { $levelVal = "low" }
        '^(medium|보통)$'     { $levelVal = "medium" }
        '^(high|높음)$'       { $levelVal = "high" }
        '^$'                   { $levelVal = $null }
        default                { throw "bad -Level (low, medium or high): $Level" }
    }
    $estDirect = ConvertTo-EstTokens $Direct
    $estDelegate = ConvertTo-EstTokens $Delegate
    if ($null -eq $estDirect -and $null -eq $estDelegate) { throw "give -Direct and/or -Delegate" }
    $timeDirect = ConvertTo-EstSeconds $TimeDirect
    $timeDelegate = ConvertTo-EstSeconds $TimeDelegate

    if (-not $Cwd) { $Cwd = (Get-Location).Path }
    $project = ([string]$Cwd).TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-'

    if (-not $DbPath) {
        $delegateHome = Split-Path $PSScriptRoot -Parent
        $dataDir = Get-AgyDataDir (Join-Path $delegateHome "runtime")
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        $DbPath = Join-Path $dataDir "delegate.db"
    }

    $db = Open-AgyDb $DbPath
    try {
        $recordedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        [void]$db.Execute(
            "INSERT INTO token_estimates (recorded_at, project, est_direct, est_delegate, est_time_direct, est_time_delegate, choice, level) VALUES (?,?,?,?,?,?,?,?)",
            [object[]]@($recordedAt, $project, $(if ($null -eq $estDirect) { $null } else { [double]$estDirect }), $(if ($null -eq $estDelegate) { $null } else { [double]$estDelegate }), $(if ($null -eq $timeDirect) { $null } else { [long]$timeDirect }), $(if ($null -eq $timeDelegate) { $null } else { [long]$timeDelegate }), $choiceVal, $levelVal)
        )
    } finally { $db.Dispose() }
    Write-Output ("recorded: direct={0} delegate={1} choice={2} level={3}" -f $estDirect, $estDelegate, $choiceVal, $levelVal)
} catch {
    Write-Output ("record-estimate skipped: {0}" -f $_.Exception.Message)
}
exit 0
