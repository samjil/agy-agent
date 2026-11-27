# stop-agy.ps1
# watch-agy.ps1 워처 및 ensure-agy-running.ps1 워치독을 안전하게 정상 종료합니다.
#
# 동작 방식:
#   1. 실행 중인 워치독(ensure-agy-running.ps1) 프로세스를 종료합니다.
#   2. runtime\logs\stop.signal 및 manual_stop.flag 파일을 생성합니다.
#   3. 워처가 현재 처리 중인 작업을 정상 완료한 뒤 스스로 안전하게 종료됩니다.
#
# 사용법:
#   .\stop-agy.ps1                         # 워처 및 워치독 안전 종료 (PowerShell)

param([string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent), [string]$RuntimeDir = "", [string]$ModelsConfigDir = "")

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



. (Join-Path $PSScriptRoot "sub\agy-layout.ps1")
$Layout         = Get-AgyLayout $RuntimeDir
$LogsDir        = $Layout.LogsDir
$StopSignalFile = $Layout.StopSignalFile
$HeartbeatDir   = $Layout.HeartbeatDir
$HeartbeatFile  = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $env:COMPUTERNAME)
$ManualStopFlag = $Layout.ManualStopFlag



# 1. 실행 중인 워치독 프로세스(ensure-agy-running.ps1) 종료

$watchdogProcs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |

    Where-Object { $_.CommandLine -like "*ensure-agy-running.ps1*" })

if ($watchdogProcs.Count -gt 0) {

    foreach ($wp in $watchdogProcs) {

        Write-Host "[+] 워치독 프로세스 종료: PID $($wp.ProcessId)" -ForegroundColor Green

        Stop-Process -Id $wp.ProcessId -Force -ErrorAction SilentlyContinue

    }

}



function Set-SubAccountsPauseFlags {
    $amPath = Join-Path $PSScriptRoot "sub\agy-models.ps1"
    $abPath = Join-Path $PSScriptRoot "sub\agy-sub-bridge.ps1"
    if (-not (Test-Path -LiteralPath $amPath -PathType Leaf) -or -not (Test-Path -LiteralPath $abPath -PathType Leaf)) { return }
    try {
        . $amPath
        . $abPath
        $cfgDir = if ($ModelsConfigDir) {
            $ModelsConfigDir
        } elseif ($env:AGY_MODELS_CONFIG_DIR) {
            $env:AGY_MODELS_CONFIG_DIR
        } else {
            Join-Path (Split-Path $PSScriptRoot -Parent) "config"
        }
        $cfg = Get-AgyModelConfig $cfgDir
        if (-not $cfg -or -not $cfg.SubAccounts -or -not $cfg.SubAccounts.Enabled) { return }
        $bridgeRoot = Get-AgySubBridgeRoot $cfg.SubAccounts
        $stamp = "paused manually at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        foreach ($slot in @($cfg.SubAccounts.Slots)) {
            $slLayout = Get-AgySubSlotLayout -BridgeRoot $bridgeRoot -SlotId $slot.Id
            New-Item -ItemType Directory -Force -Path (Split-Path $slLayout.PauseFlag -Parent) | Out-Null
            [System.IO.File]::WriteAllText($slLayout.PauseFlag, $stamp, $utf8NoBom)
            Write-Host "[+] 부계정 일시 정지 플래그 설정($($slot.Id)): $($slLayout.PauseFlag)" -ForegroundColor Green
        }
    } catch {
        Write-Warning "부계정 pause.flag 설정 중 오류: $($_.Exception.Message)"
    }
}

Set-SubAccountsPauseFlags

if (-not (Test-Path $LogsDir)) {

    Write-Host "logs 폴더를 찾을 수 없습니다: $LogsDir" -ForegroundColor Yellow

    Write-Host "워처(watch-agy.ps1)가 한 번도 실행된 적이 없을 수 있습니다." -ForegroundColor Gray

    exit 0

}



# 2. 하트비트 확인

if (Test-Path $HeartbeatFile) {

    $ageSec = [int]((Get-Date) - (Get-Item $HeartbeatFile).LastWriteTime).TotalSeconds

    if ($ageSec -gt 10) {

        Write-Host "참고: 하트비트가 ${ageSec}초 전에 마지막으로 갱신됐습니다 (워처가 이미 꺼져 있을 수 있음)." -ForegroundColor Gray

    }

} else {

    Write-Host "참고: 하트비트 파일이 없습니다 (워처가 이미 꺼져 있을 수 있음)." -ForegroundColor Gray

}



# 3. 종료 신호 및 수동 정지 플래그 생성

"stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $StopSignalFile -Encoding UTF8

"stopped manually at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $ManualStopFlag -Encoding UTF8



Write-Host "종료 신호를 보냈습니다: $StopSignalFile" -ForegroundColor Green

Write-Host "수동 정지 플래그를 설정했습니다 (자동 재시작 방지): $ManualStopFlag" -ForegroundColor Green

Write-Host "워처가 현재 작업을 마친 후 안전하게 종료됩니다." -ForegroundColor Cyan

Write-Host "상태 확인: logs\watcher.log ('===== 워처 종료')" -ForegroundColor Gray

