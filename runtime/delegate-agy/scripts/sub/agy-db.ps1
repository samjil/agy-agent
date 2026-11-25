# agy-db.ps1
# 위임 기록(tasks)과 agy 세션(agy_sessions)을 담는 SQLite 저장소(delegate-agy\data\delegate.db)를 다루는 공용 모듈입니다.
# 워처·작업자·log-qa.ps1·handoff-pump.ps1·뷰어가 이 파일을 dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-db.ps1")`
#
# 왜 SQLite 인가: 여러 프로세스(워처, 작업자 여럿, log-qa, 뷰어)가 같은 기록을 동시에 읽고 쓴다. 예전에는 파일(qa-*.jsonl, usage.csv,
# 세션 json)을 이름 있는 뮤텍스로 감싸 한 번에 하나씩 쓰고, 중복은 파일 꼬리를 읽어 검사했다. SQLite(WAL)는 동시 쓰기를 알아서 차례로
# 세우고, 같은 작업 ID 의 중복은 기본키가 막는다.
#
# 접근 방식: Windows 에 들어 있는 winsqlite3.dll 을 C# P/Invoke 로 부른다(추가 설치 없음). Windows PowerShell 5.1 의 C# 컴파일러는
# C# 5 까지만 알아서 문자열 보간($"")·?. 같은 문법을 쓰지 않았다. 컴파일 결과는 ~\.samjil\cache 에 저장해 다음 프로세스는 컴파일 없이 불러온다.

$script:AgySqliteSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace AgySqlite
{
    public class SqliteException : Exception
    {
        public int Code;
        public SqliteException(int code, string message) : base(message) { Code = code; }
    }

    public sealed class Db : IDisposable
    {
        const string Lib = "winsqlite3.dll";
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close_v2(IntPtr db);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_errmsg(IntPtr db);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_changes(IntPtr db);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_bind_null(IntPtr stmt, int index);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_bind_int64(IntPtr stmt, int index, long value);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_bind_double(IntPtr stmt, int index, double value);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] text, int length, IntPtr destructor);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_column_count(IntPtr stmt);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_name(IntPtr stmt, int col);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_column_type(IntPtr stmt, int col);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern long sqlite3_column_int64(IntPtr stmt, int col);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern double sqlite3_column_double(IntPtr stmt, int col);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int col);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt, int col);

        const int OK = 0, ROW = 100, DONE = 101;
        static readonly IntPtr Transient = new IntPtr(-1);
        IntPtr handle;

        Db(IntPtr h) { handle = h; }

        static string Utf8(IntPtr p, int len)
        {
            if (p == IntPtr.Zero || len <= 0) { return ""; }
            byte[] b = new byte[len];
            Marshal.Copy(p, b, 0, len);
            return Encoding.UTF8.GetString(b);
        }

        string Message()
        {
            IntPtr p = sqlite3_errmsg(handle);
            return p == IntPtr.Zero ? "" : Marshal.PtrToStringAnsi(p);
        }

        public static Db Open(string path, int busyMs)
        {
            byte[] p = Encoding.UTF8.GetBytes(path + "\0");
            IntPtr h;
            // 2 = READWRITE, 4 = CREATE
            int rc = sqlite3_open_v2(p, out h, 2 | 4, IntPtr.Zero);
            if (rc != OK)
            {
                string m = "열 수 없음";
                if (h != IntPtr.Zero) { m = Marshal.PtrToStringAnsi(sqlite3_errmsg(h)); sqlite3_close_v2(h); }
                throw new SqliteException(rc, "SQLite 열기 실패(" + rc + "): " + m + " [" + path + "]");
            }
            sqlite3_busy_timeout(h, busyMs);
            return new Db(h);
        }

        IntPtr Prepare(string sql, object[] args)
        {
            IntPtr stmt;
            int rc = sqlite3_prepare_v2(handle, Encoding.UTF8.GetBytes(sql + "\0"), -1, out stmt, IntPtr.Zero);
            if (rc != OK) { throw new SqliteException(rc, "SQL 준비 실패(" + rc + "): " + Message() + " [" + sql + "]"); }
            if (args != null)
            {
                for (int i = 0; i < args.Length; i++)
                {
                    int idx = i + 1;
                    object a = args[i];
                    int brc;
                    if (a == null || a is DBNull) { brc = sqlite3_bind_null(stmt, idx); }
                    else if (a is string)
                    {
                        byte[] b = Encoding.UTF8.GetBytes((string)a);
                        int n = b.Length;
                        // 길이 0 인 배열은 NULL 포인터로 넘어가 빈 문자열이 NULL 로 저장될 수 있어 한 칸을 둔다
                        if (n == 0) { b = new byte[1]; }
                        brc = sqlite3_bind_text(stmt, idx, b, n, Transient);
                    }
                    else if (a is bool) { brc = sqlite3_bind_int64(stmt, idx, ((bool)a) ? 1 : 0); }
                    else if (a is int || a is long || a is short || a is byte) { brc = sqlite3_bind_int64(stmt, idx, Convert.ToInt64(a)); }
                    else if (a is double || a is float || a is decimal) { brc = sqlite3_bind_double(stmt, idx, Convert.ToDouble(a)); }
                    else
                    {
                        byte[] b2 = Encoding.UTF8.GetBytes(a.ToString());
                        int n2 = b2.Length;
                        if (n2 == 0) { b2 = new byte[1]; }
                        brc = sqlite3_bind_text(stmt, idx, b2, n2, Transient);
                    }
                    if (brc != OK) { sqlite3_finalize(stmt); throw new SqliteException(brc, "값 바인딩 실패(" + brc + "): " + Message()); }
                }
            }
            return stmt;
        }

        // INSERT/UPDATE/DELETE/PRAGMA 등을 실행하고 영향받은 행 수를 돌려준다. 결과 행이 있으면 버린다.
        public int Execute(string sql, object[] args)
        {
            IntPtr stmt = Prepare(sql, args);
            try
            {
                int rc;
                while ((rc = sqlite3_step(stmt)) == ROW) { }
                if (rc != DONE) { throw new SqliteException(rc, "SQL 실행 실패(" + rc + "): " + Message() + " [" + sql + "]"); }
                return sqlite3_changes(handle);
            }
            finally { sqlite3_finalize(stmt); }
        }

        // SELECT 결과를 열 이름 -> 값 사전의 목록으로 돌려준다(값: string / long / double / null).
        public List<Dictionary<string, object>> Query(string sql, object[] args)
        {
            IntPtr stmt = Prepare(sql, args);
            try
            {
                List<Dictionary<string, object>> rows = new List<Dictionary<string, object>>();
                int cols = sqlite3_column_count(stmt);
                string[] names = new string[cols];
                for (int c = 0; c < cols; c++) { names[c] = Marshal.PtrToStringAnsi(sqlite3_column_name(stmt, c)); }
                int rc;
                while ((rc = sqlite3_step(stmt)) == ROW)
                {
                    Dictionary<string, object> row = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                    for (int c = 0; c < cols; c++)
                    {
                        int t = sqlite3_column_type(stmt, c);
                        if (t == 5) { row[names[c]] = null; }
                        else if (t == 1) { row[names[c]] = sqlite3_column_int64(stmt, c); }
                        else if (t == 2) { row[names[c]] = sqlite3_column_double(stmt, c); }
                        else
                        {
                            IntPtr tp = sqlite3_column_text(stmt, c);
                            int len = sqlite3_column_bytes(stmt, c);
                            row[names[c]] = Utf8(tp, len);
                        }
                    }
                    rows.Add(row);
                }
                if (rc != DONE) { throw new SqliteException(rc, "SQL 조회 실패(" + rc + "): " + Message() + " [" + sql + "]"); }
                return rows;
            }
            finally { sqlite3_finalize(stmt); }
        }

        public void Dispose()
        {
            if (handle != IntPtr.Zero) { sqlite3_close_v2(handle); handle = IntPtr.Zero; }
        }
    }
}
'@

