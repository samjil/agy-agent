# agy-rules.ps1
# 폴더(@cwd)를 열어 주는 코딩 위임에, 매번 Claude 가 지시문 끝에 직접 적던 "표준 규칙"을 워처가 호출 직전에 대신 붙여 주는 헬퍼입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-rules.ps1")`  (watch-agy.ps1 이 씁니다)
#
# 왜 필요한가:
#   DO NOT COMMIT · FOREGROUND 실행 · 한글 답변 같은 규칙을 Claude 가 위임 때마다 영어 문단으로 다시 적고, 한 줄만 빠져도
#   agy 가 커밋하거나 백그라운드 작업을 남기거나 영어로 답했다. 규칙은 늘 같으니 워처가 붙이면 Claude 는 작업 명세만 쓰면 된다.
#
# 언제 붙이는가:
#   - @cwd 로 폴더를 열어 주는 작업에만 붙인다(이 규칙들은 로컬 폴더를 만지는 작업용이다). @cwd 가 없는 위임(번역·데이터 변환 등)은 결과 언어나 형식이
#     지시문마다 달라서 건드리지 않는다 — 한글 답변 문장도 @cwd 작업에만 자동으로 붙는다.
#   - 지시문 맨 위에 "@raw: true" 가 있으면 붙이지 않는다(핸드오프 펌프가 자기 규칙을 직접 쓰는 작업이 그렇다).
#   - 규칙마다 따로 본다: 지시문에 이미 같은 뜻의 규칙이 있으면(예: "DO NOT COMMIT") 그 규칙만 건너뛰고 빠진 것만 붙인다.
#   - 붙인 것은 agy 에게 넘기는 프롬프트에만 들어간다. 위임 기록(뷰어·agy.db)의 질문에는 Claude 가 쓴 원본이 그대로 남는다.

# 규칙 목록: Name(로그용), Pattern(지시문에 이미 있는지 보는 정규식), Text(붙일 문장)
$script:AgyStandardRuleList = @(
    @{ Name = "no-commit"; Pattern = '(?i)do\s+not\s+commit|커밋하지\s*(마|않)';
       Text = "- DO NOT COMMIT. Do not run git add / commit / stash / reset / checkout / switch or any command that changes git state. Leave all changes in the working tree." },
    @{ Name = "foreground"; Pattern = '(?i)foreground|전경에서';
       Text = "- Run every command in the FOREGROUND and wait for it to finish. Do not leave background tasks or terminals running. Run commands directly; do not wrap them in another powershell.exe call." },
    @{ Name = "touch-only"; Pattern = '(?i)touch\s+only|필요한\s*파일만';
       Text = "- Touch only the files this task needs. Do not touch untracked files you did not create." },
    @{ Name = "korean"; Pattern = '(?i)write\s+the\s+final\s+reply|in\s+(korean|english)|한글(로|\s*로)\s*(작성|답|보고)|한국어로';
       Text = "Write the final reply and any report in Korean (keep code, paths, commands and raw error text as is)." }
)

# Windows 지역(형식) 설정(CultureInfo.CurrentCulture)의 언어 영어 이름: ko-KR -> Korean, ja-JP -> Japanese. 알 수 없으면 English.
# 시험에서 이 함수를 덮어써 PC 언어를 흉내 낸다.
function Get-AgyOsLanguage {
    try {
        $ci = [System.Globalization.CultureInfo]::CurrentCulture
        if ($ci.Name -eq "") { return "English" }
        if (-not $ci.IsNeutralCulture -and $ci.Parent -and $ci.Parent.Name) { $ci = $ci.Parent }
        $name = ([string]$ci.EnglishName -replace '\s*\(.*$', '').Trim()
        if ($name -match '^[A-Za-z][A-Za-z \-]{1,30}$') { return $name }
    } catch {}
    return "English"
}

# 답변 언어: 환경변수 AGY_REPLY_LANGUAGE, 없으면 <delegate-agy>\reply-language.txt 의 첫 줄.
# 값은 "Korean", "English" 처럼 영어 단어 하나이고, 비었거나 "auto" 거나 이상한 값이면 PC 의 Windows 지역(형식) 설정을 따른다(Get-AgyOsLanguage).
# 배포 팩의 설치기는 이 파일에 auto 를 적는다. 그래서 PC 지역 설정을 바꾸면 답변 언어도 따라간다.
function Get-AgyReplyLanguage {
    $lang = ([string]$env:AGY_REPLY_LANGUAGE).Trim()
    if (-not $lang) {
        $f = Join-Path $PSScriptRoot "..\..\reply-language.txt"
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            try { $lang = ([string](@(Get-Content -LiteralPath $f -Encoding UTF8 -TotalCount 1)[0])).Trim() } catch { $lang = "" }
        }
    }
    if ($lang -match '^[A-Za-z][A-Za-z \-]{1,30}$' -and $lang -ine "auto") { return $lang }
    return (Get-AgyOsLanguage)
}

