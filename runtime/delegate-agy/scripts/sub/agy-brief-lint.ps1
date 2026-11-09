# agy-brief-lint.ps1
# agy 에게 보낼 지시문(브리프)이 두 원칙(1 정확도 우선, 2 직접보다 싸야 함)에 맞는지 가볍게 점검하는 헬퍼입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "sub\agy-brief-lint.ps1")`  (submit-task.ps1 이 씁니다)
#
# 왜 필요한가:
#   스킬이 4단 브리프(목표 · 대상 명세 · 규칙과 Non-Goals · 검증과 DIGEST)를 쓰라고 안내하지만 권고일 뿐이라, Sonnet 이나 낮은 Effort 로 돌 때
#   검증 명령이나 접근 금지 범위를 빼먹은 채 위임될 수 있다. 그러면 첫 번에 틀려 재위임이 생기고(정확도 하락) 토큰은 더 든다(원칙 2 위반).
#   그래서 보내기 직전에 흔한 빠짐을 알려 준다.
#
# 규칙:
#   - 경고만 한다. 위임을 막거나 지시문을 바꾸지 않는다(오탐이 있어도 일을 막지 않으려고).
#   - 폴더(@cwd)를 여는 작업에만 보는 항목(검증 · 범위 · 대상 파일 · 너무 짧음)과, 모든 위임에 보는 항목(너무 긺 · 긴 코드 붙여넣기 · 능력을 추측한 금지 · 한글 답변 문장)이 있다.
#   - `@raw: true` 면 점검하지 않는다(자기 규칙을 직접 쓰는 작업). 환경변수 AGY_BRIEF_LINT=off 로 끈다.
#
# 반환: 경고 문장 배열(없으면 빈 배열). 문장마다 한 줄이고 어떻게 고치면 되는지가 들어 있다.

$script:AgyBriefMaxChars = 6000          # 이보다 길면 명세를 파일로 쓰고 경로만 가리키는 편이 싸다(원칙 2)
$script:AgyBriefMinChars = 80            # @cwd 작업의 본문이 이보다 짧으면 맥락이 모자랄 가능성이 크다
$script:AgyBriefMaxFenceLines = 80       # 코드 블록 하나가 이보다 길면 파일 본문을 붙여넣은 것으로 본다

# 답변 언어(Get-AgyReplyLanguage)가 Korean 이면 한글로, 아니면 영어로 경고한다.
if (-not (Get-Command Get-AgyReplyLanguage -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "agy-rules.ps1") }

function Test-AgyBriefLintEnabled {
    $v = ([string]$env:AGY_BRIEF_LINT).Trim()
    return -not ($v -match '^(?i:off|0|false|no)$')
}

# 지시문을 지시어 줄과 본문으로 나눈다(워처가 읽는 규칙: 맨 위의 `@이름: 값` 줄들, `@` 로 시작하지 않는 첫 줄부터가 본문).
function Split-AgyBriefDirectives([string]$Text) {
    $directives = @{}
    $lines = ([string]$Text) -split "\r?\n"
    $i = 0
    while ($i -lt $lines.Count) {
        $m = [regex]::Match($lines[$i], '^\s*@([A-Za-z]+)\s*:\s*(.*)$')
        if (-not $m.Success) { break }
        $key = $m.Groups[1].Value.ToLowerInvariant()
        if (-not $directives.ContainsKey($key)) { $directives[$key] = New-Object System.Collections.ArrayList }
        [void]$directives[$key].Add($m.Groups[2].Value.Trim())
        $i++
    }
    $body = if ($i -lt $lines.Count) { ($lines[$i..($lines.Count - 1)] -join "`n") } else { "" }
    return @{ Directives = $directives; Body = $body }
}

