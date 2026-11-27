# agy-account-quotas.ps1
# Claude(claude-limits.json) · 주 계정(agy-quota.json) · 부계정 슬롯(sub-quota.json / sub_quota DB) 의
# 남은 한도(remaining_pct)와 리셋 시각을 통합 스냅샷으로 수집하고, 만료된 리셋 보정 및 신호 기반 재조회를 제공한다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-account-quotas.ps1")`

$script:AgyAccountQuotasSubDir = $PSScriptRoot

if (-not (Get-Command Get-AgyModelConfig -ErrorAction SilentlyContinue)) {
    $p = Join-Path $script:AgyAccountQuotasSubDir "agy-models.ps1"
    if (Test-Path -LiteralPath $p -PathType Leaf) { . $p }
}
if (-not (Get-Command ConvertTo-AgyUtcDateTime -ErrorAction SilentlyContinue)) {
    $p = Join-Path $script:AgyAccountQuotasSubDir "agy-quota.ps1"
    if (Test-Path -LiteralPath $p -PathType Leaf) { . $p }
}
if (-not (Get-Command Get-AgySubSlotLayout -ErrorAction SilentlyContinue)) {
    $p = Join-Path $script:AgyAccountQuotasSubDir "agy-sub-bridge.ps1"
    if (Test-Path -LiteralPath $p -PathType Leaf) { . $p }
}
if (-not (Get-Command Get-LatestSubQuotas -ErrorAction SilentlyContinue)) {
    $p = Join-Path $script:AgyAccountQuotasSubDir "agy-db.ps1"
    if (Test-Path -LiteralPath $p -PathType Leaf) { . $p }
}

function Read-AgyAccountQuotaJson([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    for ($try = 0; $try -lt 3; $try++) {
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
                try {
                    $raw = $sr.ReadToEnd()
                } finally {
                    $sr.Dispose()
                }
            } finally {
                $fs.Dispose()
            }
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
            $raw = $raw.TrimStart([char]0xFEFF)
            return ($raw | ConvertFrom-Json -ErrorAction Stop)
        } catch [System.IO.IOException] {
            if ($try -lt 2) { Start-Sleep -Milliseconds 20 }
        } catch {
            return $null
        }
    }
    return $null
}

function ConvertTo-AgyAccountUtc([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Get-AgyAccountProp($Obj, [string]$Key, $Default = $null) {
    if ($null -eq $Obj -or -not $Key) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        foreach ($k in $Obj.Keys) {
            if ([string]::Equals([string]$k, $Key, [StringComparison]::OrdinalIgnoreCase)) { return $Obj[$k] }
        }
        return $Default
    }
    if ($Obj.PSObject) {
        foreach ($p in $Obj.PSObject.Properties) {
            if ([string]::Equals($p.Name, $Key, [StringComparison]::OrdinalIgnoreCase)) { return $p.Value }
        }
    }
    return $Default
}

function Get-AgyQuotaBottleneck($FiveWindow, $WeeklyWindow) {
    $vals = New-Object System.Collections.Generic.List[double]
    foreach ($w in @($FiveWindow, $WeeklyWindow)) {
        if ($null -eq $w) { continue }
        $avail = [bool](Get-AgyAccountProp $w "available" $false)
        $rem = Get-AgyAccountProp $w "remaining_pct" $null
        if ($avail -and $null -ne $rem) {
            [void]$vals.Add([double]$rem)
        }
    }
    if ($vals.Count -eq 0) { return $null }
    $minVal = $vals[0]
    for ($i = 1; $i -lt $vals.Count; $i++) {
        if ($vals[$i] -lt $minVal) { $minVal = $vals[$i] }
    }
    return [Math]::Round($minVal, 2)
}

function Test-AgyPrimaryWatcherOnline([string]$RuntimeDir) {
    if ([string]::IsNullOrWhiteSpace($RuntimeDir) -or -not (Test-Path -LiteralPath $RuntimeDir -PathType Container)) { return $false }
    foreach ($lf in @(Get-ChildItem -LiteralPath $RuntimeDir -Filter "watcher_*.lock" -File -ErrorAction SilentlyContinue)) {
        $raw = ""
        try {
            $fs = New-Object System.IO.FileStream($lf.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
                try { $raw = $sr.ReadToEnd().Trim() } finally { $sr.Dispose() }
            } finally { $fs.Dispose() }
        } catch { $raw = "" }
        $pidVal = 0
        if ([int]::TryParse($raw, [ref]$pidVal) -and $pidVal -gt 0) {
            $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -in @('powershell', 'pwsh')) {
                $same = $true
                try { $same = ($p.StartTime -le $lf.LastWriteTime.AddSeconds(5)) } catch { $same = $true }
                if ($same) { return $true }
            }
        }
    }
    return $false
}

