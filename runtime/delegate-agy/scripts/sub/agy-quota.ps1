# agy-quota.ps1
# agy 의 남은 한도(`agy -p "/usage"`)를 읽어 캐시하는 공용 헬퍼입니다(뷰어의 한도 크기 추정이 씁니다).
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-quota.ps1")`
#
# - `agy -p "/usage"` 출력에는 이메일이나 안내 문구가 섞일 수 있습니다.
#   정해진 탭 구분 한도 줄(`^(.+?)\t(.+?)\t(\d{1,3})%\t(\S+)$`)만 읽고 이메일 등은 저장하거나 기록하지 않습니다.
# - 캐시 파일은 <runtime dir>\agy-quota.json (기본 10분 보관)이며, 실패 시 기존 정상 캐시를 덮어쓰지 않습니다.

function ConvertTo-AgyUtcDateTime([string]$Text) {
    $s = ([string]$Text).Trim()
    if (-not $s) { return $null }
    $dt = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
        return $dt.ToUniversalTime()
    }
    return $null
}

# `agy -p "/usage"` 출력(JSON 또는 탭 구분 텍스트)에서 Gemini 주간/5시간 한도와 Argon 주간 한도를 뽑는다.
# 반환: @{ gemini_weekly=@{pct;reset}; gemini_5h=@{pct;reset}; argon_weekly=@{pct;reset} } (못 찾은 키는 생략)
function ConvertFrom-AgyUsageText([string]$Text) {
    $result = [ordered]@{}
    if (-not $Text) { return $result }
    $trimmed = ([string]$Text).TrimStart([char]0xFEFF).Trim()

    if ($trimmed.StartsWith("{")) {
        try {
            $jObj = $trimmed | ConvertFrom-Json -ErrorAction Stop
            $groups = $null
            if ($jObj -and $jObj.PSObject.Properties['command'] -and $jObj.command -and $jObj.command.PSObject.Properties['data'] -and $jObj.command.data -and $jObj.command.data.PSObject.Properties['groups']) {
                $groups = @($jObj.command.data.groups)
            }
            if ($groups -and $groups.Count -gt 0) {
                foreach ($g in $groups) {
                    if ($null -eq $g) { continue }
                    $gName = if ($g.PSObject.Properties['name']) { ([string]$g.name).Trim() } else { "" }
                    $buckets = if ($g.PSObject.Properties['buckets']) { @($g.buckets) } else { @() }
                    foreach ($b in $buckets) {
                        if ($null -eq $b) { continue }
                        $bName = if ($b.PSObject.Properties['name']) { ([string]$b.name).Trim() } else { "" }
                        $bWin  = if ($b.PSObject.Properties['window']) { ([string]$b.window).Trim() } else { "" }
                        $bReset = if ($b.PSObject.Properties['reset_time']) { ([string]$b.reset_time).Trim() } else { "" }
                        if (-not $b.PSObject.Properties['remaining_fraction'] -or $null -eq $b.remaining_fraction) { continue }
                        $frac = 0.0
                        if (-not [double]::TryParse([string]$b.remaining_fraction, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$frac)) { continue }
                        $pctVal = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, $frac * 100.0)), 2)
                        if ($gName -ieq 'Gemini Models') {
                            if ($bWin -ieq 'weekly' -or $bName -imatch 'Weekly') {
                                $result.gemini_weekly = [ordered]@{ pct = $pctVal; reset = $bReset }
                            } elseif ($bWin -ieq '5h' -or $bName -imatch 'Five\s*Hour') {
                                $result.gemini_5h = [ordered]@{ pct = $pctVal; reset = $bReset }
                            }
                        } elseif ($gName -imatch 'Argon' -and ($bWin -ieq 'weekly' -or $bName -imatch 'Weekly')) {
                            $result.argon_weekly = [ordered]@{ pct = $pctVal; reset = $bReset }
                        }
                    }
                }
                if ($result.Count -gt 0) { return $result }
            }
            if ($jObj -and $jObj.PSObject.Properties['response'] -and $jObj.response) {
                $Text = [string]$jObj.response
            }
        } catch {}
    }

    foreach ($line in ([string]$Text -split "`r?`n")) {
        if ($line -match '^(.+?)\t(.+?)\t(\d{1,3}(?:\.\d+)?)%\t(\S+)$') {
            $group = $Matches[1].Trim()
            $label = $Matches[2].Trim()
            $pctNum = 0.0
            if (-not [double]::TryParse($Matches[3], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$pctNum)) { continue }
            $pct = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, $pctNum)), 2)
            $reset = $Matches[4].Trim()
            if ($group -ieq 'Gemini Models') {
                if ($label -imatch 'Weekly') {
                    $result.gemini_weekly = [ordered]@{ pct = $pct; reset = $reset }
                } elseif ($label -imatch 'Five\s*Hour') {
                    $result.gemini_5h = [ordered]@{ pct = $pct; reset = $reset }
                }
            } elseif ($group -imatch 'Argon' -and $label -imatch 'Weekly') {
                $result.argon_weekly = [ordered]@{ pct = $pct; reset = $reset }
            }
        }
    }
    return $result
}

