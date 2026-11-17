# usage-stats.ps1
# 뷰어의 "실측 통계"(#/stats) 수집기입니다. Claude 대화 기록(~/.claude/projects/*/<세션>.jsonl)을 읽어 질문 한 건마다
# 직접/위임/대화, Claude 모델, 소요 시간, 토큰(입력 · 캐시 쓰기 · 캐시 읽기 · 출력)을 위임 DB 의 usage_questions 에 담고,
# 위임 기록(tasks) · 사유 기록(usage_notes, claude-meta 의 reason)을 붙입니다. 측정된 값만 다룹니다(예상 · 보정 · 환산 없음).
#
# 쓰는 법:
#   . usage-stats.ps1                      함수만 정의한다(뷰어 서버가 이렇게 부른다. agy-db.ps1 이 먼저 올라와 있어야 한다)
#   usage-stats.ps1 -UsageCollect -UsageDbPath <delegate.db> [-UsageProjectsDir <폴더>] [-UsageRuntimeDir <런타임 폴더>]
#                                          한 번 수집하고 끝난다(뷰어가 /api/usage-stats 요청 때 창 없는 별도 프로세스로 띄운다)
#
# 수집 규칙:
#   - 파일마다 지난번 위치(usage_files.offset)부터 이어 읽는다. 위치는 "그 파일의 마지막 질문이 시작한 줄"이라, 진행 중이던 질문은 다음 수집 때 다시 계산된다.
#   - 질문의 시작 = 사람이 보낸 메시지. 알림(<task-notification>) · 슬래시 명령 기록 · 압축 이어가기 · 다른 세션의 메시지 · 깨우기는 질문이 아니고 바로 앞 질문에 붙는다.
#   - 위임 = 그 질문 안에서 submit-task 를 부른 셸 명령의 결과에 "submitted: <작업ID>" 가 있다(또는 claude-meta 가 그 세션 · 그 시각의 작업을 가리킨다).
#     도구를 하나도 안 썼으면 chat, 나머지는 direct.
#   - 소요 시간 = 질문부터 마지막 이벤트까지에서 30분 넘게 빈 구간을 뺀 것. 총 토큰 = 입력 + 캐시 쓰기 + 출력(캐시 읽기는 따로).
#   - 질문 원문은 앞 60자만(붙여 넣은 내용 · 시스템 알림은 떼고, 전화번호 · 주민번호 모양은 * 로). 90일 지난 행은 지운다.
# 테스트: tests\delegate-agy\usage-stats.tests.ps1

param(
    [switch]$UsageCollect,
    [string]$UsageDbPath = "",
    [string]$UsageProjectsDir = "",
    [string]$UsageRuntimeDir = "",
    [int]$UsageRetentionDays = 90
)

# 이 파일이 있는 폴더(옆의 agy-models.ps1 로 agy 모델 이름을 짧게 만든다)
$script:AgyUsageScriptDir = $PSScriptRoot

