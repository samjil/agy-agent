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

# 답변 언어: 환경변수 AGY_REPLY_LANGUAGE, 없으면 <delegate-agy>\reply-language.txt 의 첫 줄, 둘 다 없으면 Korean(기존 동작).
# 배포 팩의 설치기가 PC 언어에 맞춰 이 파일을 적는다. 값은 "Korean", "English" 처럼 영어 단어 하나를 쓴다.
function Get-AgyReplyLanguage {
    $lang = [string]$env:AGY_REPLY_LANGUAGE
    if (-not $lang.Trim()) {
        $f = Join-Path $PSScriptRoot "..\..\reply-language.txt"
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            try { $lang = [string](@(Get-Content -LiteralPath $f -Encoding UTF8 -TotalCount 1)[0]) } catch { $lang = "" }
        }
    }
    $lang = $lang.Trim()
    if ($lang -notmatch '^[A-Za-z][A-Za-z \-]{1,30}$') { return "Korean" }
    return $lang
}

# 지시어 값이 참인가: true / yes / 1 / on / 예
function ConvertTo-AgyDirectiveFlag([string]$Value) {
    return [bool]([string]$Value -match '^\s*(?i:true|yes|1|on|예)\s*$')
}

# 표준 규칙을 붙인 프롬프트를 만든다.
#   $Prompt     지시어 줄을 뺀 지시문 본문
#   $HasFolder  @cwd 로 열리는 폴더가 있는가
#   $Raw        @raw: true 인가
# 반환: @{ Text = <agy 에 넘길 프롬프트>; Added = @(붙인 규칙 이름) }  (붙일 게 없으면 Text 는 $Prompt 그대로)
function Add-AgyStandardRules([string]$Prompt, [bool]$HasFolder, [bool]$Raw = $false) {
    if ($Raw -or -not $HasFolder) { return @{ Text = $Prompt; Added = @() } }
    $lines = New-Object System.Collections.ArrayList
    $added = New-Object System.Collections.ArrayList
    $replyLang = Get-AgyReplyLanguage
    foreach ($r in $script:AgyStandardRuleList) {
        if ([regex]::IsMatch([string]$Prompt, $r.Pattern)) { continue }
        $ruleText = if ($r.Name -eq "korean") { $r.Text.Replace("in Korean", "in $replyLang") } else { $r.Text }
        [void]$lines.Add($ruleText)
        [void]$added.Add($r.Name)
    }
    if ($added.Count -eq 0) { return @{ Text = $Prompt; Added = @() } }
    $text = ([string]$Prompt).TrimEnd() + "`n`nRules (added automatically by the watcher):`n" + ($lines -join "`n") + "`n"
    return @{ Text = $text; Added = @($added.ToArray()) }
}
