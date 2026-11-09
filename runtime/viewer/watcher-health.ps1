# watcher-health.ps1
# serve-viewer.ps1이 agy 워처(watch-agy.ps1)가 살아 있는지 확인하고, 죽어 있으면 다시
# 켜기 위한 함수 모음입니다. dot-source해서 씁니다: `. (Join-Path $PSScriptRoot "watcher-health.ps1")`
#
# 왜 하트비트만 보지 않는가:
#   워처는 하트비트를 작업 사이에만 씁니다. agy 호출 하나를 기다리는 동안(최대 1800초)은
#   쓰지 않아서, 하트비트가 300초 넘게 낡았다고 "죽었다"고 보면 일하는 중인 워처를 죽은
#   것으로 오판하고 두 번째 워처를 띄웁니다(같은 inbox를 둘이 처리). 반대로 워처가 죽어도
#   하트비트 파일은 최대 300초 남아 있어서 "켜짐"으로 보입니다. 그래서 워처가 시작할 때
#   적는 PID 잠금 파일과 그 프로세스를 먼저 봅니다(ensure-agy-running.ps1 과 같은 근거).
#
# 다시 켜는 일은 직접 하지 않고 ensure-agy-running.ps1 에 맡깁니다. 그 스크립트가 이미
# "수동 정지 존중 -> 죽은 것 같으면 20초 뒤 한 번 더 확인 -> 창 없이 재시작 -> watchdog.log
# 기록"을 하기 때문입니다. 뷰어는 60초마다 점검해서 죽어 보일 때만 그것을 띄웁니다.

# 위임 데이터 폴더(<위임>\data) 옆의 런타임 폴더(<위임>\runtime)를 구합니다.
function Get-WatcherRuntimeDir([string]$DataDir) {
    return (Join-Path (Split-Path $DataDir -Parent) "runtime")
}

# 기본 프로세스 조회: 명령줄에 watch-agy.ps1 이 들어간 powershell.exe 목록.
function Get-WatcherProcessList {
    return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*watch-agy.ps1*" })
}

# 워처가 돌고 있다고 볼 수 있는가. 반환: @{ Alive = bool; Source = 'lock'|'process+heartbeat'|'none'; Pid = int }
#   (1) 잠금 파일의 PID가 살아 있는 powershell 프로세스이고, 그 프로세스가 잠금 파일보다
#       먼저 시작했다면 살아 있음. (PID는 재사용되므로 시작 시각으로 같은 프로세스인지 확인합니다.
#       워처는 시작한 뒤에 잠금 파일을 쓰므로 프로세스 시작 시각 <= 잠금 파일 수정 시각입니다.)
#   (2) 잠금 파일이 없거나 낡았으면, 이 PC의 하트비트가 StaleSeconds 이내이면서 watch-agy.ps1 을
#       실행 중인 프로세스가 있을 때만 살아 있음. (start-agy.ps1 과 같은 보조 판정)
function Test-WatcherAlive {
    param(
        [string]$RuntimeDir,
        [string]$ComputerName = $env:COMPUTERNAME,
        [int]$StaleSeconds = 300,
        [scriptblock]$GetWatcherProcesses = $null
    )
    $lockFile = Join-Path $RuntimeDir ("watcher_{0}.lock" -f $ComputerName)

    $lockItem = Get-Item -LiteralPath $lockFile -ErrorAction SilentlyContinue
    if ($lockItem) {
        $lockPid = 0
        try { $lockPid = [int]((Get-Content -LiteralPath $lockFile -Raw -ErrorAction Stop).Trim()) } catch { $lockPid = 0 }
        if ($lockPid -gt 0) {
            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") {
                $sameProcess = $true
                try { $sameProcess = ($proc.StartTime -le $lockItem.LastWriteTime.AddSeconds(5)) } catch { $sameProcess = $true }
                if ($sameProcess) { return @{ Alive = $true; Source = "lock"; Pid = $lockPid } }
            }
        }
    }

    $hbFile = Join-Path (Join-Path $RuntimeDir "heartbeat") ("hb_{0}.txt" -f $ComputerName)
    $hb = Get-Item -LiteralPath $hbFile -ErrorAction SilentlyContinue
    if ($hb -and (((Get-Date) - $hb.LastWriteTime).TotalSeconds -le $StaleSeconds)) {
        # @(if ...) 로 감쌉니다: if 식은 원소 하나짜리 배열을 풀어 버려서 .Count 가 비게 됩니다.
        $procs = @(if ($GetWatcherProcesses) { & $GetWatcherProcesses } else { Get-WatcherProcessList })
        if ($procs.Count -gt 0) { return @{ Alive = $true; Source = "process+heartbeat"; Pid = 0 } }
    }
    return @{ Alive = $false; Source = "none"; Pid = 0 }
}

