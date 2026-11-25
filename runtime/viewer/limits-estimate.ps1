# limits-estimate.ps1
# Claude · agy 의 5시간 / 주간 한도 크기(토큰)를 추정합니다.
# 뷰어(serve-viewer.ps1)가 dot-source 해서 쓰고, 한 번 계산한 결과를 최대 60초까지 캐시합니다.
# 개인정보 보호: claude-window-cache.json 에는 파일 경로 해시 · 오프셋 · 메시지 ID · 시각(epoch) · 토큰 합만 저장하고 경로·이름·프롬프트는 쓰지 않습니다.

if (-not (Get-Command Get-SessionsRatio -ErrorAction SilentlyContinue)) {
    foreach ($uhCand in @(
        (Join-Path (Split-Path $PSScriptRoot -Parent) "delegate-agy\scripts\sub\usage-history.ps1"),
        (Join-Path $PSScriptRoot "..\delegate-agy\scripts\sub\usage-history.ps1"),
        (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\usage-history.ps1")
    )) {
        if ($uhCand -and (Test-Path -LiteralPath $uhCand -PathType Leaf)) {
            try { . $uhCand; break } catch {}
        }
    }
}

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

# ~/.claude/projects/**/*.jsonl (subagents\*.jsonl 포함) 에서 assistant 메시지별(message.id 중복 제거) 모델 · 토큰 내역을 증분 수집한다.
# 캐시 v2 도 경로·이메일·본문 없이 해시 키 · 오프셋 · 메시지 ID · epoch · 모델명 · 토큰 4종만 저장한다.
function Get-ClaudeTranscriptMessages([string]$ProjectsDir, [string]$CacheFile, [datetime]$OldestUtc = [datetime]::MinValue, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    if (-not $ProjectsDir -or -not (Test-Path -LiteralPath $ProjectsDir -PathType Container)) { return @() }

    if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
        Add-Type -AssemblyName System.Web.Extensions
    }
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue
    $js.RecursionLimit = 256

    $oldestDt = if ($OldestUtc -ne [datetime]::MinValue) { $OldestUtc.ToUniversalTime() } else { $now.AddDays(-15) }
    $pruneDt = $now.AddDays(-62)
    if ($oldestDt.AddDays(-1) -lt $pruneDt) { $pruneDt = $oldestDt.AddDays(-1) }
    $pruneCutoffEpoch = ([DateTimeOffset]$pruneDt).ToUnixTimeSeconds()

    $cacheFiles = @{}
    $dirty = $false
    if ($CacheFile -and (Test-Path -LiteralPath $CacheFile -PathType Leaf)) {
        try {
            $cRaw = [System.IO.File]::ReadAllText($CacheFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
            if ($cRaw.Trim()) {
                $cObj = $js.DeserializeObject($cRaw)
                if (($cObj -is [System.Collections.IDictionary]) -and ([int]$cObj["version"] -eq 2) -and ($cObj["files"] -is [System.Collections.IDictionary])) {
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
                                        $msgsMap[[string]$mk] = @{
                                            ts = $tsE
                                            m  = [string]$mv["m"]
                                            i  = [long]$mv["i"]
                                            cc = [long]$mv["cc"]
                                            cr = [long]$mv["cr"]
                                            o  = [long]$mv["o"]
                                        }
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
                } else {
                    $dirty = $true
                }
            }
        } catch {
            $cacheFiles = @{}
        }
    }

    $toLong = {
        param($val)
        if ($null -eq $val -or $val -is [bool] -or $val -is [string]) { return 0L }
        try { return [long]$val } catch { return 0L }
    }
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal

    $jsonlFiles = @(Get-ChildItem -LiteralPath $ProjectsDir -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue)
    foreach ($f in $jsonlFiles) {
        if ($f.LastWriteTimeUtc -lt $oldestDt) { continue }
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
                            if (-not [datetime]::TryParse($tsStr, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$tsDt)) { continue }
                            $tsEpoch = ([DateTimeOffset]$tsDt.ToUniversalTime()).ToUnixTimeSeconds()
                            if ($tsEpoch -lt $pruneCutoffEpoch) { continue }

                            $inT = & $toLong $usage["input_tokens"]
                            $ccT = & $toLong $usage["cache_creation_input_tokens"]
                            if ($ccT -eq 0 -and ($usage["cache_creation"] -is [System.Collections.IDictionary])) {
                                $ccd = $usage["cache_creation"]
                                $ccT = (& $toLong $ccd["ephemeral_5m_input_tokens"]) + (& $toLong $ccd["ephemeral_1h_input_tokens"])
                            }
                            $crT = & $toLong $usage["cache_read_input_tokens"]
                            $outT = & $toLong $usage["output_tokens"]
                            $mid = if ($msg["id"]) { [string]$msg["id"] } elseif ($obj["uuid"]) { [string]$obj["uuid"] } else { "" }
                            if (-not $mid) { continue }

                            if ($entry.msgs.ContainsKey($mid)) {
                                $prev = $entry.msgs[$mid]
                                if ($inT -gt $prev.i) { $prev.i = $inT }
                                if ($ccT -gt $prev.cc) { $prev.cc = $ccT }
                                if ($crT -gt $prev.cr) { $prev.cr = $crT }
                                if ($outT -gt $prev.o) { $prev.o = $outT }
                                if ($tsEpoch -gt $prev.ts) { $prev.ts = $tsEpoch }
                                if ($model -and -not $prev.m) { $prev.m = $model }
                            } else {
                                $entry.msgs[$mid] = @{ ts = $tsEpoch; m = $model; i = $inT; cc = $ccT; cr = $crT; o = $outT }
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
            $payload = @{ version = 2; files = $cacheFiles }
            $json = $js.Serialize($payload)
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
            Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
            [System.IO.File]::Move($tmp, $CacheFile)
        } catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    # 모든 파일에서 message.id 별로 중복을 없앤 뒤 시간순 목록을 돌려준다
    $globalMsgs = @{}
    foreach ($fk in $cacheFiles.Keys) {
        $msgs = $cacheFiles[$fk].msgs
        foreach ($mk in $msgs.Keys) {
            $mv = $msgs[$mk]
            if ($globalMsgs.ContainsKey($mk)) {
                $gm = $globalMsgs[$mk]
                if ($mv.i -gt $gm.i) { $gm.i = $mv.i }
                if ($mv.cc -gt $gm.cc) { $gm.cc = $mv.cc }
                if ($mv.cr -gt $gm.cr) { $gm.cr = $mv.cr }
                if ($mv.o -gt $gm.o) { $gm.o = $mv.o }
                if ($mv.ts -gt $gm.ts) { $gm.ts = $mv.ts }
                if ($mv.m -and -not $gm.m) { $gm.m = $mv.m }
            } else {
                $globalMsgs[$mk] = @{ ts = $mv.ts; m = $mv.m; i = $mv.i; cc = $mv.cc; cr = $mv.cr; o = $mv.o }
            }
        }
    }

    $list = New-Object System.Collections.ArrayList
    foreach ($gm in $globalMsgs.Values) {
        [void]$list.Add([pscustomobject]@{
            ts = [long]$gm.ts
            m  = [string]$gm.m
            i  = [long]$gm.i
            cc = [long]$gm.cc
            cr = [long]$gm.cr
            o  = [long]$gm.o
        })
    }
    return @($list.ToArray() | Sort-Object ts)
}

# ~/.claude/projects/**/*.jsonl (subagents\*.jsonl 포함) 에서 구간 시작 시각 이후 assistant 토큰 합계를 증분 계산한다.
# $Windows: @{ five_hour = [datetime]$StartUtc; seven_day = [datetime]$StartUtc }
function Get-ClaudeWindowTokens([string]$ProjectsDir, [string]$CacheFile, $Windows, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $totals = @{}
    if (-not $Windows -or $Windows.Count -eq 0) { return $totals }
    foreach ($wk in $Windows.Keys) { $totals[$wk] = 0L }
    if (-not $ProjectsDir -or -not (Test-Path -LiteralPath $ProjectsDir -PathType Container)) { return $totals }

    $oldestStart = $now
    $winStartEpochs = @{}
    $winEndEpochs = @{}
    foreach ($wk in $Windows.Keys) {
        $wSpec = $Windows[$wk]
        if ($wSpec -is [System.Collections.IDictionary]) {
            $sDt = ([datetime]$wSpec["start"]).ToUniversalTime()
            $eDt = if ($wSpec.Contains("end") -and $null -ne $wSpec["end"]) { ([datetime]$wSpec["end"]).ToUniversalTime() } else { $now }
        } else {
            $sDt = ([datetime]$wSpec).ToUniversalTime()
            $eDt = $now
        }
        if ($sDt -lt $oldestStart) { $oldestStart = $sDt }
        $winStartEpochs[$wk] = ([DateTimeOffset]$sDt).ToUnixTimeSeconds()
        $winEndEpochs[$wk] = ([DateTimeOffset]$eDt).ToUnixTimeSeconds()
    }

    $msgs = @(Get-ClaudeTranscriptMessages $ProjectsDir $CacheFile $oldestStart $now)
    foreach ($gm in $msgs) {
        $tot = [long]$gm.i + [long]$gm.cc + [long]$gm.cr + [long]$gm.o
        foreach ($wk in $winStartEpochs.Keys) {
            if ($gm.ts -ge $winStartEpochs[$wk] -and $gm.ts -le $winEndEpochs[$wk]) {
                $totals[$wk] += $tot
            }
        }
    }

    return $totals
}

# task_quota · tasks · task_models · usage-history 에서 위임별 agy 비용 가중 한도 추정치를 결정적으로 계산한다.
# 같은 DB 파일의 task_quota(행 수·최신 measured_at), tasks(행 수·최신 timestamp), task_models(행 수)와
# usage-history.jsonl 및 models.json 이 바뀌지 않으면 메모리 캐시를 재사용한다.
$script:AgyTaskEstimatesCache = @{}
$script:AgyQuotaCostConfigCache = @{ Stamp = ""; Value = $null }

function Get-AgyQuotaCostConfig {
    $defWeights = @{
        "hydrogen"          = 0.5
        "neon"              = 1.0
        "carbon"            = (4.0 / 3.0)
        "orchestrator-neon" = 0.75
        "orchestrator"      = 0.85
        "default"           = 1.0
    }
    $defCache = 0.1
    $defOutput = 5.0

    $cfgDir = ""
    if ($env:AGY_MODELS_CONFIG_DIR) {
        $cfgDir = [string]$env:AGY_MODELS_CONFIG_DIR
    } else {
        $c1 = Join-Path (Split-Path $PSScriptRoot -Parent) "delegate-agy\config"
        $c2 = Join-Path $env:USERPROFILE ".samjil\delegate-agy\config"
        if (Test-Path -LiteralPath (Join-Path $c1 "models.json") -PathType Leaf) { $cfgDir = $c1 }
        elseif (Test-Path -LiteralPath (Join-Path $c2 "models.json") -PathType Leaf) { $cfgDir = $c2 }
        else { $cfgDir = $c1 }
    }

    $mainPath = if ($cfgDir) { Join-Path $cfgDir "models.json" } else { "" }
    $localPath = if ($cfgDir) { Join-Path $cfgDir "models.local.json" } else { "" }
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in @($mainPath, $localPath)) {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
            if ($null -ne $fi) { [void]$parts.Add(("{0}:{1}:{2}" -f $p.ToLowerInvariant(), [long]$fi.Length, [long]$fi.LastWriteTimeUtc.Ticks)) }
        }
    }
    $stamp = ($parts.ToArray() -join "|")
    if ($script:AgyQuotaCostConfigCache.Stamp -eq $stamp -and $null -ne $script:AgyQuotaCostConfigCache.Value) {
        return $script:AgyQuotaCostConfigCache.Value
    }

    $weights = @{}
    foreach ($k in $defWeights.Keys) { $weights[$k] = [double]$defWeights[$k] }
    $cacheW = $defCache
    $outputW = $defOutput

    $toPosDouble = {
        param($val)
        if ($null -eq $val -or ($val -is [bool])) { return $null }
        $d = 0.0
        if ($val -is [double] -or $val -is [float] -or $val -is [decimal] -or $val -is [int] -or $val -is [long] -or $val -is [short] -or $val -is [byte]) {
            $d = [double]$val
        } elseif (-not [double]::TryParse(([string]$val).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            return $null
        }
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d) -or $d -le 0.0) { return $null }
        return $d
    }

    foreach ($p in @($mainPath, $localPath)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        try {
            $raw = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
            if (-not $raw.Trim()) { continue }
            $obj = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
            if ($null -eq $obj -or -not $obj.PSObject.Properties["quota_cost"] -or $null -eq $obj.quota_cost) { continue }
            $qc = $obj.quota_cost
            if ($qc.PSObject.Properties["cache"]) {
                $cv = & $toPosDouble $qc.cache
                if ($null -ne $cv) { $cacheW = [double]$cv }
            }
            if ($qc.PSObject.Properties["output"]) {
                $ov = & $toPosDouble $qc.output
                if ($null -ne $ov) { $outputW = [double]$ov }
            }
            if ($qc.PSObject.Properties["weights"] -and $null -ne $qc.weights) {
                foreach ($wp in $qc.weights.PSObject.Properties) {
                    $wv = & $toPosDouble $wp.Value
                    if ($null -ne $wv) {
                        $weights[([string]$wp.Name).Trim().ToLowerInvariant()] = [double]$wv
                    }
                }
            }
        } catch {}
    }

    $cfg = @{
        Weights = $weights
        Cache   = $cacheW
        Output  = $outputW
        Stamp   = $stamp
    }
    $script:AgyQuotaCostConfigCache = @{ Stamp = $stamp; Value = $cfg }
    return $cfg
}

