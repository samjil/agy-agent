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
    [Parameter(Mandatory = $true)][string]$WorkerTask,
    [switch]$SkipPermissions
)

$watcher = Join-Path $PSScriptRoot "watch-agy.ps1"
& $watcher -RepoRoot $RepoRoot -RuntimeDir $RuntimeDir -WorkerTask $WorkerTask -SkipPermissions:$SkipPermissions.IsPresent
exit $LASTEXITCODE
