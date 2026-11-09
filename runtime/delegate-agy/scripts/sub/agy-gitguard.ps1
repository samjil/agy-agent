# agy-gitguard.ps1
# 코딩 위임(@cwd)에서 agy 가 지시를 어기고 git 상태를 바꿔도(커밋 · 브랜치 이동 · stash) Claude 가 바로 알아채고 복구할 수 있게 하는 안전장치입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-gitguard.ps1")`  (watch-agy.ps1 이 씁니다)
#
# 하는 일:
#   1) agy 를 부르기 직전에 @cwd 폴더가 속한 git 저장소마다 HEAD · 브랜치 · stash 개수를 기록한다. 작업 트리에 커밋 안 한 변경이 있으면
#      `git stash create` 로 스냅샷 커밋을 만들어 refs/samjil/snapshots/<작업ID> 에 보관한다(작업 트리·인덱스는 건드리지 않는 안전망이다. 최근 20개만 남긴다).
#   2) agy 가 끝난 뒤 다시 읽어 바뀐 것이 있으면 응답 맨 위에 경고 배너와 복구 명령을 붙인다.
#
# 하지 않는 일: 자동으로 되돌리기(git reset). agy 가 도는 10분 안팎 사이에 사용자나 Claude 가 같은 저장소에 정당한 커밋을 했거나 같은 폴더에서 다른
#   위임 작업이 돌았을 수 있어서, 자동 reset 은 그 커밋을 날릴 수 있다. 되돌릴지는 Claude 가 log · diff 를 보고 정한다(배너에 명령이 있다).
#   스냅샷은 추적 중인 파일의 변경만 담는다(untracked 파일은 안 담는다).
#
# 끄기: 환경변수 AGY_GIT_GUARD=off | 0 | false | no. git 이 없거나 저장소가 아니면 조용히 아무것도 하지 않는다(어떤 오류도 위임을 막지 않는다).

$script:AgyGitSnapshotKeep = 20

function Test-AgyGitGuardEnabled {
    $v = ([string]$env:AGY_GIT_GUARD).Trim()
    return -not ($v -match '^(?i:off|0|false|no)$')
}