# `agy -p "/usage"` 를 콘솔 창 없이 실행해 표준 출력을 돌려준다. 실패하거나 시간 안에 끝나지 않으면 $null.
function Invoke-AgyUsageCommand([string]$AgyExe = "agy", [int]$TimeoutSec = 20) {
    $exe = $AgyExe
    if ($exe -eq "agy") {
        try {
            $cmd = Get-Command agy -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd -and $cmd.Source) { $exe = [string]$cmd.Source }
        } catch {}
    }
    if (-not (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue)) {
        $spawnLib = Join-Path $PSScriptRoot "agy-spawn.ps1"
        if (-not (Test-Path -LiteralPath $spawnLib)) { $spawnLib = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-spawn.ps1" }
        if (Test-Path -LiteralPath $spawnLib) { . $spawnLib }
    }
    if (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue) {
        $res = Invoke-AgyHiddenWithOutput -FilePath $exe -ArgumentList @("-p", "/usage", "--output-format", "json") -TimeoutSeconds $TimeoutSec
        if ($res -and $res.Pid -ge 0) {
            if ($res.TimedOut) { return $null }
            if ($res.ExitCode -eq 0 -and $res.StdOut) { return [string]$res.StdOut }
            return $null
        }
    }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $exe
        $psi.Arguments              = '-p "/usage" --output-format json'
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        try { $p.StandardInput.Close() } catch {}
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return $null
        }
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { return $null }
        $out = [string]$outTask.Result
        if (-not $out) { return $null }
        return $out
    } catch {
        return $null
    } finally {
        if ($p) { try { $p.Dispose() } catch {} }
    }
}

function Read-AgyQuotaCache([string]$CacheFile) {
    if (-not $CacheFile -or -not (Test-Path -LiteralPath $CacheFile)) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($CacheFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $obj = $text | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj) { return $null }
        $snap = [ordered]@{}
        if ($obj.PSObject.Properties['checked_at'] -and $obj.checked_at) {
            $snap.checked_at = [string]$obj.checked_at
        }
        $hasData = $false
        foreach ($k in @('gemini_weekly', 'gemini_5h', 'argon_weekly')) {
            if ($obj.PSObject.Properties[$k] -and $null -ne $obj.$k) {
                $entry = $obj.$k
                if ($null -ne $entry.pct -and $entry.reset) {
                    $snap[$k] = [ordered]@{ pct = [Math]::Round([double]$entry.pct, 2); reset = [string]$entry.reset }
                    $hasData = $true
                }
            }
        }
        if (-not $hasData) { return $null }
        return $snap
    } catch {
        return $null
    }
}

