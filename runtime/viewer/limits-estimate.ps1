# limits-estimate.ps1
# Claude · agy 의 5시간 / 주간 한도 크기(토큰)를 현재 구간 사용량 ÷ (사용 % / 100) 로 추정합니다.
# 뷰어(serve-viewer.ps1)가 dot-source 해서 쓰고, 한 번 계산한 결과를 최대 60초까지 캐시합니다.
# 개인정보 보호: claude-window-cache.json 에는 파일 경로 해시 · 오프셋 · 메시지 ID · 시각(epoch) · 토큰 합만 저장하고 경로·이름·프롬프트는 쓰지 않습니다.

function Round-LimitEstimate([double]$Value, [int]$SigDigits = 3) {
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value) -or $Value -le 0) { return 0L }
    $mag = [math]::Floor([math]::Log10($Value))
    $scale = [math]::Pow(10.0, $mag - ($SigDigits - 1))
    if ($scale -le 0) { return [long][math]::Round($Value) }
    return [long][math]::Round([math]::Round($Value / $scale, [System.MidpointRounding]::AwayFromZero) * $scale)
}

function Get-PathHashKey([string]$FullPath) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(([string]$FullPath).ToLowerInvariant())
        $hex = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
        return $hex.Substring(0, 16)
    } finally {
        $sha.Dispose()
    }
}

