# serve-viewer.ps1
# samjil AI Agent 통합 웹 뷰어 서버 (Delegate QA 실행 기록 & Handoff 인수인계)
#
# 사용법:
#   .\serve-viewer.ps1                   # 브라우저 실행 및 http://127.0.0.1:8787 서빙
#   .\serve-viewer.ps1 -Port 9000        # 포트 지정
#   .\serve-viewer.ps1 -WatcherCheckSeconds 120   # 워처 자동 점검 주기(초). 0이면 점검 안 함
#   종료: 이 창에서 Ctrl+C
#
# agy 워처(watch-agy.ps1)가 꺼져 있으면 뷰어가 주기적으로(기본 60초) 점검해서 창 없이 다시 켭니다.
# stop-agy 로 일부러 끈 상태(manual_stop.flag)면 켜지 않습니다. 끄려면 -NoAgent 를 쓰세요.

param(
    [string]$HandoffDir = "",
    [string]$DataDir    = "",
    [string]$RuntimeDir = "",
    [string]$WebDir     = "",
    [string]$ClaudeProjectsDir = "",
    [int]$Port          = 8787,
    [switch]$NoBrowser  = $false,
    [switch]$NoAgent    = $false,
    [int]$WatcherCheckSeconds = 60,
    [switch]$WorkerMode = $false  # 같은 프로세스의 일꾼으로 돌 때. 사용자는 쓰지 않는다
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$parentDir = Split-Path $PSScriptRoot -Parent

if (-not $HandoffDir) {
    if ($env:AGENT_HANDOFF_ROOT) {
        $HandoffDir = $env:AGENT_HANDOFF_ROOT
    } else {
        # 핸드오프 폴더: ~\.samjil\handoff(설치본) > 이 뷰어 옆의 handoff > 저장소의 runtime\handoff. 채널은 그 안의 channels\ 에 있다.
        # 옛 배치(~\.samjil\handoff\<채널>)가 남아 있으면 channels\ 로 한 번 옮긴다.
        $hhHome = @((Join-Path $env:USERPROFILE ".samjil\handoff"), $(if ($parentDir) { Join-Path $parentDir "handoff" }), (Join-Path $PSScriptRoot "runtime\handoff")) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
        if (-not $hhHome) { $hhHome = Join-Path $env:USERPROFILE ".samjil\handoff" }
        $hhDb = @((Join-Path $hhHome "scripts\handoff-db.ps1"), (Join-Path $PSScriptRoot "..\handoff\scripts\handoff-db.ps1")) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
        if ($hhDb) { try { . $hhDb; [void](Move-HandoffLegacyLayout $hhHome) } catch {} }
        $HandoffDir = Join-Path $hhHome "channels"
    }
}

# 위임 폴더 배치(runtime / data)는 agy-layout.ps1 이 정한다. 설치본 옆 · 저장소 옆 · 내 폴더 순서로 찾는다.
$layoutCands = @(
    (Join-Path $parentDir "delegate-agy\scripts\sub\agy-layout.ps1"),
    (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\agy-layout.ps1"),
    (Join-Path $PSScriptRoot "runtime\delegate-agy\scripts\sub\agy-layout.ps1")
)
$layoutFile = $layoutCands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if ($layoutFile) { . $layoutFile } else { Write-Error "agy-layout.ps1 을 찾을 수 없습니다. install.ps1 로 설치돼 있는지 확인하세요."; exit 1 }

if (-not $RuntimeDir) {
    if ($DataDir) {
        $RuntimeDir = Join-Path (Split-Path $DataDir -Parent) "runtime"
    } elseif ($env:AGY_DELEGATE_RUNTIME) {
        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME
    } else {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
        if (-not (Test-Path -LiteralPath $RuntimeDir) -and $parentDir -and (Test-Path -LiteralPath (Join-Path $parentDir "delegate-agy\runtime"))) {
            $RuntimeDir = Join-Path $parentDir "delegate-agy\runtime"
        }
    }
}
# 옛 배치(runtime\outbox · runtime\logs\agy.db 등)면 새 배치로 옮긴다(이미 옮겼으면 아무것도 안 함).
if (Test-Path -LiteralPath $RuntimeDir) { try { Move-AgyLegacyLayout $RuntimeDir | Out-Null } catch {} }
if (-not $DataDir) { $DataDir = Get-AgyDataDir $RuntimeDir }

if (-not $WebDir) {
    $WebDir = Join-Path $PSScriptRoot "web"
}

if (-not $ClaudeProjectsDir) {
    if ($env:CLAUDE_PROJECTS_DIR) {
        $ClaudeProjectsDir = $env:CLAUDE_PROJECTS_DIR
    } else {
        $ClaudeProjectsDir = Join-Path $env:USERPROFILE ".claude\projects"
    }
}


if (-not (Test-Path $HandoffDir)) {

    New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null

}

New-Item -ItemType Directory -Force -Path $DataDir, (Join-Path $DataDir "cache") | Out-Null



if (-not (Test-Path $WebDir)) {

    Write-Error "web 폴더를 찾을 수 없습니다: $WebDir"

    exit 1

}



# 워처 상태 판정/자동 재시작 헬퍼
. (Join-Path $PSScriptRoot "watcher-health.ps1")
$WatcherRuntimeDir = $RuntimeDir
# 위임 기록·세션 DB(<위임>\data\delegate.db). /data/ 로 내보내는 cache 폴더 밖에 둔다.
$AgyDbPath = Join-Path $DataDir "delegate.db"

# Claude Desktop 세션 및 링크 색인 헬퍼
$claudeSessionsScript = Join-Path $PSScriptRoot "claude-sessions.ps1"
if (Test-Path -LiteralPath $claudeSessionsScript) {
    try {
        . $claudeSessionsScript
    } catch {
        Write-Warning ("claude-sessions.ps1 로드 실패: {0}" -f $_.Exception.Message)
    }
}

# Claude 세션 기록에서 호출별 사용량을 읽는 헬퍼(핸드오프 c2a 카드의 Claude 쪽 토큰). 못 불러와도 그 기능만 빠진다.
$claudeUsageScript = Join-Path $PSScriptRoot "claude-usage.ps1"
if (Test-Path -LiteralPath $claudeUsageScript) {
    try {
        . $claudeUsageScript
    } catch {
        Write-Warning ("claude-usage.ps1 로드 실패: {0}" -f $_.Exception.Message)
    }
}

$RouteMap = [ordered]@{

    "/handoff/" = (Resolve-Path $HandoffDir).Path

    "/data/"    = (Resolve-Path (Join-Path $DataDir "cache")).Path

    "/"         = (Resolve-Path $WebDir).Path

}



$MimeTypes = @{

    ".html"  = "text/html; charset=utf-8"

    ".htm"   = "text/html; charset=utf-8"

    ".js"    = "text/javascript; charset=utf-8"

    ".css"   = "text/css; charset=utf-8"

    ".json"  = "application/json; charset=utf-8"

    ".jsonl" = "application/x-ndjson; charset=utf-8"

    ".csv"   = "text/csv; charset=utf-8"

    ".txt"   = "text/plain; charset=utf-8"

    ".md"    = "text/plain; charset=utf-8"

    ".ico"   = "image/x-icon"

    ".svg"   = "image/svg+xml"

    ".png"   = "image/png"

    ".jpg"   = "image/jpeg"

    ".jpeg"  = "image/jpeg"

    ".gif"   = "image/gif"

    ".webp"  = "image/webp"

    ".bmp"   = "image/bmp"

}



function Get-Utf8QueryParams([System.Uri]$uri) {

    $dict = @{}

    $q = $uri.Query

    if (-not [string]::IsNullOrWhiteSpace($q)) {

        $trimmed = $q.TrimStart('?')

        $pairs = $trimmed.Split('&')

        foreach ($p in $pairs) {

            if ($p) {

                $idx = $p.IndexOf('=')

                if ($idx -ge 0) {

                    $k = [System.Uri]::UnescapeDataString($p.Substring(0, $idx))

                    $v = [System.Uri]::UnescapeDataString($p.Substring($idx + 1))

                    $dict[$k] = $v

                } else {

                    $k = [System.Uri]::UnescapeDataString($p)

                    $dict[$k] = ""

                }

            }

        }

    }

    return $dict

}



function Get-ContentType($path) {

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()

    if ($MimeTypes.ContainsKey($ext)) { return $MimeTypes[$ext] }

    return "application/octet-stream"

}



function Resolve-SafePath([string]$urlPath) {

    $rootPrefix = "/"

    $root = $RouteMap["/"]

    foreach ($prefix in $RouteMap.Keys) {

        if ($prefix -ne "/" -and $urlPath.StartsWith($prefix)) {

            $rootPrefix = $prefix

            $root = $RouteMap[$prefix]

            break

        }

    }



    $relative = $urlPath.Substring($rootPrefix.Length).TrimStart('/')

    if ([string]::IsNullOrWhiteSpace($relative)) { $relative = "index.html" }

    $relative = [System.Uri]::UnescapeDataString($relative)



    $combined = Join-Path $root $relative

    $full = $null

    try { $full = [System.IO.Path]::GetFullPath($combined) } catch { return $null }



    $rootWithSep = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    if ($full -ne $root -and -not $full.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {

        return $null

    }

    return $full

}



function Get-HandoffRoots {

    $roots = [System.Collections.Generic.List[string]]::new()

    if ($HandoffDir -and (Test-Path $HandoffDir)) {

        $roots.Add((Resolve-Path $HandoffDir).Path)

    }

    $cands = @(

        (Join-Path $env:USERPROFILE ".samjil\handoff\channels"),

        (Join-Path $env:USERPROFILE ".samjil\samjil-handoff"),

        (Join-Path $PSScriptRoot "runtime\handoff")

    )

    foreach ($c in $cands) {

        if (Test-Path $c) {

            $p = (Resolve-Path $c).Path

            if (-not $roots.Contains($p)) {

                $roots.Add($p)

            }

        }

    }

    return $roots

}



function Find-HandoffProjectDir([string]$projectName) {

    foreach ($r in (Get-HandoffRoots)) {

        $testP = Join-Path $r $projectName

        if (Test-Path -LiteralPath $testP -PathType Container) {

            return $testP

        }

    }

    return $null

}



# delegate-agy 스크립트를 찾습니다. $RelPath 는 scripts 폴더 기준(예: "start-agy.ps1", "sub\ensure-agy-running.ps1").
# @cwd 값 목록을 중복(대소문자, 끝의 \ 또는 / 무시)·빈 값을 빼고 줄 순서대로 배열로 만든다.
# common.ps1 의 ConvertTo-CwdList 와 같은 규칙의 사본이다(뷰어는 common.ps1 을 불러오지 않는다). tests\delegate-agy\cwd-list.tests.ps1 이 둘이 같은지 확인한다.
function ConvertTo-CwdList($Value) {
    $out = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($v in @($Value)) {
        if ($null -eq $v) { continue }
        $s = ([string]$v).Trim()
        if (-not $s) { continue }
        $key = $s.TrimEnd([char]92, [char]47).ToLowerInvariant()
        if (-not $key) { $key = $s.ToLowerInvariant() }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$out.Add($s)
    }
    return @($out.ToArray())
}

function Find-DelegateScript([string]$RelPath) {
    $cands = @()
    if ($env:AGY_DELEGATE_SCRIPTS) { $cands += (Join-Path $env:AGY_DELEGATE_SCRIPTS $RelPath) }
    # 이 뷰어와 같은 폴더 구조의 형제 폴더를 먼저 본다: 설치본 뷰어(~/.samjil/viewer) 옆에는 설치본 delegate-agy 가,
    # 저장소의 뷰어(runtime/viewer) 옆에는 저장소의 delegate-agy 가 있어서 두 경우 모두 버전이 맞는다.
    # (설치본을 먼저 보면, 저장소에서 뷰어를 돌릴 때 아직 설치 전인 옛 agy-progress.ps1 을 불러온다.)
    $cands += (Join-Path (Split-Path $PSScriptRoot -Parent) (Join-Path "delegate-agy\scripts" $RelPath))
    $cands += (Join-Path $env:USERPROFILE (Join-Path ".samjil\delegate-agy\scripts" $RelPath))
    $cands += (Join-Path $PSScriptRoot (Join-Path "runtime\delegate-agy\scripts" $RelPath))
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# 진행 중인 agy 작업이 지금 무엇을 하는지 agy의 대화 기록(transcript_full.jsonl)에서 읽습니다.
# agy는 단계를 하나 끝낼 때마다 이 파일에 한 줄씩 덧붙이므로, 끝부분만 읽어도 현재 단계/최근 동작을 알 수 있습니다.
# 대화를 못 찾거나 모호하면 $null 을 돌려주고, 화면은 진행 상황 줄 없이 기존대로 표시합니다.
# 진행 중인 대화의 과정(도구 호출 목록)을 읽는다. 5초마다 불리는데 대화 기록이 수 MB 까지 커질 수 있어서, 대화마다
# "어디까지 읽었는지(Offset)"와 읽은 단계를 기억해 두고 새로 쌓인 부분만 이어 읽는다(Read-AgyProcessSteps 참고).
# 기억은 최근 8개 대화까지만 둔다.
$script:ProcessCache = @{}
$script:TokenCache = @{}
function Get-AgyProcessStepsCached([string]$ConversationId, $StartedAt = $null) {
    if (-not (Get-Command Read-AgyProcessSteps -ErrorAction SilentlyContinue)) { return @() }
    $tp = Get-AgyTranscriptPath (Get-AgyHomeDir) $ConversationId
    if (-not $tp) { return @() }
    $item = Get-Item -LiteralPath $tp -ErrorAction SilentlyContinue
    if (-not $item) { return @() }
    if ($null -eq $script:ProcessCache) { $script:ProcessCache = @{} }
    $startTs = ""
    $startedDt = $null
    if ($StartedAt) {
        try {
            if ($StartedAt -is [datetime]) { $startedDt = $StartedAt }
            elseif ($StartedAt -is [DateTimeOffset]) { $startedDt = $StartedAt.LocalDateTime }
            else { $startedDt = [datetime]::Parse([string]$StartedAt, [System.Globalization.CultureInfo]::InvariantCulture) }
            if ($startedDt -ne [datetime]::MinValue) { $startTs = $startedDt.ToString("yyyyMMddHHmmss") }
        } catch {}
    }
    $cacheKey = if ($startTs) { "$ConversationId|$startTs" } else { $ConversationId }
    $c = $script:ProcessCache[$cacheKey]
    if (-not $c -or $item.Length -lt $c.Offset) {
        # 처음 보는 대화이거나, 파일이 더 짧아졌으면(새로 만들어짐) 처음부터 읽는다
        $c = @{ Offset = [long]0; Steps = (New-Object System.Collections.ArrayList); Touched = (Get-Date) }
        $script:ProcessCache[$cacheKey] = $c
        if ($script:ProcessCache.Count -gt 8) {
            $oldest = $script:ProcessCache.GetEnumerator() | Sort-Object { $_.Value.Touched } | Select-Object -First 1
            if ($oldest) { $script:ProcessCache.Remove($oldest.Key) }
        }
    }
    $c.Touched = Get-Date
    $r = Read-AgyProcessSteps $tp $c.Offset 0 500 300 $startedDt
    foreach ($st in @($r.Steps)) { [void]$c.Steps.Add($st) }
    $c.Offset = [long]$r.Offset
    $allCount = $c.Steps.Count
    if ($allCount -le 1500) {
        return @($c.Steps.ToArray())
    }
    $front = @($c.Steps.GetRange(0, 300))
    $marker = [ordered]@{ skipped = ($allCount - 1500) }
    $back = @($c.Steps.GetRange($allCount - 1200, 1200))
    return (@($front) + @($marker) + @($back))
}

# ---- 과정 번역("한글로 번역"): 번역은 agy 호출이라 30초~1분 걸린다. 요청 처리 루프를 막지 않도록 숨김 창의 보조 스크립트
# (sub\process-translate.ps1)가 하고, 여기서는 시작시키고 상태만 읽는다. 결과는 <데이터 폴더>\process-ko\<대화 id>.json 에 캐시된다.
$script:TranslateStaleSeconds = 360   # 실행 표시 파일이 이만큼 오래되면 죽은 것으로 본다

function Get-ProcessTranslationPath([string]$ConversationId, [string]$Since = "") {
    if ($ConversationId -notmatch '^[A-Za-z0-9-]{1,80}$') { return $null }
    $suffix = ""
    if ($Since) {
        $clean = ($Since -replace '[^0-9]', '')
        if ($clean) { $suffix = "_" + $clean }
    }
    return (Join-Path $DataDir ("cache\process-ko\{0}{1}.json" -f $ConversationId, $suffix))
}

# 상태: running(번역 중) | done(끝남) | none(아직 안 함·새 단계가 생김) | error | unavailable(대화 기록이 없어 번역할 수 없음)
# 대화 id 가 올바르지 않으면 $null. items 는 번역해 둔 것(단계 순번 -> label/think/say)이라 상태와 상관없이 함께 준다.
function Get-ProcessTranslationState([string]$ConversationId, [string]$Since = "") {
    $cachePath = Get-ProcessTranslationPath $ConversationId $Since
    if (-not $cachePath) { return $null }
    if ($Since -and -not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        $legacyPath = Get-ProcessTranslationPath $ConversationId ""
        if ($legacyPath -and (Test-Path -LiteralPath $legacyPath -PathType Leaf)) {
            $cachePath = $legacyPath
        }
    }
    $cache = @{ Status = ""; Message = ""; StepsCovered = 0; Items = @{}; Model = "" }
    if (Get-Command Read-TranslationCache -ErrorAction SilentlyContinue) { $cache = Read-TranslationCache $cachePath }

    $state = "none"; $message = ""
    $run = Get-Item -LiteralPath "$cachePath.running" -ErrorAction SilentlyContinue
    $transcript = $null
    if (Get-Command Get-AgyTranscriptPath -ErrorAction SilentlyContinue) { $transcript = Get-AgyTranscriptPath (Get-AgyHomeDir) $ConversationId }
    $hasTranscript = [bool]($transcript -and (Test-Path -LiteralPath $transcript -PathType Leaf))

    if ($run -and ((Get-Date) - $run.LastWriteTime).TotalSeconds -lt $script:TranslateStaleSeconds) {
        $state = "running"
    } elseif ($cache.Items.Count -gt 0 -and -not $hasTranscript) {
        $state = "done"      # 대화 기록은 정리됐지만 번역해 둔 것은 남아 있다
    } elseif (-not $hasTranscript) {
        $state = "unavailable"; $message = "agy 대화 기록이 남아 있지 않아 번역할 수 없습니다"
    } elseif ($cache.Status -eq "unavailable") {
        $state = "none"      # 그때는 없었지만 지금은 있다: 다시 시도할 수 있게 둔다
    } elseif ($cache.Status -eq "done") {
        $sinceDt = $null
        if ($Since) {
            try { $sinceDt = [datetime]::Parse($Since, [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
        }
        $stepList = @(Get-AgyProcessStepsCached $ConversationId $sinceDt)
        $state = if ($cache.StepsCovered -ge $stepList.Count) { "done" } else { "none" }
        # 번역 규칙이 바뀌어(예: 인용문 안의 한글은 한글로 세지 않는다) 예전에 건너뛴 칸이 새로 번역 대상이 되면 이어서 번역할 수 있게 한다
        if ($state -eq "done" -and (Get-Command Get-TranslationTodo -ErrorAction SilentlyContinue) -and @(Get-TranslationTodo $stepList $cache.Items).Count -gt 0) { $state = "none" }
    } elseif ($cache.Status -eq "error") {
        $state = "error"; $message = $cache.Message
    } elseif ($cache.Status -eq "partial") {
        $state = "error"; $message = "번역이 중간에 멈췄습니다. 다시 시도하면 이어서 합니다"
    }
    return [PSCustomObject]@{ id = $ConversationId; state = $state; message = $message; model = $cache.Model; items = $cache.Items }
}

# 번역을 시작한다(이미 하는 중이거나 끝났거나 할 수 없으면 시작하지 않고 상태만 돌려준다).
function Start-ProcessTranslation([string]$ConversationId, [string]$Since = "") {
    $st = Get-ProcessTranslationState $ConversationId $Since
    if (-not $st -or $st.state -in @("running", "done", "unavailable")) { return $st }
    $trScriptPath = Find-DelegateScript "sub\process-translate.ps1"
    if (-not $trScriptPath) {
        $st.state = "error"; $st.message = "번역 스크립트(process-translate.ps1)를 찾지 못했습니다. install.ps1 을 다시 실행해 주세요"
        return $st
    }
    $cachePath = Get-ProcessTranslationPath $ConversationId $Since
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cachePath) | Out-Null
        # 보조 스크립트가 뜨기까지 1초쯤 걸려서, 그 사이 상태를 물으면 "안 함"으로 보이지 않게 표시 파일을 먼저 만든다
        [System.IO.File]::WriteAllText("$cachePath.running", '{"pid":0}', (New-Object System.Text.UTF8Encoding($false)))
        # 콘솔 창을 아예 만들지 않는 방식(CreateNoWindow)으로 띄운다. Start-Process -WindowStyle Hidden 은 창이 잠깐 깜빡일 수 있다.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $sinceArg = if ($Since) { " -Since `"$Since`"" } else { "" }
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$trScriptPath`" -ConversationId $ConversationId -OutFile `"$cachePath`"$sinceArg"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [void][System.Diagnostics.Process]::Start($psi)
    } catch {
        Remove-Item -LiteralPath "$cachePath.running" -Force -ErrorAction SilentlyContinue
        $st.state = "error"; $st.message = "번역을 시작하지 못했습니다: " + $_.Exception.Message
        return $st
    }
    $st.state = "running"; $st.message = ""
    return $st
}

function Get-AgyProgress([string]$ConversationId, $StartedAt, [string]$TaskId = "", [string]$QuestionSnippet = "", [string]$Session = "") {
    try {
        $agyHome = if ($env:AGY_HOME) { $env:AGY_HOME } else { Join-Path $env:USERPROFILE ".gemini\antigravity-cli" }
        if (-not $ConversationId) {
            if (-not $StartedAt) { return $null }
            $convDir = Join-Path $agyHome "conversations"
            if (-not (Test-Path -LiteralPath $convDir -PathType Container)) { return $null }
            $from = $StartedAt.AddSeconds(-5); $to = $StartedAt.AddSeconds(180)
            $cands = @(Get-ChildItem -LiteralPath $convDir -Filter '*.db' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -ge $from -and $_.CreationTime -le $to } |
                Sort-Object CreationTime)
            if ($cands.Count -eq 0) { return $null }
            if ($cands.Count -eq 1) {
                $ConversationId = $cands[0].BaseName
            } else {
                $matchedId = ""
                foreach ($c in $cands) {
                    $candCId = $c.BaseName
                    $candTf = Join-Path $agyHome ("brain\{0}\.system_generated\logs\transcript.jsonl" -f $candCId)
                    if (Test-Path -LiteralPath $candTf) {
                        try {
                            $firstLine = [System.IO.File]::ReadLines($candTf) | Select-Object -First 1
                            if ($firstLine) {
                                if ($TaskId -and $firstLine -match [regex]::Escape($TaskId)) {
                                    $matchedId = $candCId
                                    break
                                }
                                if ($QuestionSnippet -and $firstLine.Contains($QuestionSnippet)) {
                                    $matchedId = $candCId
                                    break
                                }
                            }
                        } catch {}
                    }
                }
                if ($matchedId) {
                    $ConversationId = $matchedId
                } else {
                    $best = $cands | Sort-Object { [Math]::Abs(($_.CreationTime - $StartedAt).TotalSeconds) } | Select-Object -First 1
                    $ConversationId = $best.BaseName
                }
            }
        }
        $tf = Join-Path $agyHome ("brain\{0}\.system_generated\logs\transcript_full.jsonl" -f $ConversationId)
        $item = Get-Item -LiteralPath $tf -ErrorAction SilentlyContinue
        if (-not $item) { return $null }

        # 끝 256KB만 읽습니다(파일은 수 MB까지 커질 수 있음). 잘린 첫 줄은 버립니다.
        $tailBytes = 262144
        $fs = [System.IO.File]::Open($tf, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $offset = [Math]::Max(0, $fs.Length - $tailBytes)
            [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ($fs.Length - $offset)
            $read = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Dispose() }
        $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $lines = @($text -split "\r?\n" | Where-Object { $_ })
        if ($offset -gt 0 -and $lines.Count -gt 0) { $lines = @($lines | Select-Object -Skip 1) }

        $stepFilter = if ($Session) { $StartedAt } else { $null }
        $sinceDt = $null
        if ($stepFilter) {
            try {
                if ($stepFilter -is [datetime]) { $sinceDt = $stepFilter }
                elseif ($stepFilter -is [DateTimeOffset]) { $sinceDt = $stepFilter.LocalDateTime }
                else { $sinceDt = [datetime]::Parse([string]$stepFilter, [System.Globalization.CultureInfo]::InvariantCulture) }
            } catch {}
        }

        $step = $null; $action = ""; $thinking = ""; $say = ""; $tool = ""; $detail = ""; $cwd = ""; $background = $false; $found = $false
        $stepIndexesSince = New-Object System.Collections.Generic.HashSet[int]
        $latestStepIndex = $null
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $o = $null
            try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
            if ($null -eq $latestStepIndex -and $null -ne $o.step_index) { $latestStepIndex = [int]$o.step_index }
            if ($null -ne $o.step_index -and $sinceDt) {
                $lineDt = $null
                if ($o.created_at) {
                    try {
                        $parsed = [datetime]::Parse([string]$o.created_at, [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::RoundtripKind)
                        $lineDt = $parsed.ToLocalTime()
                    } catch {}
                }
                if ($lineDt -and $lineDt -ge $sinceDt) {
                    [void]$stepIndexesSince.Add([int]$o.step_index)
                }
            }
            if ($o.type -eq 'PLANNER_RESPONSE') {
                $calls = @($o.tool_calls)
                # 마지막 도구 호출은 가장 최근 응답에서 읽고, agy 의 생각은 그 응답에 없으면(생각은 응답 3개 중 1개꼴) 더 앞 응답까지 거슬러 찾는다
                if (-not $found -and $calls.Count -gt 0 -and $calls[-1].args) {
                    $a = $calls[-1].args
                    $action = [string]$a.toolAction
                    if (-not $action) { $action = [string]$a.toolSummary }
                    if (-not $action) { $action = [string]$calls[-1].name }
                    $tool = [string]$calls[-1].name
                    if (Get-Command Get-AgyToolDetail -ErrorAction SilentlyContinue) { $detail = Get-AgyToolDetail $calls[-1] }
                    if ($tool -eq 'run_command') {
                        $cwd = [string]$a.Cwd
                        $background = ([string]$a.IsDaemon -match '^(?i:true|1)$')
                    }
                }
                if (-not $found) {
                    $found = $true
                    if ($o.content -and $calls.Count -gt 0) { $say = (([string]$o.content) -replace '\s+', ' ').Trim() }
                }
                if ($o.thinking) { $thinking = (([string]$o.thinking) -replace '\s+', ' ').Trim(); break }
            }
        }
        $step = if ($sinceDt) { $stepIndexesSince.Count } else { $(if ($null -ne $latestStepIndex) { $latestStepIndex } else { 0 }) }
        if ($thinking.Length -gt 500) { $thinking = $thinking.Substring(0, 500) + "…" }
        if ($say.Length -gt 300) { $say = $say.Substring(0, 300) + "…" }
        $last = $item.LastWriteTime

        # 실시간 토큰 집계 (transcript.jsonl 우선, 없으면 transcript_full.jsonl — 오프셋 기반 증분 읽기)
        # 끝난 뒤 위임 기록과 같은 기준: 총 = 입력(캐시 밖) + 출력. 같은 턴의 줄은 덮어쓰고, 캐시 읽기는 따로 센다. 계산은 agy-progress.ps1 의 공용 함수.
        $tIn = [int64]0; $tOut = [int64]0; $tCache = [int64]0; $tCtx = [int64]0; $tTurns = 0
        $compactTf = Join-Path $agyHome ("brain\{0}\.system_generated\logs\transcript.jsonl" -f $ConversationId)
        $targetTokenFile = if (Test-Path -LiteralPath $compactTf) { $compactTf } else { $tf }
        if ($targetTokenFile -and (Get-Command Update-AgyUsageState -ErrorAction SilentlyContinue)) {
            try {
                if ($null -eq $script:UsageCache) { $script:UsageCache = @{} }
                $us = $script:UsageCache[$ConversationId]
                if (-not $us -or $us.Path -ne $targetTokenFile) {
                    $us = New-AgyUsageState $targetTokenFile
                    $script:UsageCache[$ConversationId] = $us
                    if ($script:UsageCache.Count -gt 16) {
                        $oldestU = $script:UsageCache.GetEnumerator() | Sort-Object { $_.Value.Touched } | Select-Object -First 1
                        if ($oldestU) { $script:UsageCache.Remove($oldestU.Key) }
                    }
                }
                Update-AgyUsageState $us
                $sum = Get-AgyUsageSummary $us 0 $stepFilter
                $tIn = $sum.Input; $tOut = $sum.Output; $tCache = $sum.Cache; $tCtx = $sum.Context; $tTurns = $sum.Turns
            } catch {}
        }

        # 멈춤 판정에 쓸 값. 워처(watch-agy.ps1)와 같은 기준(AGY_STALL_SECONDS, 기본 300초)을 화면에도 알려 줘서, 화면이 "멈춘 것으로 보임"을 같은 잣대로 말하게 한다.
        # 오래 걸리는 명령을 백그라운드로 돌려 두고 기다리는 동안은 새 단계가 없어도 멈춘 게 아니다 - 기록 전체를 훑는 일이라 멈춤 기준에 가까워졌을 때만 확인한다.
        $stallSec = 300
        if (Get-Command Get-AgySecondsSetting -ErrorAction SilentlyContinue) { $stallSec = Get-AgySecondsSetting 'AGY_STALL_SECONDS' 300 30 }
        $waitingBg = $false
        if ((((Get-Date) - $last).TotalSeconds -ge ($stallSec - 60)) -and (Get-Command Get-AgyPendingBackgroundTasks -ErrorAction SilentlyContinue)) {
            try { $waitingBg = (@(Get-AgyPendingBackgroundTasks $agyHome $ConversationId).Count -gt 0) } catch {}
        }
        $stepList = @(Get-AgyProcessStepsCached $ConversationId $stepFilter)

        return [PSCustomObject]@{
            conversation_id = $ConversationId
            step            = $step
            action          = $action
            tool            = $tool
            detail          = $detail
            cwd             = $cwd
            background      = $background
            step_count      = $stepList.Count
            stall_seconds   = $stallSec
            waiting_background = $waitingBg
            steps           = $stepList
            thinking        = $thinking
            say             = $say
            tokens          = [PSCustomObject]@{
                input   = $tIn
                output  = $tOut
                total   = ($tIn + $tOut)
                cache   = $tCache
                context = $tCtx
                turns   = $tTurns
            }
            last_activity   = $last.ToString("yyyy-MM-dd HH:mm:ss")
            last_activity_ms = [int64]([DateTimeOffset]$last).ToUnixTimeMilliseconds()
        }
    } catch {
        return $null
    }
}

# 위임 기록·세션 DB 접근 모듈(agy-db.ps1). 못 찾으면 위임 기록 API 가 503 을 돌려주고 대기 작업의 세션 모델·대화 id 만 빠진다.
$agyDbLib = Find-DelegateScript "sub\agy-db.ps1"
if ($agyDbLib) { . $agyDbLib } else { Write-Warning "agy-db.ps1 을 찾지 못했습니다. 위임 기록을 읽을 수 없습니다." }
# 워처와 같이 쓰는 도구 호출·과정 읽기 코드(agy-progress.ps1). 못 찾으면 진행 표시의 도구 설명과 과정 목록만 빠진다.
$agyProgressLib = Find-DelegateScript "sub\agy-progress.ps1"
if ($agyProgressLib) { . $agyProgressLib }
# 번역 캐시 읽기 함수(Read-TranslationCache)도 같이 쓴다. 인자 없이 불러서 함수만 정의된다.
$processTranslateLib = Find-DelegateScript "sub\process-translate.ps1"
if ($processTranslateLib) { . $processTranslateLib }
# 질문마다 예상 기록을 강제하는 규칙(Claude Code PreToolUse HTTP 훅 /api/estimate-guard 가 쓴다). 못 찾으면 그 API 는 항상 통과시킨다.
$estimateGuardLib = Find-DelegateScript "sub\estimate-guard-lib.ps1"
if ($estimateGuardLib) { . $estimateGuardLib }
$tokenStatsLib = Find-DelegateScript "sub\token-stats.ps1"
if ($tokenStatsLib) {
    $savedRuntimeDir = $RuntimeDir
    $savedDataDir = $DataDir
    $savedAgyDbPath = $AgyDbPath
    $savedClaudeProjectsDir = $ClaudeProjectsDir
    . $tokenStatsLib
    if ($savedRuntimeDir) { $RuntimeDir = $savedRuntimeDir }
    if ($savedDataDir) { $DataDir = $savedDataDir }
    if ($savedAgyDbPath) { $AgyDbPath = $savedAgyDbPath }
    if ($savedClaudeProjectsDir) { $ClaudeProjectsDir = $savedClaudeProjectsDir }
}
# 핸드오프 채널 공용 함수(handoff-lib.ps1): 메시지 머리말의 모델과 "자동 이어가기" 상태를 읽는다. 못 찾으면 그 정보만 빠진다.
$script:HandoffMetaCache = @{}
$handoffLibLoaded = $false
foreach ($hlCand in @((Join-Path $PSScriptRoot "..\handoff\scripts\handoff-lib.ps1"), (Join-Path $env:USERPROFILE ".samjil\handoff\scripts\handoff-lib.ps1"))) {
    if (Test-Path -LiteralPath $hlCand) { try { . $hlCand; $handoffLibLoaded = $true } catch {}; break }
}

$script:ClaudeLiveCache = @{}
$script:ClaudeCandidateFilesCache = $null
$script:ClaudeCandidateFilesTime = [DateTime]::MinValue

function Get-ClaudeLiveTaskInfo {
    param(
        [string]$TaskId,
        [string]$ProjectsDir = ""
    )

    try {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { return $null }

        $nowUtc = [DateTime]::UtcNow

        # 1. task_id 별 캐시 확인 (60초 TTL, 파일 수정 시각이 바뀌지 않으면 다시 읽지 않음)
        if ($script:ClaudeLiveCache.ContainsKey($TaskId)) {
            $entry = $script:ClaudeLiveCache[$TaskId]
            $ageSec = ($nowUtc - $entry.CalculatedAt).TotalSeconds

            if ($entry.Data -ne $null) {
                if ($entry.FilePath -and (Test-Path -LiteralPath $entry.FilePath)) {
                    $lwt = (Get-Item -LiteralPath $entry.FilePath).LastWriteTimeUtc
                    if ($lwt -eq $entry.FileLastWrite) {
                        return $entry.Data
                    }
                } elseif ($ageSec -lt 60) {
                    return $entry.Data
                }
            } else {
                # 음수 캐시 (못 찾은 경우): 15초 동안 재검색 방지
                if ($ageSec -lt 15) {
                    return $null
                }
            }
        }

        if (-not $ProjectsDir) {
            $ProjectsDir = if ($script:ClaudeProjectsDir) { $script:ClaudeProjectsDir } else { $ClaudeProjectsDir }
        }
        if (-not $ProjectsDir -or -not (Test-Path -LiteralPath $ProjectsDir)) {
            return $null
        }

        # 2. 최근 6시간 안 수정된 상위 5개 파일 (5초 캐시)
        if ($null -eq $script:ClaudeCandidateFilesCache -or ($nowUtc - $script:ClaudeCandidateFilesTime).TotalSeconds -ge 5) {
            $cutoff = $nowUtc.AddHours(-6)
            $script:ClaudeCandidateFilesCache = @(
                Get-ChildItem -Path (Join-Path $ProjectsDir "*\*.jsonl") -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $cutoff } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 5
            )
            $script:ClaudeCandidateFilesTime = $nowUtc
        }

        $cands = $script:ClaudeCandidateFilesCache
        if (-not $cands -or $cands.Count -eq 0) {
            $script:ClaudeLiveCache[$TaskId] = @{
                Data          = $null
                CalculatedAt  = $nowUtc
                FilePath      = ""
                FileLastWrite = $null
            }
            return $null
        }

        # 3. 파일 끝부분(마지막 2MB)에서 task_id 탐색
        $matchedFile = $null
        $matchedText = ""
        $matchedSeek = 0L
        $maxBytes = 2 * 1024 * 1024

        foreach ($cf in $cands) {
            try {
                $fs = [System.IO.File]::Open($cf.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $flen = $fs.Length
                    $seek = [Math]::Max(0L, $flen - $maxBytes)
                    $fs.Seek($seek, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $toRead = [int]($flen - $seek)
                    $buf = New-Object byte[] $toRead
                    $read = $fs.Read($buf, 0, $toRead)
                    if ($read -gt 0) {
                        $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                        if ($txt.Contains($TaskId)) {
                            $matchedFile = $cf
                            $matchedText = $txt
                            $matchedSeek = $seek
                            break
                        }
                    }
                } finally {
                    $fs.Dispose()
                }
            } catch {
                continue
            }
        }

        if (-not $matchedFile -or -not $matchedText) {
            $script:ClaudeLiveCache[$TaskId] = @{
                Data          = $null
                CalculatedAt  = $nowUtc
                FilePath      = ""
                FileLastWrite = $null
            }
            return $null
        }

        # 4. 그 task_id 가 처음 나온 턴 (실제 사용자 프롬프트부터 현재 끝까지)
        $lines = $matchedText -split "\r?\n"
        if ($matchedSeek -gt 0 -and $lines.Length -gt 1) {
            $lines = $lines[1..($lines.Length - 1)]
        }

        $firstTaskLineIdx = -1
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i].Contains($TaskId)) {
                $firstTaskLineIdx = $i
                break
            }
        }

        if ($firstTaskLineIdx -lt 0) {
            return $null
        }

        Add-Type -AssemblyName System.Web.Extensions
        $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $js.MaxJsonLength = [int]::MaxValue

        $turnStartIdx = -1
        $turnStartTs = ""
        for ($i = $firstTaskLineIdx; $i -ge 0; $i--) {
            $l = $lines[$i].Trim()
            if ($l.StartsWith('{"type":"user"') -or $l.StartsWith('{"type": "user"') -or $l -match '"type"\s*:\s*"user"') {
                if (-not $l.Contains('"tool_result"')) {
                    try {
                        $uObj = $js.DeserializeObject($l)
                        if (Test-TokenStatsRealUser $uObj) {
                            $turnStartIdx = $i
                            $turnStartTs = [string]$uObj['timestamp']
                            break
                        }
                    } catch {}
                }
            }
        }

        if ($turnStartIdx -lt 0) {
            $turnStartIdx = 0
        }

        $baselineCtx = $null
        for ($i = $turnStartIdx - 1; $i -ge 0; $i--) {
            $l = $lines[$i].Trim()
            if ($l -match '"type"\s*:\s*"assistant"' -and $l -match '"id"\s*:\s*"(msg_[A-Za-z0-9_-]+)"') {
                $inp = 0; $cc = 0; $cr = 0; $out = 0
                if ($l -match '"input_tokens"\s*:\s*(\d+)') { $inp = [int64]$Matches[1] }
                if ($l -match '"cache_creation_input_tokens"\s*:\s*(\d+)') { $cc = [int64]$Matches[1] }
                if ($l -match '"cache_read_input_tokens"\s*:\s*(\d+)') { $cr = [int64]$Matches[1] }
                if ($l -match '"output_tokens"\s*:\s*(\d+)') { $out = [int64]$Matches[1] }
                $baselineCtx = $inp + $cc + $cr + $out
                break
            }
        }

        if ($null -eq $baselineCtx -and $turnStartIdx -eq 0) {
            $baselineCtx = 0L
        }

        $turnLines = $lines[$turnStartIdx..($lines.Length - 1)]

        $liveMetrics = $null
        if (Get-Command Get-ClaudeLiveTurnMetrics -ErrorAction SilentlyContinue) {
            $liveMetrics = Get-ClaudeLiveTurnMetrics -Lines $turnLines -BaselineCtx $baselineCtx
        }

        # 결정 시점에 기록한 예상(record-estimate)은 위임을 보내기 전에 이미 정해져 있으므로 진행 중 카드에도 붙인다(답변 끝 예상 줄보다 우선)
        if ($liveMetrics -is [System.Collections.IDictionary] -and $turnStartTs -and (Get-Command Get-RecordedEstimate -ErrorAction SilentlyContinue)) {
            # 위임을 보낸 시각(작업 번호 claude_<epoch>_N)까지의 기록 중 그 위임을 보낸 질문의 것(뒤에 다른 질문이 기록해도 바뀌지 않는다)
            $subTs = ""
            if ($TaskId -match '^claude_(\d{9,11})_\d+') { $subTs = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1] + 2).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
            $recEst = Get-RecordedEstimate $AgyDbPath (Split-Path (Split-Path $matchedFile.FullName -Parent) -Leaf) $turnStartTs $subTs
            if ($recEst) { foreach ($ek in @($recEst.Keys)) { $ev = $recEst.Item($ek); if ($null -ne $ev) { $liveMetrics.set_Item($ek, $ev) } } }
        }

        $fileLwt = (Get-Item -LiteralPath $matchedFile.FullName).LastWriteTimeUtc
        $script:ClaudeLiveCache[$TaskId] = @{
            Data          = $liveMetrics
            CalculatedAt  = $nowUtc
            FilePath      = $matchedFile.FullName
            FileLastWrite = $fileLwt
        }

        return $liveMetrics
    } catch {
        return $null
    }
}
function Get-TokenMedianValue($Numbers) {
    $arr = @($Numbers)
    if ($arr.Count -eq 0) { return $null }
    $sorted = @($arr | Sort-Object)
    $cnt = $sorted.Count
    if ($cnt % 2 -eq 1) {
        return [double]$sorted[ [Math]::Floor($cnt / 2) ]
    } else {
        $mid = [int]($cnt / 2)
        return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2.0
    }
}

function ConvertTo-LocalDateValue([string]$ts) {
    if ([string]::IsNullOrWhiteSpace($ts)) { return $null }
    $dto = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($ts, [ref]$dto)) {
        return $dto.LocalDateTime
    }
    $dt = [DateTime]::MinValue
    if ([DateTime]::TryParse($ts, [ref]$dt)) {
        return $dt
    }
    return $null
}