# git 을 한 번 실행한다(창 없이, 표준출력 UTF-8). 반환: @{ Code; Out }. 실행하지 못하면 Code = -1.
function Invoke-AgyGit([string]$Dir, [string[]]$GitArgs, [int]$TimeoutMs = 30000) {
    try {
        $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $git.Source
        $psi.Arguments = (@($GitArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
        $psi.WorkingDirectory = $Dir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) { try { $p.Kill() } catch {}; return @{ Code = -1; Out = "" } }
        $p.WaitForExit()
        return @{ Code = $p.ExitCode; Out = ([string]$outTask.Result).Trim() }
    } catch {
        return @{ Code = -1; Out = "" }
    }
}

# 폴더가 속한 저장소의 최상위 폴더. 저장소가 아니거나 git 이 없으면 $null.
function Get-AgyGitRoot([string]$Dir) {
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return $null }
    $r = Invoke-AgyGit $Dir @("rev-parse", "--show-toplevel")
    if ($r.Code -ne 0 -or -not $r.Out) { return $null }
    return ($r.Out -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
}

function Read-AgyGitState([string]$Root) {
    $head = ""; $r = Invoke-AgyGit $Root @("rev-parse", "-q", "--verify", "HEAD"); if ($r.Code -eq 0) { $head = $r.Out }
    $branch = "(분리됨)"; $r = Invoke-AgyGit $Root @("symbolic-ref", "-q", "HEAD"); if ($r.Code -eq 0 -and $r.Out) { $branch = $r.Out -replace '^refs/heads/', '' }
    $stashCount = 0; $r = Invoke-AgyGit $Root @("stash", "list"); if ($r.Code -eq 0 -and $r.Out) { $stashCount = @($r.Out -split "\r?\n" | Where-Object { $_ }).Count }
    $dirty = $false; $r = Invoke-AgyGit $Root @("status", "--porcelain"); if ($r.Code -eq 0 -and $r.Out) { $dirty = $true }
    return @{ Head = $head; Branch = $branch; StashCount = $stashCount; Dirty = $dirty }
}

# 오래된 스냅샷 참조를 지운다(최근 $script:AgyGitSnapshotKeep 개만 남긴다).
function Remove-OldAgyGitSnapshots([string]$Root) {
    $r = Invoke-AgyGit $Root @("for-each-ref", "--sort=-committerdate", "--format=%(refname)", "refs/samjil/snapshots")
    if ($r.Code -ne 0 -or -not $r.Out) { return }
    $refs = @($r.Out -split "\r?\n" | Where-Object { $_ })
    if ($refs.Count -le $script:AgyGitSnapshotKeep) { return }
    foreach ($ref in @($refs | Select-Object -Skip $script:AgyGitSnapshotKeep)) { [void](Invoke-AgyGit $Root @("update-ref", "-d", $ref)) }
}

# agy 를 부르기 직전에: @cwd 폴더들이 속한 저장소(중복 없이)의 상태를 기록하고, 커밋 안 한 변경이 있으면 스냅샷을 만든다.
# 반환: @{ TaskId; Repos = @(@{ Root; Head; Branch; StashCount; SnapRef; SnapHash }) }  (꺼져 있거나 저장소가 없으면 Repos 가 빈 배열)
function New-AgyGitGuardState($Cwds, [string]$TaskId) {
    $state = @{ TaskId = $TaskId; Repos = @() }
    if (-not (Test-AgyGitGuardEnabled)) { return $state }
    try {
        $seen = @{}
        $repos = @()
        foreach ($d in @($Cwds)) {
            $root = Get-AgyGitRoot ([string]$d)
            if (-not $root -or $seen.ContainsKey($root.ToLowerInvariant())) { continue }
            $seen[$root.ToLowerInvariant()] = $true
            $st = Read-AgyGitState $root
            $snapRef = ""; $snapHash = ""
            if ($st.Dirty -and $st.Head -and $TaskId) {
                $c = Invoke-AgyGit $root @("stash", "create")
                if ($c.Code -eq 0 -and $c.Out -match '^[0-9a-f]{7,64}$') {
                    $ref = "refs/samjil/snapshots/$TaskId"
                    $u = Invoke-AgyGit $root @("update-ref", $ref, $c.Out)
                    if ($u.Code -eq 0) { $snapRef = $ref; $snapHash = $c.Out; Remove-OldAgyGitSnapshots $root }
                }
            }
            $repos += @{ Root = $root; Head = $st.Head; Branch = $st.Branch; StashCount = $st.StashCount; SnapRef = $snapRef; SnapHash = $snapHash }
        }
        $state.Repos = @($repos)
    } catch { $state.Repos = @() }
    return $state
}

# agy 가 끝난 뒤: 바뀐 것이 있으면 응답 맨 위에 붙일 경고 배너(마크다운 인용)를, 없으면 빈 문자열을 돌려준다.
#   $ConcurrentCount  같은 저장소 폴더를 겹쳐 쓰던 다른 위임 작업의 수(있으면 변화의 원인이 그 작업일 수 있다고 알린다)
function Get-AgyGitGuardBanner($State, [int]$ConcurrentCount = 0) {
    if (-not $State -or @($State.Repos).Count -eq 0) { return "" }
    $blocks = @()
    try {
        foreach ($repo in @($State.Repos)) {
            $now = Read-AgyGitState $repo.Root
            $changes = @()
            if ($now.Head -ne $repo.Head) {
                $text = "HEAD: $(if ($repo.Head) { $repo.Head.Substring(0, [math]::Min(8, $repo.Head.Length)) } else { '(커밋 없음)' }) -> $(if ($now.Head) { $now.Head.Substring(0, [math]::Min(8, $now.Head.Length)) } else { '(커밋 없음)' })"
                if ($repo.Head -and $now.Head) {
                    $lg = Invoke-AgyGit $repo.Root @("log", "--oneline", "-n", "5", "$($repo.Head)..$($now.Head)")
                    if ($lg.Code -eq 0 -and $lg.Out) { $text += " (새 커밋: " + (@($lg.Out -split "\r?\n") -join " / ") + ")" }
                    elseif ($lg.Code -eq 0) { $text += " (이전 HEAD 보다 앞선 커밋이 없음: 되감김·브랜치 이동일 수 있음)" }
                }
                $changes += $text
            }
            if ($now.Branch -ne $repo.Branch) { $changes += "브랜치: $($repo.Branch) -> $($now.Branch)" }
            if ($now.StashCount -ne $repo.StashCount) { $changes += "stash 개수: $($repo.StashCount) -> $($now.StashCount)" }
            if ($changes.Count -eq 0) { continue }
            $b = @("> **[경고: agy 가 git 상태를 바꾼 것으로 보입니다 — 저장소 ``$($repo.Root)``]**")
            foreach ($c in $changes) { $b += "> - $c" }
            if ($repo.Head -and $now.Head -ne $repo.Head) { $b += "> - 커밋만 풀고 변경은 작업 트리에 남기는 복구: ``git -C `"$($repo.Root)`" reset --mixed $($repo.Head)``" }
            if ($now.Branch -ne $repo.Branch -and $repo.Branch -ne "(분리됨)") { $b += "> - 원래 브랜치로: ``git -C `"$($repo.Root)`" switch $($repo.Branch)``" }
            if ($repo.SnapRef) { $b += "> - 작업 전 미커밋 변경 스냅샷: ``$($repo.SnapRef)`` (확인: ``git -C `"$($repo.Root)`" diff $($repo.SnapHash)``, 되살리기: ``git -C `"$($repo.Root)`" stash apply $($repo.SnapHash)``)" }
            if ($ConcurrentCount -gt 0) { $b += "> - 주의: 이 저장소 폴더를 겹쳐 쓰던 다른 위임 작업이 $ConcurrentCount 개 있었습니다. 위 변화는 그 작업의 것일 수 있으니 ``git log`` 로 확인하세요." }
            $b += "> - 워처는 자동으로 되돌리지 않았습니다. Claude 가 ``git log`` · ``git diff`` 를 확인한 뒤 필요한 명령만 직접 실행하세요(그 사이 사용자나 Claude 의 정당한 커밋이 있었을 수 있습니다)."
            $blocks += ($b -join "`n")
        }
    } catch { return "" }
    if ($blocks.Count -eq 0) { return "" }
    return (($blocks -join "`n`n") + "`n`n")
}
