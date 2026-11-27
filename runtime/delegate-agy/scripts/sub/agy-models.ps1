# agy-models.ps1
# agy 위임 모델 단계(quick · build · build-hard · feature · feature-carbon · think · think-carbon · deep)를 설정 파일에서 읽는 공용 헬퍼입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-models.ps1")`
#   (watch-agy.ps1 · agy-autotier.ps1 · process-translate.ps1 · submit-task.ps1 · 뷰어가 씁니다)
#
# 설정 파일:
#   <delegate-agy>\config\models.json        기본값. sync-installed.ps1 · install.ps1 이 항상 덮어쓴다.
#   <delegate-agy>\config\models.local.json  사용자 덮어쓰기(선택). 동기화 · 설치가 만들지도 지우지도 않는다.
#     - tiers 는 단계 단위로 합친다: local 에 적은 단계만, 적은 필드만 기본값 위에 덮어쓴다.
#     - 그 밖의 최상위 항목(allowed · aliases · auto · escalate · translate)은 적었으면 통째로 바꾼다.
#   파일이 없으면 아래 내장 기본값, 깨졌으면 내장 기본값 + 경고(Warnings)를 쓴다. 설정 때문에 워처가 멈추지 않게 한다.
#   폴더는 환경변수 AGY_MODELS_CONFIG_DIR 로 바꿀 수 있다(시험용).
#
# 단계 이름 대신 모델 이름(allowed 목록)을 써도 된다. 그때는 그 모델 하나만 쓰고 폴백하지 않는다(원하지 않은 모델의 결과를 조용히 받지 않게).

$script:AgyModelsScriptDir = $PSScriptRoot

# models.json 과 같은 내용. 파일이 없거나 깨졌을 때 쓴다(시험이 둘이 같은지 확인한다).
function Get-AgyModelsBuiltinConfig {
    return @{
        tiers = [ordered]@{
            "quick"          = @{ model = "gemini-4-hydrogen-low";        fallback = @("gemini-4-hydrogen-medium", "gemini-4-neon-low");                               wait_sec = 180 }
            "build"          = @{ model = "gemini-4-hydrogen-medium";     fallback = @("gemini-4-hydrogen-high", "gemini-4-neon-low");                                 wait_sec = 480 }
            "build-high"     = @{ model = "gemini-4-hydrogen-high";       fallback = @("gemini-4-hydrogen-medium", "gemini-4-neon-medium");                            wait_sec = 600 }
            "build-hard"     = @{ model = "gemini-4-neon-medium";         fallback = @("gemini-4-neon-high", "gemini-4-hydrogen-xhigh", "gemini-4-carbon-medium");     wait_sec = 720 }
            "feature"        = @{ model = "gemini-pro-orchestrator-neon"; fallback = @("gemini-4-neon-high", "gemini-pro-orchestrator", "gemini-4-hydrogen-high");     wait_sec = 1200 }
            "feature-carbon" = @{ model = "gemini-pro-orchestrator";      fallback = @("gemini-4-carbon-high", "gemini-pro-orchestrator-neon", "gemini-4-neon-high");  wait_sec = 1200 }
            "think"          = @{ model = "gemini-4-neon-high";           fallback = @("gemini-4-neon-medium", "gemini-4-carbon-high", "gemini-4-hydrogen-high");      wait_sec = 1200 }
            "think-carbon"   = @{ model = "gemini-4-carbon-high";         fallback = @("gemini-4-carbon-medium", "gemini-4-neon-high", "gemini-4-neon-xhigh");         wait_sec = 1200 }
            "deep"           = @{ model = "gemini-4-neon-xhigh";          fallback = @("gemini-4-neon-high", "gemini-4-carbon-high", "gemini-4-hydrogen-xhigh");       wait_sec = 1200 }
        }
        escalate        = @{ "build" = "build-hard"; "build-high" = "build-hard"; "build-hard" = "deep" }
        auto            = @{ read = "quick"; write = "build" }
        aliases         = @{ low = "quick"; medium = "build"; high = "build-hard"; "think-argon" = "think-carbon"; "feature-argon" = "feature-carbon" }
        translate       = "quick"
        allowed         = @(
            "gemini-4-hydrogen-low", "gemini-4-hydrogen-medium", "gemini-4-hydrogen-high", "gemini-4-hydrogen-xhigh",
            "gemini-4-neon-low", "gemini-4-neon-medium", "gemini-4-neon-high", "gemini-4-neon-xhigh",
            "gemini-4-carbon-low", "gemini-4-carbon-medium", "gemini-4-carbon-high",
            "gemini-pro-orchestrator-neon", "gemini-pro-orchestrator"
        )
    }
}

# 설정 폴더: AGY_MODELS_CONFIG_DIR > <이 파일>\..\..\config (scripts\sub 기준) > <이 파일>\..\config (scripts 기준)
function Get-AgyModelsConfigDir {
    if ($env:AGY_MODELS_CONFIG_DIR) { return [string]$env:AGY_MODELS_CONFIG_DIR }
    $base = [string]$script:AgyModelsScriptDir
    if (-not $base) { return "" }
    $c1 = Join-Path (Split-Path (Split-Path $base -Parent) -Parent) "config"
    if (Test-Path -LiteralPath (Join-Path $c1 "models.json")) { return $c1 }
    $c2 = Join-Path (Split-Path $base -Parent) "config"
    if (Test-Path -LiteralPath (Join-Path $c2 "models.json")) { return $c2 }
    return $c1
}

