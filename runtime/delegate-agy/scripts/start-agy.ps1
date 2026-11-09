# start-agy.ps1
# Antigravity CLI(agy) 위임 워처(watch-agy.ps1)를 안전하게 시작/재시작합니다.
#
# 순서:
#   1. 스크립트 문법 검사 (오류 시 기동 중단 및 syntax-check.log 기록)
#   2. 기존 워처가 살아있으면 정상 종료 신호 전송 및 대기
#   3. 새 콘솔 창에서 watch-agy.ps1 실행(-Hidden 이면 창 없이 백그라운드로)
#
# 사용법:
#   .\start-agy.ps1                         # 워처 안전 시작/재시작 (PowerShell)
#   .\start-agy.ps1 -CheckOnly              # 문법 검사만 수행 (워처 미실행)
#   .\start-agy.ps1 -WaitSeconds 60         # 기존 워처 종료 대기 시간 연장
#   .\start-agy.ps1 -Hidden                 # 콘솔 창 없이 백그라운드로 시작(로그는 logs\watcher.log)

param(
    [string]$RepoRoot    = (Split-Path -Path $PSScriptRoot -Parent),
    [string]$RuntimeDir  = "",
    [int]$WaitSeconds    = 30,
    [switch]$CheckOnly   = $false,
    [switch]$Hidden      = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try { chcp 65001 > $null } catch {}



if (-not $RuntimeDir) {

    if ($env:AGY_DELEGATE_RUNTIME) {

        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime"

    } elseif (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime")) {

        $RuntimeDir = Join-Path (Split-Path $PSScriptRoot -Parent) "runtime"

    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {

        $RuntimeDir = Join-Path $RepoRoot "runtime"

    } else {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"

    }

}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

. (Join-Path $PSScriptRoot "sub\agy-layout.ps1")
$Layout        = Get-AgyLayout $RuntimeDir
$LogsDir       = $Layout.LogsDir
$HeartbeatDir  = $Layout.HeartbeatDir
New-Item -ItemType Directory -Force -Path $LogsDir, $HeartbeatDir | Out-Null
$HeartbeatFile = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $env:COMPUTERNAME)
$LockFile      = $Layout.LockFile

$WatcherScript = Join-Path $PSScriptRoot "sub\watch-agy.ps1"
if (-not (Test-Path $WatcherScript)) {
    $WatcherScript = Join-Path $PSScriptRoot "watch-agy.ps1"
}

$StopScript    = Join-Path $PSScriptRoot "stop-agy.ps1"
$CheckLog      = Join-Path $LogsDir "syntax-check.log"

if (-not (Test-Path $WatcherScript)) {
    Write-Error "watch-agy.ps1을 찾을 수 없습니다: $WatcherScript"
    exit 1
}

# -----------------------------------------------------------------------------
# 1. 스크립트 문법 사전 검증
# -----------------------------------------------------------------------------
$targets = @(
    "start-agy.ps1",
    "stop-agy.ps1",
    "submit-task.ps1",
    "sub\common.ps1",
    "sub\watch-agy.ps1",
    "sub\agy-task-worker.ps1",
    "sub\ensure-agy-running.ps1",
    "sub\handoff-pump.ps1",
    "sub\agy-rules.ps1",
    "sub\agy-gitguard.ps1",
    "sub\log-qa.ps1"
)

$lines = @("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 문법 검사 시작")
$failed = $false

foreach ($relPath in $targets) {
    $file = Join-Path $PSScriptRoot $relPath
    if (-not (Test-Path $file)) {
        # sub 폴더가 아닌 현재 폴더에 있을 수도 있는 하위 호환 폴백
        $file = Join-Path $PSScriptRoot (Split-Path -Leaf $relPath)
        if (-not (Test-Path $file)) { continue }
    }

    $displayName = Split-Path -Leaf $relPath
    $errs = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errs)

    if ($errs -and $errs.Count -gt 0) {
        $failed = $true
        $lines += "  FAIL $displayName"
        foreach ($e in $errs) {
            $lines += ("    line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
        }
    } else {
        $lines += "  OK   $displayName"
    }
}



$lines | ForEach-Object { Write-Host $_ }

try { $lines | Set-Content -Path $CheckLog -Encoding UTF8 } catch {}



if ($failed) {

    Write-Host ""

    Write-Host "문법 오류가 있어 워처를 시작하지 않았습니다. 위 내용을 확인해 주세요." -ForegroundColor Red

    Write-Host "(상세 로그: $CheckLog)" -ForegroundColor Gray

    Write-Host ""

    if (-not $CheckOnly) { Read-Host "확인했으면 Enter" }

    exit 1

}



if ($CheckOnly) {

    Write-Host "`n문법 검사를 통과했습니다. (-CheckOnly 모드)" -ForegroundColor Green

    exit 0

}



# -----------------------------------------------------------------------------

# 2. 기존 실행 중인 워처 확인 및 안전 재시작 처리

# -----------------------------------------------------------------------------

function Get-WatcherProcessCount {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*watch-agy.ps1*" }).Count
    } catch {
        return -1
    }
}

