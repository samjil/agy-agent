if ($MyInvocation.MyCommand.Path -and (-not $env:SAMJIL_UTF8_ACTIVE)) {
    $env:SAMJIL_UTF8_ACTIVE = "1"
    try {
        $utf8Content = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path, [System.Text.Encoding]::UTF8)
        $sb = [scriptblock]::Create($utf8Content)
        & $sb @args
        exit $LASTEXITCODE
    } finally {
        $env:SAMJIL_UTF8_ACTIVE = $null
    }
}

# ==========================================================
#  Agy Agent Uninstaller
#  Antigravity & Claude Code 스킬 원클릭 제거 스크립트
#
#  사용법:
#    1. 로컬 실행:
#       .\uninstall.ps1
#    2. 웹 원클릭 실행 (irm | iex):
#       irm https://raw.githubusercontent.com/samjil/agy-agent/main/uninstall.ps1 | iex
#
#  * 에이전트 간 대화 기록(~/.samjil/handoff/channels/<프로젝트>/msg/)과 핸드오프 DB(~/.samjil/handoff/data)는
#    제거 시에도 지우지 않습니다. 3개월이 지난 메시지는 워처가 켜질 때 알아서 지웁니다.
#  * 위임하면서 생긴 파일(~/.samjil/delegate-agy/runtime 의 큐 · 기록 DB · 로그 · 스크린샷)도 지우지 않습니다.
#    install.ps1 이 놓은 도구(scripts)만 지웁니다. 위임 작업 파일은 워처가 30일이 지난 것부터 알아서 지웁니다.
# ==========================================================