# 컴파일한 어셈블리를 캐시 폴더에 두고 불러온다. 이미 이 프로세스에 올라와 있으면 아무것도 안 한다.
# 캐시 파일 이름에 소스 해시가 들어가므로 소스가 바뀌면 새 파일로 다시 컴파일한다. 여러 프로세스가 동시에 처음 컴파일해도 서로 다른 임시 파일에
# 만든 뒤 복사하므로 안전하다(먼저 끝낸 것이 이긴다).
function Initialize-AgySqlite {
    if ('AgySqlite.Db' -as [type]) { return }
    $src = $script:AgySqliteSource
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($src))).Replace('-', '')).Substring(0, 12).ToLowerInvariant()
    $sha.Dispose()
    $cacheDir = if ($env:AGY_DB_CACHE_DIR) { $env:AGY_DB_CACHE_DIR } else { Join-Path $env:USERPROFILE ".samjil\cache" }
    $dll = Join-Path $cacheDir ("agy-sqlite-{0}.dll" -f $hash)
    if (-not (Test-Path -LiteralPath $dll)) {
        try {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            $tmp = Join-Path $cacheDir ("agy-sqlite-{0}-{1}.tmp.dll" -f $hash, [Guid]::NewGuid().ToString("N"))
            Add-Type -TypeDefinition $src -Language CSharp -OutputAssembly $tmp -OutputType Library
            Copy-Item -LiteralPath $tmp -Destination $dll -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        } catch {
            # 캐시를 못 만들어도(읽기 전용 폴더 등) 메모리에서 컴파일해 쓴다
        }
    }
    if ('AgySqlite.Db' -as [type]) { return }
    if (Test-Path -LiteralPath $dll) {
        try { Add-Type -Path $dll; return } catch {}
    }
    Add-Type -TypeDefinition $src -Language CSharp
}

# ============================================================================
# 연결 · 스키마 · 트랜잭션
# ============================================================================

# 표나 열을 더하면 이 숫자를 올린다. 이미 있는 DB 는 user_version 이 이 값보다 낮을 때만 스키마를 다시 확인하므로, 안 올리면 새 표가 만들어지지 않는다.
#   1: tasks · agy_sessions · meta   3: + cum_* · usage_basis(이어 보낸 세션 토큰 분리)
#   15: 토큰 통계 표(token_files · token_turns · token_task_links · token_estimates)는 더 만들지 않는다. 이미 있는 DB 의 표는 지우지 않고 그냥 안 쓴다.
#   16: 실측 통계 표(usage_files · usage_notes · usage_questions). 수집은 sub\usage-stats.ps1, 사유 기록은 note-choice.ps1 · submit-task.ps1(@reason).
#   17: usage_questions 에 Claude 노력 단계(claude_effort). 열을 새로 더할 때는 usage_files 를 비워 대화 기록을 처음부터 다시 읽게 한다(예전 질문의 노력도 채운다).
#   18: tasks 에 Gemini 가 프롬프트만으로 산정한 예상 시간(estimated_sec) 추가 (2026-11-20 부터 쓰지 않음).
#   19: usage_questions 에 위임을 보낸 서브에이전트 모델(agent_model · agent_effort) 추가. claude-meta 에서 채우므로 usage_files 는 비우지 않는다.
#   20: claude_usage(위임별 Claude 토큰 집계 캐시) 추가. 다른 표는 건드리지 않는다.
#   21: task_limits(완료된 위임별 한도 추정 스냅샷) 추가. 다른 표는 건드리지 않는다.
#   22: task_quota(위임 완료 직후 실측한 agy 남은 한도) 추가. task_limits 에서 예전 gemini 항목 제거(claude 는 유지).
#   23: task_models(위임별 실제 실행 모델 토큰) 추가. 다른 표는 건드리지 않는다.
#   24: tasks 에 context_tokens(위임 호출에서 가장 컸던 컨텍스트 크기) 열 추가. 끝날 때 워처가 쓰고, 옛 위임은 실측 통계 수집의 백필이 채운다.
#   25: usage_questions 에 본 세션에서 가장 컸던 한 호출의 컨텍스트(ctx_tokens · ctx_model) 추가. 열을 더할 때 usage_files 를 비워 예전 질문도 다시 계산한다.
$script:AgyDbSchemaVersion = 25
$script:AgyDbSchemaSql = @(
    "CREATE TABLE IF NOT EXISTS tasks (
        task_id TEXT PRIMARY KEY NOT NULL,
        timestamp TEXT, computer_name TEXT, source TEXT, model TEXT, attempts TEXT, tried_models TEXT,
        input_tokens TEXT, output_tokens TEXT, thinking_tokens TEXT, total_tokens TEXT, elapsed_sec TEXT,
        status TEXT, session TEXT, session_id TEXT, question TEXT, answer TEXT, process TEXT,
        cum_input_tokens TEXT, cum_output_tokens TEXT, cum_thinking_tokens TEXT, cum_total_tokens TEXT, usage_basis TEXT,
        estimated_sec TEXT, context_tokens INTEGER,
        updated_seq INTEGER NOT NULL DEFAULT 0)",
    "CREATE INDEX IF NOT EXISTS idx_tasks_seq ON tasks(updated_seq)",
    "CREATE INDEX IF NOT EXISTS idx_tasks_timestamp ON tasks(timestamp)",
    "CREATE TABLE IF NOT EXISTS agy_sessions (
        name TEXT PRIMARY KEY NOT NULL COLLATE NOCASE,
        conversation_id TEXT, cwd TEXT NOT NULL DEFAULT '[]', model TEXT,
        created_at TEXT, last_used_at TEXT, turn_count INTEGER NOT NULL DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY NOT NULL, value TEXT)",
    "CREATE TABLE IF NOT EXISTS claude_usage (
        task_id TEXT PRIMARY KEY NOT NULL,
        json TEXT,
        src_mtime TEXT,
        computed_at TEXT)",
    "CREATE TABLE IF NOT EXISTS task_limits (
        task_id TEXT PRIMARY KEY NOT NULL,
        json TEXT,
        captured_at TEXT)",
    "CREATE TABLE IF NOT EXISTS task_quota (
        task_id TEXT PRIMARY KEY NOT NULL,
        measured_at TEXT,
        five_used REAL,
        five_reset TEXT,
        week_used REAL,
        week_reset TEXT,
        concurrent INTEGER NOT NULL DEFAULT 0)",
    "CREATE INDEX IF NOT EXISTS idx_task_quota_measured_at ON task_quota(measured_at)",
    "CREATE TABLE IF NOT EXISTS task_models (
        task_id TEXT NOT NULL,
        model TEXT NOT NULL,
        input INTEGER NOT NULL DEFAULT 0,
        cache INTEGER NOT NULL DEFAULT 0,
        output INTEGER NOT NULL DEFAULT 0,
        thinking INTEGER NOT NULL DEFAULT 0,
        steps INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(task_id, model))",
    # 실측 통계: 대화 기록 파일별로 어디까지 읽었는지 / Claude 가 남긴 사유 / 질문 한 건의 측정값(시각은 모두 UTC ISO 글자)
    "CREATE TABLE IF NOT EXISTS usage_files (path TEXT PRIMARY KEY NOT NULL, offset INTEGER NOT NULL DEFAULT 0, mtime TEXT)",
    "CREATE TABLE IF NOT EXISTS usage_notes (id INTEGER PRIMARY KEY, session TEXT, noted_at TEXT, mode TEXT, reason TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_usage_notes_session ON usage_notes(session, noted_at)",
    "CREATE TABLE IF NOT EXISTS usage_questions (
        session TEXT NOT NULL, q_ts TEXT NOT NULL, project TEXT, mode TEXT,
        claude_model TEXT, claude_effort TEXT, agent_model TEXT, agent_effort TEXT, agy_models TEXT,
        dur_sec INTEGER, calls INTEGER,
        in_tokens INTEGER, cc_tokens INTEGER, cr_tokens INTEGER, out_tokens INTEGER,
        agy_tokens INTEGER, agy_sec INTEGER, task_ids TEXT, task_ok INTEGER, task_fail INTEGER, task_cancel INTEGER,
        reason TEXT, preview TEXT, auto INTEGER DEFAULT 0, end_ts TEXT,
        ctx_tokens INTEGER, ctx_model TEXT,
        PRIMARY KEY(session, q_ts))",
    "CREATE INDEX IF NOT EXISTS idx_usage_questions_ts ON usage_questions(q_ts)"
)

