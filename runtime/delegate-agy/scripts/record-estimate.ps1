# record-estimate.ps1
# 직접 할지 위임할지 정하는 순간의 예상을 DB(token_estimates)에 남긴다. Claude 가 질문마다 결정 직후 한 번 부른다(질문마다 통계 한 건).
# -Switch N: 질문이 겹쳤을 때 N 번째 질문 일로 돌아왔다는 표시만 남긴다(예상은 기록하지 않는다). 수집기가 그 시각부터를 N 번째 질문 몫으로 센다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File record-estimate.ps1 -Direct 1.3k -Delegate 5.0k -TimeDirect 14s -TimeDelegate 1m -Choice direct -Level low -Reason "맥락이 필요해서"
# 토큰 통계 수집기(token-stats.ps1)가 이 기록을 같은 프로젝트에서 그 시각에 진행 중이던 턴에 붙인다(답변 끝의 예상 줄을 대신한다).
# 기록 호출은 호출 수에 세지 않는다(수집기가 이 스크립트를 부르는 도구 호출을 건너뛴다). 실패해도 턴을 막지 않고 항상 0 으로 끝낸다.
param(
    [string]$Direct = "",         # 직접 처리 예상 토큰: 1300, 1.3k
    [string]$Delegate = "",       # 위임 예상 토큰
    [string]$TimeDirect = "",     # 직접 처리 예상 시간: 90, 14s, 1m, 1m30s, 1분 30초
    [string]$TimeDelegate = "",   # 위임 예상 시간
    [string]$Choice = "",         # direct | delegate
    [string]$Level = "",          # low | medium | high (낮음 · 보통 · 높음도 받는다)
    [string]$Reason = "",         # 직접/위임을 고른 사유 한 줄
    [string]$Cwd = "",            # 비우면 현재 폴더(프로젝트 이름은 Claude 의 세션 폴더 이름 규칙으로 만든다)
    [string]$DbPath = "",         # 시험용. 비우면 delegate-agy\data\delegate.db
    [double]$FactorDirect = 1.0,  # 직접 예상에 곱한 보정 계수(세션 시작 안내의 [예상 보정]). 통계가 보정 전 값으로 다음 계수를 계산하려고 함께 남긴다
    [double]$FactorDelegate = 1.0, # 위임 예상에 곱한 보정 계수
    [Alias("Switch")][int]$ToQuestion = 0,             # 질문 전환 표시: N 번째 질문 일로 돌아왔다(질문 번호는 도착 순서, 첫 질문이 1)
    [string]$MarkerDir = "",      # 기록 성공 표시(_last-record.json)를 둘 폴더. 비우면 runtime\estimate-pending (-DbPath 를 준 시험 호출은 비우면 표시를 남기지 않는다)
    [string]$Session = ""         # 비우면 환경 변수 CLAUDE_CODE_SESSION_ID. Claude Code 가 Bash · PowerShell 도구에 넣어 주며 대화 기록 파일 이름(<세션>.jsonl)과 같다
)
$ErrorActionPreference = "Stop"
# 한글 안내([경고] 등)가 Git Bash · 훅에서 깨지지 않게 출력은 UTF-8 로 낸다
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
$markerDirGiven = $MarkerDir
$dbPathGiven = $DbPath

$rawSession = if ($Session) { $Session } elseif ($env:CLAUDE_CODE_SESSION_ID) { $env:CLAUDE_CODE_SESSION_ID } else { "" }
$cleanedSession = $rawSession -replace '[^A-Za-z0-9_-]', ''
$sessionVal = if ($cleanedSession) { $cleanedSession } else { $null }

function Format-EstK([double]$n) {
    if ($n -ge 1000) { return ("{0:0.0}k" -f ($n / 1000.0)) }
    return [string][int][Math]::Round($n)
}

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

