if ($MyInvocation.MyCommand.Path -and (-not $env:SAMJIL_UTF8_ACTIVE)) {
    # 이 파일은 BOM 없이 저장돼 있습니다(의도적). Windows PowerShell 5.1이 로컬 .ps1 파일을
    # 시스템 기본 코드페이지(예: CP949)로 읽어서 한글이 깨질 수 있는데, BOM을 붙이면 그건
    # 막지만 대신 `irm | iex`로 원격 실행할 때 문자열 맨 앞에 BOM 문자(U+FEFF)가 남아
    # 첫 줄 "if"가 예약어로 인식되지 않는 오류가 생깁니다. 그래서 BOM 대신, 로컬 파일로
    # 실행될 때만 자기 자신을 UTF-8로 다시 읽어 재실행해서 두 경로 모두 오류 없이 해결합니다.
    $env:SAMJIL_UTF8_ACTIVE = "1"
    $env:SAMJIL_SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
    try {
        $utf8Content = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path, [System.Text.Encoding]::UTF8)
        $sb = [scriptblock]::Create($utf8Content)
        & $sb @args
        exit $LASTEXITCODE
    } finally {
        $env:SAMJIL_UTF8_ACTIVE = $null
        $env:SAMJIL_SCRIPT_DIR = $null
    }
}

# install.ps1
# Agy Agent 전역 설치 스크립트 (Antigravity & Claude Code)
#
# [사용법 1: 로컬 실행]
#   저장소를 clone한 폴더에서:
#   .\install.ps1
#
# [사용법 2: 원격 웹 원라이너 (새 PC 등)]
#   저장소를 clone하지 않고 PowerShell에서 바로 실행:
#   irm https://raw.githubusercontent.com/samjil/agy-agent/main/install.ps1 | iex

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$ScriptDir = if ($env:SAMJIL_SCRIPT_DIR) { $env:SAMJIL_SCRIPT_DIR } elseif ($PSScriptRoot) { $PSScriptRoot } else { "" }
$TargetDir = ""
$Uninstall = $false
# 핸드오프 자동 이어가기 Stop 훅을 ~/.claude/settings.json 에 등록할지(옵트인). irm | iex 로 받을 때는 인자를 줄 수 없어
# 환경변수 SAMJIL_HANDOFF_AUTO_HOOK=1 로도 켠다.
$HandoffAutoHook = ($env:SAMJIL_HANDOFF_AUTO_HOOK -eq "1")
# -Full: the author's complete setup (~/.claude/skills becomes a junction to ~/.agents/skills, Antigravity skills.json,
#        legacy cleanup, session hook always on). Default (simple): copy the skills into ~/.claude/skills and the runtime
#        into ~/.samjil, touching nothing else. Env: SAMJIL_FULL=1 / SAMJIL_ALWAYS_ON=1 for `irm | iex`.
$Full = ($env:SAMJIL_FULL -eq "1")
$AlwaysOn = ($env:SAMJIL_ALWAYS_ON -eq "1")
$NoStart = $false
$SkipChecks = $false
$ReplyLanguage = ""
if ($args) {
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -eq "-TargetDir" -and ($i + 1) -lt $args.Count) {
            $TargetDir = $args[++$i]
        } elseif ($args[$i] -eq "-Full") {
            $Full = $true
        } elseif ($args[$i] -eq "-AlwaysOn") {
            $AlwaysOn = $true
        } elseif ($args[$i] -eq "-NoStart") {
            $NoStart = $true
        } elseif ($args[$i] -eq "-SkipChecks") {
            $SkipChecks = $true
        } elseif ($args[$i] -eq "-ReplyLanguage" -and ($i + 1) -lt $args.Count) {
            $ReplyLanguage = [string]$args[++$i]
        } elseif ($args[$i] -eq "-Uninstall") {
            $Uninstall = $true
        } elseif ($args[$i] -eq "-HandoffAutoHook") {
            $HandoffAutoHook = $true
        }
    }
}