# 한도 스냅샷을 돌려준다.
# - 캐시 파일이 $MaxAgeSec 보다 젊으면 그대로 돌려준다.
# - 그렇지 않으면 `agy -p "/usage"`(또는 $Runner)를 실행해 파싱하고 임시 파일+이동으로 원자적으로 저장한다.
# - 실패하거나 파싱된 값이 없으면 기존 캐시를 덮어쓰지 않고, 2시간 미만인 기존 캐시가 있으면 대신 돌려주고 없으면 $null.
function Get-AgyQuotaSnapshot([string]$CacheFile, [int]$MaxAgeSec = 600, [scriptblock]$Runner = $null, [string]$AgyExe = "agy", [int]$TimeoutSec = 20, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $cached = Read-AgyQuotaCache $CacheFile
    $cacheAgeSec = $null
    if ($cached -and $cached.checked_at) {
        $checkedDt = ConvertTo-AgyUtcDateTime ([string]$cached.checked_at)
        if ($null -ne $checkedDt) {
            $cacheAgeSec = ($now - $checkedDt).TotalSeconds
            if ($MaxAgeSec -gt 0 -and $cacheAgeSec -lt $MaxAgeSec) {
                return $cached
            }
        }
    }

    $raw = $null
    try {
        if ($Runner) { $raw = & $Runner } else { $raw = Invoke-AgyUsageCommand $AgyExe $TimeoutSec }
    } catch {
        $raw = $null
    }

    $parsed = (ConvertFrom-AgyUsageText ([string]$raw))
    $parsedKeys = @($parsed.Keys)
    if ($parsedKeys.Count -gt 0) {
        $snap = [ordered]@{ checked_at = $now.ToString("yyyy-MM-ddTHH:mm:ssZ") }
        foreach ($k in $parsedKeys) { $snap[$k] = $parsed[$k] }
        if ($CacheFile) {
            $tmp = "$CacheFile.$PID.tmp"
            try {
                $dir = Split-Path -Path $CacheFile -Parent
                if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Force -Path $dir | Out-Null
                }
                $json = $snap | ConvertTo-Json -Compress -Depth 5
                [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
                Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
                [System.IO.File]::Move($tmp, $CacheFile)
            } catch {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        if ($CacheFile -and $parsed.Contains('gemini_5h') -and $parsed.Contains('gemini_weekly')) {
            try {
                if (-not (Get-Command Add-UsageHistory -ErrorAction SilentlyContinue)) {
                    $histLib = Join-Path $PSScriptRoot "usage-history.ps1"
                    if (-not (Test-Path -LiteralPath $histLib -PathType Leaf)) { $histLib = Join-Path (Split-Path $PSScriptRoot -Parent) "usage-history.ps1" }
                    if (Test-Path -LiteralPath $histLib -PathType Leaf) { . $histLib }
                }
                if (Get-Command Add-UsageHistory -ErrorAction SilentlyContinue) {
                    $rtDir = Split-Path -Path $CacheFile -Parent
                    $e5 = $parsed.Item('gemini_5h')
                    $ew = $parsed.Item('gemini_weekly')
                    [void](Add-UsageHistory -RuntimeDir $rtDir -Src "agy" -FiveUsed (100 - [int]$e5.pct) -FiveReset ([string]$e5.reset) -WeekUsed (100 - [int]$ew.pct) -WeekReset ([string]$ew.reset) -AtUtc $now)
                }
            } catch {}
        }
        return $snap
    }

    # 실패하거나 파싱된 항목이 없으면 기존 정상 캐시를 지우지 않는다(2시간 미만이면 재사용).
    if ($cached -and $null -ne $cacheAgeSec -and $cacheAgeSec -lt 7200) {
        return $cached
    }
    return $null
}

function Resolve-ClaudeTimeZone([string]$TzHint) {
    $t = ([string]$TzHint).Trim()
    if (-not $t -or $t -match '^(?i:UTC|GMT|Etc/UTC|Z)$') {
        if ($t) { return [System.TimeZoneInfo]::Utc }
        return [System.TimeZoneInfo]::Local
    }
    $map = @{
        "asia/seoul"       = "Korea Standard Time"
        "kst"              = "Korea Standard Time"
        "asia/tokyo"       = "Tokyo Standard Time"
        "jst"              = "Tokyo Standard Time"
        "america/new_york" = "Eastern Standard Time"
        "est"              = "Eastern Standard Time"
        "edt"              = "Eastern Standard Time"
        "america/los_angeles" = "Pacific Standard Time"
        "pst"              = "Pacific Standard Time"
        "pdt"              = "Pacific Standard Time"
    }
    $lower = $t.ToLowerInvariant()
    $winId = if ($map.ContainsKey($lower)) { $map[$lower] } else { $t }
    try {
        return [System.TimeZoneInfo]::FindSystemTimeZoneById($winId)
    } catch {
        return [System.TimeZoneInfo]::Local
    }
}

function ConvertFrom-ClaudeResetText([string]$ResetText, [datetime]$NowUtc = [datetime]::MinValue) {
    $raw = ([string]$ResetText).Trim()
    if (-not $raw) { return "" }
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    $tzHint = ""
    if ($raw -match '^(.*?)\s*\(([^()]+)\)\s*$') {
        $raw = $Matches[1].Trim()
        $tzHint = $Matches[2].Trim()
    }
    if (-not $raw) { return "" }

    if ($raw -match '^(?i)(?:in\s+)?(?:(\d+)\s*d(?:ays?)?)?\s*(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:ins?|inutes?)?)?$') {
        $hasD = $Matches[1]; $hasH = $Matches[2]; $hasM = $Matches[3]
        if ($hasD -or $hasH -or $hasM) {
            $d = if ($hasD) { [int]$hasD } else { 0 }
            $h = if ($hasH) { [int]$hasH } else { 0 }
            $m = if ($hasM) { [int]$hasM } else { 0 }
            return $now.AddDays($d).AddHours($h).AddMinutes($m).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }

    $tz = Resolve-ClaudeTimeZone $tzHint
    $localNow = [System.TimeZoneInfo]::ConvertTimeFromUtc($now, $tz)

    if ($raw -match '^(?i)([A-Za-z]{3,9})\s+(\d{1,2})(?:,\s*(\d{4}))?(?:,|\s+at)?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$') {
        $monName = $Matches[1].ToLowerInvariant()
        $dayVal = [int]$Matches[2]
        $yrVal = if ($Matches[3]) { [int]$Matches[3] } else { $localNow.Year }
        $hrVal = [int]$Matches[4]
        $minVal = if ($Matches[5]) { [int]$Matches[5] } else { 0 }
        $ampm = if ($Matches[6]) { $Matches[6].ToLowerInvariant() } else { "" }
        if ($ampm -eq "pm" -and $hrVal -lt 12) { $hrVal += 12 }
        elseif ($ampm -eq "am" -and $hrVal -eq 12) { $hrVal = 0 }
        $months = @{ jan=1; january=1; feb=2; february=2; mar=3; march=3; apr=4; april=4; may=5; jun=6; june=6; jul=7; july=7; aug=8; august=8; sep=9; sept=9; september=9; oct=10; october=10; nov=11; november=11; dec=12; december=12 }
        if ($months.ContainsKey($monName) -and $dayVal -ge 1 -and $dayVal -le 31 -and $hrVal -ge 0 -and $hrVal -le 23) {
            try {
                $localDt = New-Object System.DateTime($yrVal, $months[$monName], $dayVal, $hrVal, $minVal, 0, [System.DateTimeKind]::Unspecified)
                if (-not $Matches[3] -and $localDt -lt $localNow.AddDays(-30)) {
                    $localDt = New-Object System.DateTime(($yrVal + 1), $months[$monName], $dayVal, $hrVal, $minVal, 0, [System.DateTimeKind]::Unspecified)
                }
                $utcDt = [System.TimeZoneInfo]::ConvertTimeToUtc($localDt, $tz)
                return $utcDt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            } catch {}
        }
    }

    if ($raw -match '^(?i)(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$') {
        $hrVal = [int]$Matches[1]
        $minVal = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
        $ampm = if ($Matches[3]) { $Matches[3].ToLowerInvariant() } else { "" }
        if ($ampm -eq "pm" -and $hrVal -lt 12) { $hrVal += 12 }
        elseif ($ampm -eq "am" -and $hrVal -eq 12) { $hrVal = 0 }
        if ($hrVal -ge 0 -and $hrVal -le 23 -and $minVal -ge 0 -and $minVal -le 59) {
            try {
                $localDt = New-Object System.DateTime($localNow.Year, $localNow.Month, $localNow.Day, $hrVal, $minVal, 0, [System.DateTimeKind]::Unspecified)
                if ($localDt -le $localNow) { $localDt = $localDt.AddDays(1) }
                $utcDt = [System.TimeZoneInfo]::ConvertTimeToUtc($localDt, $tz)
                return $utcDt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            } catch {}
        }
    }

    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($raw, $inv, $styles, [ref]$dto)) {
        return $dto.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    return ""
}

function ConvertFrom-ClaudeUsageOutput([string]$RawOutput, [datetime]$NowUtc = [datetime]::MinValue) {
    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return $null }
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $text = ([string]$RawOutput).Trim()
    if ($text.StartsWith("{")) {
        try {
            $obj = $text | ConvertFrom-Json -ErrorAction Stop
            if ($obj -and $obj.PSObject.Properties["result"] -and $null -ne $obj.result) {
                $text = [string]$obj.result
            }
        } catch {}
    }
    $text = [regex]::Replace($text, '\x1b\[[0-9;]*[A-Za-z]', '')

    $mSess = [regex]::Match($text, '(?im)^\s*Current\s+session\s*:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*[^\w\r\n]+\s*resets\s+([^\r\n]+))?')
    $mWeek = [regex]::Match($text, '(?im)^\s*Current\s+week(?:\s*\([^)]*\))?\s*:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*[^\w\r\n]+\s*resets\s+([^\r\n]+))?')
    if (-not $mSess.Success -and -not $mWeek.Success) { return $null }

    $payload = [ordered]@{
        checked_at = $now.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    if ($mSess.Success) {
        $sPct = [double]$mSess.Groups[1].Value
        $sResetIso = if ($mSess.Groups[2].Success) { ConvertFrom-ClaudeResetText $mSess.Groups[2].Value $now } else { "" }
        if ($sPct -gt 0 -or $sResetIso) {
            $entry5 = [ordered]@{ used_pct = $sPct }
            if ($sResetIso) { $entry5["resets_at"] = $sResetIso }
            $payload["five_hour"] = $entry5
        }
    }
    if ($mWeek.Success) {
        $wPct = [double]$mWeek.Groups[1].Value
        $wResetIso = if ($mWeek.Groups[2].Success) { ConvertFrom-ClaudeResetText $mWeek.Groups[2].Value $now } else { "" }
        $entry7 = [ordered]@{ used_pct = $wPct }
        if ($wResetIso) { $entry7["resets_at"] = $wResetIso }
        $payload["seven_day"] = $entry7
    }
    $payload["source"] = "claude-cli"
    return $payload
}

# Claude CLI /usage 출력이 플랜 한도(Current session/week) 없이 비용 요약(Total cost:)만 담고 있는지 판별한다.
function Test-ClaudeUsageCostOnlyOutput([string]$RawOutput) {
    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return $false }
    $text = ([string]$RawOutput).Trim()
    if ($text.StartsWith("{")) {
        try {
            $obj = $text | ConvertFrom-Json -ErrorAction Stop
            if ($obj -and $obj.PSObject.Properties["result"] -and $null -ne $obj.result) {
                $text = [string]$obj.result
            }
        } catch {}
    }
    $text = [regex]::Replace($text, '\x1b\[[0-9;]*[A-Za-z]', '')
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ([regex]::IsMatch($text, '(?im)^\s*Current\s+(?:session|week)\b')) { return $false }
    return [regex]::IsMatch($text, '(?im)^\s*Total cost\s*:')
}

# Claude CLI /usage 미지원(cost-only) 상태 마커를 원자적으로 기록한다.
function Set-ClaudeCliUsageUnsupported([string]$RuntimeDir, [datetime]$NowUtc = [datetime]::MinValue) {
    if ([string]::IsNullOrWhiteSpace($RuntimeDir)) { return }
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $path = Join-Path $RuntimeDir "claude-cli-usage.json"
    $tmp = "$path.$PID.tmp"
    try {
        if (-not (Test-Path -LiteralPath $RuntimeDir)) {
            New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        }
        $payload = [ordered]@{
            unsupported_at  = $now.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            cli_output_kind = "cost-only"
        }
        $json = $payload | ConvertTo-Json -Compress -Depth 3
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        [System.IO.File]::Move($tmp, $path)
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Claude CLI /usage 미지원 마커를 제거한다.
function Clear-ClaudeCliUsageUnsupported([string]$RuntimeDir) {
    if ([string]::IsNullOrWhiteSpace($RuntimeDir)) { return }
    $path = Join-Path $RuntimeDir "claude-cli-usage.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# claude-cli-usage.json 마커가 존재하고 24시간 미만이면 $true 를 돌려준다.
function Test-ClaudeCliUsageUnsupported([string]$RuntimeDir, [datetime]$NowUtc = [datetime]::MinValue) {
    if ([string]::IsNullOrWhiteSpace($RuntimeDir)) { return $false }
    $path = Join-Path $RuntimeDir "claude-cli-usage.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $false }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj -or -not $obj.PSObject.Properties["unsupported_at"] -or -not $obj.unsupported_at) { return $false }
        $dt = ConvertTo-AgyUtcDateTime ([string]$obj.unsupported_at)
        if ($null -eq $dt) { return $false }
        return (($now - $dt).TotalHours -lt 24)
    } catch {
        return $false
    }
}

function Find-ClaudeCliExecutable([string]$ClaudeExe = "claude") {
    if ($env:SAMJIL_DISABLE_CLAUDE_CLI -eq '1') { return $null }
    if ($ClaudeExe -and $ClaudeExe -ne "claude") {
        if (Test-Path -LiteralPath $ClaudeExe -PathType Leaf) { return $ClaudeExe }
        return $null
    }
    try {
        $cmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return [string]$cmd.Source }
    } catch {}
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    foreach ($cand in @(
        (Join-Path $homeDir ".local\bin\claude.exe"),
        (Join-Path ([string]$env:LOCALAPPDATA) "AnthropicClaude\claude.exe")
    )) {
        if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) { return $cand }
    }
    return $null
}

function Invoke-ClaudeUsageCommand([string]$ClaudeExe = "claude", [int]$TimeoutSec = 15) {
    $exe = Find-ClaudeCliExecutable $ClaudeExe
    if (-not $exe) { return $null }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $exe
        $psi.Arguments              = '-p "/usage" --output-format json --no-session-persistence --strict-mcp-config --setting-sources ""'
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        try { $p.StandardInput.Close() } catch {}
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return $null
        }
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { return $null }
        $out = [string]$outTask.Result
        if (-not $out) { return $null }
        return $out
    } catch {
        return $null
    } finally {
        if ($p) { try { $p.Dispose() } catch {} }
    }
}

