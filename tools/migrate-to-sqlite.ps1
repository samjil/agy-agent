# 예전 파일 저장소(qa-*.jsonl, index.json, usage.csv, usage_summary.csv, sessions\*.json)를 SQLite(runtime\logs\agy.db)로 한 번에 옮긴다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\migrate-to-sqlite.ps1               # 이전 (워처·뷰어를 먼저 멈춘다)
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\migrate-to-sqlite.ps1 -Rollback     # 되돌리기
#   -RuntimeDir <폴더>   : 기본은 환경변수 AGY_DELEGATE_RUNTIME, 없으면 ~\.samjil\delegate-agy\runtime
#   -SkipProcessCheck    : 워처·뷰어가 떠 있는지 점검하지 않는다(시험용)
#
# 이전 순서: (1) 워처·뷰어가 떠 있으면 멈추라고 알리고 끝낸다 (2) 원본을 읽는다 (3) 임시 DB(agy.db.importing)에 넣는다
# (4) 건수를 맞춰 보고 기록 일부를 칸 단위로 대조한다 — 하나라도 어긋나면 임시 DB 를 지우고 원본은 그대로 둔 채 실패로 끝낸다
# (5) 통과하면 임시 DB 를 agy.db 로 바꾸고 원본을 logs\legacy-<시각>\ 로 옮긴다. 두 번 실행해도 안전하다(이미 이전했으면 알리고 끝).
# 되돌리기: 가장 최근 legacy-* 의 원본을 제자리로 돌리고, DB 에만 있던 새 기록·세션을 옛 형식으로 내보낸 뒤 agy.db 를 이름을 바꿔 보관한다.

param(
    [string]$RuntimeDir = "",
    [switch]$Rollback,
    [switch]$SkipProcessCheck,
    [int]$VerifySamples = 20
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Fail([string]$Message) { Write-Host "[x] $Message" -ForegroundColor Red; exit 1 }
function Info([string]$Message) { Write-Host $Message }

if (-not $RuntimeDir) {
    $RuntimeDir = if ($env:AGY_DELEGATE_RUNTIME) { $env:AGY_DELEGATE_RUNTIME } else { Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime" }
}
$logsDir = Join-Path $RuntimeDir "logs"
$dataDir = Join-Path $logsDir "data"
$sessionsDir = Join-Path $logsDir "sessions"
$usageCsv = Join-Path $logsDir "usage.csv"
$summaryCsv = Join-Path $logsDir "usage_summary.csv"
$indexJson = Join-Path $dataDir "index.json"
$dbPath = Join-Path $logsDir "agy.db"

$repoRoot = Split-Path $PSScriptRoot -Parent
$subDir = @((Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"), (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub")) |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ "common.ps1") } | Select-Object -First 1
if (-not $subDir) { Fail "common.ps1 / agy-db.ps1 을 찾지 못했습니다." }
. (Join-Path $subDir "common.ps1")     # agy-db.ps1, ConvertTo-CwdList, ConvertTo-ReadableJson

if (-not $SkipProcessCheck) {
    $busy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'watch-agy\.ps1|serve-viewer\.ps1' })
    if ($busy.Count -gt 0) {
        Write-Host ("워처 또는 뷰어(작업자 포함)가 돌고 있습니다(PID: {0}). 쓰는 중에 옮기면 건수가 어긋나므로 먼저 멈춰 주세요:" -f (($busy | ForEach-Object { $_.ProcessId }) -join ", ")) -ForegroundColor Yellow
        Write-Host "  워처: powershell -NoProfile -ExecutionPolicy Bypass -File `"$env:USERPROFILE\.samjil\delegate-agy\scripts\stop-agy.ps1`""
        Write-Host "  뷰어: powershell -NoProfile -ExecutionPolicy Bypass -File `"$env:USERPROFILE\.samjil\viewer\ensure-viewer-running.ps1`" -Stop"
        exit 1
    }
}

# 예전 기록 한 줄(JSON 객체)을 DB 에 넣을 레코드로. 칸 목록에 없는 키는 버리고, 질문·답이 없으면 빈 글자로 둬서 "끝난 기록"이 되게 한다.
function ConvertTo-ImportRecord($o) {
    $rec = [ordered]@{}
    foreach ($k in $script:QaRecordFields) {
        $p = $o.PSObject.Properties[$k]
        if ($null -eq $p) { continue }
        if ($k -eq 'process') { $rec[$k] = $p.Value } else { $rec[$k] = [string]$p.Value }
    }
    if (-not $rec.Contains('question')) { $rec['question'] = '' }
    if (-not $rec.Contains('answer')) { $rec['answer'] = '' }
    return $rec
}

