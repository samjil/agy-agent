# agy-sub-bridge.ps1 — 멀티 Windows 부계정 풀 브리지 레이아웃 · 라우팅 · 슬롯 분산 · 쿨다운 공용 모듈.
# 주 워처(watch-agy.ps1), 부계정 워처(-SubSlot), 셋업/로그인 교체 도구가 함께 dot-source 하여 사용한다.

function Get-AgySubObjProp($Obj, [string]$Key, $Default = $null) {
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

function Get-AgySubBridgeRoot($SubCfg = $null) {
    $envRoot = [string]$env:AGY_SUB_BRIDGE_DIR
    if (-not [string]::IsNullOrWhiteSpace($envRoot)) { return $envRoot.Trim() }
    if ($null -ne $SubCfg) {
        $cfgRoot = [string](Get-AgySubObjProp $SubCfg "BridgeDir" "")
        if ([string]::IsNullOrWhiteSpace($cfgRoot)) {
            $cfgRoot = [string](Get-AgySubObjProp $SubCfg "bridge_dir" "")
        }
        if (-not [string]::IsNullOrWhiteSpace($cfgRoot)) { return $cfgRoot.Trim() }
    }
    return "C:\ProgramData\samjil\sub-bridge"
}

function Test-AgyBridgeSafeId([string]$Id) {
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    if ($Id.Contains("..")) { return $false }
    return ($Id -match '^[A-Za-z0-9_.-]{1,100}$')
}

function Test-AgySubPathUnderRoot([string]$CandidatePath, [string]$AllowedRootDir) {
    if ([string]::IsNullOrWhiteSpace($CandidatePath) -or [string]::IsNullOrWhiteSpace($AllowedRootDir)) { return $false }
    try {
        $candFull = [System.IO.Path]::GetFullPath($CandidatePath)
        $rootFull = [System.IO.Path]::GetFullPath($AllowedRootDir).TrimEnd('\') + '\'
        return $candFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Get-AgySubSlotLayout([string]$BridgeRoot, [string]$SlotId, [string]$ComputerName = $env:COMPUTERNAME) {
    $safeRoot = if ([string]::IsNullOrWhiteSpace($BridgeRoot)) { "C:\ProgramData\samjil\sub-bridge" } else { $BridgeRoot.Trim().TrimEnd('\') }
    $rawSlot = ([string]$SlotId).Trim()
    if (-not $rawSlot -or $rawSlot -notmatch '^[A-Za-z0-9_-]{1,32}$') { throw "유효하지 않은 부계정 슬롯 ID 입니다: '$SlotId'" }
    $safeSlot = $rawSlot
    $pc = if ([string]::IsNullOrWhiteSpace($ComputerName)) { "LOCAL" } else { ($ComputerName.Trim() -replace '[^A-Za-z0-9_.-]', '_') }

    $slotRoot     = Join-Path (Join-Path $safeRoot "slots") $safeSlot
    $statusDir    = Join-Path $slotRoot "status"
    $heartbeatDir = Join-Path $slotRoot "heartbeat"
    return @{
        SlotId         = $safeSlot
        BridgeRoot     = $safeRoot
        SlotRoot       = $slotRoot
        InboxDir       = Join-Path $slotRoot "inbox"
        PromptsDir     = Join-Path $slotRoot "prompts"
        RunningDir     = Join-Path $slotRoot "running"
        OutboxDir      = Join-Path $slotRoot "outbox"
        TranscriptsDir = Join-Path $slotRoot "transcripts"
        HeartbeatDir   = $heartbeatDir
        StatusDir      = $statusDir
        StateFile          = Join-Path $statusDir "sub-state.json"
        QuotaFile          = Join-Path $statusDir "sub-quota.json"
        RefreshSignal      = Join-Path $statusDir "refresh.signal"
        QuotaRefreshSignal = Join-Path $statusDir "quota-refresh.signal"
        RestartSignal      = Join-Path $statusDir "restart.signal"
        PauseFlag      = Join-Path $statusDir "pause.flag"
        LockFile       = Join-Path $statusDir ("sub-lock_{0}.pid" -f $pc)
        HeartbeatFile  = Join-Path $heartbeatDir ("sub_{0}.txt" -f $pc)
    }
}

function Initialize-AgySubSlotDirectories([hashtable]$Layout) {
    if ($null -eq $Layout) { return $false }
    foreach ($k in @("SlotRoot", "InboxDir", "PromptsDir", "RunningDir", "OutboxDir", "TranscriptsDir", "HeartbeatDir", "StatusDir")) {
        $dir = [string]$Layout[$k]
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }
    }
    return $true
}

function Write-BridgeJsonAtomic([string]$Path, $Data) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $tmp = "{0}.{1}.{2}.tmp" -f $Path, $PID, ([Guid]::NewGuid().ToString("N"))
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        $json = $Data | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
        for ($try = 0; $try -lt 4; $try++) {
            try {
                if (Test-Path -LiteralPath $Path -PathType Leaf) {
                    [System.IO.File]::Replace($tmp, $Path, [NullString]::Value, $true)
                } else {
                    [System.IO.File]::Move($tmp, $Path)
                }
                return $true
            } catch [System.IO.IOException] {
                if ($try -ge 3) { throw }
                Start-Sleep -Milliseconds 30
            }
        }
        return $false
    } catch {
        return $false
    } finally {
        try { if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) } } catch {}
    }
}

function Read-BridgeJson([string]$Path) {
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
            return ($raw | ConvertFrom-Json)
        } catch [System.IO.IOException] {
            if ($try -lt 2) { Start-Sleep -Milliseconds 25 }
        } catch {
            return $null
        }
    }
    return $null
}