$script:AgyUsageSource = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace AgyUsage
{
    public class Question
    {
        public string QTs = "", EndTs = "", Project = "", Model = "", Effort = "", Preview = "";
        public long Offset;
        public int Calls, DurSec;
        public long In, Cc, Cr, Out;
        public bool HasTool, Auto;
        public List<string> TaskIds = new List<string>();
        internal Dictionary<string, long[]> Usage = new Dictionary<string, long[]>();
        internal Dictionary<string, int> Models = new Dictionary<string, int>();
        internal Dictionary<string, int> Efforts = new Dictionary<string, int>();
        internal DateTime Last;
        internal double Dur;
    }

    public class ScanResult
    {
        public List<Question> Questions = new List<Question>();
        public long NextOffset;
    }

    public class Scanner
    {
        const double MaxGapSec = 1800;
        static readonly Regex Submitted = new Regex(@"(?m)^submitted: (claude_\d+_\d+)\s*$");
        static readonly Regex Reminder = new Regex(@"<system-reminder>.*?</system-reminder>", RegexOptions.Singleline);
        static readonly Regex Pasted = new Regex(@"<pasted_content[^>]*>.*?</pasted_content[^>]*>", RegexOptions.Singleline);
        static readonly Regex CmdName = new Regex(@"<command-name>(.*?)</command-name>", RegexOptions.Singleline);
        static readonly Regex CmdArgs = new Regex(@"<command-args>(.*?)</command-args>", RegexOptions.Singleline);
        static readonly Regex SchedName = new Regex(@"<scheduled-task[^>]*\bname=""([^""]*)""");
        static readonly Regex Space = new Regex(@"\s+");
        static readonly Regex Phone = new Regex(@"0\d{1,2}[\s.-]?\d{3,4}[\s.-]?\d{4}");
        static readonly Regex Rrn = new Regex(@"\d{6}[\s-]?[1-8]\d{6}");
        static readonly Regex Digit = new Regex(@"\d");
        static readonly string[] NotQuestionPrefix = new string[] {
            "<task-notification", "<local-command-", "<command-name", "<command-message", "<system-reminder",
            "<agent-message", "<teammate-message", "This session is being continued from a previous conversation" };

        readonly ScanResult result = new ScanResult();
        readonly HashSet<string> submitCalls = new HashSet<string>();
        Question cur;
        bool pendingAuto;

        static Dictionary<string, object> D(object o) { return o as Dictionary<string, object>; }
        static object V(Dictionary<string, object> d, string k) { object v; if (d != null && d.TryGetValue(k, out v)) { return v; } return null; }
        static string S(Dictionary<string, object> d, string k) { return V(d, k) as string; }
        static bool B(Dictionary<string, object> d, string k) { object v = V(d, k); return (v is bool) && (bool)v; }
        static long N(Dictionary<string, object> d, string k)
        {
            object v = V(d, k);
            if (v == null || v is string || v is bool) { return 0; }
            try { return Convert.ToInt64(v); } catch { return 0; }
        }
        static string Iso(DateTime t) { return t.ToString("yyyy-MM-ddTHH:mm:ss.fff", CultureInfo.InvariantCulture) + "Z"; }

        static string MaskDigits(Match m) { return Digit.Replace(m.Value, "*"); }

        // 질문 원문에서 미리보기(앞 60자)를 만든다. 사용자 글만 남기고 번호 모양은 가린다.
        public static string MakePreview(string text, bool hasImage)
        {
            string s = text ?? "";
            bool pasted = Pasted.IsMatch(s);
            s = Pasted.Replace(Reminder.Replace(s, " "), " ");
            string t = s.TrimStart();
            if (t.StartsWith("<scheduled-task", StringComparison.Ordinal))
            {
                Match sm = SchedName.Match(t);
                s = "예약 작업" + (sm.Success ? ": " + sm.Groups[1].Value : "");
            }
            else if (t.StartsWith("<command-", StringComparison.Ordinal))
            {
                Match nm = CmdName.Match(t);
                Match am = CmdArgs.Match(t);
                s = (nm.Success ? nm.Groups[1].Value : "") + " " + (am.Success ? am.Groups[1].Value : "");
            }
            s = Space.Replace(s, " ").Trim();
            s = Phone.Replace(Rrn.Replace(s, new MatchEvaluator(MaskDigits)), new MatchEvaluator(MaskDigits));
            if (s.Length > 60) { s = s.Substring(0, 60); }
            if (s.Length == 0) { s = hasImage ? "(이미지)" : (pasted ? "(붙여 넣은 내용)" : ""); }
            return s;
        }

        void Touch(DateTime ts)
        {
            if (cur == null) { return; }
            double gap = (ts - cur.Last).TotalSeconds;
            if (gap > 0 && gap <= MaxGapSec) { cur.Dur += gap; }
            if (ts > cur.Last) { cur.Last = ts; }
        }

        void Start(DateTime ts, long offset, string preview, bool auto, string cwd)
        {
            cur = new Question();
            cur.QTs = Iso(ts);
            cur.Last = ts;
            cur.Offset = offset;
            cur.Preview = preview;
            cur.Auto = auto;
            cur.Project = cwd ?? "";
            result.Questions.Add(cur);
            pendingAuto = false;
        }

        static void Finish(Question q)
        {
            int best = 0;
            foreach (KeyValuePair<string, long[]> u in q.Usage)
            {
                q.In += u.Value[0]; q.Cc += u.Value[1]; q.Cr += u.Value[2]; q.Out += u.Value[3];
            }
            foreach (KeyValuePair<string, int> m in q.Models)
            {
                if (m.Value > best) { best = m.Value; q.Model = m.Key; }
            }
            best = 0;
            foreach (KeyValuePair<string, int> e in q.Efforts)
            {
                if (e.Value > best) { best = e.Value; q.Effort = e.Key; }
            }
            q.Calls = q.Usage.Count;
            q.DurSec = (int)Math.Round(q.Dur);
            q.EndTs = Iso(q.Last);
        }

        static string FlattenText(object content)
        {
            string s = content as string;
            if (s != null) { return s; }
            IEnumerable list = content as IEnumerable;
            if (list == null) { return ""; }
            StringBuilder sb = new StringBuilder();
            foreach (object item in list)
            {
                Dictionary<string, object> b = D(item);
                if (b != null && S(b, "type") == "text") { sb.Append(S(b, "text")).Append('\n'); }
            }
            return sb.ToString();
        }

        // 사람이 보낸 질문인가. auto: 예약 작업 · 깨우기 · /loop 로 이어진 구간이라는 표시.
        static bool IsQuestion(Dictionary<string, object> o, string trimmed, bool hasImage, out bool auto)
        {
            auto = false;
            string okind = S(D(V(o, "origin")), "kind");
            string turnOrigin = S(o, "turnOrigin");
            if (trimmed.StartsWith("<scheduled-task", StringComparison.Ordinal)) { auto = true; return true; }
            if (V(o, "wakeupSource") != null || turnOrigin == "scheduled") { auto = true; return false; }
            if (trimmed.Contains("<command-name>/loop</command-name>")) { auto = true; }
            if (trimmed.StartsWith("[Request interrupted by user", StringComparison.Ordinal)) { return false; }
            if (okind != null) { return okind == "human"; }
            if (turnOrigin != null) { return !(turnOrigin == "task_notification" || turnOrigin == "peer" || turnOrigin == "host_synthetic"); }
            foreach (string p in NotQuestionPrefix) { if (trimmed.StartsWith(p, StringComparison.Ordinal)) { return false; } }
            if (trimmed.Length == 0 && !hasImage) { return false; }
            return true;
        }

        void Process(Dictionary<string, object> o, long offset)
        {
            string type = S(o, "type");
            if (type != "user" && type != "assistant") { return; }
            if (B(o, "isSidechain")) { return; }
            DateTime ts;
            if (!DateTime.TryParse(S(o, "timestamp"), CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out ts)) { return; }
            Dictionary<string, object> msg = D(V(o, "message"));
            if (msg == null) { return; }
            object content = V(msg, "content");

            if (type == "assistant")
            {
                string model = S(msg, "model");
                if (string.IsNullOrEmpty(model) || model == "<synthetic>" || B(o, "isApiErrorMessage")) { Touch(ts); return; }
                if (cur == null) { Start(ts, offset, "", pendingAuto, S(o, "cwd")); }
                Touch(ts);
                string id = S(msg, "id") ?? S(o, "uuid") ?? cur.Usage.Count.ToString();
                Dictionary<string, object> usage = D(V(msg, "usage"));
                long cc = N(usage, "cache_creation_input_tokens");
                if (cc == 0)
                {
                    Dictionary<string, object> ccd = D(V(usage, "cache_creation"));
                    cc = N(ccd, "ephemeral_5m_input_tokens") + N(ccd, "ephemeral_1h_input_tokens");
                }
                long[] now = new long[] { N(usage, "input_tokens"), cc, N(usage, "cache_read_input_tokens"), N(usage, "output_tokens") };
                long[] had;
                if (cur.Usage.TryGetValue(id, out had)) { for (int i = 0; i < 4; i++) { if (now[i] > had[i]) { had[i] = now[i]; } } }
                else
                {
                    cur.Usage[id] = now;
                    int c; cur.Models.TryGetValue(model, out c); cur.Models[model] = c + 1;
                    // 노력 단계: 이번 턴만 다르게 준 perTurnEffort 가 있으면 그것, 없으면 그 줄의 effort(Claude Code 2.1.x 의 대화 기록)
                    string effort = S(o, "perTurnEffort");
                    if (string.IsNullOrEmpty(effort)) { effort = S(o, "effort"); }
                    if (!string.IsNullOrEmpty(effort)) { effort = effort.Trim().ToLowerInvariant(); int ec; cur.Efforts.TryGetValue(effort, out ec); cur.Efforts[effort] = ec + 1; }
                }
                IEnumerable blocks = (content is string) ? null : content as IEnumerable;
                if (blocks != null)
                {
                    foreach (object item in blocks)
                    {
                        Dictionary<string, object> b = D(item);
                        if (b == null || S(b, "type") != "tool_use") { continue; }
                        cur.HasTool = true;
                        string name = S(b, "name");
                        if (name == "Bash" || name == "PowerShell")
                        {
                            string cmd = S(D(V(b, "input")), "command");
                            string tid = S(b, "id");
                            if (cmd != null && tid != null && cmd.IndexOf("submit-task", StringComparison.OrdinalIgnoreCase) >= 0) { submitCalls.Add(tid); }
                        }
                    }
                }
                return;
            }

            // user
            bool hasImage = false, hasToolResult = false;
            IEnumerable ublocks = (content is string) ? null : content as IEnumerable;
            if (ublocks != null)
            {
                foreach (object item in ublocks)
                {
                    Dictionary<string, object> b = D(item);
                    if (b == null) { continue; }
                    string bt = S(b, "type");
                    if (bt == "image") { hasImage = true; }
                    if (bt != "tool_result") { continue; }
                    hasToolResult = true;
                    string tid = S(b, "tool_use_id");
                    if (cur == null || tid == null || !submitCalls.Contains(tid)) { continue; }
                    foreach (Match m in Submitted.Matches(FlattenText(V(b, "content")).Replace("\r", "")))
                    {
                        string task = m.Groups[1].Value;
                        if (!cur.TaskIds.Contains(task)) { cur.TaskIds.Add(task); }
                    }
                }
            }
            if (hasToolResult || B(o, "isMeta") || B(o, "isCompactSummary")) { Touch(ts); return; }
            string text = FlattenText(content);
            bool auto;
            if (IsQuestion(o, text.TrimStart(), hasImage, out auto))
            {
                Start(ts, offset, MakePreview(text, hasImage), auto, S(o, "cwd"));
                return;
            }
            if (auto) { if (cur != null) { cur.Auto = true; } else { pendingAuto = true; } }
            Touch(ts);
        }

        // 파일을 offset(줄의 시작)부터 읽어 질문들을 돌려준다. 끝이 줄바꿈으로 닫히지 않은 마지막 줄은 다음에 읽는다.
        public static ScanResult ScanFile(string path, long offset)
        {
            Scanner sc = new Scanner();
            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = int.MaxValue;
            js.RecursionLimit = 512;
            long lineStart = offset;
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (offset > fs.Length) { offset = 0; lineStart = 0; }
                fs.Seek(offset, SeekOrigin.Begin);
                byte[] buf = new byte[1 << 20];
                MemoryStream line = new MemoryStream();
                long pos = offset;
                int n;
                while ((n = fs.Read(buf, 0, buf.Length)) > 0)
                {
                    int start = 0;
                    for (int i = 0; i < n; i++)
                    {
                        if (buf[i] != 10) { continue; }
                        line.Write(buf, start, i - start);
                        if (line.Length > 2)
                        {
                            string text = Encoding.UTF8.GetString(line.GetBuffer(), 0, (int)line.Length);
                            if (text.IndexOf("\"type\":\"user\"", StringComparison.Ordinal) >= 0 || text.IndexOf("\"type\":\"assistant\"", StringComparison.Ordinal) >= 0)
                            {
                                try
                                {
                                    Dictionary<string, object> o = D(js.DeserializeObject(text));
                                    if (o != null) { sc.Process(o, lineStart); }
                                }
                                catch { }
                            }
                        }
                        line.SetLength(0);
                        start = i + 1;
                        lineStart = pos + i + 1;
                    }
                    line.Write(buf, start, n - start);
                    pos += n;
                }
            }
            foreach (Question q in sc.result.Questions) { Finish(q); }
            int count = sc.result.Questions.Count;
            sc.result.NextOffset = count > 0 ? sc.result.Questions[count - 1].Offset : lineStart;
            return sc.result;
        }
    }
}
'@