function Get-AgyModelCostWeight([string]$ModelName, $CostCfg) {
    $wMap = $CostCfg.Weights
    $m = ([string]$ModelName).Trim().ToLowerInvariant()
    if ($m -match 'orchestrator') {
        if ($m -match 'neon') {
            if ($wMap.ContainsKey('orchestrator-neon')) { return [double]$wMap['orchestrator-neon'] }
            return 0.75
        }
        if ($wMap.ContainsKey('orchestrator')) { return [double]$wMap['orchestrator'] }
        return 0.85
    }
    if ($m -match 'hydrogen') {
        if ($wMap.ContainsKey('hydrogen')) { return [double]$wMap['hydrogen'] }
        return 0.5
    }
    if ($m -match 'neon') {
        if ($wMap.ContainsKey('neon')) { return [double]$wMap['neon'] }
        return 1.0
    }
    if ($m -match 'carbon') {
        if ($wMap.ContainsKey('carbon')) { return [double]$wMap['carbon'] }
        return (4.0 / 3.0)
    }
    if ($wMap.ContainsKey('default')) { return [double]$wMap['default'] }
    return 1.0
}

function Get-AgyTaskCostUnits($TaskInfo, $TaskModels, $CostCfg) {
    $modelCost = 0.0
    $sumIn = 0.0
    $sumOut = 0.0
    $cacheW = [double]$CostCfg.Cache
    $outW = [double]$CostCfg.Output
    foreach ($tm in @($TaskModels)) {
        if ($null -eq $tm) { continue }
        $w = Get-AgyModelCostWeight ([string]$tm.model) $CostCfg
        $inT = [double]$tm.input
        $caT = [double]$tm.cache
        $ouT = [double]$tm.output
        $modelCost += $w * ($inT + ($cacheW * $caT) + ($outW * $ouT))
        $sumIn += $inT
        $sumOut += $ouT
    }

    $wFb = Get-AgyModelCostWeight ([string]$TaskInfo.Model) $CostCfg
    $inRem = 0.0
    $outRem = 0.0
    if ($TaskInfo.HasInOut) {
        $inRem = [math]::Max(0.0, [double]$TaskInfo.InputTokens - $sumIn)
        $outRem = [math]::Max(0.0, [double]$TaskInfo.OutputTokens - $sumOut)
    } else {
        $remTot = [math]::Max(0.0, [double]$TaskInfo.TotalTokens - ($sumIn + $sumOut))
        if ($remTot -gt 0.0) {
            if (($sumIn + $sumOut) -gt 0.0) {
                $outRatio = $sumOut / ($sumIn + $sumOut)
                $outRem = $remTot * $outRatio
                $inRem = $remTot * (1.0 - $outRatio)
            } else {
                $inRem = $remTot
                $outRem = 0.0
            }
        }
    }

    return ($modelCost + ($wFb * ($inRem + ($outW * $outRem))))
}

# Claude 비용 가중 설정(추정 단가 비율, Opus 입력 등가 단위 — models.json / models.local.json 의 quota_cost.claude 로 조정 가능)
$script:ClaudeQuotaCostConfigCache = @{ Stamp = ""; Value = $null }
$script:ClaudeLimitsEstimatesCache = @{}

function Get-ClaudeQuotaCostConfig {
    $defWeights = @{
        "opus"    = 1.0
        "sonnet"  = 0.6
        "haiku"   = 0.2
        "default" = 1.0
    }
    $defCacheWrite = 1.25
    $defCacheRead = 0.1
    $defOutput = 5.0

    $cfgDir = ""
    if ($env:AGY_MODELS_CONFIG_DIR) {
        $cfgDir = [string]$env:AGY_MODELS_CONFIG_DIR
    } else {
        $c1 = Join-Path (Split-Path $PSScriptRoot -Parent) "delegate-agy\config"
        $c2 = Join-Path $env:USERPROFILE ".samjil\delegate-agy\config"
        if (Test-Path -LiteralPath (Join-Path $c1 "models.json") -PathType Leaf) { $cfgDir = $c1 }
        elseif (Test-Path -LiteralPath (Join-Path $c2 "models.json") -PathType Leaf) { $cfgDir = $c2 }
        else { $cfgDir = $c1 }
    }

    $mainPath = if ($cfgDir) { Join-Path $cfgDir "models.json" } else { "" }
    $localPath = if ($cfgDir) { Join-Path $cfgDir "models.local.json" } else { "" }
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in @($mainPath, $localPath)) {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
            if ($null -ne $fi) { [void]$parts.Add(("{0}:{1}:{2}" -f $p.ToLowerInvariant(), [long]$fi.Length, [long]$fi.LastWriteTimeUtc.Ticks)) }
        }
    }
    $stamp = ($parts.ToArray() -join "|")
    if ($script:ClaudeQuotaCostConfigCache.Stamp -eq $stamp -and $null -ne $script:ClaudeQuotaCostConfigCache.Value) {
        return $script:ClaudeQuotaCostConfigCache.Value
    }

    $weights = @{}
    foreach ($k in $defWeights.Keys) { $weights[$k] = [double]$defWeights[$k] }
    $cw = $defCacheWrite
    $cr = $defCacheRead
    $outW = $defOutput

    $toPosDouble = {
        param($val)
        if ($null -eq $val -or ($val -is [bool])) { return $null }
        $d = 0.0
        if ($val -is [double] -or $val -is [float] -or $val -is [decimal] -or $val -is [int] -or $val -is [long] -or $val -is [short] -or $val -is [byte]) {
            $d = [double]$val
        } elseif (-not [double]::TryParse(([string]$val).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            return $null
        }
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d) -or $d -le 0.0) { return $null }
        return $d
    }

    foreach ($p in @($mainPath, $localPath)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        try {
            $raw = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
            if (-not $raw.Trim()) { continue }
            $obj = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
            if ($null -eq $obj -or -not $obj.PSObject.Properties["quota_cost"] -or $null -eq $obj.quota_cost) { continue }
            $qc = $obj.quota_cost
            if (-not ($qc.PSObject.Properties["claude"] -and $null -ne $qc.claude)) { continue }
            $cc = $qc.claude
            foreach ($prop in $cc.PSObject.Properties) {
                $pname = ([string]$prop.Name).Trim().ToLowerInvariant()
                $pv = & $toPosDouble $prop.Value
                if ($null -eq $pv) { continue }
                if ($pname -eq "cache_write") { $cw = [double]$pv }
                elseif ($pname -eq "cache_read") { $cr = [double]$pv }
                elseif ($pname -eq "output") { $outW = [double]$pv }
                elseif ($pname -in @("opus", "sonnet", "haiku", "default")) { $weights[$pname] = [double]$pv }
            }
        } catch {}
    }

    $cfg = @{
        Weights    = $weights
        CacheWrite = $cw
        CacheRead  = $cr
        Output     = $outW
        Stamp      = $stamp
    }
    $script:ClaudeQuotaCostConfigCache = @{ Stamp = $stamp; Value = $cfg }
    return $cfg
}

function Get-ClaudeModelCostWeight([string]$ModelName, $CostCfg) {
    $wMap = $CostCfg.Weights
    $m = ([string]$ModelName).Trim().ToLowerInvariant()
    if ($m -match 'opus') {
        if ($wMap.ContainsKey('opus')) { return [double]$wMap['opus'] }
        return 1.0
    }
    if ($m -match 'sonnet') {
        if ($wMap.ContainsKey('sonnet')) { return [double]$wMap['sonnet'] }
        return 0.6
    }
    if ($m -match 'haiku') {
        if ($wMap.ContainsKey('haiku')) { return [double]$wMap['haiku'] }
        return 0.2
    }
    if ($wMap.ContainsKey('default')) { return [double]$wMap['default'] }
    return 1.0
}

function Get-ClaudeMessageCostUnits([string]$ModelName, [double]$InTok, [double]$CcTok, [double]$CrTok, [double]$OutTok, $CostCfg) {
    $w = Get-ClaudeModelCostWeight $ModelName $CostCfg
    return ($w * ($InTok + ([double]$CostCfg.CacheWrite * $CcTok) + ([double]$CostCfg.CacheRead * $CrTok) + ([double]$CostCfg.Output * $OutTok)))
}

