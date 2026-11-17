# agy-autotier.ps1
# @model 이 없는 위임에서 요청 내용을 보고 모델 단계를 자동으로 고르는 헬퍼 모음입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-autotier.ps1")`  (watch-agy.ps1 과 handoff-pump.ps1 이 씁니다)
#
# 자동으로 고르는 단계는 두 개뿐입니다(단계 -> 모델은 config\models.json, agy-models.ps1 참고):
#   quick  (기본 gemini-4-hydrogen-low)     읽기만 하는 짧은 일: 짧은 질문 · 확인 · 번역 · 계산 · 목록 · 조회
#   build  (기본 gemini-4-hydrogen-medium)  파일을 바꾸는 일, 분석 · 검토 · 설명처럼 생각이 필요한 일, 긴 요청
# build-hard · feature · think · deep 은 자동으로 고르지 않습니다. 낱말만 보고 Orchestrator · Extra 로 보내면 명세가 분명한 일에서
# 느리고 비싸기 때문입니다(2026-11-17 측정). 그런 일은 Claude 가 조건을 보고 브리프에 @model: <단계> 로 적습니다.
#
# 판정 규칙(키워드 · 길이, LLM 을 따로 부르지 않음): 아래 내부 판정이 low 면 quick, medium 이상이면 build.
#   - 어려운 단어 · 긴 요청 · 단계가 많은 요청 · 파일을 바꾸는 말 · 분석 단어 · 중간 길이 · 코드 블록이 있으면 build
#   - 그 밖의 짧은 일은 quick
#
# 다음에는 쓰이지 않는다(그대로 따른다):
#   - 지시파일에 @model: 로 단계나 모델을 골랐을 때, 이어가는 @session 대화(대화는 시작할 때의 모델을 유지한다)
#   - 환경변수 AGY_AUTO_MODEL 이 off / 0 / false 일 때(전체 끄기: 이때는 설정의 auto.write 단계, 기본 build)
#
# 한계: 규칙이라 틀릴 수 있다. quick 결과가 미달이면 검토하는 쪽(Claude)이 @model: build 로 다시 보낸다.

$autoTierModelsLib = Join-Path $PSScriptRoot "agy-models.ps1"
if (-not (Get-Command Get-AgyModelConfig -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $autoTierModelsLib)) { . $autoTierModelsLib }

# 켜져 있는가. 기본은 켜짐. AGY_AUTO_MODEL=off|0|false|no 면 꺼짐.
function Test-AgyAutoTierEnabled {
    $v = ([string]$env:AGY_AUTO_MODEL).Trim()
    return -not ($v -match '^(?i:off|0|false|no)$')
}

# 어려운 일을 알리는 단어: 하나라도 있으면 내부 판정 high(-> build).
$script:AgyTierHeavyPattern = '(?i)(설계|아키텍처|리팩토링|리팩터|마이그레이션|보안|인증|결제|암호화|동시성|알고리즘|최적화|성능|디버깅|디버그|버그|근본\s*원인|트레이드오프|design|architect|refactor|migrat|security|authenticat|concurren|algorithm|optimi[sz]|debug|root\s*cause|trade-?off)'
# 폴더의 파일이나 상태를 바꾸는 일을 알리는 말.
$script:AgyTierWritePattern = '(?i)(수정|고쳐|고치|구현|추가해|추가하|삭제|작성해|작성하|만들어|만드|변경|바꿔|바꾸|반영|적용|이동|이름\s*바|커밋|implement|\bfix\b|\badd\b|\bwrite\b|\bcreate\b|\bmodify\b|\bupdate\b|\bdelete\b|\bremove\b|\brename\b|\bcommit\b)'
# "읽기만 한다"고 밝힌 말. 이게 있으면 위의 쓰기 단어(예: "고치지 않고")는 무시한다.
$script:AgyTierReadOnlyPattern = '(?i)(읽기\s*전용|읽기만|read-?only|(수정|고치|만들|쓰|변경)[^.\r\n]{0,14}않)'
# 기존 것을 고치는 말 / 새로 만드는 말 / 넓은 범위를 뜻하는 말: "작은 수정" 판정에 쓴다.
$script:AgyTierModifyPattern = '(?i)(수정|고쳐|고치|변경|바꿔|바꾸|반영|적용|이동|이름\s*바|삭제|\bfix\b|\bmodify\b|\bupdate\b|\brename\b|\bremove\b|\bdelete\b)'
$script:AgyTierCreatePattern = '(?i)(구현|추가해|추가하|추가한|작성해|작성하|만들어|만드|\bimplement\b|\badd\b|\bwrite\b|\bcreate\b)'
$script:AgyTierBroadPattern = '(?i)(전체|모든|전부|일괄|전반|코드베이스|\ball\b|\bevery\b|\bentire\b|\bwhole\b)'
# 파일 경로로 보이는 토큰(확장자가 있는 이름). 서로 다른 것의 개수를 센다.
$script:AgyTierFilePattern = '(?i)(?<![\w.])[\w가-힣./\\:-]*[\w가-힣-]\.(?:ps1|psm1|js|mjs|ts|tsx|jsx|java|kt|py|cs|go|rs|c|cc|cpp|h|hpp|css|scss|html|htm|json|ya?ml|xml|md|sql|sh|bat|vue|gradle|properties|txt|csv|ini|toml|config)\b'
$script:AgySmallEditMaxChars = 500
$script:AgySmallEditMaxFiles = 1