# 수집용 C# 을 컴파일해 불러온다(agy-db.ps1 의 Initialize-AgySqlite 와 같은 방식: 소스 해시가 든 이름으로 캐시 폴더에 두고 다음부터는 그대로 불러온다).
function Initialize-AgyUsageScanner {
    if ('AgyUsage.Scanner' -as [type]) { return }
    $src = $script:AgyUsageSource
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($src))).Replace('-', '')).Substring(0, 12).ToLowerInvariant()
    $sha.Dispose()
    $cacheDir = if ($env:AGY_DB_CACHE_DIR) { $env:AGY_DB_CACHE_DIR } else { Join-Path $env:USERPROFILE ".samjil\cache" }
    $dll = Join-Path $cacheDir ("agy-usage-{0}.dll" -f $hash)
    if (-not (Test-Path -LiteralPath $dll)) {
        try {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            $tmp = Join-Path $cacheDir ("agy-usage-{0}-{1}.tmp.dll" -f $hash, [Guid]::NewGuid().ToString("N"))
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies "System.Web.Extensions" -OutputAssembly $tmp -OutputType Library
            Copy-Item -LiteralPath $tmp -Destination $dll -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    if ('AgyUsage.Scanner' -as [type]) { return }
    if (Test-Path -LiteralPath $dll) {
        try { Add-Type -Path $dll; return } catch {}
    }
    Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies "System.Web.Extensions"
}

function Get-AgyUsageLockPath([string]$DbPath) { return (Join-Path (Split-Path $DbPath -Parent) "usage-collect.lock") }

# 지금 다른 프로세스가 수집 중인가(수집기는 잠금 파일을 혼자 열어 쥐고 있다).
function Test-AgyUsageCollecting([string]$DbPath) {
    $lockPath = Get-AgyUsageLockPath $DbPath
    if (-not (Test-Path -LiteralPath $lockPath)) { return $false }
    try {
        $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $fs.Dispose()
        return $false
    } catch { return $true }
}

function ConvertTo-AgyUsageIso([DateTime]$UtcTime) { return ($UtcTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture) + "Z") }

