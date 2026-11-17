# remove-estimate-guard.ps1
# 옛 설치본이 ~/.claude/settings.json 에 넣어 둔 "질문마다 예상 기록 강제" 훅(estimate-guard)을 찾아 지운다.
# 예상 기록 장치는 없어졌으므로 새로 넣는 코드는 없고, 업그레이드(install.ps1)와 제거(uninstall.ps1) 때 남은 항목만 치운다.
#   .\remove-estimate-guard.ps1            # 지우기(다른 훅과 설정은 그대로)
#   .\remove-estimate-guard.ps1 -Check     # 남은 항목이 있는지만 보기
# 바꾸기 전에 settings.json 을 .bak-<시각> 으로 백업하고, 설정 파일이 JSON 으로 읽히지 않으면 아무것도 건드리지 않고 오류로 끝낸다.
# 결과(stdout 한 줄): REMOVED | NOTFOUND | PRESENT | ABSENT
param(
    [string]$SettingsPath = "",
    [switch]$Check
)
$ErrorActionPreference = "Stop"
$home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
if (-not $SettingsPath) { $SettingsPath = Join-Path $home_ ".claude/settings.json" }
$cmdMarker = "estimate-guard.ps1"
$urlMarker = "/api/estimate-guard"
$events = @("UserPromptSubmit", "PreToolUse", "Stop")

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
function Get-GuardEntries($s, [string]$EventName) {
    $found = @()
    if ($s.PSObject.Properties["hooks"] -and $s.hooks.PSObject.Properties[$EventName]) {
        foreach ($g in @($s.hooks.$EventName)) {
            if (-not $g) { continue }
            foreach ($h in @($g.hooks)) { if (Test-OurHook $h) { $found += $h } }
        }
    }
    return @($found)
}

$present = $false
foreach ($ev in $events) { if (@(Get-GuardEntries $settings $ev).Count -gt 0) { $present = $true } }
if ($Check) { if ($present) { "PRESENT" } else { "ABSENT" }; exit 0 }
if (-not $present) { "NOTFOUND"; exit 0 }

foreach ($ev in $events) {
    if (@(Get-GuardEntries $settings $ev).Count -eq 0) { continue }
    $newGroups = @()
    foreach ($g in @($settings.hooks.$ev)) {
        if (-not $g) { continue }
        $keep = @(@($g.hooks) | Where-Object { $_ -and -not (Test-OurHook $_) })
        if ($keep.Count -gt 0) { $g.hooks = $keep; $newGroups += $g }
    }
    if ($newGroups.Count -gt 0) { $settings.hooks.$ev = $newGroups }
    else { $settings.hooks.PSObject.Properties.Remove($ev) }
}
if ($settings.PSObject.Properties["hooks"] -and @($settings.hooks.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove("hooks") }

Copy-Item -LiteralPath $SettingsPath -Destination ($SettingsPath + ".bak-" + (Get-Date -Format "yyyyMMddHHmmss")) -Force
$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($SettingsPath, $json, $utf8)
"REMOVED"