function Update-ClaudeLimitsCache([string]$CacheFile, [int]$MaxAgeSec = 0, [scriptblock]$Runner = $null, [string]$ClaudeExe = "claude", [int]$TimeoutSec = 15, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    if ($MaxAgeSec -gt 0 -and $CacheFile -and (Test-Path -LiteralPath $CacheFile -PathType Leaf)) {
        try {
            $rawOld = [System.IO.File]::ReadAllText($CacheFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
            $oldObj = $rawOld | ConvertFrom-Json -ErrorAction Stop
            if ($oldObj -and $oldObj.checked_at) {
                $oldDt = ConvertTo-AgyUtcDateTime ([string]$oldObj.checked_at)
                if ($null -ne $oldDt -and ($now - $oldDt).TotalSeconds -lt $MaxAgeSec) {
                    return $oldObj
                }
            }
        } catch {}
    }

    $raw = $null
    try {
        if ($Runner) { $raw = & $Runner } else { $raw = Invoke-ClaudeUsageCommand $ClaudeExe $TimeoutSec }
    } catch { $raw = $null }

    $parsed = ConvertFrom-ClaudeUsageOutput ([string]$raw) $now
    if ($null -eq $parsed) {
        if ($CacheFile -and (Test-ClaudeUsageCostOnlyOutput ([string]$raw))) {
            $rtDir = Split-Path -Path $CacheFile -Parent
            if ($rtDir) { Set-ClaudeCliUsageUnsupported $rtDir $now }
        }
        return $null
    }

    if ($CacheFile) {
        $dir = Split-Path -Path $CacheFile -Parent
        if ($dir) { Clear-ClaudeCliUsageUnsupported $dir }
        $tmp = "$CacheFile.$PID.tmp"
        try {
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            $json = $parsed | ConvertTo-Json -Compress -Depth 5
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
            Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
            [System.IO.File]::Move($tmp, $CacheFile)
        } catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        if ($parsed.Contains("seven_day")) {
            try {
                if (-not (Get-Command Add-UsageHistory -ErrorAction SilentlyContinue)) {
                    $histLib = Join-Path $PSScriptRoot "usage-history.ps1"
                    if (-not (Test-Path -LiteralPath $histLib -PathType Leaf)) { $histLib = Join-Path (Split-Path $PSScriptRoot -Parent) "usage-history.ps1" }
                    if (Test-Path -LiteralPath $histLib -PathType Leaf) { . $histLib }
                }
                if (Get-Command Add-UsageHistory -ErrorAction SilentlyContinue) {
                    $rtDir = Split-Path -Path $CacheFile -Parent
                    $e5 = if ($parsed.Contains("five_hour")) { $parsed.Item("five_hour") } else { $null }
                    $e7 = $parsed.Item("seven_day")
                    $f5 = if ($null -ne $e5) { [double]$e5.Item("used_pct") } else { 0.0 }
                    $f5R = if ($null -ne $e5 -and $e5.Contains("resets_at")) { [string]$e5.Item("resets_at") } else { "" }
                    $f7 = [double]$e7.Item("used_pct")
                    $f7R = if ($e7.Contains("resets_at")) { [string]$e7.Item("resets_at") } else { "" }
                    [void](Add-UsageHistory -RuntimeDir $rtDir -Src "claude" -FiveUsed $f5 -FiveReset $f5R -WeekUsed $f7 -WeekReset $f7R -AtUtc $now)
                }
            } catch {}
        }
    }
    return $parsed
}