function Test-AgySubSlotOnline([hashtable]$Layout, [datetime]$NowUtc) {
    if ($null -eq $Layout) { return $false }
    if (Get-Command Get-AgySubSlotHeartbeatUtc -ErrorAction SilentlyContinue) {
        $hbUtc = Get-AgySubSlotHeartbeatUtc $Layout
        if ($null -ne $hbUtc) {
            $age = ($NowUtc.ToUniversalTime() - $hbUtc.ToUniversalTime()).TotalSeconds
            if ($age -lt 90) { return $true }
        }
    }
    $lockCands = New-Object System.Collections.ArrayList
    $lockFile = [string]$Layout["LockFile"]
    $statusDir = [string]$Layout["StatusDir"]
    if ($lockFile -and (Test-Path -LiteralPath $lockFile -PathType Leaf)) {
        $li = Get-Item -LiteralPath $lockFile -ErrorAction SilentlyContinue
        if ($null -ne $li) { [void]$lockCands.Add($li) }
    } elseif ($statusDir -and (Test-Path -LiteralPath $statusDir -PathType Container)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $statusDir -Filter "sub-lock_*.pid" -File -ErrorAction SilentlyContinue)) {
            [void]$lockCands.Add($f)
        }
    }
    foreach ($lf in $lockCands) {
        $raw = ""
        try {
            $fs = New-Object System.IO.FileStream($lf.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
                try { $raw = $sr.ReadToEnd().Trim() } finally { $sr.Dispose() }
            } finally { $fs.Dispose() }
        } catch { $raw = "" }
        $pidVal = 0
        if ([int]::TryParse($raw, [ref]$pidVal) -and $pidVal -gt 0) {
            $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -in @('powershell', 'pwsh')) {
                $same = $true
                try { $same = ($p.StartTime -le $lf.LastWriteTime.AddSeconds(5)) } catch { $same = $true }
                if ($same) { return $true }
            }
        }
    }
    return $false
}

function ConvertTo-AgyQuotaWindow {
    param(
        $UsedPct = $null,
        [string]$ResetIso = "",
        [datetime]$NowUtc = [datetime]::MinValue,
        [switch]$IdleWhenMissing
    )

    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $hasUsed = $false
    $uRaw = 0.0
    if ($null -ne $UsedPct -and -not ($UsedPct -is [string] -and [string]::IsNullOrWhiteSpace($UsedPct))) {
        if ($UsedPct -is [double] -or $UsedPct -is [int] -or $UsedPct -is [long] -or $UsedPct -is [decimal] -or $UsedPct -is [float]) {
            $uRaw = [double]$UsedPct
            $hasUsed = $true
        } else {
            $parsedD = 0.0
            if ([double]::TryParse(([string]$UsedPct).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedD)) {
                $uRaw = $parsedD
                $hasUsed = $true
            }
        }
        if ($hasUsed -and ([double]::IsNaN($uRaw) -or [double]::IsInfinity($uRaw))) {
            $hasUsed = $false
        }
    }

    $resetTrim = if ($null -ne $ResetIso) { ([string]$ResetIso).Trim() } else { "" }
    $resetUtc = ConvertTo-AgyAccountUtc $resetTrim

    if ($null -ne $resetUtc) {
        if ($resetUtc -le $now) {
            return [ordered]@{
                available     = $true
                remaining_pct = 100.0
                used_pct      = 0.0
                reset_at      = $resetTrim
                reset_in_sec  = 0
                reset_passed  = $true
                idle_window   = $false
            }
        }
        if ($hasUsed) {
            $u = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, $uRaw)), 2)
            $rem = [Math]::Round(100.0 - $u, 2)
            $inSec = [int][Math]::Max(0, [Math]::Round(($resetUtc - $now).TotalSeconds))
            return [ordered]@{
                available     = $true
                remaining_pct = $rem
                used_pct      = $u
                reset_at      = $resetTrim
                reset_in_sec  = $inSec
                reset_passed  = $false
                idle_window   = $false
            }
        }
    }

    if ($hasUsed) {
        $u = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, $uRaw)), 2)
        $rem = [Math]::Round(100.0 - $u, 2)
        return [ordered]@{
            available     = $true
            remaining_pct = $rem
            used_pct      = $u
            reset_at      = ""
            reset_in_sec  = $null
            reset_passed  = $false
            idle_window   = $false
        }
    }

    if ($IdleWhenMissing) {
        return [ordered]@{
            available     = $true
            remaining_pct = 100.0
            used_pct      = 0.0
            reset_at      = ""
            reset_in_sec  = $null
            reset_passed  = $false
            idle_window   = $true
        }
    }

    return [ordered]@{
        available     = $false
        remaining_pct = $null
        used_pct      = $null
        reset_at      = ""
        reset_in_sec  = $null
        reset_passed  = $false
        idle_window   = $false
    }
}

