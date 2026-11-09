# agy-layout.ps1
# 위임(delegate-agy) 폴더 배치를 한 곳에서 정합니다. 워처·뷰어·start/stop·submit-task·훅이 모두 이 파일로 경로를 얻습니다.
#
#   ~\.samjil\delegate-agy\
#     scripts\                  설치 도구(uninstall 이 지우는 것)
#     data\                     위임으로 생긴 정보. 보관 기간이 지나면 워처가 정리한다(agy-retention.ps1)
#       delegate.db             위임 기록 DB(tasks · agy_sessions …)
#       tasks\processed\        처리한 지시파일
#       tasks\outbox\           agy 답변 파일
#       tasks\stuck\            멈춘 작업 파일
#       screenshots\            agy 가 남긴 이미지
#       cache\                  번역 캐시(process-ko) · claude-links.json
#       backups\                DB 백업 · 옛 기록 보관본
#     runtime\                  돌아가는 동안만 의미 있는 것
#       inbox\                  처리 전 지시파일(대기 큐)
#       running\                지금 도는 작업 표시
#       prompts\                임시 프롬프트
#       heartbeat\              워처 생존 표시
#       watcher_<PC>.lock · stop.signal · manual_stop.flag · current_task.json
#       logs\                   watcher.log · watchdog.log · syntax-check.log (진짜 런타임 로그만)
#
# 런타임 폴더 이름이 runtime 이면 data 는 그 옆(형제)이고, 아니면(시험용 임시 폴더 등) 런타임 폴더 안의 data 입니다.
# 테스트: tests\delegate-agy\agy-layout.tests.ps1

function Get-AgyDataDir([string]$RuntimeDir) {
    if ($env:AGY_DELEGATE_DATA) { return $env:AGY_DELEGATE_DATA }
    $trimmed = $RuntimeDir.TrimEnd('\', '/')
    if ((Split-Path -Leaf $trimmed) -eq "runtime") { return (Join-Path (Split-Path $trimmed -Parent) "data") }
    return (Join-Path $trimmed "data")
}

function Get-AgyLayout([string]$RuntimeDir, [string]$ComputerName = $env:COMPUTERNAME) {
    $data = Get-AgyDataDir $RuntimeDir
    return @{
        RuntimeDir     = $RuntimeDir
        DataDir        = $data
        # runtime
        InboxDir       = Join-Path $RuntimeDir "inbox"
        RunningDir     = Join-Path $RuntimeDir "running"
        PromptsDir     = Join-Path $RuntimeDir "prompts"
        HeartbeatDir   = Join-Path $RuntimeDir "heartbeat"
        LogsDir        = Join-Path $RuntimeDir "logs"
        LockFile       = Join-Path $RuntimeDir ("watcher_{0}.lock" -f $ComputerName)
        StopSignalFile = Join-Path $RuntimeDir "stop.signal"
        ManualStopFlag = Join-Path $RuntimeDir "manual_stop.flag"
        CurrentTaskFile = Join-Path $RuntimeDir "current_task.json"
        # data
        DbPath         = Join-Path $data "delegate.db"
        ProcessedDir   = Join-Path $data "tasks\processed"
        OutboxDir      = Join-Path $data "tasks\outbox"
        StuckDir       = Join-Path $data "tasks\stuck"
        ScreenshotsDir = Join-Path $data "screenshots"
        CacheDir       = Join-Path $data "cache"
        BackupsDir     = Join-Path $data "backups"
    }
}

# 옛 배치(runtime\outbox · runtime\logs\agy.db …)에 있는 것을 새 배치로 옮깁니다. 여러 번 불러도 안전합니다(이미 옮겼으면 아무것도 안 함).
# 새 위치에 같은 이름이 이미 있으면 덮어쓰지 않고 옛 것을 그대로 둡니다. 옮긴 개수를 돌려줍니다.
function Move-AgyLegacyLayout([string]$RuntimeDir) {
    $L = Get-AgyLayout $RuntimeDir
    $logs = $L.LogsDir
    $moved = 0
    $move = {
        param([string]$From, [string]$To)
        if (-not (Test-Path -LiteralPath $From)) { return 0 }
        if (Test-Path -LiteralPath $To) {
            # 새 위치에 같은 이름의 빈 폴더만 있으면(먼저 만들어졌을 때) 치우고 옮긴다. 내용이 있으면 덮어쓰지 않는다.
            if ((Test-Path -LiteralPath $To -PathType Container) -and -not (Get-ChildItem -LiteralPath $To -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $To -Force -ErrorAction SilentlyContinue }
            else { return 0 }
        }
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path $To -Parent) | Out-Null
            Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop
            return 1
        } catch { return 0 }
    }
    foreach ($pair in @(
        @((Join-Path $RuntimeDir "outbox"),      $L.OutboxDir),
        @((Join-Path $RuntimeDir "processed"),   $L.ProcessedDir),
        @((Join-Path $RuntimeDir "_stuck"),      $L.StuckDir),
        @((Join-Path $RuntimeDir "screenshots"), $L.ScreenshotsDir),
        @((Join-Path $logs "heartbeat"),         $L.HeartbeatDir),
        @((Join-Path $logs "running"),           $L.RunningDir),
        @((Join-Path $logs "prompts"),           $L.PromptsDir),
        @((Join-Path $logs "stop.signal"),       $L.StopSignalFile),
        @((Join-Path $logs "manual_stop.flag"),  $L.ManualStopFlag),
        @((Join-Path $logs "current_task.json"), $L.CurrentTaskFile),
        @((Join-Path $logs "data\claude-links.json"), (Join-Path $L.CacheDir "claude-links.json")),
        @((Join-Path $logs "data\process-ko"),   (Join-Path $L.CacheDir "process-ko"))
    )) { $moved += (& $move $pair[0] $pair[1]) }

    foreach ($f in @(Get-ChildItem -LiteralPath $logs -Filter "watcher_*.lock" -File -ErrorAction SilentlyContinue)) {
        $moved += (& $move $f.FullName (Join-Path $RuntimeDir $f.Name))
    }
    # DB(저널·WAL 포함)는 한꺼번에 옮긴다. 새 DB 가 이미 있으면 건드리지 않는다.
    if ((Test-Path -LiteralPath (Join-Path $logs "agy.db")) -and -not (Test-Path -LiteralPath $L.DbPath)) {
        foreach ($suffix in @("", "-wal", "-shm", "-journal")) {
            $moved += (& $move (Join-Path $logs ("agy.db" + $suffix)) ($L.DbPath + $suffix))
        }
    }
    # 백업 · 옛 보관본은 backups 로
    foreach ($f in @(Get-ChildItem -LiteralPath $logs -Filter "agy.db.bak-*" -File -ErrorAction SilentlyContinue)) {
        $moved += (& $move $f.FullName (Join-Path $L.BackupsDir ($f.Name -replace '^agy\.db', 'delegate.db')))
    }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $logs "data") -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "claude-links.json" })) {
        $moved += (& $move $f.FullName (Join-Path $L.BackupsDir $f.Name))
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $logs -Directory -Filter "legacy-*" -ErrorAction SilentlyContinue)) {
        $moved += (& $move $d.FullName (Join-Path $L.BackupsDir $d.Name))
    }
    # 비게 된 옛 logs\data 폴더 정리
    $oldData = Join-Path $logs "data"
    if ((Test-Path -LiteralPath $oldData) -and -not (Get-ChildItem -LiteralPath $oldData -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $oldData -Force -ErrorAction SilentlyContinue
    }
    return $moved
}
