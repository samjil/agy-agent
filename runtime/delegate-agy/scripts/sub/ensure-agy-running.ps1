# ensure-agy-running.ps1
# watch-agy.ps1 워처가 지금 살아있는지 확인하고, 죽어있으면(그리고 "일부러 끈 상태"가
# 아니면) 자동으로 다시 실행합니다.
#
# 두 가지 실행 방식을 지원합니다:
#   - 1회 점검 후 종료 (기본값, -LoopMinutes 0)
#   - 계속 실행되며 반복 점검 (-LoopMinutes N > 0): start-watchdog.vbs 가 이 모드로 띄웁니다.
#     시작하자마자 한 번 점검하고, 그 뒤로 N분마다 점검합니다.
#
# 판단 순서 (PC 하나만 보면 되므로 단순합니다):
#   1) logs\manual_stop.flag 가 있으면 -> 사용자가 stop-agy로 일부러 끈 상태. 아무것도 안 함.
#   2) 워처가 살아있다고 판단되면(아래 Test-AgyWatcherAlive) -> 아무것도 안 함.
#   3) 죽은 것 같으면 -> $ConfirmDelaySeconds 만큼 기다렸다가 "한 번 더" 확인.
#      (워처를 막 띄운 직후에는 powershell.exe가 아직 기동 중이라 잠깐 안 보일 수 있습니다.
#       확인 없이 바로 재시작하면 워처가 두 개 떠서 같은 inbox를 두고 충돌하는 사고로
#       이어질 수 있습니다.)
#   4) 두 번 다 죽어 있으면 -> 재시작.
#
# 사용법:
#   .\ensure-agy-running.ps1                 # 1회만 점검하고 종료
#   .\ensure-agy-running.ps1 -LoopMinutes 2  # 계속 떠서 2분마다 점검 (start-watchdog.vbs 방식)
#   .\ensure-agy-running.ps1 -CheckOnly      # 켜지 않고 상태만 확인: ALIVE(종료 코드 0) / DEAD(1) / MANUAL_STOP(2)
#
# -StaleThresholdSeconds 0 을 함께 주면 "하트비트가 최근이면 살아 있음" 판정(마지막 보조 검사)을 끕니다.
# 워처 창을 닫아도 하트비트 파일은 남아서, 그 판정을 두면 죽은 직후 최대 300초 동안 살아 있다고 오판합니다.

param(
    [string]$RepoRoot    = "",
    [string]$RuntimeDir  = "",
    [int]$StaleThresholdSeconds = 300,
    [int]$LoopMinutes = 0,
    # "죽은 것 같다"고 판단됐을 때, 재시작하기 전에 한 번 더 확인하기까지 기다리는 시간입니다.
    [int]$ConfirmDelaySeconds = 20,
    # 켜지 않고 상태만 보고합니다(스킬이 위임 직전에 "워처가 켜져 있는가"를 확인하는 용도).
    [switch]$CheckOnly
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if (-not $RepoRoot) {
    $parent = Split-Path -Path $PSScriptRoot -Parent
    if ((Split-Path -Leaf $PSScriptRoot) -eq "sub") {
        $RepoRoot = Split-Path -Path $parent -Parent
    } else {
        $RepoRoot = $parent
    }
}

if (-not $RuntimeDir) {
    if ($env:AGY_DELEGATE_RUNTIME) {
        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {
        $RuntimeDir = Join-Path $RepoRoot "runtime"
    } else {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
    }
}
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

. (Join-Path $PSScriptRoot "agy-layout.ps1")
$Layout         = Get-AgyLayout $RuntimeDir
$LogsDir        = $Layout.LogsDir
$HeartbeatDir   = $Layout.HeartbeatDir
$ManualStopFlag = $Layout.ManualStopFlag
$WatcherScript  = Join-Path $PSScriptRoot "watch-agy.ps1"
if (-not (Test-Path $WatcherScript)) {
    $WatcherScript = Join-Path (Split-Path $PSScriptRoot -Parent) "watch-agy.ps1"
}
$WatchdogLog    = Join-Path $LogsDir "watchdog.log"
$LockFile       = $Layout.LockFile

function Write-WatchdogLog($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
        "[$ts] $msg" | Add-Content -Path $WatchdogLog -Encoding UTF8
    } catch {}
}

# 워처가 돌고 있다고 볼 수 있으면 $true.
function Test-AgyWatcherAlive {
    # (1) PID 잠금 파일 - 가장 확실한 근거입니다.
    #     워처가 시작할 때 자기 PID를 적고, 정상 종료할 때 지웁니다.
    #     프로세스 목록을 CommandLine으로 뒤지는 방식은 작업 중인 워처를 못 찾아 중복
    #     실행되는 사고로 이어진 적이 있어서, 이 검사를 먼저 합니다.
    if (Test-Path $LockFile) {
        $lockPid = 0
        try { $lockPid = [int]((Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue).Trim()) } catch { $lockPid = 0 }
        if ($lockPid -gt 0) {
            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") {
                return $true
            }
            Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
            Write-WatchdogLog "낡은 잠금 파일을 정리했습니다 (PID $lockPid 는 더 이상 없음)."
        }
    }

    # (2) 보조 수단: 프로세스 목록에서 watch-agy.ps1 을 찾습니다.
    $localProcs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*watch-agy.ps1*" })
    if ($localProcs.Count -gt 0) {
        return $true
    }

    # (3) 마지막 보조 수단: 이 PC의 하트비트 파일이 최근이면 살아있는 것으로 봅니다.
    if (Test-Path $HeartbeatDir) {
        $mine = "hb_{0}.txt" -f $env:COMPUTERNAME
        $hb = Get-ChildItem -Path $HeartbeatDir -Filter $mine -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hb) {
            $ageSec = [int]((Get-Date) - $hb.LastWriteTime).TotalSeconds
            if ($ageSec -le $StaleThresholdSeconds) { return $true }
        }
    }

    return $false
}

