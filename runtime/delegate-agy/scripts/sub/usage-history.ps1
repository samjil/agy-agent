# usage-history.ps1
# Claude · agy 의 5시간 / 주간 사용률(%) 이력을 <runtime dir>\usage-history.jsonl 에 누적 기록하고,
# 주간 % 변화량 대비 5시간 % 변화량(주간 한도 = 약 N 세션)을 계산하는 공용 모듈입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "usage-history.ps1")` (불러올 때 부작용 없음)

if ($null -eq $script:UsageHistoryParsedCache) { $script:UsageHistoryParsedCache = @{} }
if ($null -eq $script:SessionsRatioCache) { $script:SessionsRatioCache = @{} }

function ConvertTo-UsageHistoryUtc([string]$Text) {
    $s = ([string]$Text).Trim()
    if (-not $s) { return $null }
    $dt = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
        return $dt.ToUniversalTime()
    }
    return $null
}

function Get-UsageHistoryStamp([string]$RuntimeDir) {
    if (-not $RuntimeDir) { return "" }
    $histPath = Join-Path $RuntimeDir "usage-history.jsonl"
    if (-not (Test-Path -LiteralPath $histPath -PathType Leaf)) { return "" }
    $fi = Get-Item -LiteralPath $histPath -ErrorAction SilentlyContinue
    if ($null -eq $fi) { return "" }
    return ("{0}|{1}" -f [long]$fi.Length, [long]$fi.LastWriteTimeUtc.Ticks)
}

function ConvertTo-UsageHistoryPctInt($Val) {
    if ($null -eq $Val -or ($Val -is [bool])) { return $null }
    $d = 0.0
    if ($Val -is [double] -or $Val -is [float] -or $Val -is [decimal] -or $Val -is [int] -or $Val -is [long] -or $Val -is [short] -or $Val -is [byte]) {
        $d = [double]$Val
    } elseif (-not [double]::TryParse(([string]$Val).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $null
    }
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d) -or $d -lt 0.0 -or $d -gt 100.0) { return $null }
    return [int][math]::Round($d, [System.MidpointRounding]::AwayFromZero)
}

function Find-LastUsageHistoryEntry([string]$HistPath, [string]$Src) {
    if (-not (Test-Path -LiteralPath $HistPath -PathType Leaf)) { return $null }
    $fs = [System.IO.File]::Open($HistPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $len = [long]$fs.Length
        if ($len -le 0) { return $null }

        $tailSize = [Math]::Min($len, 65536L)
        $offset = $len - $tailSize
        [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] $tailSize
        $readTotal = 0
        while ($readTotal -lt $tailSize) {
            $r = $fs.Read($buf, $readTotal, [int]($tailSize - $readTotal))
            if ($r -le 0) { break }
            $readTotal += $r
        }
        $tailText = [System.Text.Encoding]::UTF8.GetString($buf, 0, $readTotal).TrimStart([char]0xFEFF)
        $lines = @($tailText -split "\r?\n" | Where-Object { $_ })
        if ($offset -gt 0 -and $lines.Count -gt 0) {
            # 파일 중간에서 잘린 첫 줄은 온전하지 않을 수 있어 건너뛴다
            $lines = @($lines | Select-Object -Skip 1)
        }
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            try {
                $obj = ConvertFrom-Json -InputObject $lines[$i] -ErrorAction Stop
                if ($null -ne $obj -and [string]$obj.src -eq $Src) { return $obj }
            } catch {}
        }

        if ($offset -gt 0) {
            [void]$fs.Seek(0, [System.IO.SeekOrigin]::Begin)
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true, 4096, $true)
            try {
                $allText = $sr.ReadToEnd().TrimStart([char]0xFEFF)
            } finally {
                $sr.Dispose()
            }
            $allLines = @($allText -split "\r?\n" | Where-Object { $_ })
            for ($i = $allLines.Count - 1; $i -ge 0; $i--) {
                try {
                    $obj = ConvertFrom-Json -InputObject $allLines[$i] -ErrorAction Stop
                    if ($null -ne $obj -and [string]$obj.src -eq $Src) { return $obj }
                } catch {}
            }
        }
        return $null
    } finally {
        $fs.Dispose()
    }
}