function Remove-DbFiles([string]$Path) {
    foreach ($suffix in @('', '-wal', '-shm')) { Remove-Item -LiteralPath ($Path + $suffix) -Force -ErrorAction SilentlyContinue }
}

function Invoke-Migrate {
    if (Test-Path -LiteralPath $dbPath) {
        $probe = Open-AgyDb $dbPath
        try {
            $done = Get-AgyMeta $probe 'migrated_at'
            $cnt = [int64]($probe.Query('SELECT (SELECT COUNT(*) FROM tasks) + (SELECT COUNT(*) FROM agy_sessions) AS n', $null))[0]['n']
        } finally { $probe.Dispose() }
        if ($done) { Write-Host "이미 이전했습니다($done). 할 일이 없습니다." -ForegroundColor Green; return }
        if ($cnt -gt 0) { Fail "agy.db 에 이미 기록이 있는데 이전 표시(meta)가 없습니다. 다른 방법으로 쓰이던 DB 일 수 있어 덮어쓰지 않습니다: $dbPath" }
        Remove-DbFiles $dbPath     # 비어 있는 DB(뷰어가 먼저 열어 만든 것)는 지운다
    }

    # --- 읽기 ---
    $records = [ordered]@{}
    $broken = 0; $dupes = 0; $noId = 0
    $shards = @(Get-ChildItem -LiteralPath $dataDir -Filter 'qa-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($f in $shards) {
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
            $t = $line.Trim().TrimStart([char]0xFEFF)
            if (-not $t) { continue }
            $o = $null
            try { $o = $t | ConvertFrom-Json } catch { $broken++; continue }
            if ($null -eq $o -or -not $o.task_id) { $noId++; continue }
            $id = [string]$o.task_id
            if ($records.Contains($id)) { $dupes++; continue }
            $records[$id] = ConvertTo-ImportRecord $o
        }
    }

    $usageOnly = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $usageCsv) {
        foreach ($r in @(Import-Csv -LiteralPath $usageCsv -Encoding UTF8)) {
            $id = [string]$r.task_id
            if (-not $id -or $records.Contains($id)) { continue }
            $rec = [ordered]@{}
            foreach ($k in @('timestamp', 'computer_name', 'task_id', 'model', 'attempts', 'tried_models', 'input_tokens', 'output_tokens', 'thinking_tokens', 'total_tokens', 'elapsed_sec', 'status', 'session', 'session_id')) { $rec[$k] = [string]$r.$k }
            [void]$usageOnly.Add($rec)
        }
    }

    $sessions = New-Object System.Collections.ArrayList
    $brokenSessions = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $sessionsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $o = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ($null -eq $o) { throw "빈 세션 파일" }
            [void]$sessions.Add([pscustomobject]@{
                Key            = (Get-AgySessionKey ([System.IO.Path]::GetFileNameWithoutExtension($f.Name)))
                ConversationId = [string]$o.conversation_id
                Cwd            = @(ConvertTo-CwdList $o.cwd)
                Model          = [string]$o.model
                CreatedAt      = [string]$o.created_at
                LastUsedAt     = [string]$o.last_used_at
                TurnCount      = $(if ($o.turn_count) { [int]$o.turn_count } else { 1 })
            })
        } catch { $brokenSessions++ }
    }

    # --- 임시 DB 에 넣기 ---
    $legacy = Join-Path $logsDir ('legacy-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $tmp = $dbPath + '.importing'
    Remove-DbFiles $tmp
    $db = Open-AgyDb $tmp
    $problem = $null
    try {
        foreach ($id in @($records.Keys | Sort-Object { [string]$records[$_]['timestamp'] })) { [void](Save-QaRecord $db $records[$id] 'InsertOnly') }
        foreach ($rec in $usageOnly) { [void](Save-QaRecord $db $rec 'InsertOnly') }
        foreach ($s in $sessions) {
            Invoke-AgyDbTransaction $db { Set-AgySessionRow $db $s.Key $s.ConversationId $s.Cwd $s.Model $s.CreatedAt $s.LastUsedAt $s.TurnCount }
        }

        # --- 검증 ---
        $nTasks = [int64]($db.Query('SELECT COUNT(*) AS n FROM tasks', $null))[0]['n']
        $nDone = [int64]($db.Query('SELECT COUNT(*) AS n FROM tasks WHERE answer IS NOT NULL', $null))[0]['n']
        $nSess = [int64]($db.Query('SELECT COUNT(*) AS n FROM agy_sessions', $null))[0]['n']
        $usageIds = @($usageOnly | ForEach-Object { $_['task_id'] } | Sort-Object -Unique)
        $expectTasks = $records.Count + $usageIds.Count
        $expectSess = @($sessions | ForEach-Object { $_.Key } | Sort-Object -Unique).Count
        if ($nTasks -ne $expectTasks) { $problem = "작업 건수가 다릅니다: 기대 $expectTasks / DB $nTasks" }
        elseif ($nDone -ne $records.Count) { $problem = "끝난 기록 건수가 다릅니다: 기대 $($records.Count) / DB $nDone" }
        elseif ($nSess -ne $expectSess) { $problem = "세션 건수가 다릅니다: 기대 $expectSess / DB $nSess" }
        else {
            $sampleIds = @()
            if ($records.Count -gt 0) { $sampleIds = @($records.Keys | Get-Random -Count ([Math]::Min($VerifySamples, $records.Count))) }
            $bad = @()
            foreach ($id in $sampleIds) {
                $row = $db.Query('SELECT * FROM tasks WHERE task_id=?', [object[]]@($id))[0]
                $rec = $records[$id]
                foreach ($k in $rec.Keys) {
                    $want = if ($k -eq 'process') { $(if ($null -eq $rec[$k]) { $null } else { ConvertTo-AgyProcessJson $rec[$k] }) } else { [string]$rec[$k] }
                    $got = $row[$k]
                    if (("$want" -ne "$got") -or (($null -eq $want) -ne ($null -eq $got))) { $bad += "$id.$k" }
                }
            }
            if ($bad.Count -gt 0) { $problem = "대조에서 어긋난 칸이 있습니다: " + ($bad[0..([Math]::Min(4, $bad.Count - 1))] -join ", ") }
        }
        if (-not $problem) {
            Set-AgyMeta $db 'migrated_at' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Set-AgyMeta $db 'migrated_tasks' ([string]$nTasks)
            Set-AgyMeta $db 'migrated_sessions' ([string]$nSess)
            Set-AgyMeta $db 'legacy_dir' $legacy
        }
    } catch {
        $problem = "가져오다 오류가 났습니다: $($_.Exception.Message)"
    } finally {
        $db.Dispose()
    }
    if ($problem) {
        Remove-DbFiles $tmp
        Fail "이전을 중단했습니다(원본은 그대로입니다): $problem"
    }

    # --- 바꿔치기와 원본 보관 ---
    Remove-DbFiles $dbPath
    Move-Item -LiteralPath $tmp -Destination $dbPath
    foreach ($suffix in @('-wal', '-shm')) { Remove-Item -LiteralPath ($tmp + $suffix) -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $legacy | Out-Null
    foreach ($f in $shards) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $legacy $f.Name) }
    foreach ($p in @($indexJson, $usageCsv, $summaryCsv)) {
        if (Test-Path -LiteralPath $p) { Move-Item -LiteralPath $p -Destination (Join-Path $legacy (Split-Path $p -Leaf)) }
    }
    if (Test-Path -LiteralPath $sessionsDir) { Move-Item -LiteralPath $sessionsDir -Destination (Join-Path $legacy 'sessions') }

    Write-Host ("이전을 마쳤습니다: 끝난 기록 {0}건, 사용량만 있는 작업 {1}건, 세션 {2}건" -f $records.Count, $usageIds.Count, $expectSess) -ForegroundColor Green
    Info ("  건너뜀 - 깨진 줄 {0}, 작업 ID 없는 줄 {1}, 중복 {2}, 깨진 세션 {3}" -f $broken, $noId, $dupes, $brokenSessions)
    Info "  원본 보관: $legacy"
    Info "  다음: 워처·뷰어를 다시 켜세요(설치본이 오래됐다면 install.ps1 을 먼저 다시 실행)."
}