function Get-IsoWeekStringValue([DateTime]$dt) {
    $day = [int]$dt.DayOfWeek
    if ($day -eq 0) { $day = 7 }
    $thursday = $dt.AddDays(4 - $day)
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $weekNum = $cal.GetWeekOfYear($thursday, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
    return ("{0:D4}-W{1:D2}" -f $thursday.Year, $weekNum)
}

# 통계가 오래됐는지: 대화 기록 파일(*.jsonl) 중 가장 늦게 바뀐 시각이 마지막 수집(calibration.json 을 쓴 시각)보다 SlackSec 초 넘게 뒤이면 true.
# 수집한 적이 없거나(calibration.json 없음) 대화 폴더가 없으면 false(처음 수집은 사용자가 "지금 갱신"으로 한다). 수집기는 끝난 턴만 확정하므로 진행 중이던 턴은 끝난 뒤 이 판정으로 다시 잡힌다.
# 화면 데이터가 바뀌었는지 가늠하는 도장: 위임 기록(updated_seq) · 질문 행 · 예상 기록 · 작업 연결의 개수와 최댓값 · 합계, 마지막 수집 시각(calibration.json).
# 같은 도장이면 무거운 API(위임 기록 전체, 토큰 통계)를 다시 만들지 않고 메모리에 둔 응답을 그대로 준다(새 창 · 새로고침이 빨라진다).
# DB 파일 수정 시각은 워처가 수시로 쓰는 기록 때문에 계속 바뀌어 쓰지 않는다.
function Get-ViewerDataStamp([string]$DbPath, [string]$DataDir) {
    try {
        if (-not (Test-Path -LiteralPath $DbPath)) { return "" }
        $parts = New-Object System.Collections.ArrayList
        $sdb = Open-AgyDb $DbPath
        try {
            foreach ($q in @(
                "SELECT MAX(updated_seq) AS a, COUNT(*) AS b, '' AS c FROM tasks",
                "SELECT COUNT(*) AS a, MAX(turn_ts) AS b, SUM(COALESCE(d_tokens, 0)) + SUM(COALESCE(est_direct, 0)) + SUM(COALESCE(calls, 0)) AS c FROM token_turns",
                "SELECT MAX(id) AS a, COUNT(*) AS b, '' AS c FROM token_estimates",
                "SELECT MAX(task_id) AS a, COUNT(*) AS b, '' AS c FROM token_task_links")) {
                try { foreach ($row in @($sdb.Query($q, $null))) { [void]$parts.Add(("{0}/{1}/{2}" -f $row['a'], $row['b'], $row['c'])) } } catch { [void]$parts.Add("-") }
            }
        } finally { $sdb.Dispose() }
        $cal = New-Object System.IO.FileInfo((Join-Path $DataDir "calibration.json"))
        if ($cal.Exists) { [void]$parts.Add([string]$cal.LastWriteTimeUtc.Ticks) }
        return ($parts -join "|")
    } catch { return "" }
}

function Test-TokenStatsStale([string]$DataDir, [string]$ClaudeProjectsDir, [double]$SlackSec = 20) {
    try {
        if (-not $DataDir -or -not $ClaudeProjectsDir) { return $false }
        $cal = Join-Path $DataDir "calibration.json"
        if (-not (Test-Path -LiteralPath $cal) -or -not (Test-Path -LiteralPath $ClaudeProjectsDir)) { return $false }
        $calTime = (Get-Item -LiteralPath $cal).LastWriteTime
        $newest = [datetime]::MinValue
        foreach ($d in @(Get-ChildItem -LiteralPath $ClaudeProjectsDir -Directory -ErrorAction SilentlyContinue)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)) {
                if ($f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime }
            }
        }
        return ($newest -gt $calTime.AddSeconds($SlackSec))
    } catch { return $false }
}