# PSCustomObject(ConvertFrom-Json 결과)를 hashtable · 배열로 바꾼다(PowerShell 5.1 에는 -AsHashtable 이 없다).
function ConvertTo-AgyModelsHashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-AgyModelsHashtable $p.Value }
        return $h
    }
    if ($obj -is [System.Array]) { return , @($obj | ForEach-Object { ConvertTo-AgyModelsHashtable $_ }) }
    return $obj
}

function Read-AgyModelsJson([string]$Path, [System.Collections.ArrayList]$Warnings) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $obj = $text | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj -or -not ($obj -is [System.Management.Automation.PSCustomObject])) { throw "JSON 객체가 아닙니다" }
        return (ConvertTo-AgyModelsHashtable $obj)
    } catch {
        [void]$Warnings.Add("모델 설정 파일을 읽지 못해 무시합니다: $Path ($($_.Exception.Message))")
        return $null
    }
}

# 단계 하나를 검사해 정리한다. 모델이 없으면 $null(그 단계는 기본값을 쓴다).
function ConvertTo-AgyTierEntry($raw, $base, [string]$name, [System.Collections.ArrayList]$Warnings) {
    $model = if ($base) { [string]$base.model } else { "" }
    $fallback = if ($base) { @($base.fallback) } else { @() }
    $wait = if ($base) { [int]$base.wait_sec } else { 600 }
    if ($raw -is [System.Collections.IDictionary]) {
        if ($raw.Contains("model") -and ([string]$raw["model"]).Trim()) { $model = ([string]$raw["model"]).Trim() }
        if ($raw.Contains("fallback")) { $fallback = @(@($raw["fallback"]) | Where-Object { $_ -and ([string]$_).Trim() } | ForEach-Object { ([string]$_).Trim() }) }
        if ($raw.Contains("wait_sec")) {
            $w = 0
            if ([int]::TryParse([string]$raw["wait_sec"], [ref]$w) -and $w -gt 0) { $wait = $w }
            else { [void]$Warnings.Add("단계 '$name' 의 wait_sec 값이 올바르지 않아 $wait 초를 씁니다") }
        }
    }
    if (-not $model) { [void]$Warnings.Add("단계 '$name' 에 model 이 없어 무시합니다"); return $null }
    return @{ Model = $model; Fallback = @($fallback | Where-Object { $_ -ne $model } | Select-Object -Unique); WaitSec = $wait }
}

# 설정을 읽어 정리한 결과를 돌려준다.
# 반환: @{ Tiers = @{ <단계> = @{ Model; Fallback; WaitSec } }; TierNames; Escalate; Auto; Aliases; Translate; Allowed; Warnings; Sources }
function Get-AgyModelConfig([string]$ConfigDir = "") {
    if (-not $ConfigDir) { $ConfigDir = Get-AgyModelsConfigDir }
    $warnings = New-Object System.Collections.ArrayList
    $builtin = Get-AgyModelsBuiltinConfig
    $sources = @()
    $main = $null
    $local = $null
    if ($ConfigDir) {
        $mainPath = Join-Path $ConfigDir "models.json"
        $main = Read-AgyModelsJson $mainPath $warnings
        if ($main) { $sources += $mainPath }
        $localPath = Join-Path $ConfigDir "models.local.json"
        $local = Read-AgyModelsJson $localPath $warnings
        if ($local) { $sources += $localPath }
    }

    $tiers = [ordered]@{}
    foreach ($k in $builtin.tiers.Keys) {
        $tiers[$k] = @{ Model = $builtin.tiers[$k].model; Fallback = @($builtin.tiers[$k].fallback); WaitSec = [int]$builtin.tiers[$k].wait_sec }
    }
    $top = @{}
    foreach ($key in @("escalate", "auto", "aliases", "translate", "allowed")) { $top[$key] = $builtin[$key] }

    foreach ($layer in @($main, $local)) {
        if (-not ($layer -is [System.Collections.IDictionary])) { continue }
        if ($layer.Contains("tiers") -and ($layer["tiers"] -is [System.Collections.IDictionary])) {
            foreach ($tn in @($layer["tiers"].Keys)) {
                $name = ([string]$tn).Trim().ToLowerInvariant()
                if (-not $name) { continue }
                $baseT = if ($tiers.Contains($name)) { @{ model = $tiers[$name].Model; fallback = $tiers[$name].Fallback; wait_sec = $tiers[$name].WaitSec } } else { $null }
                $entry = ConvertTo-AgyTierEntry $layer["tiers"][$tn] $baseT $name $warnings
                if ($entry) { $tiers[$name] = $entry }
            }
        }
        foreach ($key in @("escalate", "auto", "aliases")) {
            if ($layer.Contains($key) -and ($layer[$key] -is [System.Collections.IDictionary])) {
                $h = @{}
                foreach ($kk in $layer[$key].Keys) { $h[([string]$kk).ToLowerInvariant()] = ([string]$layer[$key][$kk]).Trim().ToLowerInvariant() }
                $top[$key] = $h
            }
        }
        foreach ($key in @("translate")) {
            if ($layer.Contains($key) -and ([string]$layer[$key]).Trim()) { $top[$key] = ([string]$layer[$key]).Trim().ToLowerInvariant() }
        }
        if ($layer.Contains("allowed")) {
            $al = @(@($layer["allowed"]) | Where-Object { $_ -and ([string]$_).Trim() } | ForEach-Object { ([string]$_).Trim() })
            if ($al.Count -gt 0) { $top["allowed"] = $al }
        }
    }

    # 단계에 쓰인 모델은 허용 목록에 없어도 쓸 수 있게 넣는다(설정끼리 어긋나도 단계는 돌아가게).
    $allowed = New-Object System.Collections.ArrayList
    foreach ($m in @($top["allowed"])) { if (-not ($allowed -icontains $m)) { [void]$allowed.Add([string]$m) } }
    foreach ($t in $tiers.Values) { foreach ($m in @(@($t.Model) + @($t.Fallback))) { if ($m -and -not ($allowed -icontains $m)) { [void]$allowed.Add([string]$m) } } }

    $subAccounts = Resolve-AgySubAccountsConfig $main $local $warnings

    return @{
        Tiers          = $tiers
        TierNames      = @($tiers.Keys)
        Escalate       = $top["escalate"]
        Auto           = $top["auto"]
        Aliases        = $top["aliases"]
        Translate      = [string]$top["translate"]
        Allowed        = @($allowed)
        SubAccounts    = $subAccounts
        Warnings       = @($warnings)
        Sources        = @($sources)
    }
}