# 사용자가 stop-agy 로 일부러 끈 상태인가.
function Test-WatcherManualStop([string]$RuntimeDir) {
    return (Test-Path -LiteralPath (Join-Path $RuntimeDir "manual_stop.flag"))
}

# 이번 점검에서 무엇을 할지. 반환: 'ok' | 'manual-stop' | 'no-script' | 'ensure-running' | 'restart'
function Get-WatcherAutoStartDecision([bool]$Alive, [bool]$ManualStop, [bool]$EnsureScriptFound, [bool]$EnsureRunning) {
    if ($Alive)             { return 'ok' }
    if ($ManualStop)        { return 'manual-stop' }
    if (-not $EnsureScriptFound) { return 'no-script' }
    if ($EnsureRunning)     { return 'ensure-running' }
    return 'restart'
}

# ensure-agy-running.ps1 에 넘길 인자 문자열.
#   -StaleThresholdSeconds 0 : ensure 의 마지막 보조 검사는 "하트비트가 300초 안이면 살아 있음"인데,
#     워처 창을 닫아도 하트비트 파일은 남아서 죽은 직후 최대 300초 동안 살아 있다고 오판하고 아무것도
#     안 합니다(실제로 18:53 에 닫은 워처를 18:58 점검이 못 켰음). 뷰어는 이미 PID 잠금으로 죽었다고
#     판단하고 ensure 를 부르므로 그 유예를 끕니다.
#   -ConfirmDelaySeconds N : 0 이상일 때만 넘깁니다(자동 점검은 ensure 기본값 20초, "켜기"는 0).
function Get-EnsureWatcherArguments([string]$EnsureScript, [string]$RuntimeDir, [int]$ConfirmDelaySeconds = -1) {
    $q = [char]34
    $args_ = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File $q$EnsureScript$q -RuntimeDir $q$RuntimeDir$q -StaleThresholdSeconds 0"
    if ($ConfirmDelaySeconds -ge 0) { $args_ += " -ConfirmDelaySeconds $ConfirmDelaySeconds" }
    return $args_
}

# ensure-agy-running.ps1 을 창 없이 한 번 실행합니다(그 스크립트가 기본 20초 뒤 재확인하고 워처를 띄움).
# 뷰어가 멈추지 않도록 기다리지 않고 프로세스 객체만 돌려줍니다.
function Start-EnsureWatcherProcess([string]$EnsureScript, [string]$RuntimeDir, [int]$ConfirmDelaySeconds = -1) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName         = "powershell.exe"
    $psi.Arguments        = Get-EnsureWatcherArguments $EnsureScript $RuntimeDir $ConfirmDelaySeconds
    $psi.UseShellExecute  = $false
    $psi.CreateNoWindow   = $true
    $psi.WorkingDirectory = $RuntimeDir
    return [System.Diagnostics.Process]::Start($psi)
}

