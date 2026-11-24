# register-session-hook.ps1
# Claude Code 의 ~/.claude/settings.json 에 agy 워처 훅(session-start-hook.ps1)을 넣거나 뺍니다: SessionStart · UserPromptSubmit(컨텍스트 안내) · PreToolUse(Agent 도구 관문).
#   .\register-session-hook.ps1            # 넣기(이미 있으면 경로만 바꿈)
#   .\register-session-hook.ps1 -Check     # 지금 상태만 보기
#   .\register-session-hook.ps1 -Remove    # 빼기(다른 훅과 설정은 그대로)
# install.ps1 / uninstall.ps1 이 부른다. 바꾸기 전에 settings.json 을 .bak-<시각> 으로 백업하고,
# 설정 파일이 JSON 으로 읽히지 않으면 아무것도 건드리지 않고 오류로 끝낸다.
# 결과(stdout 한 줄): ADDED | UPDATED | UNCHANGED | REMOVED | NOTFOUND | PRESENT | ABSENT
param(
    [string]$SettingsPath = "",
    [string]$HookScript = "",
    [int]$TimeoutSeconds = 30,        # 훅은 워처 상태만 확인하고 기동은 백그라운드로 맡기므로 짧게
    [switch]$Remove,
    [switch]$Check,
    [switch]$NoNode                   # 질문마다 도는 훅을 Node 판(prompt-hook.js) 대신 PowerShell 판으로(시험 · Node 가 없을 때)
)
$ErrorActionPreference = "Stop"
$home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
if (-not $SettingsPath) { $SettingsPath = Join-Path $home_ ".claude/settings.json" }
if (-not $HookScript) { $HookScript = Join-Path $home_ ".samjil/delegate-agy/scripts/sub/session-start-hook.ps1" }
$marker = "session-start-hook.ps1"
$nodeMarker = "prompt-hook.js"
# 훅 명령은 셸이 무엇이든(cmd · PowerShell · Git Bash) 같은 뜻이 되도록 슬래시 경로를 큰따옴표로 감싼다.
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + ($HookScript -replace '\\', '/') + '"'
# 질문마다 · 도구 호출마다 도는 훅: Node 가 있으면 Node 판(약 0.1초), 없으면 PowerShell 판(약 0.6초). 같은 폴더의 prompt-hook.js 를 쓴다.
$promptCommand = $command + ' -Event UserPromptSubmit'
$preToolCommand = $command + ' -Event PreToolUse'
$nodeHook = Join-Path (Split-Path $HookScript -Parent) "prompt-hook.js"
if (-not $NoNode -and (Test-Path -LiteralPath $nodeHook)) {
    $nodeCmd = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nodeCmd) {
        $nodePath = $nodeHook -replace '\\', '/'
        $promptCommand = 'node "' + $nodePath + '"'
        $preToolCommand = 'node "' + $nodePath + '" --event PreToolUse'
    }
}

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

# 넣는 훅 셋: SessionStart(워처 켜기 + 규칙 한 줄) · UserPromptSubmit(컨텍스트가 크면 질문마다 서브에이전트 안내 한 줄) · PreToolUse(Agent 도구 관문)
$events = [ordered]@{
    "SessionStart"     = $command
    "UserPromptSubmit" = $promptCommand
    "PreToolUse"       = $preToolCommand
}
$eventMatchers = @{
    "PreToolUse" = "Agent|Task"
}

# 우리가 넣은 훅인가(PowerShell 판 또는 Node 판)
function Test-SamjilAgyHook($h) {
    if (-not $h) { return $false }
    $c = [string]$h.command
    return ($c.Contains($marker) -or $c.Contains($nodeMarker))
}

function Get-SessionHookEntries($s, [string]$Event = "SessionStart") {
    $found = @()
    if ($s.PSObject.Properties["hooks"] -and $s.hooks.PSObject.Properties[$Event]) {
        foreach ($g in @($s.hooks.$Event)) {
            if (-not $g) { continue }
            foreach ($h in @($g.hooks)) {
                if (Test-SamjilAgyHook $h) { $found += $h }
            }
        }
    }
    return @($found)
}

$ours = @(Get-SessionHookEntries $settings "SessionStart")
if ($Check) { if ($ours.Count -gt 0) { "PRESENT" } else { "ABSENT" }; exit 0 }

$result = ""
if ($Remove) {
    $removedAny = $false
    foreach ($ev in $events.Keys) {
        if (@(Get-SessionHookEntries $settings $ev).Count -eq 0) { continue }
        $removedAny = $true
        $newGroups = @()
        foreach ($g in @($settings.hooks.$ev)) {
            if (-not $g) { continue }
            $keep = @(@($g.hooks) | Where-Object { $_ -and -not (Test-SamjilAgyHook $_) })
            if ($keep.Count -gt 0) { $g.hooks = $keep; $newGroups += $g }
        }
        if ($newGroups.Count -gt 0) { $settings.hooks.$ev = $newGroups }
        else { $settings.hooks.PSObject.Properties.Remove($ev) }
    }
    if (-not $removedAny) { "NOTFOUND"; exit 0 }
    if (@($settings.hooks.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove("hooks") }
    $result = "REMOVED"
} else {
    $added = $false; $changed = $false
    foreach ($ev in $events.Keys) {
        $cmd = $events[$ev]
        $mine = @(Get-SessionHookEntries $settings $ev)
        if ($mine.Count -gt 0) {
            foreach ($h in $mine) {
                if ([string]$h.command -ne $cmd) { $h.command = $cmd; $changed = $true }
                if ($h.PSObject.Properties["timeout"]) { if ([int]$h.timeout -ne $TimeoutSeconds) { $h.timeout = $TimeoutSeconds; $changed = $true } }
                else { $h | Add-Member -NotePropertyName timeout -NotePropertyValue $TimeoutSeconds; $changed = $true }
            }
            if ($eventMatchers.ContainsKey($ev)) {
                $wantMatcher = $eventMatchers[$ev]
                foreach ($g in @($settings.hooks.$ev)) {
                    if (-not $g) { continue }
                    $hasMine = $false
                    foreach ($h in @($g.hooks)) { if (Test-SamjilAgyHook $h) { $hasMine = $true; break } }
                    if (-not $hasMine) { continue }
                    if ($g.PSObject.Properties["matcher"]) {
                        if ([string]$g.matcher -ne $wantMatcher) { $g.matcher = $wantMatcher; $changed = $true }
                    } else {
                        $g | Add-Member -NotePropertyName matcher -NotePropertyValue $wantMatcher
                        $changed = $true
                    }
                }
            }
        } else {
            if (-not $settings.PSObject.Properties["hooks"]) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
            if (-not $settings.hooks.PSObject.Properties[$ev]) { $settings.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @() }
            $hookItem = [pscustomobject]@{ type = "command"; command = $cmd; timeout = $TimeoutSeconds }
            if ($eventMatchers.ContainsKey($ev)) {
                $entry = [pscustomobject]@{ matcher = $eventMatchers[$ev]; hooks = @($hookItem) }
            } else {
                $entry = [pscustomobject]@{ hooks = @($hookItem) }
            }
            $settings.hooks.$ev = @(@($settings.hooks.$ev) + @($entry))
            if ($ev -eq "SessionStart") { $added = $true } else { $changed = $true }
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