function Get-AgyTaskQuotaStamp([string]$DbPath) {
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return "" }
    if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) { return "" }
    $db = $null
    try {
        $db = Open-AgyDb $DbPath
        $rows = @($db.Query(
            "SELECT (SELECT COUNT(*) FROM task_quota) AS qn, (SELECT MAX(measured_at) FROM task_quota) AS qm, (SELECT COUNT(*) FROM tasks) AS tn, (SELECT MAX(timestamp) FROM tasks) AS tm, (SELECT COUNT(*) FROM task_models) AS mn",
            $null
        ))
        if ($rows.Count -eq 0) { return "" }
        $qCnt = [int64]$rows[0]["qn"]
        $qMaxAt = if ($null -ne $rows[0]["qm"]) { [string]$rows[0]["qm"] } else { "" }
        $tCnt = [int64]$rows[0]["tn"]
        $tMaxTs = if ($null -ne $rows[0]["tm"]) { [string]$rows[0]["tm"] } else { "" }
        $mCnt = [int64]$rows[0]["mn"]
        return ("{0}|{1}|{2}|{3}|{4}" -f $qCnt, $qMaxAt, $tCnt, $tMaxTs, $mCnt)
    } catch {
        return ""
    } finally {
        if ($db) { $db.Dispose() }
    }
}

