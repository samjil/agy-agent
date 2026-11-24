# register-statusline.ps1
# Claude Code 의 ~/.claude/settings.json 에 statusLine(claude-statusline.js)을 넣거나 뺍니다.
#   .\register-statusline.ps1            # 넣기 (다른 statusLine 이 없을 때나 우리 이전 설정일 때만)
#   .\register-statusline.ps1 -Check     # PRESENT | OTHER | ABSENT
#   .\register-statusline.ps1 -Remove    # 빼기 (우리 것일 때만; 다른 statusLine 이면 건드리지 않음)
# 바꾸기 전에 settings.json 을 .bak-<시각> 으로 백업하고, JSON 으로 읽히지 않으면 건드리지 않고 오류로 끝냅니다.
# 결과(stdout 한 줄): ADDED | UPDATED | UNCHANGED | SKIPPED | REMOVED | NOTFOUND | PRESENT | OTHER | ABSENT
param(
    [string]$SettingsPath = "",
    [string]$ScriptPath = "",
    [switch]$Remove,
    [switch]$Check
)
$ErrorActionPreference = "Stop"
$home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
if (-not $SettingsPath) { $SettingsPath = Join-Path $home_ ".claude/settings.json" }
if (-not $ScriptPath) { $ScriptPath = Join-Path $home_ ".samjil/delegate-agy/scripts/sub/claude-statusline.js" }

$cmd = 'node "' + ($ScriptPath -replace '\\', '/') + '"'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Test-SamjilStatusLine($sl) {
    if ($null -eq $sl) { return $false }
    $c = ""
    if ($sl -is [System.Collections.IDictionary]) {
        $c = [string]$sl["command"]
    } elseif ($sl.PSObject.Properties["command"]) {
        $c = [string]$sl.command
    }
    if (-not $c) { return $false }
    return ($c.IndexOf("claude-statusline.js", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $c.IndexOf("statusline-probe.js", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

$settings = $null
$existed = Test-Path -LiteralPath $SettingsPath -PathType Leaf
if ($existed) {
    $text = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if ($text.Trim()) {
        try { $settings = $text | ConvertFrom-Json } catch { Write-Error "설정 파일을 JSON 으로 읽을 수 없어 건드리지 않았습니다: $SettingsPath ($($_.Exception.Message))"; exit 1 }
    }
}
if (-not $settings) { $settings = [pscustomobject]@{} }

$hasProp = [bool]$settings.PSObject.Properties["statusLine"]
$curSl = if ($hasProp) { $settings.statusLine } else { $null }
$isOurs = ($hasProp -and $null -ne $curSl -and (Test-SamjilStatusLine $curSl))

if ($Check) {
    if (-not $hasProp -or $null -eq $curSl) { "ABSENT" }
    elseif ($isOurs) { "PRESENT" }
    else { "OTHER" }
    exit 0
}

$result = ""
if ($Remove) {
    if (-not $hasProp -or $null -eq $curSl) { "NOTFOUND"; exit 0 }
    if (-not $isOurs) { "SKIPPED"; exit 0 }
    $settings.PSObject.Properties.Remove("statusLine")
    $result = "REMOVED"
} else {
    if ($hasProp -and $null -ne $curSl -and -not $isOurs) {
        "SKIPPED"
        exit 0
    }
    if ($isOurs) {
        $curType = if ($curSl.PSObject.Properties["type"]) { [string]$curSl.type } else { "" }
        $curCmd = if ($curSl.PSObject.Properties["command"]) { [string]$curSl.command } else { "" }
        if ($curType -eq "command" -and $curCmd -eq $cmd) {
            "UNCHANGED"
            exit 0
        }
        $result = "UPDATED"
    } else {
        $result = "ADDED"
    }
    $newSl = [pscustomobject]@{ type = "command"; command = $cmd }
    if ($hasProp) {
        $settings.statusLine = $newSl
    } else {
        $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $newSl
    }
}

$dir = Split-Path -Parent $SettingsPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
if ($existed) { Copy-Item -LiteralPath $SettingsPath -Destination ($SettingsPath + ".bak-" + (Get-Date -Format "yyyyMMddHHmmss")) -Force }
$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($SettingsPath, $json, $utf8)
$result