# 지시어 값이 참인가: true / yes / 1 / on / 예
function ConvertTo-AgyDirectiveFlag([string]$Value) {
    return [bool]([string]$Value -match '^\s*(?i:true|yes|1|on|예)\s*$')
}

# 실행 슬래시 명령어(@cmd) · 실행 모드(@mode) 허용 목록
#   워처(헤드리스 `agy -p`)에서 자동 확장되는 명령과 대화형 TUI 전용 명령을 구분한다.
$script:AgyAllowedSlashCommands  = @('goal', 'swarm', 'run-workflow', 'boost', 'browser', 'plan')
$script:AgyQuotaHeavyCommands    = @('swarm', 'run-workflow', 'boost')
$script:AgyInteractiveOnlyCommands = @('teamwork', 'grill-me', 'rewind', 'fork', 'btw', 'compact', 'resume', 'learn', 'permissions', 'tasks', 'agents', 'diff', 'context')
$script:AgyAllowedExecutionModes = @('plan', 'accept-edits', 'auto')

# @cmd 값을 검증·정규화한다. 비어 있으면 $null.
function Resolve-AgySlashCommand([string]$Value) {
    $v = ([string]$Value).Trim()
    if (-not $v) { return $null }
    $name = $v.TrimStart('/').Trim().ToLowerInvariant()
    if ($script:AgyAllowedSlashCommands -contains $name) {
        return @{
            Valid      = $true
            Name       = $name
            Command    = "/$name"
            QuotaHeavy = ($script:AgyQuotaHeavyCommands -contains $name)
            Error      = $null
        }
    }
    if ($script:AgyInteractiveOnlyCommands -contains $name) {
        return @{
            Valid      = $false
            Name       = $name
            Command    = ""
            QuotaHeavy = $false
            Error      = "지정한 @cmd 는 대화형 TUI 전용이라 헤드리스 워처에서 쓸 수 없습니다: /$name (명세를 파일로 저장한 뒤 별도 터미널의 agy 세션에서 @파일명 과 함께 실행하세요. 워처 지원 명령: $($script:AgyAllowedSlashCommands -join ', '))"
        }
    }
    return @{
        Valid      = $false
        Name       = $name
        Command    = ""
        QuotaHeavy = $false
        Error      = "지정한 @cmd 를 쓸 수 없습니다: $Value (지원 명령: $($script:AgyAllowedSlashCommands -join ', '))"
    }
}

# @mode 값을 검증·정규화한다(plan · accept-edits · auto). 비어 있으면 $null.
function Resolve-AgyExecutionMode([string]$Value) {
    $v = ([string]$Value).Trim()
    if (-not $v) { return $null }
    $m = $v.ToLowerInvariant()
    if ($script:AgyAllowedExecutionModes -contains $m) {
        return @{ Valid = $true; Mode = $m; Error = $null }
    }
    return @{ Valid = $false; Mode = ""; Error = "지정한 @mode 를 쓸 수 없습니다: $Value (지원 모드: $($script:AgyAllowedExecutionModes -join ', '))" }
}

# 본문 맨 앞에 지원 슬래시 명령(/swarm · /goal 등)이 있으면 떼어 낸다.
#   파일 참조(@prompt_xxx.txt)로 넘길 때도 `"/swarm @prompt_xxx.txt"` 형태로 명령이 확장되게 하려는 것이다.
function Split-AgyLeadingSlashCommand([string]$Prompt) {
    $s = [string]$Prompt
    $m = [regex]::Match($s, '^\s*/([A-Za-z][A-Za-z0-9-]*)(?:\s+([\s\S]*)|$)$')
    if ($m.Success) {
        $name = $m.Groups[1].Value.ToLowerInvariant()
        if ($script:AgyAllowedSlashCommands -contains $name) {
            $body = if ($m.Groups[2].Success) { $m.Groups[2].Value.TrimStart() } else { "" }
            return @{ Name = $name; Command = "/$name"; Body = $body }
        }
    }
    return @{ Name = ""; Command = ""; Body = $s }
}

# /goal 완료 시 agy 가 출력 끝에 남기는 HTML 주석 마커(<!-- GOAL_COMPLETE --> / <!-- GOAL_CANCELLED -->)를 뗀다.
function Remove-AgyGoalMarkers([string]$Text) {
    $s = [string]$Text
    if ($s -notmatch '(?i)<!--\s*GOAL_(?:COMPLETE|CANCELLED)\s*-->') { return $s }
    $s = [regex]::Replace($s, '(?im)^[ \t]*<!--\s*GOAL_(?:COMPLETE|CANCELLED)\s*-->[ \t]*(?:\r?\n)?', '')
    $s = [regex]::Replace($s, '(?i)[ \t]*<!--\s*GOAL_(?:COMPLETE|CANCELLED)\s*-->[ \t]*', '')
    return $s.TrimEnd("`r", "`n")
}