# 기록 한 건의 칸과 순서. New-QaRecord(common.ps1)와 뷰어 API 가 같은 목록을 쓴다.
# 값은 모두 글자(예전 jsonl 기록이 숫자도 글자로 담았다). process 는 도구 목록의 JSON 글자이고 NULL = "모름", "[]" = "없음".
$script:QaRecordFields = @('timestamp', 'computer_name', 'task_id', 'source', 'model', 'attempts', 'tried_models', 'input_tokens', 'output_tokens',
    'thinking_tokens', 'total_tokens', 'elapsed_sec', 'status', 'session', 'session_id', 'question', 'answer', 'process',
    'cum_input_tokens', 'cum_output_tokens', 'cum_thinking_tokens', 'cum_total_tokens', 'usage_basis', 'estimated_sec')

function Initialize-AgyDbSchema($Db, [string]$Path = "") {
    [void]$Db.Execute("PRAGMA journal_mode=WAL", $null)
    foreach ($sql in $script:AgyDbSchemaSql) { [void]$Db.Execute($sql, $null) }
    # 스키마 v3: tasks 표에 누적 토큰(cum_*) 및 산출 기준(usage_basis) 열 추가 및 기존 기록 마이그레이션
    $taskCols = @{}
    try {
        $tInfo = $Db.Query("PRAGMA table_info(tasks)", $null)
        if ($tInfo) {
            foreach ($row in $tInfo) {
                if ($row["name"]) { $taskCols[[string]$row["name"]] = $true }
            }
        }
    } catch {}
    $neededTaskCols = @('cum_input_tokens', 'cum_output_tokens', 'cum_thinking_tokens', 'cum_total_tokens', 'usage_basis', 'estimated_sec')
    foreach ($cName in $neededTaskCols) {
        if ($taskCols.Count -gt 0 -and -not $taskCols.ContainsKey($cName)) {
            try { [void]$Db.Execute("ALTER TABLE tasks ADD COLUMN $cName TEXT", $null) } catch {}
        }
    }
    # 스키마 v24: 컨텍스트 크기 열(숫자). 값은 비어 있다가 위임이 끝날 때 · 백필에서 채워진다.
    if ($taskCols.Count -gt 0 -and -not $taskCols.ContainsKey('context_tokens')) {
        try { [void]$Db.Execute("ALTER TABLE tasks ADD COLUMN context_tokens INTEGER", $null) } catch {}
    }

    # 스키마 v17: 실측 통계 질문 표에 Claude 노력 단계 열. 예전 DB 에 열을 더하면 읽은 위치(usage_files)를 비워 다음 수집이 처음부터 다시 읽게 한다.
    try {
        $uqCols = @{}
        foreach ($row in @($Db.Query("PRAGMA table_info(usage_questions)", $null))) { if ($row["name"]) { $uqCols[[string]$row["name"]] = $true } }
        if ($uqCols.Count -gt 0 -and -not $uqCols.ContainsKey('claude_effort')) {
            [void]$Db.Execute("ALTER TABLE usage_questions ADD COLUMN claude_effort TEXT", $null)
            [void]$Db.Execute("DELETE FROM usage_files", $null)
        }
        # 스키마 v19: 위임을 보낸 서브에이전트 모델 · 노력 단계 열. claude-meta 에서 채우므로 usage_files 는 비우지 않는다.
        foreach ($col in @('agent_model', 'agent_effort')) {
            if ($uqCols.Count -gt 0 -and -not $uqCols.ContainsKey($col)) {
                [void]$Db.Execute("ALTER TABLE usage_questions ADD COLUMN $col TEXT", $null)
            }
        }
        # 스키마 v25: 가장 컸던 한 호출의 컨텍스트. 예전 질문도 채우려고 읽은 위치(usage_files)를 비운다.
        if ($uqCols.Count -gt 0 -and -not $uqCols.ContainsKey('ctx_tokens')) {
            [void]$Db.Execute("ALTER TABLE usage_questions ADD COLUMN ctx_tokens INTEGER", $null)
            [void]$Db.Execute("ALTER TABLE usage_questions ADD COLUMN ctx_model TEXT", $null)
            [void]$Db.Execute("DELETE FROM usage_files", $null)
        }
    } catch {}

    # 기존 기록 마이그레이션 (한 번만, 되돌릴 수 있게)
    $alreadyMigrated = $false
    try {
        $mRow = $Db.Query("SELECT value FROM meta WHERE key = 'usage_delta_migrated'", $null)
        if ($mRow -and $mRow.Count -gt 0 -and $mRow[0]["value"] -eq '1') { $alreadyMigrated = $true }
    } catch {}

    if (-not $alreadyMigrated) {
        $taskCount = 0
        try {
            $cntRow = $Db.Query("SELECT COUNT(*) AS c FROM tasks", $null)
            if ($cntRow -and $cntRow.Count -gt 0) { $taskCount = [int64]$cntRow[0]["c"] }
        } catch {}

        # 실제 DB 파일이 디스크에 있고 실제로 바꿀 행이 있을 때 마이그레이션 전 백업을 남긴다
        if ($taskCount -gt 0 -and $Path -and $Path -ne ':memory:' -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            try {
                $dataDir = Split-Path $Path -Parent
                $backupDir = Join-Path $dataDir "backups"
                if (-not (Test-Path -LiteralPath $backupDir)) {
                    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
                }
                $backupName = "delegate.db.pre-usage-delta-" + (Get-Date -Format "yyyyMMdd-HHmmss")
                $backupPath = Join-Path $backupDir $backupName
                if (-not (Test-Path -LiteralPath $backupPath)) {
                    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
                }
            } catch {}
        }

        Invoke-AgyDbTransaction $Db {
            $allTasks = @($Db.Query("SELECT task_id, timestamp, session_id, input_tokens, output_tokens, thinking_tokens, total_tokens, status FROM tasks ORDER BY timestamp ASC, rowid ASC", $null))
            $groups = [ordered]@{}
            $standalone = New-Object System.Collections.ArrayList
            foreach ($t in $allTasks) {
                $sid = if ($t['session_id']) { [string]$t['session_id'] } else { "" }
                if (-not $sid) {
                    [void]$standalone.Add($t)
                } else {
                    if (-not $groups.Contains($sid)) { $groups[$sid] = New-Object System.Collections.ArrayList }
                    [void]$groups[$sid].Add($t)
                }
            }

            # 1. 세션 없는 단독 위임: 그대로 이 위임 몫(own)
            foreach ($t in $standalone) {
                $tid = [string]$t['task_id']
                $inTok = if ($null -ne $t['input_tokens']) { [string]$t['input_tokens'] } else { "" }
                $outTok = if ($null -ne $t['output_tokens']) { [string]$t['output_tokens'] } else { "" }
                $thinkTok = if ($null -ne $t['thinking_tokens']) { [string]$t['thinking_tokens'] } else { "" }
                $totTok = if ($null -ne $t['total_tokens']) { [string]$t['total_tokens'] } else { "" }
                [void]$Db.Execute("UPDATE tasks SET cum_input_tokens = ?, cum_output_tokens = ?, cum_thinking_tokens = ?, cum_total_tokens = ?, usage_basis = 'own' WHERE task_id = ?",
                    [object[]]@($inTok, $outTok, $thinkTok, $totTok, $tid))
            }

            # 2. 세션이 있는 위임: 같은 session_id 로 묶어 시각순으로 앞 기록과 비교
            foreach ($sid in $groups.Keys) {
                $group = $groups[$sid]
                $prevCumTot = $null; $prevCumIn = $null; $prevCumOut = $null; $prevCumThink = $null
                foreach ($t in $group) {
                    $tid = [string]$t['task_id']
                    $rawTot = if ($null -ne $t['total_tokens']) { [string]$t['total_tokens'] } else { "" }
                    $rawIn = if ($null -ne $t['input_tokens']) { [string]$t['input_tokens'] } else { "" }
                    $rawOut = if ($null -ne $t['output_tokens']) { [string]$t['output_tokens'] } else { "" }
                    $rawThink = if ($null -ne $t['thinking_tokens']) { [string]$t['thinking_tokens'] } else { "" }

                    $curTot = 0L; $hasTot = [int64]::TryParse($rawTot, [ref]$curTot)
                    $curIn = 0L; $hasIn = [int64]::TryParse($rawIn, [ref]$curIn)
                    $curOut = 0L; $hasOut = [int64]::TryParse($rawOut, [ref]$curOut)
                    $curThink = 0L; $hasThink = [int64]::TryParse($rawThink, [ref]$curThink)

                    if (-not $hasTot) {
                        # 토큰 숫자가 없는 행(오류 등)
                        [void]$Db.Execute("UPDATE tasks SET cum_input_tokens = ?, cum_output_tokens = ?, cum_thinking_tokens = ?, cum_total_tokens = ?, usage_basis = 'own' WHERE task_id = ?",
                            [object[]]@($rawIn, $rawOut, $rawThink, $rawTot, $tid))
                        continue
                    }

                    if ($null -eq $prevCumTot -or $curTot -lt $prevCumTot) {
                        # 그 세션의 첫 기록이거나 앞 기록보다 작아진 경우(새 대화 리셋) -> own
                        [void]$Db.Execute("UPDATE tasks SET cum_input_tokens = ?, cum_output_tokens = ?, cum_thinking_tokens = ?, cum_total_tokens = ?, usage_basis = 'own' WHERE task_id = ?",
                            [object[]]@($rawIn, $rawOut, $rawThink, $rawTot, $tid))
                        $prevCumTot = $curTot; $prevCumIn = $curIn; $prevCumOut = $curOut; $prevCumThink = $curThink
                    } else {
                        # 앞 기록보다 크거나 같음 -> 누적값으로 보고 차이(delta) 계산
                        $dTot = $curTot - $prevCumTot
                        $dIn = $curIn - $prevCumIn
                        $dOut = $curOut - $prevCumOut
                        $dThink = $curThink - $prevCumThink
                        $hasNeg = ($dTot -lt 0 -or $dIn -lt 0 -or $dOut -lt 0 -or $dThink -lt 0)

                        $newTot = [Math]::Max(0L, $dTot)
                        $newIn = [Math]::Max(0L, $dIn)
                        $newOut = [Math]::Max(0L, $dOut)
                        $newThink = [Math]::Max(0L, $dThink)
                        $basis = if ($hasNeg) { 'delta*' } else { 'delta' }

                        $newThinkStr = if ($hasThink) { [string]$newThink } else { "" }
                        [void]$Db.Execute("UPDATE tasks SET input_tokens = ?, output_tokens = ?, thinking_tokens = ?, total_tokens = ?, cum_input_tokens = ?, cum_output_tokens = ?, cum_thinking_tokens = ?, cum_total_tokens = ?, usage_basis = ? WHERE task_id = ?",
                            [object[]]@([string]$newIn, [string]$newOut, $newThinkStr, [string]$newTot, $rawIn, $rawOut, $rawThink, $rawTot, $basis, $tid))

                        $prevCumTot = $curTot; $prevCumIn = $curIn; $prevCumOut = $curOut; $prevCumThink = $curThink
                    }
                }
            }

            [void]$Db.Execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('usage_delta_migrated', '1')", $null)
        }
    }

    # 스키마 v22: 기존 task_limits 의 gemini 항목은 제거하고 claude 만 남긴다(빈 행은 삭제).
    try {
        $tlGemRows = @($Db.Query("SELECT task_id, json FROM task_limits WHERE json LIKE '%gemini%'", $null))
        if ($tlGemRows.Count -gt 0) {
            Invoke-AgyDbTransaction $Db {
                foreach ($tr in $tlGemRows) {
                    $tid = [string]$tr['task_id']
                    $rawJson = [string]$tr['json']
                    if (-not $tid -or -not $rawJson) { continue }
                    try {
                        $obj = ConvertFrom-Json -InputObject $rawJson -ErrorAction Stop
                        if ($null -eq $obj -or -not ($obj.PSObject.Properties['gemini'])) { continue }
                        $kept = [ordered]@{}
                        foreach ($p in $obj.PSObject.Properties) {
                            if ($p.Name -eq 'gemini') { continue }
                            $kept[$p.Name] = $p.Value
                        }
                        if ($kept.Count -eq 0) {
                            [void]$Db.Execute("DELETE FROM task_limits WHERE task_id = ?", [object[]]@($tid))
                        } else {
                            $newJson = ConvertTo-Json -InputObject $kept -Depth 6 -Compress
                            [void]$Db.Execute("UPDATE task_limits SET json = ? WHERE task_id = ?", [object[]]@($newJson, $tid))
                        }
                    } catch {}
                }
            }
        }
    } catch {}

    [void]$Db.Execute(("PRAGMA user_version = {0}" -f $script:AgyDbSchemaVersion), $null)
}