$script:TokenStatsAggCache = @{}

function Get-TokenStatsData {
    param(
        [string]$DbPath = "",
        [string]$DataDir = "",
        [int]$Days = 30,
        [DateTime]$Now = [DateTime]::MinValue,
        [int]$RecentPage = 1,
        [int]$RecentPageSize = 20,
        [string]$RecentPath = ""
    )

    if ($Days -ne 7 -and $Days -ne 30 -and $Days -ne 60) {
        $Days = 30
    }
    if ($Now -eq [DateTime]::MinValue) {
        $Now = [DateTime]::Now
    }
    if ($RecentPageSize -lt 1) {
        $RecentPageSize = 1
    } elseif ($RecentPageSize -gt 100) {
        $RecentPageSize = 100
    }
    if ($RecentPath -ne 'direct' -and $RecentPath -ne 'delegate' -and $RecentPath -ne 'chat') {
        $RecentPath = ""
    }
    if ($RecentPage -lt 1) {
        $RecentPage = 1
    }

    $endDate = $Now.Date
    $startDate = $endDate.AddDays(-($Days - 1))

    # 집계 캐시 키: DB 파일, WAL 파일, calibration.json 의 수정 시각과 크기, 기간(days), 기준일(endDate)
    $dbTicks = 0L; $dbLen = 0L
    if ($DbPath -and (Test-Path -LiteralPath $DbPath)) {
        try {
            $fi = Get-Item -LiteralPath $DbPath
            $dbTicks = $fi.LastWriteTimeUtc.Ticks
            $dbLen = $fi.Length
        } catch {}
    }
    $walTicks = 0L; $walLen = 0L
    $walPath = $DbPath + "-wal"
    if ($DbPath -and (Test-Path -LiteralPath $walPath)) {
        try {
            $wfi = Get-Item -LiteralPath $walPath
            $walTicks = $wfi.LastWriteTimeUtc.Ticks
            $walLen = $wfi.Length
        } catch {}
    }
    $calTicks = 0L; $calLen = 0L
    if ($DataDir) {
        $calFile = Join-Path $DataDir "calibration.json"
        if (Test-Path -LiteralPath $calFile) {
            try {
                $cfi = Get-Item -LiteralPath $calFile
                $calTicks = $cfi.LastWriteTimeUtc.Ticks
                $calLen = $cfi.Length
            } catch {}
        }
    }
    $cacheKey = "$DbPath|$Days|$($endDate.ToString('yyyy-MM-dd'))|$dbTicks|$dbLen|$walTicks|$walLen|$calTicks|$calLen"
    $cached = if ($script:TokenStatsAggCache -and $script:TokenStatsAggCache.ContainsKey($cacheKey)) { $script:TokenStatsAggCache[$cacheKey] } else { $null }

    $calObj = $null
    $updated = $null
    $delegateOk = 0
    $delegateFail = 0
    $directTurns = 0
    $delegateTurns = 0
    $netSaved = 0
    $ratioDirect = $null
    $ratioDelegate = $null
    $summary = $null
    $dailyList = @()
    $weeklyList = @()
    $points = New-Object System.Collections.ArrayList
    $turnAgyElapsedMap = @{}
    $turnTaskMap = @{}
    $recent = New-Object System.Collections.ArrayList
    $recentTotal = 0
    $recentPages = 1
    $hasTurns = $false

    if ($cached) {
        $summary           = $cached.summary
        $dailyList         = $cached.daily
        $weeklyList        = $cached.weekly_accuracy
        $points            = $cached.points
        $calObj            = $cached.calibration
        $updated           = $cached.updated
        $turnAgyElapsedMap = $cached.turnAgyElapsedMap
        $turnTaskMap       = $cached.turnTaskMap
        $hasTurns          = $cached.hasTurns
    } else {
        $dailyMap = [ordered]@{}
        $cur = $startDate
        while ($cur -le $endDate) {
            $dStr = $cur.ToString("yyyy-MM-dd")
            $dailyMap[$dStr] = [ordered]@{
                date           = $dStr
                ok             = 0
                fail           = 0
                saved          = 0
                cum_saved      = 0
                direct_turns   = 0
                delegate_turns = 0
            }
            $cur = $cur.AddDays(1)
        }
        if ($DataDir) {
            $calFile = Join-Path $DataDir "calibration.json"
            if (Test-Path -LiteralPath $calFile) {
                try {
                    $rawCal = [System.IO.File]::ReadAllText($calFile, [System.Text.Encoding]::UTF8)
                    $calObj = ConvertFrom-Json -InputObject $rawCal
                    if ($calObj -and $calObj.updated) {
                        $updated = [string]$calObj.updated
                    }
                } catch {}
            }
        }
        $weeklyMap = [ordered]@{}
    }

    if ($DbPath -and (Test-Path -LiteralPath $DbPath) -and (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) {
        $db = $null
        try {
            $db = Open-AgyDb $DbPath

            # 정렬 및 필터 가속을 위한 인덱스 보장
            try {
                [void]$db.Execute("CREATE INDEX IF NOT EXISTS idx_token_turns_ts ON token_turns(turn_ts DESC)", $null)
                [void]$db.Execute("CREATE INDEX IF NOT EXISTS idx_token_turns_path_ts ON token_turns(path, turn_ts DESC)", $null)
            } catch {}

            if (-not $cached) {
                # 1) tasks 표: 위임 성공/실패 집계
                $hasTasks = $false
                try {
                    [void]$db.Query("SELECT 1 FROM tasks LIMIT 1", $null)
                    $hasTasks = $true
                } catch {}

                if ($hasTasks) {
                    $taskRows = @($db.Query("SELECT timestamp, status FROM tasks", $null))
                    foreach ($tr in $taskRows) {
                        $ldt = ConvertTo-LocalDateValue ([string]$tr['timestamp'])
                        if ($ldt -and $ldt.Date -ge $startDate -and $ldt.Date -le $endDate) {
                            $dStr = $ldt.ToString("yyyy-MM-dd")
                            $st = [string]$tr['status']
                            $isOk = ($st -eq 'OK')
                            if ($dailyMap.Contains($dStr)) {
                                if ($isOk) { $dailyMap[$dStr].ok++ } else { $dailyMap[$dStr].fail++ }
                            }
                            if ($isOk) { $delegateOk++ } else { $delegateFail++ }
                        }
                    }
                }
            }

            # 2) token_turns 표
            if (-not $cached) {
                try {
                    [void]$db.Query("SELECT 1 FROM token_turns LIMIT 1", $null)
                    $hasTurns = $true
                } catch {}
            }

            $turnCols = @()
            if ($hasTurns) {
                try {
                    $turnCols = @($db.Query("PRAGMA table_info(token_turns)", $null) | ForEach-Object { [string]$_['name'] })
                } catch {}
            }
            $hasEstVerCol = ($turnCols -contains 'est_ver')
            $hasCrTokensCol = ($turnCols -contains 'cr_tokens')
            $hasDurSecCol = ($turnCols -contains 'dur_sec')
            $hasEstTimeDirCol = ($turnCols -contains 'est_time_direct')
            $hasEstTimeDelCol = ($turnCols -contains 'est_time_delegate')
            $hasCallsRelatedCol = ($turnCols -contains 'calls_related')
            $hasDRelatedCol = ($turnCols -contains 'd_related')
            $hasEndTsCol = ($turnCols -contains 'end_ts')
            $hasEstKindCol = ($turnCols -contains 'est_kind')
            $hasChoiceReasonCol = ($turnCols -contains 'choice_reason')
            $hasChoiceCol = ($turnCols -contains 'choice')
            $hasLevelCol = ($turnCols -contains 'level')

            # Tasks 연결 표에서 각 턴의 agy 최대 작업 시간 (MAX elapsed_sec) 조회
            # 위임 턴의 실제 시간: 위임 카드와 같은 기준(agy 처리 + Claude 쪽). agy 는 그 턴 작업 중 가장 긴 것(동시에 돌면 겹침),
            # Claude 쪽은 턴 시간 x (위임 관련 호출 / 전체 호출). 둘 다 없으면 $null.
            # 예상은 질문을 받을 때 정해 기록한 값 그대로 쓴다(위임/직접 결정의 근거라 나중에 바뀌면 안 된다). 예전에는 턴 전체 예상에서
            # 위임과 무관한 작업의 실측을 빼 "위임한 일만의 예상"으로 맞췄지만, 통계 단위가 질문이 된 뒤로는 결정 시점 값을 그대로 비교한다.
            $delegateJobEstimate = {
                param($row, [double]$fullEst)
                return $fullEst
            }
            $delegateJobTimeEstimate = {
                param($row, [double]$fullEst)
                return $fullEst
            }
            $delegateTotalSec = {
                param($row, $agySec)
                $cAll = if ($row['calls'] -ne $null -and $row['calls'] -ne [DBNull]::Value) { [double]$row['calls'] } else { 0.0 }
                $cRel = if ($hasCallsRelatedCol -and $row['calls_related'] -ne $null -and $row['calls_related'] -ne [DBNull]::Value) { [double]$row['calls_related'] } else { $cAll }
                $dur = if ($hasDurSecCol -and $row['dur_sec'] -ne $null -and $row['dur_sec'] -ne [DBNull]::Value) { [double]$row['dur_sec'] } else { $null }
                $cl = if ($dur -ne $null -and $cAll -gt 0) { $dur * [Math]::Min(1.0, $cRel / $cAll) } else { $null }
                if ($agySec -eq $null -and $cl -eq $null) { return $null }
                return [double]$(if ($agySec -ne $null) { $agySec } else { 0.0 }) + [double]$(if ($cl -ne $null) { $cl } else { 0.0 })
            }

            if (-not $cached -and $hasTurns) {
                $hasLinks = $false
                try {
                    [void]$db.Query("SELECT 1 FROM token_task_links LIMIT 1", $null)
                    $hasLinks = $true
                } catch {}
                if ($hasLinks) {
                    try {
                        $linkElapsedRows = @($db.Query("SELECT l.file, l.turn_ts, MAX(CAST(tk.elapsed_sec AS REAL)) AS max_elapsed FROM token_task_links l INNER JOIN tasks tk ON l.task_id = tk.task_id WHERE tk.elapsed_sec IS NOT NULL GROUP BY l.file, l.turn_ts", $null))
                        foreach ($ler in $linkElapsedRows) {
                            $k = ([string]$ler['file']) + "|" + ([string]$ler['turn_ts'])
                            $turnAgyElapsedMap[$k] = [double]$ler['max_elapsed']
                        }
                    } catch {}
                }

                $turnRows = @($db.Query("SELECT * FROM token_turns ORDER BY turn_ts ASC", $null))

                $inPeriodTurns = New-Object System.Collections.ArrayList
                foreach ($r in $turnRows) {
                    $ldt = ConvertTo-LocalDateValue ([string]$r['turn_ts'])
                    if ($ldt -and $ldt.Date -ge $startDate -and $ldt.Date -le $endDate) {
                        [void]$inPeriodTurns.Add(@{ Row = $r; LocalDt = $ldt; DateStr = $ldt.ToString("yyyy-MM-dd") })
                    }
                }

                $directRatios = New-Object System.Collections.ArrayList
                $delegateRatios = New-Object System.Collections.ArrayList

                $directDurSecList = New-Object System.Collections.ArrayList
                $delegateDurSecList = New-Object System.Collections.ArrayList
                $delegateAgySecList = New-Object System.Collections.ArrayList
                $directTimeRatios = New-Object System.Collections.ArrayList
                $delegateTimeRatios = New-Object System.Collections.ArrayList

                foreach ($item in $inPeriodTurns) {
                    $r = $item.Row
                    $p = [string]$r['path']
                    $fKey = ([string]$r['file']) + "|" + ([string]$r['turn_ts'])
                    $dTokensVal = if ($r['d_tokens'] -ne $null -and $r['d_tokens'] -ne [DBNull]::Value) { [double]$r['d_tokens'] } else { $null }
                    $estDirectVal = if ($r['est_direct'] -ne $null -and $r['est_direct'] -ne [DBNull]::Value) { [double]$r['est_direct'] } else { $null }
                    $estDelegateVal = if ($r['est_delegate'] -ne $null -and $r['est_delegate'] -ne [DBNull]::Value) { [double]$r['est_delegate'] } else { $null }
                    $dRelatedVal = if ($hasDRelatedCol -and $r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { [double]$r['d_related'] } else { $null }
                    $effD = if ($p -eq 'delegate' -and $dRelatedVal -ne $null) { $dRelatedVal } else { $dTokensVal }

                    $estVer = if ($hasEstVerCol -and $r['est_ver'] -ne $null -and $r['est_ver'] -ne [DBNull]::Value) { [string]$r['est_ver'] } else { if (-not $hasEstVerCol) { 'v2' } else { $null } }
                    $isV2 = ($estVer -eq 'v2')

                    $durSecVal = if ($hasDurSecCol -and $r['dur_sec'] -ne $null -and $r['dur_sec'] -ne [DBNull]::Value) { [double]$r['dur_sec'] } else { $null }
                    $estTimeDirVal = if ($hasEstTimeDirCol -and $r['est_time_direct'] -ne $null -and $r['est_time_direct'] -ne [DBNull]::Value) { [double]$r['est_time_direct'] } else { $null }
                    $estTimeDelVal = if ($hasEstTimeDelCol -and $r['est_time_delegate'] -ne $null -and $r['est_time_delegate'] -ne [DBNull]::Value) { [double]$r['est_time_delegate'] } else { $null }

                    if ($p -eq 'direct') {
                        $directTurns++
                        $dailyMap[$item.DateStr].direct_turns++
                        # v2 턴만 보정 비율에 포함
                        if ($isV2 -and $estDirectVal -ne $null -and $dTokensVal -ne $null -and $dTokensVal -gt 0) {
                            [void]$directRatios.Add($estDirectVal / $dTokensVal)
                        }
                        if ($durSecVal -ne $null) {
                            [void]$directDurSecList.Add($durSecVal)
                            if ($isV2 -and $estTimeDirVal -ne $null -and $durSecVal -gt 0) {
                                [void]$directTimeRatios.Add($estTimeDirVal / $durSecVal)
                            }
                        }
                    } elseif ($p -eq 'delegate') {
                        $delegateTurns++
                        $dailyMap[$item.DateStr].delegate_turns++
                        # v2 턴만 보정 비율에 포함
                        if ($isV2 -and $estDelegateVal -ne $null -and $effD -ne $null -and $effD -gt 0) {
                            [void]$delegateRatios.Add((& $delegateJobEstimate $r $estDelegateVal) / $effD)
                        }
                        if ($durSecVal -ne $null) {
                            [void]$delegateDurSecList.Add($durSecVal)
                        }
                        if ($turnAgyElapsedMap.ContainsKey($fKey)) {
                            $agyElapsed = $turnAgyElapsedMap[$fKey]
                            [void]$delegateAgySecList.Add($agyElapsed)
                            $delTotal = & $delegateTotalSec $r $agyElapsed
                            if ($isV2 -and $estTimeDelVal -ne $null -and $delTotal -ne $null -and $delTotal -gt 0) {
                                [void]$delegateTimeRatios.Add($estTimeDelVal / $delTotal)
                            }
                        }
                    }
                }

                $rawRatioDirect = if ($directRatios.Count -ge 5) { Get-TokenMedianValue $directRatios } else { $null }
                $rawRatioDelegate = if ($delegateRatios.Count -ge 5) { Get-TokenMedianValue $delegateRatios } else { $null }

                $ratioDirect = if ($rawRatioDirect -ne $null) { [Math]::Round([double]$rawRatioDirect, 2) } else { $null }
                $ratioDelegate = if ($rawRatioDelegate -ne $null) { [Math]::Round([double]$rawRatioDelegate, 2) } else { $null }

                $effectiveRatioDirect = if ($rawRatioDirect -ne $null) { [Math]::Max(0.2, [Math]::Min(5.0, [double]$rawRatioDirect)) } else { 1.0 }
                $effectiveRatioDelegate = if ($rawRatioDelegate -ne $null) { [Math]::Max(0.2, [Math]::Min(5.0, [double]$rawRatioDelegate)) } else { 1.0 }

                # 시간 평균 및 예상÷실제 중앙값
                $directAvgS = if ($directDurSecList.Count -gt 0) {
                    $s = 0.0; foreach ($v in $directDurSecList) { $s += $v }; [int][Math]::Round($s / $directDurSecList.Count)
                } else { $null }

                $delegateTurnAvgS = if ($delegateDurSecList.Count -gt 0) {
                    $s = 0.0; foreach ($v in $delegateDurSecList) { $s += $v }; [int][Math]::Round($s / $delegateDurSecList.Count)
                } else { $null }

                $delegateAgyAvgS = if ($delegateAgySecList.Count -gt 0) {
                    $s = 0.0; foreach ($v in $delegateAgySecList) { $s += $v }; [int][Math]::Round($s / $delegateAgySecList.Count)
                } else { $null }

                $rawRatioTimeDirect = if ($directTimeRatios.Count -ge 5) { Get-TokenMedianValue $directTimeRatios } else { $null }
                $rawRatioTimeDelegate = if ($delegateTimeRatios.Count -ge 5) { Get-TokenMedianValue $delegateTimeRatios } else { $null }

                $ratioTimeDirect = if ($rawRatioTimeDirect -ne $null) { [Math]::Round([double]$rawRatioTimeDirect, 2) } else { $null }
                $ratioTimeDelegate = if ($rawRatioTimeDelegate -ne $null) { [Math]::Round([double]$rawRatioTimeDelegate, 2) } else { $null }

                $timeSummary = [ordered]@{
                    direct_avg_s        = $directAvgS
                    delegate_agy_avg_s  = $delegateAgyAvgS
                    delegate_turn_avg_s = $delegateTurnAvgS
                    ratio_time_direct   = $ratioTimeDirect
                    ratio_time_delegate = $ratioTimeDelegate
                }

                foreach ($item in $inPeriodTurns) {
                    $r = $item.Row
                    $p = [string]$r['path']
                    $fKey = ([string]$r['file']) + "|" + ([string]$r['turn_ts'])
                    $dTokensVal = if ($r['d_tokens'] -ne $null -and $r['d_tokens'] -ne [DBNull]::Value) { [double]$r['d_tokens'] } else { $null }
                    $estDirectVal = if ($r['est_direct'] -ne $null -and $r['est_direct'] -ne [DBNull]::Value) { [double]$r['est_direct'] } else { $null }
                    $estDelegateVal = if ($r['est_delegate'] -ne $null -and $r['est_delegate'] -ne [DBNull]::Value) { [double]$r['est_delegate'] } else { $null }
                    $callsVal = if ($r['calls'] -ne $null -and $r['calls'] -ne [DBNull]::Value) { [int]$r['calls'] } else { 0 }
                    $callsRelatedVal = if ($hasCallsRelatedCol -and $r['calls_related'] -ne $null -and $r['calls_related'] -ne [DBNull]::Value) { [int]$r['calls_related'] } else { $null }
                    $dRelatedVal = if ($hasDRelatedCol -and $r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { [double]$r['d_related'] } else { $null }

                    $effD = if ($p -eq 'delegate' -and $dRelatedVal -ne $null) { $dRelatedVal } else { $dTokensVal }
                    $effCalls = if ($p -eq 'delegate' -and $callsRelatedVal -ne $null) { $callsRelatedVal } else { $callsVal }

                    $estVer = if ($hasEstVerCol -and $r['est_ver'] -ne $null -and $r['est_ver'] -ne [DBNull]::Value) { [string]$r['est_ver'] } else { if (-not $hasEstVerCol) { 'v2' } else { $null } }
                    $isV2 = ($estVer -eq 'v2')

                    $durSecVal = if ($hasDurSecCol -and $r['dur_sec'] -ne $null -and $r['dur_sec'] -ne [DBNull]::Value) { [double]$r['dur_sec'] } else { $null }
                    $estTimeDirVal = if ($hasEstTimeDirCol -and $r['est_time_direct'] -ne $null -and $r['est_time_direct'] -ne [DBNull]::Value) { [double]$r['est_time_direct'] } else { $null }
                    $estTimeDelVal = if ($hasEstTimeDelCol -and $r['est_time_delegate'] -ne $null -and $r['est_time_delegate'] -ne [DBNull]::Value) { [double]$r['est_time_delegate'] } else { $null }

                    if (($p -eq 'direct' -or $p -eq 'delegate') -and $effD -ne $null) {
                        [void]$points.Add([ordered]@{
                            path   = $p
                            calls  = $effCalls
                            actual = [int]$effD
                        })
                    }

                    $tSaved = $null
                    if ($effD -ne $null) {
                        # 손익은 위임한 질문만 센다: 절약 = 직접 했을 때의 예상(결정 시점 값) - 위임으로만 쓴 실제 토큰. 화면의 증감은 부호를 뒤집어 보인다.
                        # 직접 처리한 질문의 토큰은 원래 써야 할 토큰이라 손익과 관계없고, agy 토큰도 넣지 않는다.
                        if ($p -eq 'delegate' -and $estDirectVal -ne $null) {
                            $tSaved = [int][Math]::Round($estDirectVal) - [int][Math]::Round($effD)
                        }
                    }
                    if ($tSaved -ne $null) {
                        $dailyMap[$item.DateStr].saved += $tSaved
                        $netSaved += $tSaved
                    }

                    $wk = Get-IsoWeekStringValue $item.LocalDt
                    if (-not $weeklyMap.Contains($wk)) {
                        $weeklyMap[$wk] = @{
                            direct        = New-Object System.Collections.ArrayList
                            delegate      = New-Object System.Collections.ArrayList
                            time_direct   = New-Object System.Collections.ArrayList
                            time_delegate = New-Object System.Collections.ArrayList
                        }
                    }
                    if ($isV2) {
                        if ($p -eq 'direct') {
                            if ($estDirectVal -ne $null -and $dTokensVal -ne $null -and $dTokensVal -gt 0) {
                                [void]$weeklyMap[$wk].direct.Add($estDirectVal / $dTokensVal)
                            }
                            if ($estTimeDirVal -ne $null -and $durSecVal -ne $null -and $durSecVal -gt 0) {
                                [void]$weeklyMap[$wk].time_direct.Add($estTimeDirVal / $durSecVal)
                            }
                        } elseif ($p -eq 'delegate') {
                            if ($estDelegateVal -ne $null -and $effD -ne $null -and $effD -gt 0) {
                                [void]$weeklyMap[$wk].delegate.Add((& $delegateJobEstimate $r $estDelegateVal) / $effD)
                            }
                            if ($turnAgyElapsedMap.ContainsKey($fKey) -and $estTimeDelVal -ne $null) {
                                $agyElapsed = $turnAgyElapsedMap[$fKey]
                                if ($agyElapsed -gt 0) {
                                    [void]$weeklyMap[$wk].time_delegate.Add($estTimeDelVal / $agyElapsed)
                                }
                            }
                        }
                    }
                }

                # 3) Recent turns with paging and path filter 준비 (task links)
                try {
                    $linkRows = @($db.Query("SELECT file, turn_ts, task_id FROM token_task_links ORDER BY task_id ASC", $null))
                    foreach ($lr in $linkRows) {
                        $k = ([string]$lr['file']) + "|" + ([string]$lr['turn_ts'])
                        if (-not $turnTaskMap.ContainsKey($k)) {
                            $turnTaskMap[$k] = New-Object System.Collections.ArrayList
                        }
                        [void]$turnTaskMap[$k].Add([string]$lr['task_id'])
                    }
                } catch {}
            }

            # 3) Recent turns with paging and path filter
            if ($hasTurns) {
                $countSql = "SELECT COUNT(*) AS cnt FROM token_turns"
                $countArgs = $null
                if ($RecentPath) {
                    $countSql += " WHERE path = ?"
                    $countArgs = [object[]]@($RecentPath)
                }
                $cntRows = @($db.Query($countSql, $countArgs))
                if ($cntRows.Count -gt 0 -and $null -ne $cntRows[0]['cnt'] -and $cntRows[0]['cnt'] -ne [DBNull]::Value) {
                    $recentTotal = [int]$cntRows[0]['cnt']
                }
                $recentPages = [int][Math]::Max(1, [Math]::Ceiling([double]$recentTotal / [double]$RecentPageSize))
                if ($RecentPage -gt $recentPages) {
                    $RecentPage = $recentPages
                }
                if ($RecentPage -lt 1) {
                    $RecentPage = 1
                }
                $offset = [int64](($RecentPage - 1) * $RecentPageSize)

                $selectSql = "SELECT * FROM token_turns"
                $selectArgs = $null
                if ($RecentPath) {
                    $selectSql += " WHERE path = ? ORDER BY turn_ts DESC LIMIT ? OFFSET ?"
                    $selectArgs = [object[]]@($RecentPath, [int64]$RecentPageSize, $offset)
                } else {
                    $selectSql += " ORDER BY turn_ts DESC LIMIT ? OFFSET ?"
                    $selectArgs = [object[]]@([int64]$RecentPageSize, $offset)
                }
                $recentRows = @($db.Query($selectSql, $selectArgs))
                foreach ($r in $recentRows) {
                    $p = [string]$r['path']
                    $fKey = ([string]$r['file']) + "|" + ([string]$r['turn_ts'])
                    $dTokensVal = if ($r['d_tokens'] -ne $null -and $r['d_tokens'] -ne [DBNull]::Value) { [double]$r['d_tokens'] } else { $null }
                    $estDirectVal = if ($r['est_direct'] -ne $null -and $r['est_direct'] -ne [DBNull]::Value) { [double]$r['est_direct'] } else { $null }
                    $estDelegateVal = if ($r['est_delegate'] -ne $null -and $r['est_delegate'] -ne [DBNull]::Value) { [double]$r['est_delegate'] } else { $null }
                    $callsVal = if ($r['calls'] -ne $null -and $r['calls'] -ne [DBNull]::Value) { [int]$r['calls'] } else { 0 }
                    $callsRelatedVal = if ($hasCallsRelatedCol -and $r['calls_related'] -ne $null -and $r['calls_related'] -ne [DBNull]::Value) { [int]$r['calls_related'] } else { $null }
                    $dRelatedVal = if ($hasDRelatedCol -and $r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { [double]$r['d_related'] } else { $null }

                    $effD = if ($p -eq 'delegate' -and $dRelatedVal -ne $null) { $dRelatedVal } else { $dTokensVal }
                    $effCalls = if ($p -eq 'delegate' -and $callsRelatedVal -ne $null) { $callsRelatedVal } else { $callsVal }

                    $estVerVal = if ($hasEstVerCol -and $r['est_ver'] -ne $null -and $r['est_ver'] -ne [DBNull]::Value) { [string]$r['est_ver'] } else { if (-not $hasEstVerCol) { 'v2' } else { $null } }

                    # 직접 처리했어도 생길 공통분(위임 무관 작업)을 뺀 값끼리 비교한다: 위임 턴은 예상(직접·위임)에서 공통분을 빼고 실제는 위임 관련분(d_related)을 쓴다
                    $estDirectNet = $estDirectVal
                    $estDelegateNet = $estDelegateVal
                    $commonTok = $null
                    if ($p -eq 'delegate') {
                        if ($estDirectVal -ne $null) { $estDirectNet = & $delegateJobEstimate $r $estDirectVal }
                        if ($estDelegateVal -ne $null) { $estDelegateNet = & $delegateJobEstimate $r $estDelegateVal }
                        if ($dTokensVal -ne $null -and $dRelatedVal -ne $null) { $commonTok = [int][Math]::Max(0.0, $dTokensVal - $dRelatedVal) }
                    }
                    $estVal = if ($p -eq 'direct') { $estDirectNet } elseif ($p -eq 'delegate') { $estDelegateNet } else { $null }
                    $ratioVal = if ($estVal -ne $null -and $effD -ne $null -and $effD -gt 0) {
                        [Math]::Round($estVal / $effD, 2)
                    } else { $null }

                    $tSaved = $null
                    if ($effD -ne $null) {
                        if ($p -eq 'delegate' -and $estDirectNet -ne $null) {
                            # 위임 질문의 증감 = 위임으로만 쓴 실제 - 직접 했을 때의 예상(위임해서 아낀/더 쓴 토큰. 맨 위 손익과 같은 기준)
                            # 표의 증감은 "실제 - 그 턴이 간 길의 예상"(표에 보이는 값끼리, 보정 비율은 곱하지 않는다): 위임 턴은 공통분을 뺀 예상 위임(표의 위임 칸). 화면의 증감은 saved 의 부호를 뒤집어 보인다
                            $tSaved = [int][Math]::Round($estDirectNet) - [int][Math]::Round($effD)
                        } elseif ($p -eq 'direct' -and $estDirectVal -ne $null) {
                            # 직접 턴: 예상 직접이 얼마나 빗나갔는지(위임 예상과 비교하지 않는다)
                            $tSaved = [int][Math]::Round($estDirectVal) - [int][Math]::Round($effD)
                        }
                    }

                    $crTokensVal = if ($hasCrTokensCol -and $r['cr_tokens'] -ne $null -and $r['cr_tokens'] -ne [DBNull]::Value) { [int]$r['cr_tokens'] } else { $null }
                    $endTsVal = if ($hasEndTsCol -and $r['end_ts'] -ne $null -and $r['end_ts'] -ne [DBNull]::Value) { [string]$r['end_ts'] } else { $null }

                    $estTimeVal = $null
                    if ($p -eq 'direct' -and $hasEstTimeDirCol -and $r['est_time_direct'] -ne $null -and $r['est_time_direct'] -ne [DBNull]::Value) {
                        $estTimeVal = [int]$r['est_time_direct']
                    } elseif ($p -eq 'delegate' -and $hasEstTimeDelCol -and $r['est_time_delegate'] -ne $null -and $r['est_time_delegate'] -ne [DBNull]::Value) {
                        $estTimeVal = [int]$r['est_time_delegate']
                    }

                    $durSecVal = if ($hasDurSecCol -and $r['dur_sec'] -ne $null -and $r['dur_sec'] -ne [DBNull]::Value) { [int]$r['dur_sec'] } else { $null }
                    $actualTimeVal = $null
                    if ($p -eq 'direct') {
                        $actualTimeVal = $durSecVal
                    } elseif ($p -eq 'delegate') {
                        $agyForTurn = if ($turnAgyElapsedMap.ContainsKey($fKey)) { [double]$turnAgyElapsedMap[$fKey] } else { $null }
                        $delTotalR = if ($agyForTurn -ne $null) { & $delegateTotalSec $r $agyForTurn } else { $null }
                        if ($delTotalR -ne $null) { $actualTimeVal = [int][Math]::Round($delTotalR) }
                    }
                    # 위임 질문인데 agy 작업과 연결되지 않아 위임 시간을 모르면(대화 기록에 작업 번호가 안 남은 경우 등) 그 질문에 걸린 시간 전체를 위임 시간으로 본다
                    $delTimeIsWhole = $false
                    if ($p -eq 'delegate' -and $null -eq $actualTimeVal -and $null -ne $durSecVal) { $actualTimeVal = $durSecVal; $delTimeIsWhole = $true }

                    # 시간도 같은 기준: 예상 시간(직접·위임)에서 위임 턴은 위임 무관 Claude 시간을 빼고, 증감 = 실제 - 다른 쪽으로 했다면의 예상(+ 늘어남 · - 절약)
                    $estTimeDirRaw = if ($hasEstTimeDirCol -and $r['est_time_direct'] -ne $null -and $r['est_time_direct'] -ne [DBNull]::Value) { [double]$r['est_time_direct'] } else { $null }
                    $estTimeDelRaw = if ($hasEstTimeDelCol -and $r['est_time_delegate'] -ne $null -and $r['est_time_delegate'] -ne [DBNull]::Value) { [double]$r['est_time_delegate'] } else { $null }
                    $estTimeDirNet = $estTimeDirRaw
                    $estTimeDelNet = $estTimeDelRaw
                    if ($p -eq 'delegate') {
                        if ($estTimeDirRaw -ne $null) { $estTimeDirNet = & $delegateJobTimeEstimate $r $estTimeDirRaw }
                        if ($estTimeDelRaw -ne $null) { $estTimeDelNet = & $delegateJobTimeEstimate $r $estTimeDelRaw }
                    }
                    # 시간 증감은 두 가지(표에 보이는 값끼리): 직접 = 직접 시간 - 예상 직접 시간, 위임 = 위임 시간 - 예상 위임 시간. + 는 예상보다 더 걸림
                    # 실제 시간은 그 질문이 간 길 한쪽에만 있다: 직접 질문은 직접 시간, 위임 질문은 위임 시간. 증감도 그 길의 예상과만 비교한다(토큰 증감과 같은 기준)
                    $timeDeltaDirect = if ($p -ne 'delegate' -and $durSecVal -ne $null -and $estTimeDirNet -ne $null) { [int]$durSecVal - [int][Math]::Round($estTimeDirNet) } else { $null }
                    $estTimeDelForDelta = if ($delTimeIsWhole) { $estTimeDelRaw } else { $estTimeDelNet }
                    $timeDeltaDelegate = if ($p -eq 'delegate' -and $actualTimeVal -ne $null -and $estTimeDelForDelta -ne $null) { [int]$actualTimeVal - [int][Math]::Round($estTimeDelForDelta) } else { $null }

                    $rowTaskIds = @(if ($turnTaskMap.ContainsKey($fKey)) { $turnTaskMap[$fKey].ToArray() } else { @() })

                    [void]$recent.Add([ordered]@{
                        ts                = [string]$r['turn_ts']
                        end_ts            = $endTsVal
                        path              = $p
                        calls             = $effCalls
                        calls_related     = $callsRelatedVal
                        calls_total       = $callsVal
                        estimate          = if ($estVal -ne $null) { [int]$estVal } else { $null }
                        est_direct        = if ($estDirectVal -ne $null) { [int]$estDirectVal } else { $null }
                        est_delegate      = if ($estDelegateVal -ne $null) { [int]$estDelegateVal } else { $null }
                        est_direct_net    = if ($estDirectNet -ne $null) { [int][Math]::Round($estDirectNet) } else { $null }
                        est_delegate_net  = if ($estDelegateNet -ne $null) { [int][Math]::Round($estDelegateNet) } else { $null }
                        actual            = if ($effD -ne $null) { [int]$effD } else { $null }
                        actual_total      = if ($dTokensVal -ne $null) { [int]$dTokensVal } else { $null }
                        common_tokens     = $commonTok
                        ratio             = $ratioVal
                        saved             = $tSaved
                        project           = [string]$r['project']
                        est_ver           = $estVerVal
                        est_kind          = $(if ($hasEstKindCol -and $null -ne $r['est_kind'] -and $r['est_kind'] -ne [DBNull]::Value) { [string]$r['est_kind'] } else { $null })
                        choice_reason     = $(if ($hasChoiceReasonCol -and $null -ne $r['choice_reason'] -and $r['choice_reason'] -ne [DBNull]::Value) { [string]$r['choice_reason'] } else { $null })
                        choice            = $(if ($hasChoiceCol -and $null -ne $r['choice'] -and $r['choice'] -ne [DBNull]::Value) { [string]$r['choice'] } else { $null })
                        task_ids          = $rowTaskIds
                        level             = $(if ($hasLevelCol -and $null -ne $r['level'] -and $r['level'] -ne [DBNull]::Value) { [string]$r['level'] } else { $null })
                        cr_tokens         = $crTokensVal
                        est_time          = $estTimeVal
                        est_time_direct   = if ($estTimeDirRaw -ne $null) { [int]$estTimeDirRaw } else { $null }
                        est_time_delegate = if ($estTimeDelRaw -ne $null) { [int]$estTimeDelRaw } else { $null }
                        est_time_direct_net   = if ($estTimeDirNet -ne $null) { [int][Math]::Round($estTimeDirNet) } else { $null }
                        est_time_delegate_net = if ($estTimeDelNet -ne $null) { [int][Math]::Round($estTimeDelNet) } else { $null }
                        actual_time       = $actualTimeVal
                        time_delta_direct   = $timeDeltaDirect
                        time_delta_delegate = $timeDeltaDelegate
                        claude_wall       = $durSecVal
                    })
                }
            }
        } finally {
            if ($db) { $db.Dispose() }
        }
    }

    if (-not $cached) {
        $dailyList = @()
        $runningCum = 0
        foreach ($k in $dailyMap.Keys) {
            $item = $dailyMap[$k]
            $runningCum += [int]$item.saved
            $item.cum_saved = $runningCum
            $dailyList += $item
        }

        $weeklyList = @()
        $sortedWeeks = @($weeklyMap.Keys | Sort-Object)
        foreach ($wk in $sortedWeeks) {
            $dirMed = if ($weeklyMap[$wk].direct -and $weeklyMap[$wk].direct.Count -gt 0) {
                [Math]::Round([double](Get-TokenMedianValue $weeklyMap[$wk].direct), 2)
            } else { $null }
            $delMed = if ($weeklyMap[$wk].delegate -and $weeklyMap[$wk].delegate.Count -gt 0) {
                [Math]::Round([double](Get-TokenMedianValue $weeklyMap[$wk].delegate), 2)
            } else { $null }
            $timeDirMed = if ($weeklyMap[$wk].time_direct -and $weeklyMap[$wk].time_direct.Count -gt 0) {
                [Math]::Round([double](Get-TokenMedianValue $weeklyMap[$wk].time_direct), 2)
            } else { $null }
            $timeDelMed = if ($weeklyMap[$wk].time_delegate -and $weeklyMap[$wk].time_delegate.Count -gt 0) {
                [Math]::Round([double](Get-TokenMedianValue $weeklyMap[$wk].time_delegate), 2)
            } else { $null }
            $weeklyList += [ordered]@{
                week          = $wk
                direct        = $dirMed
                delegate      = $delMed
                time_direct   = $timeDirMed
                time_delegate = $timeDelMed
            }
        }

        $totTasks = $delegateOk + $delegateFail
        $successRate = if ($totTasks -gt 0) { [Math]::Round($delegateOk / $totTasks, 2) } else { $null }
        $samples = $directTurns + $delegateTurns

        $collectObj = [ordered]@{
            active     = $false
            delegate_n = 0
            target     = 20
        }
        if ($calObj -and $calObj.collect) {
            $c = $calObj.collect
            $collectObj.active = [bool]$c.active
            if ($c.delegate_n -ne $null) { $collectObj.delegate_n = [int]$c.delegate_n }
            if ($c.target -ne $null) { $collectObj.target = [int]$c.target }
        }

        if (-not $timeSummary) {
            $timeSummary = [ordered]@{
                direct_avg_s        = $null
                delegate_agy_avg_s  = $null
                delegate_turn_avg_s = $null
                ratio_time_direct   = $null
                ratio_time_delegate = $null
            }
        }

        $summary = [ordered]@{
            delegate_ok    = $delegateOk
            delegate_fail  = $delegateFail
            success_rate   = $successRate
            delegate_turns = $delegateTurns
            direct_turns   = $directTurns
            net_saved      = $netSaved
            ratio_direct   = $ratioDirect
            ratio_delegate = $ratioDelegate
            samples        = $samples
            collect        = $collectObj
            time           = $timeSummary
        }

        # 집계 결과 캐시 보관 (최대 10개까지 유지)
        if (-not $script:TokenStatsAggCache) { $script:TokenStatsAggCache = @{} }
        if ($script:TokenStatsAggCache.Count -gt 10) { $script:TokenStatsAggCache.Clear() }
        $script:TokenStatsAggCache[$cacheKey] = @{
            summary           = $summary
            daily             = @($dailyList)
            weekly_accuracy   = @($weeklyList)
            points            = @($points)
            calibration       = $calObj
            updated           = $updated
            turnAgyElapsedMap = $turnAgyElapsedMap
            turnTaskMap       = $turnTaskMap
            hasTurns          = $hasTurns
        }
    }

    if (-not $hasTurns) {
        if ($RecentPage -gt $recentPages) { $RecentPage = $recentPages }
        if ($RecentPage -lt 1) { $RecentPage = 1 }
    }

    return [ordered]@{
        days             = $Days
        updated          = $updated
        calibration      = $calObj
        summary          = $summary
        daily            = @($dailyList)
        weekly_accuracy  = @($weeklyList)
        points           = @($points)
        recent           = @($recent)
        recent_page      = $RecentPage
        recent_page_size = $RecentPageSize
        recent_total     = $recentTotal
        recent_pages     = $recentPages
        recent_path      = $RecentPath
    }
}

# 위임한 턴의 예상(est_delegate)을 "위임한 일만의 예상"으로 맞춘다(token-stats.ps1 의 Get-TokenDelegateJobEstimate 와 같은 식. 고치면 함께 고친다).
function Get-ViewerDelegateJobEstimate([double]$Est, $DTokens, $DRelated, $Calls, $CallsRelated) {
    $dT = if ($null -ne $DTokens -and $DTokens -ne [DBNull]::Value -and [string]$DTokens -ne '') { [double]$DTokens } else { $null }
    $dR = if ($null -ne $DRelated -and $DRelated -ne [DBNull]::Value -and [string]$DRelated -ne '') { [double]$DRelated } else { $dT }
    $other = if ($null -ne $dT -and $null -ne $dR) { [Math]::Max(0.0, $dT - $dR) } else { 0.0 }
    $job = $Est - $other
    if ($job -gt 0.0) { return $job }
    $cAll = if ($null -ne $Calls -and $Calls -ne [DBNull]::Value -and [string]$Calls -ne '') { [double]$Calls } else { 0.0 }
    $cRel = if ($null -ne $CallsRelated -and $CallsRelated -ne [DBNull]::Value -and [string]$CallsRelated -ne '') { [double]$CallsRelated } else { $cAll }
    if ($cAll -gt 0.0) { return $Est * [Math]::Min(1.0, $cRel / $cAll) }
    return $Est
}

function Get-ViewerQaRecordsJson([string]$DbPath, [string]$DataDir = "", [long]$Since = 0) {
    if (-not (Test-Path -LiteralPath $DbPath)) { return ('{{{"records":[],"seq":{0},"total":0}}' -f $Since) }
    if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue)) {
        return (Get-QaRecordsJson $DbPath $Since)
    }

    $db = Open-AgyDb $DbPath
    try {
        $hasLinks = $false
        try {
            [void]$db.Query("SELECT 1 FROM token_task_links LIMIT 1", $null)
            $hasLinks = $true
        } catch { $hasLinks = $false }

        if (-not $hasLinks) {
            return (Get-QaRecordsJson $DbPath $Since)
        }

        $total = [int64]($db.Query('SELECT COUNT(*) AS n FROM tasks WHERE answer IS NOT NULL', $null))[0]['n']
        $rows = $db.Query('SELECT * FROM tasks WHERE answer IS NOT NULL AND updated_seq > ? ORDER BY updated_seq', [object[]]@($Since))
        if ($rows.Count -eq 0) {
            return ('{{{"records":[],"seq":{0},"total":{1}}}' -f $Since, $total)
        }

        # Calculate ratio_direct (v2 only if est_ver column exists)
        $ratioDirect = 1.0
        try {
            $hasTurns = $false
            try {
                [void]$db.Query("SELECT 1 FROM token_turns LIMIT 1", $null)
                $hasTurns = $true
            } catch { $hasTurns = $false }

            if ($hasTurns) {
                $turnCols = @()
                try {
                    $turnCols = @($db.Query("PRAGMA table_info(token_turns)", $null) | ForEach-Object { [string]$_['name'] })
                } catch {}
                $hasEstVerCol = ($turnCols -contains 'est_ver')
                $estVerFilter = if ($hasEstVerCol) { " AND est_ver = 'v2'" } else { "" }

                $turnRows = @($db.Query("SELECT est_direct, d_tokens FROM token_turns WHERE path = 'direct' AND est_direct IS NOT NULL AND d_tokens IS NOT NULL AND d_tokens > 0$estVerFilter", $null))
                $directRatios = New-Object System.Collections.ArrayList
                foreach ($tr in $turnRows) {
                    $ed = [double]$tr['est_direct']
                    $dt = [double]$tr['d_tokens']
                    if ($dt -gt 0) { [void]$directRatios.Add($ed / $dt) }
                }
                if ($directRatios.Count -ge 5) {
                    $med = Get-TokenMedianValue $directRatios
                    if ($med -ne $null) {
                        $ratioDirect = [Math]::Max(0.2, [Math]::Min(5.0, [double]$med))
                    }
                } elseif ($DataDir) {
                    $calPath = Join-Path $DataDir "calibration.json"
                    if (Test-Path -LiteralPath $calPath) {
                        try {
                            $calJson = Get-Content -LiteralPath $calPath -Raw -Encoding UTF8 | ConvertFrom-Json
                            if ($calJson.estimate_accuracy -and $calJson.estimate_accuracy.direct_ratio_median) {
                                $ratioDirect = [Math]::Max(0.2, [Math]::Min(5.0, [double]$calJson.estimate_accuracy.direct_ratio_median))
                            }
                        } catch {}
                    }
                }
            }
        } catch {}

        # 위임 예상의 보정 비율(직접과 같은 방식): 위임한 턴의 (예상 ÷ 실제 증가량) 중앙값. 표본이 5개 미만이면 calibration.json 값, 그것도 없으면 1.0
        $ratioDelegateCal = 1.0
        try {
            $dCols = @($db.Query("PRAGMA table_info(token_turns)", $null) | ForEach-Object { [string]$_['name'] })
            $dExpr = if ($dCols -contains 'd_related') { "COALESCE(d_related, d_tokens)" } else { "d_tokens" }
            $dVerFilter = if ($dCols -contains 'est_ver') { " AND est_ver = 'v2'" } else { "" }
            $callsRelSel = if ($dCols -contains 'calls_related') { "calls_related" } else { "NULL AS calls_related" }
            $dRelSel = if ($dCols -contains 'd_related') { "d_related" } else { "NULL AS d_related" }
            $delRows = @($db.Query("SELECT est_delegate, $dExpr AS d, d_tokens, $dRelSel, calls, $callsRelSel FROM token_turns WHERE path = 'delegate' AND est_delegate IS NOT NULL AND $dExpr IS NOT NULL AND $dExpr > 0$dVerFilter", $null))
            $delRatiosCal = New-Object System.Collections.ArrayList
            foreach ($dr in $delRows) {
                if ([double]$dr['d'] -gt 0) {
                    $jobEstQa = Get-ViewerDelegateJobEstimate ([double]$dr['est_delegate']) $dr['d_tokens'] $dr['d_related'] $dr['calls'] $dr['calls_related']
                    [void]$delRatiosCal.Add($jobEstQa / [double]$dr['d'])
                }
            }
            if ($delRatiosCal.Count -ge 5) {
                $dm = Get-TokenMedianValue $delRatiosCal
                if ($dm -ne $null) { $ratioDelegateCal = [Math]::Max(0.2, [Math]::Min(5.0, [double]$dm)) }
            } elseif ($DataDir) {
                $calPath2 = Join-Path $DataDir "calibration.json"
                if (Test-Path -LiteralPath $calPath2) {
                    $calJson2 = Get-Content -LiteralPath $calPath2 -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($calJson2.estimate_accuracy -and $calJson2.estimate_accuracy.delegate_ratio_median) {
                        $ratioDelegateCal = [Math]::Max(0.2, [Math]::Min(5.0, [double]$calJson2.estimate_accuracy.delegate_ratio_median))
                    }
                }
            }
        } catch {}

        # Fetch links and task allocation by agy total_tokens
        $taskClaudeMap = @{}
        try {
            $turnCols = @()
            try {
                $turnCols = @($db.Query("PRAGMA table_info(token_turns)", $null) | ForEach-Object { [string]$_['name'] })
            } catch {}
            $hasEstTimeDirCol = ($turnCols -contains 'est_time_direct')
            $hasEstTimeDelCol = ($turnCols -contains 'est_time_delegate')
            $hasCallsRelatedCol = ($turnCols -contains 'calls_related')
            $hasDRelatedCol = ($turnCols -contains 'd_related')
            $hasAnomalyCol = ($turnCols -contains 'anomaly')

            $hasDurCol = ($turnCols -contains 'dur_sec')
            $linkSql = "SELECT l.task_id, l.file, l.turn_ts, t.d_tokens, t.est_direct, t.est_delegate, t.calls"
            if ($hasDurCol) { $linkSql += ", t.dur_sec" }
            if ($hasCallsRelatedCol) { $linkSql += ", t.calls_related" }
            if ($hasDRelatedCol) { $linkSql += ", t.d_related" }
            if ($hasEstTimeDirCol) { $linkSql += ", t.est_time_direct" }
            if ($hasEstTimeDelCol) { $linkSql += ", t.est_time_delegate" }
            if ($hasAnomalyCol) { $linkSql += ", t.anomaly" }
            $linkSql += ", tk.total_tokens, tk.elapsed_sec FROM token_task_links l INNER JOIN token_turns t ON l.file = t.file AND l.turn_ts = t.turn_ts LEFT JOIN tasks tk ON l.task_id = tk.task_id"

            $linkRows = @($db.Query($linkSql, $null))

            $groups = [ordered]@{}
            foreach ($lr in $linkRows) {
                $k = ([string]$lr['file']) + "|" + ([string]$lr['turn_ts'])
                if (-not $groups.Contains($k)) {
                    $groups[$k] = New-Object System.Collections.ArrayList
                }
                [void]$groups[$k].Add($lr)
            }

            foreach ($k in $groups.Keys) {
                $grp = $groups[$k]
                $n = $grp.Count
                $firstRow = $grp[0]
                $dTokens = if ($firstRow['d_tokens'] -ne $null -and $firstRow['d_tokens'] -ne [DBNull]::Value) { [double]$firstRow['d_tokens'] } else { $null }
                if ($dTokens -eq $null) { continue }

                $calls = if ($firstRow['calls'] -ne $null -and $firstRow['calls'] -ne [DBNull]::Value) { [int]$firstRow['calls'] } else { 0 }
                $callsRelated = if ($hasCallsRelatedCol -and $firstRow['calls_related'] -ne $null -and $firstRow['calls_related'] -ne [DBNull]::Value) { [int]$firstRow['calls_related'] } else { $null }
                $dRelated = if ($hasDRelatedCol -and $firstRow['d_related'] -ne $null -and $firstRow['d_related'] -ne [DBNull]::Value) { [double]$firstRow['d_related'] } else { $null }
                $anomaly = if ($hasAnomalyCol -and $firstRow['anomaly'] -ne $null -and $firstRow['anomaly'] -ne [DBNull]::Value -and [string]$firstRow['anomaly'] -ne '') { [string]$firstRow['anomaly'] } else { $null }

                $effD = if ($dRelated -ne $null) { $dRelated } else { $dTokens }
                $effCalls = if ($callsRelated -ne $null) { $callsRelated } else { $calls }
                $otherCalls = [Math]::Max(0, $calls - $effCalls)
                $otherTokens = if ($dTokens -ne $null -and $effD -ne $null) { [long][Math]::Max(0.0, $dTokens - $effD) } else { 0L }
                # 답변 끝 예상(직접·위임·시간)은 턴 전체를 잰 값이고 실제(d_related)는 위임 관련 호출만 잰 값이다.
                # 같은 범위로 비교하려고, 턴 예상에서 그 턴에 위임과 별개로 한 다른 작업의 실측(토큰·시간)을 빼서 "위임한 일만의 예상"을 구한다.
                # 호출 수 비율로 나누면 안 된다: 위임한 턴은 일을 agy 가 해서 위임 관련 호출이 원래 적으므로 직접 예상까지 지나치게 줄어든다.
                # 빼고 나서 0 이하이면(예상이 다른 작업 실측보다 작았음) 호출 비율($relFrac)을 곱하는 방식으로 돌아간다.
                $relFrac = if ($calls -gt 0 -and $callsRelated -ne $null) { [Math]::Min(1.0, [double]$callsRelated / [double]$calls) } else { 1.0 }

                $hasEstDirect = ($firstRow['est_direct'] -ne $null -and $firstRow['est_direct'] -ne [DBNull]::Value)
                $estDirect = if ($hasEstDirect) { [long]$firstRow['est_direct'] } else { $null }
                $estDirectAdj = $null
                if ($hasEstDirect) {
                    # 질문을 받을 때 기록한 예상 그대로(보정 비율을 곱하거나 다른 작업 몫을 빼지 않는다. 결정의 근거라 나중에 바뀌면 안 된다)
                    $estDirectAdj = [long][Math]::Round([double]$firstRow['est_direct'])
                }
                $turnSaved = if ($estDirectAdj -ne $null) { [long]($estDirectAdj - $effD) } else { $null }
                $hasEstDelegate = ($firstRow['est_delegate'] -ne $null -and $firstRow['est_delegate'] -ne [DBNull]::Value)
                $estDelegateAdj = $null
                if ($hasEstDelegate) {
                    $estDelegateAdj = [long][Math]::Round([double]$firstRow['est_delegate'])
                }
                $basis = if ($hasEstDirect) { "measured" } else { "partial" }
                $turnTs = [string]$firstRow['turn_ts']

                $estTimeDir = if ($hasEstTimeDirCol -and $firstRow['est_time_direct'] -ne $null -and $firstRow['est_time_direct'] -ne [DBNull]::Value) { [int]$firstRow['est_time_direct'] } else { $null }
                $estTimeDel = if ($hasEstTimeDelCol -and $firstRow['est_time_delegate'] -ne $null -and $firstRow['est_time_delegate'] -ne [DBNull]::Value) { [int]$firstRow['est_time_delegate'] } else { $null }
                $durSecTurn = if ($hasDurCol -and $firstRow['dur_sec'] -ne $null -and $firstRow['dur_sec'] -ne [DBNull]::Value) { [double]$firstRow['dur_sec'] } else { $null }

                $sumTokens = 0.0
                $hasPositive = $false
                foreach ($item in $grp) {
                    if ($item['total_tokens'] -ne $null -and $item['total_tokens'] -ne [DBNull]::Value) {
                        $tok = [double]$item['total_tokens']
                        if ($tok -gt 0) {
                            $sumTokens += $tok
                            $hasPositive = $true
                        }
                    }
                }

                $weights = @()
                for ($i = 0; $i -lt $n; $i++) {
                    $item = $grp[$i]
                    if ($hasPositive -and $sumTokens -gt 0) {
                        $tok = if ($item['total_tokens'] -ne $null -and $item['total_tokens'] -ne [DBNull]::Value -and [double]$item['total_tokens'] -gt 0) { [double]$item['total_tokens'] } else { 0.0 }
                        $weights += ($tok / $sumTokens)
                    } else {
                        $weights += (1.0 / $n)
                    }
                }

                $maxIdx = 0
                for ($i = 1; $i -lt $n; $i++) {
                    if ($weights[$i] -gt $weights[$maxIdx]) { $maxIdx = $i }
                }

                $usedList = @()
                $usedSum = 0L
                for ($i = 0; $i -lt $n; $i++) {
                    $u = [long][Math]::Round($effD * $weights[$i])
                    $usedList += $u
                    $usedSum += $u
                }
                $diffUsed = [long]$effD - $usedSum
                if ($diffUsed -ne 0) { $usedList[$maxIdx] += $diffUsed }

                $savedList = @()
                if ($turnSaved -ne $null) {
                    $savedSum = 0L
                    for ($i = 0; $i -lt $n; $i++) {
                        $s = [long][Math]::Round($turnSaved * $weights[$i])
                        $savedList += $s
                        $savedSum += $s
                    }
                    $diffSaved = [long]$turnSaved - $savedSum
                    if ($diffSaved -ne 0) { $savedList[$maxIdx] += $diffSaved }
                } else {
                    for ($i = 0; $i -lt $n; $i++) { $savedList += $null }
                }

                for ($i = 0; $i -lt $n; $i++) {
                    $item = $grp[$i]
                    $taskId = [string]$item['task_id']
                    $elapsedSec = if ($item['elapsed_sec'] -ne $null -and $item['elapsed_sec'] -ne [DBNull]::Value) { [int]$item['elapsed_sec'] } else { $null }

                    $estDirectShare = if ($savedList[$i] -ne $null) { [long]($usedList[$i] + $savedList[$i]) } elseif ($estDirectAdj -ne $null) { [long][Math]::Round($estDirectAdj * $weights[$i]) } else { $null }
                    $shareVal = [Math]::Round([double]$weights[$i], 4)
                    $estDelegateShare = if ($estDelegateAdj -ne $null) { [long][Math]::Round($estDelegateAdj * $weights[$i]) } else { $null }
                    # 시간 예상도 질문을 받을 때 기록한 값 그대로(다른 작업 시간을 빼지 않는다. 위임 결정의 근거라 나중에 바뀌면 안 된다). 위임이 여럿이면 몫만큼 나눈다.
                    $estTimeDirShare = $null
                    if ($estTimeDir -ne $null) { $estTimeDirShare = [int][Math]::Round([double]$estTimeDir * [double]$weights[$i]) }
                    $estTimeDelShare = $null
                    if ($estTimeDel -ne $null) { $estTimeDelShare = [int][Math]::Round([double]$estTimeDel * [double]$weights[$i]) }

                    # 위임에 걸린 실제 시간 = agy 처리 시간 + Claude 쪽 시간(그 턴 시간 중 위임 관련 호출의 몫, 여러 건이면 몫으로 나눔).
                    # 참고: Claude 쪽 시간에 agy 를 기다린 시간이 일부 들어 있을 수 있어 그만큼 겹쳐 셀 수 있다(근사값).
                    $claudeSec = $null
                    if ($durSecTurn -ne $null -and $calls -gt 0) { $claudeSec = [int][Math]::Round($durSecTurn * ([double]$effCalls / [double]$calls) * [double]$weights[$i]) }
                    $totalSec = $null
                    if ($elapsedSec -ne $null -or $claudeSec -ne $null) {
                        $totalSec = [int][Math]::Round([double]$(if ($elapsedSec -ne $null) { $elapsedSec } else { 0 }) + [double]$(if ($claudeSec -ne $null) { $claudeSec } else { 0 }))
                    }

                    $taskClaudeMap[$taskId] = [ordered]@{
                        est_direct        = $estDirect
                        est_direct_adj    = $estDirectAdj
                        est_direct_share  = $estDirectShare
                        est_delegate_share = $estDelegateShare
                        share             = $shareVal
                        est_direct_turn   = $estDirectAdj
                        used_turn         = [long]$effD
                        used              = $usedList[$i]
                        saved             = $savedList[$i]
                        calls             = $effCalls
                        calls_related     = $effCalls
                        other_calls       = $otherCalls
                        other_tokens      = $otherTokens
                        tasks_in_turn     = $n
                        basis             = $basis
                        turn_ts           = $turnTs
                        est_time_direct   = $estTimeDir
                        est_time_delegate = $estTimeDel
                        est_time_direct_share   = $estTimeDirShare
                        est_time_delegate_share = $estTimeDelShare
                        elapsed_sec       = $elapsedSec
                        claude_sec        = $claudeSec
                        total_sec         = $totalSec
                        anomaly           = $anomaly
                    }
                }
            }
        } catch {}

        $fields = if ($script:QaRecordFields) { $script:QaRecordFields } else { @('timestamp', 'computer_name', 'task_id', 'source', 'model', 'attempts', 'tried_models', 'input_tokens', 'output_tokens', 'thinking_tokens', 'total_tokens', 'elapsed_sec', 'status', 'session', 'session_id', 'question', 'answer', 'process', 'cum_input_tokens', 'cum_output_tokens', 'cum_thinking_tokens', 'cum_total_tokens', 'usage_basis') }

        # 작업 → 연결된 턴(file, turn_ts). 수집기가 아직 안 돈 기록에 기록한 예상을 붙이는 데 쓴다.
        $estLinkMap = @{}
        try {
            foreach ($lk in @($db.Query("SELECT task_id, file, turn_ts FROM token_task_links", $null))) {
                $estLinkMap[[string]$lk['task_id']] = [pscustomobject]@{ file = [string]$lk['file']; turn_ts = [string]$lk['turn_ts'] }
            }
        } catch {}

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
            foreach ($k in $fields) {
                $v = $r[$k]
                if ($null -eq $v) { continue }
                if (-not $firstField) { [void]$sb.Append(',') }
                $firstField = $false
                [void]$sb.Append('"').Append($k).Append('":')
                if ($k -eq 'process') { [void]$sb.Append([string]$v) } else { [void]$sb.Append((ConvertTo-AgyJsonString ([string]$v))) }
            }

            $tId = [string]$r['task_id']
            if (-not $taskClaudeMap.ContainsKey($tId) -and $estLinkMap.ContainsKey($tId) -and (Get-Command Get-RecordedEstimate -ErrorAction SilentlyContinue)) {
                # 아직 Claude 쪽 사용량이 연결되지 않은(수집기가 안 돈) 기록: 위임을 보내기 전에 record-estimate 로 남긴 예상이라도 카드에 보인다
                try {
                    $lnk = $estLinkMap[$tId]
                    $estRec = Get-RecordedEstimate $DbPath (Split-Path (Split-Path ([string]$lnk.file) -Parent) -Leaf) ([string]$lnk.turn_ts)
                    if ($estRec) {
                        $estParts = @()
                        foreach ($ek in $estRec.Keys) { $ev = $estRec.Item($ek); if ($null -ne $ev) { $estParts += ("`"{0}`":{1}" -f $ek, $ev) } }
                        if ($estParts.Count -gt 0) {
                            if (-not $firstField) { [void]$sb.Append(',') }
                            [void]$sb.Append('"claude_est":{').Append(($estParts -join ',')).Append('}')
                        }
                    }
                } catch {}
            }
            if ($taskClaudeMap.ContainsKey($tId)) {
                $c = $taskClaudeMap[$tId]
                if (-not $firstField) { [void]$sb.Append(',') }
                [void]$sb.Append('"claude":{')
                [void]$sb.Append('"est_direct":').Append($(if ($c.est_direct -ne $null) { $c.est_direct } else { 'null' })).Append(',')
                [void]$sb.Append('"est_direct_adj":').Append($(if ($c.est_direct_adj -ne $null) { $c.est_direct_adj } else { 'null' })).Append(',')
                [void]$sb.Append('"est_direct_share":').Append($(if ($c.est_direct_share -ne $null) { $c.est_direct_share } else { 'null' })).Append(',')
                [void]$sb.Append('"est_delegate_share":').Append($(if ($c.est_delegate_share -ne $null) { $c.est_delegate_share } else { 'null' })).Append(',')
                [void]$sb.Append('"share":').Append($c.share.ToString([System.Globalization.CultureInfo]::InvariantCulture)).Append(',')
                [void]$sb.Append('"est_direct_turn":').Append($(if ($c.est_direct_turn -ne $null) { $c.est_direct_turn } else { 'null' })).Append(',')
                [void]$sb.Append('"used_turn":').Append($c.used_turn).Append(',')
                [void]$sb.Append('"used":').Append($c.used).Append(',')
                [void]$sb.Append('"saved":').Append($(if ($c.saved -ne $null) { $c.saved } else { 'null' })).Append(',')
                [void]$sb.Append('"calls":').Append($c.calls).Append(',')
                [void]$sb.Append('"calls_related":').Append($c.calls_related).Append(',')
                [void]$sb.Append('"other_calls":').Append($c.other_calls).Append(',')
                [void]$sb.Append('"other_tokens":').Append($c.other_tokens).Append(',')
                [void]$sb.Append('"tasks_in_turn":').Append($c.tasks_in_turn).Append(',')
                [void]$sb.Append('"basis":"').Append($c.basis).Append('",')
                [void]$sb.Append('"turn_ts":').Append((ConvertTo-AgyJsonString $c.turn_ts))
                if ($c.est_time_direct -ne $null) {
                    [void]$sb.Append(',"est_time_direct":').Append($c.est_time_direct)
                }
                if ($c.est_time_delegate -ne $null) {
                    [void]$sb.Append(',"est_time_delegate":').Append($c.est_time_delegate)
                }
                if ($c.elapsed_sec -ne $null) {
                    [void]$sb.Append(',"elapsed_sec":').Append($c.elapsed_sec)
                }
                if ($c.est_time_direct_share -ne $null) {
                    [void]$sb.Append(',"est_time_direct_share":').Append($c.est_time_direct_share)
                }
                if ($c.est_time_delegate_share -ne $null) {
                    [void]$sb.Append(',"est_time_delegate_share":').Append($c.est_time_delegate_share)
                }
                if ($c.claude_sec -ne $null) {
                    [void]$sb.Append(',"claude_sec":').Append($c.claude_sec)
                }
                if ($c.total_sec -ne $null) {
                    [void]$sb.Append(',"total_sec":').Append($c.total_sec)
                }
                if ($c.anomaly -ne $null) {
                    [void]$sb.Append(',"anomaly":"').Append($c.anomaly).Append('"')
                }
                [void]$sb.Append('}')
            }

            # 끝난 위임이 큐에서 기다린 시간(초). 기록에는 저장돼 있지 않아서 작업 ID(claude_<접수 시각 epoch>_N)의 접수 시각을 쓴다:
            #   대기 = (끝난 시각 − 실행 시간) − 접수 시각. 오차는 수 초(agy 가 알리는 실행 시간이 시작·끝을 정확히 재지 않아서)이고,
            #   ID 에 접수 시각이 없거나(핸드오프 등) 값이 말이 안 되면(음수·7일 초과) 필드를 내지 않는다.
            if ($tId -match '^claude_(\d{9,11})_\d+' -and $r['elapsed_sec'] -ne $null -and $r['elapsed_sec'] -ne [DBNull]::Value) {
                try {
                    $createdEpoch = [double]$Matches[1]
                    $endEpoch = [double]([DateTimeOffset][datetime]::Parse([string]$r['timestamp'], [System.Globalization.CultureInfo]::InvariantCulture)).ToUnixTimeSeconds()
                    $waitCalc = $endEpoch - [double]$r['elapsed_sec'] - $createdEpoch
                    if ($waitCalc -ge 0 -and $waitCalc -lt 604800) { [void]$sb.Append(',"wait_sec":').Append([int][Math]::Round($waitCalc)) }
                } catch {}
            }

            [void]$sb.Append('}')
        }
        [void]$sb.Append('],"seq":').Append($seq).Append(',"total":').Append($total).Append('}')
        return $sb.ToString()
    } finally {
        $db.Dispose()
    }
}


# HTTP 리스너 기동 (충돌 시 기존 뷰어 자동 정리 및 대체 포트 탐색)
if (-not $WorkerMode) {
    $ViewerShared = [hashtable]::Synchronized(@{})
    $ViewerShared['QaRecordsCache'] = $null
    $ViewerShared['TokenStatsCache'] = $null
    $ViewerShared['lastClaudeScanLaunchAt'] = $null
    $ViewerShared['lastClaudeScanProc'] = $null
    $ViewerShared['lastTokenStatsProc'] = $null
    $ViewerShared['lastAutoCollectCheckAt'] = [datetime]::MinValue
    $ViewerShared['lastAutoCollectAt'] = [datetime]::MinValue

    $listener = $null
    $prefix = $null
    $started = $false
    $maxAttempts = 10

    # 호출자 프로세스 보호를 위해 PPID 조회
    $ppid = 0
    try {
        $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue).ParentProcessId
    } catch {}

    $requestedPort = $Port
    for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
        $currentPort = $Port + $attempt
        $currentPrefix = "http://127.0.0.1:$currentPort/"
        $candidateListener = New-Object System.Net.HttpListener
        $candidateListener.Prefixes.Add($currentPrefix)

        try {
            $candidateListener.Start()
            $listener = $candidateListener
            $prefix = $currentPrefix
            $Port = $currentPort
            $started = $true
            break
        } catch {
            $candidateListener.Close()

            # 첫 번째 시도(기본 포트)에서 충돌 발생 시, 기존 좀비 뷰어 프로세스 정리 후 1회 재시도
            if ($attempt -eq 0) {
                try {
                    $oldViewers = @(Get-CimInstance Win32_Process -Filter "Name like '%powershell%'" -ErrorAction SilentlyContinue | Where-Object {
                        $_.ProcessId -ne $PID -and $_.ProcessId -ne $ppid -and (
                            $_.CommandLine -match "serve-viewer\.ps1" -or
                            $_.CommandLine -match "serve-handoff\.ps1"
                        )
                    })
                    if ($oldViewers.Count -gt 0) {
                        Write-Host "[*] 기존에 실행 중이던 이전 뷰어 세션을 정리하고 포트를 재확보합니다..." -ForegroundColor Yellow
                        foreach ($ov in $oldViewers) {
                            Stop-Process -Id $ov.ProcessId -Force -ErrorAction SilentlyContinue
                        }
                        Start-Sleep -Milliseconds 600

                        # 동일 포트로 재시도
                        $retryListener = New-Object System.Net.HttpListener
                        $retryListener.Prefixes.Add($currentPrefix)
                        try {
                            $retryListener.Start()
                            $listener = $retryListener
                            $prefix = $currentPrefix
                            $started = $true
                            break
                        } catch {
                            $retryListener.Close()
                        }
                    }
                } catch {}
            }
        }
    }

    if (-not $started) {
        Write-Error "HTTP 리스너 시작 실패: 포트 $Port ~ $($Port + $maxAttempts - 1) 번이 모두 사용 중이거나 권한이 없습니다."
        exit 1
    }

    # Claude Code 훅 주소 맞춤 (PreToolUse HTTP 훅 포트 동기화)
    try {
        if (-not $env:SAMJIL_VIEWER_TEST -and -not $env:SAMJIL_NO_HOOK_SYNC -and ($requestedPort -ne $Port -or $Port -eq 8787)) {
            $regHookScript = Find-DelegateScript "sub\register-estimate-guard.ps1"
            if ($regHookScript -and (Test-Path -LiteralPath $regHookScript)) {
                $psiSync = New-Object System.Diagnostics.ProcessStartInfo
                $psiSync.FileName = "powershell.exe"
                $psiSync.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$regHookScript`" -Port $Port -UpdateOnly"
                $psiSync.UseShellExecute = $false
                $psiSync.CreateNoWindow = $true
                $psiSync.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $psiSync.RedirectStandardOutput = $true
                $procSync = [System.Diagnostics.Process]::Start($psiSync)
                $outSync = $procSync.StandardOutput.ReadToEnd()
                [void]$procSync.WaitForExit(5000)
                if ($outSync -and $outSync.Trim() -eq "UPDATED") {
                    Write-Host "[*] Claude Code 훅 주소를 뷰어 포트($Port)에 맞추었습니다." -ForegroundColor Yellow
                }
            }
        }
    } catch {}

    $workerCount = 3
    if ($env:SAMJIL_VIEWER_WORKERS -match '^\d+$') {
        $workerCount = [int]$env:SAMJIL_VIEWER_WORKERS
        if ($workerCount -lt 0) { $workerCount = 0 }
    }

    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  samjil 에이전트 통합 대시보드 (Unified Dashboard)" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  웹 대시보드     : $prefix" -ForegroundColor Green
    Write-Host ("  동시 처리       : 일꾼 {0}개 (SAMJIL_VIEWER_WORKERS 로 바꿈)" -f $workerCount) -ForegroundColor Green
    Write-Host "  위임 기록(/data): $DataDir" -ForegroundColor White
    Write-Host "  대화 저장소     : $HandoffDir" -ForegroundColor White

    # --- agy agent (워처) 자동 연동 ---
    $watcherHealth = $null
    if (-not $NoAgent) {
        # 하트비트만 보지 않고 PID 잠금 파일로 판단합니다(watcher-health.ps1). 명령줄에 watch-agy.ps1 이
        # 남아 있는 빈 -NoExit 창을 "실행 중"으로 오판하지 않습니다.
        $watcherRunning = [bool](Test-WatcherAlive -RuntimeDir $WatcherRuntimeDir).Alive

        $startScript  = Find-DelegateScript "start-agy.ps1"
        $ensureScript = Find-DelegateScript "sub\ensure-agy-running.ps1"

        if ($watcherRunning) {
            Write-Host "  agy agent (워처): 이미 실행 중 (정상)" -ForegroundColor Green
        } elseif ($startScript) {
            Write-Host "  agy agent (워처): 미실행 감지 -> 창 없이 자동 기동..." -ForegroundColor Yellow
            try {
                # -Hidden: 콘솔 창 없이 백그라운드로. (옵션 없이 부르면 -NoExit 콘솔 창이 뜬다. 숨김 뷰어가 이 창을 띄우면 닫을 수도 끌 수도 없다)
                & $startScript -Hidden | Out-Null
                Write-Host "  agy agent (워처): 기동 완료" -ForegroundColor Green
            } catch {
                Write-Host "  agy agent (워처): 자동 기동 실패 ($($_.Exception.Message))" -ForegroundColor Red
            }
        } else {
            Write-Host "  agy agent (워처): start-agy.ps1 스크립트를 찾을 수 없음" -ForegroundColor Gray
        }

        if ($ensureScript) {
            $watcherHealth = New-WatcherHealthState -RuntimeDir $WatcherRuntimeDir -EnsureScript $ensureScript -IntervalSeconds $WatcherCheckSeconds
            if ($WatcherCheckSeconds -gt 0) {
                Write-Host "  워처 자동 점검  : ${WatcherCheckSeconds}초마다 (꺼져 있으면 창 없이 다시 켬, stop-agy 로 끈 상태는 존중)" -ForegroundColor Green
            } else {
                Write-Host "  워처 자동 점검  : 끔 (화면의 켜기 버튼만 사용)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  워처 자동 점검  : ensure-agy-running.ps1 을 찾을 수 없어 끔 (켜기 버튼도 쓸 수 없음)" -ForegroundColor Gray
        }
    }

    Write-Host "  종료 방법       : 이 창에서 Ctrl+C" -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not $NoBrowser) {
        try { Start-Process $prefix } catch {}
    }

    # 워처 상태(자동 점검 · 켜기 버튼)는 부모가 만든 것 하나를 일꾼도 같이 쓴다(/api/status · /api/watcher/start 가 어느 일꾼에 가도 같게)
    $ViewerShared['WatcherHealth'] = $watcherHealth
    $workers = @()
    if ($workerCount -gt 0) {
        $viewerScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        if (-not $viewerScriptPath) { $viewerScriptPath = Join-Path $PSScriptRoot "serve-viewer.ps1" }

        for ($wIdx = 0; $wIdx -lt $workerCount; $wIdx++) {
            $rs = [runspacefactory]::CreateRunspace()
            $rs.Open()
            $rs.SessionStateProxy.SetVariable('ViewerSharedListener', $listener)
            $rs.SessionStateProxy.SetVariable('ViewerShared', $ViewerShared)

            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddCommand($viewerScriptPath)
            [void]$ps.AddParameter('WorkerMode')
            [void]$ps.AddParameter('NoBrowser')
            [void]$ps.AddParameter('NoAgent')
            if ($HandoffDir) { [void]$ps.AddParameter('HandoffDir', $HandoffDir) }
            if ($DataDir) { [void]$ps.AddParameter('DataDir', $DataDir) }
            if ($RuntimeDir) { [void]$ps.AddParameter('RuntimeDir', $RuntimeDir) }
            if ($WebDir) { [void]$ps.AddParameter('WebDir', $WebDir) }
            if ($ClaudeProjectsDir) { [void]$ps.AddParameter('ClaudeProjectsDir', $ClaudeProjectsDir) }
            if ($Port) { [void]$ps.AddParameter('Port', $Port) }

            $asyncResult = $ps.BeginInvoke()
            $workers += [pscustomobject]@{ Runspace = $rs; PowerShell = $ps; AsyncResult = $asyncResult }
        }
    }
} else {
    $listener = $ViewerSharedListener
    $watcherHealth = $ViewerShared['WatcherHealth']
    $prefix = "http://127.0.0.1:$Port/"
    $workers = @()
}

$ViewerHandleRequest = {

    $request = $context.Request

        $response = $context.Response



        try {

            $rawPath = $request.Url.AbsolutePath

            $urlPath = [System.Uri]::UnescapeDataString($rawPath)



            if ($urlPath -eq "/api/handoff/projects" -or $urlPath -eq "/api/projects") {

                $projects = @()

                $seenNames = @{}

                foreach ($hRoot in (Get-HandoffRoots)) {

                    if (-not (Test-Path $hRoot)) { continue }

                    $dirs = Get-ChildItem -LiteralPath $hRoot -Directory -ErrorAction SilentlyContinue

                    foreach ($d in $dirs) {

                        if ($d.Name -eq "templates" -or $d.Name -eq "viewer" -or $d.Name -eq "scripts" -or $d.Name -eq "data" -or $d.Name.StartsWith(".") -or $seenNames.ContainsKey($d.Name)) { continue }

                        $seenNames[$d.Name] = $true

                        $briefPath = Join-Path $d.FullName "BRIEF.md"

                        $indexPath = Join-Path $d.FullName "INDEX.md"

                        $msgDir = Join-Path $d.FullName "msg"

                        $msgCount = 0

                        if (Test-Path $msgDir) {

                            $msgFiles = Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File -ErrorAction SilentlyContinue

                            $msgCount = if ($msgFiles) { @($msgFiles).Count } else { 0 }

                        }

                        $candidates = @($d.LastWriteTime)
                        if (Test-Path $indexPath) {
                            $idxItem = Get-Item -LiteralPath $indexPath -ErrorAction SilentlyContinue
                            if ($idxItem) { $candidates += $idxItem.LastWriteTime }
                        }
                        if ($msgFiles -and $msgFiles.Count -gt 0) {
                            $latestMsgFile = $msgFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            if ($latestMsgFile) { $candidates += $latestMsgFile.LastWriteTime }
                        }
                        $maxTime = ($candidates | Sort-Object -Descending | Select-Object -First 1)
                        $lastUpdated = $maxTime.ToString("yyyy-MM-dd HH:mm:ss")

                        $latestMsg = $null

                        if (Test-Path $indexPath) {

                            $idxContent = Get-Content -LiteralPath $indexPath -Encoding UTF8 -ErrorAction SilentlyContinue

                            if ($idxContent) {

                                $tableLines = $idxContent | Where-Object { $_ -match '^\s*\|\s*\d{4}\s*\|' }

                                if ($tableLines) {

                                    $lastLine = @($tableLines)[-1]

                                    $parts = $lastLine.Split('|') | ForEach-Object { $_.Trim() }

                                    if ($parts.Length -ge 6) {

                                        $latestMsg = [PSCustomObject]@{

                                            num    = $parts[1]

                                            time   = $parts[2]

                                            dir    = $parts[3]

                                            title  = $parts[4]

                                            status = $parts[5]

                                        }

                                    }

                                }

                            }

                        }

                        $projects += [PSCustomObject]@{

                            name      = $d.Name

                            hasBrief  = (Test-Path $briefPath)

                            hasIndex  = (Test-Path $indexPath)

                            msgCount  = $msgCount

                            updated   = $lastUpdated

                            latestMsg = $latestMsg

                        }

                    }

                }

                $arr = @($projects | Sort-Object { $_.updated } -Descending)

                if ($arr.Count -eq 0) {

                    $json = "[]"

                } elseif ($arr.Count -eq 1) {

                    $json = "[" + ($arr[0] | ConvertTo-Json -Depth 5) + "]"

                } else {

                    $json = $arr | ConvertTo-Json -Depth 5

                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                $response.ContentType = "application/json; charset=utf-8"

                $response.ContentLength64 = $bytes.Length

                $response.Headers.Add("Cache-Control", "no-store")

                $response.OutputStream.Write($bytes, 0, $bytes.Length)



            } elseif ($urlPath -eq "/api/handoff/project" -or $urlPath -eq "/api/project") {

                $params = Get-Utf8QueryParams $request.Url

                $pName = $params["name"]

                if ([string]::IsNullOrWhiteSpace($pName) -or $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\")) {

                    $response.StatusCode = 400

                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project name")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $bytes.Length

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } else {

                    $pDir = Find-HandoffProjectDir $pName

                    if (-not $pDir) {

                        $response.StatusCode = 404

                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Project not found")

                        $response.ContentType = "text/plain; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    } else {

                        $briefPath = Join-Path $pDir "BRIEF.md"

                        $briefText = if (Test-Path $briefPath) { [System.IO.File]::ReadAllText($briefPath, [System.Text.Encoding]::UTF8) } else { "" }

                        

                        $msgDir = Join-Path $pDir "msg"
                        $fileList = @()
                        $msgFilesByNum = @{}
                        if (Test-Path $msgDir) {
                            $files = Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File | Sort-Object Name
                            foreach ($f in $files) {
                                $fileList += $f.Name
                                if ($f.Name -match '^(\d{4})-(.*)\.md$') {
                                    $msgFilesByNum[$Matches[1]] = $f
                                }
                            }
                        }

                        $indexPath = Join-Path $pDir "INDEX.md"
                        $indexLines = if (Test-Path $indexPath) { Get-Content -LiteralPath $indexPath -Encoding UTF8 } else { @() }
                        $parsedMessages = @()
                        foreach ($line in $indexLines) {
                            if ($line -match '^\s*\|\s*(\d{4})\s*\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|') {
                                $mNum = $Matches[1].Trim()
                                $mTime = $Matches[2].Trim()
                                $mDir = $Matches[3].Trim()
                                $mTitle = $Matches[4].Trim()
                                $mStatus = $Matches[5].Trim()

                                # 누락된 필드가 있는 경우 실제 메시지 파일에서 자동 복구
                                if ((-not $mTitle -or -not $mDir) -and $msgFilesByNum.ContainsKey($mNum)) {
                                    $mf = $msgFilesByNum[$mNum]
                                    if (-not $mDir) {
                                        if ($mf.Name -match '-(a2c|c2a)-') { $mDir = $Matches[1] }
                                    }
                                    if (-not $mTitle) {
                                        try {
                                            $firstLines = Get-Content -LiteralPath $mf.FullName -TotalCount 10 -Encoding UTF8
                                            foreach ($fl in $firstLines) {
                                                if ($fl -match '^#\s+(.+)$') {
                                                    $mTitle = $Matches[1].Trim()
                                                    break
                                                }
                                            }
                                        } catch {}
                                        if (-not $mTitle -and $mf.Name -match '^\d{4}-[a-z0-9]+-(.*)\.md$') {
                                            $mTitle = $Matches[1].Replace('-', ' ')
                                        }
                                    }
                                    if (-not $mTime) {
                                        $mTime = $mf.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                                    }
                                }

                                # 메시지 머리말의 모델·답장대상·자동(없으면 빈 값). 파일이 안 바뀌면 캐시를 쓴다.
                                $mMeta = @{ model = ""; replyTo = ""; auto = $false; session = "" }
                                if ($handoffLibLoaded -and $msgFilesByNum.ContainsKey($mNum)) {
                                    try { $mMeta = Get-HandoffMessageMeta $msgFilesByNum[$mNum].FullName $script:HandoffMetaCache } catch {}
                                }
                                # 메시지 파일이 만들어진 시각(UTC, 초 단위). Claude 가 보낸 c2a 가 어느 Claude 호출에서 나왔는지 짐작하는 데 쓴다(수정해도 만든 시각은 그대로).
                                $mCreated = ""
                                if ($msgFilesByNum.ContainsKey($mNum)) { try { $mCreated = $msgFilesByNum[$mNum].CreationTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") } catch {} }
                                $parsedMessages += [PSCustomObject]@{
                                    num     = $mNum
                                    time    = $mTime
                                    dir     = $mDir
                                    title   = $mTitle
                                    status  = if ($mStatus) { $mStatus } else { "처리됨" }
                                    model   = [string]$mMeta.model
                                    effort  = [string]$mMeta.effort
                                    replyTo = [string]$mMeta.replyTo
                                    auto    = [bool]$mMeta.auto
                                    session = [string]$mMeta.session
                                    created = $mCreated
                                }
                            }
                        }



                        $autoSummary = $null
                        if ($handoffLibLoaded) { try { $autoSummary = Get-HandoffAutoSummary $pDir } catch {} }
                        $resObj = [PSCustomObject]@{
                            name     = $pName
                            brief    = $briefText
                            messages = $parsedMessages
                            files    = $fileList
                            auto     = $autoSummary
                        }

                        $json = $resObj | ConvertTo-Json -Depth 5

                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                        $response.ContentType = "application/json; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.Headers.Add("Cache-Control", "no-store")

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    }

                }

            } elseif ($urlPath -eq "/api/handoff/message" -or $urlPath -eq "/api/message") {

                $params = Get-Utf8QueryParams $request.Url

                $pName = $params["project"]

                $fName = $params["file"]

                if ([string]::IsNullOrWhiteSpace($pName) -or [string]::IsNullOrWhiteSpace($fName) -or

                    $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\") -or

                    $fName.Contains("..") -or $fName.Contains("/") -or $fName.Contains("\")) {

                    $response.StatusCode = 400

                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project or file name")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $bytes.Length

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } else {

                    $pDir = Find-HandoffProjectDir $pName

                    $msgFilePath = if ($pDir) { Join-Path $pDir "msg\$fName" } else { $null }

                    if (-not $msgFilePath -or -not (Test-Path -LiteralPath $msgFilePath -PathType Leaf)) {

                        $response.StatusCode = 404

                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Message file not found: $fName")

                        $response.ContentType = "text/plain; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    } else {

                        $bytes = [System.IO.File]::ReadAllBytes($msgFilePath)

                        $response.ContentType = "text/plain; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.Headers.Add("Cache-Control", "no-store")

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    }

                }

            } elseif ($urlPath -eq "/api/handoff/auto") {
                # 채널의 자동 이어가기 상태(GET)와 켜기·끄기·한도 초기화(POST ?action=on|off|reset).
                # 채널 파일(AUTO.off, AUTO.json)을 바꾸는 동작이라 워처 켜기와 같이 POST + 전용 헤더만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $aName = [string]$params["name"]
                $aAct = [string]$params["action"]
                $aCode = 200
                $aPayload = $null
                $aMsg = ""
                if (-not $handoffLibLoaded) {
                    $aCode = 503; $aMsg = "handoff-lib.ps1 not found"
                } elseif ([string]::IsNullOrWhiteSpace($aName) -or $aName.Contains("..") -or $aName.Contains("/") -or $aName.Contains("\")) {
                    $aCode = 400; $aMsg = "Invalid project name"
                } elseif ($request.HttpMethod -ne "GET" -and $request.HttpMethod -ne "POST") {
                    $aCode = 405; $aMsg = "Method Not Allowed"
                    $response.Headers.Add("Allow", "GET, POST")
                } elseif ($request.HttpMethod -eq "POST" -and $request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $aCode = 403; $aMsg = "Forbidden"
                } else {
                    $aDir = Find-HandoffProjectDir $aName
                    if (-not $aDir) {
                        $aCode = 404; $aMsg = "Project not found"
                    } elseif ($request.HttpMethod -eq "POST" -and -not (Set-HandoffAutoAction $aDir $aAct)) {
                        $aCode = 400; $aMsg = "Invalid action"
                    } else {
                        if ($request.HttpMethod -eq "POST") {
                            Write-Host ("[{0}] 핸드오프 자동 이어가기 {1}: {2}" -f (Get-Date -Format 'HH:mm:ss'), $aAct, $aName) -ForegroundColor Yellow
                        }
                        $aPayload = Get-HandoffAutoSummary $aDir
                    }
                }
                $response.StatusCode = $aCode
                if ($aPayload) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($aPayload | ConvertTo-Json -Depth 5))
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($aMsg)
                    $response.ContentType = "text/plain; charset=utf-8"
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/qa/records" -or $urlPath -eq "/api/qa-records") {

                # 위임 완료 기록. 화면은 처음에 since=0 으로 전부 받고, 이후엔 마지막으로 받은 seq 이후만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $qaSince = [long]0
                if ($params["since"]) { [void][long]::TryParse([string]$params["since"], [ref]$qaSince) }
                $qaJson = $null
                # 처음 전부 받는 요청(since=0)은 데이터가 그대로면 지난번에 만든 응답을 그대로 준다(만드는 데 수 초 걸린다)
                $qaStamp = if ($qaSince -eq 0) { Get-ViewerDataStamp $AgyDbPath $DataDir } else { "" }
                if ($qaStamp -and $ViewerShared['QaRecordsCache'] -and $ViewerShared['QaRecordsCache'].Stamp -eq $qaStamp) {
                    $qaJson = [string]$ViewerShared['QaRecordsCache'].Json
                    $response.Headers.Add("X-Samjil-Cache", "hit")
                } else {
                    try { $qaJson = Get-ViewerQaRecordsJson $AgyDbPath $DataDir $qaSince } catch { try { $qaJson = Get-QaRecordsJson $AgyDbPath $qaSince } catch { $qaJson = $null } }
                    if ($qaStamp -and $null -ne $qaJson) { $ViewerShared['QaRecordsCache'] = @{ Stamp = $qaStamp; Json = $qaJson } }
                }
                if ($null -eq $qaJson) {
                    $response.StatusCode = 503
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("위임 기록 DB 를 읽지 못했습니다.")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($qaJson)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/qa/source") {

                # 길어서 잘린 기록의 원본 파일(질문 = tasks\processed 의 지시파일, 답변 = tasks\outbox 의 응답 파일)을 그대로 내려 준다.
                # 작업 ID 는 글자·숫자·_ . - 만 허용하고 ".." 는 막아서, 데이터 폴더의 tasks\processed·tasks\outbox 밖 파일은 읽지 못하게 한다.
                $params = Get-Utf8QueryParams $request.Url
                $srcTask = [string]$params["task"]
                $srcKind = [string]$params["kind"]
                                $srcPath = $null
                if ($srcTask -match '^[A-Za-z0-9가-힣_.\-]{1,200}$' -and -not $srcTask.Contains("..")) {
                    if ($srcKind -eq "question") {
                        foreach ($srcExt in @(".md", ".txt")) {
                            $srcCand = Join-Path $DataDir ("tasks\processed\" + $srcTask + $srcExt)
                            if (Test-Path -LiteralPath $srcCand -PathType Leaf) { $srcPath = $srcCand; break }
                        }
                    } elseif ($srcKind -eq "answer") {
                        $srcCand = Join-Path $DataDir ("tasks\outbox\" + $srcTask + ".response.md")
                        if (Test-Path -LiteralPath $srcCand -PathType Leaf) { $srcPath = $srcCand }
                    }
                }
                if (-not $srcPath) {
                    $response.StatusCode = 404
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("원본 파일을 찾을 수 없습니다. 이미 정리됐거나 이 PC 에 없는 작업일 수 있습니다.")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $bytes = [System.IO.File]::ReadAllBytes($srcPath)
                    # UTF-8 BOM 은 브라우저에서 글자로 보일 수 있어 뺀다
                    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bytes = $bytes[3..($bytes.Length - 1)] }
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/delegate/pending") {

                $runtimeDir = $RuntimeDir
                $inboxDir = Join-Path $runtimeDir "inbox"

                $watcherAlive = [bool](Test-WatcherAlive -RuntimeDir $WatcherRuntimeDir).Alive

                $currentTaskFile = Join-Path $runtimeDir "logs\current_task.json"
                $currentTask = $null
                if (Test-Path -LiteralPath $currentTaskFile) {
                    try {
                        $currentTask = Get-Content -LiteralPath $currentTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    } catch {}
                }

                # 작업마다 있는 표시 파일(running\<작업 ID>.json): 동시에 도는 작업 각각의 작업자 PID·모델·시작 시각·대화 ID.
                # 이 폴더가 아예 없으면 옛 워처(한 번에 하나만 처리)라서 예전 규칙(맨 앞 작업이 처리 중)을 쓴다.
                $runningDir = Join-Path $runtimeDir "running"
                $legacyQueue = -not (Test-Path -LiteralPath $runningDir -PathType Container)

                $pendingList = @()
                if (Test-Path -LiteralPath $inboxDir -PathType Container) {
                    $inboxFiles = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -match '^\.(md|txt)$' } |
                        Sort-Object CreationTime)

                    foreach ($f in $inboxFiles) {
                        try {
                            $rawText = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
                            if ($rawText.Length -gt 0 -and $rawText[0] -eq [char]0xFEFF) {
                                $rawText = $rawText.Substring(1)
                            }
                            $lines = $rawText -split "\r?\n"
                            $cwdLines = New-Object System.Collections.ArrayList
                            $sessionVal = ""
                            $modelVal = ""
                            $bodyStartIdx = $lines.Length
                            for ($i = 0; $i -lt $lines.Length; $i++) {
                                $trimmed = $lines[$i].Trim()
                                if ([string]::IsNullOrWhiteSpace($trimmed)) {
                                    continue
                                }
                                if ($trimmed -match '^@cwd:\s*(.*)$') {
                                    [void]$cwdLines.Add($Matches[1].Trim())
                                    continue
                                }
                                if ($trimmed -match '^@session:\s*(.*)$') {
                                    $sessionVal = $Matches[1].Trim()
                                    continue
                                }
                                if ($trimmed -match '^@model:\s*(.*)$') {
                                    $modelVal = $Matches[1].Trim()
                                    continue
                                }
                                $bodyStartIdx = $i
                                break
                            }
                            $question = if ($bodyStartIdx -lt $lines.Length) {
                                ($lines[$bodyStartIdx..($lines.Length - 1)] -join "`r`n").Trim()
                            } else {
                                ""
                            }
                            $claim = $null
                            $claimAlive = $false
                            if (-not $legacyQueue) {
                                $claimFile = Join-Path $runningDir ("{0}.json" -f $f.BaseName)
                                if (Test-Path -LiteralPath $claimFile) {
                                    try { $claim = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($claimFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) } catch {}
                                }
                                if ($claim -and [int]$claim.pid -gt 0) {
                                    $cp = Get-Process -Id ([int]$claim.pid) -ErrorAction SilentlyContinue
                                    $claimAlive = [bool]($cp -and $cp.ProcessName -eq "powershell")
                                }
                            }
                            if ($legacyQueue) {
                                $state = if ($watcherAlive -and $pendingList.Count -eq 0) { "processing" } else { "queued" }
                            } else {
                                $state = if ($claimAlive) { "processing" } else { "queued" }
                            }

                            # 모델 및 세션 ID 해석
                            $resolvedModel = ""
                            $sessionId = ""
                            if ($claimAlive -and $claim.model) {
                                $resolvedModel = [string]$claim.model
                            } elseif ($legacyQueue -and $currentTask -and $currentTask.task_id -eq $f.BaseName -and $currentTask.model) {
                                $resolvedModel = [string]$currentTask.model
                            }
                            if (-not $resolvedModel -and $sessionVal) {
                                try {
                                    $sObj = Get-AgySession $AgyDbPath $sessionVal
                                    if ($sObj) {
                                        if ($sObj.model) { $resolvedModel = [string]$sObj.model }
                                        if ($sObj.conversation_id) { $sessionId = [string]$sObj.conversation_id }
                                    }
                                } catch {}
                            }
                            if (-not $resolvedModel -and $modelVal) {
                                $resolvedModel = $modelVal
                            }
                            if (-not $resolvedModel) {
                                $resolvedModel = "gemini-3.8-flash-high"
                            }

                            # 진행 중인 작업이면 agy 대화 기록에서 현재 단계/최근 동작을 읽어 붙입니다.
                            # 실행 표시 파일은 있는데 그 작업자 프로세스가 사라졌으면 "중단된 것으로 보이는" 작업이다(워처가 죽었거나 작업자가 비정상 종료).
                            # 대기 중과 구별해 화면이 "대기 중"이라고 거짓말하지 않게 하고, 마지막 진행 상황도 같이 읽어 준다.
                            $interrupted = [bool](-not $legacyQueue -and $claim -and [int]$claim.pid -gt 0 -and -not $claimAlive -and $claim.started_at)
                            $claimUsable = [bool]($claim -and $claim.started_at -and ($claimAlive -or $interrupted))
                            $progress = $null
                            $startedText = ""
                            if (($state -eq "processing" -or $interrupted) -and (($claimUsable) -or ($legacyQueue -and $currentTask -and $currentTask.task_id -eq $f.BaseName))) {
                                $convId = ""
                                if ($claimUsable -and $claim.conversation_id) { $convId = [string]$claim.conversation_id }
                                if (-not $convId -and $sessionVal) {
                                    try { $sObj2 = Get-AgySession $AgyDbPath $sessionVal; if ($sObj2) { $convId = [string]$sObj2.conversation_id } } catch {}
                                }
                                if (-not $sessionVal -and $claim -and $claim.session) {
                                    $sessionVal = [string]$claim.session
                                }
                                $startedAt = $null
                                $startedText = ""
                                if ($claimUsable) {
                                    $startedText = if ($claim.started) { [string]$claim.started } elseif ($claim.started_at) { [string]$claim.started_at } else { "" }
                                } elseif ($currentTask) {
                                    $startedText = if ($currentTask.started) { [string]$currentTask.started } elseif ($currentTask.started_at) { [string]$currentTask.started_at } else { "" }
                                }
                                if ($startedText) {
                                    try { $startedAt = [datetime]::ParseExact($startedText, "yyyy-MM-dd HH:mm:ss", $null) } catch {
                                        try { $startedAt = [datetime]::Parse($startedText, [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
                                    }
                                }
                                if (-not $startedAt -and $claimUsable -and $claimFile -and (Test-Path -LiteralPath $claimFile)) {
                                    $startedAt = (Get-Item -LiteralPath $claimFile).CreationTime
                                }
                                $qSnippet = if ($question.Length -gt 40) { $question.Substring(0, 40) } else { $question }
                                $progress = Get-AgyProgress $convId $startedAt $f.BaseName $qSnippet $sessionVal
                            }

                            # 5초마다 불리는 목록에 단계 전체(최대 1,500개)를 싣지 않는다. 개수만 알려 주고, 단계는 /api/delegate/process?since= 로 새 것만 받아 간다.
                            $liveConvId = ""
                            if ($progress) {
                                $liveConvId = [string]$progress.conversation_id
                                $progress.PSObject.Properties.Remove('steps')
                            }

                            $claudeLive = Get-ClaudeLiveTaskInfo -TaskId $f.BaseName
                            $pendingObj = [ordered]@{
                                task_id    = $f.BaseName
                                created    = $f.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                                started_at = $(if (($state -eq "processing" -or $interrupted) -and $startedText) { $startedText } else { "" })
                                conversation_id = $liveConvId
                                interrupted = $interrupted
                                question   = $question
                                cwd        = @(ConvertTo-CwdList $cwdLines.ToArray())
                                session    = $sessionVal
                                session_id = $sessionId
                                model      = $resolvedModel
                                state      = $state
                                progress   = $progress
                            }
                            if ($null -ne $claudeLive) {
                                $pendingObj["claude_live"] = $claudeLive
                            }
                            $pendingList += [PSCustomObject]$pendingObj
                        } catch {
                            continue
                        }
                    }
                }

                $json = if ($pendingList.Count -eq 0) {
                    "[]"
                } elseif ($pendingList.Count -eq 1) {
                    "[" + ($pendingList[0] | ConvertTo-Json -Depth 5) + "]"
                } else {
                    $pendingList | ConvertTo-Json -Depth 5
                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.Headers.Add("Cache-Control", "no-store")
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/status" -or $urlPath -eq "/api/system/status") {

                $runtimeDir = $RuntimeDir
                $heartbeatDir = Join-Path $runtimeDir "heartbeat"
                $inboxDir = Join-Path $runtimeDir "inbox"

                # 켜짐/꺼짐은 하트비트가 아니라 PID 잠금 파일로 판단합니다(agy 를 기다리는 동안은 하트비트가 낡음).
                $aliveInfo = Test-WatcherAlive -RuntimeDir $WatcherRuntimeDir
                $watcherAlive = [bool]$aliveInfo.Alive
                $lastHeartbeat = ""
                if (Test-Path -LiteralPath $heartbeatDir -PathType Container) {
                    $latestHb = Get-ChildItem -LiteralPath $heartbeatDir -Filter "hb_*.txt" -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($latestHb) {
                        $lastHeartbeat = $latestHb.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                }

                $inboxCount = 0
                if (Test-Path -LiteralPath $inboxDir -PathType Container) {
                    $inboxFiles = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(md|txt)$' })
                    $inboxCount = $inboxFiles.Count
                }

                $autoRestart = [PSCustomObject]@{
                    enabled         = [bool]($watcherHealth -and $watcherHealth.IntervalSeconds -gt 0)
                    intervalSeconds = if ($watcherHealth) { [int]$watcherHealth.IntervalSeconds } else { 0 }
                    lastLaunch      = if ($watcherHealth -and $watcherHealth.LastLaunchAt) { $watcherHealth.LastLaunchAt.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
                    launchCount     = if ($watcherHealth) { [int]$watcherHealth.LaunchCount } else { 0 }
                    lastResult      = if ($watcherHealth) { [string]$watcherHealth.LastResult } else { "" }
                }

                $statusObj = [PSCustomObject]@{
                    port          = $Port
                    watcherAlive  = $watcherAlive
                    watcherSource = [string]$aliveInfo.Source
                    manualStop    = (Test-WatcherManualStop $WatcherRuntimeDir)
                    canStart      = [bool]$watcherHealth
                    autoRestart   = $autoRestart
                    lastHeartbeat = $lastHeartbeat
                    inboxCount    = $inboxCount
                    dataDir       = $DataDir
                    handoffDir    = $HandoffDir
                }
                $json = $statusObj | ConvertTo-Json -Depth 5
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.Headers.Add("Cache-Control", "no-store")
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/watcher/start") {

                # 워처를 켜는 동작이라 POST + 전용 헤더만 받습니다. 다른 웹 페이지가 이 주소로 보내는
                # 단순 요청(전용 헤더를 붙일 수 없음)은 거절됩니다.
                if ($request.HttpMethod -ne "POST") {
                    $response.StatusCode = 405
                    $response.Headers.Add("Allow", "POST")
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed")
                } elseif ($request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $response.StatusCode = 403
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Forbidden")
                } else {
                    $startRes = Invoke-WatcherStartRequest $watcherHealth
                    Write-Host ("[{0}] 화면에서 워처 켜기 요청: {1}" -f (Get-Date -Format 'HH:mm:ss'), $startRes.Result) -ForegroundColor Yellow
                    $json = ([PSCustomObject]@{ result = $startRes.Result; message = $startRes.Message }) | ConvertTo-Json -Depth 3
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/handoff/claude-usage") {
                # c2a 메시지 카드의 Claude 쪽 토큰: 세션(session)의 기록에서 각 시각(ts, 쉼표로 여럿) 바로 앞에 끝난 Claude 호출의 사용량.
                # 근사치다(claude-usage.ps1 머리말). 읽기만 하고, 세션 ID 는 영문자·숫자·- 만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $cuSid = [string]$params["session"]
                if ($cuSid -notmatch '^[A-Za-z0-9-]{8,64}$' -or -not (Get-Command Find-ClaudeCallBefore -ErrorAction SilentlyContinue)) {
                    $response.StatusCode = 400
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid session")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $cuPath = Get-ClaudeTranscriptPath $cuSid
                    $cuItems = [ordered]@{}
                    if ($cuPath) {
                        $cuCalls = Get-ClaudeUsageCalls $cuPath
                        foreach ($cuTs in @(([string]$params["ts"]) -split ',' | Where-Object { $_ } | Select-Object -First 200)) {
                            $cuAt = [datetime]::MinValue
                            if ([datetime]::TryParse($cuTs, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$cuAt)) {
                                $cuItems[$cuTs] = Find-ClaudeCallBefore $cuCalls $cuAt
                            } else { $cuItems[$cuTs] = $null }
                        }
                    }
                    $json = ([PSCustomObject]@{ session = $cuSid; found = [bool]$cuPath; items = $cuItems }) | ConvertTo-Json -Depth 5
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/delegate/process") {

                # 기록에 과정이 저장되지 않은 옛 위임용: agy 의 대화 id 로 대화 기록에서 도구 호출 목록을 읽어 온다.
                # id 는 영문자·숫자·- 만 받는다(경로 문자 차단은 Get-AgyTranscriptPath 가 한다).
                # since=<마지막으로 받은 단계 번호> 를 주면 그 뒤의 새 단계만 돌려준다(진행 중인 작업을 몇 초마다 따라갈 때). 없으면 전부.
                # 대화마다 읽은 위치를 기억하는 캐시(Get-AgyProcessStepsCached)를 거치므로 기록 파일이 안 바뀌었으면 파일을 다시 파싱하지 않는다.
                $params = Get-Utf8QueryParams $request.Url
                $cid = [string]$params["id"]
                $sinceN = -1
                if ($params["since"] -match '^-?\d{1,9}$') { $sinceN = [int]$params["since"] }
                $tp = $null
                if (Get-Command Get-AgyTranscriptPath -ErrorAction SilentlyContinue) { $tp = Get-AgyTranscriptPath (Get-AgyHomeDir) $cid }
                if (-not $tp) {
                    $response.StatusCode = 400
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid id")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $found = Test-Path -LiteralPath $tp -PathType Leaf
                    $stepsOut = @()
                    $total = 0
                    $lastMs = 0
                    if ($found) {
                        $startedDt = $null
                        if ($params["started"]) {
                            try { $startedDt = [datetime]::Parse([string]$params["started"], [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
                        }
                        if (-not $startedDt) {
                            $runningDir = Join-Path $runtimeDir "running"
                            if (Test-Path -LiteralPath $runningDir) {
                                foreach ($rf in @(Get-ChildItem -LiteralPath $runningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
                                    try {
                                        $rc = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($rf.FullName, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF))
                                        if ($rc -and $rc.session -and [string]$rc.conversation_id -eq $cid) {
                                            $sText = if ($rc.started) { [string]$rc.started } elseif ($rc.started_at) { [string]$rc.started_at } else { "" }
                                            if ($sText) {
                                                try { $startedDt = [datetime]::ParseExact($sText, "yyyy-MM-dd HH:mm:ss", $null) } catch {
                                                    try { $startedDt = [datetime]::Parse($sText, [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
                                                }
                                            }
                                            if (-not $startedDt) { $startedDt = $rf.CreationTime }
                                            break
                                        }
                                    } catch {}
                                }
                            }
                        }
                        $all = @(Get-AgyProcessStepsCached $cid $startedDt)
                        $total = $all.Count
                        $maxN = -1
                        foreach ($s in $all) { if ($null -ne $s.n -and [int]$s.n -gt $maxN) { $maxN = [int]$s.n } }
                        $hasSkipped = [bool]($all | Where-Object { $null -ne $_.skipped })
                        $reset = ($sinceN -gt $maxN -and $maxN -ge 0)
                        if ($hasSkipped -and $sinceN -ge 0) {
                            $backFirst = $all | Where-Object { $null -eq $_.skipped -and $null -ne $_.n } | Select-Object -Skip 300 -First 1
                            if ($backFirst -and $sinceN -lt [int]$backFirst.n) {
                                $reset = $true
                            }
                        }
                        $stepsOut = @(if ($sinceN -ge 0 -and -not $reset) { $all | Where-Object { $null -ne $_.n -and [int]$_.n -gt $sinceN } } else { $all })
                        $lastMs = [int64]([DateTimeOffset](Get-Item -LiteralPath $tp).LastWriteTime).ToUnixTimeMilliseconds()
                    } else { $reset = $false }
                    $json = ([PSCustomObject]@{ id = $cid; found = $found; steps = $stepsOut; total = $total; reset = [bool]$reset; last_activity_ms = $lastMs }) | ConvertTo-Json -Depth 5
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/estimate-guard") {

                # Claude Code 의 PreToolUse HTTP 훅: 질문의 예상(record-estimate)이 아직 없으면 일을 시작하는 도구를 막는다. 명령 훅보다 훨씬 빨라(수 ms) 도구 호출마다 건다.
                # 본문은 훅 입력 JSON. 응답은 {} (통과) 또는 permissionDecision=deny. 뷰어가 꺼져 있으면 훅 요청이 실패해 막지 않고 지나가며, 끝낼 때(Stop 훅)에 다시 걸린다.
                $egCode = 200
                $egPayload = $null
                if ($request.HttpMethod -ne "POST") {
                    $egCode = 405; $response.Headers.Add("Allow", "POST")
                } elseif ($request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $egCode = 403
                } else {
                    $egBody = ""
                    try {
                        $egReader = New-Object System.IO.StreamReader($request.InputStream, (New-Object System.Text.UTF8Encoding($false)))
                        $egBody = $egReader.ReadToEnd()
                    } catch { $egBody = "" }
                    $egRes = @{ Action = 'allow'; Message = '' }
                    if ($egBody.Length -le 1048576 -and (Get-Command Invoke-EstimateGuard -ErrorAction SilentlyContinue)) {
                        $egRes = Invoke-EstimateGuard -EventJson $egBody -RuntimeDir $RuntimeDir
                    }
                    if ($egRes.Action -eq 'deny') {
                        $egPayload = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "deny"; permissionDecisionReason = [string]$egRes.Message } }
                    } else {
                        $egPayload = @{}
                    }
                }
                $response.StatusCode = $egCode
                if ($null -ne $egPayload) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($egPayload | ConvertTo-Json -Depth 5 -Compress))
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($(if ($egCode -eq 403) { "Forbidden" } else { "Method Not Allowed" }))
                    $response.ContentType = "text/plain; charset=utf-8"
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/qa/file-sizes") {

                # 위임 기록의 과정에 나온 파일의 크기(바이트). "Claude 토큰 절약" 예상에서 읽은 파일·쓴 파일의 분량을 어림하는 데 쓴다.
                # 본문: {"paths": ["D:/a/b.html", ...]}. 없는 파일·폴더·상대 경로·네트워크 경로는 -1. 크기만 알려 주고 내용은 읽지 않는다.
                # 파일 존재 여부를 알려 주는 동작이라 다른 쓰기 API 와 같이 POST + 전용 헤더만 받는다.
                $fsCode = 200
                $fsPayload = $null
                if ($request.HttpMethod -ne "POST") {
                    $fsCode = 405; $response.Headers.Add("Allow", "POST")
                } elseif ($request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $fsCode = 403
                } else {
                    $fsBody = ""
                    try {
                        $fsReader = New-Object System.IO.StreamReader($request.InputStream, (New-Object System.Text.UTF8Encoding($false)))
                        $fsBody = $fsReader.ReadToEnd()
                    } catch { $fsBody = "" }
                    $fsReq = $null
                    if ($fsBody.Length -gt 0 -and $fsBody.Length -le 262144) { try { $fsReq = $fsBody | ConvertFrom-Json } catch { $fsReq = $null } }
                    if ($null -eq $fsReq -or $null -eq $fsReq.paths) {
                        $fsCode = 400
                    } else {
                        $fsSizes = [ordered]@{}
                        $fsCount = 0
                        foreach ($fp in @($fsReq.paths)) {
                            if ($fsCount -ge 500) { break }
                            $fpText = [string]$fp
                            if (-not $fpText -or $fsSizes.Contains($fpText)) { continue }
                            $fsCount++
                            $fsSize = -1
                            try {
                                if ([System.IO.Path]::IsPathRooted($fpText) -and -not $fpText.StartsWith("\\") -and -not $fpText.StartsWith("//") -and [System.IO.File]::Exists($fpText)) {
                                    $fsSize = [long](New-Object System.IO.FileInfo($fpText)).Length
                                }
                            } catch { $fsSize = -1 }
                            $fsSizes[$fpText] = $fsSize
                        }
                        $fsPayload = @{ sizes = $fsSizes }
                    }
                }
                $response.StatusCode = $fsCode
                if ($fsPayload) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($fsPayload | ConvertTo-Json -Depth 4 -Compress))
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($(if ($fsCode -eq 403) { "Forbidden" } elseif ($fsCode -eq 405) { "Method Not Allowed" } else { "Bad Request" }))
                    $response.ContentType = "text/plain; charset=utf-8"
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/qa/contexts") {

                # 끝난 위임 카드의 "캐시 읽기"와 "현재 컨텍스트"(그 호출의 마지막 턴이 모델에 보낸 입력 크기). 위임 기록 DB 에는 없는 값이라 대화 기록에서 계산한다.
                # 본문: {"items": [{"id": "<대화 id>", "max": <그 호출의 마지막 단계 번호, 0 이면 전체>}, ...]} -> {"results": {"<id>|<max>": {cache, context, turns}}}
                # 대화 기록을 읽는 동작이라 다른 쓰기 API 와 같이 POST + 전용 헤더만 받는다.
                $cxCode = 200
                $cxPayload = $null
                if ($request.HttpMethod -ne "POST") {
                    $cxCode = 405; $response.Headers.Add("Allow", "POST")
                } elseif ($request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $cxCode = 403
                } else {
                    $cxBody = ""
                    try {
                        $cxReader = New-Object System.IO.StreamReader($request.InputStream, (New-Object System.Text.UTF8Encoding($false)))
                        $cxBody = $cxReader.ReadToEnd()
                    } catch { $cxBody = "" }
                    $cxReq = $null
                    if ($cxBody.Length -gt 0 -and $cxBody.Length -le 262144) { try { $cxReq = $cxBody | ConvertFrom-Json } catch { $cxReq = $null } }
                    if ($null -eq $cxReq -or $null -eq $cxReq.items) {
                        $cxCode = 400
                    } else {
                        if ($null -eq $script:ContextCache) { $script:ContextCache = @{} }
                        $cxHome = if ($env:AGY_HOME) { $env:AGY_HOME } else { Join-Path $env:USERPROFILE ".gemini\antigravity-cli" }
                        $cxResults = [ordered]@{}
                        $cxCount = 0
                        foreach ($cxItem in @($cxReq.items)) {
                            if ($cxCount -ge 400) { break }
                            $cxId = [string]$cxItem.id
                            $cxMax = 0
                            try { $cxMax = [int]$cxItem.max } catch { $cxMax = 0 }
                            $cxKey = "$cxId|$cxMax"
                            if (-not $cxId -or $cxResults.Contains($cxKey)) { continue }
                            $cxCount++
                            if (-not (Get-Command Get-AgyTranscriptPath -ErrorAction SilentlyContinue)) { continue }
                            $cxFull = Get-AgyTranscriptPath $cxHome $cxId
                            if (-not $cxFull) { continue }
                            $cxCompact = Join-Path (Split-Path -Parent $cxFull) "transcript.jsonl"
                            $cxFile = if (Test-Path -LiteralPath $cxCompact) { $cxCompact } else { $cxFull }
                            if (-not (Test-Path -LiteralPath $cxFile -PathType Leaf)) { continue }
                            $cxStamp = [string](Get-Item -LiteralPath $cxFile).Length + "|" + [string](Get-Item -LiteralPath $cxFile).LastWriteTimeUtc.Ticks
                            $cached = $script:ContextCache[$cxKey]
                            if ($cached -and $cached.Stamp -eq $cxStamp) { $cxResults[$cxKey] = $cached.Value; continue }
                            try {
                                $cxState = New-AgyUsageState $cxFile
                                Update-AgyUsageState $cxState
                                $cxSum = Get-AgyUsageSummary $cxState $cxMax
                                $cxVal = @{ cache = [int64]$cxSum.Cache; context = [int64]$cxSum.Context; turns = [int]$cxSum.Turns }
                                $script:ContextCache[$cxKey] = @{ Stamp = $cxStamp; Value = $cxVal }
                                $cxResults[$cxKey] = $cxVal
                            } catch {}
                        }
                        $cxPayload = @{ results = $cxResults }
                    }
                }
                $response.StatusCode = $cxCode
                if ($cxPayload) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($cxPayload | ConvertTo-Json -Depth 5 -Compress))
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($(if ($cxCode -eq 403) { "Forbidden" } elseif ($cxCode -eq 405) { "Method Not Allowed" } else { "Bad Request" }))
                    $response.ContentType = "text/plain; charset=utf-8"
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/delegate/translate") {

                # 과정 창의 "한글로 번역". GET 은 상태와 번역해 둔 것을 읽고, POST 는 번역을 시작한다.
                # 시작은 agy 를 부르는 동작이라 워처 켜기와 같이 POST + 전용 헤더만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $cid = [string]$params["id"]
                if ($request.HttpMethod -eq "POST" -and $request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $response.StatusCode = 403
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Forbidden")
                    $response.ContentType = "text/plain; charset=utf-8"
                } elseif ($request.HttpMethod -ne "POST" -and $request.HttpMethod -ne "GET") {
                    $response.StatusCode = 405
                    $response.Headers.Add("Allow", "GET, POST")
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $sinceStr = [string]$params["since"]
                    $trState = if ($request.HttpMethod -eq "POST") { Start-ProcessTranslation $cid $sinceStr } else { Get-ProcessTranslationState $cid $sinceStr }
                    if (-not $trState) {
                        $response.StatusCode = 400
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid id")
                        $response.ContentType = "text/plain; charset=utf-8"
                    } else {
                        if ($request.HttpMethod -eq "POST") {
                            Write-Host ("[{0}] 과정 번역 요청: {1} -> {2}" -f (Get-Date -Format 'HH:mm:ss'), $cid, $trState.state) -ForegroundColor Yellow
                        }
                        $json = $trState | ConvertTo-Json -Depth 6
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                        $response.ContentType = "application/json; charset=utf-8"
                        $response.Headers.Add("Cache-Control", "no-store")
                    }
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/image") {

                $params = Get-Utf8QueryParams $request.Url

                $imgParam = $params["path"]

                $cwdParam = $params["cwd"]

                $targetPath = $null

                if (-not [string]::IsNullOrWhiteSpace($imgParam)) {

                    $targetPath = $imgParam.Trim()

                    if (-not [System.IO.Path]::IsPathRooted($targetPath) -and -not [string]::IsNullOrWhiteSpace($cwdParam)) {

                        $targetPath = Join-Path $cwdParam.Trim() $targetPath

                    }

                }



                $fullPath = $null

                try {

                    if ($targetPath) { $fullPath = [System.IO.Path]::GetFullPath($targetPath) }

                } catch { $fullPath = $null }



                $ext = if ($fullPath) { [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant() } else { "" }

                $allowedImageExts = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".ico")



                if (-not $fullPath -or -not ($allowedImageExts -contains $ext) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {

                    $response.StatusCode = 404

                    $body = [System.Text.Encoding]::UTF8.GetBytes("404 Image Not Found")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $body.Length

                    $response.OutputStream.Write($body, 0, $body.Length)

                } else {

                    $bytes = [System.IO.File]::ReadAllBytes($fullPath)

                    $response.ContentType = Get-ContentType $fullPath

                    $response.ContentLength64 = $bytes.Length

                    $response.Headers.Add("Cache-Control", "public, max-age=3600")

                    $response.Headers.Add("Content-Disposition", "inline")

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                }

            } elseif ($urlPath -eq "/api/claude/tree") {

                try {
                    $indexFile = Join-Path $DataDir "cache\claude-links.json"
                    $runningFile = "$indexFile.running"
                    $errorFile = "$indexFile.error"

                    $isScanning = $false

                    if (Test-Path -LiteralPath $runningFile) {
                        $runningRaw = $null
                        try {
                            $runningRaw = [System.IO.File]::ReadAllText($runningFile, [System.Text.Encoding]::UTF8)
                        } catch {}

                        $runningJson = $null
                        if ($runningRaw) {
                            try { $runningJson = ConvertFrom-Json -InputObject $runningRaw } catch {}
                        }

                        $rPid = 0
                        if ($runningJson -and $runningJson.pid) {
                            [int]::TryParse([string]$runningJson.pid, [ref]$rPid) | Out-Null
                        }

                        $rItem = Get-Item -LiteralPath $runningFile -ErrorAction SilentlyContinue
                        $isStale = $false

                        if (-not $rItem) {
                            $isStale = $true
                        } else {
                            $ageSec = ((Get-Date) - $rItem.LastWriteTime).TotalSeconds
                            if ($ageSec -ge 600) {
                                $isStale = $true
                            } elseif ($rPid -gt 0) {
                                $proc = Get-Process -Id $rPid -ErrorAction SilentlyContinue
                                if (-not $proc -or $proc.HasExited) {
                                    $isStale = $true
                                }
                            } else {
                                $isStale = $true
                            }
                        }

                        if ($isStale) {
                            Remove-Item -LiteralPath $runningFile -Force -ErrorAction SilentlyContinue
                            $isScanning = $false
                        } else {
                            $isScanning = $true
                        }
                    }

                    $scanProc = $ViewerShared['lastClaudeScanProc']
                    if (-not $isScanning -and $scanProc) {
                        try {
                            if (-not $scanProc.HasExited) {
                                $isScanning = $true
                            }
                        } catch {}
                    }

                    $scanLaunchAt = $ViewerShared['lastClaudeScanLaunchAt']
                    $recentlyLaunched = ($scanLaunchAt -and (((Get-Date) - $scanLaunchAt).TotalSeconds -lt 5))

                    $indexExists = Test-Path -LiteralPath $indexFile
                    $indexStale = $false
                    if ($indexExists) {
                        $indexItem = Get-Item -LiteralPath $indexFile -ErrorAction SilentlyContinue
                        if ($indexItem -and (((Get-Date) - $indexItem.LastWriteTime).TotalSeconds -gt 15)) {
                            $indexStale = $true
                        }
                    }

                    $needScan = (-not $indexExists) -or $indexStale

                    if ($needScan -and (-not $isScanning) -and (-not $recentlyLaunched)) {
                        $scannerScript = Join-Path $PSScriptRoot "scan-claude-links.ps1"
                        if (Test-Path -LiteralPath $scannerScript) {
                            $isScanning = $true
                            [System.Threading.Monitor]::Enter($ViewerShared.SyncRoot)
                            try {
                                $scanProcNow = $ViewerShared['lastClaudeScanProc']
                                $scanLaunchAtNow = $ViewerShared['lastClaudeScanLaunchAt']
                                $procBusy = ($scanProcNow -and -not $scanProcNow.HasExited)
                                $recent = ($scanLaunchAtNow -and (((Get-Date) - $scanLaunchAtNow).TotalSeconds -lt 5))
                                if (-not $procBusy -and -not $recent) {
                                    $ViewerShared['lastClaudeScanLaunchAt'] = Get-Date
                                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                                    $psi.FileName = "powershell.exe"
                                    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scannerScript`" -IndexFile `"$indexFile`""
                                    $psi.UseShellExecute = $false
                                    $psi.CreateNoWindow = $true
                                    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                                    $ViewerShared['lastClaudeScanProc'] = [System.Diagnostics.Process]::Start($psi)
                                }
                            } catch {
                                $isScanning = $false
                            } finally {
                                [System.Threading.Monitor]::Exit($ViewerShared.SyncRoot)
                            }
                        }
                    }

                    $tree = $null
                    if (Get-Command Get-ClaudeSessionTree -ErrorAction SilentlyContinue) {
                        try {
                            $tree = Get-ClaudeSessionTree
                        } catch {}
                    }

                    $available = if ($tree -and $tree.Available) { [bool]$tree.Available } else { $false }

                    $projectsList = @()
                    if ($tree -and $tree.Projects) {
                        foreach ($p in $tree.Projects) {
                            $sessList = @()
                            if ($p.sessions) {
                                foreach ($s in $p.sessions) {
                                    $sessList += $s
                                }
                            }
                            $projectsList += [ordered]@{
                                id       = [string]$p.id
                                name     = [string]$p.name
                                sessions = @($sessList)
                            }
                        }
                    }

                    $ungroupedList = @()
                    if ($tree -and $tree.Ungrouped) {
                        foreach ($s in $tree.Ungrouped) {
                            $ungroupedList += $s
                        }
                    }

                    $scanError = ""
                    if (Test-Path -LiteralPath $errorFile) {
                        try {
                            $scanError = [System.IO.File]::ReadAllText($errorFile, [System.Text.Encoding]::UTF8).Trim()
                        } catch {}
                    }

                    $linkInfo = $null
                    if (Get-Command Read-ClaudeLinkIndex -ErrorAction SilentlyContinue) {
                        try {
                            $linkInfo = Read-ClaudeLinkIndex -IndexFile $indexFile
                        } catch {}
                    }

                    $taskLinks = if ($linkInfo -and $linkInfo.Tasks) { $linkInfo.Tasks } else { @{} }
                    $handoffLinks = if ($linkInfo -and $linkInfo.Msgs) { $linkInfo.Msgs } else { @{} }
                    $updated = if ($linkInfo -and $linkInfo.Updated) { [string]$linkInfo.Updated } else { "" }

                    $outObj = [ordered]@{
                        available    = $available
                        scanning     = $isScanning
                        scanError    = $scanError
                        updated      = $updated
                        projects     = @($projectsList)
                        ungrouped    = @($ungroupedList)
                        taskLinks    = $taskLinks
                        handoffLinks = $handoffLinks
                    }

                    $json = ConvertTo-Json -InputObject $outObj -Depth 6
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.Headers.Add("Cache-Control", "no-store")
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } catch {
                    $errObj = [ordered]@{
                        available    = $false
                        scanning     = $false
                        scanError    = [string]$_.Exception.Message
                        updated      = ""
                        projects     = @()
                        ungrouped    = @()
                        taskLinks    = @{}
                        handoffLinks = @{}
                    }
                    $json = ConvertTo-Json -InputObject $errObj -Depth 6
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.Headers.Add("Cache-Control", "no-store")
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                }

            } elseif ($urlPath -eq "/api/token-stats") {

                # 토큰·위임 통계 조회 API (days 는 7·30·60 만 지원, 그 밖은 30)
                $params = Get-Utf8QueryParams $request.Url
                $qDays = 30
                if ($params["days"]) { [void][int]::TryParse([string]$params["days"], [ref]$qDays) }
                $qPage = 1
                if ($params["page"]) { [void][int]::TryParse([string]$params["page"], [ref]$qPage) }
                $qPageSize = 20
                if ($params["page_size"]) { [void][int]::TryParse([string]$params["page_size"], [ref]$qPageSize) }
                $qPath = if ($params["path"]) { [string]$params["path"] } else { "" }
                # 통계가 오래됐으면(진행 중이던 턴이 끝났는데 수집이 그 전에 한 번 돈 경우 등) 백그라운드로 한 번 더 수집한다. 확인은 1분에 한 번, 수집은 3분에 한 번까지만.
                # 페이지 이동 요청(page_move=1 또는 page > 1)에서는 자동 수집 검사를 건너뛰어 페이지 전환 속도를 높인다.
                $autoStarted = $false
                $isPageMove = ($params["page_move"] -eq "1" -or $qPage -gt 1)
                try {
                    $nowAuto = Get-Date
                    if (-not $isPageMove -and -not $env:SAMJIL_NO_AUTO_COLLECT) {
                        [System.Threading.Monitor]::Enter($ViewerShared.SyncRoot)
                        try {
                            $tsProcCur = $ViewerShared['lastTokenStatsProc']
                            $procBusy = ($tsProcCur -and -not $tsProcCur.HasExited)
                            $lastCheck = $ViewerShared['lastAutoCollectCheckAt']
                            if (-not $procBusy -and ($nowAuto - $lastCheck).TotalSeconds -ge 60) {
                                $ViewerShared['lastAutoCollectCheckAt'] = $nowAuto
                                $lastCollect = $ViewerShared['lastAutoCollectAt']
                                if (($nowAuto - $lastCollect).TotalSeconds -ge 180 -and -not (Test-Path -LiteralPath (Join-Path $RuntimeDir "token-stats.lock")) -and (Test-TokenStatsStale $DataDir $ClaudeProjectsDir)) {
                                    $tsScriptAuto = Find-DelegateScript "sub\token-stats.ps1"
                                    if ($tsScriptAuto -and (Test-Path -LiteralPath $tsScriptAuto)) {
                                        $psiA = New-Object System.Diagnostics.ProcessStartInfo
                                        $psiA.FileName = "powershell.exe"
                                        $psiA.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tsScriptAuto`" -Update -DbPath `"$AgyDbPath`" -RuntimeDir `"$RuntimeDir`""
                                        $psiA.UseShellExecute = $false
                                        $psiA.CreateNoWindow = $true
                                        $psiA.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                                        $ViewerShared['lastTokenStatsProc'] = [System.Diagnostics.Process]::Start($psiA)
                                        $ViewerShared['lastAutoCollectAt'] = $nowAuto
                                        $autoStarted = $true
                                    }
                                }
                            }
                        } finally {
                            [System.Threading.Monitor]::Exit($ViewerShared.SyncRoot)
                        }
                    }
                } catch {}
                # 같은 조건(기간 · 쪽 · 처리 방식)이고 데이터 도장이 같으면(같은 시간대 안) 지난번 응답을 그대로 준다(만드는 데 수 초 걸린다)
                $tsStamp = Get-ViewerDataStamp $AgyDbPath $DataDir
                $tsKey = if ($tsStamp) { ("{0}|{1}|{2}|{3}|{4}|{5}" -f $qDays, $qPage, $qPageSize, $qPath, (Get-Date -Format "yyyyMMddHH"), $tsStamp) } else { "" }
                $tsCache = $ViewerShared['TokenStatsCache']
                if ($tsKey -and $tsCache -and $tsCache.Key -eq $tsKey) {
                    $json = [string]$tsCache.Json
                    $response.Headers.Add("X-Samjil-Cache", "hit")
                } else {
                    $statsData = Get-TokenStatsData -DbPath $AgyDbPath -DataDir $DataDir -Days $qDays -RecentPage $qPage -RecentPageSize $qPageSize -RecentPath $qPath
                    $json = ConvertTo-Json -InputObject $statsData -Depth 6
                    if ($tsKey) { $ViewerShared['TokenStatsCache'] = @{ Key = $tsKey; Json = $json } }
                }
                # 백그라운드 수집을 막 시작했으면 화면이 잠시 뒤 다시 불러오도록 표시를 붙인다(저장해 둔 응답에는 넣지 않는다)
                if ($autoStarted) { $json = '{"auto_collect": true,' + $json.TrimStart().Substring(1) }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.Headers.Add("Cache-Control", "no-store")
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/token-stats/refresh") {

                # 토큰 통계 수집 및 보정식 즉시 갱신 (POST 전용)
                if ($request.HttpMethod -ne "POST") {
                    $response.StatusCode = 405
                    $response.Headers.Add("Allow", "POST")
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed")
                } else {
                    $lockFile = Join-Path $RuntimeDir "token-stats.lock"
                    $isRunning = $false
                    $tsProcRefresh = $ViewerShared['lastTokenStatsProc']
                    if ($tsProcRefresh -and -not $tsProcRefresh.HasExited) {
                        $isRunning = $true
                    } elseif (Test-Path -LiteralPath $lockFile) {
                        $lockPid = 0
                        try {
                            $pidText = [System.IO.File]::ReadAllText($lockFile, [System.Text.Encoding]::ASCII).Trim()
                            [void][int]::TryParse($pidText, [ref]$lockPid)
                        } catch {}
                        if ($lockPid -gt 0) {
                            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
                            if ($proc -and -not $proc.HasExited) {
                                $isRunning = $true
                            } else {
                                Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
                            }
                        } else {
                            Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
                        }
                    }

                    if ($isRunning) {
                        $outObj = [ordered]@{ started = $false; reason = "running" }
                    } else {
                        $tsScript = Find-DelegateScript "sub\token-stats.ps1"
                        if ($tsScript -and (Test-Path -LiteralPath $tsScript)) {
                            try {
                                $psi = New-Object System.Diagnostics.ProcessStartInfo
                                $psi.FileName = "powershell.exe"
                                $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tsScript`" -Update -DbPath `"$AgyDbPath`" -RuntimeDir `"$RuntimeDir`""
                                $psi.UseShellExecute = $false
                                $psi.CreateNoWindow = $true
                                $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                                $ViewerShared['lastTokenStatsProc'] = [System.Diagnostics.Process]::Start($psi)
                                $outObj = [ordered]@{ started = $true }
                            } catch {
                                $outObj = [ordered]@{ started = $false; reason = [string]$_.Exception.Message }
                            }
                        } else {
                            $outObj = [ordered]@{ started = $true }
                        }
                    }
                    $json = ConvertTo-Json -InputObject $outObj -Depth 3
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($env:SAMJIL_VIEWER_TEST -eq "1" -and $urlPath -eq "/api/_test/sleep") {

                # 시험용 느린 요청 (동시성 시험 전용)
                $params = Get-Utf8QueryParams $request.Url
                $sleepMs = 0
                if ($params["ms"]) { [void][int]::TryParse([string]$params["ms"], [ref]$sleepMs) }
                if ($sleepMs -lt 0) { $sleepMs = 0 }
                if ($sleepMs -gt 5000) { $sleepMs = 5000 }
                if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }

                $json = "{`"slept`":$sleepMs}"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.Headers.Add("Cache-Control", "no-store")
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } else {

                $filePath = Resolve-SafePath $urlPath



                if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

                    if (-not $urlPath.StartsWith("/data/") -and -not [System.IO.Path]::HasExtension($urlPath)) {

                        $filePath = Join-Path $RouteMap["/"] "index.html"

                    }

                }



                if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

                    $response.StatusCode = 404

                    $body = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $body.Length

                    $response.OutputStream.Write($body, 0, $body.Length)

                } else {

                    $bytes = [System.IO.File]::ReadAllBytes($filePath)

                    $response.ContentType = Get-ContentType $filePath

                    $response.ContentLength64 = $bytes.Length

                    $response.Headers.Add("Cache-Control", "no-store")

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                }

            }



        } catch {

            try {

                $response.StatusCode = 500

                $bytes = [System.Text.Encoding]::UTF8.GetBytes("500 Server Error: $($_.Exception.Message)")

                $response.ContentType = "text/plain; charset=utf-8"

                $response.ContentLength64 = $bytes.Length

                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } catch {}

        } finally {

            try { $response.OutputStream.Close() } catch {}

        }

    }

try {

    if ($WorkerMode) {

        while ($listener.IsListening) {
            $context = $null
            try {
                $context = $listener.GetContext()
            } catch {
                break
            }
            if ($context) {
                . $ViewerHandleRequest
            }
        }

    } else {

        $pendingContext = $null

        while ($listener.IsListening) {

            # 워처 주기 점검. 점검 시각이 아니면 바로 돌아옵니다(점검 자체가 예외를 내도 서버는 계속 돕니다).
            if ($watcherHealth) {
                try {
                    $tickResult = Invoke-WatcherHealthTick $watcherHealth
                    if ($tickResult -eq 'restart') {
                        Write-Host ("[{0}] agy 워처가 꺼져 있어 자동으로 다시 켭니다 (창 없이 실행, 20초 뒤 재확인)." -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Yellow
                    } elseif ($tickResult -like 'launch-failed*') {
                        Write-Host ("[{0}] agy 워처 자동 재시작 실패: {1}" -f (Get-Date -Format 'HH:mm:ss'), $tickResult) -ForegroundColor Red
                    }
                } catch {}
            }

            $context = $null

            try {

                # 요청이 없어도 1초마다 깨어나 위 점검을 챙깁니다(GetContext 는 요청이 올 때까지 막혀서 쓸 수 없음).
                if ($null -eq $pendingContext) { $pendingContext = $listener.GetContextAsync() }

                if (-not $pendingContext.Wait(1000)) { continue }

                $context = $pendingContext.GetAwaiter().GetResult()

                $pendingContext = $null

            } catch {

                break

            }

            if ($context) {
                . $ViewerHandleRequest
            }

        }

    }

} finally {

    if (-not $WorkerMode) {

        if ($listener) {
            try { $listener.Stop() } catch {}
            try { $listener.Close() } catch {}
        }

        foreach ($w in $workers) {
            try { $w.PowerShell.Stop() } catch {}
            try { $w.PowerShell.Dispose() } catch {}
            try { $w.Runspace.Close() } catch {}
            try { $w.Runspace.Dispose() } catch {}
        }

        Write-Host "`n웹 뷰어 서버를 종료했습니다."

    }

}