# 사용률 이력을 <RuntimeDir>\usage-history.jsonl 에 한 줄 덧붙인다.
# 같은 src 의 마지막 기록과 five · week · five_reset · week_reset 이 모두 같으면 쓰지 않는다.
# 파일 크기가 1MB 를 넘으면 최근 60일 기록만 남기고 원자적으로 다시 쓴다. 절대 예외를 밖으로 던지지 않는다.
function Add-UsageHistory([string]$RuntimeDir, [string]$Src, $FiveUsed, [string]$FiveReset, $WeekUsed, [string]$WeekReset, [datetime]$AtUtc = [datetime]::MinValue) {
    try {
        if (-not $RuntimeDir) { return $false }
        if ($Src -notin @('claude', 'agy')) { return $false }

        $fiveInt = ConvertTo-UsageHistoryPctInt $FiveUsed
        $weekInt = ConvertTo-UsageHistoryPctInt $WeekUsed
        if ($null -eq $fiveInt -or $null -eq $weekInt) { return $false }

        $fiveResetDt = ConvertTo-UsageHistoryUtc $FiveReset
        $weekResetDt = ConvertTo-UsageHistoryUtc $WeekReset
        if ($null -eq $fiveResetDt -or $null -eq $weekResetDt) { return $false }

        $fiveResetIso = $fiveResetDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $weekResetIso = $weekResetDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $at = if ($AtUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $AtUtc.ToUniversalTime() }
        $atIso = $at.ToString("yyyy-MM-ddTHH:mm:ssZ")

        $histPath = Join-Path $RuntimeDir "usage-history.jsonl"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        if (Test-Path -LiteralPath $histPath -PathType Leaf) {
            $last = Find-LastUsageHistoryEntry $histPath $Src
            if ($null -ne $last) {
                $lastFive = ConvertTo-UsageHistoryPctInt $last.five
                $lastWeek = ConvertTo-UsageHistoryPctInt $last.week
                $lastFr = ConvertTo-UsageHistoryUtc ([string]$last.five_reset)
                $lastWr = ConvertTo-UsageHistoryUtc ([string]$last.week_reset)
                if ($null -ne $lastFive -and $null -ne $lastWeek -and $null -ne $lastFr -and $null -ne $lastWr) {
                    if ($lastFive -eq $fiveInt -and $lastWeek -eq $weekInt -and
                        $lastFr.ToString("yyyy-MM-ddTHH:mm:ssZ") -eq $fiveResetIso -and
                        $lastWr.ToString("yyyy-MM-ddTHH:mm:ssZ") -eq $weekResetIso) {
                        return $false
                    }
                }
            }
        }

        if (-not (Test-Path -LiteralPath $RuntimeDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        }

        $entry = [ordered]@{
            src        = $Src
            at         = $atIso
            five       = $fiveInt
            five_reset = $fiveResetIso
            week       = $weekInt
            week_reset = $weekResetIso
        }
        $line = ($entry | ConvertTo-Json -Compress)
        [System.IO.File]::AppendAllText($histPath, ($line + "`n"), $utf8NoBom)

        $fi = Get-Item -LiteralPath $histPath -ErrorAction SilentlyContinue
        if ($null -ne $fi -and $fi.Length -gt 1048576L) {
            $cutoff = $at.AddDays(-60)
            $kept = New-Object System.Collections.Generic.List[string]
            $fs = [System.IO.File]::Open($histPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                try {
                    while ($null -ne ($ln = $sr.ReadLine())) {
                        if (-not $ln) { continue }
                        try {
                            $o = ConvertFrom-Json -InputObject $ln -ErrorAction Stop
                            if ($null -eq $o -or -not $o.at) { continue }
                            $oAt = ConvertTo-UsageHistoryUtc ([string]$o.at)
                            if ($null -ne $oAt -and $oAt -ge $cutoff) {
                                [void]$kept.Add($ln)
                            }
                        } catch {}
                    }
                } finally {
                    $sr.Dispose()
                }
            } finally {
                $fs.Dispose()
            }

            $tmp = "$histPath.$PID.tmp"
            try {
                $rewritten = if ($kept.Count -gt 0) { ($kept.ToArray() -join "`n") + "`n" } else { "" }
                [System.IO.File]::WriteAllText($tmp, $rewritten, $utf8NoBom)
                Remove-Item -LiteralPath $histPath -Force -ErrorAction SilentlyContinue
                [System.IO.File]::Move($tmp, $histPath)
            } finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }

        return $true
    } catch {
        return $false
    }
}

function Read-UsageHistoryLines([string]$RuntimeDir) {
    $out = New-Object System.Collections.ArrayList
    if (-not $RuntimeDir) { return @() }
    $histPath = Join-Path $RuntimeDir "usage-history.jsonl"
    if (-not (Test-Path -LiteralPath $histPath -PathType Leaf)) { return @() }

    $idx = 0
    $fs = [System.IO.File]::Open($histPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        try {
            while ($null -ne ($ln = $sr.ReadLine())) {
                if (-not $ln -or -not $ln.Trim()) { continue }
                $o = $null
                try { $o = ConvertFrom-Json -InputObject $ln -ErrorAction Stop } catch { continue }
                if ($null -eq $o) { continue }
                $srcVal = [string]$o.src
                if ($srcVal -notin @('claude', 'agy')) { continue }
                $atDt = ConvertTo-UsageHistoryUtc ([string]$o.at)
                $frDt = ConvertTo-UsageHistoryUtc ([string]$o.five_reset)
                $wrDt = ConvertTo-UsageHistoryUtc ([string]$o.week_reset)
                $fiveInt = ConvertTo-UsageHistoryPctInt $o.five
                $weekInt = ConvertTo-UsageHistoryPctInt $o.week
                if ($null -eq $atDt -or $null -eq $frDt -or $null -eq $wrDt -or $null -eq $fiveInt -or $null -eq $weekInt) { continue }
                [void]$out.Add([pscustomobject]@{
                    Idx          = $idx
                    AtUtc        = $atDt
                    FiveResetUtc = $frDt
                    WeekResetUtc = $wrDt
                    Item         = [ordered]@{
                        src        = $srcVal
                        at         = $atDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        five       = $fiveInt
                        five_reset = $frDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        week       = $weekInt
                        week_reset = $wrDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                })
                $idx++
            }
        } finally {
            $sr.Dispose()
        }
    } catch {
        return @()
    } finally {
        $fs.Dispose()
    }

    return @($out.ToArray() | Sort-Object AtUtc, Idx | ForEach-Object { $_.Item })
}

function Read-UsageHistory([string]$RuntimeDir, [string]$Src = "", [datetime]$UntilUtc = [datetime]::MinValue) {
    $all = @(Read-UsageHistoryLines $RuntimeDir)
    if ($all.Count -eq 0) { return @() }
    $hasUntil = ($UntilUtc -ne [datetime]::MinValue)
    $untilNorm = if ($hasUntil) { $UntilUtc.ToUniversalTime() } else { [datetime]::MaxValue }

    $filtered = New-Object System.Collections.ArrayList
    foreach ($item in $all) {
        if ($Src -and [string]$item.src -ne $Src) { continue }
        if ($hasUntil) {
            $dt = ConvertTo-UsageHistoryUtc ([string]$item.at)
            if ($null -eq $dt -or $dt -gt $untilNorm) { continue }
        }
        [void]$filtered.Add($item)
    }
    return @($filtered.ToArray())
}

# 주간 % 증가 구간(주간 변화점 사이)의 (5시간 % 증가 합) / (주간 % 증가 합) 으로 주간당 세션 수를 계산한다.
# 연속 5시간 안전 체인(동일 창 또는 리셋 직전 15분 이내 측정 후 정확히 +5h)으로 분할하여 건너뛴 창을 가로질러 합산하지 않는다.
function Get-SessionsRatio($Samples, [datetime]$UntilUtc = [datetime]::MinValue, [datetime]$NowUtc = [datetime]::MinValue, [int]$MinWeekPoints = 3, [int]$MinFivePoints = 1) {
    $hasUpper = ($UntilUtc -ne [datetime]::MinValue)
    $endUtc = if ($hasUpper) {
        $UntilUtc.ToUniversalTime()
    } elseif ($NowUtc -ne [datetime]::MinValue) {
        $NowUtc.ToUniversalTime()
    } else {
        [datetime]::UtcNow
    }
    $minUtc = $endUtc.AddDays(-14)

    $list = New-Object System.Collections.ArrayList
    $idx = 0
    foreach ($s in @($Samples)) {
        if ($null -eq $s) { continue }
        $atVal = $null; $fiveVal = $null; $frVal = $null; $weekVal = $null; $wrVal = $null
        if ($s -is [System.Collections.IDictionary]) {
            if ($s.Contains('at')) { $atVal = $s['at'] }
            if ($s.Contains('five')) { $fiveVal = $s['five'] }
            if ($s.Contains('five_reset')) { $frVal = $s['five_reset'] }
            if ($s.Contains('week')) { $weekVal = $s['week'] }
            if ($s.Contains('week_reset')) { $wrVal = $s['week_reset'] }
        } else {
            $atVal = $s.at
            $fiveVal = $s.five
            $frVal = $s.five_reset
            $weekVal = $s.week
            $wrVal = $s.week_reset
        }
        $atDt = ConvertTo-UsageHistoryUtc ([string]$atVal)
        $frDt = ConvertTo-UsageHistoryUtc ([string]$frVal)
        $wrDt = ConvertTo-UsageHistoryUtc ([string]$wrVal)
        $fiveInt = ConvertTo-UsageHistoryPctInt $fiveVal
        $weekInt = ConvertTo-UsageHistoryPctInt $weekVal
        if ($null -eq $atDt -or $null -eq $frDt -or $null -eq $wrDt -or $null -eq $fiveInt -or $null -eq $weekInt) { continue }
        if ($atDt -lt $minUtc) { continue }
        if ($hasUpper -and $atDt -gt $endUtc) { continue }

        [void]$list.Add([pscustomobject]@{
            Idx          = $idx
            AtUtc        = $atDt
            Five         = $fiveInt
            FiveResetUtc = $frDt
            Week         = $weekInt
            WeekResetUtc = $wrDt
        })
        $idx++
    }

    if ($list.Count -lt 3) { return $null }
    $sorted = @($list.ToArray() | Sort-Object AtUtc, Idx)

    # 주간 창(week_reset 2분 이내 허용) 별로 묶는다
    $windows = New-Object System.Collections.ArrayList
    $curWin = $null
    $curWinReset = [datetime]::MinValue
    foreach ($item in $sorted) {
        if ($null -eq $curWin -or [math]::Abs(($item.WeekResetUtc - $curWinReset).TotalSeconds) -gt 120.0) {
            $curWin = New-Object System.Collections.ArrayList
            [void]$windows.Add($curWin)
            $curWinReset = $item.WeekResetUtc
        }
        [void]$curWin.Add($item)
    }

    $totalWeekPoints = 0
    $totalFivePoints = 0
    $fromUtc = $null
    $toUtc = $null
    # 대체 계산(처음 · 끝 기록): 체인의 첫 샘플과 끝 샘플만 쓴다
    $fbWeekPoints = 0
    $fbFivePoints = 0
    $fbFrom = $null
    $fbTo = $null

    foreach ($win in $windows) {
        if ($win.Count -lt 2) { continue }

        # 연속 5시간 안전 체인으로 분할한다 (100% 포화 끝점 제외, 건너뛴 5시간 창에서 체인 끊기)
        $chains = New-Object System.Collections.ArrayList
        $curChain = $null
        foreach ($item in $win) {
            if ($item.Five -ge 100 -or $item.Week -ge 100) {
                $curChain = $null
                continue
            }
            if ($null -eq $curChain) {
                $curChain = New-Object System.Collections.ArrayList
                [void]$chains.Add($curChain)
                [void]$curChain.Add($item)
                continue
            }
            $prev = $curChain[$curChain.Count - 1]
            $frDiff = ($item.FiveResetUtc - $prev.FiveResetUtc).TotalSeconds
            $sameFive = ([math]::Abs($frDiff) -le 120.0)
            $nextFive = ($frDiff -ge 17880.0 -and $frDiff -le 18120.0)
            $canBridge = $false
            if ($nextFive) {
                $resetBoundary = $item.FiveResetUtc.AddHours(-5)
                $gapToResetMin = ($resetBoundary - $prev.AtUtc).TotalMinutes
                $canBridge = ($gapToResetMin -le 15.0 -and $gapToResetMin -ge -2.0)
            }
            if ($sameFive -or $canBridge) {
                [void]$curChain.Add($item)
            } else {
                $curChain = New-Object System.Collections.ArrayList
                [void]$chains.Add($curChain)
                [void]$curChain.Add($item)
            }
        }

        foreach ($ch in $chains) {
            if ($ch.Count -ge 2) {
                $fbW = $ch[$ch.Count - 1].Week - $ch[0].Week
                if ($fbW -gt 0) {
                    $fbF = 0
                    for ($k = 1; $k -lt $ch.Count; $k++) {
                        $a = $ch[$k - 1]
                        $b = $ch[$k]
                        if ([math]::Abs(($b.FiveResetUtc - $a.FiveResetUtc).TotalSeconds) -le 120.0) {
                            $d = $b.Five - $a.Five
                            if ($d -gt 0) { $fbF += $d }
                        } elseif ($b.Five -gt 0) {
                            $fbF += $b.Five
                        }
                    }
                    $fbWeekPoints += $fbW
                    $fbFivePoints += $fbF
                    if ($null -eq $fbFrom -or $ch[0].AtUtc -lt $fbFrom) { $fbFrom = $ch[0].AtUtc }
                    if ($null -eq $fbTo -or $ch[$ch.Count - 1].AtUtc -gt $fbTo) { $fbTo = $ch[$ch.Count - 1].AtUtc }
                }
            }
            if ($win.Count -lt 3) { continue }
            if ($ch.Count -lt 3) { continue }
            $cps = New-Object System.Collections.ArrayList
            for ($i = 1; $i -lt $ch.Count; $i++) {
                if ($ch[$i].Week -gt $ch[$i - 1].Week) {
                    [void]$cps.Add($i)
                }
            }
            if ($cps.Count -lt 2) { continue }

            $firstIdx = [int]$cps[0]
            $lastIdx = [int]$cps[$cps.Count - 1]
            $wPts = $ch[$lastIdx].Week - $ch[$firstIdx].Week
            if ($wPts -le 0) { continue }

            $fPts = 0
            for ($k = $firstIdx + 1; $k -le $lastIdx; $k++) {
                $a = $ch[$k - 1]
                $b = $ch[$k]
                if ([math]::Abs(($b.FiveResetUtc - $a.FiveResetUtc).TotalSeconds) -le 120.0) {
                    $delta = $b.Five - $a.Five
                    if ($delta -gt 0) { $fPts += $delta }
                } else {
                    # 직전 샘플이 리셋 15분 이내 측정이고 정확히 +5h 인 안전 연결: 새 창은 0% 에서 시작하므로 b.five 를 더한다.
                    if ($b.Five -gt 0) { $fPts += $b.Five }
                }
            }

            $totalWeekPoints += $wPts
            $totalFivePoints += $fPts
            $winFrom = $ch[$firstIdx].AtUtc
            $winTo = $ch[$lastIdx].AtUtc
            if ($null -eq $fromUtc -or $winFrom -lt $fromUtc) { $fromUtc = $winFrom }
            if ($null -eq $toUtc -or $winTo -gt $toUtc) { $toUtc = $winTo }
        }
    }

    if ($totalWeekPoints -lt $MinWeekPoints -or $totalFivePoints -lt $MinFivePoints -or $totalFivePoints -le 0) {
        # 변화점 방식이 기준에 못 미치면 처음 · 끝 기록 방식으로 대체한다 (주간 10%p 이상, 5시간 20%p 이상)
        $fbMinW = [math]::Max(10, $MinWeekPoints)
        $fbMinF = [math]::Max(20, $MinFivePoints)
        if ($fbWeekPoints -lt $fbMinW -or $fbFivePoints -lt $fbMinF -or $fbFivePoints -le 0) { return $null }
        return [ordered]@{
            ratio       = [math]::Round(($fbFivePoints / [double]$fbWeekPoints), 1, [System.MidpointRounding]::AwayFromZero)
            five_points = [int]$fbFivePoints
            week_points = [int]$fbWeekPoints
            from        = $fbFrom.ToString("yyyy-MM-ddTHH:mm:ssZ")
            to          = $fbTo.ToString("yyyy-MM-ddTHH:mm:ssZ")
            basis       = "endpoints"
        }
    }

    $ratioVal = [math]::Round(($totalFivePoints / [double]$totalWeekPoints), 1, [System.MidpointRounding]::AwayFromZero)
    return [ordered]@{
        ratio       = $ratioVal
        five_points = [int]$totalFivePoints
        week_points = [int]$totalWeekPoints
        from        = $fromUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        to          = $toUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        basis       = "change_points"
    }
}

# usage-history.jsonl 이 아직 없을 때 기존 task_quota 행(agy)과 현재 claude-limits.json(claude)으로 초기 이력을 한 번 채운다.
function Initialize-UsageHistorySeed([string]$RuntimeDir, [string]$DbPath = "") {
    try {
        if (-not $RuntimeDir) { return }
        $histPath = Join-Path $RuntimeDir "usage-history.jsonl"
        if (Test-Path -LiteralPath $histPath -PathType Leaf) { return }

        if ($DbPath -and (Test-Path -LiteralPath $DbPath -PathType Leaf) -and (Get-Command Get-TaskQuotaMap -ErrorAction SilentlyContinue)) {
            $qMap = (Get-TaskQuotaMap $DbPath)
            if ($qMap -and $qMap.Count -gt 0) {
                $rows = @($qMap.Values | Sort-Object { [string]$_.measured_at })
                foreach ($r in $rows) {
                    $mDt = ConvertTo-UsageHistoryUtc ([string]$r.measured_at)
                    if ($null -eq $mDt) { continue }
                    if ($null -eq $r.five_used -or -not $r.five_reset -or $null -eq $r.week_used -or -not $r.week_reset) { continue }
                    [void](Add-UsageHistory -RuntimeDir $RuntimeDir -Src "agy" -FiveUsed $r.five_used -FiveReset ([string]$r.five_reset) -WeekUsed $r.week_used -WeekReset ([string]$r.week_reset) -AtUtc $mDt)
                }
            }
        }

        $cLimitsFile = Join-Path $RuntimeDir "claude-limits.json"
        if (Test-Path -LiteralPath $cLimitsFile -PathType Leaf) {
            try {
                $raw = [System.IO.File]::ReadAllText($cLimitsFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                if ($raw.Trim()) {
                    $obj = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                    if ($null -ne $obj -and $obj.PSObject.Properties['five_hour'] -and $obj.PSObject.Properties['seven_day'] -and $null -ne $obj.five_hour -and $null -ne $obj.seven_day) {
                        $atDt = if ($obj.PSObject.Properties['checked_at'] -and $obj.checked_at) { ConvertTo-UsageHistoryUtc ([string]$obj.checked_at) } else { $null }
                        if ($null -eq $atDt) { $atDt = [datetime]::UtcNow }
                        [void](Add-UsageHistory -RuntimeDir $RuntimeDir -Src "claude" -FiveUsed $obj.five_hour.used_pct -FiveReset ([string]$obj.five_hour.resets_at) -WeekUsed $obj.seven_day.used_pct -WeekReset ([string]$obj.seven_day.resets_at) -AtUtc $atDt)
                    }
                }
            } catch {}
        }
    } catch {}
}

# 이력 파일의 크기+수정시각 도장과 (src, 분 단위 올림 UntilUtc, 임계치) 키로 세션 환산 계산을 캐시한다.
function Get-CachedSessionsRatio([string]$RuntimeDir, [string]$Src, [datetime]$UntilUtc = [datetime]::MinValue, [datetime]$NowUtc = [datetime]::MinValue, [int]$MinWeekPoints = 0, [int]$MinFivePoints = 0) {
    if (-not $RuntimeDir -or $Src -notin @('claude', 'agy')) { return $null }
    $stamp = Get-UsageHistoryStamp $RuntimeDir
    if (-not $stamp) { return $null }

    $effMinW = if ($MinWeekPoints -gt 0) { $MinWeekPoints } else { 5 }
    $effMinF = if ($MinFivePoints -gt 0) { $MinFivePoints } else { 20 }

    $dirKey = try { [System.IO.Path]::GetFullPath($RuntimeDir).ToLowerInvariant() } catch { $RuntimeDir.ToLowerInvariant() }
    $parsedEntry = if ($script:UsageHistoryParsedCache.ContainsKey($dirKey)) { $script:UsageHistoryParsedCache.Item($dirKey) } else { $null }
    if (-not $parsedEntry -or $parsedEntry.Stamp -ne $stamp) {
        $all = @(Read-UsageHistoryLines $RuntimeDir)
        $bySrc = @{
            claude = @($all | Where-Object { $_.src -eq 'claude' })
            agy    = @($all | Where-Object { $_.src -eq 'agy' })
        }
        $parsedEntry = @{ Stamp = $stamp; BySrc = $bySrc }
        $script:UsageHistoryParsedCache[$dirKey] = $parsedEntry
    }

    $ratioEntry = if ($script:SessionsRatioCache.ContainsKey($dirKey)) { $script:SessionsRatioCache.Item($dirKey) } else { $null }
    if (-not $ratioEntry -or $ratioEntry.Stamp -ne $stamp) {
        $ratioEntry = @{ Stamp = $stamp; Entries = @{} }
        $script:SessionsRatioCache[$dirKey] = $ratioEntry
    }

    $hasUpper = ($UntilUtc -ne [datetime]::MinValue)
    $uKey = ""
    $evalUntil = [datetime]::MinValue
    $evalNow = [datetime]::MinValue
    if ($hasUpper) {
        $u = $UntilUtc.ToUniversalTime()
        $rem = $u.Ticks % 600000000L
        $roundedU = if ($rem -gt 0) { [datetime]::new($u.Ticks - $rem + 600000000L, [System.DateTimeKind]::Utc) } else { $u }
        $uKey = "{0}|{1}|{2}|{3}" -f $Src, $roundedU.ToString("yyyy-MM-ddTHH:mm"), $effMinW, $effMinF
        $evalUntil = $roundedU
    } else {
        $evalNow = if ($NowUtc -ne [datetime]::MinValue) { $NowUtc.ToUniversalTime() } else { [datetime]::UtcNow }
        $uKey = "{0}|live|{1}|{2}|{3}" -f $Src, $evalNow.ToString("yyyy-MM-ddTHH:mm"), $effMinW, $effMinF
    }

    if ($ratioEntry.Entries.ContainsKey($uKey)) {
        return $ratioEntry.Entries.Item($uKey)
    }

    $srcSamples = @($parsedEntry.BySrc.Item($Src))
    $res = if ($hasUpper) {
        (Get-SessionsRatio -Samples $srcSamples -UntilUtc $evalUntil -MinWeekPoints $effMinW -MinFivePoints $effMinF)
    } else {
        (Get-SessionsRatio -Samples $srcSamples -NowUtc $evalNow -MinWeekPoints $effMinW -MinFivePoints $effMinF)
    }

    if ($ratioEntry.Entries.Count -gt 512) { $ratioEntry.Entries.Clear() }
    $ratioEntry.Entries[$uKey] = $res
    return $res
}