function Test-WatcherAlive {
    # (1) PID 잠금 파일 - 가장 확실한 근거입니다. ensure-agy-running.ps1의
    #     Test-AgyWatcherAlive와 같은 방식입니다.
    if (Test-Path $LockFile) {
        $lockPid = 0
        try { $lockPid = [int]((Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue).Trim()) } catch { $lockPid = 0 }
        if ($lockPid -gt 0 -and $lockPid -ne $PID) {
            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") { return $true }
        }
    }

    # (2) 보조 수단: 잠금 파일이 비정상 유실된 경우를 대비해 프로세스 목록과 하트비트를 함께 확인합니다.
    #     주의: -NoExit 창은 스크립트가 이미 종료되었어도 CommandLine에 영구적으로 "watch-agy.ps1"이 남고,
    #     현재 콘솔 창($PID)에서 start-agy.ps1을 재실행했을 때도 CommandLine에 남아있습니다.
    #     따라서 $PID는 제외하고, 하트비트가 최근(300초 이내)일 때만 실제 살아있는 것으로 판정합니다.
#     300초는 워치독(ensure-agy-running.ps1)과 같은 기준입니다. 워처는 agy 작업을 기다리는
#     동안(길면 몇 분) 하트비트를 쓰지 않아서, 더 짧게 잡으면 살아 있는 워처를 죽었다고 보고
#     두 번째 워처를 띄웁니다 - 그러면 같은 질문을 둘이 처리합니다.
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*watch-agy.ps1*" })
        if ($procs.Count -gt 0 -and (Test-Path $HeartbeatFile)) {
            $ageSec = [int]((Get-Date) - (Get-Item $HeartbeatFile).LastWriteTime).TotalSeconds
            if ($ageSec -le 300) { return $true }
        }
    } catch {}

    return $false
}



if (Test-WatcherAlive) {

    Write-Host "기존 워처가 실행 중인 것으로 보입니다 - 정상 종료를 요청합니다..." -ForegroundColor Yellow



    if (Test-Path $StopScript) {

        & $StopScript -RepoRoot $RepoRoot -RuntimeDir $RuntimeDir | Out-Null

    } else {

        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

        "stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |

            Set-Content -Path $Layout.StopSignalFile -Encoding UTF8

    }



    $n = Get-WatcherProcessCount

    if ($n -gt 1) {

        Write-Host "주의: 워처가 $n 개 실행 중입니다 - 모두 정리 후 하나만 새로 시작합니다." -ForegroundColor Yellow

    }



    Write-Host "워처가 멈추기를 기다립니다 (최대 ${WaitSeconds}초)..."

    $deadline = (Get-Date).AddSeconds($WaitSeconds)

    $stopSignal = $Layout.StopSignalFile

    while ((Get-Date) -lt $deadline -and (Test-WatcherAlive)) {

        if (-not (Test-Path $stopSignal)) {

            "stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |

                Set-Content -Path $stopSignal -Encoding UTF8 -ErrorAction SilentlyContinue

        }

        Start-Sleep -Seconds 2

    }



    Remove-Item -Path $stopSignal -Force -ErrorAction SilentlyContinue

    $manualStopFlag = $Layout.ManualStopFlag

    Remove-Item -Path $manualStopFlag -Force -ErrorAction SilentlyContinue



    if (Test-WatcherAlive) {

        Write-Host ""

        Write-Host "경고: ${WaitSeconds}초 안에 워처 종료를 확인하지 못했습니다 (처리 중인 작업이 길어질 수 있습니다)." -ForegroundColor Red

        Write-Host "워처 충돌을 방지하기 위해 새 워처를 시작하지 않고 중단합니다." -ForegroundColor Red

        Write-Host "logs\watcher.log 에서 종료를 확인한 뒤 다시 실행해 주세요." -ForegroundColor Gray

        exit 1

    }



    Write-Host "기존 워처가 정상 종료되었습니다." -ForegroundColor Green

} else {

    Write-Host "실행 중인 워처가 없습니다 - 새로 시작합니다." -ForegroundColor Cyan

}



# -----------------------------------------------------------------------------
# 3. 워처 기동 (기본: 새 콘솔 창 / -Hidden: 창 없이 백그라운드)
# -----------------------------------------------------------------------------
if ($Hidden) {
    # ensure-agy-running.ps1 과 같은 방식: WScript.Shell.Run(명령, 0)은 콘솔 창을 아예 만들지 않는다.
    $launched = $false
    try {
        $q   = [char]34
        $cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $q$WatcherScript$q -RuntimeDir $q$RuntimeDir$q"
        $sh  = New-Object -ComObject WScript.Shell
        try { $sh.CurrentDirectory = $RuntimeDir } catch {}
        [void]$sh.Run($cmd, 0, $false)
        $launched = $true
    } catch {
        Write-Host "숨김 실행(WScript.Shell)에 실패해 Start-Process 로 대체합니다: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if (-not $launched) {
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -WorkingDirectory $RuntimeDir -ArgumentList @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$WatcherScript`"", "-RuntimeDir", "`"$RuntimeDir`"")
    }
    Write-Host "새 워처를 창 없이 백그라운드로 실행했습니다." -ForegroundColor Green
} else {
    $procParams = @{
        FilePath         = "powershell.exe"
        ArgumentList     = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$WatcherScript`"", "-RuntimeDir", "`"$RuntimeDir`"")
        WorkingDirectory = $RuntimeDir
    }
    Start-Process @procParams
    Write-Host "새 워처 창을 실행했습니다." -ForegroundColor Green
}

Write-Host "logs\watcher.log 에서 '===== 워처 시작' 로그로 확인할 수 있습니다." -ForegroundColor Gray