# 위임 작업 ID 들의 agy 쪽 값(모델 · 토큰 · 처리 시간 · 상태별 건수)을 tasks 에서 모은다. 아직 안 끝난 작업이 있으면 $null(다음 수집 때 다시 본다).
function Get-AgyUsageTaskSummary($Db, [string[]]$TaskIds) {
    $models = New-Object System.Collections.ArrayList
    $tokens = [long]0; $sec = [long]0; $ok = 0; $fail = 0; $cancel = 0
    foreach ($id in $TaskIds) {
        $rows = $Db.Query("SELECT model, total_tokens, elapsed_sec, status FROM tasks WHERE task_id = ? AND answer IS NOT NULL", [object[]]@($id))
        if ($rows.Count -eq 0) { return $null }
        $r = $rows[0]
        $m = [string]$r['model']
        if ($m -and -not $models.Contains($m)) { [void]$models.Add($m) }
        $n = [long]0
        if ([long]::TryParse([string]$r['total_tokens'], [ref]$n)) { $tokens += $n }
        $d = [double]0
        if ([double]::TryParse([string]$r['elapsed_sec'], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $sec += [long][math]::Round($d) }
        $st = ([string]$r['status']).ToUpperInvariant()
        if ($st -eq 'OK') { $ok++ } elseif ($st -eq 'CANCELLED') { $cancel++ } else { $fail++ }
    }
    return @{ Models = ($models -join ', '); Tokens = $tokens; Sec = $sec; Ok = $ok; Fail = $fail; Cancel = $cancel }
}

# 한 번 수집한다. 다른 수집이 돌고 있으면 아무것도 하지 않는다. 돌려주는 값: @{ Ran; Files; Questions }
function Invoke-AgyUsageCollect([string]$DbPath, [string]$ProjectsDir, [string]$RuntimeDir = "", [int]$RetentionDays = 90) {
    $out = @{ Ran = $false; Files = 0; Questions = 0 }
    $lockPath = Get-AgyUsageLockPath $DbPath
    $lockDir = Split-Path $lockPath -Parent
    if (-not (Test-Path -LiteralPath $lockDir)) { New-Item -ItemType Directory -Force -Path $lockDir | Out-Null }
    $lock = $null
    try { $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) } catch { return $out }
    $db = $null
    try {
        Initialize-AgyUsageScanner
        $db = Open-AgyDb $DbPath
        $out.Ran = $true
        $cutUtc = [DateTime]::UtcNow.AddDays(-$RetentionDays)
        $cutIso = ConvertTo-AgyUsageIso $cutUtc

        # 1) 대화 기록: 바뀐 파일만, 지난번 위치부터
        $known = @{}
        foreach ($r in $db.Query("SELECT path, offset, mtime FROM usage_files", $null)) { $known[[string]$r['path']] = @{ Offset = [long]$r['offset']; Stamp = [string]$r['mtime'] } }
        $files = @()
        if ($ProjectsDir -and (Test-Path -LiteralPath $ProjectsDir -PathType Container)) {
            $files = @(Get-ChildItem -LiteralPath $ProjectsDir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter "*.jsonl" -File -ErrorAction SilentlyContinue } |
                Where-Object { $_.LastWriteTimeUtc -ge $cutUtc } | Sort-Object LastWriteTimeUtc -Descending)
        }
        $seen = @{}
        foreach ($f in $files) {
            $seen[$f.FullName] = $true
            $stamp = "{0}/{1}" -f $f.LastWriteTimeUtc.Ticks, $f.Length
            $k = $known[$f.FullName]
            if ($k -and $k.Stamp -eq $stamp) { continue }
            $offset = if ($k -and $k.Offset -le $f.Length) { [long]$k.Offset } else { [long]0 }
            $res = $null
            try { $res = [AgyUsage.Scanner]::ScanFile($f.FullName, $offset) } catch { continue }
            $session = $f.BaseName
            $filePath = $f.FullName
            $kept = @($res.Questions | Where-Object { $_.QTs -ge $cutIso })
            Invoke-AgyDbTransaction $db {
                if ($offset -eq 0) { [void]$db.Execute("DELETE FROM usage_questions WHERE session = ?", [object[]]@($session)) }
                elseif ($res.Questions.Count -gt 0) { [void]$db.Execute("DELETE FROM usage_questions WHERE session = ? AND q_ts >= ?", [object[]]@($session, [string]$res.Questions[0].QTs)) }
                foreach ($q in $kept) {
                    $mode = if ($q.TaskIds.Count -gt 0) { 'delegate' } elseif ($q.HasTool) { 'direct' } else { 'chat' }
                    [void]$db.Execute("INSERT OR REPLACE INTO usage_questions (session, q_ts, project, mode, claude_model, claude_effort, dur_sec, calls, in_tokens, cc_tokens, cr_tokens, out_tokens, task_ids, preview, auto, end_ts) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        [object[]]@($session, [string]$q.QTs, [string]$q.Project, $mode, [string]$q.Model, [string]$q.Effort, [long]$q.DurSec, [long]$q.Calls, [long]$q.In, [long]$q.Cc, [long]$q.Cr, [long]$q.Out,
                            (@($q.TaskIds) -join ','), [string]$q.Preview, $(if ($q.Auto) { [long]1 } else { [long]0 }), [string]$q.EndTs))
                }
                [void]$db.Execute("INSERT OR REPLACE INTO usage_files (path, offset, mtime) VALUES (?,?,?)", [object[]]@($filePath, [long]$res.NextOffset, $stamp))
            } | Out-Null
            $out.Files++
            $out.Questions += $kept.Count
        }

        # 2) claude-meta(submit-task.ps1 이 남김): 서브에이전트가 제출해 대화 기록에서 못 찾은 위임을 세션 · 시각으로 붙이고, @reason 사유를 넣는다
        $metaDir = if ($RuntimeDir) { Join-Path $RuntimeDir "claude-meta" } else { "" }
        if ($metaDir -and (Test-Path -LiteralPath $metaDir -PathType Container)) {
            $owner = @{}
            foreach ($r in $db.Query("SELECT session, q_ts, task_ids FROM usage_questions WHERE task_ids IS NOT NULL AND task_ids <> ''", $null)) {
                foreach ($tid in ([string]$r['task_ids'] -split ',')) { if ($tid) { $owner[$tid] = @{ Session = [string]$r['session']; QTs = [string]$r['q_ts'] } } }
            }
            foreach ($mf in @(Get-ChildItem -LiteralPath $metaDir -Filter "claude_*.json" -File -ErrorAction SilentlyContinue)) {
                $tid = $mf.BaseName
                $meta = $null
                try { $meta = [System.IO.File]::ReadAllText($mf.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
                if (-not $meta) { continue }
                $own = $owner[$tid]
                $sess = ([string]$meta.session) -replace '[^A-Za-z0-9_-]', ''
                if (-not $own -and $sess -and $tid -match '^claude_(\d{9,11})_\d+$') {
                    $subIso = ConvertTo-AgyUsageIso ([DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).UtcDateTime.AddSeconds(1))
                    $hit = $db.Query("SELECT q_ts, task_ids FROM usage_questions WHERE session = ? AND q_ts <= ? ORDER BY q_ts DESC LIMIT 1", [object[]]@($sess, $subIso))
                    if ($hit.Count -gt 0) {
                        $ids = @(([string]$hit[0]['task_ids'] -split ',') | Where-Object { $_ }) + $tid
                        [void]$db.Execute("UPDATE usage_questions SET mode = 'delegate', task_ids = ?, agy_tokens = NULL WHERE session = ? AND q_ts = ?", [object[]]@(($ids -join ','), $sess, [string]$hit[0]['q_ts']))
                        $own = @{ Session = $sess; QTs = [string]$hit[0]['q_ts'] }
                        $owner[$tid] = $own
                    }
                }
                $reason = (([string]$meta.reason) -replace '\s+', ' ').Trim()
                if ($own -and $reason) {
                    if ($reason.Length -gt 200) { $reason = $reason.Substring(0, 200) }
                    [void]$db.Execute("UPDATE usage_questions SET reason = ? WHERE session = ? AND q_ts = ? AND (reason IS NULL OR reason <> ?)", [object[]]@($reason, $own.Session, $own.QTs, $reason))
                }
            }
        }

        # 3) 사유 기록(note-choice.ps1): 같은 세션에서 "질문 시작 <= 기록 시각 < 다음 질문 시작" 인 질문에 첫 기록을 붙인다
        [void]$db.Execute("UPDATE usage_questions SET reason = (SELECT n.reason FROM usage_notes n WHERE n.session = usage_questions.session AND n.noted_at >= usage_questions.q_ts AND n.noted_at < COALESCE((SELECT MIN(q2.q_ts) FROM usage_questions q2 WHERE q2.session = usage_questions.session AND q2.q_ts > usage_questions.q_ts), '9999') ORDER BY n.noted_at, n.id LIMIT 1) WHERE reason IS NULL AND session IN (SELECT DISTINCT session FROM usage_notes)", $null)

        # 4) 위임 행의 agy 쪽 값: 작업이 모두 끝난 행만 채운다
        foreach ($r in @($db.Query("SELECT session, q_ts, task_ids FROM usage_questions WHERE mode = 'delegate' AND agy_tokens IS NULL", $null))) {
            $sum = Get-AgyUsageTaskSummary $db @(([string]$r['task_ids'] -split ',') | Where-Object { $_ })
            if ($null -eq $sum) { continue }
            [void]$db.Execute("UPDATE usage_questions SET agy_models = ?, agy_tokens = ?, agy_sec = ?, task_ok = ?, task_fail = ?, task_cancel = ? WHERE session = ? AND q_ts = ?",
                [object[]]@([string]$sum.Models, [long]$sum.Tokens, [long]$sum.Sec, [long]$sum.Ok, [long]$sum.Fail, [long]$sum.Cancel, [string]$r['session'], [string]$r['q_ts']))
        }

        # 5) 보관: 90일 지난 행과, 더는 보지 않는 파일의 위치 기록을 지운다
        [void]$db.Execute("DELETE FROM usage_questions WHERE q_ts < ?", [object[]]@($cutIso))
        [void]$db.Execute("DELETE FROM usage_notes WHERE noted_at < ?", [object[]]@($cutIso))
        foreach ($p in @($known.Keys)) { if (-not $seen.ContainsKey($p)) { [void]$db.Execute("DELETE FROM usage_files WHERE path = ?", [object[]]@($p)) } }
        Set-AgyMeta $db 'usage_updated_at' (ConvertTo-AgyUsageIso ([DateTime]::UtcNow))
    } finally {
        if ($null -ne $db) { $db.Dispose() }
        if ($null -ne $lock) { $lock.Dispose() }
    }
    return $out
}