function ConvertTo-NormalizedSubPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $clean = $Path.Trim().Replace('/', '\')
    try {
        $clean = [System.IO.Path]::GetFullPath($clean)
    } catch {}
    return $clean.TrimEnd('\')
}

function Test-AgySubPathAccessible([string[]]$Cwds, [string]$PrimaryUserProfile = $env:USERPROFILE, [string[]]$AllowedSubtrees = @()) {
    if ($null -eq $Cwds -or @($Cwds).Count -eq 0) { return $true }
    $profNorm = ConvertTo-NormalizedSubPath $PrimaryUserProfile
    if (-not $profNorm) { return $true }

    $allowedNorms = New-Object System.Collections.ArrayList
    foreach ($a in @($AllowedSubtrees)) {
        $an = ConvertTo-NormalizedSubPath ([string]$a)
        if ($an) { [void]$allowedNorms.Add($an) }
    }

    foreach ($c in @($Cwds)) {
        $cn = ConvertTo-NormalizedSubPath ([string]$c)
        if (-not $cn) { continue }
        $underProfile = [string]::Equals($cn, $profNorm, [StringComparison]::OrdinalIgnoreCase) -or
            $cn.StartsWith($profNorm + "\", [StringComparison]::OrdinalIgnoreCase)
        if (-not $underProfile) { continue }

        $explicitlyAllowed = $false
        foreach ($an in $allowedNorms) {
            if ([string]::Equals($cn, $an, [StringComparison]::OrdinalIgnoreCase) -or
                $cn.StartsWith($an + "\", [StringComparison]::OrdinalIgnoreCase)) {
                $explicitlyAllowed = $true
                break
            }
        }
        if (-not $explicitlyAllowed) { return $false }
    }
    return $true
}

function Test-AgySubAccountCandidate($SubCfg, [string]$FirstModel, [string]$SlashCmd = "", [string[]]$Cwds = @(), $ExistingSession = $null, [bool]$Upgrade = $false) {
    if ($null -eq $SubCfg) { return @{ Eligible = $false; Reason = "disabled" } }
    $enabled = [bool](Get-AgySubObjProp $SubCfg "Enabled" $false)
    $slots = @(Get-AgySubObjProp $SubCfg "Slots" @())
    if (-not $enabled -or $slots.Count -eq 0) {
        return @{ Eligible = $false; Reason = "disabled" }
    }

    $pattern = [string](Get-AgySubObjProp $SubCfg "ModelPattern" "^gemini-4-hydrogen-")
    if ([string]::IsNullOrWhiteSpace($pattern)) { $pattern = "^gemini-4-hydrogen-" }
    $m = ([string]$FirstModel).Trim()
    if ([string]::IsNullOrWhiteSpace($m) -or ($m -notmatch $pattern)) {
        return @{ Eligible = $false; Reason = "model_mismatch" }
    }

    $cmdNorm = ([string]$SlashCmd).Trim().TrimStart('/').ToLowerInvariant()
    if ($cmdNorm) {
        $blocked = @(Get-AgySubObjProp $SubCfg "PrimaryOnlyCmds" @("browser"))
        foreach ($b in $blocked) {
            $bn = ([string]$b).Trim().TrimStart('/').ToLowerInvariant()
            if ($bn -and $cmdNorm -eq $bn) {
                return @{ Eligible = $false; Reason = "primary_only_cmd" }
            }
        }
    }

    $allowedSubtrees = @(Get-AgySubObjProp $SubCfg "AllowedSubtrees" @())
    if (-not (Test-AgySubPathAccessible $Cwds $env:USERPROFILE $allowedSubtrees)) {
        return @{ Eligible = $false; Reason = "inaccessible_cwd" }
    }

    if ($null -ne $ExistingSession) {
        $cid = ([string](Get-AgySubObjProp $ExistingSession "conversation_id" "")).Trim()
        if ($cid) {
            $acct = ([string](Get-AgySubObjProp $ExistingSession "account" "primary")).Trim().ToLowerInvariant()
            if (-not $acct) { $acct = "primary" }
            if ($acct -eq "primary" -and -not $Upgrade) {
                return @{ Eligible = $false; Reason = "primary_session" }
            }
        }
    }

    return @{ Eligible = $true; Reason = "ok" }
}

function Get-AgyHydrogenPrefixChain([string[]]$ModelChain, [string]$Pattern = "^gemini-4-hydrogen-") {
    $pat = if ([string]::IsNullOrWhiteSpace($Pattern)) { "^gemini-4-hydrogen-" } else { $Pattern }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($m in @($ModelChain)) {
        $ms = ([string]$m).Trim()
        if (-not $ms) { continue }
        if ($ms -match $pat) { [void]$list.Add($ms) }
        else { break }
    }
    return @($list.ToArray())
}

function ConvertTo-BridgeHashtable($Obj) {
    $ht = [ordered]@{}
    if ($null -eq $Obj) { return $ht }
    if ($Obj -is [System.Collections.IDictionary]) {
        foreach ($k in $Obj.Keys) { $ht[[string]$k] = $Obj[$k] }
        return $ht
    }
    if ($Obj.PSObject) {
        foreach ($p in $Obj.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    }
    return $ht
}

function Set-AgySubSlotCooldown([string]$BridgeRoot, [string]$SlotId, [int]$CooldownSec = 60, [string]$Reason = "", [datetime]$NowUtc = [datetime]::UtcNow) {
    $lay = Get-AgySubSlotLayout $BridgeRoot $SlotId
    Initialize-AgySubSlotDirectories $lay | Out-Null
    $existing = Read-BridgeJson $lay.StateFile
    $state = ConvertTo-BridgeHashtable $existing
    $utc = $NowUtc.ToUniversalTime()
    $sec = [Math]::Max(1, $CooldownSec)
    $state["slot_id"] = $lay.SlotId
    $state["cooldown_at"] = $utc.ToString("o")
    $state["cooldown_until"] = $utc.AddSeconds($sec).ToString("o")
    $state["cooldown_reason"] = [string]$Reason
    $state["updated_at"] = $utc.ToString("o")
    return (Write-BridgeJsonAtomic $lay.StateFile $state)
}

function Clear-AgySubSlotCooldown([string]$BridgeRoot, [string]$SlotId) {
    $lay = Get-AgySubSlotLayout $BridgeRoot $SlotId
    Initialize-AgySubSlotDirectories $lay | Out-Null
    $existing = Read-BridgeJson $lay.StateFile
    $state = ConvertTo-BridgeHashtable $existing
    $state["slot_id"] = $lay.SlotId
    $state["cooldown_at"] = ""
    $state["cooldown_until"] = ""
    $state["cooldown_reason"] = ""
    $state["updated_at"] = ([datetime]::UtcNow.ToString("o"))
    return (Write-BridgeJsonAtomic $lay.StateFile $state)
}

function Set-AgySubSlotDispatched([string]$BridgeRoot, [string]$SlotId, [datetime]$NowUtc = [datetime]::UtcNow) {
    $lay = Get-AgySubSlotLayout $BridgeRoot $SlotId
    Initialize-AgySubSlotDirectories $lay | Out-Null
    $existing = Read-BridgeJson $lay.StateFile
    $state = ConvertTo-BridgeHashtable $existing
    $utc = $NowUtc.ToUniversalTime()
    $state["slot_id"] = $lay.SlotId
    $state["last_dispatched_at"] = $utc.ToString("o")
    $state["updated_at"] = $utc.ToString("o")
    return (Write-BridgeJsonAtomic $lay.StateFile $state)
}

function Get-AgySubSlotBottleneckUsedPct([hashtable]$Layout, [datetime]$NowUtc) {
    if ($null -eq $Layout) { return 0.0 }
    $quota = Read-BridgeJson $Layout.QuotaFile
    if ($null -eq $quota) { return 0.0 }
    $nowU = $NowUtc.ToUniversalTime()

    $fiveEff = 0.0
    $fiveVal = 0.0
    if ([double]::TryParse([string](Get-AgySubObjProp $quota "five_used" ""), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$fiveVal)) {
        $fiveResetUtc = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $quota "five_reset" ""))
        if ($null -eq $fiveResetUtc -or $fiveResetUtc -gt $nowU) {
            $fiveEff = [Math]::Max(0.0, [Math]::Min(100.0, $fiveVal))
        }
    }

    $weekEff = 0.0
    $weekVal = 0.0
    if ([double]::TryParse([string](Get-AgySubObjProp $quota "week_used" ""), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$weekVal)) {
        $weekResetUtc = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $quota "week_reset" ""))
        if ($null -eq $weekResetUtc -or $weekResetUtc -gt $nowU) {
            $weekEff = [Math]::Max(0.0, [Math]::Min(100.0, $weekVal))
        }
    }

    return [Math]::Max($fiveEff, $weekEff)
}