# sub_accounts / 구 sub_account 설정을 읽어 정규화된 해시테이블을 돌려준다. 미설정이면 $null.
function Resolve-AgySubAccountsConfig($Main, $Local, [System.Collections.ArrayList]$Warnings) {
    $cfg = @{
        Enabled           = $false
        BridgeDir         = "C:\ProgramData\samjil\sub-bridge"
        SharedDelegateDir = "C:\ProgramData\samjil\delegate-agy"
        AgyBinDir         = ""
        ModelPattern      = "^gemini-4-hydrogen-"
        AckTimeoutSec     = 12
        CooldownSec       = 60
        FallbackToPrimary = $true
        AsyncUsageCheck   = $true
        PrimaryOnlyCmds   = @("browser")
        AllowedSubtrees   = @()
        Slots             = @()
    }
    $slotsMap = [ordered]@{}
    $sawSub = $false

    foreach ($layerInfo in @(@{ Label = "models.json"; Data = $Main }, @{ Label = "models.local.json"; Data = $Local })) {
        $layer = $layerInfo.Data
        if (-not ($layer -is [System.Collections.IDictionary])) { continue }
        $isPlural = $layer.Contains("sub_accounts")
        $isSingle = (-not $isPlural) -and $layer.Contains("sub_account")
        if (-not $isPlural -and -not $isSingle) { continue }
        $raw = if ($isPlural) { $layer["sub_accounts"] } else { $layer["sub_account"] }
        if ($null -eq $raw) { continue }
        if (-not ($raw -is [System.Collections.IDictionary])) {
            if ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 sub_accounts 형식이 올바르지 않아 무시합니다") }
            continue
        }
        $sawSub = $true

        if ($raw.Contains("enabled") -and $null -ne $raw["enabled"]) { $cfg.Enabled = [bool]$raw["enabled"] }
        if ($raw.Contains("bridge_dir") -and -not [string]::IsNullOrWhiteSpace([string]$raw["bridge_dir"])) {
            $cfg.BridgeDir = ([string]$raw["bridge_dir"]).Trim()
        }
        if ($raw.Contains("shared_delegate_dir") -and -not [string]::IsNullOrWhiteSpace([string]$raw["shared_delegate_dir"])) {
            $cfg.SharedDelegateDir = ([string]$raw["shared_delegate_dir"]).Trim()
        }
        if ($raw.Contains("agy_bin_dir") -and -not [string]::IsNullOrWhiteSpace([string]$raw["agy_bin_dir"])) {
            $cfg.AgyBinDir = ([string]$raw["agy_bin_dir"]).Trim()
        }
        if ($raw.Contains("model_pattern") -and -not [string]::IsNullOrWhiteSpace([string]$raw["model_pattern"])) {
            $pat = ([string]$raw["model_pattern"]).Trim()
            try {
                [void][regex]::new($pat)
                $cfg.ModelPattern = $pat
            } catch {
                if ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 sub_accounts.model_pattern 정규식이 잘못되어 기본값을 씁니다: $pat") }
            }
        }
        if ($raw.Contains("ack_timeout_sec") -and $null -ne $raw["ack_timeout_sec"]) {
            $n = 0
            if ([int]::TryParse([string]$raw["ack_timeout_sec"], [ref]$n) -and $n -gt 0) { $cfg.AckTimeoutSec = $n }
            elseif ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 ack_timeout_sec 값이 올바르지 않아 $($cfg.AckTimeoutSec)초를 씁니다") }
        }
        if ($raw.Contains("cooldown_sec") -and $null -ne $raw["cooldown_sec"]) {
            $n = 0
            if ([int]::TryParse([string]$raw["cooldown_sec"], [ref]$n) -and $n -ge 0) { $cfg.CooldownSec = $n }
            elseif ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 cooldown_sec 값이 올바르지 않아 $($cfg.CooldownSec)초를 씁니다") }
        }
        if ($raw.Contains("fallback_to_primary") -and $null -ne $raw["fallback_to_primary"]) {
            $cfg.FallbackToPrimary = [bool]$raw["fallback_to_primary"]
        }
        if ($raw.Contains("async_usage_check") -and $null -ne $raw["async_usage_check"]) {
            $cfg.AsyncUsageCheck = [bool]$raw["async_usage_check"]
        }
        if ($raw.Contains("primary_only_cmds")) {
            $cmds = New-Object System.Collections.ArrayList
            foreach ($c in @($raw["primary_only_cmds"])) {
                $cs = ([string]$c).Trim().TrimStart('/')
                if ($cs -and ($cmds -notcontains $cs)) { [void]$cmds.Add($cs) }
            }
            $cfg.PrimaryOnlyCmds = @($cmds)
        }
        if ($raw.Contains("allowed_subtrees")) {
            $subtrees = New-Object System.Collections.ArrayList
            foreach ($st in @($raw["allowed_subtrees"])) {
                if ($null -eq $st) { continue }
                $sts = ([string]$st).Trim()
                if ($sts -and ($subtrees -notcontains $sts)) { [void]$subtrees.Add($sts) }
            }
            $cfg.AllowedSubtrees = @($subtrees)
        }

        if ($isPlural) {
            if ($raw.Contains("slots")) {
                $slotsMap.Clear()
                foreach ($s in @($raw["slots"])) {
                    if ($null -eq $s) { continue }
                    if (-not ($s -is [System.Collections.IDictionary])) {
                        if ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 sub_accounts.slots 항목이 객체가 아니어서 건너뜁니다") }
                        continue
                    }
                    $sid = if ($s.Contains("id")) { ([string]$s["id"]).Trim() } else { "" }
                    if (-not $sid) { $sid = "sub$($slotsMap.Count + 1)" }
                    if ($sid -notmatch '^[A-Za-z0-9_-]{1,32}$') {
                        if ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 sub_accounts 슬롯 ID '$sid' 형식이 올바르지 않아 건너뜁니다") }
                        continue
                    }
                    $winUser = if ($s.Contains("windows_user")) { ([string]$s["windows_user"]).Trim() } else { "" }
                    if (-not $winUser) {
                        if ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 sub_accounts 슬롯 '$sid' 에 windows_user 가 없어 건너뜁니다") }
                        continue
                    }
                    $lbl = if ($s.Contains("label") -and -not [string]::IsNullOrWhiteSpace([string]$s["label"])) {
                        ([string]$s["label"]).Trim()
                    } elseif ($sid -match '^sub(\d+)$') {
                        "부계정 $($Matches[1])"
                    } else {
                        $sid
                    }
                    $mp = 5
                    if ($s.Contains("max_parallel") -and $null -ne $s["max_parallel"]) {
                        $mpParsed = 0
                        if ([int]::TryParse([string]$s["max_parallel"], [ref]$mpParsed) -and $mpParsed -gt 0) { $mp = $mpParsed }
                        elseif ($null -ne $Warnings) { [void]$Warnings.Add("$($layerInfo.Label) 의 슬롯 '$sid' max_parallel 값이 잘못되어 5를 씁니다") }
                    }
                    $slotsMap[$sid] = @{
                        Id          = $sid
                        WindowsUser = $winUser
                        Label       = $lbl
                        MaxParallel = $mp
                    }
                }
            }
        } else {
            # 구 단일 sub_account 키를 slots 1개 배열로 변환
            $slotsMap.Clear()
            $sid = if ($raw.Contains("id") -and -not [string]::IsNullOrWhiteSpace([string]$raw["id"])) { ([string]$raw["id"]).Trim() } else { "sub1" }
            $winUser = if ($raw.Contains("windows_user")) { ([string]$raw["windows_user"]).Trim() } else { "" }
            if ($winUser) {
                $lbl = if ($raw.Contains("label") -and -not [string]::IsNullOrWhiteSpace([string]$raw["label"])) {
                    ([string]$raw["label"]).Trim()
                } elseif ($sid -match '^sub(\d+)$') {
                    "부계정 $($Matches[1])"
                } else {
                    $sid
                }
                $mp = 5
                if ($raw.Contains("max_parallel") -and $null -ne $raw["max_parallel"]) {
                    $mpParsed = 0
                    if ([int]::TryParse([string]$raw["max_parallel"], [ref]$mpParsed) -and $mpParsed -gt 0) { $mp = $mpParsed }
                }
                $slotsMap[$sid] = @{
                    Id          = $sid
                    WindowsUser = $winUser
                    Label       = $lbl
                    MaxParallel = $mp
                }
            } elseif ($null -ne $Warnings) {
                [void]$Warnings.Add("$($layerInfo.Label) 의 sub_account 에 windows_user 가 없어 무시합니다")
            }
        }
    }

    if (-not $sawSub) { return $null }
    $cfg.Slots = @($slotsMap.Values)
    if ($cfg.Enabled -and @($cfg.Slots).Count -eq 0) {
        $cfg.Enabled = $false
        if ($null -ne $Warnings) { [void]$Warnings.Add("sub_accounts.enabled=true 이지만 유효한 slots 가 없어 비활성화합니다") }
    }
    return $cfg
}