function Get-AgyUsageMedian($Values) {
    $list = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($list.Count -eq 0) { return $null }
    $mid = [int][math]::Floor($list.Count / 2)
    if ($list.Count % 2 -eq 1) { return [long]$list[$mid] }
    return [long][math]::Round(([double]$list[$mid - 1] + [double]$list[$mid]) / 2)
}

function Get-AgyUsageSum($Values) {
    $s = [long]0
    foreach ($v in @($Values)) { if ($null -ne $v) { $s += [long]$v } }
    return $s
}

# "claude-opus-5-5-20260101" -> "opus-5-5" (화면에 보일 짧은 이름)
function ConvertTo-AgyUsageShortModel([string]$Model) {
    return (([string]$Model) -replace '^claude-', '' -replace '-\d{8}$', '')
}

# Claude 모델 + 노력 단계: "opus-5-5" + "high" -> "opus-5-5 (high)". 노력을 모르면(예전 기록) 모델만.
function ConvertTo-AgyUsageClaudeLabel([string]$ShortModel, [string]$Effort) {
    if (-not $ShortModel) { return "" }
    if ($Effort -and $Effort.Trim()) { return ("{0} ({1})" -f $ShortModel, $Effort.Trim().ToLowerInvariant()) }
    return $ShortModel
}

