# submit-task.ps1
# agy 위임 작업을 inbox 에 넣고 결과를 기다리는 한 줄짜리 도구입니다. Claude 가 위임 때마다 긴 bash(런타임 폴더 찾기 + 폴링 루프)를
# 새로 쓰지 않아도 되게 하려는 것입니다(출력 토큰 절약, 스크립트 실수 방지).
#
# 사용법 (지시문은 표준입력으로 받습니다):
#   powershell.exe -NoProfile -File "$env:USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1" <<'EOF'
#   @cwd: C:\project
#   <지시문>
#   EOF
#
#   -File <경로>        표준입력 대신 지시문 파일을 읽는다
#   -NoWait             넣기만 하고 작업 ID 만 출력한다(여러 개를 병렬로 보낼 때). 나중에 -Poll 로 기다린다
#   -Poll <ID>...       이미 보낸 작업(들)의 결과를 기다린다(쉼표·공백으로 여러 개). 시간 초과로 끝난 뒤 다시 확인할 때도 쓴다
#   -WaitSeconds <초>   기다리는 최대 시간(기본 170 — device_bash 한 호출이 3분 제한이라 그 안에 돌아오게)
#   -MaxWaitSec <초>    -WaitSeconds 와 같은 뜻이고, 주면 그것을 쓴다(폴 시작 기준 그 시간까지만 기다림, 연장 없음)
#   -CancelOnTimeout    기다리는 시간이 다 됐는데 안 끝난 작업을 취소한다. -MaxWaitSec 를 안 주면 작업 시작(claim started_at 또는 ID 제출 시각) 기준
#                       단계의 대기 한도(config\models.json 의 wait_sec: quick 3분 · build 8분 · build-hard 12분 · feature · feature-carbon · think · think-carbon · deep 20분)까지 기다린다.
#                       한도가 지나도 작업이 계속 진행 중이거나(대화 활동·도구 출력) 백그라운드 도구가 도는 중이면 대기를 연장하며, 5분간 진행이 없고 도는 백그라운드 도구도 없을 때나 2시간 절대 한도를 넘길 때만 취소한다.
#                       대기열에서 다른 작업 실행으로 차례를 기다리는 중이어도 워처가 살아 있으면 취소하지 않는다. 백그라운드 대기로 쓴다
#   지시문 맨 위에 "@model: <단계>" 를 쓰면 그 단계로 보낸다(quick · build · build-hard · feature · feature-carbon · think · think-carbon · deep). 없으면 워처가 quick/build 중에서 고른다.
#   지시문 맨 위에 "@cmd: <명령>"(goal · swarm · run-workflow · boost · browser · plan) · "@mode: <모드>"(plan · accept-edits · auto) 를 쓰면 실행 명령과 권한 모드를 함께 넘긴다.
#   새로 넣으면 표준 오류에 "[단계] <단계> (<모델>) · 대기 한도 <초>" 한 줄을 알린다.
#   지시문 맨 위에 "@reason: <한 줄>" 을 쓰면 위임 사유로 기록하고(claude-meta\<ID>.json 의 reason) agy 에 보내는 지시문에서는 뺀다.
#   -Cancel <ID>...     작업(들)을 취소한다: 대기 중이면 지시 파일을 치우고, 실행 중이면 작업자 프로세스 트리를 끝낸다. 기록 상태는 CANCELLED
#   -Status <ID>...     기다리지도 취소하지도 않고 작업(들)의 지금 상태만 한 줄씩 출력한다(쉼표·공백으로 여러 개, 읽기 전용)
#
# 출력(표준 출력):
#   submitted: <ID>                      (새로 넣었을 때)
#   ===RESULT=== <ID>  + 응답 본문         (응답 파일이 생김. 실패 사유도 응답으로 올 수 있으니 본문을 읽는다)
#   ===ERROR=== <ID>   + 거절 사유 또는 error.log 본문 (답변이 나오기 전에 실패함: 거절된 모델, 없는 폴더, 또는 오류 로그)
#   ===PENDING=== <ID> + 진행 상태 한 줄    (시간 안에 안 끝남: 경과 시간·모델·마지막 단계. 작업은 계속 돌고 있다 — 다시 제출하지 말고 -Poll 로 확인)
#   ===CANCELLED=== <ID> + 취소 사유       (취소됨: -Cancel 이나 -CancelOnTimeout 의 결과. 이미 취소된 작업을 -Poll 해도 이렇게 나온다)
#   ===DONE=== <ID>                       (-Cancel 했는데 이미 끝나 있어 취소하지 않음. 결과는 -Poll 로 읽는다)
#   ===NOTFOUND=== <ID>                   (-Cancel 했는데 대기열에도 실행 목록에도 없음)
#   ===STATUS=== <ID> <상태> | ...       (-Status 조회 결과: 완료 · 실패 · 취소 · 실행 중 · 작업자 사라짐(결과 없음) · 대기열 · 없음)
#   ===UPDATE_AVAILABLE===               (새 버전 안내로 제출 보류 — 아무것도 대기열에 넣지 않음, 같은 버전에 24시간 1회)
# 종료 코드: 0 모두 결과 있음(-Status 는 모두 완료·실패·취소·없음) / 1 오류가 있음 / 2 아직 진행 중(-Status 는 대기열·실행 중 있음) / 3 입력·환경 오류(런타임 폴더 없음, 지시문이 비었음 등) / 4 시간 초과로 취소함(-CancelOnTimeout, -Status 는 작업자 사라짐 있음) / 5 새 버전 안내로 제출 보류(===UPDATE_AVAILABLE===)
#
# 컨텍스트 알림: 새로 제출할 때 Claude 대화 기록 끝에서 컨텍스트 크기를 읽어, 기준(기본 200000 토큰, 환경변수 AGY_CTX_SUBAGENT_THRESHOLD)을 넘으면
#   표준 오류에 한 줄 알린다("위임 절차는 서브에이전트에 맡기세요"). 제출은 그대로 진행한다.

param(
    [string]$File = "",
    [string[]]$Poll = @(),
    [string[]]$Cancel = @(),
    [string[]]$Status = @(),
    [switch]$NoWait,
    [int]$WaitSeconds = 170,
    [int]$MaxWaitSec = 0,
    [switch]$CancelOnTimeout,
    [string]$RuntimeDir = "",
    [string]$Model = "",
    [string[]]$Cwd = @()
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8 } catch {}
$script:InProcSubmit = $false
$script:LastSubmitExitCode = 0
$script:SubmitErrBuf = $null

<#
.SYNOPSIS
표준 오류(stderr) 또는 인프로세스 테스트 버퍼로 오류/안내 한 줄을 기록합니다.
#>
function Write-SubmitErrorLine([string]$Message) {
    if ($script:InProcSubmit -and $null -ne $script:SubmitErrBuf) {
        [void]$script:SubmitErrBuf.Add([string]$Message)
    } else {
        [Console]::Error.WriteLine([string]$Message)
    }
}

<#
.SYNOPSIS
테스트용 양수 밀리초 환경변수를 읽습니다. 미설정/비정상 값이면 0을 반환합니다.
#>
function Get-SubmitTestMs([string]$Name) {
    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ($raw -match '^\d+$') {
        $v = [int]$raw
        if ($v -gt 0) { return $v }
    }
    return 0
}

<#
.SYNOPSIS
테스트 폴링 단축 환경변수(AGY_TEST_POLL_MS)가 설정되어 있으면 해당 ms, 아니면 기본 ms 만큼 대기합니다.
#>
function Start-SubmitPollSleep([int]$DefaultMs) {
    $tPoll = Get-SubmitTestMs "AGY_TEST_POLL_MS"
    $ms = if ($tPoll -gt 0) { $tPoll } else { $DefaultMs }
    Start-Sleep -Milliseconds ([Math]::Max(10, $ms))
}

<#
.SYNOPSIS
취소 정리 전 작업 완료 유예 시간 동안 완료 여부를 주기적으로 확인합니다.
#>
function Wait-SubmitTaskDoneGrace([string]$Id, [int]$DefaultStepMs, [int]$DefaultLimitMs) {
    $tPoll = Get-SubmitTestMs "AGY_TEST_POLL_MS"
    $tCWait = Get-SubmitTestMs "AGY_TEST_CANCEL_WAIT_MS"
    $stepMs = if ($tPoll -gt 0) { $tPoll } else { $DefaultStepMs }
    $limMs = if ($tCWait -gt 0) { $tCWait } else { $DefaultLimitMs }
    $maxSteps = [Math]::Max(1, [int][Math]::Ceiling($limMs / [double]$stepMs))
    for ($i = 0; $i -lt $maxSteps -and -not (Test-TaskDone $Id); $i++) {
        Start-Sleep -Milliseconds $stepMs
    }
}

function Stop-WithCode([int]$Code, [string]$Message) {
    if ($Message) { Write-SubmitErrorLine $Message }
    if ($script:InProcSubmit) {
        $script:LastSubmitExitCode = $Code
        throw "SAMJIL_SUBMIT_STOP"
    }
    exit $Code
}

# 런타임 폴더: -RuntimeDir > 환경변수 AGY_DELEGATE_RUNTIME > 이 스크립트 옆(설치 위치 ~/.samjil/delegate-agy/scripts -> ../runtime) > 예전 설치 이름들
. (Join-Path $PSScriptRoot "sub\agy-layout.ps1")

function Resolve-RuntimeDirForSubmit([string]$Given) {
    $cands = @()
    if ($Given) { $cands += $Given }
    if ($env:AGY_DELEGATE_RUNTIME) { $cands += $env:AGY_DELEGATE_RUNTIME }
    $cands += (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime")
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    foreach ($n in @(".samjil\delegate-agy", ".samjil\samjil-delegate-agy", ".samjil\agent-delegate-agy", ".samjil\delegate", ".agent-delegate")) {
        $cands += (Join-Path $home_ ($n + "\runtime"))
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c "inbox") -PathType Container)) { return $c }
    }
    return $null
}

function Read-AllStdin {
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, $utf8)
    return $reader.ReadToEnd()
}

function Read-TextFile([string]$Path) {
    return ([System.IO.File]::ReadAllText($Path, $utf8)).TrimStart([char]0xFEFF)
}

function Read-SubmitClaimJson([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    for ($try = 0; $try -lt 4; $try++) {
        $fs = $null
        $sr = $null
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $sr = New-Object System.IO.StreamReader($fs, $utf8, $true)
            $t = $sr.ReadToEnd()
            if ($t) { $t = $t.TrimStart([char]0xFEFF) }
            if (-not $t -or -not $t.Trim()) { return $null }
            return (ConvertFrom-Json -InputObject $t -ErrorAction Stop)
        } catch {
            if ($try -lt 3) { Start-Sleep -Milliseconds 20 }
        } finally {
            if ($sr) { try { $sr.Dispose() } catch {} }
            if ($fs) { try { $fs.Dispose() } catch {} }
        }
    }
    return $null
}

function Test-TaskDone([string]$Id) {
    foreach ($n in @("$Id.response.md", "$Id.error.log")) {
        $p = Join-Path $script:OutboxDir $n
        if ((Test-Path -LiteralPath $p -PathType Leaf) -and ((Get-Item -LiteralPath $p).Length -gt 0)) { return $true }
    }
    return $false
}