# 단계의 모델 순서(주 모델 + 폴백). $Available(agy models 결과)이 있으면 없는 모델을 뺀다.
# 다 빠지면 원래 순서를 그대로 돌려준다(목록이 틀렸을 수도 있으니 막지 않는다).
function Get-AgyTierChain($Config, [string]$Tier, [string[]]$Available = @()) {
    if (-not $Config -or -not $Config.Tiers.Contains($Tier)) { return @() }
    $t = $Config.Tiers[$Tier]
    $chain = @(@($t.Model) + @($t.Fallback) | Where-Object { $_ } | Select-Object -Unique)
    if (@($Available).Count -gt 0) {
        $kept = @($chain | Where-Object { $Available -icontains $_ })
        if ($kept.Count -gt 0) { return $kept }
    }
    return $chain
}

# @model 값(단계 이름 · 별칭 · 모델 이름)을 해석한다.
# 반환: $null(빈 값) 또는 @{ Kind = 'tier'|'model'|'unknown'; Tier; Model; Chain; WaitSec; Error }
#   tier  : 단계 이름이나 별칭(low · medium · high). Chain 은 폴백을 포함한 순서, Model 은 첫 모델.
#   model : 허용 목록의 모델 이름. Chain 은 그 모델 하나(폴백 없음). Tier 는 그 모델을 주 모델로 쓰는 단계(없으면 "").
function Resolve-AgyModelSpec([string]$Value, $Config, [string[]]$Available = @()) {
    $v = ([string]$Value).Trim()
    if (-not $v) { return $null }
    if (-not $Config) { $Config = Get-AgyModelConfig }
    $lower = $v.ToLowerInvariant()
    $tier = ""
    if ($Config.Tiers.Contains($lower)) { $tier = $lower }
    elseif ($Config.Aliases -and $Config.Aliases.Contains($lower) -and $Config.Tiers.Contains([string]$Config.Aliases[$lower])) { $tier = [string]$Config.Aliases[$lower] }
    if ($tier) {
        $chain = @(Get-AgyTierChain $Config $tier $Available)
        return @{ Kind = "tier"; Tier = $tier; Model = $chain[0]; Chain = $chain; WaitSec = [int]$Config.Tiers[$tier].WaitSec; Error = $null }
    }
    $canonical = @($Config.Allowed | Where-Object { $_ -ieq $v }) | Select-Object -First 1
    if ($canonical) {
        $ownTier = ""
        foreach ($tn in $Config.TierNames) { if ($Config.Tiers[$tn].Model -ieq $canonical) { $ownTier = $tn; break } }
        $wait = if ($ownTier) { [int]$Config.Tiers[$ownTier].WaitSec } else { 0 }
        return @{ Kind = "model"; Tier = $ownTier; Model = [string]$canonical; Chain = @([string]$canonical); WaitSec = $wait; Error = $null }
    }
    return @{ Kind = "unknown"; Tier = ""; Model = $null; Chain = @(); WaitSec = 0; Error = "지정한 @model 을 쓸 수 없습니다: $v (단계: $($Config.TierNames -join ', ') / 모델: $($Config.Allowed -join ', '))" }
}