# 생각이 필요한 일: 분석·검토·설명 등. 있으면 최소 medium.
$script:AgyTierAnalysisPattern = '(?i)(분석|원인|왜\s|이유|검토|리뷰|비교|조사|평가|점검|설명|explain|analy[sz]|review|compare|investigat|\bwhy\b)'

# 요청 본문(지시어 줄을 뺀 것)과 폴더 접근 여부로 단계를 고른다.
#   $Text      프롬프트 본문
#   $HasFolder @cwd 로 열리는 폴더가 있는가(있으면 agy 가 파일을 읽고 쓸 수 있다)
# 반환: @{ Tier = 'quick'|'build' (설정의 auto.read / auto.write); Model = <그 단계의 주 모델>; Reason = <왜 그렇게 골랐는지 한 줄> }
function Get-AgyAutoTier([string]$Text, [bool]$HasFolder = $false) {
    $t = ([string]$Text).Trim()
    $len = $t.Length
    $heavy = [regex]::Match($t, $script:AgyTierHeavyPattern)
    $readOnly = [regex]::IsMatch($t, $script:AgyTierReadOnlyPattern)
    $write = [regex]::Match($t, $script:AgyTierWritePattern)
    $analysis = [regex]::Match($t, $script:AgyTierAnalysisPattern)
    $fences = [int]([regex]::Matches($t, '```').Count / 2)
    $steps = [regex]::Matches($t, '(?m)^\s*\d+[.)]\s').Count
    $fileTokens = @([regex]::Matches($t, $script:AgyTierFilePattern) | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique).Count

    $tier = "low"
    $reason = "짧고(${len}자) 분석·파일 변경 단어가 없는 일"
    if ($heavy.Success) {
        $tier = "high"; $reason = "어려운 작업 단어('$($heavy.Value)')"
    } elseif ($fences -ge 2 -or $steps -ge 5 -or $len -gt 2500) {
        $tier = "high"
        $reason = if ($len -gt 2500) { "긴 요청(${len}자)" } elseif ($steps -ge 5) { "단계가 많은 요청(${steps}단계)" } else { "코드 블록이 여럿(${fences}개)" }
    } elseif ($write.Success -and -not $readOnly) {
        if ($HasFolder) {
            # 작은 수정이면 medium: 고치는 말이고, 새로 만드는 말·넓은 범위 말이 없고, 짧고, 파일이 많지 않고, 코드 블록·번호 단계가 없다(어려운 단어는 위에서 이미 걸러졌다)
            $modifies = [regex]::IsMatch($t, $script:AgyTierModifyPattern)
            $creates = [regex]::IsMatch($t, $script:AgyTierCreatePattern)
            $broad = [regex]::Match($t, $script:AgyTierBroadPattern)
            $big = @()
            if (-not $modifies) { $big += "고치는 말이 아님" }
            if ($creates) { $big += "새로 만드는 말" }
            if ($broad.Success) { $big += "넓은 범위('$($broad.Value)')" }
            if ($len -gt $script:AgySmallEditMaxChars) { $big += "${len}자" }
            if ($fileTokens -gt $script:AgySmallEditMaxFiles) { $big += "파일 ${fileTokens}개" }
            if ($fences -gt 0) { $big += "코드 블록" }
            if ($steps -gt 0) { $big += "번호 단계" }
            if ($big.Count -eq 0) { $tier = "medium"; $reason = "폴더의 작은 수정('$($write.Value)', ${len}자, 파일 ${fileTokens}개)" }
            else { $tier = "high"; $reason = "폴더의 파일을 바꾸는 일('$($write.Value)') - 작은 수정 아님: $($big -join ', ')" }
        }
        else { $tier = "medium"; $reason = "만들거나 고치는 일('$($write.Value)')" }
    } elseif ($analysis.Success) {
        $tier = "medium"; $reason = "분석·검토·설명 단어('$($analysis.Value.Trim())')"
    } elseif ($len -gt 1200 -or $fences -eq 1) {
        $tier = "medium"; $reason = if ($fences -eq 1) { "코드 블록이 있는 요청" } else { "중간 길이 요청(${len}자)" }
    } elseif ($readOnly -and $HasFolder) {
        $reason = "읽기만 하는 짧은 일(${len}자)"
    }
    # 내부 판정 low -> quick, medium · high -> build. 어려워 보여도 build 보다 위 단계는 자동으로 쓰지 않는다(Claude 가 @model 로 적는다).
    $cfg = Get-AgyModelConfig
    $readTier = if ($cfg.Auto -and $cfg.Auto.read -and $cfg.Tiers.Contains([string]$cfg.Auto.read)) { [string]$cfg.Auto.read } else { "quick" }
    $writeTier = if ($cfg.Auto -and $cfg.Auto.write -and $cfg.Tiers.Contains([string]$cfg.Auto.write)) { [string]$cfg.Auto.write } else { "build" }
    $picked = if ($tier -eq "low") { $readTier } else { $writeTier }
    if ($tier -eq "high") { $reason = "$reason (자동 선택은 $writeTier 까지만)" }
    $model = if ($cfg.Tiers.Contains($picked)) { [string]$cfg.Tiers[$picked].Model } else { "" }
    return @{ Tier = $picked; Model = $model; Reason = $reason }
}