# 아직 끝나지 않은 작업의 상태를 한 줄로: 대기열 / 실행 중(경과·모델·마지막 단계) / 접수 기록 없음
function Get-PendingStatus([string]$Id) {
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    $claimPath = Join-Path $runningDir "$Id.json"
    $parts = @()
    $claim = Read-SubmitClaimJson $claimPath
    if ($claim) {
        $startText = if ($claim.started_at) { [string]$claim.started_at } else { [string]$claim.started }
        $st = [datetime]::MinValue
        if ($startText -and [datetime]::TryParse($startText, [ref]$st)) {
            $parts += ("경과 {0}분" -f [math]::Floor(((Get-Date) - $st).TotalMinutes))
        }
        if ($claim.PSObject.Properties['account'] -and $claim.account -and ([string]$claim.account -ne "primary")) {
            $parts += ("계정 " + [string]$claim.account)
        }
        if ($claim.model) { $parts += ("모델 " + [string]$claim.model) }
        if ($claim.session) { $parts += ("세션 " + [string]$claim.session) }
        $conv = [string]$claim.conversation_id
        $bridgeTr = if ($claim.PSObject.Properties['bridge_transcript']) { [string]$claim.bridge_transcript } else { "" }
        if ($bridgeTr -and (Test-Path -LiteralPath $bridgeTr -PathType Leaf)) {
            try {
                $progress = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
                if (Test-Path -LiteralPath $progress) {
                    . $progress
                    $step = Format-AgyLastStep (Get-AgyLastStepSummary "" "" $bridgeTr)
                    if ($step) { $parts += $step }
                }
            } catch {}
        } elseif ($conv) {
            try {
                $progress = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
                if (Test-Path -LiteralPath $progress) {
                    . $progress
                    $step = Format-AgyLastStep (Get-AgyLastStepSummary (Get-AgyHomeDir) $conv)
                    if ($step) { $parts += $step }
                }
            } catch {}
        } else {
            $parts += "agy 대화를 시작하는 중"
        }
        return ("진행 중 · " + ($parts -join " · "))
    }
    $queued = @(Get-ChildItem -LiteralPath (Join-Path $script:RuntimeDirResolved "inbox") -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Id })
    if ($queued.Count -gt 0) {
        $running = @(Get-ChildItem -LiteralPath $runningDir -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
        $text = "대기열에서 기다리는 중(지금 도는 작업 ${running}개)"
        $hb = @(Get-ChildItem -LiteralPath (Get-AgyLayout $script:RuntimeDirResolved).HeartbeatDir -Filter "hb_*.txt" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($hb.Count -eq 0 -or ((Get-Date) - $hb[0].LastWriteTime).TotalMinutes -gt 5) { $text += " · 워처 하트비트가 없습니다: 워처가 꺼져 있는지 확인하세요" }
        return $text
    }
    return "접수 기록 없음(inbox 에도 실행 목록에도 없음): 작업 ID 를 확인하세요"
}

# ensure-agy-running.ps1 경로(시험에서는 환경변수 AGY_TEST_ENSURE_SCRIPT 로 대체할 수 있다)
function Get-SubmitEnsureScript {
    if ($env:AGY_TEST_ENSURE_SCRIPT -and (Test-Path -LiteralPath $env:AGY_TEST_ENSURE_SCRIPT -PathType Leaf)) {
        return $env:AGY_TEST_ENSURE_SCRIPT
    }
    return (Join-Path $PSScriptRoot "sub\ensure-agy-running.ps1")
}

# 워처 상태를 ensure-agy-running.ps1 -CheckOnly -StaleThresholdSeconds 0 으로 확인한다(ALIVE | DEAD | MANUAL_STOP).
function Get-SubmitWatcherStatus {
    $ensure = Get-SubmitEnsureScript
    if (Test-Path -LiteralPath $ensure -PathType Leaf) {
        try {
            $out = @(& $ensure -RuntimeDir $script:RuntimeDirResolved -CheckOnly -StaleThresholdSeconds 0 2>$null)
            $word = ((@($out) -join "").Trim())
            if ($word -in @("ALIVE", "DEAD", "MANUAL_STOP")) { return $word }
        } catch {}
    }
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    if (Test-Path -LiteralPath $layout.LockFile -PathType Leaf) {
        $lockPid = 0
        try { $lockPid = [int]((Get-Content -LiteralPath $layout.LockFile -Raw -ErrorAction SilentlyContinue).Trim()) } catch { $lockPid = 0 }
        if ($lockPid -gt 0) {
            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") { return "ALIVE" }
        }
    }
    if (Test-Path -LiteralPath $layout.ManualStopFlag -PathType Leaf) { return "MANUAL_STOP" }
    return "DEAD"
}

# 살아 있는 워처의 PID 를 잠금 파일(또는 프로세스 목록)에서 읽는다. 못 찾으면 0.
function Get-SubmitWatcherPid {
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    if (Test-Path -LiteralPath $layout.LockFile -PathType Leaf) {
        $lockPid = 0
        try { $lockPid = [int]((Get-Content -LiteralPath $layout.LockFile -Raw -ErrorAction SilentlyContinue).Trim()) } catch { $lockPid = 0 }
        if ($lockPid -gt 0) {
            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") { return $lockPid }
        }
    }
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                Test-AgyWatcherProcessAlive -Process $_ -RuntimeDir $script:RuntimeDirResolved -StaleThresholdSeconds 0
            })
        if ($procs.Count -gt 0) { return [int]$procs[0].ProcessId }
    } catch {}
    return 0
}

# 실행 표시 파일(running\<ID>.json)에 필드를 합쳐 원자적으로 쓴다(watch-agy.ps1 의 Write-RunningClaim 과 같은 형식).
function Write-SubmitRunningClaim([string]$TaskId, [hashtable]$Fields) {
    if (-not $TaskId) { return }
    try {
        $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
        if (-not (Test-Path -LiteralPath $runningDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $runningDir | Out-Null
        }
        $path = Join-Path $runningDir ("{0}.json" -f $TaskId)
        $data = [ordered]@{ task_id = $TaskId }
        $old = Read-SubmitClaimJson $path
        if ($old) { foreach ($p in $old.PSObject.Properties) { $data[$p.Name] = $p.Value } }
        foreach ($k in $Fields.Keys) { $data[$k] = $Fields[$k] }
        $tmp = "$path.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $data -Compress -Depth 4), $utf8)
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {}
}

function Remove-SubmitRunningClaim([string]$TaskId) {
    if (-not $TaskId) { return }
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    Remove-Item -LiteralPath (Join-Path $runningDir ("{0}.json" -f $TaskId)) -Force -ErrorAction SilentlyContinue
}

function Get-TaskCwdsFromText([string]$Text) {
    $cwds = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($line in @(([string]$Text) -split "`r?`n")) {
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\ufeff?@cwd:\s*(.+)$') {
            $c = $Matches[1].Trim()
            $k = $c.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
            if ($k -and -not $seen.ContainsKey($k)) { $seen[$k] = $true; [void]$cwds.Add($c) }
        }
        elseif ($line -match '^\ufeff?@[A-Za-z]+\s*:') { }
        else { break }
    }
    return @($cwds.ToArray())
}

# 지시파일 맨 위에서 @session · @cwd 만 꺼낸다(직접 작업자 실행 시 running claim 에 기록).
function Get-SubmitTaskMeta([string]$TaskPath) {
    $session = ""
    $cwds = @()
    try {
        $raw = Read-TextFile $TaskPath
        $cwds = @(Get-TaskCwdsFromText $raw)
        foreach ($line in @($raw -split "`r?`n")) {
            if ($line -match '^\s*$') { continue }
            if ($line -match '^\ufeff?@session:\s*(.+)$') { $session = $Matches[1].Trim(); break }
            elseif ($line -match '^\ufeff?@[A-Za-z]+\s*:') { }
            else { break }
        }
    } catch {}
    return @{ Session = $session; Cwds = @($cwds) }
}

# 작업자 powershell 에 넘길 인자(watch-agy.ps1 의 Get-InboxWorkerArgs 와 같은 형식, 따옴표 없는 원래 값).
function Get-SubmitInboxWorkerArgs([string]$Wrapper, [string]$TaskPath, [string]$RepoRootValue, [string]$RuntimeDirValue, [bool]$Skip = $true) {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Wrapper,
        "-RepoRoot", $RepoRootValue, "-RuntimeDir", $RuntimeDirValue, "-WorkerTask", $TaskPath)
    if ($Skip) { $a += "-SkipPermissions" }
    return $a
}

# 띄운 작업자가 실제로 시작했는지 확인한다(watch-agy.ps1 의 Wait-InboxWorkerStarted 와 같은 판정).
function Wait-SubmitInboxWorkerStarted([int]$WorkerPid, [string]$TaskPath, [int]$TimeoutMs = 1500) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue)) {
            return (-not (Test-Path -LiteralPath $TaskPath))
        }
        Start-Sleep -Milliseconds 100
    }
    return $true
}