# 실패한 단계를 한 단계 올려 다시 보낼 곳(build -> build-hard -> deep). 없으면 "".
function Get-AgyEscalationTier($Config, [string]$Tier) {
    if (-not $Config -or -not $Tier) { return "" }
    $t = $Tier.ToLowerInvariant()
    if ($Config.Escalate -and $Config.Escalate.Contains($t)) {
        $next = [string]$Config.Escalate[$t]
        if ($Config.Tiers.Contains($next)) { return $next }
    }
    return ""
}

# `agy models` 출력에서 모델 ID 를 뽑는다(줄 첫 낱말이 소문자 · 숫자 · 점 · 하이픈으로 된 것).
function ConvertFrom-AgyModelsList([string]$Text) {
    $ids = @()
    foreach ($line in ([string]$Text -split "`r?`n")) {
        # -cmatch: 대소문자를 가린다("Fetching available models..." 같은 머리 줄을 모델로 읽지 않게). ID 에는 하이픈이 하나 이상 있다.
        if ($line -cmatch '^\s*([a-z0-9][a-z0-9.]*(?:-[a-z0-9.]+)+)(\s|$)') { $ids += $Matches[1] }
    }
    return @($ids | Select-Object -Unique)
}

# `agy models` 를 불러 쓸 수 있는 모델 ID 목록을 돌려준다. 실패하거나 시간 안에 끝나지 않으면 $null.
# 창이 없는 백그라운드 워처에서도 콘솔 창이 깜빡이지 않도록 Win32 무창 분리 실행(agy-spawn.ps1)으로 실행한다.
function Get-AgyAvailableModels([string]$AgyExe = "agy", [int]$TimeoutSec = 20) {
    if (-not (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue)) {
        $spawnLib = Join-Path $PSScriptRoot "agy-spawn.ps1"
        if (-not (Test-Path $spawnLib)) { $spawnLib = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-spawn.ps1" }
        if (Test-Path $spawnLib) { . $spawnLib }
    }
    if (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue) {
        $res = Invoke-AgyHiddenWithOutput -FilePath $AgyExe -ArgumentList @("models") -TimeoutSeconds $TimeoutSec
        # Pid -1 = 헬퍼 자체가 실패(실행 파일 없음 · Add-Type 실패 등): 아래 기본 방식으로 한 번 더 해 본다
        if ($res -and $res.Pid -ge 0) {
            # 시간 초과면 트리째 끝낸 뒤 바로 돌아온다. 그때 받은 일부 출력은 믿지 않는다(예전과 같이 $null).
            if ($res.TimedOut) { return $null }
            if ($res.ExitCode -eq 0 -and $res.StdOut) {
                $ids = @(ConvertFrom-AgyModelsList $res.StdOut)
                if ($ids.Count -gt 0) { return $ids }
            }
            return $null
        }
    }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $AgyExe
        $psi.Arguments              = "models"
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
        $ids = @(ConvertFrom-AgyModelsList ([string]$outTask.Result))
        if ($ids.Count -eq 0) { return $null }
        return $ids
    } catch {
        return $null
    } finally {
        if ($p) { try { $p.Dispose() } catch {} }
    }
}