function Get-AgyAccountQuotasSnapshot {
    param(
        [string]$RuntimeDir,
        [string]$DbPath = "",
        [string]$ConfigDir = "",
        [datetime]$NowUtc = [datetime]::MinValue,
        $SharedState = $null
    )

    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $accounts = New-Object System.Collections.ArrayList

    $priRefreshProc = $null
    $priRefreshAt = $null
    $claudeRefreshProc = $null
    $claudeRefreshAt = $null
    $lastManualAt = $null
    if ($SharedState -is [System.Collections.IDictionary]) {
        $hasSync = ($null -ne $SharedState.SyncRoot)
        if ($hasSync) { [System.Threading.Monitor]::Enter($SharedState.SyncRoot) }
        try {
            if ($SharedState.Contains("PrimaryRefreshProc")) { $priRefreshProc = $SharedState["PrimaryRefreshProc"] }
            if ($SharedState.Contains("PrimaryRefreshAt")) { $priRefreshAt = $SharedState["PrimaryRefreshAt"] }
            if ($SharedState.Contains("ClaudeRefreshProc")) { $claudeRefreshProc = $SharedState["ClaudeRefreshProc"] }
            if ($SharedState.Contains("ClaudeRefreshAt")) { $claudeRefreshAt = $SharedState["ClaudeRefreshAt"] }
            if ($SharedState.Contains("LastManualRefreshAt")) { $lastManualAt = $SharedState["LastManualRefreshAt"] }
        } finally {
            if ($hasSync) { [System.Threading.Monitor]::Exit($SharedState.SyncRoot) }
        }
    }

    # 1. Claude (claude-limits.json: used_pct -> remaining_pct = 100 - used_pct)
    $claudePath = if ($RuntimeDir) { Join-Path $RuntimeDir "claude-limits.json" } else { "" }
    $claudeObj = Read-AgyAccountQuotaJson $claudePath
    $hasClaudeFile = ($null -ne $claudeObj)
    $claudeMeasured = if ($hasClaudeFile) { [string](Get-AgyAccountProp $claudeObj "checked_at" "") } else { "" }
    $claudeMeasuredUtc = ConvertTo-AgyAccountUtc $claudeMeasured
    $c5Obj = if ($hasClaudeFile) { Get-AgyAccountProp $claudeObj "five_hour" $null } else { $null }
    $c7Obj = if ($hasClaudeFile) { Get-AgyAccountProp $claudeObj "seven_day" $null } else { $null }
    $c5Used = if ($null -ne $c5Obj) { Get-AgyAccountProp $c5Obj "used_pct" $null } else { $null }
    $c5Reset = if ($null -ne $c5Obj) { [string](Get-AgyAccountProp $c5Obj "resets_at" "") } else { "" }
    $c7Used = if ($null -ne $c7Obj) { Get-AgyAccountProp $c7Obj "used_pct" $null } else { $null }
    $c7Reset = if ($null -ne $c7Obj) { [string](Get-AgyAccountProp $c7Obj "resets_at" "") } else { "" }

    $claudeFive = ConvertTo-AgyQuotaWindow -UsedPct $c5Used -ResetIso $c5Reset -NowUtc $now -IdleWhenMissing:$hasClaudeFile
    $claudeWeek = ConvertTo-AgyQuotaWindow -UsedPct $c7Used -ResetIso $c7Reset -NowUtc $now
    $claudeCliAvailable = $false
    if (Get-Command Find-ClaudeCliExecutable -ErrorAction SilentlyContinue) {
        try { $claudeCliAvailable = [bool](Find-ClaudeCliExecutable) } catch { $claudeCliAvailable = $false }
    }
    $claudeCliUnsupported = $false
    if (Get-Command Test-ClaudeCliUsageUnsupported -ErrorAction SilentlyContinue) {
        try { $claudeCliUnsupported = [bool](Test-ClaudeCliUsageUnsupported $RuntimeDir $now) } catch { $claudeCliUnsupported = $false }
    }
    $claudeCliUsable = $claudeCliAvailable -and -not $claudeCliUnsupported
    $claudeProcAlive = $false
    if ($null -ne $claudeRefreshProc) {
        try { $claudeProcAlive = (-not $claudeRefreshProc.HasExited) } catch { $claudeProcAlive = $false }
    }
    $claudeRefreshing = $claudeProcAlive
    if (-not $claudeRefreshing -and $claudeRefreshAt -is [datetime]) {
        $cLaunchUtc = $claudeRefreshAt.ToUniversalTime()
        $cSinceLaunch = ($now - $cLaunchUtc).TotalSeconds
        if ($cSinceLaunch -ge 0 -and $cSinceLaunch -lt 45 -and ($null -eq $claudeMeasuredUtc -or $claudeMeasuredUtc -lt $cLaunchUtc)) {
            $claudeRefreshing = $true
        }
    }
    $claudeRawSource = if ($hasClaudeFile) { ([string](Get-AgyAccountProp $claudeObj "source" "")).Trim() } else { "" }
    $claudeSource = if ($claudeRawSource -ieq "claude-cli") {
        "cli"
    } elseif ($claudeRawSource -ieq "desktop-tool") {
        "desktop"
    } else {
        ""
    }
    $claudeNote = if ($claudeSource -eq "cli") {
        "Claude CLI 에서 조회"
    } elseif ($claudeSource -eq "desktop") {
        "Claude Desktop 에서 기록"
    } elseif ($claudeCliUsable) {
        "Claude CLI /usage 실시간 조회"
    } elseif ($claudeCliUnsupported) {
        "Claude 세션 실행 시 자동 기록 (CLI /usage 미지원)"
    } else {
        "Claude Code 실행 시 자동 기록"
    }
    [void]$accounts.Add([ordered]@{
        id                       = "claude"
        short_label              = "C"
        label                    = "Claude"
        sub_label                = ""
        provider                 = "claude"
        source                   = $claudeSource
        status                   = $(if ($hasClaudeFile -or $claudeCliAvailable) { "online" } else { "empty" })
        refreshable              = [bool]$claudeCliUsable
        refreshing               = [bool]$claudeRefreshing
        note                     = $claudeNote
        measured_at              = $claudeMeasured
        five_hour                = $claudeFive
        weekly                   = $claudeWeek
        bottleneck_remaining_pct = (Get-AgyQuotaBottleneck $claudeFive $claudeWeek)
    })

    # 2. Primary (agy-quota.json: pct is REMAINING % -> used_pct = 100 - pct)
    $priStatus = if (Test-AgyPrimaryWatcherOnline $RuntimeDir) { "online" } else { "idle" }
    $priPath = if ($RuntimeDir) { Join-Path $RuntimeDir "agy-quota.json" } else { "" }
    $priObj = Read-AgyAccountQuotaJson $priPath
    $priMeasured = if ($null -ne $priObj) { [string](Get-AgyAccountProp $priObj "checked_at" "") } else { "" }
    $priMeasuredUtc = ConvertTo-AgyAccountUtc $priMeasured

    $p5Obj = if ($null -ne $priObj) { Get-AgyAccountProp $priObj "gemini_5h" $null } else { $null }
    $pwObj = if ($null -ne $priObj) { Get-AgyAccountProp $priObj "gemini_weekly" $null } else { $null }
    $p5Pct = if ($null -ne $p5Obj) { Get-AgyAccountProp $p5Obj "pct" $null } else { $null }
    $p5Used = if ($null -ne $p5Pct) { 100.0 - [double]$p5Pct } else { $null }
    $p5Reset = if ($null -ne $p5Obj) { [string](Get-AgyAccountProp $p5Obj "reset" "") } else { "" }
    $pwPct = if ($null -ne $pwObj) { Get-AgyAccountProp $pwObj "pct" $null } else { $null }
    $pwUsed = if ($null -ne $pwPct) { 100.0 - [double]$pwPct } else { $null }
    $pwReset = if ($null -ne $pwObj) { [string](Get-AgyAccountProp $pwObj "reset" "") } else { "" }

    $priFive = ConvertTo-AgyQuotaWindow -UsedPct $p5Used -ResetIso $p5Reset -NowUtc $now
    $priWeek = ConvertTo-AgyQuotaWindow -UsedPct $pwUsed -ResetIso $pwReset -NowUtc $now

    $priProcAlive = $false
    if ($null -ne $priRefreshProc) {
        try { $priProcAlive = (-not $priRefreshProc.HasExited) } catch { $priProcAlive = $false }
    }
    $priRefreshing = $priProcAlive
    if (-not $priRefreshing -and $priRefreshAt -is [datetime]) {
        $launchUtc = $priRefreshAt.ToUniversalTime()
        $sinceLaunch = ($now - $launchUtc).TotalSeconds
        if ($sinceLaunch -ge 0 -and $sinceLaunch -lt 45 -and ($null -eq $priMeasuredUtc -or $priMeasuredUtc -lt $launchUtc)) {
            $priRefreshing = $true
        }
    }

    [void]$accounts.Add([ordered]@{
        id                       = "primary"
        short_label              = "A"
        label                    = "Agy"
        sub_label                = ""
        provider                 = "agy"
        status                   = $priStatus
        refreshable              = $true
        refreshing               = [bool]$priRefreshing
        note                     = ""
        measured_at              = $priMeasured
        five_hour                = $priFive
        weekly                   = $priWeek
        bottleneck_remaining_pct = (Get-AgyQuotaBottleneck $priFive $priWeek)
    })

    # 3. Sub-account slots (sub-quota.json / sub_quota DB: five_used, week_used are USED %)
    $cfg = $null
    if (Get-Command Get-AgyModelConfig -ErrorAction SilentlyContinue) {
        try { $cfg = Get-AgyModelConfig $ConfigDir } catch { $cfg = $null }
    }
    if ($cfg -and $cfg.SubAccounts -and [bool](Get-AgyAccountProp $cfg.SubAccounts "Enabled" $false)) {
        $subCfg = $cfg.SubAccounts
        $bridgeRoot = Get-AgySubBridgeRoot $subCfg
        $dbSubQuotas = $null
        $dbSubLoaded = $false

        foreach ($slot in @(Get-AgyAccountProp $subCfg "Slots" @())) {
            $sid = ([string](Get-AgyAccountProp $slot "Id" "")).Trim()
            if (-not $sid) { continue }
            $lay = Get-AgySubSlotLayout $bridgeRoot $sid

            $shortLbl = if ($sid -match '^sub(\d+)$') { "A$($Matches[1])" } else { $sid }
            $dispLbl = if ($sid -match '^sub(\d+)$') { "Agy 부$($Matches[1])" } else { ([string](Get-AgyAccountProp $slot "Label" $sid)).Trim() }
            if (-not $dispLbl) { $dispLbl = $sid }

            $sStatus = "offline"
            if ((Get-Command Test-AgySubSlotBlocked -ErrorAction SilentlyContinue) -and (Test-AgySubSlotBlocked $lay $now)) {
                $sStatus = "cooldown"
            } elseif (Test-AgySubSlotOnline $lay $now) {
                $sStatus = "online"
            }

            $sq = Read-AgyAccountQuotaJson $lay.QuotaFile
            if ($null -eq $sq -and -not $dbSubLoaded) {
                $dbSubLoaded = $true
                if ($DbPath -and (Test-Path -LiteralPath $DbPath -PathType Leaf) -and (Get-Command Get-LatestSubQuotas -ErrorAction SilentlyContinue)) {
                    try { $dbSubQuotas = Get-LatestSubQuotas $DbPath } catch { $dbSubQuotas = $null }
                }
            }
            if ($null -eq $sq -and $null -ne $dbSubQuotas -and $dbSubQuotas.ContainsKey($sid)) {
                $sq = $dbSubQuotas.Item($sid)
            }

            $sMeasured = if ($null -ne $sq) { [string](Get-AgyAccountProp $sq "measured_at" "") } else { "" }
            $sMeasuredUtc = ConvertTo-AgyAccountUtc $sMeasured
            $sFiveUsed = if ($null -ne $sq) { Get-AgyAccountProp $sq "five_used" $null } else { $null }
            $sFiveReset = if ($null -ne $sq) { [string](Get-AgyAccountProp $sq "five_reset" "") } else { "" }
            $sWeekUsed = if ($null -ne $sq) { Get-AgyAccountProp $sq "week_used" $null } else { $null }
            $sWeekReset = if ($null -ne $sq) { [string](Get-AgyAccountProp $sq "week_reset" "") } else { "" }

            $sFive = ConvertTo-AgyQuotaWindow -UsedPct $sFiveUsed -ResetIso $sFiveReset -NowUtc $now
            $sWeek = ConvertTo-AgyQuotaWindow -UsedPct $sWeekUsed -ResetIso $sWeekReset -NowUtc $now

            $sRefreshing = $false
            $qSigPath = [string]$lay["QuotaRefreshSignal"]
            if ($qSigPath -and (Test-Path -LiteralPath $qSigPath -PathType Leaf)) {
                try {
                    $sigItem = Get-Item -LiteralPath $qSigPath -ErrorAction SilentlyContinue
                    if ($null -ne $sigItem) {
                        $sigUtc = $sigItem.LastWriteTimeUtc
                        $sigAge = ($now - $sigUtc).TotalSeconds
                        if ($sigAge -lt 45 -and ($null -eq $sMeasuredUtc -or $sigUtc -gt $sMeasuredUtc)) {
                            $sRefreshing = $true
                        }
                    }
                } catch {}
            }

            [void]$accounts.Add([ordered]@{
                id                       = $sid
                short_label              = $shortLbl
                label                    = $dispLbl
                sub_label                = ""
                provider                 = "agy-sub"
                status                   = $sStatus
                refreshable              = $true
                refreshing               = [bool]$sRefreshing
                note                     = ""
                measured_at              = $sMeasured
                five_hour                = $sFive
                weekly                   = $sWeek
                bottleneck_remaining_pct = (Get-AgyQuotaBottleneck $sFive $sWeek)
            })
        }
    }

    $anyRefreshing = $false
    foreach ($acc in $accounts) {
        if ([bool](Get-AgyAccountProp $acc "refreshing" $false)) {
            $anyRefreshing = $true
            break
        }
    }

    $remCooldownSec = 0
    if ($lastManualAt -is [datetime]) {
        $elapsed = ($now - $lastManualAt.ToUniversalTime()).TotalSeconds
        if ($elapsed -ge 0 -and $elapsed -lt 15) {
            $remCooldownSec = [int][Math]::Ceiling(15.0 - $elapsed)
        }
    }

    return [ordered]@{
        generated_at = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
        refreshing   = $anyRefreshing
        cooldown_sec = $remCooldownSec
        accounts     = [object[]]@($accounts.ToArray())
    }
}