function Get-AgyTaskEstimatesInternal([string]$DbPath, [string]$RuntimeDir = "") {
    $emptyRes = @{ Estimates = @{}; Latest = [ordered]@{}; Stamp = "" }
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return $emptyRes }
    if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) { return $emptyRes }

    if ($RuntimeDir) {
        Ensure-UsageHistoryLoadedAndSeeded $RuntimeDir $DbPath
    } elseif (-not (Get-Command Get-SessionsRatio -ErrorAction SilentlyContinue)) {
        $cands = @(
            (Join-Path (Split-Path $PSScriptRoot -Parent) "delegate-agy\scripts\sub\usage-history.ps1"),
            (Join-Path $PSScriptRoot "..\delegate-agy\scripts\sub\usage-history.ps1"),
            (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\usage-history.ps1")
        )
        foreach ($c in $cands) {
            if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
                try { . $c; break } catch {}
            }
        }
    }

    $parseUtcIso = {
        param([string]$s)
        if (-not $s) { return $null }
        $dt = [datetime]::MinValue
        $st = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $st, [ref]$dt)) {
            return $dt.ToUniversalTime()
        }
        return $null
    }

    $parseTaskFinishUtc = {
        param([string]$s, $fallbackUtc = $null)
        if ($s) {
            $dt = [datetime]::MinValue
            if ($s -match '(Z|[+-]\d{2}:?\d{2})$') {
                $st = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $st, [ref]$dt)) {
                    return $dt.ToUniversalTime()
                }
            } else {
                if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) {
                    return $dt.ToUniversalTime()
                }
            }
        }
        return $fallbackUtc
    }

    $costCfg = (Get-AgyQuotaCostConfig)
    $histStamp = if ($RuntimeDir -and (Get-Command Get-UsageHistoryStamp -ErrorAction SilentlyContinue)) { Get-UsageHistoryStamp $RuntimeDir } else { "" }
    $dirKey = if ($RuntimeDir) { try { [System.IO.Path]::GetFullPath($RuntimeDir).ToLowerInvariant() } catch { $RuntimeDir.ToLowerInvariant() } } else { "" }
    $cacheKey = "{0}|{1}" -f ([System.IO.Path]::GetFullPath($DbPath).ToLowerInvariant()), $dirKey

    $db = $null
    $qRows = @()
    $taskRows = @()
    $modelsByTid = @{}
    try {
        $db = Open-AgyDb $DbPath
        $sRows = @($db.Query(
            "SELECT (SELECT COUNT(*) FROM task_quota) AS qn, (SELECT MAX(measured_at) FROM task_quota) AS qm, (SELECT COUNT(*) FROM tasks) AS tn, (SELECT MAX(timestamp) FROM tasks) AS tm, (SELECT COUNT(*) FROM task_models) AS mn",
            $null
        ))
        $cnt = if ($sRows.Count -gt 0) { [int64]$sRows[0]["qn"] } else { 0L }
        $maxAt = if ($sRows.Count -gt 0 -and $null -ne $sRows[0]["qm"]) { [string]$sRows[0]["qm"] } else { "" }
        $tCnt = if ($sRows.Count -gt 0) { [int64]$sRows[0]["tn"] } else { 0L }
        $tMaxTs = if ($sRows.Count -gt 0 -and $null -ne $sRows[0]["tm"]) { [string]$sRows[0]["tm"] } else { "" }
        $mCnt = if ($sRows.Count -gt 0) { [int64]$sRows[0]["mn"] } else { 0L }
        $stamp = "{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $cnt, $maxAt, $tCnt, $tMaxTs, $mCnt, $histStamp, $costCfg.Stamp

        if ($script:AgyTaskEstimatesCache.ContainsKey($cacheKey)) {
            $cached = $script:AgyTaskEstimatesCache.Item($cacheKey)
            if ($cached -and $cached.Stamp -eq $stamp) {
                return $cached
            }
        }

        if ($cnt -eq 0) {
            $res0 = @{ Estimates = @{}; Latest = [ordered]@{}; Stamp = $stamp }
            $script:AgyTaskEstimatesCache[$cacheKey] = $res0
            return $res0
        }

        $qRows = @($db.Query(
            "SELECT task_id, measured_at, five_used, five_reset, week_used, week_reset, concurrent FROM task_quota ORDER BY measured_at ASC, rowid ASC",
            $null
        ))

        $earliestUtc = $null
        foreach ($r in $qRows) {
            $mDt = & $parseUtcIso ([string]$r["measured_at"])
            if ($null -ne $mDt) {
                $d15 = $mDt.AddDays(-15)
                if ($null -eq $earliestUtc -or $d15 -lt $earliestUtc) { $earliestUtc = $d15 }
            }
            foreach ($pair in @(@{ col = "five_reset"; hours = 5 }, @{ col = "week_reset"; hours = 168 })) {
                $rawR = if ($null -ne $r[$pair.col]) { [string]$r[$pair.col] } else { "" }
                if (-not $rawR) { continue }
                $rUtc = & $parseUtcIso $rawR
                if ($null -eq $rUtc) { continue }
                $wStart = $rUtc.AddHours(-$pair.hours).AddDays(-1)
                if ($null -eq $earliestUtc -or $wStart -lt $earliestUtc) { $earliestUtc = $wStart }
            }
        }

        if ($null -ne $earliestUtc) {
            $lowerBoundLocal = $earliestUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
            $taskRows = @($db.Query(
                "SELECT task_id, timestamp, model, input_tokens, output_tokens, total_tokens, elapsed_sec, status, usage_basis FROM tasks WHERE timestamp IS NOT NULL AND timestamp <> '' AND timestamp >= ?",
                [object[]]@($lowerBoundLocal)
            ))
        } else {
            $taskRows = @($db.Query(
                "SELECT task_id, timestamp, model, input_tokens, output_tokens, total_tokens, elapsed_sec, status, usage_basis FROM tasks WHERE timestamp IS NOT NULL AND timestamp <> ''",
                $null
            ))
        }

        if (Get-Command Get-TaskModelsMap -ErrorAction SilentlyContinue) {
            $modelsByTid = (Get-TaskModelsMap $db)
        }
    } catch {
        return $emptyRes
    } finally {
        if ($db) { $db.Dispose() }
    }

    $quotaTaskIds = @{}
    foreach ($qr in $qRows) {
        $qTid = [string]$qr["task_id"]
        if ($qTid) { $quotaTaskIds[$qTid] = $true }
    }

    # 모든 agy 작업(실패·취소 포함)을 파싱한다. 겹침 판정과 비정상 종료 오염 구간 차단에 모두 필요하다.
    $agyTasks = New-Object System.Collections.ArrayList
    $taskById = @{}
    $tryDbl = {
        param($val)
        if ($null -eq $val -or ($val -is [bool])) { return @{ Ok = $false; Val = 0.0 } }
        $s = ([string]$val).Trim()
        if (-not $s) { return @{ Ok = $false; Val = 0.0 } }
        $d = 0.0
        if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            if (-not [double]::IsNaN($d) -and -not [double]::IsInfinity($d)) {
                return @{ Ok = $true; Val = $d }
            }
        }
        return @{ Ok = $false; Val = 0.0 }
    }

    foreach ($tr in $taskRows) {
        $tid = [string]$tr["task_id"]
        if (-not $tid) { continue }
        $mdl = if ($null -ne $tr["model"]) { [string]$tr["model"] } else { "" }
        $status = if ($null -ne $tr["status"]) { ([string]$tr["status"]).Trim() } else { "" }
        if ($mdl -match '(?i)claude') { continue }
        if ($mdl) {
            if ($mdl -notmatch '(?i)gemini|orchestrator') { continue }
        } else {
            if ($status -ieq 'OK' -and -not $quotaTaskIds.ContainsKey($tid)) { continue }
        }

        $tsStr = if ($null -ne $tr["timestamp"]) { [string]$tr["timestamp"] } else { "" }
        $finUtc = & $parseTaskFinishUtc $tsStr $null
        if ($null -eq $finUtc) { continue }
        $elRes = & $tryDbl $tr["elapsed_sec"]
        $elapsedSec = if ($elRes.Ok -and $elRes.Val -gt 0.0) { $elRes.Val } else { 0.0 }
        $startUtc = if ($elapsedSec -gt 0.0) { $finUtc.AddSeconds(-$elapsedSec) } else { $finUtc }

        $inRes = & $tryDbl $tr["input_tokens"]
        $outRes = & $tryDbl $tr["output_tokens"]
        $totRes = & $tryDbl $tr["total_tokens"]
        $inTok = if ($inRes.Ok -and $inRes.Val -gt 0.0) { $inRes.Val } else { 0.0 }
        $outTok = if ($outRes.Ok -and $outRes.Val -gt 0.0) { $outRes.Val } else { 0.0 }
        $hasInOut = (($inRes.Ok -or $outRes.Ok) -and ($inTok + $outTok -gt 0.0))
        $totTok = if ($totRes.Ok -and $totRes.Val -gt 0.0) { $totRes.Val } elseif ($hasInOut) { $inTok + $outTok } else { 0.0 }

        $basis = if ($null -ne $tr["usage_basis"]) { ([string]$tr["usage_basis"]).Trim().ToLowerInvariant() } else { "" }
        $tModels = if ($modelsByTid.ContainsKey($tid)) { @($modelsByTid[$tid]) } else { @() }

        $tInfo = @{
            TaskId       = $tid
            Model        = $mdl
            Status       = $status
            Basis        = $basis
            FinUtc       = $finUtc
            StartUtc     = $startUtc
            ElapsedSec   = $elapsedSec
            InputTokens  = $inTok
            OutputTokens = $outTok
            HasInOut     = $hasInOut
            TotalTokens  = $totTok
        }
        $costUnits = if ($totTok -gt 0.0) { Get-AgyTaskCostUnits $tInfo $tModels $costCfg } else { 0.0 }
        $isCleanTask = ($status -ieq 'OK') -and ($totTok -gt 0.0) -and ($costUnits -gt 0.0) -and ($basis -notin @('cumulative', 'delta*'))

        $tObj = [pscustomobject]@{
            TaskId      = $tid
            Model       = $mdl
            Status      = $status
            Basis       = $basis
            FinUtc      = $finUtc
            StartUtc    = $startUtc
            TotalTokens = $totTok
            CostUnits   = $costUnits
            IsCleanTask = $isCleanTask
        }
        $taskById[$tid] = $tObj
        [void]$agyTasks.Add($tObj)
    }

    # task_quota 목록 정리
    $quotaList = New-Object System.Collections.ArrayList
    foreach ($r in $qRows) {
        $tid = [string]$r["task_id"]
        if (-not $tid) { continue }
        $mAtStr = if ($null -ne $r["measured_at"]) { [string]$r["measured_at"] } else { "" }
        $mAtUtc = & $parseUtcIso $mAtStr
        if ($null -eq $mAtUtc) { continue }

        $fUsed = $null
        if ($null -ne $r["five_used"]) { try { $fUsed = [double]$r["five_used"] } catch {} }
        $fResetUtc = if ($null -ne $r["five_reset"]) { & $parseUtcIso ([string]$r["five_reset"]) } else { $null }
        $wUsed = $null
        if ($null -ne $r["week_used"]) { try { $wUsed = [double]$r["week_used"] } catch {} }
        $wResetUtc = if ($null -ne $r["week_reset"]) { & $parseUtcIso ([string]$r["week_reset"]) } else { $null }
        $conc = if ($null -ne $r["concurrent"] -and [int]$r["concurrent"] -ne 0) { 1 } else { 0 }

        $tRec = if ($taskById.ContainsKey($tid)) { $taskById[$tid] } else { $null }
        $finUtc = if ($null -ne $tRec) { $tRec.FinUtc } else { $mAtUtc }

        [void]$quotaList.Add([pscustomobject]@{
            Idx          = $quotaList.Count
            TaskId       = $tid
            MatIso       = $mAtUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            MatUtc       = $mAtUtc
            FinUtc       = $finUtc
            FiveUsed     = $fUsed
            FiveResetUtc = $fResetUtc
            WeekUsed     = $wUsed
            WeekResetUtc = $wResetUtc
            Concurrent   = $conc
            TaskCost     = if ($null -ne $tRec) { [double]$tRec.CostUnits } else { 0.0 }
            TaskTokens   = if ($null -ne $tRec) { [double]$tRec.TotalTokens } else { 0.0 }
        })
    }

    if ($quotaList.Count -eq 0) {
        $res0 = @{ Estimates = @{}; Latest = [ordered]@{}; Stamp = $stamp }
        $script:AgyTaskEstimatesCache[$cacheKey] = $res0
        return $res0
    }

    # usage-history.jsonl 이 있으면 우선 사용하고, 없으면 task_quota 행으로 동일 포맷 샘플을 합성한다.
    $histSamples = @()
    if ($RuntimeDir -and (Get-Command Read-UsageHistory -ErrorAction SilentlyContinue)) {
        $histSamples = @(Read-UsageHistory -RuntimeDir $RuntimeDir -Src "agy")
    }
    if ($histSamples.Count -eq 0) {
        $synList = New-Object System.Collections.ArrayList
        $prevSig = ""
        foreach ($q in $quotaList) {
            if ($null -eq $q.FiveUsed -or $null -eq $q.FiveResetUtc -or $null -eq $q.WeekUsed -or $null -eq $q.WeekResetUtc) { continue }
            $frIso = $q.FiveResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $wrIso = $q.WeekResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $fInt = [int][math]::Round($q.FiveUsed, [System.MidpointRounding]::AwayFromZero)
            $wInt = [int][math]::Round($q.WeekUsed, [System.MidpointRounding]::AwayFromZero)
            $sig = "{0}|{1}|{2}|{3}" -f $fInt, $frIso, $wInt, $wrIso
            if ($sig -eq $prevSig) { continue }
            $prevSig = $sig
            [void]$synList.Add([ordered]@{
                src        = "agy"
                at         = $q.MatIso
                five       = $fInt
                five_reset = $frIso
                week       = $wInt
                week_reset = $wrIso
            })
        }
        $histSamples = @($synList.ToArray())
    }

    # 1.2.1 정지 체크포인트 선별: concurrent==0 이고 다른 agy 작업(실패·취소 포함)의 [start-5s, fin+5s]가 [fin, mat] 와 겹치지 않아야 함
    $quiescent = New-Object System.Collections.ArrayList
    foreach ($q in $quotaList) {
        if ($q.Concurrent -ne 0) { continue }
        $measStart = if ($q.FinUtc -lt $q.MatUtc) { $q.FinUtc } else { $q.MatUtc }
        $measEnd = if ($q.FinUtc -gt $q.MatUtc) { $q.FinUtc } else { $q.MatUtc }
        $overlaps = $false
        foreach ($t in $agyTasks) {
            if ($t.TaskId -eq $q.TaskId) { continue }
            if ($t.StartUtc.AddSeconds(-5) -le $measEnd -and $t.FinUtc.AddSeconds(5) -ge $measStart) {
                $overlaps = $true
                break
            }
        }
        if (-not $overlaps) {
            [void]$quiescent.Add($q)
        }
    }

    # 1.2.2 ~ 1.2.4 인접 정지 체크포인트 쌍 (a, b) 로 후보 클린 세그먼트를 구성한다
    $candidateSegs = New-Object System.Collections.ArrayList
    $segByEndIdx = @{}
    $hasSessCmd = [bool](Get-Command Get-SessionsRatio -ErrorAction SilentlyContinue)

    for ($qi = 1; $qi -lt $quiescent.Count; $qi++) {
        $a = $quiescent[$qi - 1]
        $b = $quiescent[$qi]

        $segTasks = New-Object System.Collections.ArrayList
        foreach ($t in $agyTasks) {
            if ($t.TaskId -eq $a.TaskId) { continue }
            if ($t.TaskId -eq $b.TaskId -or ($t.FinUtc -gt $a.FinUtc -and $t.FinUtc -le $b.FinUtc)) {
                [void]$segTasks.Add($t)
            }
        }
        if ($segTasks.Count -eq 0) { continue }

        $allClean = $true
        $segN = 0.0
        $segC = 0.0
        $minStartUtc = $null
        $aStartBound = $a.FinUtc.AddSeconds(-5)
        foreach ($st in $segTasks) {
            if (-not $st.IsCleanTask -or $st.StartUtc -lt $aStartBound) {
                $allClean = $false
                break
            }
            $segN += $st.TotalTokens
            $segC += $st.CostUnits
            if ($null -eq $minStartUtc -or $st.StartUtc -lt $minStartUtc) {
                $minStartUtc = $st.StartUtc
            }
        }
        if (-not $allClean -or $segN -le 0.0 -or $segC -le 0.0 -or $null -eq $minStartUtc) { continue }

        $idleMin = ($minStartUtc - $a.MatUtc).TotalMinutes
        $isSingle = ($segTasks.Count -eq 1)

        # 주간 적격 판정 (5시간 창과 독립)
        $hasWeek = $false
        $deltaW = 0.0
        $weekFrom = $null
        $weekTo = $null
        if ($null -ne $a.WeekUsed -and $null -ne $a.WeekResetUtc -and $null -ne $b.WeekUsed -and $null -ne $b.WeekResetUtc) {
            if ($a.WeekUsed -lt 100.0 -and $b.WeekUsed -lt 100.0 -and [math]::Abs(($b.WeekResetUtc - $a.WeekResetUtc).TotalSeconds) -le 120.0) {
                $dw = $b.WeekUsed - $a.WeekUsed
                if ($dw -ge 0.0) {
                    $hasWeek = $true
                    $deltaW = $dw
                    $weekFrom = $a.WeekUsed
                    $weekTo = $b.WeekUsed
                }
            }
        }

        # 5시간 적격 판정 (동일 창 또는 새 창 시작 합성 0% 앵커)
        $hasFive = $false
        $delta5 = 0.0
        $fiveFrom = $null
        $fiveTo = $null
        $isSyn5 = $false
        if ($null -ne $a.FiveUsed -and $null -ne $a.FiveResetUtc -and $null -ne $b.FiveUsed -and $null -ne $b.FiveResetUtc -and $b.FiveUsed -lt 100.0) {
            $frDiff = ($b.FiveResetUtc - $a.FiveResetUtc).TotalSeconds
            if ([math]::Abs($frDiff) -le 120.0) {
                if ($a.FiveUsed -lt 100.0) {
                    $d5 = $b.FiveUsed - $a.FiveUsed
                    if ($d5 -ge 0.0) {
                        $hasFive = $true
                        $delta5 = $d5
                        $fiveFrom = $a.FiveUsed
                        $fiveTo = $b.FiveUsed
                    }
                }
            } elseif ($frDiff -ge 17880.0 -and $frDiff -le 18120.0 -and $b.FiveUsed -ge 0.0) {
                $t0 = $b.FiveResetUtc.AddHours(-5)
                $afterT0 = ($minStartUtc -ge $t0)
                if ($afterT0) {
                    $preWindowTask = $false
                    foreach ($ot in $agyTasks) {
                        if ($ot.TaskId -eq $a.TaskId) { continue }
                        if ($ot.FinUtc -gt $a.FinUtc -and $ot.StartUtc -le $t0) {
                            $preWindowTask = $true
                            break
                        }
                    }
                    if (-not $preWindowTask) {
                        $nearReset = ((($t0 - $a.MatUtc).TotalMinutes -le 15.0) -and (($a.MatUtc - $t0).TotalSeconds -le 120.0))
                        $weekAligned = $false
                        if (-not $nearReset -and $hasWeek) {
                            $r0 = 4.0
                            if ($hasSessCmd) {
                                $rPre = (Get-SessionsRatio -Samples $histSamples -UntilUtc $b.MatUtc -MinWeekPoints 3 -MinFivePoints 1)
                                if ($null -ne $rPre -and $rPre.ratio -gt 0) { $r0 = [double]$rPre.ratio }
                            }
                            if ([math]::Abs(($deltaW * $r0) - $b.FiveUsed) -le 1.5) {
                                $weekAligned = $true
                            }
                        }
                        if ($nearReset -or $weekAligned) {
                            $hasFive = $true
                            $delta5 = $b.FiveUsed
                            $fiveFrom = 0.0
                            $fiveTo = $b.FiveUsed
                            $isSyn5 = $true
                        }
                    }
                }
            }
        }

        if (-not $hasFive -and -not $hasWeek) { continue }

        $segObj = [pscustomobject]@{
            EndQuotaIdx  = $b.Idx
            EndTaskId    = $b.TaskId
            EndMatUtc    = $b.MatUtc
            SegN         = $segN
            SegC         = $segC
            IdleMin      = $idleMin
            IsSingleTask = $isSingle
            HasFive      = $hasFive
            Delta5       = $delta5
            FiveFrom     = $fiveFrom
            FiveTo       = $fiveTo
            IsSyn5       = $isSyn5
            HasWeek      = $hasWeek
            DeltaW       = $deltaW
            WeekFrom     = $weekFrom
            WeekTo       = $weekTo
        }
        [void]$candidateSegs.Add($segObj)
        $segByEndIdx[$b.Idx] = $segObj
    }

    # 1.3 ~ 1.4, 4.1 ~ 4.3 각 작업 시점(measured_at)까지의 데이터만 사용해 결정적 추정치를 계산한다
    $rowResults = New-Object System.Collections.ArrayList
    foreach ($q in $quotaList) {
        $k = $q.Idx
        $cutoff = $q.MatUtc
        $winStart14 = $cutoff.AddDays(-14)

        $cand5 = New-Object System.Collections.ArrayList
        $l0Samples = New-Object System.Collections.ArrayList
        foreach ($s in $candidateSegs) {
            if ($s.EndQuotaIdx -gt $k) { break }
            if ($s.EndMatUtc -lt $winStart14 -or -not $s.HasFive) { continue }
            [void]$cand5.Add($s)
            if ($s.Delta5 -ge 2.0) {
                [void]$l0Samples.Add((100.0 * $s.SegC / $s.Delta5))
            }
        }

        # 1.2.5 예비 단가 L0 및 외부 미기록 사용 이상치 게이트
        $l0 = 12000000.0
        if ($l0Samples.Count -ge 3) {
            $sortedL0 = @($l0Samples.ToArray() | Sort-Object)
            $mid = [int][math]::Floor($sortedL0.Count / 2)
            if (($sortedL0.Count % 2) -eq 1) {
                $l0 = [double]$sortedL0[$mid]
            } else {
                $l0 = ([double]$sortedL0[$mid - 1] + [double]$sortedL0[$mid]) / 2.0
            }
            if ($l0 -le 0.0) { $l0 = 12000000.0 }
        }

        $clean5 = New-Object System.Collections.ArrayList
        $rejectedEndIdx = @{}
        $sumDelta5 = 0.0
        foreach ($s in $cand5) {
            $expD5 = 100.0 * $s.SegC / $l0
            $isOutlier = ((($s.Delta5 - 1.0) -gt [math]::Max((2.0 * $expD5), ($expD5 + 2.0))) -or ($s.IdleMin -gt 30.0 -and ($s.Delta5 - $expD5) -gt 1.5))
            if ($isOutlier) {
                $rejectedEndIdx[$s.EndQuotaIdx] = $true
                continue
            }
            [void]$clean5.Add($s)
            $sumDelta5 += $s.Delta5
        }

        $l5c = 0.0
        $l5raw = 0.0
        $fiveInitial = $false
        $fivePtsInt = [int][math]::Round($sumDelta5, [System.MidpointRounding]::AwayFromZero)
        if ($sumDelta5 -ge 10.0) {
            $sumWC = 0.0
            $sumWN = 0.0
            $sumWD5 = 0.0
            foreach ($s in $clean5) {
                $ageDays = [math]::Max(0.0, ($cutoff - $s.EndMatUtc).TotalDays)
                $g = [math]::Pow(2.0, -($ageDays / 7.0))
                $sumWC += ($g * $s.SegC)
                $sumWN += ($g * $s.SegN)
                $sumWD5 += ($g * $s.Delta5)
            }
            if ($sumWD5 -gt 0.0 -and $sumWC -gt 0.0 -and $sumWN -gt 0.0) {
                $l5c = 100.0 * $sumWC / $sumWD5
                $l5raw = 100.0 * $sumWN / $sumWD5
                $fiveInitial = ($sumDelta5 -lt 20.0)
            }
        }

        $sess = $null
        if ($hasSessCmd) {
            $sess = (Get-SessionsRatio -Samples $histSamples -UntilUtc $cutoff -MinWeekPoints 5 -MinFivePoints 20)
        }

        $lwc = 0.0
        $lwraw = 0.0
        if ($l5c -gt 0.0 -and $sumDelta5 -ge 20.0 -and $null -ne $sess -and $sess.week_points -gt 0) {
            $rExact = [double]$sess.five_points / [double]$sess.week_points
            if ($rExact -gt 0.0) {
                $lwc = $rExact * $l5c
                $lwraw = $rExact * $l5raw
            }
        }

        $measured = $null
        if ($segByEndIdx.ContainsKey($k)) {
            $endSeg = $segByEndIdx[$k]
            if ($endSeg.IsSingleTask -and -not $rejectedEndIdx.ContainsKey($k)) {
                $mMap = [ordered]@{}
                if ($endSeg.HasFive) {
                    $mMap["five_delta"] = [int][math]::Round($endSeg.Delta5, [System.MidpointRounding]::AwayFromZero)
                    $mMap["five_from"] = [int][math]::Round($endSeg.FiveFrom, [System.MidpointRounding]::AwayFromZero)
                    $mMap["five_to"] = [int][math]::Round($endSeg.FiveTo, [System.MidpointRounding]::AwayFromZero)
                }
                if ($endSeg.HasWeek) {
                    $mMap["week_delta"] = [int][math]::Round($endSeg.DeltaW, [System.MidpointRounding]::AwayFromZero)
                    $mMap["week_from"] = [int][math]::Round($endSeg.WeekFrom, [System.MidpointRounding]::AwayFromZero)
                    $mMap["week_to"] = [int][math]::Round($endSeg.WeekTo, [System.MidpointRounding]::AwayFromZero)
                }
                if ($mMap.Count -gt 0) { $measured = $mMap }
            }
        }

        [void]$rowResults.Add([pscustomobject]@{
            Quota       = $q
            AtUtc       = $q.MatUtc
            AtIso       = $q.MatIso
            WeekResetUtc = $q.WeekResetUtc
            L5C         = $l5c
            L5Raw       = $l5raw
            FivePoints  = $fivePtsInt
            FiveInitial = $fiveInitial
            LWC         = $lwc
            LWRaw       = $lwraw
            Sessions    = $sess
            Measured    = $measured
        })
    }

    # 3.7 같은 주간 창 안에서 임계치 미달 초기 카드를 해당 주간 창의 첫 수렴 추정치로 백필한다
    $weekGroups = New-Object System.Collections.ArrayList
    $curWg = $null
    $curWgReset = [datetime]::MinValue
    foreach ($rr in $rowResults) {
        $wr = $rr.Quota.WeekResetUtc
        if ($null -eq $wr) {
            [void]$weekGroups.Add(@($rr))
            $curWg = $null
            $curWgReset = [datetime]::MinValue
            continue
        }
        if ($null -eq $curWg -or [math]::Abs(($wr - $curWgReset).TotalSeconds) -gt 120.0) {
            $curWg = New-Object System.Collections.ArrayList
            [void]$weekGroups.Add($curWg)
            $curWgReset = $wr
        }
        [void]$curWg.Add($rr)
    }

    $estMap = @{}
    foreach ($wg in $weekGroups) {
        $first5 = $null
        $firstW = $null
        foreach ($rr in $wg) {
            if ($null -eq $first5 -and $rr.L5C -gt 0.0) { $first5 = $rr }
            if ($null -eq $firstW -and $rr.LWC -gt 0.0) { $firstW = $rr }
        }

        foreach ($rr in $wg) {
            $q = $rr.Quota
            $tid = $q.TaskId
            $cardEnt = [ordered]@{
                measured_at = $q.MatIso
                cost_units  = [math]::Round($q.TaskCost, 2)
            }

            if ($rr.L5C -gt 0.0) {
                $fh = [ordered]@{
                    est         = (Round-LimitEstimate $rr.L5Raw 3)
                    est_cost    = [long][math]::Round($rr.L5C, [System.MidpointRounding]::AwayFromZero)
                    five_points = [int]$rr.FivePoints
                }
                if ($null -ne $q.FiveUsed) { $fh["used_pct"] = [math]::Round($q.FiveUsed, 1) }
                if ($q.TaskCost -gt 0.0) { $fh["share_pct"] = [math]::Round((100.0 * $q.TaskCost / $rr.L5C), 2) }
                if ($rr.FiveInitial) { $fh["initial"] = $true }
                $cardEnt["five_hour"] = $fh
            } elseif ($null -ne $first5) {
                $fh = [ordered]@{
                    est          = (Round-LimitEstimate $first5.L5Raw 3)
                    est_cost     = [long][math]::Round($first5.L5C, [System.MidpointRounding]::AwayFromZero)
                    five_points  = [int]$first5.FivePoints
                    stale        = $true
                    backfill     = $true
                    estimated_at = $first5.Quota.MatIso
                }
                if ($null -ne $q.FiveUsed) { $fh["used_pct"] = [math]::Round($q.FiveUsed, 1) }
                if ($q.TaskCost -gt 0.0) { $fh["share_pct"] = [math]::Round((100.0 * $q.TaskCost / $first5.L5C), 2) }
                if ($first5.FiveInitial) { $fh["initial"] = $true }
                $cardEnt["five_hour"] = $fh
            }

            $effSess = $null
            if ($rr.LWC -gt 0.0) {
                $wk = [ordered]@{
                    est      = (Round-LimitEstimate $rr.LWRaw 3)
                    est_cost = [long][math]::Round($rr.LWC, [System.MidpointRounding]::AwayFromZero)
                }
                if ($null -ne $q.WeekUsed) { $wk["used_pct"] = [math]::Round($q.WeekUsed, 1) }
                if ($q.TaskCost -gt 0.0) { $wk["share_pct"] = [math]::Round((100.0 * $q.TaskCost / $rr.LWC), 2) }
                $cardEnt["weekly"] = $wk
                $effSess = $rr.Sessions
            } elseif ($null -ne $firstW) {
                $wk = [ordered]@{
                    est          = (Round-LimitEstimate $firstW.LWRaw 3)
                    est_cost     = [long][math]::Round($firstW.LWC, [System.MidpointRounding]::AwayFromZero)
                    stale        = $true
                    backfill     = $true
                    estimated_at = $firstW.Quota.MatIso
                }
                if ($null -ne $q.WeekUsed) { $wk["used_pct"] = [math]::Round($q.WeekUsed, 1) }
                if ($q.TaskCost -gt 0.0) { $wk["share_pct"] = [math]::Round((100.0 * $q.TaskCost / $firstW.LWC), 2) }
                $cardEnt["weekly"] = $wk
                $effSess = $firstW.Sessions
            }

            if ($null -ne $effSess) { $cardEnt["sessions"] = $effSess }
            if ($null -ne $rr.Measured) { $cardEnt["measured"] = $rr.Measured }

            $estMap[$tid] = $cardEnt
        }
    }

    # 실시간 최신 한도 추정치는 마지막 행의 비-백필(현재 시점 임계치 충족) 값만 사용한다
    $latest = [ordered]@{}
    $latestBasis = @{ five_points = 0; week_points = 0; sessions_five_points = 0 }
    if ($rowResults.Count -gt 0) {
        $lastRr = $rowResults[$rowResults.Count - 1]
        $lq = $lastRr.Quota
        $latestBasis.five_points = [int]$lastRr.FivePoints
        if ($lastRr.Sessions) {
            $latestBasis.week_points = [int]$lastRr.Sessions.week_points
            $latestBasis.sessions_five_points = [int]$lastRr.Sessions.five_points
        } elseif ($hasSessCmd) {
            $unSess = (Get-SessionsRatio -Samples $histSamples -UntilUtc $lq.MatUtc -MinWeekPoints 1 -MinFivePoints 1)
            if ($null -ne $unSess) {
                $latestBasis.week_points = [int]$unSess.week_points
                $latestBasis.sessions_five_points = [int]$unSess.five_points
            }
        }
        if ($lastRr.L5C -gt 0.0) {
            $lfh = [ordered]@{
                est         = (Round-LimitEstimate $lastRr.L5Raw 3)
                est_cost    = [long][math]::Round($lastRr.L5C, [System.MidpointRounding]::AwayFromZero)
                five_points = [int]$lastRr.FivePoints
            }
            if ($null -ne $lq.FiveUsed) { $lfh["used_pct"] = [math]::Round($lq.FiveUsed, 1) }
            if ($lastRr.FiveInitial) { $lfh["initial"] = $true }
            $latest["five_hour"] = $lfh
        }
        if ($lastRr.LWC -gt 0.0) {
            $lwk = [ordered]@{
                est      = (Round-LimitEstimate $lastRr.LWRaw 3)
                est_cost = [long][math]::Round($lastRr.LWC, [System.MidpointRounding]::AwayFromZero)
            }
            if ($null -ne $lq.WeekUsed) { $lwk["used_pct"] = [math]::Round($lq.WeekUsed, 1) }
            $latest["weekly"] = $lwk
            if ($null -ne $lastRr.Sessions) { $latest["sessions"] = $lastRr.Sessions }
        }
    }

    $res = @{
        Estimates  = $estMap
        Latest     = $latest
        Timeline   = @($rowResults.ToArray())
        WeekGroups = @($weekGroups.ToArray())
        Basis      = $latestBasis
        Stamp      = $stamp
    }
    $script:AgyTaskEstimatesCache[$cacheKey] = $res
    return $res
}