# FileSystemProvider(Remove-Item) 이 부모 (NP)(X) 폴더에서 Access is denied 로 중단되는 경우를 피해
# .NET File.Delete 로 단일 파일을 안전하게 지운다 (읽기 전용 해제 · 예외 비전파).
function Remove-AgyFileSafe([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if ([System.IO.File]::Exists($Path)) {
            try {
                $attrs = [System.IO.File]::GetAttributes($Path)
                if ($attrs -band [System.IO.FileAttributes]::ReadOnly) {
                    [System.IO.File]::SetAttributes($Path, ($attrs -band (-bnot [System.IO.FileAttributes]::ReadOnly)))
                }
            } catch {}
            [System.IO.File]::Delete($Path)
        }
        return (-not [System.IO.File]::Exists($Path))
    } catch {
        return $false
    }
}

# 워처가 켜질 때 쓸 수 있는 모델 목록을 확인해 $File 에 적는다. 목록(배열)을 돌려주고, 확인하지 못하면 $null.
# - 늘 `agy models` 를 새로 부른다. agy 계정을 바꾸면 쓸 수 있는 모델이 달라지므로 예전 결과(다른 계정 · 지난 실행)를 다시 쓰지 않는다.
# - 먼저 예전 파일을 지운다. 확인에 실패하거나 시간 안에 끝나지 않으면 파일이 없는 채로 남아 작업자는 모델을 거르지 않는다.
# - 파일에는 확인 시각과 모델 ID 만 적는다(계정 · 이메일은 적지 않는다).
# - 임시 파일에 다 쓴 뒤 이름을 바꿔, 작업자가 쓰다 만 파일을 읽지 않게 한다.
# $Lister: 시험용. 지정하면 `agy models` 대신 이 스크립트 블록의 결과를 목록으로 쓴다.
function Update-AgyAvailableModelsFile([string]$File, [string]$AgyExe = "agy", [int]$TimeoutSec = 20, [scriptblock]$Lister = $null) {
    [void](Remove-AgyFileSafe $File)
    $avail = $null
    try {
        if ($Lister) { $avail = & $Lister } else { $avail = Get-AgyAvailableModels $AgyExe $TimeoutSec }
    } catch { $avail = $null }
    $ids = @(@($avail) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    if ($ids.Count -eq 0) { return $null }
    $tmp = "$File.$PID.tmp"
    try {
        $json = [ordered]@{ checked_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); models = $ids } | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        if ([System.IO.File]::Exists($File)) {
            [System.IO.File]::Replace($tmp, $File, [NullString]::Value, $true)
        } else {
            [System.IO.File]::Move($tmp, $File)
        }
    } catch {
        [void](Remove-AgyFileSafe $tmp)
        [void](Remove-AgyFileSafe $File)
        return $null
    }
    return $ids
}