# 질문 전환 표시만 하는 호출: 예상은 기록하지 않고 전환 표시(kind=switch)만 남긴다. 수집기는 대화 기록에서 이 호출의 시각을 보고,
# 진행 중 위임 카드는 이 표시로 그 위임을 보낸 질문의 예상을 고른다. 실패해도 막지 않는다.
if ($ToQuestion -gt 0) {
    try {
        $subDirS = Join-Path $PSScriptRoot "sub"
        . (Join-Path $subDirS "agy-db.ps1")
        . (Join-Path $subDirS "agy-layout.ps1")
        $cwdS = if ($Cwd) { $Cwd } else { (Get-Location).Path }
        $projS = ($cwdS.Trim().TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-')
        if (-not $DbPath) { $DbPath = Join-Path (Get-AgyDataDir (Join-Path $PSScriptRoot "..\runtime")) "delegate.db" }
        $dbS = Open-AgyDb $DbPath
        try {
            [void]$dbS.Execute("INSERT INTO token_estimates (recorded_at, project, kind, switch_to, session) VALUES (?,?,?,?,?)", [object[]]@((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"), $projS, "switch", [long]$ToQuestion, $sessionVal))
        } finally { $dbS.Dispose() }
    } catch {}
    Write-Output ("switched: question {0}" -f $ToQuestion)
    exit 0
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

    $reasonVal = $null
    if ($Reason) {
        $cleanedReason = ($Reason -replace "[\r\n]+", " ").Trim()
        if ($cleanedReason.Length -gt 300) { $cleanedReason = $cleanedReason.Substring(0, 300) }
        if ($cleanedReason) { $reasonVal = $cleanedReason }
    }

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
            "INSERT INTO token_estimates (recorded_at, project, est_direct, est_delegate, est_time_direct, est_time_delegate, choice, level, factor_direct, factor_delegate, reason, session) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            [object[]]@($recordedAt, $project, $(if ($null -eq $estDirect) { $null } else { [double]$estDirect }), $(if ($null -eq $estDelegate) { $null } else { [double]$estDelegate }), $(if ($null -eq $timeDirect) { $null } else { [long]$timeDirect }), $(if ($null -eq $timeDelegate) { $null } else { [long]$timeDelegate }), $choiceVal, $levelVal, $(if ($FactorDirect -gt 0) { [double]$FactorDirect } else { 1.0 }), $(if ($FactorDelegate -gt 0) { [double]$FactorDelegate } else { 1.0 }), $reasonVal, $sessionVal)
        )
    } finally { $db.Dispose() }
    # 기록 성공 표시: 예상 기록 가드(estimate-guard-lib.ps1)가 이 파일의 시각으로 "기록 명령이 실제로 성공했는지"를 확인한다
    try {
        $markDir = if ($markerDirGiven) { $markerDirGiven } elseif (-not $dbPathGiven) { Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime") "estimate-pending" } else { "" }
        if ($markDir) {
            if (-not (Test-Path -LiteralPath $markDir)) { New-Item -ItemType Directory -Force -Path $markDir | Out-Null }
            [System.IO.File]::WriteAllText((Join-Path $markDir "_last-record.json"), (([ordered]@{ recorded_at = $recordedAt; project = $project }) | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch {}
    Write-Output ("recorded: direct={0} delegate={1} choice={2} level={3}" -f $estDirect, $estDelegate, $choiceVal, $levelVal)
    # 위임 예상이 직접 예상보다 20% 넘게 적은데 직접을 골랐으면 알린다(규칙: 더 싼 쪽, 20% 안쪽이면 위임)
    if ($choiceVal -eq "direct" -and $null -ne $estDirect -and $null -ne $estDelegate -and $estDirect -gt 0 -and $estDelegate -lt ($estDirect * 0.8)) {
        $pctLess = [int][Math]::Round((1.0 - ([double]$estDelegate / [double]$estDirect)) * 100)
        Write-Output ("[경고] 위임 예상 {0} 이 직접 예상 {1} 보다 {2}% 적은데 직접으로 기록했습니다. 직접 처리 사유(이 대화의 맥락이 필요 · 설계나 가장 어려운 조각 · 틀리면 비용이 큼 · Claude 전용 도구)에 해당하지 않으면 위임으로 바꾸고 -Choice delegate 로 다시 기록하세요(예상 값은 처음 기록으로 고정되고 선택 · 사유만 바뀝니다)." -f (Format-EstK $estDelegate), (Format-EstK $estDirect), $pctLess)
    }
} catch {
    Write-Output ("record-estimate FAILED (예상이 기록되지 않았습니다. 값 형식을 고쳐 다시 기록하세요): {0}" -f $_.Exception.Message)
}
exit 0