# DB 를 연다(없으면 만든다). 쓰는 쪽이 짧게 열고 바로 Dispose 한다. 다른 프로세스가 쓰는 중이면 BusyMs 까지 기다린다.
function Open-AgyDb([string]$Path, [int]$BusyMs = 10000) {
    Initialize-AgySqlite
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $db = [AgySqlite.Db]::Open($Path, $BusyMs)
    try {
        [void]$db.Execute("PRAGMA synchronous=NORMAL", $null)
        $ver = $db.Query("PRAGMA user_version", $null)
        if ([int64]$ver[0]["user_version"] -lt $script:AgyDbSchemaVersion) { Initialize-AgyDbSchema $db $Path }
    } catch {
        $db.Dispose()
        throw
    }
    return $db
}

# BEGIN IMMEDIATE ... COMMIT 으로 Body 를 실행한다. 오류가 나면 ROLLBACK 하고 그 오류를 그대로 던진다. Body 가 돌려준 값을 돌려준다.
function Invoke-AgyDbTransaction($Db, [scriptblock]$Body) {
    [void]$Db.Execute("BEGIN IMMEDIATE", $null)
    try {
        $result = & $Body
        [void]$Db.Execute("COMMIT", $null)
        return $result
    } catch {
        try { [void]$Db.Execute("ROLLBACK", $null) } catch {}
        throw
    }
}