# agy 모델 목록("gemini-4-hydrogen-medium, gemini-3.8-flash-low")을 짧은 이름으로: "hydrogen-medium, flash-low"(agy-models.ps1 의 Get-AgyModelShortName)
function ConvertTo-AgyUsageAgyShort([string]$Models) {
    if (-not $Models) { return "" }
    if (-not (Get-Command Get-AgyModelShortName -ErrorAction SilentlyContinue)) {
        $lib = Join-Path $script:AgyUsageScriptDir "agy-models.ps1"
        if ($script:AgyUsageScriptDir -and (Test-Path -LiteralPath $lib)) { . $lib }
    }
    $parts = @(([string]$Models -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (Get-Command Get-AgyModelShortName -ErrorAction SilentlyContinue) { $parts = @($parts | ForEach-Object { Get-AgyModelShortName $_ }) }
    return ($parts -join ', ')
}

# /api/usage-stats 의 본문(JSON 글자). 기간은 UTC 기록 시각끼리 비교하고, 일별 묶음만 이 PC 의 현지 날짜로 한다.
function Get-AgyUsageStatsJson([string]$DbPath, [int]$Days = 7, [bool]$Collecting = $false, [int]$RowLimit = 200) {
    if (@(7, 30, 90) -notcontains $Days) { $Days = 7 }
    $rows = @()
    $updated = $null
    $taskInfo = @{}
    if (Test-Path -LiteralPath $DbPath) {
        $db = Open-AgyDb $DbPath
        try {
            $updated = Get-AgyMeta $db 'usage_updated_at'
            $since = ConvertTo-AgyUsageIso ([DateTime]::UtcNow.AddDays(-$Days))
            $rows = @($db.Query("SELECT * FROM usage_questions WHERE q_ts >= ? ORDER BY q_ts DESC", [object[]]@($since)))
            # 위임 질문의 작업별 모델 · 결과 · 걸린 시간(화면에서 작업을 펼칠 때 칩으로 보인다)
            $allIds = New-Object System.Collections.ArrayList
            foreach ($r in $rows) { foreach ($tid in ([string]$r['task_ids'] -split ',')) { if ($tid) { [void]$allIds.Add($tid) } } }
            for ($i = 0; $i -lt $allIds.Count; $i += 500) {
                $chunk = @($allIds[$i..([math]::Min($i + 499, $allIds.Count - 1))])
                $marks = (@($chunk | ForEach-Object { '?' }) -join ',')
                foreach ($t in $db.Query("SELECT task_id, model, status, elapsed_sec FROM tasks WHERE task_id IN ($marks)", [object[]]$chunk)) {
                    $taskInfo[[string]$t['task_id']] = $t
                }
            }
        } finally { $db.Dispose() }
    }
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $rows) {
        $claude = ConvertTo-AgyUsageShortModel ([string]$r['claude_model'])
        $effort = if ($r.ContainsKey('claude_effort') -and $null -ne $r['claude_effort']) { [string]$r['claude_effort'] } else { "" }
        $claudeLabel = ConvertTo-AgyUsageClaudeLabel $claude $effort
        $agy = [string]$r['agy_models']
        $agyShort = ConvertTo-AgyUsageAgyShort $agy
        $combo = if ([string]$r['mode'] -eq 'delegate') { "{0} → {1}" -f $(if ($claudeLabel) { $claudeLabel } else { '?' }), $(if ($agyShort) { $agyShort } else { '?' }) } else { $(if ($claudeLabel) { $claudeLabel } else { '?' }) }
        $local = $null
        try { $local = ([DateTime]::Parse([string]$r['q_ts'], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)).ToLocalTime() } catch { $local = Get-Date }
        [void]$items.Add([pscustomobject][ordered]@{
            q_ts = [string]$r['q_ts']; end_ts = [string]$r['end_ts']; session = [string]$r['session']; project = [string]$r['project']
            mode = [string]$r['mode']; claude_model = $claude; claude_effort = $effort; claude_label = $claudeLabel; agy_models = $agy; combo = $combo
            dur_sec = [long]$r['dur_sec']; calls = [long]$r['calls']
            tokens = ([long]$r['in_tokens'] + [long]$r['cc_tokens'] + [long]$r['out_tokens']); cr_tokens = [long]$r['cr_tokens']
            agy_tokens = $(if ($null -eq $r['agy_tokens']) { $null } else { [long]$r['agy_tokens'] })
            agy_sec = $(if ($null -eq $r['agy_sec']) { $null } else { [long]$r['agy_sec'] })
            task_ids = [string[]]@(([string]$r['task_ids'] -split ',') | Where-Object { $_ })
            tasks = @(@(([string]$r['task_ids'] -split ',') | Where-Object { $_ }) | ForEach-Object {
                $ti = $taskInfo[$_]
                $sec = $null
                if ($ti) { $d = [double]0; if ([double]::TryParse([string]$ti['elapsed_sec'], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $sec = [long][math]::Round($d) } }
                [pscustomobject][ordered]@{
                    id = [string]$_
                    model = $(if ($ti -and $ti['model']) { [string]$ti['model'] } else { $null })
                    status = $(if ($ti -and $ti['status']) { ([string]$ti['status']).ToUpperInvariant() } else { $null })
                    sec = $sec
                }
            })
            task_ok = [long]$(if ($null -eq $r['task_ok']) { 0 } else { $r['task_ok'] }); task_fail = [long]$(if ($null -eq $r['task_fail']) { 0 } else { $r['task_fail'] }); task_cancel = [long]$(if ($null -eq $r['task_cancel']) { 0 } else { $r['task_cancel'] })
            reason = [string]$r['reason']; preview = [string]$r['preview']; auto = ([long]$r['auto'] -eq 1)
            day = $local.ToString("yyyy-MM-dd")
        })
    }

    $byMode = [ordered]@{}
    foreach ($mode in @('direct', 'delegate', 'chat')) {
        $set = @($items | Where-Object { $_.mode -eq $mode })
        $byMode[$mode] = [ordered]@{
            count = $set.Count
            dur_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.dur_sec })); dur_sum = (Get-AgyUsageSum @($set | ForEach-Object { $_.dur_sec }))
            tokens_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.tokens })); tokens_sum = (Get-AgyUsageSum @($set | ForEach-Object { $_.tokens }))
            cr_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.cr_tokens })); cr_sum = (Get-AgyUsageSum @($set | ForEach-Object { $_.cr_tokens }))
            agy_tokens_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.agy_tokens })); agy_tokens_sum = (Get-AgyUsageSum @($set | ForEach-Object { $_.agy_tokens }))
        }
    }
    $work = @($items | Where-Object { $_.mode -ne 'chat' })
    $summary = [ordered]@{
        total = $items.Count
        auto = @($items | Where-Object { $_.auto }).Count
        by_mode = $byMode
        tasks = [ordered]@{ ok = (Get-AgyUsageSum @($items | ForEach-Object { $_.task_ok })); fail = (Get-AgyUsageSum @($items | ForEach-Object { $_.task_fail })); cancel = (Get-AgyUsageSum @($items | ForEach-Object { $_.task_cancel })) }
        reason = [ordered]@{ with = @($work | Where-Object { $_.reason }).Count; total = $work.Count }
    }

    $byModel = New-Object System.Collections.ArrayList
    foreach ($g in @($items | Group-Object combo | Sort-Object Count -Descending)) {
        $set = @($g.Group)
        [void]$byModel.Add([ordered]@{
            combo = [string]$g.Name; mode = [string]$set[0].mode; count = $set.Count
            dur_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.dur_sec }))
            tokens_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.tokens }))
            agy_tokens_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.agy_tokens }))
        })
    }

    $perDay = @{}
    foreach ($it in $items) {
        if (-not $perDay.ContainsKey($it.day)) { $perDay[$it.day] = @{ direct = 0; delegate = 0; chat = 0 } }
        if ($perDay[$it.day].ContainsKey($it.mode)) { $perDay[$it.day][$it.mode]++ }
    }
    $daily = New-Object System.Collections.ArrayList
    $today = (Get-Date).Date
    for ($i = $Days - 1; $i -ge 0; $i--) {
        $key = $today.AddDays(-$i).ToString("yyyy-MM-dd")
        $d = if ($perDay.ContainsKey($key)) { $perDay[$key] } else { @{ direct = 0; delegate = 0; chat = 0 } }
        [void]$daily.Add([ordered]@{ date = $key; direct = $d.direct; delegate = $d.delegate; chat = $d.chat })
    }

    $result = [ordered]@{
        updated_at = $updated
        collecting = $Collecting
        days = $Days
        summary = $summary
        by_model = [object[]]$byModel.ToArray()
        daily = [object[]]$daily.ToArray()
        rows = [object[]]@($items | Select-Object -First $RowLimit)
    }
    return (ConvertTo-Json -InputObject $result -Depth 6 -Compress)
}

if ($UsageCollect) {
    try {
        if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "agy-db.ps1") }
        if (-not $UsageProjectsDir) { $UsageProjectsDir = if ($env:CLAUDE_PROJECTS_DIR) { $env:CLAUDE_PROJECTS_DIR } else { Join-Path $env:USERPROFILE ".claude\projects" } }
        $collected = Invoke-AgyUsageCollect $UsageDbPath $UsageProjectsDir $UsageRuntimeDir $UsageRetentionDays
        Write-Output ("collected: files={0} questions={1} ran={2}" -f $collected.Files, $collected.Questions, $collected.Ran)
        exit 0
    } catch {
        [Console]::Error.WriteLine("usage-stats: " + $_.Exception.Message)
        exit 1
    }
}