function Get-AgySubSlotLastDispatchedTicks([hashtable]$Layout) {
    if ($null -eq $Layout) { return [long]0 }
    $state = Read-BridgeJson $Layout.StateFile
    if ($null -eq $state) { return [long]0 }
    $dt = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $state "last_dispatched_at" ""))
    if ($null -eq $dt) { return [long]0 }
    return [long]$dt.Ticks
}

function Parse-BridgeUtcTimestamp([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Get-AgySubSlotHeartbeatUtc([hashtable]$Layout) {
    $files = @(Get-ChildItem -LiteralPath $Layout.HeartbeatDir -Filter "sub_*.txt" -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return $null }
    $latest = ($files | Sort-Object -Property LastWriteTimeUtc -Descending | Select-Object -First 1)
    if ($null -eq $latest) { return $null }
    return $latest.LastWriteTimeUtc
}

function Test-AgySubSlotBlocked([hashtable]$Layout, [datetime]$NowUtc) {
    $nowU = $NowUtc.ToUniversalTime()
    $state = Read-BridgeJson $Layout.StateFile
    if ($null -ne $state) {
        $coolUntil = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $state "cooldown_until" ""))
        if ($null -ne $coolUntil -and $nowU -lt $coolUntil) {
            $recoveredByRefresh = $false
            if (Test-Path -LiteralPath $Layout.RefreshSignal -PathType Leaf) {
                $sigUtc = (Get-Item -LiteralPath $Layout.RefreshSignal).LastWriteTimeUtc
                $recordedUtc = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $state "cooldown_at" ""))
                if ($null -eq $recordedUtc) {
                    $recordedUtc = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $state "updated_at" ""))
                }
                if ($null -eq $recordedUtc -and (Test-Path -LiteralPath $Layout.StateFile -PathType Leaf)) {
                    $recordedUtc = (Get-Item -LiteralPath $Layout.StateFile).LastWriteTimeUtc
                }
                if ($null -eq $recordedUtc -or $sigUtc -ge $recordedUtc) {
                    $recoveredByRefresh = $true
                }
            }
            if (-not $recoveredByRefresh) { return $true }
        }
    }

    $quota = Read-BridgeJson $Layout.QuotaFile
    if ($null -ne $quota) {
        $measuredUtc = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $quota "measured_at" ""))
        $fiveUsedVal = 0.0
        $hasFive = [double]::TryParse([string](Get-AgySubObjProp $quota "five_used" ""), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$fiveUsedVal)
        $weekUsedVal = 0.0
        $hasWeek = [double]::TryParse([string](Get-AgySubObjProp $quota "week_used" ""), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$weekUsedVal)

        $fiveResetStr = [string](Get-AgySubObjProp $quota "five_reset" "")
        $fiveResetUtc = Parse-BridgeUtcTimestamp $fiveResetStr
        $fiveExhausted = $false
        if ($hasFive -and $fiveUsedVal -ge 100) {
            if ($null -ne $fiveResetUtc) {
                if ($fiveResetUtc -gt $nowU) { $fiveExhausted = $true }
            } elseif ([string]::IsNullOrWhiteSpace($fiveResetStr) -and $null -ne $measuredUtc) {
                if ([Math]::Abs(($nowU - $measuredUtc).TotalMinutes) -le 30) { $fiveExhausted = $true }
            }
        }

        $weekResetUtc = Parse-BridgeUtcTimestamp ([string](Get-AgySubObjProp $quota "week_reset" ""))
        $weekExhausted = ($hasWeek -and $weekUsedVal -ge 100 -and $null -ne $weekResetUtc -and $weekResetUtc -gt $nowU)

        if ($fiveExhausted -or $weekExhausted) {
            $recoveredByRefresh = $false
            if (Test-Path -LiteralPath $Layout.RefreshSignal -PathType Leaf) {
                $sigUtc = (Get-Item -LiteralPath $Layout.RefreshSignal).LastWriteTimeUtc
                if ($null -eq $measuredUtc -or $sigUtc -ge $measuredUtc) {
                    $recoveredByRefresh = $true
                }
            }
            if (-not $recoveredByRefresh) { return $true }
        }
    }

    return $false
}