# 특정 시점($RefUtc)에 유효한 한도 추정치를 타임라인 · 주간 그룹에서 조회한다(Claude · agy 공용).
# 해당 시점까지 임계치를 못 넘겼으면 같은 주간 창 안에서 임계치를 처음 넘긴 시점의 추정치(backfill=$true)를 돌려준다.
function Get-LimitsEstimateAtTime($Timeline, $WeekGroups, [datetime]$RefUtc) {
    $res = @{ five_hour = $null; weekly = $null; sessions = $null }
    if ($null -eq $Timeline -or @($Timeline).Count -eq 0) { return $res }
    $ref = $RefUtc.ToUniversalTime()
    $win14 = $ref.AddDays(-14)

    $rr = $null
    foreach ($item in @($Timeline)) {
        if ($item.AtUtc -gt $ref) { break }
        if ($item.AtUtc -ge $win14) { $rr = $item }
    }

    $matchWg = $null
    if ($null -ne $WeekGroups) {
        if ($null -ne $rr -and $null -ne $rr.WeekResetUtc) {
            foreach ($wg in @($WeekGroups)) {
                $wgArr = @($wg)
                if ($wgArr.Count -eq 0) { continue }
                $wr = $wgArr[0].WeekResetUtc
                if ($null -ne $wr -and [math]::Abs(($wr - $rr.WeekResetUtc).TotalSeconds) -le 120.0) {
                    $matchWg = $wgArr
                    break
                }
            }
        }
        if ($null -eq $matchWg) {
            foreach ($wg in @($WeekGroups)) {
                $wgArr = @($wg)
                if ($wgArr.Count -eq 0) { continue }
                $wr = $wgArr[0].WeekResetUtc
                if ($null -ne $wr -and $ref -ge $wr.AddDays(-7).AddSeconds(-120) -and $ref -le $wr.AddSeconds(120)) {
                    $matchWg = $wgArr
                    break
                }
            }
        }
    }

    $first5 = $null
    $firstW = $null
    if ($null -ne $matchWg) {
        foreach ($x in $matchWg) {
            if ($null -eq $first5 -and $x.L5C -gt 0.0) { $first5 = $x }
            if ($null -eq $firstW -and $x.LWC -gt 0.0) { $firstW = $x }
        }
    }

    if ($null -ne $rr -and $rr.L5C -gt 0.0) {
        $fh = [ordered]@{
            est         = (Round-LimitEstimate $rr.L5Raw 3)
            est_cost    = [long][math]::Round($rr.L5C, [System.MidpointRounding]::AwayFromZero)
            five_points = [int]$rr.FivePoints
        }
        if ($rr.FiveInitial) { $fh["initial"] = $true }
        $res.five_hour = $fh
    } elseif ($null -ne $first5) {
        $fh = [ordered]@{
            est          = (Round-LimitEstimate $first5.L5Raw 3)
            est_cost     = [long][math]::Round($first5.L5C, [System.MidpointRounding]::AwayFromZero)
            five_points  = [int]$first5.FivePoints
            backfill     = $true
            estimated_at = $first5.AtIso
        }
        if ($first5.FiveInitial) { $fh["initial"] = $true }
        $res.five_hour = $fh
    }

    if ($null -ne $rr -and $rr.LWC -gt 0.0) {
        $res.weekly = [ordered]@{
            est      = (Round-LimitEstimate $rr.LWRaw 3)
            est_cost = [long][math]::Round($rr.LWC, [System.MidpointRounding]::AwayFromZero)
        }
        $res.sessions = $rr.Sessions
    } elseif ($null -ne $firstW) {
        $res.weekly = [ordered]@{
            est          = (Round-LimitEstimate $firstW.LWRaw 3)
            est_cost     = [long][math]::Round($firstW.LWC, [System.MidpointRounding]::AwayFromZero)
            backfill     = $true
            estimated_at = $firstW.AtIso
        }
        if ($null -ne $firstW.Sessions) {
            $sCopy = [ordered]@{}
            foreach ($sk in $firstW.Sessions.Keys) { $sCopy[$sk] = $firstW.Sessions[$sk] }
            $sCopy["backfill"] = $true
            $sCopy["estimated_at"] = $firstW.AtIso
            $res.sessions = $sCopy
        }
    }

    return $res
}