if ($Uninstall) {
    $uninstallScript = Join-Path $ScriptDir "uninstall.ps1"
    if (-not [string]::IsNullOrEmpty($ScriptDir) -and (Test-Path $uninstallScript)) {
        & $uninstallScript
    } else {
        $rawUninstall = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/samjil/agy-agent/main/uninstall.ps1" -UseBasicParsing)
        Invoke-Expression $rawUninstall
    }
    exit 0
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Agy Agent Installer" -ForegroundColor Cyan
Write-Host "  (Antigravity & Claude Code 전역 설치기)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$isRemote = [string]::IsNullOrEmpty($ScriptDir) -or (-not (Test-Path (Join-Path $ScriptDir "samjil-handoff")))

if ($isRemote) {
    # 원격 실행 모드: GitHub에서 최신 소스 다운로드
    Write-Host "[*] 원격 설치 모드로 최신 패키지 다운로드 중..." -ForegroundColor Yellow
    $zipUrl = "https://github.com/samjil/agy-agent/archive/refs/heads/main.zip"
    $tempZip = Join-Path $env:TEMP "agy-agent-main.zip"
    $tempExtract = Join-Path $env:TEMP "agy-agent-extract"

    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
        if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract }
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

        $extractedRoot = Join-Path $tempExtract "agy-agent-main"
        if (-not (Test-Path $extractedRoot)) {
            $sub = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1
            if ($sub) { $extractedRoot = $sub.FullName }
        }
        $SkillsSourceDir = $extractedRoot
        Write-Host "[+] 최신 패키지 다운로드 완료!" -ForegroundColor Green
    } catch {
        Write-Error "GitHub 패키지 다운로드 실패: $($_.Exception.Message)"
        exit 1
    }
} else {
    # 로컬 저장소 모드 (저장소는 소스 관리 전용)
    $SkillsSourceDir = $ScriptDir
    Write-Host "[*] 로컬 설치 소스 패키지: $SkillsSourceDir" -ForegroundColor Gray
}

$SkillsSourceDir = (Resolve-Path $SkillsSourceDir).Path