# 워처 없이 지시파일 하나를 작업자 모드(agy-task-worker.ps1 -> watch-agy.ps1 -WorkerTask)로 숨김 실행한다.
# 실행 전후에 running\<ID>.json claim 을 써서 -Poll · -Cancel · 뷰어가 실행 중으로 보게 한다. 성공하면 작업자 PID, 실패하면 0.
function Start-SubmitDirectWorker([string]$TaskId, [string]$TaskPath) {
    $wrapper = ""
    $isTestWorker = $false
    if ($env:AGY_TEST_WORKER_CMD) {
        $wrapper = $env:AGY_TEST_WORKER_CMD
        $isTestWorker = $true
    } else {
        $wrapper = Join-Path $PSScriptRoot "sub\agy-task-worker.ps1"
        if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
            $wrapper = Join-Path $PSScriptRoot "sub\watch-agy.ps1"
        }
    }
    if (-not $wrapper -or -not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { return 0 }

    $repoRootValue = Split-Path -Path $PSScriptRoot -Parent
    $meta = Get-SubmitTaskMeta $TaskPath
    $rawArgs = @(Get-SubmitInboxWorkerArgs $wrapper $TaskPath $repoRootValue $script:RuntimeDirResolved $true)
    $argList = @($rawArgs | ForEach-Object { if ([string]$_ -match '\s') { "`"$_`"" } else { [string]$_ } })
    try {
        Write-SubmitRunningClaim $TaskId @{ pid = 0; session = $meta.Session; cwds = @($meta.Cwds); started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); watcher_pid = 0 }
        $workerPid = 0
        if (-not (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue)) {
            $spawnLib = Join-Path $PSScriptRoot "sub\agy-spawn.ps1"
            if (Test-Path -LiteralPath $spawnLib -PathType Leaf) { . $spawnLib }
        }
        if (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue) {
            $workerPid = Start-AgyHiddenDetachedProcess -FilePath "powershell.exe" -ArgumentList $rawArgs -WorkingDirectory $script:RuntimeDirResolved -NoShellFallback
            if ($workerPid -gt 0 -and -not $isTestWorker -and -not (Wait-SubmitInboxWorkerStarted $workerPid $TaskPath)) {
                $workerPid = 0
            }
        }
        if ($workerPid -le 0) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = ($argList -join " ")
            $psi.WorkingDirectory = $script:RuntimeDirResolved
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $proc = [System.Diagnostics.Process]::Start($psi)
            $workerPid = $proc.Id
        }
        if ($isTestWorker -or (Test-Path -LiteralPath $TaskPath) -or ($null -ne (Get-Process -Id $workerPid -ErrorAction SilentlyContinue))) {
            Write-SubmitRunningClaim $TaskId @{ pid = $workerPid }
        } else {
            Remove-SubmitRunningClaim $TaskId
        }
        return $workerPid
    } catch {
        Remove-SubmitRunningClaim $TaskId
        return 0
    }
}

# 워처가 꺼져 있으면(DEAD · MANUAL_STOP) 워처를 숨김 기동해 최대 15초 기다린다.
# 그래도 켜지지 않으면 이 작업 하나를 작업자 모드로 직접 실행한다.
# 위임 제출/복구는 수동 정지를 덮어쓰므로, 상태 확인 전에 manual_stop.flag 와 남은 stop.signal 을 항상 지운다
# (워처가 ALIVE 로 보여도 플래그 때문에 곧 종료하려 할 수 있기 때문).
function Ensure-SubmitWatcherOrDirectWorker([string]$TaskId, [string]$TaskPath) {
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    # start-agy.ps1 과 같은 방식으로 수동 정지 표시와 남은 정지 신호를 먼저 지운다
    Remove-Item -LiteralPath $layout.ManualStopFlag -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $layout.StopSignalFile -Force -ErrorAction SilentlyContinue

    $status = Get-SubmitWatcherStatus
    if ($status -eq "ALIVE") {
        return @{ Mode = "alive"; Pid = (Get-SubmitWatcherPid) }
    }

    $watcherAliveNow = $false
    if ($env:AGY_TEST_NO_WATCHER_START -ne "1") {
        $ensure = Get-SubmitEnsureScript
        if (Test-Path -LiteralPath $ensure -PathType Leaf) {
            try {
                & $ensure -RuntimeDir $script:RuntimeDirResolved -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0 2>$null | Out-Null
            } catch {}
        }
        $maxWait = 15
        if ($env:AGY_TEST_WATCHER_WAIT_SECONDS -match '^\d+$') { $maxWait = [int]$env:AGY_TEST_WATCHER_WAIT_SECONDS }
        for ($w = 0; $w -le $maxWait; $w++) {
            if ((Get-SubmitWatcherStatus) -eq "ALIVE") { $watcherAliveNow = $true; break }
            if ($w -lt $maxWait) { Start-SubmitPollSleep 1000 }
        }
    }

    if ($watcherAliveNow) {
        $wpid = Get-SubmitWatcherPid
        Write-SubmitErrorLine "[워처] 꺼져 있어 켰습니다(PID $wpid)."
        return @{ Mode = "watcher_started"; Pid = $wpid }
    }

    if ($TaskPath -and (Test-Path -LiteralPath $TaskPath -PathType Leaf)) {
        $workerPid = Start-SubmitDirectWorker $TaskId $TaskPath
        if ($workerPid -gt 0) {
            Write-SubmitErrorLine "[워처 없음] 워처를 켜지 못해 이 작업을 작업자로 직접 실행합니다(PID $workerPid)."
            return @{ Mode = "direct_worker"; Pid = $workerPid }
        }
    }
    return @{ Mode = "failed"; Pid = 0 }
}

# 대기열(inbox 에 있고 실행 표시 없음) 작업인데 워처가 꺼져 있으면, 작업당 한 번 워처를 켜거나 작업자를 직접 띄운다.
# 워처가 첫 점검 뒤에 종료될 수 있으므로 매 폴 라운드마다 다시 확인한다. 복구에 성공하면 $true.
function Try-RecoverQueuedTask([string]$TaskId, [hashtable]$RecoverTried, [string]$RunningDir) {
    if ($RecoverTried.ContainsKey($TaskId)) { return $false }
    $claimPath = Join-Path $RunningDir "$TaskId.json"
    if (Test-Path -LiteralPath $claimPath -PathType Leaf) { return $false }
    $queuedNow = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $TaskId } | Select-Object -First 1)
    if ($queuedNow.Count -eq 0) { return $false }
    if ((Get-SubmitWatcherStatus) -eq "ALIVE") { return $false }
    $RecoverTried[$TaskId] = $true
    $recRes = Ensure-SubmitWatcherOrDirectWorker $TaskId $queuedNow[0].FullName
    return ($null -ne $recRes -and ($recRes.Mode -in @("watcher_started", "direct_worker")))
}

# 다른 작업이 실제로 실행 중인지(PID 프로세스 살아있음) 확인한다
function Test-OtherTaskRunning([string]$MyTaskId) {
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    if (-not (Test-Path -LiteralPath $runningDir -PathType Container)) { return $false }
    foreach ($f in @(Get-ChildItem -LiteralPath $runningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        if ([System.IO.Path]::GetFileNameWithoutExtension($f.Name) -eq $MyTaskId) { continue }
        try {
            $claim = Read-SubmitClaimJson $f.FullName
            if ($claim) {
                $claimPid = 0
                try { $claimPid = [int]$claim.pid } catch { $claimPid = 0 }
                if ($claimPid -gt 0) {
                    $p = Get-Process -Id $claimPid -ErrorAction SilentlyContinue
                    if ($p -and -not $p.HasExited) { return $true }
                }
            }
        } catch {}
    }
    return $false
}

# 작업 시작 시각: 실행 중 claim started_at > 작업 ID 에 담긴 제출 시각(claude_<epoch>_N) > 폴 시작 시각(fallback)
function Get-TaskStartTime([string]$Id, [datetime]$Fallback) {
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    $claimPath = Join-Path $runningDir "$Id.json"
    $claim = Read-SubmitClaimJson $claimPath
    if ($claim) {
        try {
            $startText = if ($claim.started_at) { [string]$claim.started_at } else { [string]$claim.started }
            $st = [datetime]::MinValue
            if ($startText -and [datetime]::TryParse($startText, [ref]$st)) {
                return $st
            }
        } catch {}
    }
    if ($Id -match '^claude_(\d{9,11})_\d+$') {
        try {
            return [DateTimeOffset]::FromUnixTimeSeconds([int64]$Matches[1]).LocalDateTime
        } catch {}
    }
    return $Fallback
}

<#
.SYNOPSIS
실행 중인 작업의 대화 기록·백그라운드 도구 로그·하위 에이전트·부계정 claim 을 확인해 최근 활동 시각과 사유를 반환합니다.
#>
function Get-SubmitTaskActivity($Claim, [string]$AgyHome, [datetime]$Now) {
    $convId = if ($Claim -and $Claim.PSObject.Properties['conversation_id'] -and $Claim.conversation_id) { [string]$Claim.conversation_id } else { "" }
    $bridgeTr = if ($Claim -and $Claim.PSObject.Properties['bridge_transcript'] -and $Claim.bridge_transcript) { [string]$Claim.bridge_transcript } else { "" }
    $hasBridgeTr = [bool]($bridgeTr -and (Test-Path -LiteralPath $bridgeTr -PathType Leaf))
    $actSubClaim = $null
    if ($Claim -and $Claim.PSObject.Properties['last_activity_utc'] -and $Claim.last_activity_utc) {
        $parsedSubDto = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$Claim.last_activity_utc, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$parsedSubDto)) {
            $actSubClaim = $parsedSubDto.LocalDateTime
        }
    }

    $latestAct = $null
    $actReason = ""
    $hasSource = [bool]($convId -or $hasBridgeTr -or $actSubClaim)
    if ($hasSource) {
        $actConv = if ($convId -or $hasBridgeTr) { Get-AgyConversationActivity $AgyHome $convId $(if ($hasBridgeTr) { $bridgeTr } else { "" }) } else { $null }
        $actTask = if ($hasBridgeTr -or -not $convId) { $null } else { Get-AgyTaskLogActivity $AgyHome $convId }
        $actChild = if ($hasBridgeTr -or -not $convId) { $null } else { Get-AgyChildConversationActivity $AgyHome $convId }

        if ($actConv -and ($null -eq $latestAct -or $actConv -gt $latestAct)) {
            $latestAct = $actConv
            $actReason = "새 단계 기록됨"
        }
        if ($actTask -and ($null -eq $latestAct -or $actTask -gt $latestAct)) {
            $latestAct = $actTask
            $actReason = "백그라운드 도구 출력"
        }
        if ($actChild -and ($null -eq $latestAct -or $actChild -gt $latestAct)) {
            $latestAct = $actChild
            $actReason = "하위 에이전트 활동"
        }
        if ($actSubClaim -and ($null -eq $latestAct -or $actSubClaim -gt $latestAct)) {
            $latestAct = $actSubClaim
            $actReason = "부계정 작업자 활동"
        }
    }

    $agoSec = if ($latestAct) { [int][Math]::Max(0, ($Now - $latestAct).TotalSeconds) } else { $null }
    return @{
        HasSource        = $hasSource
        ConvId           = $convId
        BridgeTranscript = $bridgeTr
        HasBridgeTr      = $hasBridgeTr
        LatestActivity   = $latestAct
        Reason           = $actReason
        AgoSeconds       = $agoSec
    }
}

<#
.SYNOPSIS
delegate.db 에서 작업의 상태·소요 시간·모델 메타를 읽기 전용으로 조회합니다.
#>
function Read-SubmitTaskDbMeta([string]$DbPath, [string]$TaskId) {
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return $null }
    try {
        # agy-db.ps1 의 읽기 전용 열기를 쓴다(컴파일한 SQLite 래퍼를 캐시해 두어 빠르다).
        if (-not (Get-Command Open-AgyDbReadOnly -ErrorAction SilentlyContinue)) {
            $dbLib = Join-Path $PSScriptRoot "sub\agy-db.ps1"
            if (Test-Path -LiteralPath $dbLib -PathType Leaf) { . $dbLib }
        }
        if (-not (Get-Command Open-AgyDbReadOnly -ErrorAction SilentlyContinue)) { return $null }
        $db = Open-AgyDbReadOnly $DbPath 1000
        try {
            $rows = @($db.Query("SELECT status, elapsed_sec, model, tried_models, account FROM tasks WHERE task_id = ?", [object[]]@($TaskId)))
            if ($rows.Count -gt 0) { return $rows[0] }
        } finally {
            $db.Dispose()
        }
    } catch {}
    return $null
}

<#
.SYNOPSIS
작업 ID 하나의 현재 상태를 파일·DB·프로세스 기준으로 읽기 전용 판정해 한 줄 요약과 종료 코드를 반환합니다.
#>
function Get-SubmitTaskStatusEntry([string]$Id, $Layout, [string]$AgyHome, [datetime]$Now, [ref]$CachedWatcherStatus) {
    $respPath = Join-Path $script:OutboxDir "$Id.response.md"
    $errPath  = Join-Path $script:OutboxDir "$Id.error.log"
    $hasResp = (Test-Path -LiteralPath $respPath -PathType Leaf) -and ((Get-Item -LiteralPath $respPath).Length -gt 0)
    $hasErr  = (Test-Path -LiteralPath $errPath -PathType Leaf) -and ((Get-Item -LiteralPath $errPath).Length -gt 0)

    if ($hasResp -or $hasErr) {
        $respText = if ($hasResp) { Read-TextFile $respPath } else { "" }
        $firstLine = if ($respText) { (($respText -split "`r?`n")[0]).Trim() } else { "" }
        $errText = if ($hasErr) { Read-TextFile $errPath } else { "" }
        $isRejected = ($hasErr -and ($errText -match '^\ufeff?지정한 @(model|cwd|cmd|mode) '))

        $dbRows = @(Read-SubmitTaskDbMeta $Layout.DbPath $Id)
        $dbRow = if ($dbRows.Count -gt 0) { $dbRows[0] } else { $null }
        $dbStatus = if ($dbRow -and $dbRow["status"]) { ([string]$dbRow["status"]).Trim().ToUpperInvariant() } else { "" }

        $stateLabel = "완료"
        if ($isRejected) {
            $stateLabel = "실패"
        } elseif ($hasResp -and ($respText.StartsWith($script:CancelledPrefix) -or $firstLine -match '^(취소됨\(CANCELLED\)|CANCELLED\b)')) {
            $stateLabel = "취소"
        } elseif ($dbStatus -eq "CANCELLED") {
            $stateLabel = "취소"
        } elseif ($dbStatus -in @("ERROR", "FAIL", "FAILED")) {
            $stateLabel = "실패"
        } elseif ($dbStatus -eq "OK") {
            $stateLabel = "완료"
        } elseif (-not $hasResp -and $hasErr) {
            $stateLabel = "실패"
        } elseif ($firstLine -match '^(ERROR\b|\[ERROR\]|실패\b|지정한 @(model|cwd|cmd|mode) )') {
            $stateLabel = "실패"
        }

        $tsFile = if ($hasResp -and -not $isRejected) { $respPath } elseif ($hasErr) { $errPath } else { $respPath }
        $finishedAt = (Get-Item -LiteralPath $tsFile).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $parts = @("끝난 시각 $finishedAt")
        if ($dbRow -and $null -ne $dbRow["elapsed_sec"]) {
            $elRaw = ([string]$dbRow["elapsed_sec"]).Trim()
            if ($elRaw) {
                $elDisplay = if ($elRaw.EndsWith("초")) { $elRaw } else { "{0}초" -f $elRaw }
                $parts += ("소요 {0}" -f $elDisplay)
            }
        }
        if ($dbRow -and $dbRow["model"]) {
            $dbModel = ([string]$dbRow["model"]).Trim()
            if ($dbModel) { $parts += ("모델 {0}" -f $dbModel) }
        }
        return @{
            Line     = ("===STATUS=== {0} {1} | {2}" -f $Id, $stateLabel, ($parts -join " | "))
            ExitCode = 0
        }
    }

    $claimPath = Join-Path $Layout.RunningDir "$Id.json"
    if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
        $claim = Read-SubmitClaimJson $claimPath
        $claimPid = 0
        if ($claim -and $claim.PSObject.Properties['pid'] -and $null -ne $claim.pid) {
            [int]::TryParse([string]$claim.pid, [ref]$claimPid) | Out-Null
        }
        $workerAlive = ($claimPid -gt 4 -and $null -ne (Get-Process -Id $claimPid -ErrorAction SilentlyContinue))

        $parts = @()
        if ($workerAlive) {
            $parts += ("PID {0} 살아 있음" -f $claimPid)
        } else {
            if ($claimPid -gt 0) { $parts += ("PID {0} 없음" -f $claimPid) }
            else { $parts += "PID 없음" }
        }

        if ($claim) {
            $startText = if ($claim.PSObject.Properties['started_at'] -and $claim.started_at) { [string]$claim.started_at } elseif ($claim.PSObject.Properties['started'] -and $claim.started) { [string]$claim.started } else { "" }
            $st = [datetime]::MinValue
            if ($startText -and [datetime]::TryParse($startText, [ref]$st)) {
                $parts += ("시작 {0}" -f $st.ToString("yyyy-MM-dd HH:mm:ss"))
                $elSpan = $Now - $st
                if ($elSpan.TotalSeconds -lt 0) { $elSpan = [TimeSpan]::Zero }
                $totalMin = [int][Math]::Floor($elSpan.TotalMinutes)
                $parts += ("경과 {0:00}:{1:00}" -f $totalMin, $elSpan.Seconds)
            }

            $claimModel = if ($claim.PSObject.Properties['model'] -and $claim.model) { ([string]$claim.model).Trim() } else { "" }
            $claimTried = if ($claim.PSObject.Properties['tried'] -and $claim.tried) { ([string]$claim.tried).Trim() } else { "" }
            if ($claimModel -and $claimTried -and $claimTried -ne $claimModel) {
                $parts += ("모델 {0} (시도 {1})" -f $claimModel, $claimTried)
            } elseif ($claimModel) {
                $parts += ("모델 {0}" -f $claimModel)
            } elseif ($claimTried) {
                $parts += ("모델 {0}" -f $claimTried)
            }

            $bridgeSlot = if ($claim.PSObject.Properties['bridge_slot'] -and $claim.bridge_slot) { ([string]$claim.bridge_slot).Trim() } else { "" }
            if ($bridgeSlot) {
                $parts += ("부계정 슬롯 {0}" -f $bridgeSlot)
            }

            if ($workerAlive) {
                $probeState = if ($claim.PSObject.Properties['probe_state'] -and $claim.probe_state) { ([string]$claim.probe_state).Trim() } else { "" }
                if ($probeState) {
                    $parts += ("probe_state {0}" -f $probeState)
                }
                $actInfo = Get-SubmitTaskActivity $claim $AgyHome $Now
                if ($actInfo.LatestActivity) {
                    $parts += ("마지막 활동 {0}초 전({1})" -f $actInfo.AgoSeconds, $actInfo.Reason)
                } elseif ($actInfo.HasSource) {
                    $parts += "마지막 활동 기록 없음"
                } else {
                    $parts += "대화 시작 중"
                }
            }
        }

        if ($workerAlive) {
            return @{
                Line     = ("===STATUS=== {0} 실행 중 | {1}" -f $Id, ($parts -join " | "))
                ExitCode = 2
            }
        }
        return @{
            Line     = ("===STATUS=== {0} 작업자 사라짐(결과 없음) | {1}" -f $Id, ($parts -join " | "))
            ExitCode = 4
        }
    }

    $queued = @(Get-ChildItem -LiteralPath $Layout.InboxDir -File -ErrorAction SilentlyContinue |
        Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Id -and $_.Extension -in @('.md', '.txt') })
    if ($queued.Count -gt 0) {
        $queuedSec = [int][Math]::Max(0, ($Now - $queued[0].LastWriteTime).TotalSeconds)
        if (-not $CachedWatcherStatus.Value) {
            $CachedWatcherStatus.Value = Get-SubmitWatcherStatus
        }
        $wStatus = $CachedWatcherStatus.Value
        return @{
            Line     = ("===STATUS=== {0} 대기열 | 들어온 지 {1}초 | 워처 {2}" -f $Id, $queuedSec, $wStatus)
            ExitCode = 2
        }
    }

    return @{
        Line     = ("===STATUS=== {0} 없음" -f $Id)
        ExitCode = 0
    }
}

$script:CancelledPrefix = "취소됨(CANCELLED):"

# 모델 단계 설정(config\models.json)과 자동 선택 규칙. 대기 한도(-CancelOnTimeout 의 기본값)를 단계에서 읽는다.
# 시작 지연을 줄이려고 -Cancel 이 끝난 뒤(스크립트 스코프)에 agy-models.ps1 만 불러오고, agy-autotier/agy-rules 는 Get-BriefTierInfo 안에서만 불러온다.
$script:ModelsReady = $false
$script:CachedModelConfig = $null
function Get-SubmitModelConfig {
    if (-not $script:ModelsReady) { return $null }
    if ($null -eq $script:CachedModelConfig) {
        $script:CachedModelConfig = Get-AgyModelConfig
    }
    return $script:CachedModelConfig
}

# 지시문 맨 위 지시어(@model · @session · @cwd · @cmd · @mode)로 워처가 쓸 단계와 대기 한도를 짐작한다(워처와 같은 규칙).
# 반환: @{ Tier; Model; WaitSec; Cmd; Mode } (설정을 못 읽으면 $null)
function Get-BriefTierInfo([string]$Text, $CallerMeta = $null) {
    $cfg = Get-SubmitModelConfig
    if (-not $cfg) { return $null }
    try {
        $autoTierLib = Join-Path $PSScriptRoot "sub\agy-autotier.ps1"
        if (Test-Path -LiteralPath $autoTierLib -PathType Leaf) { . $autoTierLib }
        $rulesLibForSubmit = Join-Path $PSScriptRoot "sub\agy-rules.ps1"
        if (Test-Path -LiteralPath $rulesLibForSubmit -PathType Leaf) { . $rulesLibForSubmit }
    } catch {}
    $model = ""; $session = ""; $hasCwd = $false; $cmd = ""; $mode = ""; $body = [string]$Text
    while ($body.Length -gt 0) {
        $parts = $body -split "`r?`n", 2
        $line = $parts[0]
        if ($line -match '^\s*$') { }
        elseif ($line -match '^﻿?@model:\s*(.+)$') { $model = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@session:\s*(.+)$') { $session = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@cwd:\s*(.+)$') { $hasCwd = $true }
        elseif ($line -match '^﻿?@cmd:\s*(.+)$') { $cmd = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@mode:\s*(.+)$') { $mode = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@(raw|upgrade|reason):') { }
        else { break }
        $body = if ($parts.Length -gt 1) { $parts[1] } else { "" }
    }
    $cmdName = ""
    $cmdDisplay = ""
    if ($cmd -and (Get-Command Resolve-AgySlashCommand -ErrorAction SilentlyContinue)) {
        $cr = Resolve-AgySlashCommand $cmd
        if ($cr -and $cr.Valid) { $cmdName = [string]$cr.Name; $cmdDisplay = [string]$cr.Command }
    } elseif (-not $cmd -and (Get-Command Split-AgyLeadingSlashCommand -ErrorAction SilentlyContinue)) {
        $lc = Split-AgyLeadingSlashCommand $body
        if ($lc.Command) { $cmdName = [string]$lc.Name; $cmdDisplay = [string]$lc.Command; $body = [string]$lc.Body }
    }
    $modeName = ""
    if ($mode -and (Get-Command Resolve-AgyExecutionMode -ErrorAction SilentlyContinue)) {
        $mr = Resolve-AgyExecutionMode $mode
        if ($mr -and $mr.Valid) { $modeName = [string]$mr.Mode }
    }
    $writeTier = if ($cfg.Auto -and $cfg.Auto.write -and $cfg.Tiers.Contains([string]$cfg.Auto.write)) { [string]$cfg.Auto.write } else { "build" }
    $tier = ""
    $resolvedModel = ""
    $waitSec = 0
    $specKind = ""
    if ($model) {
        $spec = Resolve-AgyModelSpec $model $cfg
        if ($spec) { $specKind = [string]$spec.Kind }
        if ($spec -and $spec.Kind -eq "tier") { $tier = [string]$spec.Tier }
        elseif ($spec -and $spec.Kind -eq "model") {
            $tier = [string]$spec.Tier
            $resolvedModel = [string]$spec.Model
            $waitSec = if ($spec.WaitSec -gt 0) { [int]$spec.WaitSec } else { [int]$cfg.Tiers[$writeTier].WaitSec }
        }
    }
    if (-not $resolvedModel) {
        if (-not $tier) {
            if (-not $session -and (Get-Command Get-AgyAutoTier -ErrorAction SilentlyContinue) -and (Test-AgyAutoTierEnabled)) {
                try { $tier = [string](Get-AgyAutoTier $body $hasCwd).Tier } catch { $tier = "" }
            }
            if (-not $tier -or -not $cfg.Tiers.Contains($tier)) { $tier = $writeTier }
        }
        $resolvedModel = [string]$cfg.Tiers[$tier].Model
        $waitSec = [int]$cfg.Tiers[$tier].WaitSec
    }
    if (-not $session -and $specKind -ne "model" -and (Get-Command Resolve-AgyCallerSameLevelSpec -ErrorAction SilentlyContinue)) {
        $matched = Resolve-AgyCallerSameLevelSpec $cfg @() $CallerMeta $model $tier $specKind
        if ($matched) {
            $tier = [string]$matched.Tier
            $resolvedModel = [string]$matched.Model
            $waitSec = [int]$matched.WaitSec
        }
    }
    if ($cmdName -in @('swarm', 'run-workflow', 'boost')) {
        $waitSec = [Math]::Max($waitSec, 1200)
    }
    return @{ Tier = $tier; Model = $resolvedModel; WaitSec = $waitSec; Cmd = $cmdDisplay; Mode = $modeName }
}

# 작업 하나의 대기 한도(초). 실행 표시 파일의 단계(워처가 정한 것) > inbox/processed 지시문에서 짐작한 단계 > 0(모름)
function Get-TaskWaitSec([string]$Id, [bool]$AllowProcessedFallback = $true) {
    $cfg = Get-SubmitModelConfig
    if (-not $cfg) { return 0 }
    try {
        $layout = Get-AgyLayout $script:RuntimeDirResolved
        $claimPath = Join-Path $layout.RunningDir "$Id.json"
        $claim = Read-SubmitClaimJson $claimPath
        if ($claim) {
            $t = [string]$claim.tier
            if ($t -and $cfg.Tiers.Contains($t)) { return [int]$cfg.Tiers[$t].WaitSec }
        }
        $callerMeta = $null
        try {
            $cmPath = Join-Path (Join-Path $script:RuntimeDirResolved "claude-meta") "$Id.json"
            if (Test-Path -LiteralPath $cmPath -PathType Leaf) {
                $callerMeta = (Read-TextFile $cmPath) | ConvertFrom-Json
            }
        } catch {}
        $searchDirs = @((Join-Path $script:RuntimeDirResolved "inbox"))
        if ($AllowProcessedFallback -and $layout.ProcessedDir) { $searchDirs += $layout.ProcessedDir }
        foreach ($dirPath in $searchDirs) {
            if (-not $dirPath) { continue }
            foreach ($ext in @(".md", ".txt")) {
                $brief = Join-Path $dirPath "$Id$ext"
                if (Test-Path -LiteralPath $brief -PathType Leaf) {
                    $info = Get-BriefTierInfo (Read-TextFile $brief) $callerMeta
                    if ($info) { return [int]$info.WaitSec }
                }
            }
        }
    } catch {}
    return 0
}

function Read-AntigravityTranscriptLastModel([string]$TranscriptPath) {
    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) { return "" }
    foreach ($tailBytes in @(65536L, 524288L, 2097152L)) {
        $rawText = ""
        $fs = $null
        try {
            $fs = [System.IO.File]::Open($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $len = $fs.Length
            $readBytes = [Math]::Min($len, $tailBytes)
            if ($readBytes -le 0) { return "" }
            [void]$fs.Seek($len - $readBytes, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $readBytes
            $readTotal = 0
            while ($readTotal -lt $readBytes) {
                $n = $fs.Read($buf, $readTotal, $readBytes - $readTotal)
                if ($n -le 0) { break }
                $readTotal += $n
            }
            $rawText = [System.Text.Encoding]::UTF8.GetString($buf, 0, $readTotal)
        } catch {
            return ""
        } finally {
            if ($fs) { $fs.Dispose() }
        }
        $lines = $rawText -split "[\r\n]+"
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $ln = $lines[$i]
            if (-not $ln -or $ln.IndexOf('"PLANNER_RESPONSE"', [System.StringComparison]::Ordinal) -lt 0) { continue }
            if ($ln.IndexOf('"model"', [System.StringComparison]::Ordinal) -lt 0) { continue }
            $t = $ln.TrimStart([char]0xFEFF).Trim()
            try {
                $parsed = ConvertFrom-Json -InputObject $t -ErrorAction Stop
                if ($parsed -and [string]$parsed.type -eq 'PLANNER_RESPONSE' -and $parsed.PSObject.Properties['model'] -and $parsed.model) {
                    return ([string]$parsed.model).Trim()
                }
                continue
            } catch {}
            $head = $t
            foreach ($cutKey in @('"thinking":', '"content":', '"tool_calls":')) {
                $idx = $head.IndexOf($cutKey, [System.StringComparison]::Ordinal)
                if ($idx -gt 0) { $head = $head.Substring(0, $idx) }
            }
            if ($head -match '"type"\s*:\s*"PLANNER_RESPONSE"' -and $head -match '"model"\s*:\s*"([^"]+)"') {
                return $Matches[1].Trim()
            }
        }
    }
    return ""
}

function Get-AntigravityCallerMeta {
    $convId = [string]$env:ANTIGRAVITY_CONVERSATION_ID
    if (-not $convId -and $env:ANTIGRAVITY_SOURCE_METADATA) {
        try {
            $sm = ConvertFrom-Json -InputObject ([string]$env:ANTIGRAVITY_SOURCE_METADATA) -ErrorAction Stop
            if ($sm -and $sm.tool -and $sm.tool.conversationId) { $convId = [string]$sm.tool.conversationId }
        } catch {}
    }
    $convId = $convId.Trim()
    $validConv = ($convId -match '^[A-Za-z0-9-]{8,80}$')
    if (($env:ANTIGRAVITY_AGENT -ne '1') -and -not $validConv) { return $null }

    $foundModel = ""
    $rootConvId = ""
    $rootModel  = ""
    if ($validConv) {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $roots = New-Object System.Collections.ArrayList
        foreach ($cand in @($env:ANTIGRAVITY_APP_DATA_DIR, $env:AGY_HOME, (Join-Path $homeDir ".gemini\antigravity"), (Join-Path $homeDir ".gemini\antigravity-cli"))) {
            if ($cand -and -not ($roots -contains $cand)) { [void]$roots.Add($cand) }
        }
        $matchedRoot = ""
        foreach ($root in $roots) {
            $logDir = Join-Path $root ("brain\{0}\.system_generated\logs" -f $convId)
            if (-not (Test-Path -LiteralPath $logDir -PathType Container)) { continue }
            $matchedRoot = $root
            foreach ($leaf in @("transcript.jsonl", "transcript_full.jsonl")) {
                $m = Read-AntigravityTranscriptLastModel (Join-Path $logDir $leaf)
                if ($m) { $foundModel = $m; break }
            }
            if ($foundModel) { break }
        }

        # 서브에이전트 여부 및 루트 부모 대화 ID 확인
        $dbRoots = if ($matchedRoot) { @($matchedRoot) } else { @($roots) }
        foreach ($root in $dbRoots) {
            $sumDb = Join-Path $root "conversation_summaries.db"
            if (-not (Test-Path -LiteralPath $sumDb -PathType Leaf)) { continue }
            try {
                if (-not (Get-Command Open-AgyDbReadOnly -ErrorAction SilentlyContinue)) {
                    $dbLib = Join-Path $PSScriptRoot "sub\agy-db.ps1"
                    if (Test-Path -LiteralPath $dbLib -PathType Leaf) { . $dbLib }
                }
                if (Get-Command Open-AgyDbReadOnly -ErrorAction SilentlyContinue) {
                    $db = Open-AgyDbReadOnly $sumDb 1000
                    try {
                        $cur = $convId
                        $seen = @{ $cur = $true }
                        for ($hop = 0; $hop -lt 10; $hop++) {
                            $rows = @($db.Query("SELECT parent_conversation_id FROM conversation_summaries WHERE conversation_id = ?", @($cur)))
                            $parent = ""
                            if ($rows.Count -gt 0 -and $rows[0]["parent_conversation_id"]) {
                                $parent = ([string]$rows[0]["parent_conversation_id"]).Trim()
                            }
                            if (-not $parent) {
                                $pRows = @($db.Query("SELECT parent_id FROM conversation_parents WHERE conversation_id = ?", @($cur)))
                                if ($pRows.Count -gt 0 -and $pRows[0]["parent_id"]) {
                                    $parent = ([string]$pRows[0]["parent_id"]).Trim()
                                }
                            }
                            if (-not $parent -or $seen.ContainsKey($parent)) { break }
                            $seen[$parent] = $true
                            $cur = $parent
                        }
                        if ($cur -ne $convId) { $rootConvId = $cur }
                    } finally {
                        $db.Dispose()
                    }
                }
            } catch {}
            if ($rootConvId) { break }
        }

        if ($rootConvId) {
            foreach ($root in $dbRoots) {
                $rLogDir = Join-Path $root ("brain\{0}\.system_generated\logs" -f $rootConvId)
                if (-not (Test-Path -LiteralPath $rLogDir -PathType Container)) { continue }
                foreach ($leaf in @("transcript.jsonl", "transcript_full.jsonl")) {
                    $rm = Read-AntigravityTranscriptLastModel (Join-Path $rLogDir $leaf)
                    if ($rm) { $rootModel = $rm; break }
                }
                if ($rootModel) { break }
            }
        }
    }
    return @{
        client      = "antigravity"
        model       = $(if ($rootConvId) { $rootModel } else { $foundModel })
        agent_model = $(if ($rootConvId) { $foundModel } else { "" })
        session     = $(if ($rootConvId) { $rootConvId } elseif ($validConv) { $convId } else { "" })
    }
}

# 지시문 맨 위 "@키: 값" 줄들 가운데 "@reason: <사유>" 를 떼어 낸다. 사유는 통계용 기록(claude-meta)에만 남기고 agy 에는 보내지 않는다.
# 돌려주는 값: @{ Text = <@reason 줄을 뺀 지시문>; Reason = <사유(없으면 "")> }. @reason 줄이 없으면 지시문은 한 글자도 바뀌지 않는다.
function Split-TaskReason([string]$Text) {
    $parts = [regex]::Split([string]$Text, '(?<=\n)')
    $kept = New-Object System.Collections.ArrayList
    $reason = ""
    $inHeader = $true
    foreach ($part in $parts) {
        if ($inHeader) {
            $m = [regex]::Match($part, '^\ufeff?\s*@([A-Za-z]+)\s*:(.*)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if (-not $m.Success) { $inHeader = $false }
            elseif ($m.Groups[1].Value -ieq 'reason') {
                if (-not $reason) { $reason = (($m.Groups[2].Value -replace '\s+', ' ').Trim()) }
                continue
            }
        }
        [void]$kept.Add($part)
    }
    if ($reason.Length -gt 200) { $reason = $reason.Substring(0, 200) }
    return @{ Text = ($kept -join ''); Reason = $reason }
}

# 지시문 앞의 "@키: 값" 줄(@cwd · @model 등)을 빼고 질문 본문만 남긴다(취소 기록의 질문 칸용).
function Get-TaskBodyText([string]$Text) {
    $lines = @(([string]$Text) -split "`r?`n")
    $i = 0
    while ($i -lt $lines.Count -and $lines[$i] -match '^\s*@[A-Za-z]+\s*:') { $i++ }
    if ($i -ge $lines.Count) { return "" }
    return (($lines[$i..($lines.Count - 1)]) -join "`n").Trim()
}

# 취소를 마무리한다: 응답 파일(취소 사유)을 쓰고, 지시 파일이 inbox 에 남아 있으면 processed 로 옮기고, 실행 표시를 지우고, 기록(DB)에 CANCELLED 로 남긴다.
function Complete-CancelledTask([string]$Id, [string]$Reason, $Claim = $null) {
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $message = "$script:CancelledPrefix $Reason"
    $outFile = Join-Path $script:OutboxDir "$Id.response.md"
    $taskText = ""
    $claimPath = Join-Path $layout.RunningDir "$Id.json"
    if ($null -eq $Claim) {
        $Claim = Read-SubmitClaimJson $claimPath
    }
    foreach ($ext in @(".md", ".txt")) {
        $cand = Join-Path $inboxDir ($Id + $ext)
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            try { $taskText = Read-TextFile $cand } catch {}
            try {
                New-Item -ItemType Directory -Force -Path $layout.ProcessedDir | Out-Null
                Move-Item -LiteralPath $cand -Destination (Join-Path $layout.ProcessedDir ($Id + $ext)) -Force
            } catch { Remove-Item -LiteralPath $cand -Force -ErrorAction SilentlyContinue }
        }
    }
    if (-not $taskText) {
        $proc = Join-Path $layout.ProcessedDir "$Id.md"
        if (-not (Test-Path -LiteralPath $proc)) { $proc = Join-Path $layout.ProcessedDir "$Id.txt" }
        if (Test-Path -LiteralPath $proc -PathType Leaf) { try { $taskText = Read-TextFile $proc } catch {} }
    }
    $existing = $false
    if ((Test-Path -LiteralPath $outFile -PathType Leaf) -and ((Get-Item -LiteralPath $outFile).Length -gt 0)) { $existing = $true }
    Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $layout.RunningDir "$Id.cancel") -Force -ErrorAction SilentlyContinue
    # 응답 파일이 이미 있으면 워처가 취소를 마무리하고 기록(DB)까지 남긴 것이므로 덮어쓰지 않는다.
    if ($existing) { return }

    $session = if ($Claim -and $Claim.session) { [string]$Claim.session } else { "" }
    $model = if ($Claim -and $Claim.model) { [string]$Claim.model } else { "" }
    $triedModels = if ($Claim -and $Claim.tried) { [string]$Claim.tried } else { "" }
    $convId = if ($Claim -and $Claim.conversation_id) { [string]$Claim.conversation_id } else { "" }
    $startedDt = $null
    $elapsedSec = ""
    $startText = if ($Claim -and $Claim.started_at) { [string]$Claim.started_at } elseif ($Claim -and $Claim.started) { [string]$Claim.started } else { "" }
    if ($startText) {
        $parsedStart = [datetime]::MinValue
        if ([datetime]::TryParse($startText, [ref]$parsedStart)) {
            $startedDt = $parsedStart
            $elapsedSec = [string][math]::Round([math]::Max(0.0, ((Get-Date) - $parsedStart).TotalSeconds), 1)
        }
    }

    $answer = $message
    $processSteps = $null
    $bridgeTrCancel = if ($Claim -and $Claim.PSObject.Properties['bridge_transcript'] -and $Claim.bridge_transcript) { [string]$Claim.bridge_transcript } else { "" }
    $hasBridgeTrCancel = [bool]($bridgeTrCancel -and (Test-Path -LiteralPath $bridgeTrCancel -PathType Leaf))
    if ($convId -or $hasBridgeTrCancel) {
        try {
            if (-not (Get-Command Get-AgyCancelledWorkText -ErrorAction SilentlyContinue)) {
                $pLib = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
                if (Test-Path -LiteralPath $pLib) { . $pLib }
            }
            $agyHomeDir = Get-AgyHomeDir
            $workText = Get-AgyCancelledWorkText $agyHomeDir $convId $startedDt $bridgeTrCancel
            if ($workText) { $answer = $message + "`n`n" + $workText }
            $tPath = if ($hasBridgeTrCancel) { $bridgeTrCancel } else { Get-AgyTranscriptPath $agyHomeDir $convId }
            if ($tPath -and (Test-Path -LiteralPath $tPath -PathType Leaf)) {
                $since = if ($session -and $startedDt) { $startedDt.AddSeconds(-5) } else { $null }
                $processSteps = @((Read-AgyProcessSteps $tPath 0 1500 500 300 $since).Steps)
            }
        } catch {}
    }

    New-Item -ItemType Directory -Force -Path $script:OutboxDir | Out-Null
    [System.IO.File]::WriteAllText($outFile, $answer, $utf8)

    try {
        . (Join-Path $PSScriptRoot "sub\agy-db.ps1")
        $claimAcct = if ($Claim -and $Claim.PSObject.Properties['account'] -and $Claim.account) { [string]$Claim.account } else { "primary" }
        $claimFb   = if ($Claim -and $Claim.PSObject.Properties['fallback_from'] -and $Claim.fallback_from) { [string]$Claim.fallback_from } else { "" }
        $rec = [ordered]@{
            timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            computer_name = [string]$env:COMPUTERNAME
            task_id       = $Id
            model         = $model
            tried_models  = $triedModels
            elapsed_sec   = $elapsedSec
            status        = "CANCELLED"
            session       = $session
            session_id    = $convId
            account       = $claimAcct
            fallback_from = $claimFb
            question      = (Get-TaskBodyText $taskText)
            answer        = $answer
            process       = $processSteps
        }
        [void](Write-QaRecordToDb $layout.DbPath $rec 'Upsert')
    } catch {}
}

# 작업 하나를 취소한다. 돌려주는 값: cancelled | done(이미 끝남) | notfound
function Invoke-CancelTask([string]$Id, [string]$Reason) {
    if (Test-TaskDone $Id) { return "done" }
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $claimPath = Join-Path $layout.RunningDir "$Id.json"
    for ($round = 0; $round -lt 2; $round++) {
        $claim = Read-SubmitClaimJson $claimPath
        $claimPid = 0
        if ($claim) { try { $claimPid = [int]$claim.pid } catch { $claimPid = 0 } }
        $bridgeSlot = if ($claim -and $claim.PSObject.Properties['bridge_slot'] -and $claim.bridge_slot) { [string]$claim.bridge_slot } else { "" }
        $matchedSubSlots = @()
        try {
            $subBridgeLib = Join-Path $PSScriptRoot "sub\agy-sub-bridge.ps1"
            if (Test-Path -LiteralPath $subBridgeLib -PathType Leaf) {
                . $subBridgeLib
                $subCfgObj = $null
                try {
                    $mLib = Join-Path $PSScriptRoot "sub\agy-models.ps1"
                    if (Test-Path -LiteralPath $mLib -PathType Leaf) {
                        . $mLib
                        $subCfgObj = (Get-AgyModelConfig).SubAccounts
                    }
                } catch {}
                if ($bridgeSlot) {
                    $matchedSubSlots = @($bridgeSlot)
                } elseif ($subCfgObj -and $subCfgObj.Enabled -and $subCfgObj.Slots) {
                    $brRootScan = Get-AgySubBridgeRoot $subCfgObj
                    foreach ($sObj in @($subCfgObj.Slots)) {
                        $sidScan = ([string]$sObj.Id).Trim()
                        if (-not $sidScan) { continue }
                        $layScan = Get-AgySubSlotLayout $brRootScan $sidScan
                        if ((Test-Path -LiteralPath (Join-Path $layScan.RunningDir "$Id.json") -PathType Leaf) -or
                            (Test-Path -LiteralPath (Join-Path $layScan.InboxDir "$Id.task.json") -PathType Leaf)) {
                            $matchedSubSlots += $sidScan
                        }
                    }
                }
            }
        } catch {}
        if ($claimPid -gt 0 -or $bridgeSlot -or $matchedSubSlots.Count -gt 0) {
            # 실행 중: 워처가 "취소" 로 마무리하도록 표시를 남기고, 부계정 브리지 슬롯이면 해당 슬롯에도 .cancel 을 전파한다.
            [System.IO.File]::WriteAllText((Join-Path $layout.RunningDir "$Id.cancel"), $Reason, $utf8)
            if ($matchedSubSlots.Count -gt 0) {
                try {
                    $brRoot = Get-AgySubBridgeRoot $subCfgObj
                    foreach ($targetSlot in $matchedSubSlots) {
                        $brLay = Get-AgySubSlotLayout $brRoot $targetSlot
                        New-Item -ItemType Directory -Force -Path $brLay.RunningDir | Out-Null
                        [System.IO.File]::WriteAllText((Join-Path $brLay.RunningDir "$Id.cancel"), $Reason, $utf8)
                    }
                } catch {}
                # 부계정 워처 및 주 중계 루프가 CANCELLED 결과와 account 를 보존해 마무리하도록 잠깐 대기
                Wait-SubmitTaskDoneGrace $Id 250 8000
                if (Test-TaskDone $Id) { return "cancelled" }
            }
            if ($claimPid -gt 0) {
                $proc = Get-Process -Id $claimPid -ErrorAction SilentlyContinue
                if ($proc -and $proc.ProcessName -eq "powershell") {
                    try { & taskkill.exe /PID $claimPid /T /F 2>&1 | Out-Null } catch {}
                }
            }
            # 워처가 살아 있으면 곧 표시를 보고 응답 · 기록을 남긴다. 잠시 기다려 보고, 안 되면(워처가 꺼져 있음) 여기서 마무리한다.
            Wait-SubmitTaskDoneGrace $Id 500 10000
            Complete-CancelledTask $Id $Reason $claim
            return "cancelled"
        }
        # 대기 중: 지시 파일을 치운다(워처가 그 사이 가져갔으면 다시 확인한다)
        $queued = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Id })
        if ($queued.Count -gt 0) {
            if (-not $claim) {
                Complete-CancelledTask $Id $Reason
                return "cancelled"
            }
            Start-SubmitPollSleep 700   # 워처가 막 시작하는 중(실행 표시는 있고 PID 는 아직 0): 잠깐 뒤 다시 본다
            continue
        }
        if (-not $claim) { break }
        Start-SubmitPollSleep 700
    }
    if (Test-TaskDone $Id) { return "done" }
    return "notfound"
}