# 잠깐 뒤에 다시 하면 될 오류인가(다른 프로세스가 잠가 둠, 디스크 입출력 문제 등). 이 경우 기록은 pending 폴더로 피한다.
function Test-AgyDbTransient($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($null -ne $e) {
        if ($e -is [AgySqlite.SqliteException] -and (@(5, 6, 10, 13, 14) -contains [int]$e.Code)) { return $true }
        $e = $e.InnerException
    }
    return $false
}

# ============================================================================
# JSON 글자 만들기 (뷰어 API 가 DB 의 글자를 그대로 이어 붙여 JSON 을 만든다)
# ============================================================================

function ConvertTo-AgyJsonString([string]$Text) {
    if ($null -eq $Text) { return 'null' }
    $t = $Text.Replace('\', '\\').Replace('"', '\"')
    $t = [regex]::Replace($t, '[\x00-\x1f]', {
        param($m)
        $c = [int][char]$m.Value
        switch ($c) {
            8 { return '\b' }
            9 { return '\t' }
            10 { return '\n' }
            12 { return '\f' }
            13 { return '\r' }
            default { return ('\u{0:x4}' -f $c) }
        }
    })
    return '"' + $t + '"'
}

function ConvertTo-AgyJsonArray($Items) {
    $list = @($Items | Where-Object { $null -ne $_ })
    return '[' + ((@($list | ForEach-Object { ConvertTo-AgyJsonString ([string]$_) })) -join ',') + ']'
}

# 글자 목록의 JSON("[...]")을 읽는다. ConvertFrom-Json 은 5.1 에서 배열을 한 덩어리로 돌려주는 일이 있어, 항목을 하나씩 꺼내 평평하게 만든다.
# 비어 있거나 읽을 수 없으면 빈 배열(호출하는 쪽에서 @() 로 감싼다).
function ConvertFrom-AgyJsonArray([string]$Text) {
    $out = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        try {
            $parsed = ConvertFrom-Json -InputObject $Text
            foreach ($item in $parsed) { [void]$out.Add($item) }
        } catch { }
    }
    return $out.ToArray()
}

# process(도구 목록)를 DB 에 넣을 JSON 글자로. 빈 목록은 "[]" 이다.
function ConvertTo-AgyProcessJson($Steps) {
    $list = @($Steps)
    if ($list.Count -eq 0) { return '[]' }
    return (ConvertTo-Json -InputObject $list -Depth 8 -Compress)
}

# ============================================================================
# 위임 기록 (tasks)
# ============================================================================

function ConvertTo-AgyRowObject($Dict) {
    $o = [ordered]@{}
    foreach ($k in $Dict.Keys) { $o[$k] = $Dict[$k] }
    return [pscustomobject]$o
}

# 기록 한 건을 저장한다. 돌려주는 값: 실제로 바뀐 행이 있으면 $true.
#   Upsert           : 같은 작업 ID 가 있으면 Record 에 있는 칸만 덮어쓴다(없는 칸은 그대로)
#   InsertOnly       : 같은 작업 ID 가 이미 있으면 아무것도 하지 않는다(먼저 쓴 것이 이긴다)
#   FillIfIncomplete : 같은 작업 ID 의 행이 있고 아직 답(answer)이 비어 있을 때만 채운다("끝난 기록"이 되게 한다)
function Save-QaRecord($Db, [System.Collections.IDictionary]$Record, [string]$Mode = 'Upsert') {
    $taskId = if ($Record.Contains('task_id')) { [string]$Record['task_id'] } else { '' }
    if (-not $taskId) { throw "task_id 가 없는 기록은 저장할 수 없습니다." }
    foreach ($k in $Record.Keys) {
        if ($script:QaRecordFields -notcontains [string]$k) { throw "기록에 없는 칸 이름입니다: $k" }
    }
    $cols = New-Object System.Collections.ArrayList
    $vals = New-Object System.Collections.ArrayList
    foreach ($k in $script:QaRecordFields) {
        if (-not $Record.Contains($k)) { continue }
        $v = $Record[$k]
        if ($k -eq 'process') { $v = $(if ($null -eq $v) { $null } else { ConvertTo-AgyProcessJson $v }) }
        else { $v = [string]$v }
        [void]$cols.Add($k)
        [void]$vals.Add($v)
    }
    $setCols = @($cols | Where-Object { $_ -ne 'task_id' })
    $sql = "INSERT INTO tasks ({0}) VALUES ({1}) ON CONFLICT(task_id) DO " -f ($cols -join ','), ((@('?') * $cols.Count) -join ',')
    if ($Mode -eq 'InsertOnly' -or $setCols.Count -eq 0) { $sql += 'NOTHING' }
    else {
        $sql += 'UPDATE SET ' + (($setCols | ForEach-Object { "$_=excluded.$_" }) -join ',')
        if ($Mode -eq 'FillIfIncomplete') { $sql += ' WHERE tasks.answer IS NULL' }
    }
    $bindArgs = $vals.ToArray()
    $written = Invoke-AgyDbTransaction $Db {
        $n = $Db.Execute($sql, $bindArgs)
        if ($n -gt 0) {
            [void]$Db.Execute('UPDATE tasks SET updated_seq=(SELECT COALESCE(MAX(updated_seq),0)+1 FROM tasks) WHERE task_id=?', [object[]]@($taskId))
        }
        return ($n -gt 0)
    }
    return [bool]$written
}

function Get-AgyPendingDir([string]$DbPath) { return (Join-Path (Split-Path $DbPath -Parent) 'pending') }

# DB 를 잠깐 못 쓸 때 기록을 잃지 않게 파일로 둔다. 다음에 DB 를 열 때 Import-PendingQaRecords 가 가져온다.
function Save-PendingQaRecord([string]$DbPath, [System.Collections.IDictionary]$Record, [string]$Mode) {
    $dir = Get-AgyPendingDir $DbPath
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $id = ([string]$Record['task_id']) -replace '[\\/:*?"<>|]', '_'
    $json = ConvertTo-Json -InputObject ([ordered]@{ mode = $Mode; record = $Record }) -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $dir ("{0}.{1}.json" -f $id, $Mode)), $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Import-PendingQaRecords($Db, [string]$PendingDir) {
    if (-not (Test-Path -LiteralPath $PendingDir)) { return 0 }
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $PendingDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
        try {
            $o = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $rec = [ordered]@{}
            foreach ($p in $o.record.PSObject.Properties) { $rec[$p.Name] = $p.Value }
            [void](Save-QaRecord $Db $rec ([string]$o.mode))
            Remove-Item -LiteralPath $f.FullName -Force
            $n++
        } catch { }
    }
    return $n
}

