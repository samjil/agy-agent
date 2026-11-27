# agy-task-worker.ps1
# 워처(watch-agy.ps1)가 지시파일 하나를 처리하려고 따로 띄우는 "작업자" 프로세스의 진입점입니다.
#
# 하는 일은 watch-agy.ps1 을 -WorkerTask 모드로 부르는 것이 전부입니다. 굳이 이 껍데기를 두는 이유:
# start-agy.ps1 / ensure-agy-running.ps1 은 프로세스 명령줄에 "watch-agy.ps1" 이 있는지로 워처를 찾습니다.
# 작업자를 watch-agy.ps1 로 직접 띄우면 작업자가 워처로 오인되어(예: 재시작 때 종료되어) 작업이 사라질 수 있습니다.
# 이 껍데기로 띄우면 작업자의 명령줄에는 이 파일 이름만 나타납니다.
param(
    [string]$RepoRoot = "",
    [string]$RuntimeDir = "",
    [string]$WorkerTask = "",
    [switch]$SkipPermissions,
    [string]$SubSlot = "",
    [string]$SubBridgeDir = "",
    [string]$SubUsageTaskId = "",
    [string]$SubUsageQuotaFile = "",
    [string]$SubUsageSlotFile = "",
    [int]$SubUsageTimeoutSec = 40,
    [string]$PrimaryQuotaCacheFile = "",
    [string]$ClaudeQuotaCacheFile = ""
)

if (-not [string]::IsNullOrWhiteSpace($SubUsageTaskId)) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($SubSlot)) { $env:AGY_SUB_SLOT = $SubSlot }
        $bridgeLib = Join-Path $PSScriptRoot "agy-sub-bridge.ps1"
        $quotaLib  = Join-Path $PSScriptRoot "agy-quota.ps1"
        if (Test-Path -LiteralPath $bridgeLib) { . $bridgeLib }
        if (Test-Path -LiteralPath $quotaLib) { . $quotaLib }
        if ((Get-Command Invoke-AgyUsageCommand -ErrorAction SilentlyContinue) -and (Get-Command ConvertFrom-AgyUsageText -ErrorAction SilentlyContinue)) {
            $rawUsage = Invoke-AgyUsageCommand "agy" $SubUsageTimeoutSec
            if ($rawUsage) {
                $parsed = ConvertFrom-AgyUsageText ([string]$rawUsage)
                if ($parsed -and ($parsed.Contains('gemini_5h') -or $parsed.Contains('gemini_weekly'))) {
                    $fiveUsed = $null; $fiveReset = ""
                    $weekUsed = $null; $weekReset = ""
                    if ($parsed.Contains('gemini_5h')) {
                        $e5 = $parsed.Item('gemini_5h')
                        $fiveUsed = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, 100.0 - [double]$e5.pct)), 2)
                        $fiveReset = [string]$e5.reset
                    }
                    if ($parsed.Contains('gemini_weekly')) {
                        $ew = $parsed.Item('gemini_weekly')
                        $weekUsed = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, 100.0 - [double]$ew.pct)), 2)
                        $weekReset = [string]$ew.reset
                    }
                    $qObj = [ordered]@{
                        task_id     = $SubUsageTaskId
                        slot_id     = $SubSlot
                        measured_at = ([datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
                        five_used   = $fiveUsed
                        five_reset  = $fiveReset
                        week_used   = $weekUsed
                        week_reset  = $weekReset
                    }
                    if ($SubUsageQuotaFile) { [void](Write-BridgeJsonAtomic $SubUsageQuotaFile $qObj) }
                    if ($SubUsageSlotFile)  { [void](Write-BridgeJsonAtomic $SubUsageSlotFile $qObj) }
                }
            }
        }
    } catch {}
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($PrimaryQuotaCacheFile)) {
    try {
        $quotaLib = Join-Path $PSScriptRoot "agy-quota.ps1"
        if (Test-Path -LiteralPath $quotaLib) { . $quotaLib }
        if (Get-Command Get-AgyQuotaSnapshot -ErrorAction SilentlyContinue) {
            [void](Get-AgyQuotaSnapshot -CacheFile $PrimaryQuotaCacheFile -MaxAgeSec 0 -TimeoutSec $SubUsageTimeoutSec)
        }
    } catch {}
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($ClaudeQuotaCacheFile)) {
    try {
        $quotaLib = Join-Path $PSScriptRoot "agy-quota.ps1"
        if (Test-Path -LiteralPath $quotaLib) { . $quotaLib }
        if (Get-Command Update-ClaudeLimitsCache -ErrorAction SilentlyContinue) {
            [void](Update-ClaudeLimitsCache -CacheFile $ClaudeQuotaCacheFile -MaxAgeSec 0 -TimeoutSec $SubUsageTimeoutSec)
        }
    } catch {}
    exit 0
}

$watcher = Join-Path $PSScriptRoot "watch-agy.ps1"
$callArgs = @{
    RepoRoot   = $RepoRoot
    RuntimeDir = $RuntimeDir
    WorkerTask = $WorkerTask
}
if ($SkipPermissions.IsPresent) { $callArgs['SkipPermissions'] = $true }
if (-not [string]::IsNullOrWhiteSpace($SubSlot)) { $callArgs['SubSlot'] = $SubSlot }
if (-not [string]::IsNullOrWhiteSpace($SubBridgeDir)) { $callArgs['SubBridgeDir'] = $SubBridgeDir }
& $watcher @callArgs
exit $LASTEXITCODE
