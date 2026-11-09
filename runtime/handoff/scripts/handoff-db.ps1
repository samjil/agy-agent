# handoff-db.ps1
# samjil-handoff 채널의 "원장(메시지 목록과 상태) · 자동 이어가기 상태"를 SQLite(~\.samjil\handoff\data\handoff.db)에 담는 모듈입니다.
# handoff-lib.ps1 이 dot-source 해서 씁니다(워처의 핸드오프 펌프 · Claude Stop 훅 · 뷰어가 모두 lib 를 거친다).
#
#   ~\.samjil\handoff\
#     scripts\ templates\        설치 도구
#     data\handoff.db            원장 · 자동 이어가기 상태 (보관 3개월)
#     channels\<프로젝트>\       BRIEF.md · msg\NNNN-방향-슬러그.md(협의 원문) · INDEX.md(DB 에서 만든 보기) · AUTO.off
#
# INDEX.md 는 이제 DB 에서 다시 만드는 "보기"다. 사람·에이전트가 예전처럼 손으로 줄을 고쳐도 다음에 읽을 때 DB 로 흡수한다
# (마지막으로 만든 파일의 해시와 다르면 파일의 행을 DB 에 반영한 뒤 다시 만든다). 그래서 규약을 한꺼번에 바꾸지 않아도 된다.
#
# SQLite 접근은 delegate-agy 의 agy-db.ps1(winsqlite3 P/Invoke)을 같이 쓴다. 같은 상대 위치(handoff\scripts -> ..\..\delegate-agy\scripts\sub)를 본다.
# 테스트: tests\handoff\handoff-db.tests.ps1

function Find-HandoffAgyDbLib {
    $cands = @()
    if ($env:AGY_DB_LIB) { $cands += $env:AGY_DB_LIB }
    $cands += (Join-Path $PSScriptRoot "..\..\delegate-agy\scripts\sub\agy-db.ps1")
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if ($home_) { $cands += (Join-Path $home_ ".samjil\delegate-agy\scripts\sub\agy-db.ps1") }
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path } }
    return $null
}
if (-not (Get-Command Initialize-AgySqlite -CommandType Function -ErrorAction SilentlyContinue)) {
    $script:__handoffAgyDbLib = Find-HandoffAgyDbLib
    if ($script:__handoffAgyDbLib) { . $script:__handoffAgyDbLib }
}

$script:HandoffDbSchemaVersion = 1
$script:HandoffDbSchemaSql = @(
    "CREATE TABLE IF NOT EXISTS messages (
        channel TEXT NOT NULL, num TEXT NOT NULL, ts TEXT, dir TEXT, title TEXT, status TEXT,
        PRIMARY KEY (channel, num))",
    "CREATE TABLE IF NOT EXISTS channel_state (
        channel TEXT PRIMARY KEY NOT NULL, halted INTEGER NOT NULL DEFAULT 0, halted_at TEXT, halted_reason TEXT,
        max_num INTEGER NOT NULL DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS dispatches (
        channel TEXT NOT NULL, task_id TEXT NOT NULL, num TEXT, at TEXT, done INTEGER NOT NULL DEFAULT 0, tier TEXT,
        PRIMARY KEY (channel, task_id))",
    "CREATE TABLE IF NOT EXISTS hook_blocks (channel TEXT NOT NULL, num TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel, num))",
    "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY NOT NULL, value TEXT)"
)

# --------------------------------------------------------------------------------------------
# 경로
# --------------------------------------------------------------------------------------------

# 데이터 폴더: 환경변수 AGENT_HANDOFF_DATA > 채널 루트 이름이 channels 면 그 옆의 data > (시험용 임시 루트) 루트 안의 .data
function Get-HandoffDataDir {
    if ($env:AGENT_HANDOFF_DATA) { return $env:AGENT_HANDOFF_DATA }
    $root = (Get-HandoffRootDir).TrimEnd([char]92, [char]47)
    if (-not $root) { return "" }
    if ((Split-Path -Leaf $root) -eq "channels") { return (Join-Path (Split-Path $root -Parent) "data") }
    return (Join-Path $root ".data")
}

function Get-HandoffDbPath { return (Join-Path (Get-HandoffDataDir) "handoff.db") }