# 경로로 부르는 기록 저장. 돌려주는 값: 'saved' | 'skipped'(InsertOnly 중복 / 이미 끝난 기록) | 'pending'(DB 를 못 써서 pending 폴더에 둠)
function Write-QaRecordToDb([string]$DbPath, [System.Collections.IDictionary]$Record, [string]$Mode = 'Upsert') {
    $db = $null
    try {
        $db = Open-AgyDb $DbPath
        [void](Import-PendingQaRecords $db (Get-AgyPendingDir $DbPath))
        if (Save-QaRecord $db $Record $Mode) { return 'saved' }
        return 'skipped'
    } catch {
        if (Test-AgyDbTransient $_) {
            Save-PendingQaRecord $DbPath $Record $Mode
            return 'pending'
        }
        throw
    } finally {
        if ($null -ne $db) { $db.Dispose() }
    }
}

# 작업 ID 의 행(없으면 $null). 열 이름이 속성이다. 아직 안 채운 칸은 $null.
function Get-QaTaskRow([string]$DbPath, [string]$TaskId) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return $null }
    $db = Open-AgyDb $DbPath
    try {
        $rows = $db.Query('SELECT * FROM tasks WHERE task_id=?', [object[]]@($TaskId))
        if ($rows.Count -eq 0) { return $null }
        return (ConvertTo-AgyRowObject $rows[0])
    } finally { $db.Dispose() }
}

# 사용량 행만 있고 아직 질문·답이 안 채워진 작업들(옛 이름으로 "usage.csv 에는 있는데 jsonl 에는 없는 작업").
function Get-QaIncompleteRows([string]$DbPath) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return @() }
    $db = Open-AgyDb $DbPath
    try {
        $rows = $db.Query('SELECT * FROM tasks WHERE answer IS NULL ORDER BY timestamp', $null)
        $out = @()
        foreach ($r in $rows) { $out += ,(ConvertTo-AgyRowObject $r) }
        return $out
    } finally { $db.Dispose() }
}

# 보관 기간이 지난 기록을 지운다. 돌려주는 값: 지운 건수.
function Remove-QaRecordsOlderThan([string]$DbPath, [int]$Months) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return 0 }
    $cut = (Get-Date).AddMonths(-$Months).ToString('yyyy-MM-dd HH:mm:ss')
    $db = Open-AgyDb $DbPath
    try {
        return $db.Execute("DELETE FROM tasks WHERE timestamp IS NOT NULL AND timestamp <> '' AND timestamp < ?", [object[]]@($cut))
    } finally { $db.Dispose() }
}

# 뷰어 API 의 본문: updated_seq 가 Since 보다 큰 "끝난 기록"들을 예전 jsonl 한 줄과 같은 모양으로 담은 JSON 글자.
# { "records": [...], "seq": <가장 큰 updated_seq>, "total": <끝난 기록 전체 건수> }
function Get-QaRecordsJson([string]$DbPath, [long]$Since = 0) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return ('{{"records":[],"seq":{0},"total":0}}' -f $Since) }
    $db = Open-AgyDb $DbPath
    try {
        $total = [int64]($db.Query('SELECT COUNT(*) AS n FROM tasks WHERE answer IS NOT NULL', $null))[0]['n']
        $rows = $db.Query('SELECT * FROM tasks WHERE answer IS NOT NULL AND updated_seq > ? ORDER BY updated_seq', [object[]]@($Since))
    } finally { $db.Dispose() }
    $seq = $Since
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{"records":[')
    $first = $true
    foreach ($r in $rows) {
        if ([int64]$r['updated_seq'] -gt $seq) { $seq = [int64]$r['updated_seq'] }
        if (-not $first) { [void]$sb.Append(',') }
        $first = $false
        [void]$sb.Append('{')
        $firstField = $true
        foreach ($k in $script:QaRecordFields) {
            $v = $r[$k]
            if ($null -eq $v) { continue }
            if (-not $firstField) { [void]$sb.Append(',') }
            $firstField = $false
            [void]$sb.Append('"').Append($k).Append('":')
            if ($k -eq 'process') { [void]$sb.Append([string]$v) } else { [void]$sb.Append((ConvertTo-AgyJsonString ([string]$v))) }
        }
        [void]$sb.Append('}')
    }
    [void]$sb.Append('],"seq":').Append($seq).Append(',"total":').Append($total).Append('}')
    return $sb.ToString()
}

# ============================================================================
# agy 세션 (agy_sessions): "사람이 붙인 세션 이름" <-> agy 의 conversation_id
# ============================================================================

# 이름을 키로 바꾼다(예전의 세션 파일 이름 규칙 그대로: 금지 문자는 _, 앞뒤 공백 제거, 100자). 키는 대소문자를 가리지 않는다.
function Get-AgySessionKey([string]$Name) {
    $safe = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = '_' }
    if ($safe.Length -gt 100) { $safe = $safe.Substring(0, 100) }
    return $safe
}

function Get-AgySessionRow($Db, [string]$Key) {
    $rows = $Db.Query('SELECT * FROM agy_sessions WHERE name=?', [object[]]@($Key))
    if ($rows.Count -eq 0) { return $null }
    $r = $rows[0]
    return [pscustomobject][ordered]@{
        name            = [string]$r['name']
        conversation_id = [string]$r['conversation_id']
        cwd             = @(ConvertFrom-AgyJsonArray ([string]$r['cwd']))
        model           = [string]$r['model']
        created_at      = [string]$r['created_at']
        last_used_at    = [string]$r['last_used_at']
        turn_count      = [int]$r['turn_count']
    }
}

function Set-AgySessionRow($Db, [string]$Key, [string]$ConversationId, $Cwd, [string]$Model, [string]$CreatedAt, [string]$LastUsedAt, [int]$TurnCount) {
    [void]$Db.Execute('INSERT INTO agy_sessions (name, conversation_id, cwd, model, created_at, last_used_at, turn_count) VALUES (?,?,?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET conversation_id=excluded.conversation_id, cwd=excluded.cwd, model=excluded.model, created_at=excluded.created_at, last_used_at=excluded.last_used_at, turn_count=excluded.turn_count',
        [object[]]@($Key, $ConversationId, (ConvertTo-AgyJsonArray $Cwd), $Model, $CreatedAt, $LastUsedAt, $TurnCount))
}

# 경로로 부르는 세션 읽기. DB 가 없으면 $null.
function Get-AgySession([string]$DbPath, [string]$Name) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return $null }
    $db = Open-AgyDb $DbPath
    try { return (Get-AgySessionRow $db (Get-AgySessionKey $Name)) } finally { $db.Dispose() }
}

# 세션의 최근 "성공한" 위임(질문·답)을 오래된 것부터 돌려준다(모델 승격 때 새 대화에 이전 맥락을 글로 붙이려는 용도). 세션 이름은 대소문자를 가리지 않는다.
# 반환: @(@{ TaskId; Timestamp; Model; Question; Answer }). DB 가 없거나 기록이 없으면 빈 배열.
function Get-AgySessionHistory([string]$DbPath, [string]$Name, [int]$Limit = 2) {
    if (-not $Name -or $Limit -lt 1 -or -not (Test-Path -LiteralPath $DbPath)) { return @() }
    $db = Open-AgyDb $DbPath
    try {
        $rows = $db.Query("SELECT task_id, timestamp, model, question, answer FROM tasks WHERE session = ? COLLATE NOCASE AND status = 'OK' AND answer IS NOT NULL ORDER BY timestamp DESC, task_id DESC LIMIT ?", [object[]]@($Name, [long]$Limit))
        $out = @()
        foreach ($r in $rows) {
            $out += ,@{ TaskId = [string]$r['task_id']; Timestamp = [string]$r['timestamp']; Model = [string]$r['model']; Question = [string]$r['question']; Answer = [string]$r['answer'] }
        }
        [array]::Reverse($out)
        return @($out)
    } finally { $db.Dispose() }
}