# Claude 사용률 측정 이력(usage-history.jsonl + claude-limits.json)과 대화 기록(~/.claude/projects)으로
# agy 와 동일한 비용 가중 클린 세그먼트 기반 한도 추정치를 계산한다.
function Get-ClaudeLimitsEstimatesInternal([string]$RuntimeDir, [string]$ProjectsDir, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $emptyRes = @{
        Timeline   = @()
        WeekGroups = @()
        Latest     = [ordered]@{}
        Basis      = @{ five_points = 0; week_points = 0; sessions_five_points = 0 }
        Stamp      = ""
    }
    if (-not $RuntimeDir -and -not $ProjectsDir) { return $emptyRes }

    if ($RuntimeDir) {
        Ensure-UsageHistoryLoadedAndSeeded $RuntimeDir ""
    } elseif (-not (Get-Command Get-SessionsRatio -ErrorAction SilentlyContinue)) {
        $cands = @(
            (Join-Path (Split-Path $PSScriptRoot -Parent) "delegate-agy\scripts\sub\usage-history.ps1"),
            (Join-Path $PSScriptRoot "..\delegate-agy\scripts\sub\usage-history.ps1"),
            (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\usage-history.ps1")
        )
        foreach ($c in $cands) {
            if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
                try { . $c; break } catch {}
            }
        }
    }

    $costCfg = (Get-ClaudeQuotaCostConfig)
    $histStamp = if ($RuntimeDir -and (Get-Command Get-UsageHistoryStamp -ErrorAction SilentlyContinue)) { Get-UsageHistoryStamp $RuntimeDir } else { "" }
    $cLimitsFile = if ($RuntimeDir) { Join-Path $RuntimeDir "claude-limits.json" } else { "" }
    $limStamp = ""
    if ($cLimitsFile -and (Test-Path -LiteralPath $cLimitsFile -PathType Leaf)) {
        $fiLim = Get-Item -LiteralPath $cLimitsFile -ErrorAction SilentlyContinue
        if ($null -ne $fiLim) { $limStamp = ("{0}:{1}" -f [long]$fiLim.Length, [long]$fiLim.LastWriteTimeUtc.Ticks) }
    }
    $maxJsonlTicks = 0L
    if ($ProjectsDir -and (Test-Path -LiteralPath $ProjectsDir -PathType Container)) {
        foreach ($jf in @(Get-ChildItem -LiteralPath $ProjectsDir -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue)) {
            if ([long]$jf.LastWriteTimeUtc.Ticks -gt $maxJsonlTicks) { $maxJsonlTicks = [long]$jf.LastWriteTimeUtc.Ticks }
        }
    }

    $dirKey = if ($RuntimeDir) { try { [System.IO.Path]::GetFullPath($RuntimeDir).ToLowerInvariant() } catch { $RuntimeDir.ToLowerInvariant() } } else { "" }
    $projKey = if ($ProjectsDir) { try { [System.IO.Path]::GetFullPath($ProjectsDir).ToLowerInvariant() } catch { $ProjectsDir.ToLowerInvariant() } } else { "" }
    $cacheKey = "{0}|{1}" -f $dirKey, $projKey
    $stamp = "{0}|{1}|{2}|{3}|{4}" -f $histStamp, $limStamp, $maxJsonlTicks, $costCfg.Stamp, $now.ToString("yyyy-MM-ddTHH:mm")
    if ($script:ClaudeLimitsEstimatesCache.ContainsKey($cacheKey)) {
        $cached = $script:ClaudeLimitsEstimatesCache.Item($cacheKey)
        if ($cached -and $cached.Stamp -eq $stamp) { return $cached }
    }

    $parseUtc = {
        param([string]$s)
        if (-not $s) { return $null }
        $dt = [datetime]::MinValue
        $st = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $st, [ref]$dt)) {
            return $dt.ToUniversalTime()
        }
        return $null
    }

    $rawReadings = New-Object System.Collections.ArrayList
    if ($RuntimeDir -and (Get-Command Read-UsageHistory -ErrorAction SilentlyContinue)) {
        foreach ($h in @(Read-UsageHistory -RuntimeDir $RuntimeDir -Src "claude")) {
            $atDt = & $parseUtc ([string]$h.at)
            if ($null -eq $atDt) { continue }
            $frDt = & $parseUtc ([string]$h.five_reset)
            $wrDt = & $parseUtc ([string]$h.week_reset)
            [void]$rawReadings.Add([pscustomobject]@{
                AtUtc        = $atDt
                AtIso        = $atDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
                FiveUsed     = [double]$h.five
                FiveResetUtc = $frDt
                WeekUsed     = [double]$h.week
                WeekResetUtc = $wrDt
            })
        }
    }

    $cSnap = Read-ClaudeLimitsFile $cLimitsFile
    if ($cSnap -and $cSnap.checked_at) {
        $cDt = & $parseUtc ([string]$cSnap.checked_at)
        if ($null -ne $cDt) {
            $fU = if ($cSnap.Contains("five_hour")) { [double]$cSnap.five_hour.used_pct } else { $null }
            $fR = if ($cSnap.Contains("five_hour") -and $cSnap.five_hour.Contains("resets_at")) { & $parseUtc ([string]$cSnap.five_hour.resets_at) } else { $null }
            $wU = if ($cSnap.Contains("seven_day")) { [double]$cSnap.seven_day.used_pct } else { $null }
            $wR = if ($cSnap.Contains("seven_day") -and $cSnap.seven_day.Contains("resets_at")) { & $parseUtc ([string]$cSnap.seven_day.resets_at) } else { $null }
            $dup = $false
            foreach ($ex in $rawReadings) {
                if ([math]::Abs(($ex.AtUtc - $cDt).TotalSeconds) -le 2.0) {
                    $fMatch = ($null -eq $fU) -or ([math]::Round($fU, [System.MidpointRounding]::AwayFromZero) -eq [math]::Round($ex.FiveUsed, [System.MidpointRounding]::AwayFromZero))
                    $wMatch = ($null -eq $wU) -or ([math]::Round($wU, [System.MidpointRounding]::AwayFromZero) -eq [math]::Round($ex.WeekUsed, [System.MidpointRounding]::AwayFromZero))
                    if ($fMatch -and $wMatch) { $dup = $true; break }
                }
            }
            if (-not $dup -and ($null -ne $fU -or $null -ne $wU)) {
                [void]$rawReadings.Add([pscustomobject]@{
                    AtUtc        = $cDt
                    AtIso        = $cDt.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    FiveUsed     = $fU
                    FiveResetUtc = $fR
                    WeekUsed     = $wU
                    WeekResetUtc = $wR
                })
            }
        }
    }

    if ($rawReadings.Count -lt 2) {
        $res0 = @{
            Timeline   = @()
            WeekGroups = @()
            Latest     = [ordered]@{}
            Basis      = @{ five_points = 0; week_points = 0; sessions_five_points = 0 }
            Stamp      = $stamp
        }
        $script:ClaudeLimitsEstimatesCache[$cacheKey] = $res0
        return $res0
    }

    $readingList = @($rawReadings.ToArray() | Sort-Object AtUtc)
    $histList = New-Object System.Collections.ArrayList
    $prevSig = ""
    foreach ($rd in $readingList) {
        if ($null -eq $rd.FiveUsed -or $null -eq $rd.FiveResetUtc -or $null -eq $rd.WeekUsed -or $null -eq $rd.WeekResetUtc) { continue }
        $frIso = $rd.FiveResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $wrIso = $rd.WeekResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $fInt = [int][math]::Round($rd.FiveUsed, [System.MidpointRounding]::AwayFromZero)
        $wInt = [int][math]::Round($rd.WeekUsed, [System.MidpointRounding]::AwayFromZero)
        $sig = "{0}|{1}|{2}|{3}" -f $fInt, $frIso, $wInt, $wrIso
        if ($sig -eq $prevSig) { continue }
        $prevSig = $sig
        [void]$histList.Add([ordered]@{
            src        = "claude"
            at         = $rd.AtIso
            five       = $fInt
            five_reset = $frIso
            week       = $wInt
            week_reset = $wrIso
        })
    }
    $histSamples = @($histList.ToArray())

    $oldestStart = $readingList[0].AtUtc
    foreach ($rd in $readingList) {
        if ($null -ne $rd.FiveResetUtc) {
            $ws = $rd.FiveResetUtc.AddHours(-5)
            if ($ws -lt $oldestStart) { $oldestStart = $ws }
        }
    }
    $cCacheFile = if ($RuntimeDir) { Join-Path $RuntimeDir "claude-window-cache.json" } else { "" }
    $rawMsgs = @(Get-ClaudeTranscriptMessages $ProjectsDir $cCacheFile $oldestStart $now)
    $msgArr = New-Object System.Collections.ArrayList
    foreach ($gm in $rawMsgs) {
        $nVal = [double]([long]$gm.i + [long]$gm.cc + [long]$gm.cr + [long]$gm.o)
        if ($nVal -le 0.0) { continue }
        $cVal = Get-ClaudeMessageCostUnits $gm.m ([double]$gm.i) ([double]$gm.cc) ([double]$gm.cr) ([double]$gm.o) $costCfg
        if ($cVal -le 0.0) { continue }
        [void]$msgArr.Add([pscustomobject]@{
            ts = [long]$gm.ts
            n  = $nVal
            c  = $cVal
        })
    }

    $hasSessCmd = [bool](Get-Command Get-SessionsRatio -ErrorAction SilentlyContinue)
    $candidateSegs = New-Object System.Collections.ArrayList
    $mStartHint = 0
    $mCount = $msgArr.Count

    for ($ri = 1; $ri -lt $readingList.Count; $ri++) {
        $a = $readingList[$ri - 1]
        $b = $readingList[$ri]
        if ($b.AtUtc -le $a.AtUtc) { continue }

        $aEpoch = ([DateTimeOffset]$a.AtUtc).ToUnixTimeSeconds()
        $bEpoch = ([DateTimeOffset]$b.AtUtc).ToUnixTimeSeconds()
        while ($mStartHint -lt $mCount -and $msgArr[$mStartHint].ts -le $aEpoch) { $mStartHint++ }

        # 주간 적격 판정 (5시간 창과 독립)
        $hasWeek = $false
        $deltaW = 0.0
        if ($null -ne $a.WeekUsed -and $null -ne $a.WeekResetUtc -and $null -ne $b.WeekUsed -and $null -ne $b.WeekResetUtc) {
            if ($a.WeekUsed -lt 100.0 -and $b.WeekUsed -lt 100.0 -and [math]::Abs(($b.WeekResetUtc - $a.WeekResetUtc).TotalSeconds) -le 120.0) {
                $dw = $b.WeekUsed - $a.WeekUsed
                if ($dw -ge 0.0) {
                    $hasWeek = $true
                    $deltaW = $dw
                }
            }
        }

        # 5시간 적격 판정 (동일 창 또는 새 창 시작 합성 0% 앵커)
        $hasFive = $false
        $delta5 = 0.0
        $segWinStartEpoch = $aEpoch
        if ($null -ne $a.FiveUsed -and $null -ne $a.FiveResetUtc -and $null -ne $b.FiveUsed -and $null -ne $b.FiveResetUtc -and $b.FiveUsed -lt 100.0) {
            $frDiff = ($b.FiveResetUtc - $a.FiveResetUtc).TotalSeconds
            if ([math]::Abs($frDiff) -le 120.0) {
                if ($a.FiveUsed -lt 100.0) {
                    $d5 = $b.FiveUsed - $a.FiveUsed
                    if ($d5 -ge 0.0) {
                        $hasFive = $true
                        $delta5 = $d5
                    }
                }
            } elseif ($frDiff -ge 17880.0 -and $b.FiveUsed -ge 0.0) {
                $t0 = $b.FiveResetUtc.AddHours(-5)
                if ($t0 -ge $a.AtUtc.AddSeconds(-120)) {
                    $t0Epoch = ([DateTimeOffset]$t0).ToUnixTimeSeconds()
                    $hasPreWindowMsg = $false
                    for ($mi = $mStartHint; $mi -lt $mCount; $mi++) {
                        $mts = $msgArr[$mi].ts
                        if ($mts -gt $bEpoch -or $mts -gt $t0Epoch) { break }
                        if ($mts -gt $aEpoch -and $mts -le $t0Epoch) {
                            $hasPreWindowMsg = $true
                            break
                        }
                    }
                    if (-not $hasPreWindowMsg) {
                        $nearReset = ((($t0 - $a.AtUtc).TotalMinutes -le 15.0) -and (($a.AtUtc - $t0).TotalSeconds -le 120.0))
                        $weekAligned = $false
                        if (-not $nearReset -and $hasWeek) {
                            $r0 = 7.0
                            if ($hasSessCmd) {
                                $rPre = (Get-SessionsRatio -Samples $histSamples -UntilUtc $b.AtUtc -MinWeekPoints 3 -MinFivePoints 1)
                                if ($null -ne $rPre -and $rPre.ratio -gt 0) { $r0 = [double]$rPre.ratio }
                            }
                            if ([math]::Abs(($deltaW * $r0) - $b.FiveUsed) -le 1.5) {
                                $weekAligned = $true
                            }
                        }
                        if ($nearReset -or $weekAligned) {
                            $hasFive = $true
                            $delta5 = $b.FiveUsed
                            if ($t0Epoch -gt $segWinStartEpoch) { $segWinStartEpoch = $t0Epoch }
                        }
                    }
                }
            }
        }

        if (-not $hasFive -and -not $hasWeek) { continue }

        $segN = 0.0
        $segC = 0.0
        $minMsgEpoch = 0L
        for ($mi = $mStartHint; $mi -lt $mCount; $mi++) {
            $mItem = $msgArr[$mi]
            if ($mItem.ts -gt $bEpoch) { break }
            if ($mItem.ts -le $segWinStartEpoch) { continue }
            $segN += $mItem.n
            $segC += $mItem.c
            if ($minMsgEpoch -eq 0L -or $mItem.ts -lt $minMsgEpoch) { $minMsgEpoch = $mItem.ts }
        }
        if ($segN -le 0.0 -or $segC -le 0.0 -or $minMsgEpoch -le 0L) { continue }

        $minMsgUtc = [DateTimeOffset]::FromUnixTimeSeconds($minMsgEpoch).UtcDateTime
        $idleMin = ($minMsgUtc - $a.AtUtc).TotalMinutes

        [void]$candidateSegs.Add([pscustomobject]@{
            EndIdx    = $ri
            EndAtUtc  = $b.AtUtc
            SegN      = $segN
            SegC      = $segC
            IdleMin   = $idleMin
            HasFive   = $hasFive
            Delta5    = $delta5
            HasWeek   = $hasWeek
            DeltaW    = $deltaW
        })
    }

    $evalAtCutoff = {
        param([int]$MaxEndIdx, [datetime]$CutoffUtc, $WeekResetVal = $null, [string]$AtIsoVal = "")
        $winStart14 = $CutoffUtc.AddDays(-14)
        $cand5 = New-Object System.Collections.ArrayList
        $l0Samples = New-Object System.Collections.ArrayList
        foreach ($s in $candidateSegs) {
            if ($MaxEndIdx -ge 0 -and $s.EndIdx -gt $MaxEndIdx) { break }
            if ($s.EndAtUtc -gt $CutoffUtc) { break }
            if ($s.EndAtUtc -lt $winStart14 -or -not $s.HasFive) { continue }
            [void]$cand5.Add($s)
            if ($s.Delta5 -ge 2.0) {
                [void]$l0Samples.Add((100.0 * $s.SegC / $s.Delta5))
            }
        }

        $l0 = 12000000.0
        if ($l0Samples.Count -ge 3) {
            $sortedL0 = @($l0Samples.ToArray() | Sort-Object)
            $mid = [int][math]::Floor($sortedL0.Count / 2)
            if (($sortedL0.Count % 2) -eq 1) {
                $l0 = [double]$sortedL0[$mid]
            } else {
                $l0 = ([double]$sortedL0[$mid - 1] + [double]$sortedL0[$mid]) / 2.0
            }
            if ($l0 -le 0.0) { $l0 = 12000000.0 }
        }

        $clean5 = New-Object System.Collections.ArrayList
        $sumDelta5 = 0.0
        foreach ($s in $cand5) {
            $expD5 = 100.0 * $s.SegC / $l0
            $isOutlier = ((($s.Delta5 - 1.0) -gt [math]::Max((2.0 * $expD5), ($expD5 + 2.0))) -or ($s.IdleMin -gt 30.0 -and ($s.Delta5 - $expD5) -gt 1.5))
            if ($isOutlier) { continue }
            [void]$clean5.Add($s)
            $sumDelta5 += $s.Delta5
        }

        $l5c = 0.0
        $l5raw = 0.0
        $fiveInitial = $false
        $fivePtsInt = [int][math]::Round($sumDelta5, [System.MidpointRounding]::AwayFromZero)
        if ($sumDelta5 -ge 10.0) {
            $sumWC = 0.0
            $sumWN = 0.0
            $sumWD5 = 0.0
            foreach ($s in $clean5) {
                $ageDays = [math]::Max(0.0, ($CutoffUtc - $s.EndAtUtc).TotalDays)
                $g = [math]::Pow(2.0, -($ageDays / 7.0))
                $sumWC += ($g * $s.SegC)
                $sumWN += ($g * $s.SegN)
                $sumWD5 += ($g * $s.Delta5)
            }
            if ($sumWD5 -gt 0.0 -and $sumWC -gt 0.0 -and $sumWN -gt 0.0) {
                $l5c = 100.0 * $sumWC / $sumWD5
                $l5raw = 100.0 * $sumWN / $sumWD5
                $fiveInitial = ($sumDelta5 -lt 20.0)
            }
        }

        $sess = $null
        $unSess = $null
        if ($hasSessCmd) {
            $sess = (Get-SessionsRatio -Samples $histSamples -UntilUtc $CutoffUtc -MinWeekPoints 5 -MinFivePoints 20)
            if ($null -eq $sess) {
                $unSess = (Get-SessionsRatio -Samples $histSamples -UntilUtc $CutoffUtc -MinWeekPoints 1 -MinFivePoints 1)
            }
        }

        $lwc = 0.0
        $lwraw = 0.0
        if ($l5c -gt 0.0 -and $sumDelta5 -ge 20.0 -and $null -ne $sess -and $sess.week_points -gt 0) {
            $rExact = [double]$sess.five_points / [double]$sess.week_points
            if ($rExact -gt 0.0) {
                $lwc = $rExact * $l5c
                $lwraw = $rExact * $l5raw
            }
        }

        return [pscustomobject]@{
            AtUtc        = $CutoffUtc
            AtIso        = $(if ($AtIsoVal) { $AtIsoVal } else { $CutoffUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") })
            WeekResetUtc = $WeekResetVal
            L5C          = $l5c
            L5Raw        = $l5raw
            FivePoints   = $fivePtsInt
            FiveInitial  = $fiveInitial
            LWC          = $lwc
            LWRaw        = $lwraw
            Sessions     = $sess
            UnSess       = $unSess
        }
    }

    $rowResults = New-Object System.Collections.ArrayList
    for ($ri = 0; $ri -lt $readingList.Count; $ri++) {
        $rd = $readingList[$ri]
        [void]$rowResults.Add((& $evalAtCutoff $ri $rd.AtUtc $rd.WeekResetUtc $rd.AtIso))
    }

    $weekGroups = New-Object System.Collections.ArrayList
    $curWg = $null
    $curWgReset = [datetime]::MinValue
    foreach ($rr in $rowResults) {
        $wr = $rr.WeekResetUtc
        if ($null -eq $wr) {
            [void]$weekGroups.Add(@($rr))
            $curWg = $null
            $curWgReset = [datetime]::MinValue
            continue
        }
        if ($null -eq $curWg -or [math]::Abs(($wr - $curWgReset).TotalSeconds) -gt 120.0) {
            $curWg = New-Object System.Collections.ArrayList
            [void]$weekGroups.Add($curWg)
            $curWgReset = $wr
        }
        [void]$curWg.Add($rr)
    }

    $lastReading = $readingList[$readingList.Count - 1]
    $liveCutoff = if ($now -ge $lastReading.AtUtc) { $now } else { $lastReading.AtUtc }
    $liveRr = & $evalAtCutoff -1 $liveCutoff $lastReading.WeekResetUtc ($liveCutoff.ToString("yyyy-MM-ddTHH:mm:ssZ"))

    $latest = [ordered]@{}
    $latestBasis = @{
        five_points          = [int]$liveRr.FivePoints
        week_points          = 0
        sessions_five_points = 0
    }
    if ($null -ne $liveRr.Sessions) {
        $latestBasis.week_points = [int]$liveRr.Sessions.week_points
        $latestBasis.sessions_five_points = [int]$liveRr.Sessions.five_points
    } elseif ($null -ne $liveRr.UnSess) {
        $latestBasis.week_points = [int]$liveRr.UnSess.week_points
        $latestBasis.sessions_five_points = [int]$liveRr.UnSess.five_points
    }

    if ($liveRr.L5C -gt 0.0) {
        $lfh = [ordered]@{
            est         = (Round-LimitEstimate $liveRr.L5Raw 3)
            est_cost    = [long][math]::Round($liveRr.L5C, [System.MidpointRounding]::AwayFromZero)
            five_points = [int]$liveRr.FivePoints
        }
        if ($liveRr.FiveInitial) { $lfh["initial"] = $true }
        if ($null -ne $lastReading.FiveUsed -and $null -ne $lastReading.FiveResetUtc -and $lastReading.FiveResetUtc -gt $now) {
            $lfh["used_pct"] = [math]::Round($lastReading.FiveUsed, 1)
            $lfh["resets_at"] = $lastReading.FiveResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $latest["five_hour"] = $lfh
    }
    if ($liveRr.LWC -gt 0.0) {
        $lwk = [ordered]@{
            est      = (Round-LimitEstimate $liveRr.LWRaw 3)
            est_cost = [long][math]::Round($liveRr.LWC, [System.MidpointRounding]::AwayFromZero)
        }
        if ($null -ne $lastReading.WeekUsed -and $null -ne $lastReading.WeekResetUtc -and $lastReading.WeekResetUtc -gt $now) {
            $lwk["used_pct"] = [math]::Round($lastReading.WeekUsed, 1)
            $lwk["resets_at"] = $lastReading.WeekResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $latest["seven_day"] = $lwk
        if ($null -ne $liveRr.Sessions) { $latest["sessions"] = $liveRr.Sessions }
    }

    $res = @{
        Timeline   = @($rowResults.ToArray())
        WeekGroups = @($weekGroups.ToArray())
        Latest     = $latest
        Basis      = $latestBasis
        Stamp      = $stamp
    }
    $script:ClaudeLimitsEstimatesCache[$cacheKey] = $res
    return $res
}

function Get-LatestClaudeLimitsEstimate([string]$RuntimeDir, [string]$ProjectsDir, [datetime]$NowUtc = [datetime]::MinValue) {
    $res = (Get-ClaudeLimitsEstimatesInternal $RuntimeDir $ProjectsDir $NowUtc)
    return $res.Latest
}

function Get-AgyTaskEstimates([string]$DbPath, [string]$RuntimeDir = "") {
    $res = (Get-AgyTaskEstimatesInternal $DbPath $RuntimeDir)
    return $res.Estimates
}

function Get-LatestAgyLimitsEstimate([string]$DbPath, [string]$RuntimeDir = "") {
    $res = (Get-AgyTaskEstimatesInternal $DbPath $RuntimeDir)
    return $res.Latest
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

# 한도 추정 스냅샷을 계산한다.
# Claude · agy 의 5시간 / 주간 추정 한도 스냅샷을 계산한다.
# 반환: @{ claude = @{ five_hour = @{ est; used_pct; resets_at }; seven_day = @{...} }; gemini = @{ five_hour = ...; weekly = ... } }
# 새 계산이 비어 있는 창은 <runtime dir>\limits-last.json 의 마지막 유효 추정치를 stale=true 로 돌려준다.
if ($null -eq $script:UsageHistorySeedAttempted) { $script:UsageHistorySeedAttempted = @{} }

function Ensure-UsageHistoryLoadedAndSeeded([string]$RuntimeDir, [string]$DbPath) {
    if (-not (Get-Command Get-CachedSessionsRatio -ErrorAction SilentlyContinue)) {
        $cands = @(
            (Join-Path (Split-Path $PSScriptRoot -Parent) "delegate-agy\scripts\sub\usage-history.ps1"),
            (Join-Path $PSScriptRoot "..\delegate-agy\scripts\sub\usage-history.ps1"),
            (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\usage-history.ps1")
        )
        foreach ($c in $cands) {
            if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
                try { . $c; break } catch {}
            }
        }
    }
    if ($RuntimeDir -and (Get-Command Initialize-UsageHistorySeed -ErrorAction SilentlyContinue)) {
        $histPath = Join-Path $RuntimeDir "usage-history.jsonl"
        if (-not (Test-Path -LiteralPath $histPath -PathType Leaf)) {
            $seedKey = "{0}|{1}" -f $RuntimeDir.ToLowerInvariant(), ([string]$DbPath).ToLowerInvariant()
            if (-not $script:UsageHistorySeedAttempted.ContainsKey($seedKey)) {
                $script:UsageHistorySeedAttempted[$seedKey] = $true
                Initialize-UsageHistorySeed -RuntimeDir $RuntimeDir -DbPath $DbPath
            }
        }
    }
}

function Get-LimitsEstimateSnapshot([string]$RuntimeDir, [string]$DbPath, [string]$ProjectsDir, [datetime]$NowUtc = [datetime]::MinValue, $AgyQuotaSnapshot = $null) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }

    # 1. 사용률 이력 시드 준비 (Claude · agy)
    if ($RuntimeDir) {
        Ensure-UsageHistoryLoadedAndSeeded $RuntimeDir $DbPath
    }

    $out = [ordered]@{}

    # 2. Claude (usage-history.jsonl + claude-limits.json + ~/.claude/projects 비용 가중 클린 세그먼트 기반 추정치)
    $claudeLatest = (Get-LatestClaudeLimitsEstimate $RuntimeDir $ProjectsDir $now)
    if ($claudeLatest -and @($claudeLatest.Keys).Count -gt 0) {
        $out["claude"] = $claudeLatest
    }

    # 3. agy (task_quota + tasks + task_models 비용 가중 클린 세그먼트 기반 추정치)
    $agyLatest = (Get-LatestAgyLimitsEstimate $DbPath $RuntimeDir)
    if ($agyLatest -and @($agyLatest.Keys).Count -gt 0) {
        $out["gemini"] = $agyLatest
    }

    return $out
}
