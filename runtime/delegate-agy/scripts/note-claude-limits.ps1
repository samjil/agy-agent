# note-claude-limits.ps1
# Claude 데스크톱 앱의 사용량 도구(mcp__ccd_session_mgmt__get_usage)에서 받은 5시간·주간 사용률과 리셋 시각을
# runtime/claude-limits.json 에 원자적으로 저장합니다. 뷰어(limits-estimate.ps1)가 한도 크기를 추정할 때 씁니다.
#
# 쓰는 법: 호출 2 확인 명령 앞에 ';' 로 붙여 한 번에 실행한다.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/note-claude-limits.ps1" -FiveHourPct 12 -FiveHourReset "2026-11-23T15:00:00Z" -WeekPct 34 -WeekReset "2026-11-28T00:00:00Z" ; <확인 명령>
#
# 동작: 0..100 범위의 사용률과 ISO 리셋 시각만 받아 claude-limits.json 에 저장하고 성공 시 아무것도 출력하지 않는다.
#   한쪽 구간만 유효하면 기존 파일의 다른 구간(리셋 시각이 아직 미래인 경우)을 유지한다.
#   잘못된 입력이면 표준 오류에 짧은 한글 한 줄만 찍고, 어떤 경우에도 종료 코드는 0 이다.
# 테스트: tests\delegate-agy\note-claude-limits.tests.ps1

param(
    [double]$FiveHourPct = -1,
    [string]$FiveHourReset = "",
    [double]$WeekPct = -1,
    [string]$WeekReset = "",
    [string]$RuntimeDir = ""
)

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    function Parse-WindowInput([double]$Pct, [string]$Reset) {
        $resetTrim = ([string]$Reset).Trim()
        if ($Pct -eq -1 -and -not $resetTrim) {
            return @{ Omitted = $true; Valid = $false; Entry = $null }
        }
        if ([double]::IsNaN($Pct) -or [double]::IsInfinity($Pct) -or $Pct -lt 0.0 -or $Pct -gt 100.0) {
            return @{ Omitted = $false; Valid = $false; Entry = $null }
        }
        if (-not $resetTrim) {
            return @{ Omitted = $false; Valid = $false; Entry = $null }
        }
        $dt = [datetime]::MinValue
        if (-not [datetime]::TryParse($resetTrim, $inv, $styles, [ref]$dt)) {
            return @{ Omitted = $false; Valid = $false; Entry = $null }
        }
        $entry = [ordered]@{
            used_pct  = $Pct
            resets_at = $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        return @{ Omitted = $false; Valid = $true; Entry = $entry }
    }

    $fiveRes = Parse-WindowInput $FiveHourPct $FiveHourReset
    $weekRes = Parse-WindowInput $WeekPct $WeekReset

    $hasInvalid = ((-not $fiveRes.Omitted -and -not $fiveRes.Valid) -or (-not $weekRes.Omitted -and -not $weekRes.Valid))
    if (-not $fiveRes.Valid -and -not $weekRes.Valid) {
        [Console]::Error.WriteLine("note-claude-limits: 유효한 사용률·리셋 시각이 없어 저장하지 않았습니다.")
        exit 0
    }
    if ($hasInvalid) {
        [Console]::Error.WriteLine("note-claude-limits: 일부 구간 값이 잘못되어 건너뛰었습니다.")
    }

    if (-not $RuntimeDir) {
        if ($env:AGY_DELEGATE_RUNTIME) { $RuntimeDir = $env:AGY_DELEGATE_RUNTIME }
        else { $RuntimeDir = Join-Path (Split-Path $PSScriptRoot -Parent) "runtime" }
    }

    $targetFile = Join-Path $RuntimeDir "claude-limits.json"
    $nowUtc = [DateTime]::UtcNow

    $fiveEntry = $fiveRes.Entry
    $weekEntry = $weekRes.Entry

    # 한쪽 구간만 유효할 때 기존 파일에 다른 구간의 미래 리셋 시각이 남아 있으면 유지한다
    if ((-not $fiveEntry -or -not $weekEntry) -and (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
        try {
            $oldRaw = [System.IO.File]::ReadAllText($targetFile, $utf8NoBom).TrimStart([char]0xFEFF)
            if ($oldRaw.Trim()) {
                $oldObj = ConvertFrom-Json -InputObject $oldRaw -ErrorAction Stop
                if ($null -ne $oldObj) {
                    $readExisting = {
                        param([string]$key)
                        if (-not ($oldObj.PSObject.Properties[$key] -and $null -ne $oldObj.$key)) { return $null }
                        $e = $oldObj.$key
                        if ($null -eq $e.used_pct -or -not $e.resets_at) { return $null }
                        $p = 0.0
                        if (-not [double]::TryParse([string]$e.used_pct, [System.Globalization.NumberStyles]::Float, $inv, [ref]$p)) { return $null }
                        if ([double]::IsNaN($p) -or [double]::IsInfinity($p) -or $p -lt 0.0 -or $p -gt 100.0) { return $null }
                        $rdt = [datetime]::MinValue
                        if (-not [datetime]::TryParse(([string]$e.resets_at).Trim(), $inv, $styles, [ref]$rdt)) { return $null }
                        $rUtc = $rdt.ToUniversalTime()
                        if ($rUtc -le $nowUtc) { return $null }
                        return [ordered]@{
                            used_pct  = $p
                            resets_at = $rUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }
                    }
                    if (-not $fiveEntry) { $fiveEntry = & $readExisting "five_hour" }
                    if (-not $weekEntry) { $weekEntry = & $readExisting "seven_day" }
                }
            }
        } catch {
        }
    }

    $payload = [ordered]@{
        checked_at = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    if ($fiveEntry) { $payload["five_hour"] = $fiveEntry }
    if ($weekEntry) { $payload["seven_day"] = $weekEntry }
    $payload["source"] = "desktop-tool"

    $json = $payload | ConvertTo-Json -Compress -Depth 4
    $dir = Split-Path -Path $targetFile -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $tmp = "$targetFile.$PID.tmp"
    try {
        [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
        Remove-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
        [System.IO.File]::Move($tmp, $targetFile)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
} catch {
    [Console]::Error.WriteLine("note-claude-limits: 저장하지 못했습니다.")
}
exit 0