function Remove-AgySessionsOlderThan([string]$DbPath, [int]$Days) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return 0 }
    $cut = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd HH:mm:ss')
    $db = Open-AgyDb $DbPath
    try { return $db.Execute('DELETE FROM agy_sessions WHERE last_used_at < ?', [object[]]@($cut)) } finally { $db.Dispose() }
}

# ============================================================================
# meta
# ============================================================================

function Get-AgyMeta($Db, [string]$Key) {
    $rows = $Db.Query('SELECT value FROM meta WHERE key=?', [object[]]@($Key))
    if ($rows.Count -eq 0) { return $null }
    return [string]$rows[0]['value']
}

function Set-AgyMeta($Db, [string]$Key, [string]$Value) {
    [void]$Db.Execute('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', [object[]]@($Key, $Value))
}

# ============================================================================
# claude_usage (위임별 Claude 토큰 집계 캐시)
# ============================================================================

function Get-ClaudeUsageCache($Db, [string]$TaskId) {
    if (-not $TaskId) { return $null }
    $rows = $Db.Query('SELECT json, src_mtime, computed_at FROM claude_usage WHERE task_id = ?', [object[]]@($TaskId))
    if ($rows.Count -eq 0) { return $null }
    $r = $rows[0]
    return @{
        json        = if ($null -ne $r['json']) { [string]$r['json'] } else { "" }
        src_mtime   = if ($null -ne $r['src_mtime']) { [string]$r['src_mtime'] } else { "" }
        computed_at = if ($null -ne $r['computed_at']) { [string]$r['computed_at'] } else { "" }
    }
}

function Get-ClaudeUsageCacheMap($Db) {
    $map = @{}
    foreach ($r in @($Db.Query('SELECT task_id, json, src_mtime, computed_at FROM claude_usage', $null))) {
        $tid = [string]$r['task_id']
        if (-not $tid) { continue }
        $map[$tid] = @{
            json        = if ($null -ne $r['json']) { [string]$r['json'] } else { "" }
            src_mtime   = if ($null -ne $r['src_mtime']) { [string]$r['src_mtime'] } else { "" }
            computed_at = if ($null -ne $r['computed_at']) { [string]$r['computed_at'] } else { "" }
        }
    }
    return $map
}

function Set-ClaudeUsageCache($Db, [string]$TaskId, [string]$Json, [string]$SrcMtime, [string]$ComputedAt) {
    if (-not $TaskId) { return }
    [void]$Db.Execute(
        'INSERT INTO claude_usage (task_id, json, src_mtime, computed_at) VALUES (?, ?, ?, ?) ON CONFLICT(task_id) DO UPDATE SET json=excluded.json, src_mtime=excluded.src_mtime, computed_at=excluded.computed_at',
        [object[]]@($TaskId, $Json, $SrcMtime, $ComputedAt)
    )
}

# ============================================================================
# task_limits (완료된 위임별 한도 추정 스냅샷 — 최초 1회만 저장, 덮어쓰지 않음)
# ============================================================================

function Get-TaskLimitsSnapshot($Db, [string]$TaskId) {
    if (-not $TaskId) { return $null }
    $rows = $Db.Query('SELECT json, captured_at FROM task_limits WHERE task_id = ?', [object[]]@($TaskId))
    if ($rows.Count -eq 0) { return $null }
    $r = $rows[0]
    return @{
        json        = if ($null -ne $r['json']) { [string]$r['json'] } else { "" }
        captured_at = if ($null -ne $r['captured_at']) { [string]$r['captured_at'] } else { "" }
    }
}

function Get-TaskLimitsMap($Db) {
    $map = @{}
    foreach ($r in @($Db.Query('SELECT task_id, json, captured_at FROM task_limits', $null))) {
        $tid = [string]$r['task_id']
        if (-not $tid) { continue }
        $map[$tid] = @{
            json        = if ($null -ne $r['json']) { [string]$r['json'] } else { "" }
            captured_at = if ($null -ne $r['captured_at']) { [string]$r['captured_at'] } else { "" }
        }
    }
    return $map
}

function Set-TaskLimitsSnapshot($Db, [string]$TaskId, [string]$Json, [string]$CapturedAt) {
    if (-not $TaskId -or -not $Json) { return $false }
    $n = $Db.Execute(
        'INSERT OR IGNORE INTO task_limits (task_id, json, captured_at) VALUES (?, ?, ?)',
        [object[]]@($TaskId, $Json, $CapturedAt)
    )
    return ($n -gt 0)
}

# ============================================================================
# task_quota (위임 완료 직후 실측한 agy 남은 한도 — 최초 1회만 저장, 덮어쓰지 않음)
# ============================================================================

function Save-TaskQuota($Db, [string]$TaskId, [string]$MeasuredAt, $FiveUsed, [string]$FiveReset, $WeekUsed, [string]$WeekReset, $Concurrent = 0) {
    if (-not $TaskId) { return $false }
    $fu = if ($null -ne $FiveUsed) { [double]$FiveUsed } else { $null }
    $fr = if ($FiveReset) { [string]$FiveReset } else { $null }
    $wu = if ($null -ne $WeekUsed) { [double]$WeekUsed } else { $null }
    $wr = if ($WeekReset) { [string]$WeekReset } else { $null }
    $conc = if ($Concurrent -is [bool]) { if ($Concurrent) { 1 } else { 0 } } else { if ([int]$Concurrent -ne 0) { 1 } else { 0 } }

    $owned = $false
    $conn = $Db
    if ($Db -is [string]) {
        $conn = Open-AgyDb ([string]$Db)
        $owned = $true
    }
    try {
        $n = $conn.Execute(
            'INSERT OR IGNORE INTO task_quota (task_id, measured_at, five_used, five_reset, week_used, week_reset, concurrent) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [object[]]@($TaskId, $MeasuredAt, $fu, $fr, $wu, $wr, $conc)
        )
        return ($n -gt 0)
    } finally {
        if ($owned -and $null -ne $conn) { $conn.Dispose() }
    }
}

function Get-TaskQuotaMap($Db) {
    $map = @{}
    $owned = $false
    $conn = $Db
    if ($Db -is [string]) {
        $p = [string]$Db
        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { return $map }
        $conn = Open-AgyDb $p
        $owned = $true
    }
    try {
        foreach ($r in @($conn.Query('SELECT task_id, measured_at, five_used, five_reset, week_used, week_reset, concurrent FROM task_quota', $null))) {
            $tid = [string]$r['task_id']
            if (-not $tid) { continue }
            $map[$tid] = @{
                task_id     = $tid
                measured_at = if ($null -ne $r['measured_at']) { [string]$r['measured_at'] } else { "" }
                five_used   = if ($null -ne $r['five_used']) { [double]$r['five_used'] } else { $null }
                five_reset  = if ($null -ne $r['five_reset']) { [string]$r['five_reset'] } else { "" }
                week_used   = if ($null -ne $r['week_used']) { [double]$r['week_used'] } else { $null }
                week_reset  = if ($null -ne $r['week_reset']) { [string]$r['week_reset'] } else { "" }
                concurrent  = if ($null -ne $r['concurrent']) { [int]$r['concurrent'] } else { 0 }
            }
        }
        return $map
    } finally {
        if ($owned -and $null -ne $conn) { $conn.Dispose() }
    }
}