<#
.SYNOPSIS
위임 제출 · 폴링 · 취소 본체를 실행합니다. dot-source 시 단위 테스트에서 직접 호출할 수 있습니다.
#>
function Invoke-SubmitTask {
    param(
        [string]$File = "",
        [string[]]$Poll = @(),
        [string[]]$Cancel = @(),
        [string[]]$Status = @(),
        [switch]$NoWait,
        [int]$WaitSeconds = 170,
        [int]$MaxWaitSec = 0,
        [switch]$CancelOnTimeout,
        [string]$RuntimeDir = "",
        [switch]$ExplicitWaitSeconds
    )

    $script:InProcSubmit = ($env:AGY_TEST_INPROC -eq "1")
    $script:LastSubmitExitCode = 0
    $script:SubmitErrBuf = New-Object 'System.Collections.Generic.List[string]'
    $script:ModelsReady = $false
    $script:CachedModelConfig = $null
    $script:SubmittedRecoverTried = $false
    $script:SubmittedTaskId = $null
    $script:RuntimeDirResolved = $null
    $script:OutboxDir = $null

    try {
$script:RuntimeDirResolved = Resolve-RuntimeDirForSubmit $RuntimeDir
if (-not $script:RuntimeDirResolved) { Stop-WithCode 3 "위임 런타임 폴더(~/.samjil/delegate-agy/runtime)를 찾지 못했습니다. install.ps1 로 설치돼 있는지 확인하세요." }
$script:OutboxDir = (Get-AgyLayout $script:RuntimeDirResolved).OutboxDir
$inboxDir = Join-Path $script:RuntimeDirResolved "inbox"

# -Status: 기다리지도 취소하지도 않고 지금 상태만 한 줄씩 출력하고 끝낸다(읽기 전용)
$statusIds = @()
foreach ($p in @($Status)) { foreach ($x in ([string]$p -split '[,\s]+')) { if ($x) { $statusIds += $x } } }
foreach ($id in $statusIds) { if ($id -notmatch '^[A-Za-z0-9_-]{1,80}$') { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: $id" } }
if (@($Status).Count -gt 0 -and $statusIds.Count -eq 0) { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: (비어 있음)" }
if ($statusIds.Count -gt 0) {
    $progressLib = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
    if (-not (Get-Command Get-AgyConversationActivity -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $progressLib -PathType Leaf)) {
        . $progressLib
    }
    $statusLayout = Get-AgyLayout $script:RuntimeDirResolved
    $statusAgyHome = if (Get-Command Get-AgyHomeDir -ErrorAction SilentlyContinue) { Get-AgyHomeDir } elseif ($env:AGY_HOME) { $env:AGY_HOME } else { (Join-Path $env:USERPROFILE ".gemini\antigravity-cli") }
    $statusNow = Get-Date
    $cachedWatcherStatus = ""
    $statusExit = 0
    foreach ($id in $statusIds) {
        $entry = Get-SubmitTaskStatusEntry $id $statusLayout $statusAgyHome $statusNow ([ref]$cachedWatcherStatus)
        Write-Output $entry.Line
        if ($entry.ExitCode -gt $statusExit) { $statusExit = [int]$entry.ExitCode }
    }
    $script:LastSubmitExitCode = $statusExit
    return
}

# 기다릴 작업 ID 들
$ids = @()
foreach ($p in @($Poll)) { foreach ($x in ([string]$p -split '[,\s]+')) { if ($x) { $ids += $x } } }
foreach ($id in $ids) { if ($id -notmatch '^[A-Za-z0-9_-]{1,80}$') { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: $id" } }

# -Cancel: 작업(들)을 취소하고 끝낸다
$cancelIds = @()
foreach ($p in @($Cancel)) { foreach ($x in ([string]$p -split '[,\s]+')) { if ($x) { $cancelIds += $x } } }
foreach ($id in $cancelIds) { if ($id -notmatch '^[A-Za-z0-9_-]{1,80}$') { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: $id" } }
if ($cancelIds.Count -gt 0) {
    $cancelExit = 0
    foreach ($id in $cancelIds) {
        $res = Invoke-CancelTask $id "사용자 요청으로 취소했습니다."
        switch ($res) {
            "cancelled" { Write-Output "===CANCELLED=== $id" }
            "done"      { Write-Output "===DONE=== $id"; Write-Output "이미 끝나 있어 취소하지 않았습니다. 결과는 -Poll 로 읽으세요." }
            default     { Write-Output "===NOTFOUND=== $id"; Write-Output "대기열에도 실행 목록에도 없습니다. 작업 ID 를 확인하세요."; $cancelExit = 1 }
        }
    }
    $script:LastSubmitExitCode = $cancelExit
    return
}

try {
    . (Join-Path $PSScriptRoot "sub\agy-models.ps1")
    $script:ModelsReady = $true
} catch {}

if ($ids.Count -eq 0) {
    # 새로 넣기
    $text = $null
    if ($File) {
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { Stop-WithCode 3 "지시문 파일이 없습니다: $File" }
        $text = Read-TextFile $File
    } elseif ($script:InProcSubmit -and (Test-Path Env:\AGY_TEST_STDIN_TEXT)) {
        $text = ([string]$env:AGY_TEST_STDIN_TEXT).TrimStart([char]0xFEFF)
    } elseif ([Console]::IsInputRedirected) {
        $text = (Read-AllStdin).TrimStart([char]0xFEFF)
    }
    if (-not $text -or -not $text.Trim()) { Stop-WithCode 3 "지시문이 비었습니다. 표준입력(heredoc)이나 -File 로 지시문을 주세요." }
    if ($Model -or @($Cwd).Count -gt 0) {
        $hasHeaderCwd = $false
        $hasHeaderModel = $false
        foreach ($hLine in @($text -split "`r?`n")) {
            if ($hLine -match '^\s*$') { continue }
            if ($hLine -match '^﻿?@cwd\s*:') { $hasHeaderCwd = $true; continue }
            if ($hLine -match '^﻿?@model\s*:') { $hasHeaderModel = $true; continue }
            if ($hLine -match '^﻿?@[A-Za-z]+\s*:') { continue }
            break
        }
        $prependLines = New-Object System.Collections.ArrayList
        if (-not $hasHeaderCwd) {
            foreach ($cDir in @($Cwd)) {
                if ($cDir -and $cDir.Trim()) { [void]$prependLines.Add("@cwd: $($cDir.Trim())") }
            }
        }
        if ($Model -and $Model.Trim() -and -not $hasHeaderModel) {
            [void]$prependLines.Add("@model: $($Model.Trim())")
        }
        if ($prependLines.Count -gt 0) {
            $text = ($prependLines -join "`n") + "`n" + $text.TrimStart([char]0xFEFF)
        }
    }
    # "@reason: <사유>" 줄은 기록용이다: 떼어 두었다가 claude-meta 에 남기고, agy 에 보내는 지시문에는 넣지 않는다.
    $taskReason = ""
    $split = Split-TaskReason $text
    if ($split.Reason) { $taskReason = $split.Reason; $text = $split.Text }
    if (-not $text.Trim()) { Stop-WithCode 3 "지시문이 비었습니다. @reason 줄 말고 지시문 본문을 주세요." }
    # 새 버전 업데이트 관문: 캐시만 확인(네트워크 없음), 같은 버전에 24시간 1회만 제출 보류(AGY_SKIP_UPDATE_GATE=1 로 건너뜀)
    if ($env:AGY_SKIP_UPDATE_GATE -ne "1") {
        $updateGate = $null
        try {
            $updateLib = Join-Path $PSScriptRoot "sub\update-check.ps1"
            if (Test-Path -LiteralPath $updateLib -PathType Leaf) {
                . $updateLib
                Start-SamjilUpdateFetchBackground
                $updateGate = Test-SamjilSubmitUpdateGate
            }
        } catch {
            $updateGate = $null
        }
        if ($null -ne $updateGate) {
            Write-Output "===UPDATE_AVAILABLE==="
            Write-Output ("설치본 {0} · 최신 {1}" -f $updateGate.Installed, $updateGate.Latest)
            Write-Output "업데이트: PowerShell 에서 irm https://raw.githubusercontent.com/samjil/agy-agent/main/install.ps1 | iex  (또는 뷰어 http://127.0.0.1:8787 의 업데이트 버튼)"
            Write-Output "이 안내는 같은 버전에 24시간에 한 번만 나옵니다. 업데이트하지 않고 진행하려면 같은 위임을 다시 보내세요."
            $script:LastSubmitExitCode = 5
            return
        }
    }
    # 브리프 점검(경고만): 검증 방법·범위 제한·대상 파일이 빠졌거나 너무 길면 보내기 전에 알린다. 위임은 그대로 진행한다. AGY_BRIEF_LINT=off 로 끈다.
    try {
        $lintLib = Join-Path $PSScriptRoot "sub\agy-brief-lint.ps1"
        if (Test-Path -LiteralPath $lintLib) {
            . $lintLib
            if (Test-AgyBriefLintEnabled) {
                $briefWarnings = @(Get-AgyBriefWarnings $text)
                $isKorean = ((Get-AgyReplyLanguage) -eq "Korean")
                $prefix = if ($isKorean) { "[브리프 점검] " } else { "[Brief check] " }
                $tail = if ($isKorean) {
                    "[브리프 점검] 위 항목은 경고일 뿐이라 위임은 그대로 진행합니다. 다음 위임부터 반영하거나, 빠진 것을 바로 채워 다시 보내려면 이 작업을 취소하세요."
                } else {
                    "[Brief check] These are warnings only; the task was submitted. Fix them next time, or cancel this task and resend with the missing parts."
                }
                foreach ($bw in $briefWarnings) { Write-SubmitErrorLine ($prefix + $bw) }
                if ($briefWarnings.Count -gt 0) { Write-SubmitErrorLine $tail }
            }
        }
    } catch {}
    $id = "claude_{0}_{1}" -f ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()), (Get-Random -Minimum 0 -Maximum 32768)
    # 이 위임을 보낸 Claude 모델·effort 정보를 기억한다(뷰어 진행 중 카드 및 방금 끝난 카드 표시용).
    # 같은 대화 기록 끝에서 컨텍스트 크기도 읽어, 크면 위임 절차(제출 · 대기 · 검토)를 서브에이전트에 맡기라고 알린다.
    $metaObj = [ordered]@{}
    try {
        $sessId = $env:CLAUDE_CODE_SESSION_ID
        if ($sessId) {
            $transcriptLib = Join-Path $PSScriptRoot "sub\claude-transcript.ps1"
            if (Test-Path -LiteralPath $transcriptLib) {
                . $transcriptLib
                $mainTranscriptPath = Resolve-ClaudeTranscriptPath -SessionId $sessId
                $lastUsage = if ($mainTranscriptPath) { Get-ClaudeTranscriptLastUsage -TranscriptPath $mainTranscriptPath } else { $null }
                $subAgent = if ($mainTranscriptPath) { Find-ClaudeSubmittingSubagent -MainTranscriptPath $mainTranscriptPath } else { $null }
                $ctxThreshold = 200000
                if ($env:AGY_CTX_SUBAGENT_THRESHOLD -match '^\d+$') { $ctxThreshold = [int]$env:AGY_CTX_SUBAGENT_THRESHOLD }
                # 서브에이전트가 제출한 경우에는 본 세션이 아니라 서브에이전트 자신의 컨텍스트 크기로 판단한다.
                $effectiveCtx = if ($subAgent) { [long]$subAgent.ctx } elseif ($lastUsage -and $lastUsage.ctx) { [long]$lastUsage.ctx } else { 0L }
                if ($effectiveCtx -gt $ctxThreshold) {
                    # 이미 제출한 뒤라, 지금 할 수 있는 일(남은 대기 · 검토를 넘기기)을 알린다. 다음 위임부터는 질문 시점의 훅 알림을 보고 처음부터 서브에이전트에 맡긴다.
                    Write-SubmitErrorLine ("[컨텍스트 {0}k] 컨텍스트가 큽니다(기준 {1}k). 제출은 됐으니 이 작업의 대기 · diff 검토 · 시험은 본 세션에서 하지 말고, 서브에이전트 하나(저렴한 모델)에 아래 작업 ID 와 확인할 시험 명령을 넘겨 맡긴 뒤 5줄 보고만 받으세요(본 세션은 호출마다 대화 전체를 다시 읽습니다)." -f [int][math]::Round($effectiveCtx / 1000.0), [int]($ctxThreshold / 1000))
                }
                if ($lastUsage -and $lastUsage.model) {
                    $metaObj['model'] = $lastUsage.model
                    $metaObj['effort'] = $lastUsage.effort
                    $metaObj['session'] = $sessId
                }
                if ($subAgent) {
                    if ($subAgent.model)  { $metaObj['agent_model']  = [string]$subAgent.model }
                    if ($subAgent.effort) { $metaObj['agent_effort'] = [string]$subAgent.effort }
                    if ($subAgent.id)     { $metaObj['agent_id']     = [string]$subAgent.id }
                    if ($subAgent.type)   { $metaObj['agent_type']   = [string]$subAgent.type }
                    if ($subAgent.desc)   { $metaObj['agent_desc']   = [string]$subAgent.desc }
                    if (-not $metaObj.Contains('session')) { $metaObj['session'] = $sessId }
                }
            }
        } else {
            $agMeta = Get-AntigravityCallerMeta
            if ($agMeta) {
                $metaObj['src_client'] = [string]$agMeta.client
                if ($agMeta.model)       { $metaObj['src_model']   = [string]$agMeta.model }
                if ($agMeta.agent_model) { $metaObj['agent_model'] = [string]$agMeta.agent_model }
                if ($agMeta.session)     { $metaObj['src_session'] = [string]$agMeta.session }
            }
        }
    } catch {}
    # 메타 파일: Claude 모델을 알았거나 사유(@reason)가 있을 때 남긴다. 사유는 실측 통계가 나중에 읽으므로 통계 보관 기간(90일)만큼 둔다.
    try {
        if ($taskReason) { $metaObj['reason'] = $taskReason }
        $taskCwdsMeta = @(Get-TaskCwdsFromText $text)
        if ($taskCwdsMeta.Count -gt 0) { $metaObj['cwd'] = @($taskCwdsMeta) }
        if ($metaObj.Count -gt 0) {
            $metaDir = Join-Path $script:RuntimeDirResolved "claude-meta"
            if (-not (Test-Path -LiteralPath $metaDir -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $metaDir | Out-Null
            }
            $metaPath = Join-Path $metaDir "$id.json"
            [System.IO.File]::WriteAllText($metaPath, ($metaObj | ConvertTo-Json -Compress), $utf8)

            $cutoff = (Get-Date).AddDays(-90)
            Get-ChildItem -LiteralPath $metaDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    # 쓰는 도중의 파일을 워처가 읽지 않게 임시 이름으로 쓰고 바꿔치기한다(.tmp 는 워처가 보지 않는다)
    $tmp = Join-Path $inboxDir "$id.md.tmp"
    $taskFilePath = Join-Path $inboxDir "$id.md"
    [System.IO.File]::WriteAllText($tmp, $text, $utf8)
    Move-Item -LiteralPath $tmp -Destination $taskFilePath
    Write-Output "submitted: $id"
    try {
        $tierInfo = Get-BriefTierInfo $text $metaObj
        if ($tierInfo) {
            $extraInfo = ""
            if ($tierInfo.Cmd) { $extraInfo += " · 명령 $($tierInfo.Cmd)" }
            if ($tierInfo.Mode) { $extraInfo += " · 모드 $($tierInfo.Mode)" }
            Write-SubmitErrorLine ("[단계] {0} ({1}){2} · 대기 한도 {3}초(-CancelOnTimeout 의 기본값)" -f $(if ($tierInfo.Tier) { $tierInfo.Tier } else { "모델 지정" }), $tierInfo.Model, $extraInfo, $tierInfo.WaitSec)
        }
    } catch {}
    $script:SubmittedRecoverTried = $false
    try {
        $submitEnsureRes = Ensure-SubmitWatcherOrDirectWorker $id $taskFilePath
        if ($submitEnsureRes -and $submitEnsureRes.Mode -ne "alive") { $script:SubmittedRecoverTried = $true }
    } catch {}
    if ($NoWait) { $script:LastSubmitExitCode = 0; return }
    $script:SubmittedTaskId = $id
    $ids = @($id)
}

# 기다리기: -MaxWaitSec 가 주어지거나 -CancelOnTimeout 이 없으면 기존처럼 폴 시작 기준 대기.
# -CancelOnTimeout 만 준 경우: 작업 시작(claim started_at 또는 ID 제출 시각) 기준 단계 한도까지 대기하며,
# 한도가 지나도 활동(대화/도구 로그)이 있으면 멈출 때까지 대기를 연장하고 10초마다 재확인한다.
$timedOut = @()
$startedWait = Get-Date
$pollLayout = Get-AgyLayout $script:RuntimeDirResolved
$pollRunningDir = $pollLayout.RunningDir
$watcherRecoverTried = @{}
if ($script:SubmittedTaskId -and $script:SubmittedRecoverTried) { $watcherRecoverTried[$script:SubmittedTaskId] = $true }

if ($MaxWaitSec -gt 0 -or -not $CancelOnTimeout) {
    $effectiveWait = if ($MaxWaitSec -gt 0) { $MaxWaitSec } else { $WaitSeconds }
    $testWaitMs = Get-SubmitTestMs "AGY_TEST_WAIT_MS"
    $deadline = if ($testWaitMs -gt 0 -and $effectiveWait -gt 0) { $startedWait.AddMilliseconds($testWaitMs) } else { $startedWait.AddSeconds([math]::Max(0, $effectiveWait)) }
    while ($true) {
        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) })
        if ($pending.Count -eq 0) { break }
        foreach ($pid_ in $pending) {
            [void](Try-RecoverQueuedTask $pid_ $watcherRecoverTried $pollRunningDir)
        }
        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) })
        if ($pending.Count -eq 0 -or (Get-Date) -ge $deadline) { break }
        $interval = if (((Get-Date) - $startedWait).TotalSeconds -lt 60) { 3 } else { 10 }
        $left = ($deadline - (Get-Date)).TotalSeconds
        if ($left -le 0) { break }
        $testPollMs = Get-SubmitTestMs "AGY_TEST_POLL_MS"
        if ($testPollMs -gt 0) {
            Start-Sleep -Milliseconds ([math]::Max(10, [math]::Min($testPollMs, [int][math]::Ceiling($left * 1000))))
        } else {
            Start-Sleep -Seconds ([math]::Max(1, [math]::Min($interval, [math]::Floor($left))))
        }
    }
    if ($CancelOnTimeout) {
        foreach ($pid_ in @($ids | Where-Object { -not (Test-TaskDone $_) })) {
            [void](Invoke-CancelTask $pid_ ("기다리는 한도({0}초)가 지나도 끝나지 않아 취소했습니다. 직접 처리하세요." -f $effectiveWait))
            $timedOut += $pid_
        }
    }
} else {
    # -CancelOnTimeout 만 주어진 경우: 작업별 시작 시각 기준 + 진행 중 대기 연장 규칙
    $progressLib = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
    if (Test-Path -LiteralPath $progressLib -PathType Leaf) { . $progressLib }
    $stallSec = Get-AgySecondsSetting "AGY_STALL_SECONDS" 300 30
    $hardTimeoutSec = Get-AgySecondsSetting "AGY_HARD_TIMEOUT_SECONDS" 7200 60
    $recheckSec = 10.0
    if ($env:AGY_POLL_RECHECK_SEC -match '^\d+(\.\d+)?$') {
        $recheckSec = [double]$env:AGY_POLL_RECHECK_SEC
    }
    $agyHome = Get-AgyHomeDir
    $runningDir = $pollRunningDir
    $extendedPrinted = @{}
    $bgExtendedPrinted = @{}
    $probeExtendedPrinted = @{}
    $activeProbeStates = @("checking", "thinking", "tool running", "asked")

    while ($true) {
        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) -and ($timedOut -notcontains $_) })
        if ($pending.Count -eq 0) { break }

        $now = Get-Date

        foreach ($id in $pending) {
            $tStart = Get-TaskStartTime $id $startedWait
            $tLimit = Get-TaskWaitSec $id (-not $ExplicitWaitSeconds)
            if ($tLimit -le 0) { $tLimit = $WaitSeconds }
            $elapsed = ($now - $tStart).TotalSeconds

            # 절대 마감: 작업 시작으로부터 AGY_HARD_TIMEOUT_SECONDS(기본 7200) 경과 시 취소
            if ($elapsed -ge $hardTimeoutSec) {
                $reason = "절대 대기 한도({0}초)가 지나 취소했습니다. 직접 처리하세요." -f $hardTimeoutSec
                [void](Invoke-CancelTask $id $reason)
                $timedOut += $id
                continue
            }

            # 대기열(inbox 에 있고 실행 표시 없음) 작업인데 워처가 꺼져 있으면, 작업당 한 번 워처를 켜거나 작업자를 직접 띄운다.
            $claimPath = Join-Path $runningDir "$id.json"
            if (Try-RecoverQueuedTask $id $watcherRecoverTried $runningDir) {
                continue
            }

            # 단계 한도 전이면 계속 대기
            if ($elapsed -lt $tLimit) {
                continue
            }

            # 단계 대기 한도 초과: 실행 중/대기열/활동 상태 판정
            $claim = Read-SubmitClaimJson $claimPath

            if ($claim) {
                $claimPid = 0
                if ($claim.PSObject.Properties['pid'] -and $null -ne $claim.pid) {
                    [int]::TryParse([string]$claim.pid, [ref]$claimPid) | Out-Null
                }
                $workerAliveNow = ($claimPid -gt 4 -and $null -ne (Get-Process -Id $claimPid -ErrorAction SilentlyContinue))
                $deadOrphanWorker = ($claimPid -gt 4 -and -not $workerAliveNow -and ((Get-SubmitWatcherStatus) -ne "ALIVE"))
                $probeState = ""
                if ($claim.PSObject.Properties['probe_state'] -and $claim.probe_state) {
                    $probeState = ([string]$claim.probe_state).Trim()
                }
                if (-not $deadOrphanWorker -and $probeState -and ($activeProbeStates -contains $probeState)) {
                    $probeKey = "{0}|{1}" -f $id, $probeState
                    if (-not $probeExtendedPrinted.ContainsKey($probeKey)) {
                        $probeLabel = switch ($probeState) {
                            "checking"     { "생각 중인지 확인하는 중(checking)" }
                            "thinking"     { "모델이 생각하는 중(thinking)" }
                            "tool running" { "도구를 실행하는 중(tool running)" }
                            "asked"        { "같은 대화에 진행 상황을 묻는 중(asked)" }
                            default        { $probeState }
                        }
                        Write-SubmitErrorLine ("[대기 연장] {0}: 한도 {1}초가 지났지만 {2}이라 계속 기다립니다." -f $id, $tLimit, $probeLabel)
                        $probeExtendedPrinted[$probeKey] = $true
                    }
                    continue
                }
                $actInfo = Get-SubmitTaskActivity $claim $agyHome $now
                $convId = $actInfo.ConvId
                $bridgeTrPoll = $actInfo.BridgeTranscript
                $hasBridgeTrPoll = $actInfo.HasBridgeTr
                if ($actInfo.HasSource) {
                    $latestAct = $actInfo.LatestActivity
                    $actReason = $actInfo.Reason
                    $agoSec = if ($null -ne $actInfo.AgoSeconds) { [int]$actInfo.AgoSeconds } else { [int][Math]::Max(0, $elapsed) }
                    $cancelStallThreshold = if ($workerAliveNow) { $stallSec + 45 } else { $stallSec }
                    if ($latestAct -and ($agoSec -lt $stallSec)) {
                        # 활동 진행 중: 대기 연장 및 re-check 안내 1회 출력
                        if (-not $extendedPrinted.ContainsKey($id)) {
                            Write-SubmitErrorLine ("[대기 연장] {0}: 한도 {1}초가 지났지만 {2}초 전에도 진행했습니다({3}). 멈출 때까지 계속 기다립니다." -f $id, $tLimit, $agoSec, $actReason)
                            $extendedPrinted[$id] = $true
                        }
                    } elseif ($agoSec -lt $cancelStallThreshold) {
                        # 워처 폴링(30초)이 멈춤 확인(probe_state = checking)을 기록할 여유를 준다
                        continue
                    } else {
                        # 멈춤 후보: 최근 stall window 동안 활동 없음. 다만 agy 가 백그라운드로 돌린 도구가 아직 안 끝났으면 기다린다(워처와 같은 판정).
                        $bgPending = if (-not $convId -and -not $hasBridgeTrPoll) { @() } else { @(Get-AgyPendingBackgroundTasks $agyHome $convId $(if ($hasBridgeTrPoll) { $bridgeTrPoll } else { "" })) }
                        if ($bgPending.Count -gt 0) {
                            if (-not $bgExtendedPrinted.ContainsKey($id)) {
                                Write-SubmitErrorLine ("[대기 연장] {0}: 한도 {1}초가 지났고 {2}초 넘게 새 기록이 없지만 agy 가 백그라운드로 돌린 도구 {3}건({4})이 아직 끝나지 않아 기다립니다. 워처의 절대 마감이나 {5}초 절대 한도에서 끝납니다." -f $id, $tLimit, $stallSec, $bgPending.Count, ($bgPending -join ', '), $hardTimeoutSec)
                                $bgExtendedPrinted[$id] = $true
                            }
                        } else {
                            $cancelReason = "기다리는 한도({0}초)가 지났고 최근 {1}초 동안 진행이 없어 취소했습니다. 직접 처리하세요." -f $tLimit, $stallSec
                            [void](Invoke-CancelTask $id $cancelReason)
                            $timedOut += $id
                        }
                    }
                } else {
                    # claim 에 conversation_id 가 아직 없음: limit + window 넘었으면 멈춤으로 취소
                    if ($elapsed -ge ($tLimit + $stallSec)) {
                        $cancelReason = "기다리는 한도({0}초)가 지났고 최근 {1}초 동안 진행이 없어 취소했습니다. 직접 처리하세요." -f $tLimit, $stallSec
                        [void](Invoke-CancelTask $id $cancelReason)
                        $timedOut += $id
                    }
                }
            } else {
                # running 목록에 없음: 대기열(inbox) 확인
                $queued = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $id })
                if ($queued.Count -gt 0) {
                    $watcherAlive = ((Get-SubmitWatcherStatus) -eq "ALIVE")
                    $otherRunning = Test-OtherTaskRunning $id
                    if ($watcherAlive -and $otherRunning) {
                        # 워처가 살아있고 다른 작업이 돌고 있음: 차례 기다리는 중
                        if (-not $extendedPrinted.ContainsKey($id)) {
                            Write-SubmitErrorLine ("[대기 연장] {0}: 아직 차례를 기다리는 중입니다." -f $id)
                            $extendedPrinted[$id] = $true
                        }
                    } elseif (-not $watcherAlive) {
                        # 워처가 꺼져 있음
                        $cancelReason = "기다리는 한도({0}초)가 지났고 워처가 꺼져 있어 취소했습니다. 직접 처리하세요." -f $tLimit
                        [void](Invoke-CancelTask $id $cancelReason)
                        $timedOut += $id
                    }
                } else {
                    # inbox 에도 running 에도 없음
                    if (Test-TaskDone $id) { continue }
                    $cancelReason = "기다리는 한도({0}초)가 지나도 끝나지 않아 취소했습니다. 직접 처리하세요." -f $tLimit
                    [void](Invoke-CancelTask $id $cancelReason)
                    $timedOut += $id
                }
            }
        }

        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) -and ($timedOut -notcontains $_) })
        if ($pending.Count -eq 0) { break }

        $anyOverLimit = $false
        foreach ($wid in $pending) {
            $ws = Get-TaskStartTime $wid $startedWait
            $wl = Get-TaskWaitSec $wid (-not $ExplicitWaitSeconds); if ($wl -le 0) { $wl = $WaitSeconds }
            if (($now - $ws).TotalSeconds -ge $wl) { $anyOverLimit = $true; break }
        }
        $interval = if ($anyOverLimit -or (($now - $startedWait).TotalSeconds -ge 60)) { $recheckSec } else { [Math]::Min(3.0, $recheckSec) }
        $testPollMs = Get-SubmitTestMs "AGY_TEST_POLL_MS"
        if ($testPollMs -gt 0) { $interval = [Math]::Min($interval, $testPollMs / 1000.0) }
        if ($interval -ge 1.0) {
            Start-Sleep -Seconds ([int][Math]::Round($interval))
        } else {
            Start-Sleep -Milliseconds ([Math]::Max(10, [int]($interval * 1000)))
        }
    }
}