function Get-HandoffChannelKey([string]$ChannelDir) { return (Split-Path -Leaf $ChannelDir.TrimEnd([char]92, [char]47)) }

# --------------------------------------------------------------------------------------------
# 연결
# --------------------------------------------------------------------------------------------

function Open-HandoffDb {
    if (-not (Get-Command Initialize-AgySqlite -CommandType Function -ErrorAction SilentlyContinue)) { throw "agy-db.ps1 을 찾을 수 없어 핸드오프 DB 를 열 수 없습니다." }
    Initialize-AgySqlite
    $path = Get-HandoffDbPath
    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $db = [AgySqlite.Db]::Open($path, 10000)
    try {
        [void]$db.Execute("PRAGMA synchronous=NORMAL", $null)
        $ver = $db.Query("PRAGMA user_version", $null)
        if ([int64]$ver[0]["user_version"] -lt $script:HandoffDbSchemaVersion) {
            [void]$db.Execute("PRAGMA journal_mode=WAL", $null)
            foreach ($sql in $script:HandoffDbSchemaSql) { [void]$db.Execute($sql, $null) }
            [void]$db.Execute(("PRAGMA user_version = {0}" -f $script:HandoffDbSchemaVersion), $null)
        }
    } catch { $db.Dispose(); throw }
    return $db
}

# --------------------------------------------------------------------------------------------
# 원장 보기(INDEX.md) <-> DB
# --------------------------------------------------------------------------------------------

function Get-HandoffFileHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs)).Replace("-", "")) } finally { $fs.Dispose() }
    } catch { return "" } finally { $sha.Dispose() }
}

function Set-HandoffMaxNum($Db, [string]$Key, [int]$Num) {
    [void]$Db.Execute("INSERT INTO channel_state (channel, max_num) VALUES (?, ?) ON CONFLICT(channel) DO UPDATE SET max_num = MAX(max_num, excluded.max_num)", [object[]]@($Key, $Num))
}

# DB 의 행으로 INDEX.md 를 다시 만든다. 위쪽 설명(표 앞의 줄)과 줄바꿈 모양(CRLF/LF)·BOM 은 기존 파일을 따른다.
function Write-HandoffIndexView([string]$ChannelDir, $Db) {
    $key = Get-HandoffChannelKey $ChannelDir
    $idx = Join-Path $ChannelDir "INDEX.md"
    $header = @("# INDEX — 메시지 원장", "", "이 파일은 핸드오프 DB(data\handoff.db)에서 만든 보기다. 줄을 손으로 고쳐도 다음에 읽을 때 DB 에 반영된다.", "상태는 보냄 · 읽음 · 처리됨 · 보류 · 작업중 중 하나.", "")
    $nl = "`n"; $bom = $false
    if (Test-Path -LiteralPath $idx -PathType Leaf) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($idx)
            $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
            if ($text.Contains("`r`n")) { $nl = "`r`n" }
            $lines = @($text -split "\r?\n")
            $tableAt = -1
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\|\s*번호\s*\|') { $tableAt = $i; break } }
            if ($tableAt -gt 0) { $header = @($lines[0..($tableAt - 1)]) }
        } catch {}
    }
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in $header) { $out.Add($h) }
    $out.Add("| 번호 | 시각 | 방향 | 제목 | 상태 |")
    $out.Add("|---|---|---|---|---|")
    foreach ($r in @($Db.Query("SELECT num, ts, dir, title, status FROM messages WHERE channel = ? ORDER BY num", [object[]]@($key)))) {
        $out.Add(("| {0} | {1} | {2} | {3} | {4} |" -f $r["num"], $r["ts"], $r["dir"], $r["title"], $r["status"]))
    }
    $content = ($out -join $nl) + $nl
    $outBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($content)
    if ($bom) { $outBytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $outBytes) }
    $tmp = $idx + ".tmp"
    [System.IO.File]::WriteAllBytes($tmp, $outBytes)
    Move-Item -LiteralPath $tmp -Destination $idx -Force
    [void]$Db.Execute("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [object[]]@(("index_hash:" + $key), (Get-HandoffFileHash $idx)))
}