# ============================================================================
# task_models (위임별 실제 실행 모델 토큰 — 최초 1회만 저장, 덮어쓰지 않음)
# ============================================================================

function Save-TaskModels($Db, [string]$TaskId, $Models) {
    if (-not $TaskId -or $null -eq $Models) { return $false }
    $items = New-Object System.Collections.ArrayList
    foreach ($m in @($Models)) {
        if ($null -eq $m) { continue }
        $getVal = {
            param($obj, [string]$k1, [string]$k2)
            if ($obj -is [System.Collections.IDictionary]) {
                if ($obj.Contains($k1)) { return $obj[$k1] }
                if ($obj.Contains($k2)) { return $obj[$k2] }
            } elseif ($obj.PSObject) {
                $p1 = $obj.PSObject.Properties[$k1]
                if ($null -ne $p1) { return $p1.Value }
                $p2 = $obj.PSObject.Properties[$k2]
                if ($null -ne $p2) { return $p2.Value }
            }
            return $null
        }
        $name = [string](& $getVal $m 'Model' 'model')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $inp = [int64](& $getVal $m 'Input' 'input')
        $cac = [int64](& $getVal $m 'Cache' 'cache')
        $out = [int64](& $getVal $m 'Output' 'output')
        $thk = [int64](& $getVal $m 'Thinking' 'thinking')
        $stp = [int](& $getVal $m 'Steps' 'steps')
        [void]$items.Add([ordered]@{ model = $name.Trim(); input = $inp; cache = $cac; output = $out; thinking = $thk; steps = $stp })
    }
    if ($items.Count -eq 0) { return $false }

    $owned = $false
    $conn = $Db
    if ($Db -is [string]) {
        $conn = Open-AgyDb ([string]$Db)
        $owned = $true
    }
    try {
        $existing = @($conn.Query('SELECT 1 AS has_row FROM task_models WHERE task_id = ? LIMIT 1', [object[]]@($TaskId)))
        if ($existing.Count -gt 0) { return $false }
        $inserted = Invoke-AgyDbTransaction $conn {
            $cnt = 0
            foreach ($it in $items) {
                $n = $conn.Execute(
                    'INSERT OR IGNORE INTO task_models (task_id, model, input, cache, output, thinking, steps) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [object[]]@($TaskId, $it.model, $it.input, $it.cache, $it.output, $it.thinking, $it.steps)
                )
                if ($n -gt 0) { $cnt++ }
            }
            return ($cnt -gt 0)
        }
        return [bool]$inserted
    } finally {
        if ($owned -and $null -ne $conn) { $conn.Dispose() }
    }
}

# 위임 한 건의 컨텍스트 크기(그 호출에서 마지막 턴이 모델에 보낸 입력 = 캐시 밖 입력 + 캐시 읽기)를 tasks.context_tokens 에 저장한다.
# 비어 있을 때만 쓰고(덮어쓰지 않음) 0 이하 값은 저장하지 않는다. 저장했으면 true.
function Save-TaskContext($Db, [string]$TaskId, $Context) {
    if (-not $TaskId -or $null -eq $Context) { return $false }
    $ctx = [int64]0
    if (-not [int64]::TryParse([string]$Context, [ref]$ctx) -or $ctx -le 0) { return $false }
    $owned = $false
    $conn = $Db
    if ($Db -is [string]) {
        $conn = Open-AgyDb ([string]$Db)
        $owned = $true
    }
    try {
        $n = $conn.Execute('UPDATE tasks SET context_tokens = ? WHERE task_id = ? AND context_tokens IS NULL', [object[]]@($ctx, $TaskId))
        return ($n -gt 0)
    } finally {
        if ($owned -and $null -ne $conn) { $conn.Dispose() }
    }
}

function ConvertTo-TaskModelEntry($Row) {
    $inp = if ($null -ne $Row['input']) { [int64]$Row['input'] } else { [int64]0 }
    $cac = if ($null -ne $Row['cache']) { [int64]$Row['cache'] } else { [int64]0 }
    $out = if ($null -ne $Row['output']) { [int64]$Row['output'] } else { [int64]0 }
    $thk = if ($null -ne $Row['thinking']) { [int64]$Row['thinking'] } else { [int64]0 }
    $stp = if ($null -ne $Row['steps']) { [int]$Row['steps'] } else { 0 }
    return [pscustomobject][ordered]@{
        model    = [string]$Row['model']
        input    = $inp
        cache    = $cac
        output   = $out
        thinking = $thk
        total    = ($inp + $out)
        steps    = $stp
    }
}

function Get-TaskModelsForIds($Db, [string[]]$TaskIds) {
    $map = @{}
    $uniqueIds = @($TaskIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($uniqueIds.Count -eq 0) { return $map }

    $owned = $false
    $conn = $Db
    if ($Db -is [string]) {
        $p = [string]$Db
        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { return $map }
        $conn = Open-AgyDb $p
        $owned = $true
    }
    try {
        $grouped = @{}
        for ($i = 0; $i -lt $uniqueIds.Count; $i += 500) {
            $chunk = @($uniqueIds[$i..([Math]::Min($i + 499, $uniqueIds.Count - 1))])
            $marks = (@($chunk | ForEach-Object { '?' }) -join ',')
            foreach ($r in @($conn.Query("SELECT task_id, model, input, cache, output, thinking, steps FROM task_models WHERE task_id IN ($marks)", [object[]]$chunk))) {
                $tid = [string]$r['task_id']
                if (-not $tid) { continue }
                if (-not $grouped.ContainsKey($tid)) { $grouped[$tid] = New-Object System.Collections.ArrayList }
                [void]$grouped[$tid].Add((ConvertTo-TaskModelEntry $r))
            }
        }
        foreach ($tid in $grouped.Keys) {
            $sorted = @($grouped[$tid] | Sort-Object -Property @{ Expression = { $_.total }; Descending = $true }, @{ Expression = { $_.model }; Ascending = $true })
            $map[$tid] = $sorted
        }
        return $map
    } finally {
        if ($owned -and $null -ne $conn) { $conn.Dispose() }
    }
}

function Get-TaskModelsMap($Db) {
    $map = @{}
    $owned = $false
    $conn = $Db
    if ($Db -is [string]) {
        $p = [string]$Db
        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { return $map }
        $conn = Open-AgyDb $p
        $owned = $true
    }
    try {
        $grouped = @{}
        foreach ($r in @($conn.Query('SELECT task_id, model, input, cache, output, thinking, steps FROM task_models', $null))) {
            $tid = [string]$r['task_id']
            if (-not $tid) { continue }
            if (-not $grouped.ContainsKey($tid)) { $grouped[$tid] = New-Object System.Collections.ArrayList }
            [void]$grouped[$tid].Add((ConvertTo-TaskModelEntry $r))
        }
        foreach ($tid in $grouped.Keys) {
            $sorted = @($grouped[$tid] | Sort-Object -Property @{ Expression = { $_.total }; Descending = $true }, @{ Expression = { $_.model }; Ascending = $true })
            $map[$tid] = $sorted
        }
        return $map
    } finally {
        if ($owned -and $null -ne $conn) { $conn.Dispose() }
    }
}
