# sub-supervisor.ps1 — 부계정 Windows 계정별 작업 스케줄러 감시 래퍼(Supervisor loop).
# 예약 작업(LogonType=Password)이 이 래퍼를 띄우며, 비관리자 CMA\shlee 는 pause.flag · restart.signal 로 재시작·일시정지를 제어한다.

param(
    [Parameter(Mandatory = $true)][string]$SubSlot,
    [string]$BridgeDir = "",
    [string]$WatcherPath = "",
    [int]$PollSeconds = 2,
    [switch]$Once
)

$ErrorActionPreference = "Stop"

$bridgeLib = Join-Path $PSScriptRoot "agy-sub-bridge.ps1"
if (-not (Test-Path -LiteralPath $bridgeLib)) { $bridgeLib = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-sub-bridge.ps1" }
. $bridgeLib

$bridgeRoot = if (-not [string]::IsNullOrWhiteSpace($BridgeDir)) { $BridgeDir.Trim() } else { Get-AgySubBridgeRoot $null }
$layout = Get-AgySubSlotLayout $bridgeRoot $SubSlot
Initialize-AgySubSlotDirectories $layout | Out-Null

$modelsLib = Join-Path $PSScriptRoot "agy-models.ps1"
if (-not (Test-Path -LiteralPath $modelsLib)) { $modelsLib = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-models.ps1" }
$cfgDirSup = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "config"
if ((Test-Path -LiteralPath $modelsLib -PathType Leaf) -and (Test-Path -LiteralPath $cfgDirSup -PathType Container)) {
    try {
        . $modelsLib
        $supCfg = Get-AgyModelConfig $cfgDirSup
        if ($supCfg -and $supCfg.SubAccounts -and $supCfg.SubAccounts.AgyBinDir) {
            $bDir = [string]$supCfg.SubAccounts.AgyBinDir
            if ((Test-Path -LiteralPath $bDir -PathType Container) -and ($env:PATH -notlike "*$bDir*")) {
                $env:PATH = "$bDir;$env:PATH"
            }
        }
    } catch {}
}

if (-not $WatcherPath) {
    $WatcherPath = Join-Path $PSScriptRoot "watch-agy.ps1"
    if (-not (Test-Path -LiteralPath $WatcherPath)) {
        $WatcherPath = Join-Path (Split-Path $PSScriptRoot -Parent) "watch-agy.ps1"
    }
}
if (-not (Test-Path -LiteralPath $WatcherPath -PathType Leaf)) {
    throw "부계정 워처 스크립트를 찾을 수 없습니다: $WatcherPath"
}

$stopFlag = Join-Path $layout.StatusDir "stop.flag"
$waitSleepMs = [Math]::Max(500, [Math]::Min(2000, $PollSeconds * 1000))

function ConvertTo-SupervisorArg([string]$Arg) {
    if ($null -eq $Arg) { return '""' }
    if ($Arg.Length -gt 0 -and $Arg -notmatch '[\s"]') { return $Arg }
    return ('"' + ($Arg -replace '(\\*)"', '$1$1\"') + '"')
}

while ($true) {
    if (Test-Path -LiteralPath $stopFlag) { break }

    while (Test-Path -LiteralPath $layout.PauseFlag) {
        if (Test-Path -LiteralPath $stopFlag) { break }
        Start-Sleep -Milliseconds $waitSleepMs
    }
    if (Test-Path -LiteralPath $stopFlag) { break }

    $childArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $WatcherPath,
        "-SubSlot", $layout.SlotId,
        "-SubBridgeDir", $bridgeRoot,
        "-PollSeconds", ([string]$PollSeconds)
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($childArgs | ForEach-Object { ConvertTo-SupervisorArg ([string]$_) }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $proc = $null
    $exitCode = 0
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        while (-not $proc.WaitForExit(1000)) {
            if (Test-Path -LiteralPath $stopFlag) {
                try { & taskkill /PID $proc.Id /T /F 2>$null | Out-Null } catch {}
                try { $null = $proc.WaitForExit(3000) } catch {}
                break
            }
        }
        $proc.Refresh()
        if ($proc.HasExited) { $exitCode = [int]$proc.ExitCode }
    } finally {
        if ($proc) { try { $proc.Dispose() } catch {} }
    }

    if (Test-Path -LiteralPath $stopFlag) { break }
    if ($exitCode -eq 42) {
        # restart.signal 정상 재시작 요청: 바로 새 워처를 띄운다
        Start-Sleep -Milliseconds 200
        continue
    }
    if ($Once) { break }
    Start-Sleep -Seconds 2
}

exit 0