function Invoke-EnsureAgyRunningCheck {
    if (-not (Test-Path $WatcherScript)) {
        Write-WatchdogLog "watch-agy.ps1을 찾을 수 없어 감시를 건너뜁니다: $WatcherScript"
        return
    }

    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

    # 사용자가 일부러 꺼둔 상태면 존중하고 아무것도 하지 않습니다.
    if (Test-Path $ManualStopFlag) {
        return
    }

    if (Test-AgyWatcherAlive) {
        return
    }

    # 여기까지 왔으면 "죽은 것 같다"는 뜻입니다. 다만 워처를 방금 띄운 직후라면 아직
    # 기동 중이라 안 보였을 수 있으므로, 잠시 뒤 한 번 더 확인하고 나서 결정합니다.
    if ($ConfirmDelaySeconds -gt 0) {
        Start-Sleep -Seconds $ConfirmDelaySeconds
        if (Test-AgyWatcherAlive) {
            return
        }
    }

    Write-WatchdogLog "워처가 돌고 있지 않은 것으로 판단되어(${ConfirmDelaySeconds}초 간격으로 두 번 확인) 자동으로 재시작합니다."

    # 창을 아예 만들지 않고 띄웁니다.
    $launched = $false
    try {
        $q   = [char]34
        $cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $q$WatcherScript$q -RuntimeDir $q$RuntimeDir$q"
        $sh  = New-Object -ComObject WScript.Shell
        try { $sh.CurrentDirectory = $RuntimeDir } catch {}
        [void]$sh.Run($cmd, 0, $false)
        $launched = $true
    } catch {
        Write-WatchdogLog "숨김 실행(WScript.Shell)에 실패해 기본 방식으로 대체합니다: $($_.Exception.Message)"
    }

    if (-not $launched) {
        $pParams = @{
            FilePath         = "powershell.exe"
            ArgumentList     = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$WatcherScript`"", "-RuntimeDir", "`"$RuntimeDir`"")
            WorkingDirectory = $RuntimeDir
        }
        Start-Process @pParams
    }

    Write-WatchdogLog "재시작 명령을 실행했습니다. (watcher.log에서 '===== 워처 시작' 로그로 확인 가능)"
}

if ($CheckOnly) {
    # 살아 있으면 수동 정지 플래그가 있어도 ALIVE 입니다(워처가 현재 작업을 마치고 끄는 중일 수 있음).
    if (Test-AgyWatcherAlive) { Write-Output "ALIVE"; exit 0 }
    if (Test-Path $ManualStopFlag) { Write-Output "MANUAL_STOP"; exit 2 }
    Write-Output "DEAD"
    exit 1
}

if ($LoopMinutes -le 0) {
    # 1회만 점검하고 끝냅니다.
    Invoke-EnsureAgyRunningCheck
} else {
    # 이 프로세스 자체가 계속 떠서 스스로 반복 점검합니다.
    Write-WatchdogLog "워치독 반복 감시를 시작합니다 (시작 즉시 1회 점검, 이후 ${LoopMinutes}분마다, PC: $env:COMPUTERNAME)."
    while ($true) {
        Invoke-EnsureAgyRunningCheck
        Start-Sleep -Seconds ($LoopMinutes * 60)
    }
}