# 표준 규칙을 붙인 프롬프트를 만든다.
#   $Prompt       지시어 줄을 뺀 지시문 본문
#   $HasFolder    @cwd 로 열리는 폴더가 있는가
#   $Raw          @raw: true 인가
#   $SlashCommand 실행 슬래시 명령(/swarm · /run-workflow 등, 선택)
# 반환: @{ Text = <agy 에 넘길 프롬프트>; Added = @(붙인 규칙 이름) }  (붙일 게 없으면 Text 는 $Prompt 그대로)
function Add-AgyStandardRules([string]$Prompt, [bool]$HasFolder, [bool]$Raw = $false, [string]$SlashCommand = "") {
    if ($Raw -or -not $HasFolder) { return @{ Text = $Prompt; Added = @() } }
    $lines = New-Object System.Collections.ArrayList
    $added = New-Object System.Collections.ArrayList
    $replyLang = Get-AgyReplyLanguage
    foreach ($r in $script:AgyStandardRuleList) {
        if ([regex]::IsMatch([string]$Prompt, $r.Pattern)) { continue }
        if ($r.Name -eq "korean" -and [regex]::IsMatch([string]$Prompt, '(?i)\bin\s+' + [regex]::Escape($replyLang) + '\b')) { continue }
        $ruleText = if ($r.Name -eq "korean") { $r.Text.Replace("in Korean", "in $replyLang") } else { $r.Text }
        [void]$lines.Add($ruleText)
        [void]$added.Add($r.Name)
    }
    if ($SlashCommand -ieq "/swarm" -and ([string]$Prompt) -notmatch '(?i)workspace\s*:\s*["'']?inherit|share[^.\r\n]{0,20}쓰지') {
        [void]$lines.Add('- For /swarm: keep all workers on workspace:"inherit" with non-overlapping file ownership (do NOT use workspace:"share"/"branch" or git commits). Post a concise final summary after workers and verifiers finish.')
        [void]$added.Add("swarm-safe")
    } elseif ($SlashCommand -ieq "/run-workflow" -and ([string]$Prompt) -notmatch '(?i)workspace\s*:\s*["'']?inherit') {
        [void]$lines.Add('- For /run-workflow: keep workflow agents on workspace:"inherit" with disjoint file ownership (no git commits) and print a concise final summary.')
        [void]$added.Add("workflow-safe")
    }
    if ($added.Count -eq 0) { return @{ Text = $Prompt; Added = @() } }
    $text = ([string]$Prompt).TrimEnd() + "`n`nRules (added automatically by the watcher):`n" + ($lines -join "`n") + "`n"
    return @{ Text = $text; Added = @($added.ToArray()) }
}

# 직접 작업을 수행하는 Gemini(agy)가 과거 기록이 아닌 현재 프롬프트의 양·난이도·복잡도만 분석해
# 첫 응답 맨 앞에 예상 소요 시간([ETA: <초>s])을 출력하도록 지시를 붙인다(@raw: true 면 생략).
function Add-AgyEtaInstruction([string]$Prompt, [bool]$Raw = $false) {
    if ($Raw) { return @{ Text = $Prompt; Added = $false } }
    if ([regex]::IsMatch([string]$Prompt, '(?i)\[\s*ETA\s*:')) { return @{ Text = $Prompt; Added = $false } }
    $inst = "Before calling your first tool (or at the very beginning of your response), estimate the total execution time in seconds based solely on this prompt's volume, difficulty, and complexity (do not assume any prior history), and output a single tag on its own line: [ETA: <seconds>s] (for example, [ETA: 180s])."
    $text = ([string]$Prompt).TrimEnd() + "`n`n" + $inst + "`n"
    return @{ Text = $text; Added = $true }
}

# 텍스트에서 Gemini 가 출력한 [ETA: <초>s] 태그를 추출하고, 본문에서는 해당 태그를 제거한다.
function Split-AgyEtaFromText([string]$Text) {
    $raw = [string]$Text
    $est = $null
    $m = [regex]::Match($raw, '(?i)\[\s*ETA\s*:\s*(\d+)\s*(?:s|sec|seconds|초)?\s*\]')
    if ($m.Success) {
        $v = 0
        if ([int]::TryParse($m.Groups[1].Value, [ref]$v) -and $v -ge 1 -and $v -le 86400) {
            $est = $v
        }
        $raw = [regex]::Replace($raw, '(?im)^\s*\[\s*ETA\s*:\s*\d+\s*(?:s|sec|seconds|초)?\s*\]\s*(\r?\n)?', '')
        $raw = [regex]::Replace($raw, '(?i)\s*\[\s*ETA\s*:\s*\d+\s*(?:s|sec|seconds|초)?\s*\]', '')
        $raw = $raw.TrimStart("`r", "`n")
    }
    return @{ EstimatedSec = $est; CleanText = $raw }
}