function Invoke-Rollback {
    $legacy = Get-ChildItem -LiteralPath $logsDir -Directory -Filter 'legacy-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $legacy) { Fail "되돌릴 원본(legacy-*)이 없습니다: $logsDir" }
    if (-not (Test-Path -LiteralPath $dbPath)) { Fail "agy.db 가 없습니다: $dbPath" }

    # 원본 샤드에 있는 작업 ID
    $legacyIds = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $legacy.FullName -Filter 'qa-*.jsonl' -File -ErrorAction SilentlyContinue)) {
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
            $t = $line.Trim().TrimStart([char]0xFEFF)
            if (-not $t) { continue }
            try { $o = $t | ConvertFrom-Json; if ($o -and $o.task_id) { $legacyIds[[string]$o.task_id] = $true } } catch {}
        }
    }

    # DB 에만 있는 새 기록·세션
    $newTasks = @(); $newSessions = @()
    $db = Open-AgyDb $dbPath
    try {
        foreach ($r in $db.Query('SELECT * FROM tasks WHERE answer IS NOT NULL ORDER BY timestamp', $null)) {
            if ($legacyIds.ContainsKey([string]$r['task_id'])) { continue }
            $rec = [ordered]@{}
            foreach ($k in $script:QaRecordFields) {
                $v = $r[$k]
                if ($null -eq $v) { continue }
                if ($k -eq 'process') { $rec[$k] = @(ConvertFrom-AgyJsonArray ([string]$v)) } else { $rec[$k] = [string]$v }
            }
            $newTasks += ,$rec
        }
        foreach ($s in $db.Query('SELECT name FROM agy_sessions', $null)) {
            $row = Get-AgySessionRow $db ([string]$s['name'])
            if ($row) { $newSessions += ,$row }
        }
    } finally { $db.Dispose() }

    # 원본을 제자리로
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $legacy.FullName -File)) {
        $dest = if ($f.Name -like 'qa-*.jsonl' -or $f.Name -eq 'index.json') { $dataDir } else { $logsDir }
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) -Force
    }
    $legSessions = Join-Path $legacy.FullName 'sessions'
    if (Test-Path -LiteralPath $legSessions) { Move-Item -LiteralPath $legSessions -Destination $sessionsDir -Force }

    # 새 기록 -> 옛 형식 샤드(qa-*.jsonl 이름이라 옛 코드와 뷰어가 읽는다)
    if ($newTasks.Count -gt 0) {
        $shard = Join-Path $dataDir ("qa-{0}.rollback.jsonl" -f (Get-Date -Format 'yyyy-MM'))
        $lines = @($newTasks | ForEach-Object { ConvertTo-ReadableJson $_ 6 })
        [System.IO.File]::AppendAllText($shard, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    }
    # 새 세션 -> 세션 파일 (옛 코드가 읽는 모양)
    New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
    foreach ($s in $newSessions) {
        $path = Join-Path $sessionsDir ("{0}.json" -f $s.name)
        if (Test-Path -LiteralPath $path) { continue }
        $data = [ordered]@{ name = $s.name; conversation_id = $s.conversation_id; cwd = @($s.cwd); model = $s.model; created_at = $s.created_at; last_used_at = $s.last_used_at; turn_count = $s.turn_count }
        Set-Content -LiteralPath $path -Value (ConvertTo-ReadableJson $data 4 -Pretty) -Encoding UTF8
    }

    if (@(Get-ChildItem -LiteralPath $legacy.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $legacy.FullName -Force -ErrorAction SilentlyContinue }
    $kept = $dbPath + '.rolledback-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item -LiteralPath $dbPath -Destination $kept
    foreach ($suffix in @('-wal', '-shm')) { Remove-Item -LiteralPath ($dbPath + $suffix) -Force -ErrorAction SilentlyContinue }

    Write-Host ("되돌렸습니다: DB 에만 있던 기록 {0}건, 세션 {1}건을 옛 형식으로 내보냈습니다." -f $newTasks.Count, $newSessions.Count) -ForegroundColor Green
    Info "  DB 는 보관했습니다: $kept"
    Info "  코드도 이전 커밋으로 되돌려야 옛 방식으로 돕니다."
}

if ($Rollback) { Invoke-Rollback } else { Invoke-Migrate }
exit 0