# 이번 워처 기동 때 확인한 모델 목록을 읽는다. 파일이 없거나 못 읽으면 빈 배열(= 확인하지 않은 것으로 보고 거르지 않는다).
function Read-AgyAvailableModelsFile([string]$File) {
    try {
        if (-not (Test-Path -LiteralPath $File)) { return @() }
        $j = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
        return @(@($j.models) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    } catch { return @() }
}

# 설정의 모델 중 $Available 에 없는 것들. 반환: @{ <단계> = @(<없는 모델>...) } (없으면 빈 표)
function Get-AgyMissingTierModels($Config, [string[]]$Available) {
    $missing = [ordered]@{}
    if (@($Available).Count -eq 0) { return $missing }
    foreach ($tn in $Config.TierNames) {
        $t = $Config.Tiers[$tn]
        $gone = @(@(@($t.Model) + @($t.Fallback)) | Where-Object { $_ -and -not ($Available -icontains $_) })
        if ($gone.Count -gt 0) { $missing[$tn] = $gone }
    }
    return $missing
}

# 화면 · 로그용 짧은 이름: gemini-4-hydrogen-xhigh -> hydrogen-extra, gemini-4-neon-xhigh -> neon-extra,
# gemini-4-carbon-high -> carbon-high, gemini-4-neon-medium -> neon-medium,
# gemini-pro-orchestrator-neon -> orchestrator-neon, gemini-pro-orchestrator -> orchestrator-carbon,
# gemini-pro-orchestrator-argon -> orchestrator-argon (예전 g1-pro -> orchestrator, 3.8-flash-medium -> flash-medium). 모르는 이름은 그대로.
function Get-AgyModelShortName([string]$Model) {
    $m = ([string]$Model).Trim()
    if ($m -match '^(?i)gemini-4-(hydrogen|neon|carbon|argon)(?:-tiered)?-xhigh$') { return ("{0}-extra" -f $Matches[1].ToLowerInvariant()) }
    if ($m -match '^(?i)gemini-4-(hydrogen|neon|carbon|argon)(?:-tiered)?-(\w+)$') { return ("{0}-{1}" -f $Matches[1].ToLowerInvariant(), $Matches[2].ToLowerInvariant()) }
    if ($m -match '^(?i)gemini-pro-orchestrator-neon$') { return "orchestrator-neon" }
    if ($m -match '^(?i)gemini-pro-orchestrator$') { return "orchestrator-carbon" }
    if ($m -match '^(?i)gemini-pro-orchestrator-argon$') { return "orchestrator-argon" }
    if ($m -match '^(?i)gemini-pro-orchestrator') { return "orchestrator" }
    if ($m -match '^(?i)gemini-\d+(?:\.\d+)?-(flash|pro|lite)-(\w+)$') { return ("{0}-{1}" -f $Matches[1].ToLowerInvariant(), $Matches[2].ToLowerInvariant()) }
    return $m
}

function Test-AgyCallerLevelMatchEnabled {
    $v = ([string]$env:AGY_MATCH_CALLER_LEVEL).Trim()
    return -not ($v -match '^(?i:off|0|false|no)$')
}

function Get-AgyMetaFieldValue($Obj, [string]$Name) {
    if ($null -eq $Obj) { return "" }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return [string]$Obj[$Name] }
        return ""
    }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
    return ""
}