function Read-ClaudeLimitsFile([string]$LimitsFile) {
    if (-not $LimitsFile -or -not (Test-Path -LiteralPath $LimitsFile -PathType Leaf)) { return $null }
    try {
        $fs = [System.IO.File]::Open($LimitsFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        try {
            $raw = $sr.ReadToEnd().TrimStart([char]0xFEFF)
        } finally {
            $sr.Dispose()
        }
        if (-not $raw.Trim()) { return $null }
        $obj = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if ($null -eq $obj) { return $null }
        $out = [ordered]@{}
        if ($obj.PSObject.Properties["checked_at"] -and $obj.checked_at) {
            $out["checked_at"] = [string]$obj.checked_at
        }
        $hasAny = $false
        foreach ($k in @("five_hour", "seven_day")) {
            if ($obj.PSObject.Properties[$k] -and $null -ne $obj.$k) {
                $e = $obj.$k
                if ($null -ne $e.used_pct) {
                    $entry = [ordered]@{ used_pct = [double]$e.used_pct }
                    if ($e.PSObject.Properties["resets_at"] -and $e.resets_at) {
                        $entry["resets_at"] = [string]$e.resets_at
                    }
                    $out[$k] = $entry
                    $hasAny = $true
                }
            }
        }
        if (-not $hasAny) { return $null }
        return $out
    } catch {
        return $null
    }
}

# ~/.claude/projects/**/*.jsonl (subagents\*.jsonl 포함) 에서 구간 시작 시각 이후 assistant 토큰 합계를 증분 계산한다.
# $Windows: @{ five_hour = [datetime]$StartUtc; seven_day = [datetime]$StartUtc }
function Get-ClaudeWindowTokens([string]$ProjectsDir, [string]$CacheFile, $Windows, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $totals = @{}
    if (-not $Windows -or $Windows.Count -eq 0) { return $totals }
    foreach ($wk in $Windows.Keys) { $totals[$wk] = 0L }
    if (-not $ProjectsDir -or -not (Test-Path -LiteralPath $ProjectsDir -PathType Container)) { return $totals }

    if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
        Add-Type -AssemblyName System.Web.Extensions
    }
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue
    $js.RecursionLimit = 256

    $oldestStart = $now
    $winEpochs = @{}
    $nowEpoch = ([DateTimeOffset]$now).ToUnixTimeSeconds()
    foreach ($wk in $Windows.Keys) {
        $dt = ([datetime]$Windows[$wk]).ToUniversalTime()
        if ($dt -lt $oldestStart) { $oldestStart = $dt }
        $winEpochs[$wk] = ([DateTimeOffset]$dt).ToUnixTimeSeconds()
    }
    $pruneCutoffEpoch = ([DateTimeOffset]$now.AddDays(-8)).ToUnixTimeSeconds()

    # 캐시 로드 (경로·이메일·본문 없이 해시 키 · 오프셋 · 메시지 ID · epoch · 토큰만)
    $cacheFiles = @{}
    if ($CacheFile -and (Test-Path -LiteralPath $CacheFile -PathType Leaf)) {
        try {
            $cRaw = [System.IO.File]::ReadAllText($CacheFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
            if ($cRaw.Trim()) {
                $cObj = $js.DeserializeObject($cRaw)
                if (($cObj -is [System.Collections.IDictionary]) -and ($cObj["files"] -is [System.Collections.IDictionary])) {
                    foreach ($fk in $cObj["files"].Keys) {
                        $fe = $cObj["files"][$fk]
                        if (-not ($fe -is [System.Collections.IDictionary])) { continue }
                        $msgsMap = @{}
                        if ($fe["msgs"] -is [System.Collections.IDictionary]) {
                            foreach ($mk in $fe["msgs"].Keys) {
                                $mv = $fe["msgs"][$mk]
                                if ($mv -is [System.Collections.IDictionary]) {
                                    $tsE = [long]$mv["ts"]
                                    if ($tsE -ge $pruneCutoffEpoch) {
                                        $msgsMap[[string]$mk] = @{ ts = $tsE; t = [long]$mv["t"] }
                                    }
                                }
                            }
                        }
                        $cacheFiles[[string]$fk] = @{
                            offset = [long]$fe["offset"]
                            size   = [long]$fe["size"]
                            mtime  = [long]$fe["mtime"]
                            msgs   = $msgsMap
                        }
                    }
                }
            }
        } catch {
            $cacheFiles = @{}
        }
    }

    $dirty = $false
    $toLong = {
        param($val)
        if ($null -eq $val -or $val -is [bool] -or $val -is [string]) { return 0L }
        try { return [long]$val } catch { return 0L }
    }

    $jsonlFiles = @(Get-ChildItem -LiteralPath $ProjectsDir -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue)
    foreach ($f in $jsonlFiles) {
        if ($f.LastWriteTimeUtc -lt $oldestStart) { continue }
        $key = Get-PathHashKey $f.FullName
        $fSize = [long]$f.Length
        $fMtime = [long]$f.LastWriteTimeUtc.Ticks

        $entry = if ($cacheFiles.ContainsKey($key)) { $cacheFiles[$key] } else { $null }
        if ($entry -and $entry.size -eq $fSize -and $entry.mtime -eq $fMtime) {
            continue
        }

        if (-not $entry -or $fSize -lt $entry.offset) {
            $entry = @{ offset = 0L; size = $fSize; mtime = $fMtime; msgs = @{} }
            $cacheFiles[$key] = $entry
        }

        $fs = $null
        try {
            $fs = [System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $actualLen = [long]$fs.Length
            if ($actualLen -lt $entry.offset) {
                $entry.offset = 0L
                $entry.msgs = @{}
            }
            $rem = $actualLen - $entry.offset
            if ($rem -gt 0) {
                [void]$fs.Seek($entry.offset, [System.IO.SeekOrigin]::Begin)
                $buf = New-Object byte[] $rem
                $readTotal = 0
                while ($readTotal -lt $rem) {
                    $r = $fs.Read($buf, $readTotal, $rem - $readTotal)
                    if ($r -le 0) { break }
                    $readTotal += $r
                }
                if ($readTotal -gt 0) {
                    # 아직 \n 으로 닫히지 않은 마지막 줄은 다음번에 읽는다
                    $lastNl = -1
                    for ($bi = $readTotal - 1; $bi -ge 0; $bi--) {
                        if ($buf[$bi] -eq 10) { $lastNl = $bi; break }
                    }
                    if ($lastNl -ge 0) {
                        $chunkText = [System.Text.Encoding]::UTF8.GetString($buf, 0, $lastNl + 1)
                        $newOffset = $entry.offset + [long]($lastNl + 1)
                        foreach ($ln in ($chunkText -split "\r?\n")) {
                            if (-not $ln -or $ln.IndexOf('"assistant"', [System.StringComparison]::Ordinal) -lt 0 -or $ln.IndexOf('"usage"', [System.StringComparison]::Ordinal) -lt 0) { continue }
                            $obj = $null
                            try { $obj = $js.DeserializeObject($ln) } catch { continue }
                            if (-not ($obj -is [System.Collections.IDictionary]) -or $obj["type"] -ne "assistant" -or $obj["isApiErrorMessage"] -eq $true) { continue }
                            $msg = $obj["message"]
                            if (-not ($msg -is [System.Collections.IDictionary])) { continue }
                            $model = [string]$msg["model"]
                            if (-not $model -or $model -eq "<synthetic>") { continue }
                            $usage = $msg["usage"]
                            if (-not ($usage -is [System.Collections.IDictionary])) { continue }
                            $tsStr = [string]$obj["timestamp"]
                            if (-not $tsStr) { continue }
                            $tsDt = [datetime]::MinValue
                            $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                            if (-not [datetime]::TryParse($tsStr, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$tsDt)) { continue }
                            $tsEpoch = ([DateTimeOffset]$tsDt.ToUniversalTime()).ToUnixTimeSeconds()
                            if ($tsEpoch -lt $pruneCutoffEpoch) { continue }

                            $tot = (& $toLong $usage["input_tokens"]) + (& $toLong $usage["cache_creation_input_tokens"]) + (& $toLong $usage["cache_read_input_tokens"]) + (& $toLong $usage["output_tokens"])
                            $mid = if ($msg["id"]) { [string]$msg["id"] } elseif ($obj["uuid"]) { [string]$obj["uuid"] } else { "" }
                            if (-not $mid) { continue }

                            if ($entry.msgs.ContainsKey($mid)) {
                                $prev = $entry.msgs[$mid]
                                if ($tot -gt $prev.t) { $prev.t = $tot }
                                if ($tsEpoch -gt $prev.ts) { $prev.ts = $tsEpoch }
                            } else {
                                $entry.msgs[$mid] = @{ ts = $tsEpoch; t = $tot }
                            }
                        }
                        $entry.offset = $newOffset
                    }
                }
            }
            $entry.size = $actualLen
            $entry.mtime = $fMtime
            $dirty = $true
        } catch {
        } finally {
            if ($fs) { $fs.Dispose() }
        }
    }

    # 오래된 항목 정리
    $deadKeys = @()
    foreach ($fk in $cacheFiles.Keys) {
        $msgs = $cacheFiles[$fk].msgs
        $oldMids = @()
        foreach ($mk in $msgs.Keys) {
            if ($msgs[$mk].ts -lt $pruneCutoffEpoch) { $oldMids += $mk }
        }
        foreach ($om in $oldMids) { $msgs.Remove($om); $dirty = $true }
        if ($msgs.Count -eq 0) { $deadKeys += $fk }
    }
    foreach ($dk in $deadKeys) { $cacheFiles.Remove($dk); $dirty = $true }

    if ($dirty -and $CacheFile) {
        $tmp = "$CacheFile.$PID.tmp"
        try {
            $dir = Split-Path -Path $CacheFile -Parent
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            $payload = @{ version = 1; files = $cacheFiles }
            $json = $js.Serialize($payload)
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
            Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
            [System.IO.File]::Move($tmp, $CacheFile)
        } catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    # 모든 파일에서 message.id 별로 중복을 없앤 뒤 구간 내 토큰 합계 계산
    $globalMsgs = @{}
    foreach ($fk in $cacheFiles.Keys) {
        $msgs = $cacheFiles[$fk].msgs
        foreach ($mk in $msgs.Keys) {
            $mv = $msgs[$mk]
            if ($globalMsgs.ContainsKey($mk)) {
                $gm = $globalMsgs[$mk]
                if ($mv.t -gt $gm.t) { $gm.t = $mv.t }
                if ($mv.ts -gt $gm.ts) { $gm.ts = $mv.ts }
            } else {
                $globalMsgs[$mk] = @{ ts = $mv.ts; t = $mv.t }
            }
        }
    }

    foreach ($gm in $globalMsgs.Values) {
        foreach ($wk in $winEpochs.Keys) {
            if ($gm.ts -ge $winEpochs[$wk] -and $gm.ts -le $nowEpoch) {
                $totals[$wk] += $gm.t
            }
        }
    }

    return $totals
}

# tasks 표에서 agy(Gemini / Orchestrator 통합) 구간 토큰 합계를 구한다.
function Get-AgyWindowTokens([string]$DbPath, $Windows, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $totals = @{}
    if (-not $Windows -or $Windows.Count -eq 0) { return $totals }
    foreach ($wk in $Windows.Keys) { $totals[$wk] = 0L }
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return $totals }
    if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) { return $totals }

    $oldestStart = $now
    foreach ($wk in $Windows.Keys) {
        $dt = ([datetime]$Windows[$wk]).ToUniversalTime()
        if ($dt -lt $oldestStart) { $oldestStart = $dt }
    }
    $lowerBoundLocal = $oldestStart.ToLocalTime().AddDays(-1).ToString("yyyy-MM-dd HH:mm:ss")

    $db = $null
    try {
        $db = Open-AgyDb $DbPath
        $rows = $db.Query("SELECT timestamp, model, total_tokens FROM tasks WHERE timestamp IS NOT NULL AND timestamp <> '' AND timestamp >= ?", [object[]]@($lowerBoundLocal))
        foreach ($r in @($rows)) {
            $tok = 0L
            if (-not [long]::TryParse([string]$r["total_tokens"], [ref]$tok) -or $tok -le 0) { continue }
            $tsStr = [string]$r["timestamp"]
            if (-not $tsStr) { continue }
            $tsDt = [datetime]::MinValue
            if (-not [datetime]::TryParse($tsStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$tsDt)) { continue }
            $tsUtc = $tsDt.ToUniversalTime()
            if ($tsUtc -gt $now) { continue }

            $m = [string]$r["model"]
            if ($m -notmatch '(?i)gemini|orchestrator') { continue }

            foreach ($wk in $Windows.Keys) {
                if ($tsUtc -ge ([datetime]$Windows[$wk]).ToUniversalTime()) {
                    $totals[$wk] += $tok
                }
            }
        }
    } catch {
    } finally {
        if ($db) { $db.Dispose() }
    }
    return $totals
}

# 마지막 유효 한도 추정치 파일(limits-last.json)을 읽는다. 숫자와 ISO 시각만 허용한다.
function Read-LimitsLastFile([string]$LastFile) {
    $res = [ordered]@{}
    if (-not $LastFile -or -not (Test-Path -LiteralPath $LastFile -PathType Leaf)) { return $res }
    try {
        $fs = [System.IO.File]::Open($LastFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        try {
            $raw = $sr.ReadToEnd().TrimStart([char]0xFEFF)
        } finally {
            $sr.Dispose()
        }
        if (-not $raw.Trim()) { return $res }
        $obj = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if ($null -eq $obj) { return $res }
        $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        $schema = [ordered]@{
            claude = @("five_hour", "seven_day")
            gemini = @("five_hour", "weekly")
        }
        foreach ($src in $schema.Keys) {
            if (-not $obj.PSObject.Properties[$src] -or $null -eq $obj.$src) { continue }
            $srcObj = $obj.$src
            $srcOut = [ordered]@{}
            foreach ($wk in $schema[$src]) {
                if (-not $srcObj.PSObject.Properties[$wk] -or $null -eq $srcObj.$wk) { continue }
                $e = $srcObj.$wk
                $estVal = 0L
                if ($null -eq $e.est -or ($e.est -is [bool]) -or ($e.est -is [string])) { continue }
                try { $estVal = [long]$e.est } catch { continue }
                if ($estVal -le 0) { continue }
                $atStr = [string]$e.estimated_at
                if (-not $atStr) { continue }
                $dt = [datetime]::MinValue
                if (-not [datetime]::TryParse($atStr, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) { continue }
                $srcOut[$wk] = [ordered]@{
                    est          = $estVal
                    estimated_at = $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
            if ($srcOut.Count -gt 0) { $res[$src] = $srcOut }
        }
    } catch {
        return [ordered]@{}
    }
    return $res
}

# 마지막 유효 한도 추정치 파일(limits-last.json)을 원자적으로 저장한다. 숫자와 ISO 시각만 기록한다.
function Write-LimitsLastFile([string]$LastFile, $Data) {
    if (-not $LastFile -or -not $Data) { return }
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $schema = [ordered]@{
        claude = @("five_hour", "seven_day")
        gemini = @("five_hour", "weekly")
    }
    $clean = [ordered]@{}
    foreach ($src in $schema.Keys) {
        if (-not $Data.Contains($src)) { continue }
        $srcMap = $Data.Item($src)
        if (-not $srcMap) { continue }
        $srcClean = [ordered]@{}
        foreach ($wk in $schema[$src]) {
            if (-not $srcMap.Contains($wk)) { continue }
            $e = $srcMap.Item($wk)
            if (-not $e) { continue }
            $estVal = 0L
            try { $estVal = [long]$e.est } catch { continue }
            if ($estVal -le 0) { continue }
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParse([string]$e.estimated_at, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) { continue }
            $srcClean[$wk] = [ordered]@{
                est          = $estVal
                estimated_at = $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
        if ($srcClean.Count -gt 0) { $clean[$src] = $srcClean }
    }
    if ($clean.Count -eq 0) { return }

    $tmp = "$LastFile.$PID.tmp"
    try {
        $dir = Split-Path -Path $LastFile -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $json = ConvertTo-Json -InputObject $clean -Depth 4 -Compress
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Remove-Item -LiteralPath $LastFile -Force -ErrorAction SilentlyContinue
        [System.IO.File]::Move($tmp, $LastFile)
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Claude · agy 의 5시간 / 주간 추정 한도 스냅샷을 계산한다.
# 반환: @{ claude = @{ five_hour = @{ est; used_pct; resets_at }; seven_day = @{...} }; gemini = @{ five_hour = ...; weekly = ... } }
# 새 계산이 비어 있는 창은 <runtime dir>\limits-last.json 의 마지막 유효 추정치를 stale=true 로 돌려준다.
function Get-LimitsEstimateSnapshot([string]$RuntimeDir, [string]$DbPath, [string]$ProjectsDir, [datetime]$NowUtc = [datetime]::MinValue, $AgyQuotaSnapshot = $null) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $nowIso = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $fresh = [ordered]@{}

    $buildEntry = {
        param([long]$winTokens, [double]$usedPct, [string]$resetIso)
        if ($usedPct -lt 3.0 -or $winTokens -le 0) { return $null }
        $est = Round-LimitEstimate ($winTokens / ($usedPct / 100.0)) 3
        if ($est -le 0) { return $null }
        return [ordered]@{
            est       = $est
            used_pct  = [math]::Round($usedPct, 1)
            resets_at = $resetIso
        }
    }

    $parseUtc = {
        param([string]$s)
        if (-not $s) { return $null }
        $dt = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
            return $dt.ToUniversalTime()
        }
        return $null
    }

    # 1. Claude
    $cLimitsFile = if ($RuntimeDir) { Join-Path $RuntimeDir "claude-limits.json" } else { "" }
    $cSnap = Read-ClaudeLimitsFile $cLimitsFile
    if ($cSnap -and $cSnap.checked_at) {
        $cChecked = & $parseUtc ([string]$cSnap.checked_at)
        if ($null -ne $cChecked -and ($now - $cChecked).TotalHours -le 6.0) {
            $cWindows = @{}
            $cMeta = @{}
            foreach ($spec in @(@{ key = "five_hour"; hours = 5 }, @{ key = "seven_day"; hours = 168 })) {
                $k = $spec.key
                if (-not $cSnap.Contains($k)) { continue }
                $e = $cSnap.Item($k)
                $pct = [double]$e.used_pct
                $rStr = [string]$e.resets_at
                $rDt = & $parseUtc $rStr
                if ($pct -ge 3.0 -and $null -ne $rDt -and $rDt -gt $now) {
                    $cWindows[$k] = $rDt.AddHours(-$spec.hours)
                    $cMeta[$k] = @{ pct = $pct; reset = $rDt.ToString("yyyy-MM-ddTHH:mm:ssZ") }
                }
            }
            if ($cWindows.Count -gt 0) {
                $cCache = if ($RuntimeDir) { Join-Path $RuntimeDir "claude-window-cache.json" } else { "" }
                $cTokens = Get-ClaudeWindowTokens $ProjectsDir $cCache $cWindows $now
                $cOut = [ordered]@{}
                foreach ($k in @("five_hour", "seven_day")) {
                    if (-not $cMeta.ContainsKey($k)) { continue }
                    $ent = & $buildEntry ([long]$cTokens.Item($k)) ([double]$cMeta[$k].pct) ([string]$cMeta[$k].reset)
                    if ($null -ne $ent) { $cOut[$k] = $ent }
                }
                if ($cOut.Count -gt 0) { $fresh["claude"] = $cOut }
            }
        }
    }

    # 2. agy (Gemini 5h/주간 공용 한도)
    $aSnap = $AgyQuotaSnapshot
    if ($null -eq $aSnap -and $RuntimeDir -and (Get-Command Read-AgyQuotaCache -ErrorAction SilentlyContinue)) {
        $aSnap = Read-AgyQuotaCache (Join-Path $RuntimeDir "agy-quota.json")
    }
    if ($aSnap -and $aSnap.checked_at) {
        $aChecked = & $parseUtc ([string]$aSnap.checked_at)
        if ($null -ne $aChecked -and ($now - $aChecked).TotalHours -le 6.0) {
            $aWindows = @{}
            $aMeta = @{}
            foreach ($spec in @(
                @{ key = "gemini_5h"; hours = 5 },
                @{ key = "gemini_weekly"; hours = 168 }
            )) {
                $k = $spec.key
                $e = $aSnap.$k
                if ($null -eq $e -or $null -eq $e.pct -or -not $e.reset) { continue }
                $usedPct = 100.0 - [double]$e.pct
                $rDt = & $parseUtc ([string]$e.reset)
                if ($usedPct -ge 3.0 -and $null -ne $rDt -and $rDt -gt $now) {
                    $aWindows[$k] = $rDt.AddHours(-$spec.hours)
                    $aMeta[$k] = @{ pct = $usedPct; reset = $rDt.ToString("yyyy-MM-ddTHH:mm:ssZ") }
                }
            }
            if ($aWindows.Count -gt 0) {
                $aTokens = Get-AgyWindowTokens $DbPath $aWindows $now
                $gemOut = [ordered]@{}
                if ($aMeta.ContainsKey("gemini_5h")) {
                    $ent = & $buildEntry ([long]$aTokens.Item("gemini_5h")) ([double]$aMeta["gemini_5h"].pct) ([string]$aMeta["gemini_5h"].reset)
                    if ($null -ne $ent) { $gemOut["five_hour"] = $ent }
                }
                if ($aMeta.ContainsKey("gemini_weekly")) {
                    $ent = & $buildEntry ([long]$aTokens.Item("gemini_weekly")) ([double]$aMeta["gemini_weekly"].pct) ([string]$aMeta["gemini_weekly"].reset)
                    if ($null -ne $ent) { $gemOut["weekly"] = $ent }
                }
                if ($gemOut.Count -gt 0) { $fresh["gemini"] = $gemOut }
            }
        }
    }

    # 3. 마지막 유효 추정치(limits-last.json) 저장 및 폴백 병합
    $lastFile = if ($RuntimeDir) { Join-Path $RuntimeDir "limits-last.json" } else { "" }
    $saved = if ($lastFile) { Read-LimitsLastFile $lastFile } else { [ordered]@{} }
    $savedDirty = $false
    $out = [ordered]@{}
    $schema = [ordered]@{
        claude = @("five_hour", "seven_day")
        gemini = @("five_hour", "weekly")
    }
    foreach ($src in $schema.Keys) {
        $srcFresh = if ($fresh.Contains($src)) { $fresh.Item($src) } else { $null }
        $srcSaved = if ($saved.Contains($src)) { $saved.Item($src) } else { $null }
        $srcOut = [ordered]@{}
        foreach ($wk in $schema[$src]) {
            if ($srcFresh -and $srcFresh.Contains($wk) -and $null -ne $srcFresh.Item($wk)) {
                $fe = $srcFresh.Item($wk)
                $srcOut[$wk] = $fe
                if (-not $saved.Contains($src)) { $saved[$src] = [ordered]@{} }
                $saved.Item($src)[$wk] = [ordered]@{
                    est          = [long]$fe.est
                    estimated_at = $nowIso
                }
                $savedDirty = $true
            } elseif ($srcSaved -and $srcSaved.Contains($wk) -and $null -ne $srcSaved.Item($wk)) {
                $se = $srcSaved.Item($wk)
                $srcOut[$wk] = [ordered]@{
                    est          = [long]$se.est
                    estimated_at = [string]$se.estimated_at
                    stale        = $true
                }
            }
        }
        if ($srcOut.Count -gt 0) { $out[$src] = $srcOut }
    }
    if ($savedDirty -and $lastFile) {
        Write-LimitsLastFile $lastFile $saved
    }

    return $out
}