# 계정 한도 비동기 재조회를 요청한다.
# -Force: 수동 갱신(15초 쓰로틀, 전체 대상). -Force 없음: 자동 갱신(600초 쓰로틀, 누락/노후(900초)/리셋 시각 도과 대상만 실행).
# SAMJIL_DISABLE_QUOTA_REFRESH=1 이면 외부 claude/agy(powershell.exe) 프로세스 기동을 건너뛰되 -Force 신호 파일(quota-refresh.signal)은 기록한다(SAMJIL_DISABLE_QUOTA_SIGNALS=1 이면 신호 기록도 생략).
function Request-AgyAccountQuotasRefresh {
    param(
        [string]$RuntimeDir,
        [string]$ConfigDir = "",
        $SharedState = $null,
        [switch]$Force,
        [datetime]$NowUtc = [datetime]::MinValue,
        [scriptblock]$PrimaryLauncher = $null,
        [scriptblock]$ClaudeLauncher = $null
    )

    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $hasSync = ($SharedState -is [System.Collections.IDictionary] -and $null -ne $SharedState.SyncRoot)

    if ($SharedState -is [System.Collections.IDictionary]) {
        if ($hasSync) { [System.Threading.Monitor]::Enter($SharedState.SyncRoot) }
        try {
            if ($Force) {
                $lastManual = if ($SharedState.Contains("LastManualRefreshAt")) { $SharedState["LastManualRefreshAt"] } else { $null }
                if ($lastManual -is [datetime]) {
                    $elapsed = ($now - $lastManual.ToUniversalTime()).TotalSeconds
                    if ($elapsed -ge 0 -and $elapsed -lt 15) {
                        return @{ triggered = $false; reason = 'throttled'; cooldown_sec = [int][Math]::Ceiling(15.0 - $elapsed) }
                    }
                }
            } else {
                $lastAuto = if ($SharedState.Contains("LastAutoRefreshAt")) { $SharedState["LastAutoRefreshAt"] } else { $null }
                if ($lastAuto -is [datetime]) {
                    $elapsed = ($now - $lastAuto.ToUniversalTime()).TotalSeconds
                    if ($elapsed -ge 0 -and $elapsed -lt 300) {
                        return @{ triggered = $false; reason = 'throttled'; cooldown_sec = 0 }
                    }
                }
            }
        } finally {
            if ($hasSync) { [System.Threading.Monitor]::Exit($SharedState.SyncRoot) }
        }
    }

    $refreshClaude = [bool]$Force
    $refreshPrimary = [bool]$Force
    $staleSubIds = @{}
    if (-not $Force) {
        $snap = Get-AgyAccountQuotasSnapshot -RuntimeDir $RuntimeDir -ConfigDir $ConfigDir -NowUtc $now -SharedState $SharedState
        foreach ($acc in @($snap.accounts)) {
            $aid = [string](Get-AgyAccountProp $acc "id" "")
            $prov = [string](Get-AgyAccountProp $acc "provider" "")
            $st = [string](Get-AgyAccountProp $acc "status" "")
            $isRef = [bool](Get-AgyAccountProp $acc "refreshable" $false)
            if ($aid -eq "claude" -and -not $isRef) { continue }
            if ($prov -eq "agy-sub" -and $st -ne "online") { continue }

            $f5 = Get-AgyAccountProp $acc "five_hour" $null
            $fw = Get-AgyAccountProp $acc "weekly" $null
            $maxAge = 300
            $mUtc = ConvertTo-AgyAccountUtc ([string](Get-AgyAccountProp $acc "measured_at" ""))
            $isStale = ($null -eq $f5 -or $null -eq $fw -or -not [bool]$f5.available -or -not [bool]$fw.available -or [bool]$f5.reset_passed -or [bool]$fw.reset_passed -or $null -eq $mUtc -or ($now - $mUtc).TotalSeconds -gt $maxAge)
            if ($isStale) {
                if ($aid -eq "claude") { $refreshClaude = $true }
                elseif ($aid -eq "primary") { $refreshPrimary = $true }
                elseif ($prov -eq "agy-sub") { $staleSubIds[$aid] = $true }
            }
        }
        if (-not $refreshClaude -and -not $refreshPrimary -and $staleSubIds.Count -eq 0) {
            return @{ triggered = $false; reason = 'fresh'; cooldown_sec = 0 }
        }
    }

    if ($SharedState -is [System.Collections.IDictionary]) {
        if ($hasSync) { [System.Threading.Monitor]::Enter($SharedState.SyncRoot) }
        try {
            if ($Force) {
                $SharedState["LastManualRefreshAt"] = $now
            } else {
                $SharedState["LastAutoRefreshAt"] = $now
            }
        } finally {
            if ($hasSync) { [System.Threading.Monitor]::Exit($SharedState.SyncRoot) }
        }
    }

    $disableSubproc = ($env:SAMJIL_DISABLE_QUOTA_REFRESH -eq '1')
    $disableSignals = ($env:SAMJIL_DISABLE_QUOTA_SIGNALS -eq '1')
    $workerPath = Join-Path $script:AgyAccountQuotasSubDir "agy-task-worker.ps1"
    if ($RuntimeDir -and -not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        $workerPath = Join-Path $RuntimeDir "..\scripts\sub\agy-task-worker.ps1"
    }

    # Claude CLI 비동기 재조회
    $claudeCliAvailable = $false
    if (Get-Command Find-ClaudeCliExecutable -ErrorAction SilentlyContinue) {
        try { $claudeCliAvailable = [bool](Find-ClaudeCliExecutable) } catch { $claudeCliAvailable = $false }
    }
    $claudeCliUnsupported = $false
    if (Get-Command Test-ClaudeCliUsageUnsupported -ErrorAction SilentlyContinue) {
        try { $claudeCliUnsupported = [bool](Test-ClaudeCliUsageUnsupported $RuntimeDir $now) } catch { $claudeCliUnsupported = $false }
    }
    $claudeCliUsable = $claudeCliAvailable -and -not $claudeCliUnsupported
    if ($refreshClaude -and -not $claudeCliUnsupported -and ($null -ne $ClaudeLauncher -or ($claudeCliUsable -and -not $disableSubproc))) {
        $launchedClaude = $null
        if ($null -ne $ClaudeLauncher) {
            try { $launchedClaude = & $ClaudeLauncher $RuntimeDir $now } catch { $launchedClaude = $null }
        } elseif ($RuntimeDir -and (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
            try {
                $cCachePath = Join-Path $RuntimeDir "claude-limits.json"
                $cArgs = @(
                    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $workerPath,
                    "-ClaudeQuotaCacheFile", $cCachePath
                )
                $psiC = New-Object System.Diagnostics.ProcessStartInfo
                $psiC.FileName = "powershell.exe"
                $psiC.Arguments = (@($cArgs | ForEach-Object { if ([string]$_ -match '[\s"]') { "`"$_`"" } else { [string]$_ } }) -join ' ')
                $psiC.UseShellExecute = $false
                $psiC.CreateNoWindow = $true
                $psiC.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $launchedClaude = [System.Diagnostics.Process]::Start($psiC)
            } catch {
                $launchedClaude = $null
            }
        }
        if ($SharedState -is [System.Collections.IDictionary]) {
            if ($hasSync) { [System.Threading.Monitor]::Enter($SharedState.SyncRoot) }
            try {
                $SharedState["ClaudeRefreshProc"] = $launchedClaude
                $SharedState["ClaudeRefreshAt"] = $now
            } finally {
                if ($hasSync) { [System.Threading.Monitor]::Exit($SharedState.SyncRoot) }
            }
        }
    }

    # 주 계정 비동기 재조회
    if ($refreshPrimary) {
        $launchedProc = $null
        if ($null -ne $PrimaryLauncher) {
            try { $launchedProc = & $PrimaryLauncher $RuntimeDir $now } catch { $launchedProc = $null }
        } elseif (-not $disableSubproc -and $RuntimeDir -and (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
            try {
                $cachePath = Join-Path $RuntimeDir "agy-quota.json"
                $pArgs = @(
                    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $workerPath,
                    "-PrimaryQuotaCacheFile", $cachePath
                )
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "powershell.exe"
                $psi.Arguments = (@($pArgs | ForEach-Object { if ([string]$_ -match '[\s"]') { "`"$_`"" } else { [string]$_ } }) -join ' ')
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $launchedProc = [System.Diagnostics.Process]::Start($psi)
            } catch {
                $launchedProc = $null
            }
        }

        if ($SharedState -is [System.Collections.IDictionary] -and ($null -ne $launchedProc -or $null -ne $PrimaryLauncher -or -not $disableSubproc)) {
            if ($hasSync) { [System.Threading.Monitor]::Enter($SharedState.SyncRoot) }
            try {
                $SharedState["PrimaryRefreshProc"] = $launchedProc
                $SharedState["PrimaryRefreshAt"] = $now
            } finally {
                if ($hasSync) { [System.Threading.Monitor]::Exit($SharedState.SyncRoot) }
            }
        }
    }

    # 부계정 슬롯 quota-refresh.signal 기록
    if (-not $disableSignals -and ($Force -or ($staleSubIds.Count -gt 0 -and -not $disableSubproc))) {
        $cfg = $null
        if (Get-Command Get-AgyModelConfig -ErrorAction SilentlyContinue) {
            try { $cfg = Get-AgyModelConfig $ConfigDir } catch { $cfg = $null }
        }
        if ($cfg -and $cfg.SubAccounts -and [bool](Get-AgyAccountProp $cfg.SubAccounts "Enabled" $false)) {
            $bridgeRoot = Get-AgySubBridgeRoot $cfg.SubAccounts
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            foreach ($slot in @(Get-AgyAccountProp $cfg.SubAccounts "Slots" @())) {
                $sid = ([string](Get-AgyAccountProp $slot "Id" "")).Trim()
                if (-not $sid) { continue }
                if (-not $Force -and -not $staleSubIds.ContainsKey($sid)) { continue }
                $lay = Get-AgySubSlotLayout $bridgeRoot $sid
                if (Test-Path -LiteralPath $lay.SlotRoot) {
                    try {
                        if (-not (Test-Path -LiteralPath $lay.StatusDir)) {
                            [void][System.IO.Directory]::CreateDirectory($lay.StatusDir)
                        }
                        [System.IO.File]::WriteAllText($lay.QuotaRefreshSignal, $now.ToString("o"), $utf8NoBom)
                    } catch {}
                }
            }
        }
    }

    return @{
        triggered    = $true
        reason       = $(if ($Force) { 'manual' } else { 'auto' })
        cooldown_sec = $(if ($Force) { 15 } else { 0 })
    }
}