# 호출 세션(Antigravity/Claude)의 추론 수준(high/xhigh 등)에 맞춰 위임 단계/체인을 동급 이상으로 맞춘다.
# 반환: $null(변경 없음) 또는 @{ Kind = 'tier'; Tier; Model; Chain; WaitSec; CallerDesc }
function Resolve-AgyCallerSameLevelSpec($Config, [string[]]$Available = @(), $CallerMeta = $null, [string]$RequestedValue = "", [string]$CurrentTier = "", [string]$CurrentKind = "") {
    if (-not (Test-AgyCallerLevelMatchEnabled)) { return $null }
    if ($null -eq $CallerMeta -or -not $Config) { return $null }
    if ($CurrentKind -eq "model") { return $null }

    $srcClient  = (Get-AgyMetaFieldValue $CallerMeta 'src_client').Trim()
    $agentModel = (Get-AgyMetaFieldValue $CallerMeta 'agent_model').Trim()
    $srcModel   = (Get-AgyMetaFieldValue $CallerMeta 'src_model').Trim()
    $claudeMod  = (Get-AgyMetaFieldValue $CallerMeta 'model').Trim()
    $callerModel  = if ($agentModel) { $agentModel } elseif ($srcModel) { $srcModel } else { $claudeMod }
    $callerEffort = if ($agentModel) { (Get-AgyMetaFieldValue $CallerMeta 'agent_effort').Trim() } elseif ($srcModel) { (Get-AgyMetaFieldValue $CallerMeta 'src_effort').Trim() } else { (Get-AgyMetaFieldValue $CallerMeta 'effort').Trim() }

    $normModel  = ($callerModel.ToLowerInvariant() -replace '-tiered-', '-')
    $normEffort = $callerEffort.ToLowerInvariant()
    if (-not $normModel -and -not $normEffort) { return $null }

    $reqTrim = ([string]$RequestedValue).Trim()
    $targetTier = ""
    $customChain = @()

    if ($srcClient -ieq "antigravity" -and $normModel) {
        if (-not $reqTrim) {
            if ($CurrentTier -eq "quick") { return $null }
            switch ($normModel) {
                "gemini-4-hydrogen-low"        { $targetTier = "quick" }
                "gemini-4-hydrogen-medium"     { $targetTier = "build" }
                "gemini-4-hydrogen-high"       { $targetTier = "build-high" }
                "gemini-4-hydrogen-xhigh"      { $targetTier = "build-high"; $customChain = @("gemini-4-hydrogen-xhigh", "gemini-4-hydrogen-high", "gemini-4-hydrogen-medium") }
                "gemini-4-neon-low"            { $targetTier = "build-hard"; $customChain = @("gemini-4-neon-low", "gemini-4-neon-medium", "gemini-4-hydrogen-high") }
                "gemini-4-neon-medium"         { $targetTier = "build-hard" }
                "gemini-4-neon-high"           { $targetTier = "think" }
                "gemini-4-neon-xhigh"          { $targetTier = "deep" }
                "gemini-pro-orchestrator-neon" { $targetTier = "feature" }
                "gemini-pro-orchestrator"      { $targetTier = "feature-carbon" }
                "gemini-4-carbon-low"          { $targetTier = "think-carbon"; $customChain = @($normModel, "gemini-4-carbon-high", "gemini-4-neon-high") }
                "gemini-4-carbon-medium"       { $targetTier = "think-carbon"; $customChain = @($normModel, "gemini-4-carbon-high", "gemini-4-neon-high") }
                "gemini-4-carbon-high"         { $targetTier = "think-carbon" }
            }
        } elseif ($CurrentTier -eq "build") {
            if ($normModel -in @("gemini-4-hydrogen-xhigh", "gemini-4-neon-xhigh")) {
                $targetTier = "build-high"
                $customChain = @("gemini-4-hydrogen-xhigh", "gemini-4-hydrogen-high", "gemini-4-hydrogen-medium")
            } elseif ($normModel -match '-(high|xhigh)$' -or $normModel -like 'gemini-pro-orchestrator*') {
                $targetTier = "build-high"
            }
        } elseif ($CurrentTier -eq "build-hard") {
            if ($normModel -eq "gemini-4-neon-xhigh") {
                $targetTier = "deep"
            } elseif ($normModel -in @("gemini-4-neon-high", "gemini-4-carbon-high") -or $normModel -like 'gemini-pro-orchestrator*') {
                $targetTier = "think"
            }
        }
    }
    # Claude 세션은 effort(대부분 기본값 high)로 단계를 올리지 않는다: Claude 가 브리프의 @model 로 단계를 직접 고른다(2026-11-27 결정).

    if (-not $targetTier -or -not $Config.Tiers.Contains($targetTier)) { return $null }
    if ($targetTier -eq $CurrentTier -and $customChain.Count -eq 0) { return $null }

    $chain = if ($customChain.Count -gt 0) {
        if (@($Available).Count -gt 0) {
            $kept = @($customChain | Where-Object { $Available -icontains $_ })
            if ($kept.Count -gt 0) { $kept } else { $customChain }
        } else { $customChain }
    } else {
        @(Get-AgyTierChain $Config $targetTier $Available)
    }
    if ($chain.Count -eq 0) { return $null }

    $callerDesc = if ($normModel -and $normEffort) { "$normModel ($normEffort)" } elseif ($normModel) { $normModel } else { $normEffort }
    return @{
        Kind       = "tier"
        Tier       = $targetTier
        Model      = [string]$chain[0]
        Chain      = @($chain)
        WaitSec    = [int]$Config.Tiers[$targetTier].WaitSec
        CallerDesc = $callerDesc
    }
}

# 모델 ID 를 한도 묶음 이름으로 바꾼다. Gemini 계열은 모두 같은 한도("gemini")를 쓴다.
function Get-AgyQuotaGroup([string]$Model) {
    $m = ([string]$Model).Trim().ToLowerInvariant()
    if (-not $m) { return "" }
    if ($m.StartsWith("gemini-") -or $m.StartsWith("gemini-pro-orchestrator")) { return "gemini" }
    return $m
}

# 오류 문자열 안의 "Resets in 1h35m43s" / "Resets in 45m" / "Resets in 30s" 를 찾아 $NowUtc + 그 시간(UTC DateTime)을 돌려준다. 없으면 $null.
function ConvertFrom-AgyResetsInText([string]$Text, [datetime]$NowUtc = [datetime]::MinValue) {
    if (-not $Text) { return $null }
    $baseUtc = if ($NowUtc -eq [datetime]::MinValue) {
        [datetime]::UtcNow
    } elseif ($NowUtc.Kind -eq [System.DateTimeKind]::Local) {
        $NowUtc.ToUniversalTime()
    } else {
        [datetime]::SpecifyKind($NowUtc, [System.DateTimeKind]::Utc)
    }
    if ($Text -match '(?i)Resets\s+in\s+(?=\d+\s*[hms])(?:(?<h>\d+)\s*h)?\s*(?:(?<m>\d+)\s*m)?\s*(?:(?<s>\d+)\s*s)?') {
        $h = if ($Matches.ContainsKey('h') -and $Matches['h']) { [double]$Matches['h'] } else { 0 }
        $m = if ($Matches.ContainsKey('m') -and $Matches['m']) { [double]$Matches['m'] } else { 0 }
        $s = if ($Matches.ContainsKey('s') -and $Matches['s']) { [double]$Matches['s'] } else { 0 }
        return $baseUtc.AddHours($h).AddMinutes($m).AddSeconds($s)
    }
    return $null
}

# 한도 소진 오류인지 판정한다(503 "No capacity" · "high traffic" 등 서버 과부하는 $false).
function Test-AgyQuotaExhaustedError([string]$Text) {
    if (-not $Text) { return $false }
    return [bool]($Text -match '(?i)Individual quota reached|RESOURCE_EXHAUSTED|quota (?:exceeded|reached|exhausted)')
}