# 주기 점검 상태. IntervalSeconds 마다 한 번 점검합니다(첫 점검은 시작 후 한 주기 뒤:
# 뷰어 시작 시점의 워처 기동은 serve-viewer.ps1 이 따로 처리합니다).
# IntervalSeconds 가 0 이하이면 자동 점검은 하지 않고, "켜기" 요청만 처리하는 상태가 됩니다.
function New-WatcherHealthState {
    param(
        [string]$RuntimeDir,
        [string]$EnsureScript,
        [int]$IntervalSeconds = 60,
        [datetime]$Now = (Get-Date),
        [scriptblock]$GetWatcherProcesses = $null,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    return @{
        RuntimeDir          = $RuntimeDir
        ComputerName        = $ComputerName
        EnsureScript        = $EnsureScript
        IntervalSeconds     = $IntervalSeconds
        NextCheckAt         = if ($IntervalSeconds -gt 0) { $Now.AddSeconds($IntervalSeconds) } else { [datetime]::MaxValue }
        LastCheckAt         = $null
        LastLaunchAt        = $null
        LaunchCount         = 0
        LastResult          = ""
        EnsureProcess       = $null
        GetWatcherProcesses = $GetWatcherProcesses
    }
}

# 서버 루프에서 자주 불러도 되는 함수: 점검 시각이 안 됐으면 바로 $null 을 돌려줍니다.
# 점검했으면 결정 문자열을 돌려줍니다. $Launcher 는 시험에서 가짜로 바꿀 수 있습니다.
function Invoke-WatcherHealthTick {
    param(
        [hashtable]$State,
        [datetime]$Now = (Get-Date),
        [scriptblock]$Launcher = { param($script, $runtime) Start-EnsureWatcherProcess $script $runtime }
    )
    if ($Now -lt $State.NextCheckAt) { return $null }
    $State.NextCheckAt = $Now.AddSeconds($State.IntervalSeconds)
    $State.LastCheckAt = $Now

    $alive = [bool](Test-WatcherAlive -RuntimeDir $State.RuntimeDir -ComputerName $State.ComputerName -GetWatcherProcesses $State.GetWatcherProcesses).Alive
    $manual = Test-WatcherManualStop $State.RuntimeDir
    $ensureRunning = ($null -ne $State.EnsureProcess) -and (-not $State.EnsureProcess.HasExited)
    $decision = Get-WatcherAutoStartDecision $alive $manual ([bool]$State.EnsureScript) $ensureRunning

    if ($decision -eq 'restart') {
        try {
            $State.EnsureProcess = & $Launcher $State.EnsureScript $State.RuntimeDir
            $State.LastLaunchAt = $Now
            $State.LaunchCount++
        } catch {
            $decision = "launch-failed: " + $_.Exception.Message
        }
    }
    $State.LastResult = $decision
    return $decision
}

# 사용자가 화면의 "켜기"를 눌렀을 때. 반환: @{ Result = ...; Message = ... }
#   already-running  이미 켜져 있음            no-script  ensure 스크립트가 없음(또는 -NoAgent)
#   busy             직전에 띄운 ensure 가 아직 도는 중   started    창 없이 켜기 시작함
#   failed           실행에 실패함
# 자동 점검과 달리 기다리지 않고(재확인 0초) 바로 켭니다. 사용자가 직접 누른 것이므로 stop-agy 로
# 끈 상태(manual_stop.flag)여도 플래그를 지우고 켭니다.
function Invoke-WatcherStartRequest {
    param(
        [hashtable]$State,
        [datetime]$Now = (Get-Date),
        [scriptblock]$Launcher = { param($script, $runtime, $delay) Start-EnsureWatcherProcess $script $runtime $delay }
    )
    if (($null -eq $State) -or (-not $State.EnsureScript)) {
        return @{ Result = "no-script"; Message = "ensure-agy-running.ps1 을 찾을 수 없거나 -NoAgent 로 실행한 뷰어입니다." }
    }
    $alive = [bool](Test-WatcherAlive -RuntimeDir $State.RuntimeDir -ComputerName $State.ComputerName -GetWatcherProcesses $State.GetWatcherProcesses).Alive
    if ($alive) { return @{ Result = "already-running"; Message = "이미 켜져 있습니다." } }
    if (($null -ne $State.EnsureProcess) -and (-not $State.EnsureProcess.HasExited)) {
        return @{ Result = "busy"; Message = "이미 켜는 중입니다." }
    }
    $flag = Join-Path $State.RuntimeDir "manual_stop.flag"
    if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
    try {
        $State.EnsureProcess = & $Launcher $State.EnsureScript $State.RuntimeDir 0
        $State.LastLaunchAt = $Now
        $State.LaunchCount++
        $State.LastResult = "manual-start"
        return @{ Result = "started"; Message = "워처를 켜는 중입니다." }
    } catch {
        $State.LastResult = "launch-failed: " + $_.Exception.Message
        return @{ Result = "failed"; Message = "실행하지 못했습니다: " + $_.Exception.Message }
    }
}
