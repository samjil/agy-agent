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
        // 본 세션에서 가장 컸던 한 호출의 컨텍스트(입력 + 캐시 쓰기 + 캐시 읽기)와 그 호출의 모델
        public long CtxTokens;
        public string CtxModel = "";
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
                long[] fin = cur.Usage[id];
                long ctxNow = fin[0] + fin[1] + fin[2];
                if (ctxNow > cur.CtxTokens) { cur.CtxTokens = ctxNow; cur.CtxModel = model; }
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
                    [void]$db.Execute("INSERT OR REPLACE INTO usage_questions (session, q_ts, project, mode, claude_model, claude_effort, dur_sec, calls, in_tokens, cc_tokens, cr_tokens, out_tokens, task_ids, preview, auto, end_ts, ctx_tokens, ctx_model) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        [object[]]@($session, [string]$q.QTs, [string]$q.Project, $mode, [string]$q.Model, [string]$q.Effort, [long]$q.DurSec, [long]$q.Calls, [long]$q.In, [long]$q.Cc, [long]$q.Cr, [long]$q.Out,
                            (@($q.TaskIds) -join ','), [string]$q.Preview, $(if ($q.Auto) { [long]1 } else { [long]0 }), [string]$q.EndTs,
                            $(if ($q.CtxTokens -gt 0) { [long]$q.CtxTokens } else { $null }), $(if ($q.CtxModel) { [string]$q.CtxModel } else { $null })))
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
                # 서브에이전트가 보낸 위임이면 서브에이전트 모델 · 노력 단계도 붙인다(한 질문에 여럿이면 먼저 기록된 값을 유지)
                $agentModel = ([string]$meta.agent_model).Trim()
                if ($own -and $agentModel) {
                    $agentEffort = ([string]$meta.agent_effort).Trim().ToLowerInvariant()
                    [void]$db.Execute("UPDATE usage_questions SET agent_model = ?, agent_effort = ? WHERE session = ? AND q_ts = ? AND (agent_model IS NULL OR agent_model = '')", [object[]]@($agentModel, $agentEffort, $own.Session, $own.QTs))
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

        # 4.5) 끝난 위임 중 task_models 가 비어 있고 대화 기록이 아직 남아 있는 건을 한 번씩 채운다(멱등)
        try { [void](Invoke-AgyTaskModelsBackfillWithDb $db) } catch {}

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

# agy 모델 목록("gemini-4-hydrogen-medium, gemini-4-carbon-high")을 짧은 이름으로: "hydrogen-medium, carbon-high"(agy-models.ps1 의 Get-AgyModelShortName)
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

# 이미 열린 DB 연결에서 task_models 가 없는 완료 작업을 대화 기록으로 채운다(세션당 한 번만 읽고 멱등).
function Invoke-AgyTaskModelsBackfillWithDb($Db, [string]$AgyHome = "") {
    $res = @{ Checked = 0; Backfilled = 0; Rows = 0 }
    if ($null -eq $Db) { return $res }
    if (-not (Get-Command New-AgyUsageState -ErrorAction SilentlyContinue)) {
        $progLib = Join-Path $script:AgyUsageScriptDir "agy-progress.ps1"
        if ($script:AgyUsageScriptDir -and (Test-Path -LiteralPath $progLib)) { try { . $progLib } catch {} }
    }
    if (-not (Get-Command New-AgyUsageState -ErrorAction SilentlyContinue) -or -not (Get-Command Save-TaskModels -ErrorAction SilentlyContinue)) {
        return $res
    }
    $homeDir = if ($AgyHome) {
        $AgyHome
    } elseif (Get-Command Get-AgyHomeDir -ErrorAction SilentlyContinue) {
        Get-AgyHomeDir
    } else {
        Join-Path $env:USERPROFILE ".gemini\antigravity-cli"
    }

    $sql = "SELECT t.task_id, t.session_id, t.timestamp, t.elapsed_sec, t.process FROM tasks t LEFT JOIN task_models tm ON tm.task_id = t.task_id WHERE t.answer IS NOT NULL AND t.session_id IS NOT NULL AND t.session_id <> '' AND (tm.task_id IS NULL OR t.context_tokens IS NULL)"
    $candidates = @($Db.Query($sql, $null))
    $res.Checked = $candidates.Count
    if ($candidates.Count -eq 0) { return $res }

    $bySess = @{}
    foreach ($c in $candidates) {
        $sid = [string]$c['session_id']
        if (-not $sid) { continue }
        if (-not $bySess.ContainsKey($sid)) { $bySess[$sid] = New-Object System.Collections.ArrayList }
        [void]$bySess[$sid].Add($c)
    }

    foreach ($sid in $bySess.Keys) {
        try {
            $tp = if (Get-Command Get-AgyTranscriptUsageFile -ErrorAction SilentlyContinue) {
                Get-AgyTranscriptUsageFile $homeDir $sid
            } else {
                $cand = Get-AgyTranscriptPath $homeDir $sid
                if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) { $cand } else { $null }
            }
            if (-not $tp) { continue }
            $state = New-AgyUsageState $tp
            Update-AgyUsageState $state
            foreach ($t in $bySess[$sid]) {
                try {
                    $tid = [string]$t['task_id']
                    if (-not $tid) { continue }
                    $range = if (Get-Command Resolve-AgyTaskStepRange -ErrorAction SilentlyContinue) {
                        Resolve-AgyTaskStepRange $state $t['process'] $t
                    } else {
                        @{ MinStep = 0; MaxStep = 0 }
                    }
                    $sum = Get-AgyUsageSummary $state $range.MaxStep $null $range.MinStep
                    if ($null -ne $sum) {
                        # 컨텍스트 크기(tasks.context_tokens)는 비어 있을 때만 채운다
                        if (Get-Command Save-TaskContext -ErrorAction SilentlyContinue) { try { [void](Save-TaskContext $Db $tid $sum.Context) } catch {} }
                        if (@($sum.ByModel).Count -gt 0 -and (Save-TaskModels $Db $tid $sum.ByModel)) {
                            $res.Backfilled++
                            $res.Rows += @($sum.ByModel).Count
                        }
                    }
                } catch {}
            }
        } catch {}
    }
    return $res
}

