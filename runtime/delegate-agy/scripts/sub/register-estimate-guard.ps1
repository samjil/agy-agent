# register-estimate-guard.ps1
# Claude Code 의 ~/.claude/settings.json 에 "질문마다 예상 기록 강제" 훅 셋(estimate-guard)을 넣거나 뺍니다.
#   UserPromptSubmit : 새 질문 표시 + 기록 안내(명령 훅)
#   PreToolUse       : 기록 전에 일을 시작하는 도구를 막음(뷰어의 HTTP 훅 /api/estimate-guard: 빨라서 도구 호출마다 걸어도 부담이 없다. 뷰어가 꺼져 있으면 막지 않고 지나간다)
#   Stop             : 기록 없이 끝내려 하면 막음(명령 훅. 뷰어가 꺼져 있어도 여기서 걸린다)
#   .\register-estimate-guard.ps1            # 넣기(이미 있으면 경로 · 주소만 바꿈)
#   .\register-estimate-guard.ps1 -Check     # 지금 상태만 보기
#   .\register-estimate-guard.ps1 -Remove    # 빼기(다른 훅과 설정은 그대로)
# install.ps1 / uninstall.ps1 이 부른다. 바꾸기 전에 settings.json 을 .bak-<시각> 으로 백업하고,
# 설정 파일이 JSON 으로 읽히지 않으면 아무것도 건드리지 않고 오류로 끝낸다.
# 결과(stdout 한 줄): ADDED | UPDATED | UNCHANGED | REMOVED | NOTFOUND | PRESENT | ABSENT
param(
    [string]$SettingsPath = "",
    [string]$GuardScript = "",
    [int]$Port = 8787,                # 뷰어 포트(PreToolUse HTTP 훅 주소)
    [switch]$Remove,
    [switch]$Check,
    [switch]$UpdateOnly
)
$ErrorActionPreference = "Stop"
$home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
if (-not $SettingsPath) { $SettingsPath = Join-Path $home_ ".claude/settings.json" }
if (-not $GuardScript) { $GuardScript = Join-Path $home_ ".samjil/delegate-agy/scripts/sub/estimate-guard.ps1" }
$cmdMarker = "estimate-guard.ps1"
$urlMarker = "/api/estimate-guard"
# 명령 훅은 셸이 무엇이든(cmd · PowerShell · Git Bash) 같은 뜻이 되도록 슬래시 경로를 큰따옴표로 감싼다.
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + ($GuardScript -replace '\\', '/') + '"'
$url = "http://127.0.0.1:$Port/api/estimate-guard"

# 이벤트별 우리 훅 정의(타입 · 값)
$specs = @(
    @{ Event = "UserPromptSubmit"; Kind = "command" },
    @{ Event = "PreToolUse"; Kind = "http" },
    @{ Event = "Stop"; Kind = "command" }
)

$utf8 = New-Object System.Text.UTF8Encoding($false)
$settings = $null
$existed = Test-Path -LiteralPath $SettingsPath -PathType Leaf
if ($existed) {
    $text = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8)
    if ($text.Trim()) {
        try { $settings = $text | ConvertFrom-Json } catch { Write-Error "설정 파일을 JSON 으로 읽을 수 없어 건드리지 않았습니다: $SettingsPath ($($_.Exception.Message))"; exit 1 }
    }
}
if (-not $settings) { $settings = [pscustomobject]@{} }

function Test-OurHook($h) {
    if (-not $h) { return $false }
    if ($h.PSObject.Properties["command"] -and ([string]$h.command).Contains($cmdMarker)) { return $true }
    if ($h.PSObject.Properties["url"] -and ([string]$h.url).Contains($urlMarker)) { return $true }
    return $false
}
function Get-EstimateGuardEntries($s, [string]$EventName) {
    $found = @()
    if ($s.PSObject.Properties["hooks"] -and $s.hooks.PSObject.Properties[$EventName]) {
        foreach ($g in @($s.hooks.$EventName)) {
            if (-not $g) { continue }
            foreach ($h in @($g.hooks)) { if (Test-OurHook $h) { $found += $h } }
        }
    }
    return @($found)
}
function New-OurHook([string]$Kind) {
    if ($Kind -eq "http") {
        return [pscustomobject]@{ type = "http"; url = $url; timeout = 5; headers = [pscustomobject]@{ "X-Samjil-Viewer" = "1" } }
    }
    return [pscustomobject]@{ type = "command"; command = $command; timeout = 10 }
}

if ($Check) {
    $all = $true
    foreach ($sp in $specs) { if (@(Get-EstimateGuardEntries $settings $sp.Event).Count -eq 0) { $all = $false } }
    if ($all) { "PRESENT" } else { "ABSENT" }
    exit 0
}

if ($UpdateOnly) {
    if (-not $existed) { "ABSENT"; exit 0 }
    $hasAny = $false
    foreach ($sp in $specs) {
        $ours = @(Get-EstimateGuardEntries $settings $sp.Event)
        if ($ours.Count -gt 0) { $hasAny = $true; break }
    }
    if (-not $hasAny) { "ABSENT"; exit 0 }
}

$changed = $false
$result = ""
if ($Remove) {
    foreach ($sp in $specs) {
        $ev = $sp.Event
        if (@(Get-EstimateGuardEntries $settings $ev).Count -eq 0) { continue }
        $newGroups = @()
        foreach ($g in @($settings.hooks.$ev)) {
            if (-not $g) { continue }
            $keep = @(@($g.hooks) | Where-Object { $_ -and -not (Test-OurHook $_) })
            if ($keep.Count -gt 0) { $g.hooks = $keep; $newGroups += $g }
        }
        if ($newGroups.Count -gt 0) { $settings.hooks.$ev = $newGroups }
        else { $settings.hooks.PSObject.Properties.Remove($ev) }
        $changed = $true
    }
    if ($changed -and $settings.PSObject.Properties["hooks"] -and @($settings.hooks.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove("hooks") }
    if (-not $changed) { "NOTFOUND"; exit 0 }
    $result = "REMOVED"
} else {
    $added = $false
    foreach ($sp in $specs) {
        $ev = $sp.Event
        $ours = @(Get-EstimateGuardEntries $settings $ev)
        if ($ours.Count -gt 0) {
            foreach ($h in $ours) {
                if ($sp.Kind -eq "http") {
                    if ([string]$h.url -ne $url) { $h.url = $url; $changed = $true }
                } else {
                    if ([string]$h.command -ne $command) { $h.command = $command; $changed = $true }
                }
            }
        } else {
            if (-not $settings.PSObject.Properties["hooks"]) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
            if (-not $settings.hooks.PSObject.Properties[$ev]) { $settings.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @() }
            $entry = [pscustomobject]@{ hooks = @((New-OurHook $sp.Kind)) }
            $settings.hooks.$ev = @(@($settings.hooks.$ev) + @($entry))
            $added = $true
        }
    }
    if ($added) { $result = "ADDED" } elseif ($changed) { $result = "UPDATED" } else { "UNCHANGED"; exit 0 }
}

$dir = Split-Path -Parent $SettingsPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
if ($existed) { Copy-Item -LiteralPath $SettingsPath -Destination ($SettingsPath + ".bak-" + (Get-Date -Format "yyyyMMddHHmmss")) -Force }
$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($SettingsPath, $json, $utf8)
$result