function Get-AgyBriefWarnings([string]$Text) {
    $out = New-Object System.Collections.ArrayList
    $parts = Split-AgyBriefDirectives $Text
    $dir = $parts.Directives
    $body = [string]$parts.Body
    $isRaw = $dir.ContainsKey("raw") -and [bool]([string]$dir["raw"][0] -match '^(?i:true|yes|1|on|예)$')
    if ($isRaw) { return @() }
    $hasFolder = $dir.ContainsKey("cwd") -and @($dir["cwd"] | Where-Object { $_ }).Count -gt 0
    $compact = ($body -replace '\s+', '')
    $len = $body.Length
    $replyLang = Get-AgyReplyLanguage
    $ko = ($replyLang -eq "Korean")

    if ($hasFolder) {
        if ($compact.Length -lt $script:AgyBriefMinChars) {
            [void]$out.Add($(if ($ko) { "지시문 본문이 매우 짧습니다(공백 뺀 $($compact.Length)자). agy 는 빈 상태로 시작하니 목표 · 대상 파일 · 검증 방법을 적어야 첫 번에 맞습니다." } else { "The brief body is very short ($($compact.Length) characters without spaces). agy starts with nothing, so state the goal, the target files and how to verify to get it right the first time." }))
        }
        if ($body -notmatch '(?i)(검증|테스트|시험|빌드|린트|lint|typecheck|타입\s*체크|test|build|verify|실행해|\[4\.)') {
            [void]$out.Add($(if ($ko) { "검증 방법이 보이지 않습니다. 돌릴 테스트·빌드 명령과 보고 형식을 적으세요(4단 브리프의 [4]). 없으면 agy 의 자기 보고를 믿을 수밖에 없고 재위임이 늘어납니다." } else { "No way to verify is visible. Name the test or build command to run and the report format (part [4] of the four-part brief). Without it you can only trust agy's own report and re-delegation goes up." }))
        }
        if ($body -notmatch '(?i)(접근\s*금지|건드리지|수정하지|손대지|지적하지|바꾸지|non-?goals?|범위\s*밖|범위\s*제한|\[3\.|하지\s*말|do\s+not\s+(touch|modify|change|edit)|don''t\s+(touch|modify|change|edit)|out\s+of\s+scope|must\s+not)') {
            [void]$out.Add($(if ($ko) { "범위 제한(건드리면 안 되는 파일·코드, Non-Goals)이 보이지 않습니다(4단 브리프의 [3]). 없으면 agy 가 무관한 코드까지 고치거나 지적합니다." } else { "No scope limit is visible (files or code not to touch, non-goals; part [3] of the four-part brief). Without it agy may change or comment on unrelated code." }))
        }
        if ($body -notmatch '(?i)(?<![\w.])[\w가-힣./\\:-]*[\w가-힣-]\.(?:ps1|psm1|js|mjs|ts|tsx|jsx|java|kt|py|cs|go|rs|css|scss|html|json|ya?ml|xml|md|sql|sh|bat|vue|gradle|properties|txt|csv|ini|toml)\b' -and $body -notmatch '\[2\.') {
            [void]$out.Add($(if ($ko) { "대상 파일 경로가 보이지 않습니다. 실제 존재를 확인한 파일 경로:줄을 적어 주세요(4단 브리프의 [2]). agy 가 파일을 찾느라 단계와 토큰을 씁니다." } else { "No target file path is visible. Give file paths with line numbers that you have checked exist (part [2] of the four-part brief). Otherwise agy spends steps and tokens searching for files." }))
        }
    }

    if ($len -gt $script:AgyBriefMaxChars) {
        [void]$out.Add($(if ($ko) { "지시문이 깁니다($len자). 명세가 길면 파일로 써 두고 지시문에는 그 경로만 가리키세요(토큰이 직접 하는 것보다 적어야 합니다)." } else { "The brief is long ($len characters). If the spec is long, write it to a file and point to that path in the brief (delegating must cost fewer tokens than doing it yourself)." }))
    }
    # 코드 블록 하나가 너무 길면 파일 본문을 붙여넣은 것
    $maxFence = 0
    foreach ($m in [regex]::Matches($body, '(?s)```[^\n]*\n(.*?)```')) {
        $n = ($m.Groups[1].Value.TrimEnd([char]10, [char]13) -split "\n").Count
        if ($n -gt $maxFence) { $maxFence = $n }
    }
    if ($maxFence -gt $script:AgyBriefMaxFenceLines) {
        [void]$out.Add($(if ($ko) { "코드 블록이 ${maxFence}줄로 깁니다. 파일 본문을 붙이지 말고 파일 경로:줄만 적으세요(agy 가 @cwd 로 직접 읽습니다)." } else { "A code block is ${maxFence} lines long. Do not paste file contents; give path:line only (agy reads the files itself through @cwd)." }))
    }
    if ($body -match '(?i)((브라우저|browser|chrome|크롬)[^.\n]{0,14}(열지|쓰지|사용하지|금지)|do\s+not\s+(open|use)\s+(a\s+)?(web\s+)?browser)') {
        [void]$out.Add($(if ($ko) { "'브라우저를 열지 마라' 같은 능력을 추측한 금지가 있습니다. agy 는 chrome-devtools-mcp 로 로컬 화면을 열 수 있으니, 금지는 실제로 위험한 것(범위 밖 수정, git 상태 변경)에만 두세요." } else { "The brief forbids something based on a guess about agy's abilities (for example 'do not open a browser'). agy can open local pages through chrome-devtools-mcp, so only forbid what is really risky (edits out of scope, changing git state)." }))
    }
    if (-not $hasFolder) {
        if ($ko) {
            if ($body -notmatch '(?i)(한글|한국어|in\s+korean)') {
                [void]$out.Add("한글로 답하라는 문장이 없습니다. @cwd 가 없는 위임은 '최종 답변은 한글로 작성' 문장을 직접 넣어야 합니다(번역처럼 결과 언어가 한국어가 아니면 무시하세요).")
            }
        } elseif ($replyLang -ne "English" -and $body -notmatch ('(?i)\b' + [regex]::Escape($replyLang) + '\b')) {
            [void]$out.Add("No sentence tells agy to answer in $replyLang. A delegation without @cwd needs a line such as 'Write the final reply in $replyLang' (ignore this for translation or other tasks whose result is in another language).")
        }
    }
    return @($out.ToArray())
}