# INDEX.md 가 마지막으로 만든 것과 다르면(손으로 고쳤거나 예전 채널) 그 행을 DB 에 흡수한 뒤 보기를 다시 만든다. 이미 같으면 아무것도 안 한다.
function Sync-HandoffLedger([string]$ChannelDir, $Db) {
    $key = Get-HandoffChannelKey $ChannelDir
    $idx = Join-Path $ChannelDir "INDEX.md"
    $stored = $Db.Query("SELECT value FROM meta WHERE key = ?", [object[]]@("index_hash:" + $key))
    $storedHash = if ($stored.Count -gt 0) { [string]$stored[0]["value"] } else { $null }
    if (Test-Path -LiteralPath $idx -PathType Leaf) {
        $h = Get-HandoffFileHash $idx
        if ($h -and $h -eq $storedHash) { return }
        $text = $null
        try {
            $fs = New-Object System.IO.FileStream($idx, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try { $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true); $text = $sr.ReadToEnd() } finally { $fs.Dispose() }
        } catch { return }
        foreach ($line in @($text -split "\r?\n")) {
            $r = ConvertFrom-HandoffIndexLine $line
            if (-not $r) { continue }
            [void]$Db.Execute("INSERT INTO messages (channel, num, ts, dir, title, status) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(channel, num) DO UPDATE SET ts=excluded.ts, dir=excluded.dir, title=excluded.title, status=excluded.status", [object[]]@($key, $r.Num, $r.Time, $r.Dir, $r.Title, $r.Status))
            Set-HandoffMaxNum $Db $key ([int]$r.Num)
        }
        Write-HandoffIndexView $ChannelDir $Db
        return
    }
    if ($Db.Query("SELECT 1 FROM messages WHERE channel = ? LIMIT 1", [object[]]@($key)).Count -gt 0) { Write-HandoffIndexView $ChannelDir $Db }
}

# 원장을 한 번의 잠금 안에서 읽고 쓰는 도우미: DB 를 열고 INDEX.md 와 맞춘 뒤 $Body($Db, $Key) 를 실행한다. 돌려준 값을 그대로 돌려준다.
function Invoke-HandoffLedger([string]$ChannelDir, [scriptblock]$Body) {
    $script:__hlDir = $ChannelDir; $script:__hlBody = $Body
    return (Invoke-HandoffLock $ChannelDir {
        $db = Open-HandoffDb
        try {
            Sync-HandoffLedger $script:__hlDir $db
            & $script:__hlBody $db (Get-HandoffChannelKey $script:__hlDir)
        } finally { $db.Dispose() }
    })
}

# --------------------------------------------------------------------------------------------
# 보관 기간(개월)이 지난 메시지·기록 정리
# --------------------------------------------------------------------------------------------

# 메시지 시각(없으면 파일 수정 시각)이 보관 기간보다 오래된 메시지 파일과 원장 행, 위임 기록을 지운다. 지운 메시지 개수를 돌려준다.
# 번호는 DB 의 max_num 이 기억하므로 지워도 새 메시지가 옛 번호를 다시 쓰지 않는다. BRIEF.md · INDEX.md 와 채널 폴더는 지우지 않는다.
function Remove-HandoffOlderThan([int]$Months = 3) {
    $cut = (Get-Date).AddMonths(-$Months)
    $cutStr = $cut.ToString("yyyy-MM-dd HH:mm")
    $removed = 0
    foreach ($ch in @(Get-HandoffChannelDirs)) {
        $script:__hrCh = $ch; $script:__hrCut = $cut; $script:__hrCutStr = $cutStr
        $n = Invoke-HandoffLedger $ch {
            param($db, $key)
            $dir = $script:__hrCh
            $gone = 0
            $msgDir = Join-Path $dir "msg"
            $rows = @($db.Query("SELECT num, ts FROM messages WHERE channel = ?", [object[]]@($key)))
            $known = @{}
            foreach ($r in $rows) {
                $num = [string]$r["num"]; $known[$num] = $true
                $ts = [string]$r["ts"]
                $file = Get-HandoffMessageFile $dir $num
                $old = $false
                if ($ts) { $old = ($ts -lt $script:__hrCutStr) }
                elseif ($file) { $old = ($file.LastWriteTime -lt $script:__hrCut) }
                if (-not $old) { continue }
                if ($file) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
                [void]$db.Execute("DELETE FROM messages WHERE channel = ? AND num = ?", [object[]]@($key, $num))
                [void]$db.Execute("DELETE FROM hook_blocks WHERE channel = ? AND num = ?", [object[]]@($key, $num))
                $gone++
            }
            # 원장에 없는 오래된 메시지 파일(손으로 만들고 아직 흡수 전인 것 포함)도 정리한다
            if (Test-Path -LiteralPath $msgDir -PathType Container) {
                foreach ($f in @(Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File -ErrorAction SilentlyContinue)) {
                    if ($f.Name -match '^(\d{4})-' -and -not $known.ContainsKey($Matches[1]) -and $f.LastWriteTime -lt $script:__hrCut) {
                        Set-HandoffMaxNum $db $key ([int]$Matches[1])
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                        $gone++
                    }
                }
            }
            [void]$db.Execute("DELETE FROM dispatches WHERE channel = ? AND at IS NOT NULL AND at <> '' AND at < ?", [object[]]@($key, $script:__hrCut.ToString("yyyy-MM-dd HH:mm:ss")))
            if ($gone -gt 0) { Write-HandoffIndexView $dir $db }
            return $gone
        }
        $removed += [int]$n
    }
    return $removed
}