function Get-AgySubSlotsBusyState($SubCfg, [string]$BridgeRoot, [datetime]$NowUtc = [datetime]::UtcNow, [int]$HeartbeatMaxAgeSec = 60) {
    $res = @{
        HasBusyHealthySlot   = $false
        FailedOrExhaustedIds = [string[]]@()
    }
    if ($null -eq $SubCfg -or -not [bool](Get-AgySubObjProp $SubCfg "Enabled" $false)) { return $res }
    $slots = @(Get-AgySubObjProp $SubCfg "Slots" @())
    if ($slots.Count -eq 0) { return $res }

    $root = if ([string]::IsNullOrWhiteSpace($BridgeRoot)) { Get-AgySubBridgeRoot $SubCfg } else { $BridgeRoot.Trim() }
    $nowU = $NowUtc.ToUniversalTime()
    $failedList = New-Object System.Collections.Generic.List[string]

    foreach ($s in $slots) {
        $sid = ([string](Get-AgySubObjProp $s "Id" "")).Trim()
        if (-not $sid) { continue }
        $maxP = [int](Get-AgySubObjProp $s "MaxParallel" 5)
        if ($maxP -lt 1) { $maxP = 5 }

        $lay = Get-AgySubSlotLayout $root $sid
        if (Test-Path -LiteralPath $lay.PauseFlag) { continue }

        $hbUtc = Get-AgySubSlotHeartbeatUtc $lay
        if ($null -eq $hbUtc -or (($nowU - $hbUtc).TotalSeconds -gt $HeartbeatMaxAgeSec)) {
            [void]$failedList.Add($sid)
            continue
        }

        if (Test-AgySubSlotBlocked $lay $nowU) {
            [void]$failedList.Add($sid)
            continue
        }

        $runningCount = @(Get-ChildItem -LiteralPath $lay.RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
        $inboxCount   = @(Get-ChildItem -LiteralPath $lay.InboxDir -Filter "*.task.json" -File -ErrorAction SilentlyContinue).Count
        $loadCount    = $runningCount + $inboxCount
        if ($loadCount -ge $maxP) {
            $res.HasBusyHealthySlot = $true
        }
    }

    $res.FailedOrExhaustedIds = [string[]]@($failedList.ToArray())
    return $res
}

function Select-AgySubSlotOrder($SubCfg, [string]$BridgeRoot, [string[]]$Cwds = @(), [string]$TaskId = "", $ExistingSession = $null, [datetime]$NowUtc = [datetime]::UtcNow, [int]$HeartbeatMaxAgeSec = 60) {
    if ($null -eq $SubCfg -or -not [bool](Get-AgySubObjProp $SubCfg "Enabled" $false)) { return @() }
    $slots = @(Get-AgySubObjProp $SubCfg "Slots" @())
    if ($slots.Count -eq 0) { return @() }

    $root = if ([string]::IsNullOrWhiteSpace($BridgeRoot)) { Get-AgySubBridgeRoot $SubCfg } else { $BridgeRoot.Trim() }
    $nowU = $NowUtc.ToUniversalTime()

    $sessAccount = ""
    if ($null -ne $ExistingSession) {
        $sessAccount = ([string](Get-AgySubObjProp $ExistingSession "account" "")).Trim().ToLowerInvariant()
    }

    $candidates = New-Object System.Collections.ArrayList
    foreach ($s in $slots) {
        $sid = ([string](Get-AgySubObjProp $s "Id" "")).Trim()
        if (-not $sid) { continue }
        $winUser = ([string](Get-AgySubObjProp $s "WindowsUser" "")).Trim()
        $lbl = ([string](Get-AgySubObjProp $s "Label" $sid)).Trim()
        $maxP = [int](Get-AgySubObjProp $s "MaxParallel" 5)
        if ($maxP -lt 1) { $maxP = 5 }

        $lay = Get-AgySubSlotLayout $root $sid
        if (Test-Path -LiteralPath $lay.PauseFlag) { continue }

        $hbUtc = Get-AgySubSlotHeartbeatUtc $lay
        if ($null -eq $hbUtc -or (($nowU - $hbUtc).TotalSeconds -gt $HeartbeatMaxAgeSec)) { continue }

        $runningCount = @(Get-ChildItem -LiteralPath $lay.RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
        $inboxCount   = @(Get-ChildItem -LiteralPath $lay.InboxDir -Filter "*.task.json" -File -ErrorAction SilentlyContinue).Count
        $loadCount    = $runningCount + $inboxCount
        if ($loadCount -ge $maxP) { continue }

        if (Test-AgySubSlotBlocked $lay $nowU) { continue }

        $usedPct = Get-AgySubSlotBottleneckUsedPct $lay $nowU
        $quotaBucket = [int][Math]::Floor($usedPct / 5.0)
        $lastDispTicks = Get-AgySubSlotLastDispatchedTicks $lay

        [void]$candidates.Add(@{
            Id                  = $sid
            WindowsUser         = $winUser
            Label               = $lbl
            RunningCount        = $loadCount
            MaxParallel         = $maxP
            SessionAffinity     = ($sessAccount -and ($sid.ToLowerInvariant() -eq $sessAccount))
            QuotaUsedPct        = $usedPct
            QuotaBucket         = $quotaBucket
            LastDispatchedTicks = $lastDispTicks
        })
    }

    if ($candidates.Count -eq 0) { return @() }

    # 동일 저장소(@cwd)에서도 한 슬롯으로 쏠리지 않도록 TaskId 우선 해시로 동률 분산
    $seed = ([string]$TaskId).Trim()
    if (-not $seed) {
        foreach ($c in @($Cwds)) {
            $norm = ConvertTo-NormalizedSubPath ([string]$c)
            if ($norm) { $seed = $norm.ToLowerInvariant(); break }
        }
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))
        $hashNum = [System.BitConverter]::ToUInt32($bytes, 0)
    } finally {
        $sha.Dispose()
    }
    $nCand = $candidates.Count
    $anchor = [int]($hashNum % [uint32]$nCand)

    $scored = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $nCand; $i++) {
        $c = $candidates[$i]
        $affRank = if ($c.SessionAffinity) { 0 } else { 1 }
        $tieRank = (($i - $anchor + $nCand) % $nCand)
        $c["AffRank"] = $affRank
        $c["TieRank"] = $tieRank
        $c["Score"]   = ($affRank * 1000000) + ($c.RunningCount * 10000) + ($c.QuotaBucket * 100) + $tieRank
        [void]$scored.Add($c)
    }

    $sorted = @($scored | Sort-Object -Property `
        @{ Expression = { $_.AffRank }; Ascending = $true }, `
        @{ Expression = { $_.RunningCount }; Ascending = $true }, `
        @{ Expression = { $_.QuotaBucket }; Ascending = $true }, `
        @{ Expression = { $_.LastDispatchedTicks }; Ascending = $true }, `
        @{ Expression = { $_.TieRank }; Ascending = $true })
    return $sorted
}
