# quota-balance.ps1
# Claude 구독 한도와 agy(Gemini) 한도의 소모 속도를 남은 창 시간과 비교해 위임 균형 모드를 계산합니다.
# dot-source 하면 라이브러리 함수만 불러오고, 직접(-File) 실행하면 CLI 로 동작합니다.

param(
    [string]$RuntimeDir = "",
    [int]$Claude5hUsed = -1,
    [string]$Claude5hResetsAt = "",
    [int]$ClaudeWeekUsed = -1,
    [string]$ClaudeWeekResetsAt = "",
    [switch]$RefreshAgy,
    [switch]$Json,
    [switch]$Quiet
)

function Resolve-QuotaRuntimeDir([string]$RuntimeDir = "") {
    if (-not [string]::IsNullOrWhiteSpace($RuntimeDir)) { return $RuntimeDir.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($env:AGY_DELEGATE_RUNTIME)) { return $env:AGY_DELEGATE_RUNTIME.Trim() }
    return (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime")
}

function ConvertTo-UtcDateTime($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        return [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc)
    }
    if ($Value -is [DateTimeOffset]) {
        return $Value.UtcDateTime
    }
    $s = ([string]$Value).Trim()
    if (-not $s) { return $null }
    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Format-IsoUtc([datetime]$Dt) {
    $utc = ConvertTo-UtcDateTime $Dt
    if ($null -eq $utc) { return "" }
    if (($utc.Ticks % [TimeSpan]::TicksPerSecond) -eq 0) {
        return $utc.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $utc.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-QuotaReadableJson($InputObject, [switch]$Pretty) {
    $json = if ($Pretty) {
        ConvertTo-Json -InputObject $InputObject -Depth 6
    } else {
        ConvertTo-Json -InputObject $InputObject -Depth 6 -Compress
    }
    if ($null -eq $json) { return "" }
    return [regex]::Replace($json, '(?<!\\)((?:\\\\)*)\\u([0-9a-fA-F]{4})', {
        param($m)
        $code = [Convert]::ToInt32($m.Groups[2].Value, 16)
        if ($code -lt 0x20 -or $code -eq 0x22 -or $code -eq 0x5C) { return $m.Value }
        return $m.Groups[1].Value + [string][char]$code
    })
}

function Read-QuotaJsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Write-QuotaJsonFile([string]$Path, $Object) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $json = ConvertTo-QuotaReadableJson $Object -Pretty
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    # 작업자 · 훅 · 새로 고침이 동시에 읽고 쓰므로, 임시 파일에 다 쓴 뒤 바꿔치기한다(반쯤 쓴 파일을 읽지 않게)
    $tmp = "$Path.tmp-" + [guid]::NewGuid().ToString("N")
    try {
        [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Format-TimeLeft([datetime]$ResetsAt, [datetime]$NowUtc) {
    $span = $ResetsAt - $NowUtc
    if ($span.TotalSeconds -le 0) { return "0m" }
    $totalMinutes = [int][Math]::Floor($span.TotalMinutes)
    if ($totalMinutes -ge 1440) {
        $days = [int][Math]::Floor($totalMinutes / 1440)
        $hours = [int][Math]::Floor(($totalMinutes % 1440) / 60)
        return "${days}d${hours}h"
    }
    if ($totalMinutes -ge 60) {
        $hours = [int][Math]::Floor($totalMinutes / 60)
        $mins = [int]($totalMinutes % 60)
        return "${hours}h${mins}m"
    }
    return "${totalMinutes}m"
}

function ConvertFrom-AgyUsageText([string]$Text) {
    $items = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    foreach ($rawLine in ($Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
        $cols = $rawLine -split "`t"
        if ($cols.Count -ne 4) { continue }
        $c0 = $cols[0].Trim()
        $c1 = $cols[1].Trim()
        $c2 = $cols[2].Trim()
        $c3 = $cols[3].Trim()

        $group = $null
        if ($c0 -eq "Gemini Models") { $group = "gemini" }
        elseif ($c0 -like "*Argon*") { $group = "argon" }
        elseif ($c0 -like "Claude*") { $group = "claude-gpt" }
        else { continue }

        $window = $null
        if ($c1 -like "*Five Hour*") { $window = "5h" }
        elseif ($c1 -like "*Weekly*") { $window = "week" }
        else { continue }

        if ($c2 -notmatch '^(\d+)\s*%$') { continue }
        $rem = [int]$Matches[1]

        $resetsAt = ConvertTo-UtcDateTime $c3
        if ($null -eq $resetsAt) { continue }

        [void]$items.Add(@{
            Group     = $group
            Window    = $window
            Remaining = $rem
            ResetsAt  = $resetsAt
        })
    }
    return @($items.ToArray())
}

function Update-AgyQuotaCache([string]$RuntimeDir = "", [string]$AgyExe = "agy", [int]$TimeoutSec = 20) {
    $rt = Resolve-QuotaRuntimeDir $RuntimeDir
    $workDir = if ($env:TEMP -and (Test-Path -LiteralPath $env:TEMP)) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $tmpOut = Join-Path $workDir ("agy-usage-" + [guid]::NewGuid().ToString("N") + ".txt")
    $tmpErr = "$tmpOut.err"
    try {
        $p = Start-Process -FilePath $AgyExe -ArgumentList @("-p", "/usage", "--print-timeout", "15s") -WorkingDirectory $workDir -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -ErrorAction Stop
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return $null
        }
        if (-not (Test-Path -LiteralPath $tmpOut)) { return $null }
        $text = [System.IO.File]::ReadAllText($tmpOut, [System.Text.Encoding]::UTF8)
        $items = @(ConvertFrom-AgyUsageText $text)
        $hasGemini = @($items | Where-Object { $_.Group -eq "gemini" }).Count -gt 0
        if (-not $hasGemini) { return $null }

        $jsonItems = New-Object System.Collections.ArrayList
        foreach ($it in $items) {
            [void]$jsonItems.Add([ordered]@{
                group     = [string]$it.Group
                window    = [string]$it.Window
                remaining = [int]$it.Remaining
                resets_at = Format-IsoUtc $it.ResetsAt
            })
        }
        $payload = [ordered]@{
            checked_at = Format-IsoUtc ([DateTime]::UtcNow)
            items      = @($jsonItems.ToArray())
        }
        Write-QuotaJsonFile (Join-Path $rt "agy-quota.json") $payload
        return $items
    } catch {
        return $null
    } finally {
        Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    }
}

function Save-ClaudeQuota(
    [string]$RuntimeDir = "",
    [int]$FiveHourUsed,
    [string]$FiveHourResetsAt,
    [int]$WeekUsed,
    [string]$WeekResetsAt,
    [datetime]$Now = [DateTime]::UtcNow
) {
    $rt = Resolve-QuotaRuntimeDir $RuntimeDir
    $nowUtc = ConvertTo-UtcDateTime $Now
    $fiveDt = ConvertTo-UtcDateTime $FiveHourResetsAt
    $weekDt = ConvertTo-UtcDateTime $WeekResetsAt
    $payload = [ordered]@{
        checked_at = Format-IsoUtc $nowUtc
        five_hour  = [ordered]@{
            used      = [int]$FiveHourUsed
            resets_at = if ($null -ne $fiveDt) { Format-IsoUtc $fiveDt } else { [string]$FiveHourResetsAt }
        }
        week       = [ordered]@{
            used      = [int]$WeekUsed
            resets_at = if ($null -ne $weekDt) { Format-IsoUtc $weekDt } else { [string]$WeekResetsAt }
        }
    }
    Write-QuotaJsonFile (Join-Path $rt "claude-quota.json") $payload
}

function Get-WindowSlack(
    [double]$Remaining,
    [datetime]$ResetsAt,
    [double]$WindowHours,
    [datetime]$Now = [DateTime]::UtcNow
) {
    $nowUtc = ConvertTo-UtcDateTime $Now
    $resetsUtc = ConvertTo-UtcDateTime $ResetsAt
    if ($nowUtc -ge $resetsUtc) { return [double]0 }

    $rawPct = ($resetsUtc - $nowUtc).TotalHours / $WindowHours * 100.0
    $timeLeftPct = [Math]::Max(0.0, [Math]::Min(100.0, $rawPct))
    $slack = $Remaining - $timeLeftPct

    if ($timeLeftPct -lt 15.0) {
        $slack = [Math]::Min($slack, $Remaining - 15.0)
    }
    if ((100.0 - $timeLeftPct) -lt 15.0 -and $slack -lt 0.0) {
        $slack = $slack / 2.0
    }
    return [double]$slack
}

function Get-ProviderScore([double]$FiveSlack, [double]$WeekSlack, [double]$WeekRemaining) {
    if ($WeekRemaining -gt 30.0) {
        return [double](0.7 * $FiveSlack + 0.3 * $WeekSlack)
    }
    return [double][Math]::Min($FiveSlack, $WeekSlack)
}

function Get-QuotaBalance([string]$RuntimeDir = "", [datetime]$Now = [DateTime]::UtcNow) {
    $rt = Resolve-QuotaRuntimeDir $RuntimeDir
    $nowUtc = ConvertTo-UtcDateTime $Now

    # 1. agy-quota.json 읽기 (6시간 이내만 유효)
    $agyKnown = $false
    $agyAgeMin = $null
    $gem5Item = $null
    $gemWeekItem = $null
    $argonWeekItem = $null

    $agyObj = Read-QuotaJsonFile (Join-Path $rt "agy-quota.json")
    if ($null -ne $agyObj -and $agyObj.checked_at) {
        $agyChecked = ConvertTo-UtcDateTime $agyObj.checked_at
        if ($null -ne $agyChecked) {
            $ageHours = ($nowUtc - $agyChecked).TotalHours
            if ($ageHours -le 6.0) {
                foreach ($it in @($agyObj.items)) {
                    if ($null -eq $it) { continue }
                    $g = [string]$it.group
                    $w = [string]$it.window
                    if ($g -eq "gemini" -and $w -eq "5h") { $gem5Item = $it }
                    elseif ($g -eq "gemini" -and $w -eq "week") { $gemWeekItem = $it }
                    elseif ($g -eq "argon" -and $w -eq "week") { $argonWeekItem = $it }
                }
                if ($null -ne $gem5Item -or $null -ne $gemWeekItem) {
                    $agyKnown = $true
                    $agyAgeMin = [int][Math]::Max(0, [Math]::Round(($nowUtc - $agyChecked).TotalMinutes))
                }
            }
        }
    }

    $gem5Rem = 100.0
    $gem5Slack = 0.0
    $gem5Resets = $null
    if ($null -ne $gem5Item) {
        $gem5Resets = ConvertTo-UtcDateTime $gem5Item.resets_at
        if ($null -ne $gem5Resets -and $nowUtc -ge $gem5Resets) {
            $gem5Rem = 100.0
            $gem5Slack = 0.0
        } else {
            $gem5Rem = [double]$gem5Item.remaining
            $gem5Slack = if ($null -ne $gem5Resets) { Get-WindowSlack $gem5Rem $gem5Resets 5 $nowUtc } else { 0.0 }
        }
    }

    $gemWeekRem = 100.0
    $gemWeekSlack = 0.0
    $gemWeekResets = $null
    if ($null -ne $gemWeekItem) {
        $gemWeekResets = ConvertTo-UtcDateTime $gemWeekItem.resets_at
        if ($null -ne $gemWeekResets -and $nowUtc -ge $gemWeekResets) {
            $gemWeekRem = 100.0
            $gemWeekSlack = 0.0
        } else {
            $gemWeekRem = [double]$gemWeekItem.remaining
            $gemWeekSlack = if ($null -ne $gemWeekResets) { Get-WindowSlack $gemWeekRem $gemWeekResets 168 $nowUtc } else { 0.0 }
        }
    }

    $argon = "unknown"
    $argonRem = $null
    if ($agyKnown -and $null -ne $argonWeekItem) {
        $argonResets = ConvertTo-UtcDateTime $argonWeekItem.resets_at
        if ($null -ne $argonResets -and $nowUtc -ge $argonResets) {
            $argonRem = 100.0
            $argonSlack = 0.0
        } else {
            $argonRem = [double]$argonWeekItem.remaining
            $argonSlack = if ($null -ne $argonResets) { Get-WindowSlack $argonRem $argonResets 168 $nowUtc } else { 0.0 }
        }
        if ($argonRem -lt 20.0 -or $argonSlack -lt -10.0) { $argon = "limited" }
        else { $argon = "ok" }
    }

    # 2. claude-quota.json 읽기 (2시간 이내만 유효)
    $claudeKnown = $false
    $claudeAgeMin = $null
    $claude5Rem = 100.0
    $claude5Slack = 0.0
    $claude5Resets = $null
    $claudeWeekRem = 100.0
    $claudeWeekSlack = 0.0
    $claudeWeekResets = $null

    $claudeObj = Read-QuotaJsonFile (Join-Path $rt "claude-quota.json")
    if ($null -ne $claudeObj -and $claudeObj.checked_at -and $null -ne $claudeObj.five_hour -and $null -ne $claudeObj.week) {
        $claudeChecked = ConvertTo-UtcDateTime $claudeObj.checked_at
        if ($null -ne $claudeChecked -and ($nowUtc - $claudeChecked).TotalHours -le 2.0) {
            $claudeKnown = $true
            $claudeAgeMin = [int][Math]::Max(0, [Math]::Round(($nowUtc - $claudeChecked).TotalMinutes))

            $claude5Resets = ConvertTo-UtcDateTime $claudeObj.five_hour.resets_at
            if ($null -ne $claude5Resets -and $nowUtc -ge $claude5Resets) {
                $claude5Rem = 100.0
                $claude5Slack = 0.0
            } else {
                $claude5Rem = [Math]::Max(0.0, [Math]::Min(100.0, 100.0 - [double]$claudeObj.five_hour.used))
                $claude5Slack = if ($null -ne $claude5Resets) { Get-WindowSlack $claude5Rem $claude5Resets 5 $nowUtc } else { 0.0 }
            }

            $claudeWeekResets = ConvertTo-UtcDateTime $claudeObj.week.resets_at
            if ($null -ne $claudeWeekResets -and $nowUtc -ge $claudeWeekResets) {
                $claudeWeekRem = 100.0
                $claudeWeekSlack = 0.0
            } else {
                $claudeWeekRem = [Math]::Max(0.0, [Math]::Min(100.0, 100.0 - [double]$claudeObj.week.used))
                $claudeWeekSlack = if ($null -ne $claudeWeekResets) { Get-WindowSlack $claudeWeekRem $claudeWeekResets 168 $nowUtc } else { 0.0 }
            }
        }
    }

    # 3. 점수 및 차이 계산
    $agyScore = if ($agyKnown) { Get-ProviderScore $gem5Slack $gemWeekSlack $gemWeekRem } else { $null }
    $claudeScore = if ($claudeKnown) { Get-ProviderScore $claude5Slack $claudeWeekSlack $claudeWeekRem } else { $null }
    $gapRaw = if ($agyKnown -and $claudeKnown) { $agyScore - $claudeScore } else { $null }
    $gapRounded = if ($null -ne $gapRaw) { [Math]::Round($gapRaw, 1) } else { $null }

    # 4. 모드 결정 (a -> e)
    $mode = "balanced"
    if (-not $agyKnown) {
        $mode = "balanced"
    } elseif ($gem5Rem -lt 10.0 -or $gemWeekRem -lt 5.0) {
        $mode = "no-agy"
    } elseif ($claudeKnown -and $claude5Rem -le 10.0) {
        $mode = "agy-max"
    } elseif (-not $claudeKnown) {
        if ($gem5Rem -ge 70.0 -and $gemWeekSlack -ge -5.0) { $mode = "agy-more" }
        else { $mode = "balanced" }
    } else {
        $prevValid = $false
        $prevMode = ""
        $prevObj = Read-QuotaJsonFile (Join-Path $rt "quota-balance.json")
        # 이전 모드는 Claude 수치를 알고 두 쪽을 비교해 정한 것만 이어받는다(Claude 를 몰라 agy 만 보고 정한 agy-more 를 끌고 오지 않게)
        if ($null -ne $prevObj -and $prevObj.computed_at -and $prevObj.mode -and ($prevObj.PSObject.Properties["compared"] -and [bool]$prevObj.compared)) {
            $prevDt = ConvertTo-UtcDateTime $prevObj.computed_at
            if ($null -ne $prevDt -and ($nowUtc - $prevDt).TotalHours -le 6.0) {
                $prevValid = $true
                $prevMode = [string]$prevObj.mode
            }
        }

        if ($prevValid -and ($prevMode -eq "agy-more" -or $prevMode -eq "agy-max") -and $gapRaw -ge 15.0) {
            $mode = "agy-more"
        } elseif ($prevValid -and $prevMode -eq "claude-more" -and $gapRaw -le -15.0) {
            $mode = "claude-more"
        } elseif ($gapRaw -ge 25.0) {
            $mode = "agy-more"
        } elseif ($gapRaw -le -25.0) {
            $mode = "claude-more"
        } else {
            $mode = "balanced"
        }
    }

    # 5. 서브에이전트 기준치
    $threshold = switch ($mode) {
        "agy-more" { 80000 }
        "agy-max"  { 30000 }
        default    { 200000 }
    }

    # 6. quota-balance.json 저장
    $balancePayload = [ordered]@{
        mode        = $mode
        computed_at = Format-IsoUtc $nowUtc
        gap         = $gapRounded
        # 두 쪽 점수를 비교해 정한 모드인가(히스테리시스는 이것만 이어받는다). 단계 a~d 로 정해졌으면 false.
        compared    = [bool]($null -ne $gapRounded -and $claudeKnown -and $mode -ne "no-agy" -and $mode -ne "agy-max")
    }
    Write-QuotaJsonFile (Join-Path $rt "quota-balance.json") $balancePayload

    # 7. 한 줄 요약 (Line)
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add("[한도 균형] $mode")

    if ($claudeKnown) {
        $c5Used = [int][Math]::Round(100.0 - $claude5Rem)
        $cWeekUsed = [int][Math]::Round(100.0 - $claudeWeekRem)
        $c5ResetText = if ($null -ne $claude5Resets) { Format-TimeLeft $claude5Resets $nowUtc } else { "0m" }
        [void]$parts.Add("Claude 5시간 ${c5Used}% 사용(리셋 $c5ResetText)")
        [void]$parts.Add("주간 ${cWeekUsed}%")
    } else {
        [void]$parts.Add("Claude 수치 없음")
    }

    if (-not $agyKnown) {
        [void]$parts.Add("agy 한도를 아직 읽지 못함")
    } else {
        if ($null -ne $gem5Item) {
            $g5ResetText = if ($null -ne $gem5Resets) { Format-TimeLeft $gem5Resets $nowUtc } else { "0m" }
            [void]$parts.Add(("agy Gemini 5시간 {0}% 남음({1})" -f [int][Math]::Round($gem5Rem), $g5ResetText))
            if ($null -ne $gemWeekItem) {
                [void]$parts.Add(("주간 {0}%" -f [int][Math]::Round($gemWeekRem)))
            }
        } elseif ($null -ne $gemWeekItem) {
            [void]$parts.Add(("agy Gemini 주간 {0}% 남음" -f [int][Math]::Round($gemWeekRem)))
        }
        if ($argon -ne "unknown" -and $null -ne $argonRem) {
            [void]$parts.Add(("Argon 주간 {0}%" -f [int][Math]::Round($argonRem)))
        }
        if ($null -ne $gapRaw) {
            $gapInt = [int][Math]::Round($gapRaw)
            $sign = if ($gapInt -gt 0) { "+" } else { "" }
            [void]$parts.Add("차이 ${sign}${gapInt}")
        }
    }

    if ($claudeKnown) {
        [void]$parts.Add("Claude 수치 ${claudeAgeMin}분 전")
    } elseif ($agyKnown) {
        [void]$parts.Add("agy 수치 ${agyAgeMin}분 전")
    }

    $line = ($parts.ToArray()) -join " · "

    # 8. 권고 문구 (Advice)
    $advice = switch ($mode) {
        "agy-more"    { "Claude 한도가 더 빨리 줄고 있다: 파일 2개 이상 작업 · 시험 · 문서 · 코드 탐색 묶음은 위임하고, 컨텍스트가 80k 를 넘으면 위임 절차를 서브에이전트에 맡긴다. 한두 줄 수정은 그대로 직접." }
        "agy-max"     { "Claude 5시간 한도가 거의 찼다: 위임할 수 있는 일은 모두 위임하고 Claude 는 브리프 · 검토 · 사용자 응답만 한다. 컨텍스트 30k 를 넘으면 서브에이전트." }
        "balanced"    { "두 한도가 비슷한 속도로 쓰이고 있다: 평소 규칙대로." }
        "claude-more" { "agy 한도가 더 빨리 줄고 있다: 위임 조건이 맞는 일은 평소대로 위임하되, 같은 결과면 더 가벼운 단계(quick · build)를 고르고 deep · feature 는 꼭 필요할 때만."}
        "no-agy"      { "agy Gemini 한도가 거의 없다: 리셋 전까지 위임하지 않는다." }
    }
    # Claude 수치를 모르는데 agy 가 넉넉해서 agy-more 가 된 경우: "Claude 가 더 빨리 준다"고 단정하지 않는다.
    if ($mode -eq "agy-more" -and -not $claudeKnown) {
        $advice = "Claude 수치는 없지만 agy 한도가 넉넉하다: 파일 2개 이상 작업 · 시험 · 문서 · 코드 탐색 묶음은 위임하고, 컨텍스트가 80k 를 넘으면 위임 절차를 서브에이전트에 맡긴다. 한두 줄 수정은 그대로 직접."
    }
    if ($argon -eq "limited") {
        $advice += " Argon 한도가 빠듯하다: think · feature 는 꼭 필요한 상의만, 작업 분할은 Claude 가 하고 build · build-hard 로."
    }
    # Claude 수치가 없거나 30분이 넘었으면 갱신 방법을 알린다(데스크톱 앱의 사용량 도구로만 읽을 수 있다).
    if (-not $claudeKnown -or ($null -ne $claudeAgeMin -and $claudeAgeMin -gt 30)) {
        $advice += " (Claude 수치 갱신: 일이 있는 요청이면 사용량을 읽고 다음 셸 명령 앞에 quota-balance.ps1 -Claude5hUsed · -Claude5hResetsAt · -ClaudeWeekUsed · -ClaudeWeekResetsAt 를 붙인다)"
    }

    return [PSCustomObject][ordered]@{
        Mode              = $mode
        Gap               = $gapRounded
        ClaudeScore       = $claudeScore
        AgyScore          = $agyScore
        ClaudeKnown       = [bool]$claudeKnown
        ClaudeAgeMin      = $claudeAgeMin
        AgyAgeMin         = $agyAgeMin
        Argon             = $argon
        SubagentThreshold = [int]$threshold
        Line              = $line
        Advice            = $advice
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $rt = Resolve-QuotaRuntimeDir $RuntimeDir
        if ($Claude5hUsed -ge 0 -and $ClaudeWeekUsed -ge 0) {
            Save-ClaudeQuota -RuntimeDir $rt -FiveHourUsed $Claude5hUsed -FiveHourResetsAt $Claude5hResetsAt -WeekUsed $ClaudeWeekUsed -WeekResetsAt $ClaudeWeekResetsAt
        }

        $needAgyRefresh = [bool]$RefreshAgy
        if (-not $needAgyRefresh) {
            $agyData = Read-QuotaJsonFile (Join-Path $rt "agy-quota.json")
            if ($null -eq $agyData -or -not $agyData.checked_at) {
                $needAgyRefresh = $true
            } else {
                $checkedDt = ConvertTo-UtcDateTime $agyData.checked_at
                if ($null -eq $checkedDt -or ([DateTime]::UtcNow - $checkedDt).TotalMinutes -gt 10.0) {
                    $needAgyRefresh = $true
                }
            }
        }
        if ($needAgyRefresh) {
            # 겹쳐 뜬 새로 고침(작업 여러 개가 동시에 끝남 · 질문마다 훅)은 하나만 agy 를 부른다: 2분 안에 시작한 새로 고침이 있으면 건너뛴다.
            # agy 가 응답하지 않아 한도 파일이 계속 오래돼도 2분에 한 번만 시도한다.
            $marker = Join-Path $rt "agy-quota.refreshing"
            $recent = (Test-Path -LiteralPath $marker) -and (((Get-Date) - (Get-Item -LiteralPath $marker).LastWriteTime).TotalMinutes -lt 2)
            if (-not $recent) {
                try { [System.IO.File]::WriteAllText($marker, (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) } catch {}
                $cmd = Get-Command agy -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($cmd -and $cmd.Source) {
                    [void](Update-AgyQuotaCache -RuntimeDir $rt -AgyExe $cmd.Source)
                }
            }
        }

        $result = Get-QuotaBalance -RuntimeDir $rt
        if ($Json) {
            Write-Output (ConvertTo-QuotaReadableJson $result)
        } elseif (-not $Quiet) {
            Write-Output $result.Line
            Write-Output $result.Advice
        }
    } catch {
        # CLI 는 항상 0 으로 종료한다.
    }
    exit 0
}