# --------------------------------------------------------------------------------------------
# 옛 폴더 배치(~\.samjil\handoff\<채널>\) -> channels\<채널>\ . 이미 옮겼으면 아무것도 안 한다. 옮긴 채널 수를 돌려준다.
# --------------------------------------------------------------------------------------------
function Move-HandoffLegacyLayout([string]$HandoffHome = "") {
    if (-not $HandoffHome) {
        $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        if (-not $home_) { return 0 }
        $HandoffHome = Join-Path $home_ ".samjil\handoff"
    }
    if (-not (Test-Path -LiteralPath $HandoffHome -PathType Container)) { return 0 }
    $channels = Join-Path $HandoffHome "channels"
    $moved = 0
    foreach ($d in @(Get-ChildItem -LiteralPath $HandoffHome -Directory -ErrorAction SilentlyContinue)) {
        if (@("scripts", "templates", "data", "channels", "viewer", "skills") -contains $d.Name) { continue }
        if (-not ((Test-Path -LiteralPath (Join-Path $d.FullName "INDEX.md") -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $d.FullName "BRIEF.md") -PathType Leaf))) { continue }
        $dest = Join-Path $channels $d.Name
        if (Test-Path -LiteralPath $dest) { continue }
        New-Item -ItemType Directory -Force -Path $channels | Out-Null
        try {
            Move-Item -LiteralPath $d.FullName -Destination $dest -ErrorAction Stop
            $moved++
        } catch {
            # 폴더 자체를 못 옮길 때(IDE·파일 감시기가 폴더를 열어 두면 이름을 못 바꾼다): 안의 항목을 하나씩 옮긴다.
            # 하나라도 실패하면 이미 옮긴 것을 되돌려 반쯤 옮긴 채널이 남지 않게 한다.
            $done = @()
            $ok = $true
            try {
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                foreach ($c in @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop)) {
                    Move-Item -LiteralPath $c.FullName -Destination (Join-Path $dest $c.Name) -ErrorAction Stop
                    $done += $c.Name
                }
            } catch { $ok = $false }
            if ($ok) {
                Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue   # 비었다. 열어 둔 쪽이 있으면 못 지워도 괜찮다
                $moved++
            } else {
                foreach ($n in $done) { try { Move-Item -LiteralPath (Join-Path $dest $n) -Destination (Join-Path $d.FullName $n) -ErrorAction Stop } catch {} }
                if (-not (Get-ChildItem -LiteralPath $dest -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    $off = Join-Path $HandoffHome "AUTO.off"
    if ((Test-Path -LiteralPath $off -PathType Leaf) -and (Test-Path -LiteralPath $channels -PathType Container) -and -not (Test-Path -LiteralPath (Join-Path $channels "AUTO.off"))) {
        try { Move-Item -LiteralPath $off -Destination (Join-Path $channels "AUTO.off") -ErrorAction Stop } catch {}
    }
    return $moved
}