# -----------------------------------------------------------------------------
# 1. Antigravity 설정 정리 및 ~/.agents/skills 등록 보장
# -----------------------------------------------------------------------------
# 저장소 자체(clone 한 폴더)는 스킬 경로로 직접 연결하지 않으므로 skills.json에서 제거합니다.
$GeminiConfigDir = Join-Path $env:USERPROFILE ".gemini\config"
$SkillsJsonPath = Join-Path $GeminiConfigDir "skills.json"
if ($Full) {

if (-not (Test-Path $GeminiConfigDir)) {
    New-Item -ItemType Directory -Force -Path $GeminiConfigDir | Out-Null
}

$configObj = $null
if (Test-Path $SkillsJsonPath) {
    try {
        $rawJson = Get-Content -LiteralPath $SkillsJsonPath -Raw -Encoding UTF8
        if ($rawJson -and $rawJson.Trim()) {
            $configObj = $rawJson | ConvertFrom-Json
        }
    } catch {}
}

if (-not $configObj) {
    $configObj = [PSCustomObject]@{ entries = @() }
}
if (-not $configObj.entries) {
    $configObj | Add-Member -MemberType NoteProperty -Name "entries" -Value @() -Force
}

# 저장소 경로나 samjil 관련 이전 직접 참조 항목 제거
$cleanedEntries = @()
$hasAgentsSkills = $false
foreach ($entry in $configObj.entries) {
    if ($entry -and $entry.path) {
        $p = [string]$entry.path
        if ($p -eq "~/.agents/skills" -or $p -eq ((Join-Path $env:USERPROFILE ".agents\skills").Replace('\', '/'))) {
            $hasAgentsSkills = $true
            $cleanedEntries += $entry
        } elseif ($p -match "samjil" -or $p -match "github.com/samjil") {
            # 저장소 직접 연결 해제
            Write-Host "[*] Antigravity skills.json 등록 해제: $p" -ForegroundColor Gray
        } else {
            $cleanedEntries += $entry
        }
    }
}

if (-not $hasAgentsSkills) {
    $cleanedEntries += [PSCustomObject]@{ path = "~/.agents/skills" }
    Write-Host "[+] Antigravity skills.json 에 ~/.agents/skills 등록 완료" -ForegroundColor Green
}

$configObj.entries = $cleanedEntries
$jsonOutput = $configObj | ConvertTo-Json -Depth 10
# [System.Text.Encoding]::UTF8은 BOM을 함께 씁니다. 이 파일은 Antigravity(Gemini CLI)가
# 별도로 읽는 설정 파일이라, 그쪽 JSON 파서가 BOM을 벗기지 않으면 파싱이 깨질 수 있습니다.
# UTF8Encoding($false)로 BOM 없이 순수 UTF-8로만 써도 한글 등 비ASCII 문자는 그대로
# 정확하게 인코딩되므로(깨짐 방지 목적은 그대로 유지), 여기서는 BOM만 뺍니다.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($SkillsJsonPath, $jsonOutput, $utf8NoBom)
}   # end if ($Full): Antigravity skills.json

# -----------------------------------------------------------------------------
# 2. 에이전트 스킬 배포 (Claude Code & Antigravity AGY)
#    -> 스킬 폴더에는 순수 SKILL.md 만 배치
# -----------------------------------------------------------------------------
$ClaudeSkillsRoot = Join-Path $env:USERPROFILE ".claude\skills"
$AgentsSkillsRoot = Join-Path $env:USERPROFILE ".agents\skills"

if ($Full) {
New-Item -ItemType Directory -Force -Path $AgentsSkillsRoot | Out-Null

# 구버전 스킬 정리 (agent-handoff, agent-delegate-agy)
$legacySkills = @("agent-handoff", "agent-delegate-agy")
foreach ($old in $legacySkills) {
    $cOld = Join-Path $ClaudeSkillsRoot $old
    if (Test-Path $cOld) {
        $item = Get-Item -LiteralPath $cOld -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { cmd /c rmdir "$cOld" 2>&1 | Out-Null }
        else { Remove-Item -Recurse -Force -LiteralPath $cOld -ErrorAction SilentlyContinue }
    }
    $aOld = Join-Path $AgentsSkillsRoot $old
    if (Test-Path $aOld) {
        Remove-Item -Recurse -Force -LiteralPath $aOld -ErrorAction SilentlyContinue
    }
}
}   # end if ($Full): legacy skill cleanup

# ~/.claude/skills 는 ~/.agents/skills 로 가는 정션 하나로 둔다. 이미 정션이면 그대로 둔다.
# 일반 폴더면 안에 든 것을 지우지 않고 ~/.agents/skills 로 옮긴 뒤 정션으로 바꾼다 — 사용자가 직접
# 넣은 스킬도 들어 있을 수 있고, 지우면 되살릴 곳이 없다. 이름이 겹치는 것은 보관만 한다.
function Convert-ClaudeSkillsToJunction {
    New-Item -ItemType Directory -Force -Path (Split-Path $ClaudeSkillsRoot -Parent) | Out-Null

    if (Test-Path -LiteralPath $ClaudeSkillsRoot) {
        $cItem = Get-Item -LiteralPath $ClaudeSkillsRoot -Force
        if ($cItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return }

        $backupDir = "$ClaudeSkillsRoot.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        foreach ($child in @(Get-ChildItem -LiteralPath $ClaudeSkillsRoot -Force)) {
            if ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                # 예전 설치가 스킬마다 만든 정션이다. 링크만 걷고 원본(~/.agents/skills)은 둔다
                cmd /c "rmdir `"$($child.FullName)`"" 2>&1 | Out-Null
                continue
            }
            $dest = Join-Path $AgentsSkillsRoot $child.Name
            if (Test-Path -LiteralPath $dest) {
                New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
                Move-Item -LiteralPath $child.FullName -Destination (Join-Path $backupDir $child.Name) -Force
                Write-Host "[!] ~/.agents/skills 에 같은 이름이 있어 보관만 했습니다: $($child.Name) -> $backupDir" -ForegroundColor Yellow
            } else {
                Move-Item -LiteralPath $child.FullName -Destination $dest
                Write-Host "[+] ~/.agents/skills 로 옮겼습니다: $($child.Name)" -ForegroundColor Green
            }
        }
        if (@(Get-ChildItem -LiteralPath $ClaudeSkillsRoot -Force).Count -gt 0) {
            throw "~/.claude/skills 를 비우지 못해 정션으로 바꾸지 않았습니다. 남은 항목을 확인해 주세요: $ClaudeSkillsRoot"
        }
        Remove-Item -LiteralPath $ClaudeSkillsRoot -Force
    }

    cmd /c mklink /J "$ClaudeSkillsRoot" "$AgentsSkillsRoot" 2>&1 | Out-Null
    $made = Get-Item -LiteralPath $ClaudeSkillsRoot -Force -ErrorAction SilentlyContinue
    if (-not $made -or -not ($made.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "~/.claude/skills 정션을 만들지 못했습니다. 스킬은 ~/.agents/skills 에 그대로 있습니다."
    }
    Write-Host "[+] Claude Code 단일 정션(Junction) 연결 완료: ~/.claude/skills -> ~/.agents/skills" -ForegroundColor Green
}

if ($Full) { Convert-ClaudeSkillsToJunction }
else { New-Item -ItemType Directory -Force -Path $ClaudeSkillsRoot | Out-Null }

$targetSkills = @("samjil-handoff", "samjil-delegate-agy", "samjil-git-commit")

foreach ($sName in $targetSkills) {
    $srcSkillDir = Join-Path $SkillsSourceDir $sName
    $srcSkillMd = Join-Path $srcSkillDir "SKILL.md"

    if (-not (Test-Path $srcSkillMd)) { continue }

    # (1) 공용 스킬 저장소: ~/.agents/skills/<skill-name>/
    $aDestDir = Join-Path $(if ($Full) { $AgentsSkillsRoot } else { $ClaudeSkillsRoot }) $sName
    if (Test-Path $aDestDir) {
        $subDirsToClean = @((Join-Path $aDestDir "scripts"), (Join-Path $aDestDir "viewer"), (Join-Path $aDestDir "templates"))
        foreach ($sd in $subDirsToClean) {
            if (Test-Path $sd) { Remove-Item -Recurse -Force -LiteralPath $sd -ErrorAction SilentlyContinue }
        }
    } else {
        New-Item -ItemType Directory -Force -Path $aDestDir | Out-Null
    }
    Copy-Item -Force -LiteralPath $srcSkillMd -Destination (Join-Path $aDestDir "SKILL.md")
    $srcRefs = Join-Path $srcSkillDir "references"
    if (Test-Path -LiteralPath $srcRefs) {
        $dstRefs = Join-Path $aDestDir "references"
        New-Item -ItemType Directory -Force -Path $dstRefs | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $srcRefs "*") -Destination $dstRefs
    }
    Write-Host "[+] 공용 스킬 저장소 배치 완료: $sName (SKILL.md)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 3. 부속 도구 및 스크립트, 웹 파일 설치 (~/.samjil/)
# -----------------------------------------------------------------------------
$SamjilRoot = Join-Path $env:USERPROFILE ".samjil"
New-Item -ItemType Directory -Force -Path $SamjilRoot | Out-Null

# 3-1. 런타임 배치 (~/.samjil/delegate-agy, ~/.samjil/handoff)
$srcRuntime = Join-Path $SkillsSourceDir "runtime"
if (Test-Path $srcRuntime) {
    $srcDelegate = Join-Path $srcRuntime "delegate-agy"
    if (Test-Path $srcDelegate) {
        $destDelegate = Join-Path $SamjilRoot "delegate-agy"
        New-Item -ItemType Directory -Force -Path $destDelegate | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $srcDelegate "*") -Destination $destDelegate
        Write-Host "[+] delegate-agy 런타임 및 스크립트 배치 완료 (~/.samjil/delegate-agy)" -ForegroundColor Green

        # 3-1a. 세션 시작 훅: 새 Claude 세션이 열릴 때 agy 워처를 창 없이 켜고 samjil-delegate-agy 스킬을 먼저 따르게 한다.
        #       Claude Code 설정을 바꾸므로 등록 전에 settings.json 을 백업한다(register-session-hook.ps1). 끄려면 uninstall.ps1.
        $regSession = Join-Path $destDelegate "scripts\sub\register-session-hook.ps1"
        $hookPresent = $false
        if (Test-Path $regSession) {
            try { $hookPresent = ((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $regSession -Check 2>&1 | Out-String).Trim() -eq "PRESENT") } catch {}
        }
        if ((Test-Path $regSession) -and ($AlwaysOn -or $Full -or $hookPresent)) {
            try {
                $sessOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $regSession 2>&1 | Out-String).Trim()
                Write-Host "[+] agy 워처 SessionStart 훅 등록: $sessOut (~/.claude/settings.json)" -ForegroundColor Green
            } catch {
                Write-Warning "agy 워처 SessionStart 훅 등록 중 오류: $_"
            }
        }
    }

    $srcHandoff = Join-Path $srcRuntime "handoff"
    if (Test-Path $srcHandoff) {
        $destHandoff = Join-Path $SamjilRoot "handoff"
        New-Item -ItemType Directory -Force -Path $destHandoff | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $srcHandoff "*") -Destination $destHandoff
        Write-Host "[+] handoff 템플릿·스크립트 배치 완료 (~/.samjil/handoff)" -ForegroundColor Green

        # 3-1b. 핸드오프 자동 이어가기 Stop 훅(옵트인): agy 회신이 오면 같은 Claude 세션에서 "메시지 확인해줘" 없이 이어 간다.
        #       Claude Code 설정을 바꾸는 일이라 -HandoffAutoHook 을 준 때만 하고, 바꾸기 전에 settings.json 을 백업한다.
        $regHook = Join-Path $destHandoff "scripts\register-handoff-hook.ps1"
        if (Test-Path $regHook) {
            try {
                $regArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $regHook)
                if (-not $HandoffAutoHook) { $regArgs += "-Check" }
                $regOut = (& powershell.exe @regArgs 2>&1 | Out-String).Trim()
                if ($HandoffAutoHook) {
                    Write-Host "[+] 핸드오프 자동 이어가기 Stop 훅 등록: $regOut (~/.claude/settings.json)" -ForegroundColor Green
                } elseif ($regOut -eq "PRESENT") {
                    Write-Host "[i] 핸드오프 자동 이어가기 Stop 훅이 이미 등록돼 있습니다(경로를 새로 고치려면 -HandoffAutoHook 로 다시 실행)." -ForegroundColor Gray
                } else {
                    Write-Host "[i] 핸드오프 자동 이어가기 Stop 훅은 등록하지 않았습니다. Claude 쪽도 자동으로 이어 가려면: .\install.ps1 -HandoffAutoHook" -ForegroundColor Gray
                }
            } catch {
                Write-Warning "핸드오프 Stop 훅 등록 중 오류: $_"
            }
        }
    }

    $srcViewer = Join-Path $srcRuntime "viewer"
    if (Test-Path $srcViewer) {
        $destViewer = Join-Path $SamjilRoot "viewer"
        New-Item -ItemType Directory -Force -Path $destViewer | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $srcViewer "*") -Destination $destViewer
        Write-Host "[+] 통합 웹 뷰어 배치 완료 (~/.samjil/viewer)" -ForegroundColor Green
    }
}

# 3-2. 중복/구버전 스크립트 및 이전 루트 파일 정리 (~/.samjil/)
$oldRedundantFiles = @(
    (Join-Path $SamjilRoot "serve-viewer.ps1"),
    (Join-Path $SamjilRoot "serve-viewer.bat"),
    (Join-Path $SamjilRoot "serve-dashboard.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\start-agy.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\stop-agy.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\restart-agy.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\serve-dashboard.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\serve-report.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\check-and-start.ps1"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\restart-agy.ps1"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\stop-watchdog.ps1")
)
foreach ($orf in $oldRedundantFiles) {
    if (Test-Path -LiteralPath $orf) {
        Remove-Item -Force -LiteralPath $orf -ErrorAction SilentlyContinue
    }
}
$oldRootWeb = Join-Path $SamjilRoot "web"
if (Test-Path -LiteralPath $oldRootWeb) {
    Remove-Item -Recurse -Force -LiteralPath $oldRootWeb -ErrorAction SilentlyContinue
}

# 3-4. 기존 레거시 데이터 자동 마이그레이션 (대화 기록 및 QA 로그 보존)
$newHandoffDir = Join-Path $SamjilRoot "handoff"
$legacyHandoffPaths = @(
    (Join-Path $SamjilRoot "samjil-handoff"),
    (Join-Path $SamjilRoot "agent-handoff"),
    (Join-Path $env:USERPROFILE ".agent-handoff")
)
foreach ($legacy in $legacyHandoffPaths) {
    if (Test-Path $legacy) {
        $legacyProjects = Get-ChildItem -LiteralPath $legacy -Directory -ErrorAction SilentlyContinue
        if ($legacyProjects.Count -gt 0) {
            New-Item -ItemType Directory -Force -Path $newHandoffDir | Out-Null
            foreach ($proj in $legacyProjects) {
                if ($proj.Name -eq "viewer" -or $proj.Name -eq "templates" -or $proj.Name -eq "scripts") { continue }
                $dest = Join-Path $newHandoffDir $proj.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item -Recurse -Force -LiteralPath $proj.FullName -Destination $dest
                    Write-Host "[*] 기존 대화 기록을 ~/.samjil/handoff 로 이전했습니다: $($proj.Name)" -ForegroundColor Green
                }
            }
        }
        Remove-Item -Recurse -Force -LiteralPath $legacy -ErrorAction SilentlyContinue
    }
}

$oldDelegateLogs = Join-Path $SamjilRoot "samjil-delegate-agy\runtime\logs"
$newDelegateLogs = Join-Path $SamjilRoot "delegate-agy\runtime\logs"
if (Test-Path $oldDelegateLogs) {
    if (-not (Test-Path $newDelegateLogs)) {
        New-Item -ItemType Directory -Force -Path (Join-Path $SamjilRoot "delegate-agy\runtime") | Out-Null
        Copy-Item -Recurse -Force -LiteralPath $oldDelegateLogs -Destination $newDelegateLogs
        Write-Host "[*] 기존 위임 로그를 ~/.samjil/delegate-agy 로 이전했습니다" -ForegroundColor Green
    }
    Remove-Item -Recurse -Force -LiteralPath (Join-Path $SamjilRoot "samjil-delegate-agy") -ErrorAction SilentlyContinue
}

# 원격 설치 임시 파일 정리
if ($isRemote) {
    Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------------
# 4. Post-install: unblock downloaded files, answer language, agy check, watcher self-test
#    (messages are ASCII on purpose)
# -----------------------------------------------------------------------------
$problems = New-Object System.Collections.ArrayList
Get-ChildItem -LiteralPath $SamjilRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {}
}
$versionSrc = Join-Path $SkillsSourceDir "VERSION"
if (Test-Path -LiteralPath $versionSrc) {
    $vText = [System.IO.File]::ReadAllText($versionSrc).Trim()
    if ($vText -and $vText -notmatch '\$Format') { [System.IO.File]::WriteAllText((Join-Path $SamjilRoot "VERSION"), $vText + "`r`n") }
}

$delegateHome = Join-Path $SamjilRoot "delegate-agy"
if (Test-Path -LiteralPath $delegateHome) {
    $langFile = Join-Path $delegateHome "reply-language.txt"
    if (-not $ReplyLanguage -and (Test-Path -LiteralPath $langFile)) {
        $ReplyLanguage = ([string](@(Get-Content -LiteralPath $langFile -Encoding UTF8 -TotalCount 1)[0])).Trim()   # re-running keeps the chosen language
    }
    # "auto" (the default) follows the Windows region (format) setting at run time, so changing the PC region changes agy's answers too.
    if (-not $ReplyLanguage -or $ReplyLanguage -notmatch '^[A-Za-z][A-Za-z \-]{1,30}$') { $ReplyLanguage = "auto" }
    [System.IO.File]::WriteAllText($langFile, $ReplyLanguage + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $shown = $ReplyLanguage
    if ($ReplyLanguage -ieq "auto") {
        try {
            . (Join-Path $delegateHome "scripts\sub\agy-rules.ps1")
            $shown = "auto, currently " + (Get-AgyOsLanguage) + ", from the Windows region setting"
        } catch {}
    }
    Write-Host "[+] agy answers in: $shown (edit $langFile to change; write a language name such as English to fix it)" -ForegroundColor Green
}

$agyOk = $true
if (-not $SkipChecks) {
    $agyCmd = Get-Command agy -ErrorAction SilentlyContinue
    if (-not $agyCmd) {
        $agyOk = $false
        [void]$problems.Add("agy was not found on PATH. Install the Antigravity CLI, open a NEW terminal, run 'agy' once to sign in, then run Install.cmd again.")
    } else {
        $job = Start-Job -ScriptBlock { & agy models 2>&1 | Out-String }
        if (Wait-Job $job -Timeout 25) {
            if ((Receive-Job $job) -match "gemini") { Write-Host "[+] agy found and signed in: $($agyCmd.Source)" -ForegroundColor Green }
            else { $agyOk = $false; [void]$problems.Add("agy is installed but did not list models. Run 'agy' once in a terminal and sign in, then run Install.cmd again.") }
        } else {
            Stop-Job $job
            $agyOk = $false
            [void]$problems.Add("'agy models' did not answer within 25 seconds. Check your network and sign-in, then run Install.cmd again.")
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

if (-not $NoStart -and $agyOk -and (Test-Path -LiteralPath $delegateHome)) {
    $ensure = Join-Path $delegateHome "scripts\sub\ensure-agy-running.ps1"
    try {
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ensure`"", "-ConfirmDelaySeconds", "0", "-StaleThresholdSeconds", "0") | Out-Null
        $watcherOk = $false
        for ($w = 0; $w -lt 10; $w++) {
            Start-Sleep -Seconds 3
            if ((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -CheckOnly -StaleThresholdSeconds 0 2>$null | Out-String).Trim() -eq "ALIVE") { $watcherOk = $true; break }
        }
        if ($watcherOk) { Write-Host "[+] Watcher is running (ALIVE)." -ForegroundColor Green }
        else { [void]$problems.Add("The watcher did not start within 30 seconds. See $delegateHome\runtime\logs\watchdog.log") }
    } catch { [void]$problems.Add("Could not start the watcher: $_") }
}

if (-not $Full) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    if ($problems.Count -eq 0) {
        Write-Host "  Done. Open Claude Code and say:  ask agy to say hello" -ForegroundColor Green
    } else {
        Write-Host "  Installed, but one thing needs your attention:" -ForegroundColor Yellow
        foreach ($p in $problems) { Write-Host "   - $p" -ForegroundColor Yellow }
    }
    Write-Host "  Skills : ~/.claude/skills/ (samjil-delegate-agy, samjil-handoff, samjil-git-commit)" -ForegroundColor Gray
    Write-Host "  Tools  : ~/.samjil/   Remove skills and tools: Uninstall.cmd" -ForegroundColor Gray
    if (-not $AlwaysOn) { Write-Host "  Mode   : on request. For delegation in every session run: Install.cmd -AlwaysOn" -ForegroundColor Gray }
    Write-Host "==========================================================" -ForegroundColor Cyan
}