# DB 경로를 받아 task_models 를 백필한다(대화 기록이 남아 있는 완료 작업만, 멱등).
function Invoke-AgyTaskModelsBackfill([string]$DbPath, [string]$AgyHome = "") {
    $res = @{ Checked = 0; Backfilled = 0; Rows = 0 }
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return $res }
    $db = Open-AgyDb $DbPath
    try {
        return (Invoke-AgyTaskModelsBackfillWithDb $db $AgyHome)
    } finally {
        $db.Dispose()
    }
}

# /api/usage-stats 의 본문(JSON 글자). 기간은 UTC 기록 시각끼리 비교하고, 일별 묶음만 이 PC 의 현지 날짜로 한다.
# 모델 컨텍스트 창 크기: models.json 의 context_window({claude: {키: 토큰|null}, agy: {...}}) 를 models.local.json 이 키 단위로 덮어쓴다.
# 반환: @{ claude = @{키 = 토큰}; agy = @{키 = 토큰} } (null · 잘못된 값은 "모름" 이라 넣지 않는다)
function Get-AgyContextWindowConfig {
    $cfgDir = ""
    if ($env:AGY_MODELS_CONFIG_DIR) { $cfgDir = [string]$env:AGY_MODELS_CONFIG_DIR }
    else {
        $c1 = Join-Path (Split-Path (Split-Path $script:AgyUsageScriptDir -Parent) -Parent) "config"
        $c2 = Join-Path $env:USERPROFILE ".samjil\delegate-agy\config"
        if (Test-Path -LiteralPath (Join-Path $c1 "models.json") -PathType Leaf) { $cfgDir = $c1 }
        elseif (Test-Path -LiteralPath (Join-Path $c2 "models.json") -PathType Leaf) { $cfgDir = $c2 }
        else { $cfgDir = $c1 }
    }
    $res = @{ claude = @{}; agy = @{} }
    foreach ($name in @("models.json", "models.local.json")) {
        $p = Join-Path $cfgDir $name
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        try {
            $raw = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
            if (-not $raw.Trim()) { continue }
            $obj = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
            if ($null -eq $obj -or -not $obj.PSObject.Properties["context_window"] -or $null -eq $obj.context_window) { continue }
            foreach ($side in @("claude", "agy")) {
                $sp = $obj.context_window.PSObject.Properties[$side]
                if ($null -eq $sp -or $null -eq $sp.Value) { continue }
                foreach ($prop in $sp.Value.PSObject.Properties) {
                    $key = ([string]$prop.Name).Trim().ToLowerInvariant()
                    if (-not $key) { continue }
                    $v = $prop.Value
                    $n = [double]0
                    if ($null -eq $v -or $v -is [bool] -or -not [double]::TryParse(([string]$v).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n) -or $n -le 0) {
                        if ($res[$side].ContainsKey($key)) { [void]$res[$side].Remove($key) }
                        continue
                    }
                    $res[$side][$key] = [int64]$n
                }
            }
        } catch {}
    }
    return $res
}

# 모델 이름에 들어 있는 키 가운데 가장 긴 것의 창 크기. 없거나 모르면 default, 그것도 없으면 $null.
function Resolve-AgyContextWindow($Map, [string]$ModelId) {
    if ($null -eq $Map) { return $null }
    $id = ([string]$ModelId).ToLowerInvariant()
    $best = ""
    if ($id) { foreach ($k in $Map.Keys) { if ($k -ne "default" -and $id.Contains($k) -and $k.Length -gt $best.Length) { $best = $k } } }
    if ($best) { return [int64]$Map[$best] }
    if ($Map.ContainsKey("default")) { return [int64]$Map["default"] }
    return $null
}

