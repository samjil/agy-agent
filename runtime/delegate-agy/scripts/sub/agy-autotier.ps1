# agy-autotier.ps1
# 요청의 난이도를 보고 agy 모델의 "노력 단계"(low / medium / high)를 자동으로 고르는 헬퍼 모음입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-autotier.ps1")`  (watch-agy.ps1 과 handoff-pump.ps1 이 씁니다)
#
# 왜 필요한가:
#   간단한 질문·확인·번역까지 매번 가장 높은 단계(gemini-3.8-flash-high)로 돌리면 시간과 쿼터가 낭비된다.
#   그렇다고 어려운 일을 낮은 단계로 돌리면 결과가 미달이라 재위임 비용이 더 든다. 그래서 "분명히 쉬운 것만" 낮추고,
#   애매하면 지금까지처럼 high 를 쓴다(보수적). 이 판정은 규칙(키워드·길이)이라 LLM 을 따로 부르지 않는다.
#
# 단계와 모델 (agy 모델 ID 에 노력 단계가 들어 있다):
#   low    gemini-3.8-flash-low     분명히 쉬운 일: 짧은 질문·확인·번역·계산·목록·읽기만 하는 조회
#   medium gemini-3.8-flash-medium  분석·검토·설명처럼 생각은 필요하지만 파일을 바꾸지는 않는 일, 중간 길이 요청
#   high   gemini-3.8-flash-high    설계·최적화·디버깅 같은 어려운 단어, 폴더의 파일을 바꾸는 일(작은 수정은 예외: 아래), 긴 요청, 단계가 많은 요청
#
# 폴더(@cwd)의 파일을 바꾸는 일은 원래 모두 high 였는데, 위임의 대부분이 이 경우라 사소한 수정도 high(한 번에 약 9~12분)로 가서 대기가 길었다.
# 그래서 "작은 수정"의 신호를 모두 만족할 때만 medium 으로 낮춘다(하나라도 어긋나면 high 그대로. 보수적):
#   - 기존 것을 고치는 말(수정·고쳐·변경·바꿔·적용·삭제 등)이고, 새로 만드는 말(구현·추가·작성·만들 등)이 없다
#   - 지시문이 500자 이하, 파일 경로로 보이는 토큰이 1개 이하, 코드 블록·번호 단계·"전체/모든" 같은 넓은 범위 말이 없다
#   - 어려운 단어가 없다(버그·리팩토링도 어려운 단어로 센다)
# 낮춘 결과가 미달이면 검토하는 쪽(Claude)이 한 단계 올려 다시 보내므로, 기준은 일부러 좁게 잡았다.
#
# 다음에는 쓰이지 않는다(그대로 따른다):
#   - 지시파일에 @model: 로 모델을 직접 골랐을 때, 이어가는 @session 대화(대화는 시작할 때의 모델을 유지한다)
#   - 환경변수 AGY_AUTO_MODEL 이 off / 0 / false 일 때(전체 끄기)
#
# 한계: 규칙이라 틀릴 수 있다. 낮은 단계로 간 결과가 미달이면 검토하는 쪽(Claude)이 @model: gemini-3.8-flash-high 로 다시 보낸다.

$script:AgyAutoTierModels = @{
    low    = "gemini-3.8-flash-low"
    medium = "gemini-3.8-flash-medium"
    high   = "gemini-3.8-flash-high"
}

# 켜져 있는가. 기본은 켜짐. AGY_AUTO_MODEL=off|0|false|no 면 꺼짐.
function Test-AgyAutoTierEnabled {
    $v = ([string]$env:AGY_AUTO_MODEL).Trim()
    return -not ($v -match '^(?i:off|0|false|no)$')
}

# 어려운 일을 알리는 단어: 하나라도 있으면 high.
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
# 반환: @{ Tier = 'low'|'medium'|'high'; Model = <정식 모델 ID>; Reason = <왜 그렇게 골랐는지 한 줄> }
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
    return @{ Tier = $tier; Model = $script:AgyAutoTierModels[$tier]; Reason = $reason }
}