$exit = 0
foreach ($id in $ids) {
    $resp = Join-Path $script:OutboxDir "$id.response.md"
    $err = Join-Path $script:OutboxDir "$id.error.log"
    $hasResp = (Test-Path -LiteralPath $resp -PathType Leaf) -and ((Get-Item -LiteralPath $resp).Length -gt 0)
    $hasErr = (Test-Path -LiteralPath $err -PathType Leaf) -and ((Get-Item -LiteralPath $err).Length -gt 0)

    $isRejected = $false
    $errText = ""
    if ($hasErr) {
        $errText = Read-TextFile $err
        if ($errText -match '^\ufeff?지정한 @(model|cwd|cmd|mode) ') {
            $isRejected = $true
        }
    }

    if ($isRejected) {
        Write-Output "===ERROR=== $id"
        Write-Output $errText
        if ($exit -lt 1) { $exit = 1 }
    } elseif ($hasResp) {
        $respText = Read-TextFile $resp
        if ($respText.StartsWith($script:CancelledPrefix)) {
            Write-Output "===CANCELLED=== $id"
            if ($timedOut -contains $id -and $exit -ne 1) { $exit = 4 }
        } else {
            Write-Output "===RESULT=== $id"
        }
        Write-Output $respText
    } elseif ($hasErr) {
        Write-Output "===ERROR=== $id"
        Write-Output $errText
        if ($exit -lt 1) { $exit = 1 }
    } else {
        Write-Output ("===PENDING=== $id " + (Get-PendingStatus $id))
        $exit = 2
    }

    if ($isRejected -or $hasResp -or $hasErr) {
        try {
            if (-not (Get-Command Get-QaTaskRow -ErrorAction SilentlyContinue)) {
                $dbLibPath = Join-Path $PSScriptRoot "sub\agy-db.ps1"
                if (Test-Path -LiteralPath $dbLibPath -PathType Leaf) { . $dbLibPath }
            }
            if (Get-Command Get-QaTaskRow -ErrorAction SilentlyContinue) {
                $dbP = (Get-AgyLayout $script:RuntimeDirResolved).DbPath
                if ($dbP -and (Test-Path -LiteralPath $dbP -PathType Leaf)) {
                    $qRow = $null
                    for ($qTry = 0; $qTry -lt 4; $qTry++) {
                        $qRow = Get-QaTaskRow $dbP $id
                        if ($qRow -and $qRow.PSObject.Properties['account']) { break }
                        if ($qTry -lt 3) { Start-Sleep -Milliseconds 40 }
                    }
                    if ($qRow -and $qRow.PSObject.Properties['fallback_from'] -and -not [string]::IsNullOrWhiteSpace([string]$qRow.fallback_from)) {
                        $fbFrom = [string]$qRow.fallback_from
                        $usedAcct = if ($qRow.PSObject.Properties['account'] -and $qRow.account) { [string]$qRow.account } else { "primary" }
                        $usedMod = if ($qRow.PSObject.Properties['model'] -and $qRow.model) { [string]$qRow.model } else { "" }
                        if ($usedAcct -eq "primary") {
                            Write-SubmitErrorLine "[계정 폴백 경고] $id : 부계정($fbFrom) 한도 소진/미응답으로 주 계정($usedMod)으로 폴백 실행했습니다. 다음 턴 전에 switch-sub-agy.ps1 로 부계정 로그인을 교체하세요."
                        } else {
                            Write-SubmitErrorLine "[부계정 알림] $id : $fbFrom 한도 소진/미응답으로 $usedAcct($usedMod) 에서 실행되었습니다."
                        }
                    }
                }
            }
        } catch {}
    }
}
$script:LastSubmitExitCode = $exit
    } catch {
        if ($_.Exception.Message -eq "SAMJIL_SUBMIT_STOP") { return }
        throw
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$hasExplicitWaitSec = $PSBoundParameters.ContainsKey('WaitSeconds')
Invoke-SubmitTask -File $File -Poll $Poll -Cancel $Cancel -Status $Status -NoWait:$NoWait -WaitSeconds $WaitSeconds -MaxWaitSec $MaxWaitSec -CancelOnTimeout:$CancelOnTimeout -RuntimeDir $RuntimeDir -ExplicitWaitSeconds:$hasExplicitWaitSec
exit $script:LastSubmitExitCode