function Get-AgyUsageStatsJson([string]$DbPath, [int]$Days = 7, [bool]$Collecting = $false, [int]$RowLimit = 200, [string]$RuntimeDir = "", [string]$ProjectsDir = "", [datetime]$NowUtc = [datetime]::MinValue) {
    if (@(7, 30, 90) -notcontains $Days) { $Days = 7 }
    $evalNow = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }

    if (-not (Get-Command Get-LimitsEstimateAtTime -ErrorAction SilentlyContinue)) {
        $leCands = @(
            (Join-Path (Split-Path (Split-Path (Split-Path $script:AgyUsageScriptDir -Parent) -Parent) -Parent) "viewer\limits-estimate.ps1"),
            (Join-Path $env:USERPROFILE ".samjil\viewer\limits-estimate.ps1")
        )
        foreach ($lc in $leCands) {
            if ($lc -and (Test-Path -LiteralPath $lc -PathType Leaf)) {
                try { . $lc; break } catch {}
            }
        }
    }

    $rows = @()
    $updated = $null
    $taskInfo = @{}
    $taskModelsMap = @{}
    $claudeUsageMap = @{}
    if (Test-Path -LiteralPath $DbPath) {
        $db = Open-AgyDb $DbPath
        try {
            $updated = Get-AgyMeta $db 'usage_updated_at'
            $since = ConvertTo-AgyUsageIso ($evalNow.AddDays(-$Days))
            $rows = @($db.Query("SELECT * FROM usage_questions WHERE q_ts >= ? ORDER BY q_ts DESC", [object[]]@($since)))
            # 위임 질문의 작업별 모델 · 결과 · 걸린 시간(화면에서 작업을 펼칠 때 칩으로 보인다)
            $allIds = New-Object System.Collections.ArrayList
            foreach ($r in $rows) { foreach ($tid in ([string]$r['task_ids'] -split ',')) { if ($tid) { [void]$allIds.Add($tid) } } }
            for ($i = 0; $i -lt $allIds.Count; $i += 500) {
                $chunk = @($allIds[$i..([math]::Min($i + 499, $allIds.Count - 1))])
                $marks = (@($chunk | ForEach-Object { '?' }) -join ',')
                foreach ($t in $db.Query("SELECT task_id, model, status, elapsed_sec, tried_models, input_tokens, output_tokens, total_tokens, timestamp, context_tokens FROM tasks WHERE task_id IN ($marks)", [object[]]$chunk)) {
                    $taskInfo[[string]$t['task_id']] = $t
                }
            }
            # 위임 카드가 보이는 Claude 토큰(본 세션 · 서브 합계)은 claude_usage 에 얼려 둔 JSON 을 쓴다
            for ($i = 0; $i -lt $allIds.Count; $i += 500) {
                $chunk = @($allIds[$i..([math]::Min($i + 499, $allIds.Count - 1))])
                $marks = (@($chunk | ForEach-Object { '?' }) -join ',')
                try {
                    foreach ($cu in $db.Query("SELECT task_id, json FROM claude_usage WHERE task_id IN ($marks)", [object[]]$chunk)) {
                        if ($cu['json']) { try { $claudeUsageMap[[string]$cu['task_id']] = (ConvertFrom-Json -InputObject ([string]$cu['json'])) } catch {} }
                    }
                } catch {}
            }
            if ($allIds.Count -gt 0 -and (Get-Command Get-TaskModelsForIds -ErrorAction SilentlyContinue)) {
                $taskModelsMap = Get-TaskModelsForIds $db ([string[]]@($allIds.ToArray()))
            }
        } finally { $db.Dispose() }
    }

    $agyInternal = $null
    if ((Test-Path -LiteralPath $DbPath) -and (Get-Command Get-AgyTaskEstimatesInternal -ErrorAction SilentlyContinue)) {
        try { $agyInternal = Get-AgyTaskEstimatesInternal $DbPath $RuntimeDir } catch { $agyInternal = $null }
    }
    $claudeInternal = $null
    if (($RuntimeDir -or $ProjectsDir) -and (Get-Command Get-ClaudeLimitsEstimatesInternal -ErrorAction SilentlyContinue)) {
        try { $claudeInternal = Get-ClaudeLimitsEstimatesInternal $RuntimeDir $ProjectsDir $evalNow } catch { $claudeInternal = $null }
    }
    $agyCostCfg = if (Get-Command Get-AgyQuotaCostConfig -ErrorAction SilentlyContinue) { Get-AgyQuotaCostConfig } else { $null }
    $claudeCostCfg = if (Get-Command Get-ClaudeQuotaCostConfig -ErrorAction SilentlyContinue) { Get-ClaudeQuotaCostConfig } else { $null }
    $ctxWinCfg = Get-AgyContextWindowConfig

    $parseTsUtc = {
        param([string]$s)
        if (-not $s) { return $null }
        $dt = [datetime]::MinValue
        if ($s -match '(Z|[+-]\d{2}:?\d{2})$') {
            $st = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
            if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $st, [ref]$dt)) { return $dt.ToUniversalTime() }
        } else {
            if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) { return $dt.ToUniversalTime() }
        }
        return $null
    }
    $tryDblVal = {
        param($v)
        if ($null -eq $v -or ($v -is [bool])) { return @{ Ok = $false; Val = 0.0 } }
        $d = 0.0
        if ([double]::TryParse(([string]$v).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            if (-not [double]::IsNaN($d) -and -not [double]::IsInfinity($d)) { return @{ Ok = $true; Val = $d } }
        }
        return @{ Ok = $false; Val = 0.0 }
    }
    $buildQuotaSide = {
        param([double]$CostUnits, [long]$RawTokens, $AtEst, $MeasuredObj = $null)
        if ($null -eq $AtEst) { return $null }
        $side = [ordered]@{
            raw_tokens = $RawTokens
            cost_units = [math]::Round($CostUnits, 2)
        }
        $hasAny = $false
        if ($null -ne $AtEst.five_hour -and $AtEst.five_hour.est_cost -gt 0) {
            $fhSrc = $AtEst.five_hour
            $fh = [ordered]@{
                est         = [long]$fhSrc.est
                est_cost    = [long]$fhSrc.est_cost
                five_points = [int]$fhSrc.five_points
                share_pct   = $(if ($CostUnits -gt 0.0) { [math]::Round((100.0 * $CostUnits / [double]$fhSrc.est_cost), 2) } else { 0.0 })
            }
            if ($fhSrc.Contains("initial") -and $fhSrc.initial) { $fh["initial"] = $true }
            if ($fhSrc.Contains("backfill") -and $fhSrc.backfill) {
                $fh["backfill"] = $true
                if ($fhSrc.Contains("estimated_at")) { $fh["estimated_at"] = [string]$fhSrc.estimated_at }
            }
            $side["five_hour"] = $fh
            $hasAny = $true
        }
        if ($null -ne $AtEst.weekly -and $AtEst.weekly.est_cost -gt 0) {
            $wkSrc = $AtEst.weekly
            $wk = [ordered]@{
                est       = [long]$wkSrc.est
                est_cost  = [long]$wkSrc.est_cost
                share_pct = $(if ($CostUnits -gt 0.0) { [math]::Round((100.0 * $CostUnits / [double]$wkSrc.est_cost), 2) } else { 0.0 })
            }
            if ($wkSrc.Contains("backfill") -and $wkSrc.backfill) {
                $wk["backfill"] = $true
                if ($wkSrc.Contains("estimated_at")) { $wk["estimated_at"] = [string]$wkSrc.estimated_at }
            }
            $side["weekly"] = $wk
            $hasAny = $true
        }
        if ($null -ne $AtEst.sessions) {
            $side["sessions"] = $AtEst.sessions
            $hasAny = $true
        }
        if ($null -ne $MeasuredObj) {
            $side["measured"] = $MeasuredObj
        }
        if (-not $hasAny) { return $null }
        return $side
    }

    $items = New-Object System.Collections.ArrayList
    foreach ($r in $rows) {
        $claude = ConvertTo-AgyUsageShortModel ([string]$r['claude_model'])
        $effort = if ($r.ContainsKey('claude_effort') -and $null -ne $r['claude_effort']) { [string]$r['claude_effort'] } else { "" }
        $claudeLabel = ConvertTo-AgyUsageClaudeLabel $claude $effort
        $agentRaw = if ($r.ContainsKey('agent_model') -and $null -ne $r['agent_model']) { [string]$r['agent_model'] } else { "" }
        $agent = ConvertTo-AgyUsageShortModel $agentRaw
        $agentEffort = if ($r.ContainsKey('agent_effort') -and $null -ne $r['agent_effort']) { [string]$r['agent_effort'] } else { "" }
        $agentLabel = ConvertTo-AgyUsageClaudeLabel $agent $agentEffort
        $agy = [string]$r['agy_models']
        $agyShort = ConvertTo-AgyUsageAgyShort $agy
        $combo = if ([string]$r['mode'] -eq 'delegate') {
            $left = if ($claudeLabel) { $claudeLabel } else { '?' }
            if ($agentLabel) { $left = "{0} › 서브 {1}" -f $left, $agentLabel }
            "{0} → {1}" -f $left, $(if ($agyShort) { $agyShort } else { '?' })
        } else { $(if ($claudeLabel) { $claudeLabel } else { '?' }) }
        # 각 위임 작업 중 한도 · 과부하로 앞 모델이 실패하고 다른 모델로 넘어간 경우, 그 실패한 모델의 짧은 이름 목록(성공한 작업만 센다)
        $failedList = New-Object System.Collections.ArrayList
        $rowTaskIds = @(([string]$r['task_ids'] -split ',') | Where-Object { $_ })
        foreach ($tid in $rowTaskIds) {
            $ti = $taskInfo[$tid]
            if ($ti -and ([string]$ti['status']).ToUpperInvariant() -eq 'OK' -and $ti['tried_models']) {
                $rawChain = @(([string]$ti['tried_models']) -split '\s*->\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if ($rawChain.Count -gt 1) {
                    $used = [string]$ti['model']
                    $usedIdx = $rawChain.IndexOf($used)
                    $earlier = if ($usedIdx -gt 0) {
                        $rawChain[0..($usedIdx - 1)]
                    } elseif ($usedIdx -lt 0) {
                        $rawChain[0..($rawChain.Count - 2)]
                    } else {
                        @()
                    }
                    foreach ($em in $earlier) {
                        $sn = ConvertTo-AgyUsageAgyShort $em
                        if ($sn) { [void]$failedList.Add($sn) }
                    }
                }
            }
        }
        $agyFailed = [string[]]@($failedList | Select-Object -Unique)
        $qRealMap = @{}
        foreach ($tid in $rowTaskIds) {
            if ($taskModelsMap.ContainsKey($tid)) {
                foreach ($tm in @($taskModelsMap[$tid])) {
                    $mName = [string]$tm.model
                    if (-not $mName) { continue }
                    if (-not $qRealMap.ContainsKey($mName)) {
                        $qRealMap[$mName] = @{ model = $mName; input = [int64]0; cache = [int64]0; output = [int64]0; thinking = [int64]0; total = [int64]0; steps = 0 }
                    }
                    $qr = $qRealMap[$mName]
                    $qr.input += [int64]$tm.input
                    $qr.cache += [int64]$tm.cache
                    $qr.output += [int64]$tm.output
                    $qr.thinking += [int64]$tm.thinking
                    $qr.total += ([int64]$tm.input + [int64]$tm.output)
                    $qr.steps += [int]$tm.steps
                }
            }
        }
        $qRealModels = @($qRealMap.Values | Sort-Object -Property @{ Expression = { $_.total }; Descending = $true }, @{ Expression = { $_.model }; Ascending = $true } | ForEach-Object {
            [pscustomobject][ordered]@{
                model    = [string]$_.model
                short    = (ConvertTo-AgyUsageAgyShort ([string]$_.model))
                total    = [int64]$_.total
                input    = [int64]$_.input
                cache    = [int64]$_.cache
                output   = [int64]$_.output
                thinking = [int64]$_.thinking
                steps    = [int]$_.steps
            }
        })

        $qIn = [long]$r['in_tokens']; $qCc = [long]$r['cc_tokens']; $qCr = [long]$r['cr_tokens']; $qOut = [long]$r['out_tokens']
        $qClaudeTok = $qIn + $qCc + $qOut
        $qClaudeModels = if ($qClaudeTok -gt 0) {
            @([pscustomobject][ordered]@{
                model = [string]$r['claude_model']
                short = $(if ($claude) { $claude } else { 'Claude' })
                total = [int64]$qClaudeTok
            })
        } else { @() }

        # 질문 하나의 모든 토큰(위임 카드와 같은 항목): agy 는 작업별 실제 모델 합, Claude 는 본 세션 · 서브
        $sumU = { param($List) $o = [ordered]@{ total = [int64]0; calls = [int64]0; input = [int64]0; cache_write = [int64]0; cache_read = [int64]0; output = [int64]0 }
            foreach ($u in @($List)) { if ($null -eq $u) { continue }
                foreach ($pair in @(@('total','total'), @('calls','calls'), @('input','in'), @('cache_write','cache_write'), @('cache_read','cache_read'), @('output','out'))) {
                    $pv = $u.PSObject.Properties[$pair[1]]; if ($null -ne $pv -and $null -ne $pv.Value) { $o[$pair[0]] += [int64]$pv.Value } } }
            return $o }
        $tkMainList = New-Object System.Collections.ArrayList; $tkSubList = New-Object System.Collections.ArrayList
        foreach ($tid in $rowTaskIds) {
            if (-not $claudeUsageMap.ContainsKey($tid)) { continue }
            $cuo = $claudeUsageMap[$tid]
            if ($null -ne $cuo.PSObject.Properties['main'] -and $null -ne $cuo.main) { [void]$tkMainList.Add($cuo.main) }
            if ($null -ne $cuo.PSObject.Properties['sub'] -and $null -ne $cuo.sub) { [void]$tkSubList.Add($cuo.sub) }
        }
        $tkMain = if ($tkMainList.Count -gt 0) { & $sumU $tkMainList } else {
            [ordered]@{ total = [int64]($qIn + $qCc + $qOut); calls = [int64]$r['calls']; input = [int64]$qIn; cache_write = [int64]$qCc; cache_read = [int64]$qCr; output = [int64]$qOut } }
        $tkSub = if ($tkSubList.Count -gt 0) { & $sumU $tkSubList } else { $null }
        $tkHasSub = ($null -ne $tkSub -and ($tkSub.total -gt 0 -or $tkSub.calls -gt 0))
        # 컨텍스트: 본 세션은 수집기가 질문마다 저장한 값, 서브는 위임별 Claude 토큰 JSON 의 가장 큰 호출
        $mkCtx = { param([int64]$Tok, [string]$Model, $WinMap)
            if ($Tok -le 0) { return $null }
            return [pscustomobject][ordered]@{ tokens = $Tok; model = $Model; window = (Resolve-AgyContextWindow $WinMap $Model) } }
        $ctxMainTok = [int64]0
        if ($null -ne $r['ctx_tokens'] -and -not ($r['ctx_tokens'] -is [System.DBNull])) { [int64]::TryParse([string]$r['ctx_tokens'], [ref]$ctxMainTok) | Out-Null }
        $ctxMainModel = if ($null -ne $r['ctx_model'] -and -not ($r['ctx_model'] -is [System.DBNull])) { [string]$r['ctx_model'] } else { "" }
        $ctxSubTok = [int64]0; $ctxSubModel = ""
        foreach ($sj in $tkSubList) {
            $sc = $sj.PSObject.Properties['ctx']
            if ($null -ne $sc -and $null -ne $sc.Value -and [int64]$sc.Value -gt $ctxSubTok) {
                $ctxSubTok = [int64]$sc.Value
                $sm = $sj.PSObject.Properties['ctx_model']; $ctxSubModel = if ($null -ne $sm -and $null -ne $sm.Value) { [string]$sm.Value } else { "" }
            }
        }
        $tkClaudeCtx = [pscustomobject][ordered]@{ main = (& $mkCtx $ctxMainTok $ctxMainModel $ctxWinCfg.claude); sub = (& $mkCtx $ctxSubTok $ctxSubModel $ctxWinCfg.claude) }
        $tkClaude = [ordered]@{
            context     = $tkClaudeCtx
            total       = [int64]($tkMain.total + $(if ($tkHasSub) { $tkSub.total } else { 0 }))
            input       = [int64]($tkMain.input + $(if ($tkHasSub) { $tkSub.input } else { 0 }))
            cache_write = [int64]($tkMain.cache_write + $(if ($tkHasSub) { $tkSub.cache_write } else { 0 }))
            cache_read  = [int64]($tkMain.cache_read + $(if ($tkHasSub) { $tkSub.cache_read } else { 0 }))
            output      = [int64]($tkMain.output + $(if ($tkHasSub) { $tkSub.output } else { 0 }))
            main        = [pscustomobject]$tkMain
            sub         = $(if ($tkHasSub) { [pscustomobject]$tkSub } else { $null })
        }
        $tkAgyModels = @($qRealModels | ForEach-Object { [pscustomobject][ordered]@{ model = $_.model; input = $_.input; cache = $_.cache; output = $_.output; thinking = $_.thinking; total = $_.total } })
        $tkAgyIn = [int64]0; $tkAgyCache = [int64]0; $tkAgyOut = [int64]0; $tkAgyThink = [int64]0
        foreach ($m in $tkAgyModels) { $tkAgyIn += $m.input; $tkAgyCache += $m.cache; $tkAgyOut += $m.output; $tkAgyThink += $m.thinking }
        if ($tkAgyModels.Count -eq 0 -and $rowTaskIds.Count -gt 0) {
            foreach ($tid in $rowTaskIds) {
                $ti = $taskInfo[$tid]; if (-not $ti) { continue }
                $fi = & $tryDblVal $ti['input_tokens']; $fo = & $tryDblVal $ti['output_tokens']
                if ($fi.Ok -and $fi.Val -gt 0) { $tkAgyIn += [int64]$fi.Val }
                if ($fo.Ok -and $fo.Val -gt 0) { $tkAgyOut += [int64]$fo.Val }
            }
        }
        # 컨텍스트 = 이 질문의 위임들 가운데 가장 컸던 값(없으면 null)
        $tkAgyCtx = $null; $tkAgyCtxModel = ""
        foreach ($tid in $rowTaskIds) {
            $ti = $taskInfo[$tid]; if (-not $ti) { continue }
            $cv = $ti['context_tokens']
            if ($null -ne $cv -and -not ($cv -is [System.DBNull])) {
                $cl = [int64]0
                if ([int64]::TryParse([string]$cv, [ref]$cl) -and $cl -gt 0 -and ($null -eq $tkAgyCtx -or $cl -gt $tkAgyCtx)) { $tkAgyCtx = $cl; $tkAgyCtxModel = [string]$ti['model'] }
            }
        }
        $tkAgy = [ordered]@{
            total = [int64]($tkAgyIn + $tkAgyOut); input = $tkAgyIn; cache = $tkAgyCache; output = $tkAgyOut; thinking = $tkAgyThink
            context = $tkAgyCtx; context_model = $(if ($null -ne $tkAgyCtx) { $tkAgyCtxModel } else { $null })
            context_window = $(if ($null -ne $tkAgyCtx) { Resolve-AgyContextWindow $ctxWinCfg.agy $tkAgyCtxModel } else { $null })
            models = [object[]]$tkAgyModels
        }
        $tokensObj = [pscustomobject][ordered]@{ agy = [pscustomobject]$tkAgy; claude = [pscustomobject]$tkClaude }

        $qEndUtc = & $parseTsUtc ([string]$r['end_ts'])
        if ($null -eq $qEndUtc) { $qEndUtc = & $parseTsUtc ([string]$r['q_ts']) }
        if ($null -eq $qEndUtc) { $qEndUtc = $evalNow }

        $qQuota = [ordered]@{}
        if ($null -ne $claudeInternal -and (Get-Command Get-LimitsEstimateAtTime -ErrorAction SilentlyContinue)) {
            $cRawAll = $qIn + $qCc + $qCr + $qOut
            $cCost = if ($cRawAll -gt 0 -and $null -ne $claudeCostCfg -and (Get-Command Get-ClaudeMessageCostUnits -ErrorAction SilentlyContinue)) {
                Get-ClaudeMessageCostUnits ([string]$r['claude_model']) ([double]$qIn) ([double]$qCc) ([double]$qCr) ([double]$qOut) $claudeCostCfg
            } else { 0.0 }
            $cAtEst = Get-LimitsEstimateAtTime $claudeInternal.Timeline $claudeInternal.WeekGroups $qEndUtc
            $cSide = & $buildQuotaSide $cCost $cRawAll $cAtEst $null
            if ($null -ne $cSide) { $qQuota["claude"] = $cSide }
        }

        if ([string]$r['mode'] -eq 'delegate' -and $rowTaskIds.Count -gt 0 -and $null -ne $agyInternal -and (Get-Command Get-LimitsEstimateAtTime -ErrorAction SilentlyContinue)) {
            $qAgyCost = 0.0
            $qAgyRaw = 0L
            $agyRefUtc = $qEndUtc
            $qMeasured = $null
            foreach ($tid in $rowTaskIds) {
                $ti = $taskInfo[$tid]
                if ($ti) {
                    $inR = & $tryDblVal $ti['input_tokens']
                    $outR = & $tryDblVal $ti['output_tokens']
                    $totR = & $tryDblVal $ti['total_tokens']
                    $inV = if ($inR.Ok -and $inR.Val -gt 0.0) { $inR.Val } else { 0.0 }
                    $outV = if ($outR.Ok -and $outR.Val -gt 0.0) { $outR.Val } else { 0.0 }
                    $hasIO = (($inR.Ok -or $outR.Ok) -and ($inV + $outV -gt 0.0))
                    $totV = if ($totR.Ok -and $totR.Val -gt 0.0) { $totR.Val } elseif ($hasIO) { $inV + $outV } else { 0.0 }
                    $qAgyRaw += [long][math]::Round($totV)
                    if ($totV -gt 0.0 -and $null -ne $agyCostCfg -and (Get-Command Get-AgyTaskCostUnits -ErrorAction SilentlyContinue)) {
                        $tModels = if ($taskModelsMap.ContainsKey($tid)) { @($taskModelsMap[$tid]) } else { @() }
                        $tInf = @{ Model = [string]$ti['model']; InputTokens = $inV; OutputTokens = $outV; HasInOut = $hasIO; TotalTokens = $totV }
                        $qAgyCost += Get-AgyTaskCostUnits $tInf $tModels $agyCostCfg
                    }
                    $tFin = & $parseTsUtc ([string]$ti['timestamp'])
                    if ($null -ne $tFin -and $tFin -gt $agyRefUtc) { $agyRefUtc = $tFin }
                }
                if ($agyInternal.Estimates -and $agyInternal.Estimates.ContainsKey($tid)) {
                    $estRec = $agyInternal.Estimates[$tid]
                    if ($estRec -and $estRec.Contains("measured_at")) {
                        $mDt = & $parseTsUtc ([string]$estRec.measured_at)
                        if ($null -ne $mDt -and $mDt -gt $agyRefUtc) { $agyRefUtc = $mDt }
                    }
                    if ($rowTaskIds.Count -eq 1 -and $estRec -and $estRec.Contains("measured")) {
                        $qMeasured = $estRec.measured
                    }
                }
            }
            $aAtEst = Get-LimitsEstimateAtTime $agyInternal.Timeline $agyInternal.WeekGroups $agyRefUtc
            $aSide = & $buildQuotaSide $qAgyCost $qAgyRaw $aAtEst $qMeasured
            if ($null -ne $aSide) { $qQuota["agy"] = $aSide }
        }

        $local = $null
        try { $local = ([DateTime]::Parse([string]$r['q_ts'], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)).ToLocalTime() } catch { $local = Get-Date }
        $rowObj = [ordered]@{
            q_ts = [string]$r['q_ts']; end_ts = [string]$r['end_ts']; session = [string]$r['session']; project = [string]$r['project']
            mode = [string]$r['mode']; claude_model = $claude; claude_effort = $effort; claude_label = $claudeLabel
            agent_model = $agent; agent_effort = $agentEffort; agent_label = $agentLabel; agy_models = $agy; combo = $combo
            agy_failed = $agyFailed; real_models = [object[]]$qRealModels; claude_models = [object[]]$qClaudeModels
            dur_sec = [long]$r['dur_sec']; calls = [long]$r['calls']
            tokens = $qClaudeTok; cr_tokens = $qCr
            agy_tokens = $(if ($null -eq $r['agy_tokens']) { $null } else { [long]$r['agy_tokens'] })
            agy_sec = $(if ($null -eq $r['agy_sec']) { $null } else { [long]$r['agy_sec'] })
            task_ids = [string[]]$rowTaskIds
            tasks = @($rowTaskIds | ForEach-Object {
                $ti = $taskInfo[$_]
                $sec = $null
                if ($ti) { $d = [double]0; if ([double]::TryParse([string]$ti['elapsed_sec'], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $sec = [long][math]::Round($d) } }
                [pscustomobject][ordered]@{
                    id = [string]$_
                    model = $(if ($ti -and $ti['model']) { [string]$ti['model'] } else { $null })
                    status = $(if ($ti -and $ti['status']) { ([string]$ti['status']).ToUpperInvariant() } else { $null })
                    sec = $sec
                    tried = $(if ($ti -and $ti['tried_models']) { [string]$ti['tried_models'] } else { $null })
                }
            })
            task_ok = [long]$(if ($null -eq $r['task_ok']) { 0 } else { $r['task_ok'] }); task_fail = [long]$(if ($null -eq $r['task_fail']) { 0 } else { $r['task_fail'] }); task_cancel = [long]$(if ($null -eq $r['task_cancel']) { 0 } else { $r['task_cancel'] })
            reason = [string]$r['reason']; preview = [string]$r['preview']; auto = ([long]$r['auto'] -eq 1)
            day = $local.ToString("yyyy-MM-dd")
            tokens_detail = $tokensObj
        }
        if ($qQuota.Count -gt 0) { $rowObj["quota"] = $qQuota }
        [void]$items.Add([pscustomobject]$rowObj)
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
        $gRealMap = @{}
        foreach ($it in $set) {
            foreach ($rm in @($it.real_models)) {
                if ($null -eq $rm -or -not $rm.model) { continue }
                $mName = [string]$rm.model
                if (-not $gRealMap.ContainsKey($mName)) {
                    $gRealMap[$mName] = @{ model = $mName; short = [string]$rm.short; total = [int64]0 }
                }
                $gRealMap[$mName].total += [int64]$rm.total
            }
        }
        $gRealModels = @($gRealMap.Values | Sort-Object -Property @{ Expression = { $_.total }; Descending = $true }, @{ Expression = { $_.model }; Ascending = $true } | ForEach-Object {
            [pscustomobject][ordered]@{
                model = [string]$_.model
                short = [string]$_.short
                total = [int64]$_.total
            }
        })
        [void]$byModel.Add([ordered]@{
            combo = [string]$g.Name; mode = [string]$set[0].mode; count = $set.Count
            dur_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.dur_sec }))
            tokens_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.tokens }))
            agy_tokens_median = (Get-AgyUsageMedian @($set | ForEach-Object { $_.agy_tokens }))
            real_models = [object[]]$gRealModels
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

    $limitsSummary = [ordered]@{}
    if ($null -ne $claudeInternal) {
        $clLat = $claudeInternal.Latest
        $clOut = [ordered]@{ basis = $claudeInternal.Basis }
        if ($clLat.Contains("five_hour")) { $clOut["five_hour"] = $clLat["five_hour"] }
        if ($clLat.Contains("seven_day")) { $clOut["weekly"] = $clLat["seven_day"] }
        if ($clLat.Contains("sessions")) { $clOut["sessions"] = $clLat["sessions"] }
        $limitsSummary["claude"] = $clOut
    }
    if ($null -ne $agyInternal) {
        $agLat = $agyInternal.Latest
        $agOut = [ordered]@{ basis = $agyInternal.Basis }
        if ($agLat.Contains("five_hour")) { $agOut["five_hour"] = $agLat["five_hour"] }
        if ($agLat.Contains("weekly")) { $agOut["weekly"] = $agLat["weekly"] }
        if ($agLat.Contains("sessions")) { $agOut["sessions"] = $agLat["sessions"] }
        $limitsSummary["agy"] = $agOut
    }

    $result = [ordered]@{
        updated_at = $updated
        collecting = $Collecting
        days = $Days
        summary = $summary
        limits = $limitsSummary
        by_model = [object[]]$byModel.ToArray()
        daily = [object[]]$daily.ToArray()
        rows = [object[]]@($items | Select-Object -First $RowLimit)
    }
    return (ConvertTo-Json -InputObject $result -Depth 10 -Compress)
}

if ($UsageCollect) {
    try {
        if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "agy-db.ps1") }
        if (-not (Get-Command New-AgyUsageState -ErrorAction SilentlyContinue)) {
            $progPath = Join-Path $PSScriptRoot "agy-progress.ps1"
            if (Test-Path -LiteralPath $progPath) { . $progPath }
        }
        if (-not $UsageProjectsDir) { $UsageProjectsDir = if ($env:CLAUDE_PROJECTS_DIR) { $env:CLAUDE_PROJECTS_DIR } else { Join-Path $env:USERPROFILE ".claude\projects" } }
        $collected = Invoke-AgyUsageCollect $UsageDbPath $UsageProjectsDir $UsageRuntimeDir $UsageRetentionDays
        Write-Output ("collected: files={0} questions={1} ran={2}" -f $collected.Files, $collected.Questions, $collected.Ran)
        exit 0
    } catch {
        [Console]::Error.WriteLine("usage-stats: " + $_.Exception.Message)
        exit 1
    }
}