$Force = ($args -contains "-Force")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Agy Agent Uninstaller" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 안전한 스킬 디렉터리/정션 제거 함수
function Remove-SkillTarget([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        # 정션 링크 안전 해제
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$Path`"" > $null 2>&1
            Write-Host "[+] 정션 링크 해제: $Path" -ForegroundColor Green
        } else {
            Remove-Item -Recurse -Force -LiteralPath $Path
            Write-Host "[+] 스킬 디렉터리 삭제 완료: $Path" -ForegroundColor Green
        }
    } catch {
        Write-Warning "삭제 실패 ($Path): $_"
    }
}

$targetSkills = @("samjil-handoff", "samjil-delegate-agy", "samjil-git-commit", "agent-handoff", "agent-delegate-agy")

# -----------------------------------------------------------------------------
# 0. Stop the watcher and the dashboard first (so their files can be removed)
# -----------------------------------------------------------------------------
$stopAgy = Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\stop-agy.ps1"
if (Test-Path -LiteralPath $stopAgy) {
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stopAgy 2>&1 | Out-Null; Write-Host "[+] agy watcher stopped" -ForegroundColor Green } catch {}
}
$ensureViewer = Join-Path $env:USERPROFILE ".samjil\viewer\ensure-viewer-running.ps1"
if (Test-Path -LiteralPath $ensureViewer) {
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensureViewer -Stop 2>&1 | Out-Null } catch {}
}
Start-Sleep -Seconds 2

# -----------------------------------------------------------------------------
# 1. Claude Code 전역 스킬 제거 (~/.claude/skills/)
# -----------------------------------------------------------------------------
$claudeSkillsDir = Join-Path $env:USERPROFILE ".claude\skills"
foreach ($s in $targetSkills) {
    $targetPath = Join-Path $claudeSkillsDir $s
    if (Test-Path $targetPath) {
        Remove-SkillTarget $targetPath
    }
}

# -----------------------------------------------------------------------------
# 2. Antigravity (AGY) 전역 스킬 제거 (~/.agents/skills/)
# -----------------------------------------------------------------------------
$agentsSkillsDir = Join-Path $env:USERPROFILE ".agents\skills"
foreach ($s in $targetSkills) {
    $targetPath = Join-Path $agentsSkillsDir $s
    if (Test-Path $targetPath) {
        Remove-SkillTarget $targetPath
    }
}

# -----------------------------------------------------------------------------
# 2-1. 핸드오프 자동 이어가기 Stop 훅 제거 (~/.claude/settings.json 의 hooks.Stop 에서 우리 항목만)
# -----------------------------------------------------------------------------
$regHookScript = Join-Path $env:USERPROFILE ".samjil\handoff\scripts\register-handoff-hook.ps1"
if (Test-Path $regHookScript) {
    try {
        $hookRes = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $regHookScript -Remove 2>&1 | Out-String).Trim()
        if ($hookRes -eq "REMOVED") { Write-Host "[+] 핸드오프 Stop 훅 제거 (~/.claude/settings.json, 백업: settings.json.bak-*)" -ForegroundColor Green }
    } catch {
        Write-Warning "핸드오프 Stop 훅 제거 중 오류: $_"
    }
}

# 2-2. agy 워처 SessionStart 훅 제거 (~/.claude/settings.json 의 hooks.SessionStart 에서 우리 항목만)
$regSessionScript = Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\register-session-hook.ps1"
if (Test-Path $regSessionScript) {
    try {
        $sessRes = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $regSessionScript -Remove 2>&1 | Out-String).Trim()
        if ($sessRes -eq "REMOVED") { Write-Host "[+] agy 워처 SessionStart 훅 제거 (~/.claude/settings.json, 백업: settings.json.bak-*)" -ForegroundColor Green }
    } catch {
        Write-Warning "agy 워처 SessionStart 훅 제거 중 오류: $_"
    }
}

# -----------------------------------------------------------------------------
# 3. Antigravity 설정 정리 (~/.gemini/config/skills.json)
# -----------------------------------------------------------------------------
$skillsJsonPath = Join-Path $env:USERPROFILE ".gemini\config\skills.json"
if (Test-Path $skillsJsonPath) {
    try {
        $raw = Get-Content $skillsJsonPath -Raw -Encoding UTF8
        $json = ConvertFrom-Json $raw
        if ($json.entries) {
            $filtered = @()
            foreach ($e in $json.entries) {
                $p = $e.path
                # 저장소 직접 연결 또는 samjil 이전 임시 경로 제거
                if ($p -match "samjil" -or $p -match "github.com/samjil") {
                    Write-Host "[+] Antigravity skills.json 등록 해제: $p" -ForegroundColor Green
                } else {
                    $filtered += $e
                }
            }
            $json.entries = $filtered
            $updatedJson = ConvertTo-Json $json -Depth 10
            # BOM 없는 UTF-8로 씁니다 (install.ps1과 동일한 이유 - Antigravity의 JSON 파서가
            # BOM을 못 벗기면 skills.json 파싱이 깨질 수 있습니다).
            [System.IO.File]::WriteAllText($skillsJsonPath, $updatedJson, (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch {
        Write-Warning "skills.json 정리 중 오류: $_"
    }
}

# ~/.agents/.skill-lock.json 에서 samjil 스킬 등록 정보 정리
$skillLockPath = Join-Path $env:USERPROFILE ".agents\.skill-lock.json"
if (Test-Path $skillLockPath) {
    try {
        $rawLock = Get-Content $skillLockPath -Raw -Encoding UTF8
        $lockJson = ConvertFrom-Json $rawLock
        if ($lockJson.skills) {
            $lockChanged = $false
            foreach ($ts in $targetSkills) {
                if ($lockJson.skills.PSObject.Properties[$ts]) {
                    $lockJson.skills.PSObject.Properties.Remove($ts)
                    $lockChanged = $true
                }
            }
            if ($lockChanged) {
                $updatedLock = ConvertTo-Json $lockJson -Depth 10
                [System.IO.File]::WriteAllText($skillLockPath, $updatedLock, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "[+] ~/.agents/.skill-lock.json 등록 해제 완료" -ForegroundColor Green
            }
        }
    } catch {
        Write-Warning "skill-lock.json 정리 중 오류: $_"
    }
}

# -----------------------------------------------------------------------------
# 4. 부속 도구 및 런타임 정리 (~/.samjil/)
# -----------------------------------------------------------------------------
$samjilDir = Join-Path $env:USERPROFILE ".samjil"
if (Test-Path -LiteralPath $samjilDir) {
    # 4-1. 통합 웹 뷰어 실행부 제거
    $viewerDir = Join-Path $samjilDir "viewer"
    if (Test-Path -LiteralPath $viewerDir) {
        Remove-Item -Recurse -Force -LiteralPath $viewerDir -ErrorAction SilentlyContinue
        Write-Host "[+] 통합 웹 뷰어 디렉터리 삭제 완료: $viewerDir" -ForegroundColor Green
    }
    $webDir = Join-Path $samjilDir "web"
    if (Test-Path -LiteralPath $webDir) {
        Remove-Item -Recurse -Force -LiteralPath $webDir -ErrorAction SilentlyContinue
        Write-Host "[+] 웹 대시보드 파일 삭제 완료: $webDir" -ForegroundColor Green
    }
    $viewerFiles = @("serve-viewer.bat", "serve-viewer.ps1", "serve-dashboard.bat")
    foreach ($vf in $viewerFiles) {
        $vPath = Join-Path $samjilDir $vf
        if (Test-Path -LiteralPath $vPath) {
            Remove-Item -Force -LiteralPath $vPath -ErrorAction SilentlyContinue
            Write-Host "[+] 뷰어 실행 파일 삭제: $vPath" -ForegroundColor Green
        }
    }

    # 4-2. Delegate 디렉터리 정리: install.ps1 이 놓은 도구(scripts)만 지우고, 위임하면서 생긴 것(runtime: 큐 · 기록 DB · 로그 · 스크린샷 등)은 건드리지 않는다.
    #      위임 작업 파일은 워처가 켜질 때 30일이 지난 것부터 알아서 지운다(agy-retention.ps1).
    $delegateDirs = @(
        (Join-Path $samjilDir "delegate-agy"),
        (Join-Path $samjilDir "samjil-delegate-agy"),
        (Join-Path $samjilDir "agent-delegate-agy")
    )
    foreach ($dd in $delegateDirs) {
        if (Test-Path -LiteralPath $dd) {
            $scriptsPath = Join-Path $dd "scripts"
            if (Test-Path -LiteralPath $scriptsPath) {
                Remove-Item -Recurse -Force -LiteralPath $scriptsPath -ErrorAction SilentlyContinue
                Write-Host "[+] Delegate 설치 도구 삭제 완료: $scriptsPath" -ForegroundColor Green
            }
            Remove-Item -Force -LiteralPath (Join-Path $dd "reply-language.txt") -ErrorAction SilentlyContinue
            $leftFiles = @(Get-ChildItem -LiteralPath $dd -Recurse -File -Force -ErrorAction SilentlyContinue)
            if ($leftFiles.Count -gt 0) {
                Write-Host "[i] 위임하면서 생긴 파일($($leftFiles.Count)개)은 지우지 않고 보존합니다: $dd" -ForegroundColor Cyan
            } else {
                Remove-Item -Recurse -Force -LiteralPath $dd -ErrorAction SilentlyContinue
                Write-Host "[+] 빈 Delegate 디렉터리 삭제 완료: $dd" -ForegroundColor Green
            }
        }
    }

    # 4-3. Handoff 웹 뷰어 및 템플릿 도구 제거 (설치 시 추가된 툴링 파일만)
    $toolDirs = @(
        (Join-Path $samjilDir "handoff\templates"),
        (Join-Path $samjilDir "samjil-handoff\viewer"),
        (Join-Path $samjilDir "samjil-handoff\templates"),
        (Join-Path $samjilDir "agent-handoff\viewer"),
        (Join-Path $samjilDir "agent-handoff\templates")
    )
    foreach ($td in $toolDirs) {
        if (Test-Path -LiteralPath $td) {
            Remove-Item -Recurse -Force -LiteralPath $td -ErrorAction SilentlyContinue
            Write-Host "[+] Handoff 설치 도구 삭제 완료: $td" -ForegroundColor Green
        }
    }

    # 4-4. Handoff 대화 저장소 처리 (~/.samjil/handoff/, ~/.samjil/samjil-handoff/, ~/.samjil/agent-handoff/)
    $handoffDirs = @(
        (Join-Path $samjilDir "handoff"),
        (Join-Path $samjilDir "samjil-handoff"),
        (Join-Path $samjilDir "agent-handoff")
    )
    foreach ($hd in $handoffDirs) {
        if (Test-Path -LiteralPath $hd) {
            # 실제 대화 파일(.md)이 남아있는지 확인
            $handoffFiles = @(Get-ChildItem -LiteralPath $hd -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue)
            $handoffDb = Join-Path $hd "data\handoff.db"
            if ($handoffFiles.Count -gt 0 -or (Test-Path -LiteralPath $handoffDb)) {
                # 실제 대화 기록이 있으면 100% 영구 보존!
                Write-Host "[i] 에이전트 대화 기록($($handoffFiles.Count)건)이 존재하여 안전하게 보존합니다: $hd" -ForegroundColor Cyan
            } else {
                # 대화 파일이 없는 빈 폴더면 클린 삭제
                Remove-Item -Recurse -Force -LiteralPath $hd -ErrorAction SilentlyContinue
                Write-Host "[+] 빈 Handoff 디렉터리 삭제 완료: $hd" -ForegroundColor Green
            }
        }
    }

    # 4-5. 레거시 빈 디렉터리 정리
    $legacyDirs = @(
        (Join-Path $samjilDir "delegate")
    )
    foreach ($ld in $legacyDirs) {
        if (Test-Path -LiteralPath $ld) {
            $ldFiles = @(Get-ChildItem -LiteralPath $ld -Recurse -File -ErrorAction SilentlyContinue)
            if ($ldFiles.Count -eq 0) {
                Remove-Item -Recurse -Force -LiteralPath $ld -ErrorAction SilentlyContinue
            }
        }
    }

    # 4-6. ~/.samjil 루트 디렉터리가 비어있으면 삭제
    $remaining = @(Get-ChildItem -LiteralPath $samjilDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        Remove-Item -Force -LiteralPath $samjilDir -ErrorAction SilentlyContinue
        Write-Host "[+] 빈 ~/.samjil 디렉터리 정리 완료: $samjilDir" -ForegroundColor Green
    } else {
        Write-Host "[i] 에이전트 대화 기록이 보존되어 ~/.samjil 디렉터리를 유지합니다: $samjilDir" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  스킬 및 부속 도구 제거가 완료되었습니다." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