if ($Full) {
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  설치가 성공적으로 완료되었습니다!" -ForegroundColor Green
Write-Host "  [스킬 (순수 SKILL.md)]" -ForegroundColor White
Write-Host "    - Claude Code        : ~/.claude/skills/ -> ~/.agents/skills/ (단일 정션)" -ForegroundColor Gray
Write-Host "    - Antigravity Skills : ~/.agents/skills/ (skills.json 연동)" -ForegroundColor Gray
Write-Host "  [도구 및 웹 파일 (~/.samjil)]" -ForegroundColor White
Write-Host "    - 통합 웹 뷰어 실행 : ~/.samjil/viewer/serve-viewer.bat (또는 .ps1)" -ForegroundColor Cyan
Write-Host "      (브라우저에서 Delegate QA / Handoff 탭 선택 열람)" -ForegroundColor Gray
Write-Host "      (창·브라우저 탭 없이 백그라운드로 켜기: ~/.samjil/viewer/ensure-viewer-running.ps1 또는 더블클릭 start-viewer-hidden.vbs — 워처도 함께 켜짐, 끄기는 -Stop)" -ForegroundColor Gray
Write-Host "    - 위임 워처 시작/재시작 : ~/.samjil/delegate-agy/scripts/start-agy.ps1" -ForegroundColor Gray
Write-Host "      (창 없이 시작하려면 -Hidden)" -ForegroundColor Gray
Write-Host "    - 위임 워처 안전 중지   : ~/.samjil/delegate-agy/scripts/stop-agy.ps1" -ForegroundColor Gray
Write-Host "    - 대화 저장소         : ~/.samjil/handoff/channels/ (원장·자동 설정 DB: ~/.samjil/handoff/data/handoff.db)" -ForegroundColor Gray
Write-Host "    - 핸드오프 자동 이어가기: agy 쪽은 워처가 자동 처리(채널에 AUTO.off 파일을 두면 끔). Claude 쪽은 .\install.ps1 -HandoffAutoHook 로 Stop 훅을 등록" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
}   # end if ($Full): original summary
