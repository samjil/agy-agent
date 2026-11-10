# token-stats.ps1
# Claude Code 대화 기록(~/.claude/projects/*/*.jsonl)에서 실제 토큰 사용량을 수집해,
# 도구 호출 수에 따른 토큰 예상 식(Theil-Sen 보정)을 갱신하고 calibration.json 에 저장합니다.
param(
    [switch]$Update,
    [switch]$Report,
    [switch]$Backfill,
    [string]$DbPath = "",
    [string]$ProjectsDir = "",
    [string]$RuntimeDir = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# 의존 모듈 로드
. (Join-Path $PSScriptRoot "agy-db.ps1")
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "agy-layout.ps1")) {
    . (Join-Path $PSScriptRoot "agy-layout.ps1")
}

# 예상 기록 호출(record-estimate.ps1 ... -Choice ...)은 도구 호출 수와 경로(직접/위임/대화) 판정에서 뺀다.
# 기록은 통계를 위한 부가 호출이라 센 호출 수에 들어가면 예상 식과 순수 대화 턴이 오염된다.
$script:RecordEstimateCallPattern = 'record-estimate\.ps1.*(?:-Choice|-Switch)'

# 도구 결과에서 위임 작업 번호를 읽는 무늬: submit-task.ps1 이 줄 맨 앞에 찍는 표시(submitted: · ===RESULT=== 등) 뒤의 번호만 읽는다.
# 대화 기록 한 줄(JSON) 안에서 줄 맨 앞은 글자열이 시작하는 따옴표 바로 뒤이거나 \n 뒤다. 파일을 읽거나 검색한 출력 속에 인용된 것(\" 뒤)은 읽지 않는다
# (시험 파일을 grep 한 출력의 가짜 번호가 그 질문의 위임으로 잡히던 문제).
$script:TaskMarkPattern = '(?:(?<!\\)"|(?<!\\)\\n)(?:submitted|===RESULT===|===PENDING===|===ERROR===)[: ]+\s*(claude_\d+_\d+)'
$script:TaskSubmittedPattern = '(?:(?<!\\)"|(?<!\\)\\n)submitted[: ]+\s*(claude_\d+_\d+)'

# 이 도구 호출이 예상 기록(record-estimate)만 하는가. 기록을 첫 작업 명령 앞에 붙여 한 번에 실행하면(record-estimate … ; git status)
# 그 호출은 실제 작업이라 호출 수에 센다. 기록만 하는 호출만 뺀다. 명령을 읽지 못하면 예전처럼 기록 호출로 본다.
function Test-RecordEstimateOnlyLine([string]$Line) {
    if ($Line -notmatch $script:RecordEstimateCallPattern) { return $false }
    $m = [regex]::Match($Line, '"command"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return $true }
    $cmd = $m.Groups[1].Value -replace '\\n', "`n" -replace '\\"', '"'
    foreach ($seg in ($cmd -split ';|&&|\|\||\r?\n')) {
        $s = $seg.Trim()
        if ($s -and $s -notmatch 'record-estimate\.ps1') { return $false }
    }
    return $true
}

function Test-IsDelegationToolCall([string]$ToolName, $InputObj) {
    if ($ToolName -and $ToolName -notmatch '(?i)^(bash|powershell|cmd|terminal)$') {
        return $false
    }
    $cmd = ""
    if ($InputObj -is [System.Collections.IDictionary]) {
        if ($InputObj.ContainsKey('command')) { $cmd = [string]$InputObj['command'] }
        elseif ($InputObj.ContainsKey('code')) { $cmd = [string]$InputObj['code'] }
        else {
            $parts = @()
            foreach ($v in $InputObj.Values) { if ($v) { $parts += [string]$v } }
            $cmd = $parts -join " "
        }
    } elseif ($InputObj -is [string]) {
        $cmd = $InputObj
    }
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }

    if ($cmd -match '(?i)\bsubmit-task(?:\.ps1)?\b') { return $true }
    if ($cmd -match '(?i)-Poll\b') { return $true }
    if ($cmd -match '(?i)-NoWait\b') { return $true }
    if ($cmd -match '(?i)\bensure-agy-running(?:\.ps1)?\b') { return $true }
    if ($cmd -match '(?i)\bstop-agy(?:\.ps1)?\b') { return $true }
    if ($cmd -match '(?i)(?:inbox[/\\].*<<|<<.*inbox[/\\].*|>>?\s*.*inbox)') { return $true }
    return $false
}

function ConvertTo-TokenNumber([string]$Val, [string]$K) {
    if ([string]::IsNullOrWhiteSpace($Val)) { return $null }
    $numStr = $Val.Replace(',', '').Trim()
    $d = 0.0
    if (-not [double]::TryParse($numStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $null
    }
    if ($K -and $K.Trim().ToLower() -eq 'k') {
        $d = $d * 1000.0
    }
    return $d
}

function ConvertTo-TimeSeconds([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()
    $total = 0.0
    $hasMatch = $false

    # Hour
    $mH = [regex]::Match($t, '(?i)(\d+(?:\.\d+)?)\s*(?:시간|h(?:ours?|rs?)?)\b')
    if (-not $mH.Success) {
        $mH = [regex]::Match($t, '(?i)(\d+(?:\.\d+)?)\s*(?:시간|h)')
    }
    if ($mH.Success) {
        $val = 0.0
        if ([double]::TryParse($mH.Groups[1].Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
            $total += $val * 3600.0
            $hasMatch = $true
            $t = $t.Remove($mH.Index, $mH.Length)
        }
    }

    # Minute
    $mM = [regex]::Match($t, '(?i)(\d+(?:\.\d+)?)\s*(?:분|m(?:in(?:ute)?s?)?)\b')
    if (-not $mM.Success) {
        $mM = [regex]::Match($t, '(?i)(\d+(?:\.\d+)?)\s*(?:분|m)')
    }
    if ($mM.Success) {
        $val = 0.0
        if ([double]::TryParse($mM.Groups[1].Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
            $total += $val * 60.0
            $hasMatch = $true
            $t = $t.Remove($mM.Index, $mM.Length)
        }
    }

    # Second
    $mS = [regex]::Match($t, '(?i)(\d+(?:\.\d+)?)\s*(?:초|s(?:ec(?:ond)?s?)?)\b')
    if (-not $mS.Success) {
        $mS = [regex]::Match($t, '(?i)(\d+(?:\.\d+)?)\s*(?:초|s)')
    }
    if ($mS.Success) {
        $val = 0.0
        if ([double]::TryParse($mS.Groups[1].Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
            $total += $val
            $hasMatch = $true
        }
    }

    if (-not $hasMatch) { return $null }
    return [int][Math]::Round($total)
}

function Format-DurationText($Seconds) {
    if ($null -eq $Seconds -or $Seconds -eq [DBNull]::Value -or $Seconds -lt 0) { return "-" }
    $s = [int]$Seconds
    if ($s -lt 60) { return ("{0}초" -f $s) }
    $h = [Math]::Floor($s / 3600)
    $m = [Math]::Floor(($s % 3600) / 60)
    if ($h -gt 0) {
        if ($m -gt 0) { return ("{0}시간 {1}분" -f $h, $m) }
        else { return ("{0}시간" -f $h) }
    } else {
        return ("{0}분" -f $m)
    }
}

function Get-TokenEstimate([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $estDirect = $null
    $estDelegate = $null
    $estTimeDirect = $null
    $estTimeDelegate = $null
    $version = $null
    $format = $null

    # v2 토큰: 예상 토큰: 직접 **X** (vs|·) 위임 **Y**
    $rxTokV2 = [regex]'예상\s*토큰\s*:\s*직접\s*\*\*\s*([\d.,]+)\s*([kK]?)\s*\*\*\s*(?:vs|[·\u00B7\u2022\.])\s*위임\s*\*\*\s*([\d.,]+)\s*([kK]?)\s*\*\*'
    $mTok = $rxTokV2.Match($Text)
    if ($mTok.Success) {
        $estDirect = ConvertTo-TokenNumber $mTok.Groups[1].Value $mTok.Groups[2].Value
        $estDelegate = ConvertTo-TokenNumber $mTok.Groups[3].Value $mTok.Groups[4].Value
        $version = "v2"
        $format = "new"
    }

    # v2 시간: 예상 시간: 직접 **A** (vs|·) 위임 **B**
    $rxTimeV2 = [regex]'예상\s*시간\s*:\s*직접\s*\*\*\s*([^*]+?)\s*\*\*\s*(?:vs|[·\u00B7\u2022\.])\s*위임\s*\*\*\s*([^*]+?)\s*\*\*'
    $mTime = $rxTimeV2.Match($Text)
    if ($mTime.Success) {
        $estTimeDirect = ConvertTo-TimeSeconds $mTime.Groups[1].Value
        $estTimeDelegate = ConvertTo-TimeSeconds $mTime.Groups[2].Value
        if (-not $version) {
            $version = "v2"
            $format = "new"
        }
    }

    if ($version -eq "v2") {
        return @{
            Direct       = $estDirect
            Delegate     = $estDelegate
            TimeDirect   = $estTimeDirect
            TimeDelegate = $estTimeDelegate
            Version      = "v2"
            Format       = $format
        }
    }

    # 옛 형식 1: 토큰 직접 ~N < 위임 ~M
    $rxOld1 = [regex]'토큰\s*직접\s*~\s*([\d.,]+)\s*([kK]?)\s*<\s*위임\s*~\s*([\d.,]+)\s*([kK]?)'
    $m = $rxOld1.Match($Text)
    if ($m.Success) {
        $d = ConvertTo-TokenNumber $m.Groups[1].Value $m.Groups[2].Value
        $del = ConvertTo-TokenNumber $m.Groups[3].Value $m.Groups[4].Value
        return @{ Direct = $d; Delegate = $del; TimeDirect = $null; TimeDelegate = $null; Version = "v1"; Format = "old1" }
    }

    # 옛 형식 2: 직접 **X** vs 위임 **Y** (예상 토큰: 접두 없음)
    $rxOld2 = [regex]'직접\s*\*\*\s*([\d.,]+)\s*([kK]?)\s*\*\*\s*vs\s*위임\s*\*\*\s*([\d.,]+)\s*([kK]?)\s*\*\*'
    $m = $rxOld2.Match($Text)
    if ($m.Success) {
        $d = ConvertTo-TokenNumber $m.Groups[1].Value $m.Groups[2].Value
        $del = ConvertTo-TokenNumber $m.Groups[3].Value $m.Groups[4].Value
        return @{ Direct = $d; Delegate = $del; TimeDirect = $null; TimeDelegate = $null; Version = "v1"; Format = "old2" }
    }

    return $null
}

function Get-TokenTurnChoice([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text -match '\*\*\[Agy 위임 · 직접 처리( · 수준 (낮음|보통|높음))?\]\*\*') { return 'direct' }
    if ($Text -match '\*\*\[Agy 위임( · 수준 (낮음|보통|높음))?\]\*\*') { return 'delegate' }
    return $null
}

# assistant 대화 기록 한 줄에서 text 블록의 글만 이어 붙여 돌려준다(도구 입력 · 생각 블록은 뺀다).
function Get-AssistantTextBlocks([string]$Line) {
    try {
        Add-Type -AssemblyName System.Web.Extensions
        if (-not $script:TokenStatsJsonReader) { $script:TokenStatsJsonReader = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $script:TokenStatsJsonReader.MaxJsonLength = [int]::MaxValue }
        $o = $script:TokenStatsJsonReader.DeserializeObject($Line)
        if (-not ($o -is [System.Collections.IDictionary]) -or -not $o.ContainsKey('message')) { return "" }
        $m = $o['message']
        if (-not ($m -is [System.Collections.IDictionary]) -or -not $m.ContainsKey('content')) { return "" }
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in @($m['content'])) {
            if ($b -is [System.Collections.IDictionary] -and [string]$b['type'] -eq 'text' -and $b.ContainsKey('text')) { [void]$sb.Append([string]$b['text']).Append("`n") }
        }
        return $sb.ToString()
    } catch {
        # JSON 으로 읽지 못하는 줄(잘린 줄 등)은 예전처럼 줄 전체를 글로 본다
        return ($Line -replace '\\n', "`n" -replace '\\"', '"')
    }
}

function Get-TokenTurnReason([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $rx = [regex]'(?m)\*\*\[Agy (?:위임|delegation)[^\]]*\]\*\*[ \t]*(.*?)(?=[ \t]{2,}|\r?$)'
    $found = @($rx.Matches($Text))
    if ($found.Count -eq 0) { return $null }
    $lastMatch = $found[$found.Count - 1]
    $val = $lastMatch.Groups[1].Value
    # 꼬리 줄이 메시지의 마지막 줄이면 대화 기록 JSON 의 나머지("}],...)가 같은 줄에 붙어 온다: 글이 끝나는 따옴표에서 자른다
    $val = ($val -split '"\s*[,}\]]')[0]
    if ([string]::IsNullOrWhiteSpace($val)) { return $null }
    $val = [regex]::Replace($val, '^(?i:\s*(?:이유|why)\s*:\s*)', '')
    $val = $val.Replace('**', '').Trim()
    if (-not $val) { return $null }
    if ($val.Length -gt 200) { $val = $val.Substring(0, 200) }
    return $val
}

function Get-TokenTurnLevel([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $rx = [regex]'\*\*\[Agy 위임(?: · 직접 처리)?(?: · 수준 (낮음|보통|높음))?\]\*\*'
    $found = $rx.Matches($Text)
    if ($found.Count -eq 0) { return $null }
    $lastMatch = $found[$found.Count - 1]
    if (-not $lastMatch.Groups[1].Success -or [string]::IsNullOrEmpty($lastMatch.Groups[1].Value)) {
        return $null
    }
    switch ($lastMatch.Groups[1].Value) {
        '낮음' { return 'low' }
        '보통' { return 'medium' }
        '높음' { return 'high' }
        default { return $null }
    }
}

function Get-TokenMedian($Numbers) {
    $arr = @($Numbers)
    if ($arr.Count -eq 0) { return $null }
    $sorted = @($arr | Sort-Object)
    $cnt = $sorted.Count
    if ($cnt % 2 -eq 1) {
        return [double]$sorted[ [Math]::Floor($cnt / 2) ]
    } else {
        $mid = $cnt / 2
        return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2.0
    }
}

function Get-TheilSenEstimator($Points, [int]$DefaultA, [int]$DefaultB) {
    $pts = @($Points)
    $n = $pts.Count
    if ($n -lt 8) {
        return @{ a = $DefaultA; b = $DefaultB; n = $n; source = "default" }
    }

    $slopes = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = $i + 1; $j -lt $n; $j++) {
            $dx = [double]$pts[$j].calls - [double]$pts[$i].calls
            if ($dx -ne 0.0) {
                $dy = [double]$pts[$j].d - [double]$pts[$i].d
                [void]$slopes.Add($dy / $dx)
            }
        }
    }
    if ($slopes.Count -eq 0) {
        return @{ a = $DefaultA; b = $DefaultB; n = $n; source = "default" }
    }

    $bRaw = Get-TokenMedian $slopes
    if ($bRaw -le 0.0) {
        return @{ a = $DefaultA; b = $DefaultB; n = $n; source = "default" }
    }

    $intercepts = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $n; $i++) {
        $intVal = [double]$pts[$i].d - ($bRaw * [double]$pts[$i].calls)
        [void]$intercepts.Add($intVal)
    }
    $aRaw = Get-TokenMedian $intercepts
    # 도구 호출이 0일 때의 기본 비용(절편 a)은 음수가 될 수 없으므로(컨텍스트 유지 및 최소 기본 입출력 비용은 항상 0 이상이어야 함) 음수가 나오면 0으로 보정한다.
    if ($aRaw -lt 0.0) { $aRaw = 0.0 }

    $a = [int]([Math]::Round($aRaw / 100.0) * 100)
    if ($a -lt 0) { $a = 0 }
    $b = [int]([Math]::Round($bRaw / 100.0) * 100)
    return @{ a = $a; b = $b; n = $n; source = "measured" }
}

# 수준별 보정: 프롬프트 수준(low/medium/high)마다 같은 식(a + b x 호출 수)을 따로 맞춘다.
# 필요한 표본 수는 고정하지 않고 호출당 값이 흩어진 정도로 정한다(Get-RequiredSampleSize, 30~300).
# 그 수준의 표본이 모자라면 전체 식($Overall)을 그대로 쓴다(source = "overall").
# $Kind: 'direct'(calls, d_tokens) | 'delegate'(calls_related/d_related 우선) | 'time'(calls, dur_sec)
function Get-TokenLevelFits($Rows, [string]$Kind, [bool]$HasLevelCol, $Overall) {
    $out = [ordered]@{}
    foreach ($lv in @('low', 'medium', 'high')) {
        $pts = New-Object System.Collections.ArrayList
        $rates = New-Object System.Collections.ArrayList
        if ($HasLevelCol) {
            foreach ($r in @($Rows)) {
                $rl = $r['level']
                if ($null -eq $rl -or $rl -eq [DBNull]::Value -or [string]$rl -ne $lv) { continue }
                $c = 0
                $v = 0.0
                if ($Kind -eq 'delegate') {
                    $c = if ($r['calls_related'] -ne $null -and $r['calls_related'] -ne [DBNull]::Value) { [int]$r['calls_related'] } else { [int]$r['calls'] }
                    $v = if ($r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { [double]$r['d_related'] } else { [double]$r['d_tokens'] }
                } elseif ($Kind -eq 'time') {
                    $c = [int]$r['calls']
                    $v = [double]$r['dur_sec']
                } else {
                    $c = [int]$r['calls']
                    $v = [double]$r['d_tokens']
                }
                if ($c -lt 1) { continue }
                if ($Kind -eq 'time') { [void]$pts.Add(@{ calls = $c; dur = [int]$v }) } else { [void]$pts.Add(@{ calls = $c; d = [int]$v }) }
                [void]$rates.Add($v / [double]$c)
            }
        }
        $req = Get-RequiredSampleSize $rates
        $n = $pts.Count
        $fit = $null
        if ($n -ge [int]$req.required) {
            if ($Kind -eq 'time') {
                $fit = Get-TheilSenTimeEstimator -Points $pts -DefaultA ([int]$Overall.a_s) -DefaultB ([int]$Overall.b_s)
            } else {
                $fit = Get-TheilSenEstimator -Points $pts -DefaultA ([int]$Overall.a) -DefaultB ([int]$Overall.b)
            }
            if ($fit.source -ne 'measured') { $fit = $null }
        }
        $src = if ($null -ne $fit) { "level" } else { "overall" }
        if ($Kind -eq 'time') {
            $aV = if ($null -ne $fit) { $fit.a_s } else { $Overall.a_s }
            $bV = if ($null -ne $fit) { $fit.b_s } else { $Overall.b_s }
            $out[$lv] = [ordered]@{ a_s = [int]$aV; b_s = [int]$bV; n = [int]$n; required = [int]$req.required; cv = $req.cv; width = $req.width; source = $src }
        } else {
            $aV = if ($null -ne $fit) { $fit.a } else { $Overall.a }
            $bV = if ($null -ne $fit) { $fit.b } else { $Overall.b }
            $out[$lv] = [ordered]@{ a = [int]$aV; b = [int]$bV; n = [int]$n; required = [int]$req.required; cv = $req.cv; width = $req.width; source = $src }
        }
    }
    return $out
}

function Get-TheilSenTimeEstimator($Points, [int]$DefaultA = 11, [int]$DefaultB = 15) {
    $pts = @($Points)
    $n = $pts.Count
    if ($n -lt 8) {
        return @{ a_s = $DefaultA; b_s = $DefaultB; n = $n; source = "default" }
    }

    $slopes = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $n; $i++) {
        for ($j = $i + 1; $j -lt $n; $j++) {
            $dx = [double]$pts[$j].calls - [double]$pts[$i].calls
            if ($dx -ne 0.0) {
                $dy = [double]$pts[$j].dur - [double]$pts[$i].dur
                [void]$slopes.Add($dy / $dx)
            }
        }
    }
    if ($slopes.Count -eq 0) {
        return @{ a_s = $DefaultA; b_s = $DefaultB; n = $n; source = "default" }
    }

    $bRaw = Get-TokenMedian $slopes
    if ($bRaw -le 0.0) {
        return @{ a_s = $DefaultA; b_s = $DefaultB; n = $n; source = "default" }
    }

    $intercepts = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $n; $i++) {
        $intVal = [double]$pts[$i].dur - ($bRaw * [double]$pts[$i].calls)
        [void]$intercepts.Add($intVal)
    }
    $aRaw = Get-TokenMedian $intercepts
    if ($aRaw -lt 0.0) { $aRaw = 0.0 }

    $a = [int][Math]::Round($aRaw)
    if ($a -lt 0) { $a = 0 }
    $b = [int][Math]::Round($bRaw)
    return @{ a_s = $a; b_s = $b; n = $n; source = "measured" }
}

# 수준별 식을 쓰기에 표본이 충분한지 정한다(필요한 표본 수).
# 목표: 호출당 값의 중앙값이 95% 확률로 실제 값의 ±$Rel(15%) 안에 들 것.
# 분포 모양을 가정하지 않으려고 부트스트랩을 쓴다: 지금 표본에서 같은 수를 복원 추출해 중앙값을 $Boot 번 다시 구하고,
# 그 중앙값이 원래 중앙값에서 벗어난 비율의 95번째 값(width)을 잰다. 벗어남은 표본 수의 제곱근에 반비례하므로
# 필요한 수 = n x (width / $Rel)^2 로 늘리거나 줄인다. 정규분포 가정 식은 두 덩어리로 갈린 분포(위임 토큰)에서 필요한 수를 크게 낮게 잡았다.
# 표본이 10개 미만이면 흩어짐을 아직 알 수 없어 $Max 를 돌려준다. 같은 입력에는 같은 답이 나오게 난수 씨앗을 고정한다.
# cv(사분위 범위로 잰 흩어짐)는 참고용으로 함께 돌려준다.
function Get-RequiredSampleSize($Rates, [int]$Min = 30, [int]$Max = 1000, [double]$Rel = 0.15, [int]$Boot = 500) {
    $list = @($Rates | Where-Object { $null -ne $_ -and $_ -ne [DBNull]::Value } | ForEach-Object { [double]$_ })
    $n = $list.Count
    if ($n -lt 10) {
        return @{ required = [int]$Max; cv = $null; width = $null }
    }
    $sorted = [double[]]$list
    [Array]::Sort($sorted)

    $getQuantile = {
        param([double]$p)
        $idx = ($n - 1) * $p
        $k = [int][Math]::Floor($idx)
        $f = $idx - $k
        if ($k -ge $n - 1) { return [double]$sorted[$n - 1] }
        return [double]$sorted[$k] + $f * ([double]$sorted[$k + 1] - [double]$sorted[$k])
    }
    $q1 = & $getQuantile 0.25
    $med = & $getQuantile 0.5
    $q3 = & $getQuantile 0.75
    if ($med -le 0.0) {
        return @{ required = [int]$Max; cv = $null; width = $null }
    }
    $cv = ($q3 - $q1) / (1.349 * $med)

    $rng = New-Object System.Random 12345
    $buf = New-Object 'double[]' $n
    $dev = New-Object 'double[]' $Boot
    $mid = [int][Math]::Floor($n / 2)
    $odd = ($n % 2 -eq 1)
    for ($b = 0; $b -lt $Boot; $b++) {
        for ($i = 0; $i -lt $n; $i++) { $buf[$i] = $sorted[$rng.Next($n)] }
        [Array]::Sort($buf)
        $bm = if ($odd) { $buf[$mid] } else { ($buf[$mid - 1] + $buf[$mid]) / 2.0 }
        $dev[$b] = [Math]::Abs($bm - $med) / $med
    }
    [Array]::Sort($dev)
    $width = $dev[[int][Math]::Ceiling(0.95 * $Boot) - 1]

    $req = if ($width -le 0.0) { $Min } else { [int][Math]::Ceiling($n * ($width / $Rel) * ($width / $Rel)) }
    if ($req -lt $Min) { $req = $Min }
    if ($req -gt $Max) { $req = $Max }
    return @{ required = [int]$req; cv = [Math]::Round($cv, 2); width = [Math]::Round($width, 3) }
}

function Test-TokenStatsRealUser($Obj) {
    if ($null -eq $Obj) { return $false }
    if ($Obj['type'] -ne 'user') { return $false }
    if ($Obj.ContainsKey('isMeta') -and [bool]$Obj['isMeta']) { return $false }
    if ($Obj.ContainsKey('isSidechain') -and [bool]$Obj['isSidechain']) { return $false }

    $msg = if ($Obj.ContainsKey('message')) { $Obj['message'] } else { $null }
    $c = if ($msg -is [System.Collections.IDictionary] -and $msg.ContainsKey('content')) {
        $msg['content']
    } elseif ($Obj.ContainsKey('content')) {
        $Obj['content']
    } else {
        $null
    }

    if ($c -is [string]) {
        $t = $c.Trim()
        if (-not $t) { return $false }
        if ($t.StartsWith('<system-reminder') -or $t.StartsWith('<command-') -or $t.StartsWith('<local-command') -or $t.StartsWith('[SYSTEM NOTIFICATION')) { return $false }
        return $true
    }

    if ($c -is [System.Collections.IEnumerable]) {
        $texts = New-Object System.Collections.ArrayList
        foreach ($b in $c) {
            if ($b -is [System.Collections.IDictionary]) {
                if ($b.ContainsKey('type') -and [string]$b['type'] -eq 'tool_result') { return $false }
                if ($b.ContainsKey('type') -and [string]$b['type'] -eq 'text' -and $b.ContainsKey('text')) {
                    [void]$texts.Add([string]$b['text'])
                }
            }
        }
        $t = ((@($texts) -join ' ').Trim())
        if (-not $t) { return $false }
        if ($t.StartsWith('<system-reminder') -or $t.StartsWith('<command-') -or $t.StartsWith('<local-command') -or $t.StartsWith('[SYSTEM NOTIFICATION')) { return $false }
        return $true
    }

    return $false
}

# 컨텍스트가 가득 차 압축된 뒤 Claude Code 가 자동으로 붙이는 "이어서 진행" 메시지인가. 새 질문이 아니라 하던 질문의 이어짐이다.
function Test-TokenStatsContinuation($Obj) {
    if ($null -eq $Obj) { return $false }
    $msg = if ($Obj.ContainsKey('message')) { $Obj['message'] } else { $null }
    $c = if ($msg -is [System.Collections.IDictionary] -and $msg.ContainsKey('content')) { $msg['content'] } elseif ($Obj.ContainsKey('content')) { $Obj['content'] } else { $null }
    $t = ''
    if ($c -is [string]) {
        $t = $c
    } elseif ($c -is [System.Collections.IEnumerable]) {
        foreach ($b in $c) {
            if ($b -is [System.Collections.IDictionary] -and [string]$b['type'] -eq 'text' -and $b.ContainsKey('text')) { $t += ([string]$b['text'] + ' ') }
        }
    }
    return $t.TrimStart().StartsWith('This session is being continued')
}

# 사용자 프롬프트 하나 뒤에 이어진 작업(span) 도중 새 질문(queued_command)이 도착했으면, 질문마다 따로 행을 만든다.
#  - 질문의 몫 나누기: 질문마다 Claude 가 "이 질문 작업을 시작했다"고 남긴 표식(record-estimate 호출, 그 시각까지 도착한 가장 최근 질문의 것)이 있으면 그 시각부터 다음 표식 전까지가 그 질문 몫이다
#    (-Switch N 표식은 N 번째 질문 일로 돌아왔다는 뜻). 표식이 없는 질문은 도착한 시각부터가 몫이다(도착 순서). 질문 번호는 도착 순서(첫 프롬프트가 1번).
#  - 시간: 이벤트 사이 간격(300초 상한)을 간격 끝 이벤트의 주인에게 준다. 단 새 질문 도착 · 표식 직전의 간격은 그 전 주인에게 준다
#    (다른 질문 때문에 생긴 지연은 그 질문 몫으로 가지, 이 질문 시간에 더해지지 않는다). 질문별 시간을 모두 더하면 전체 시간과 같다.
#  - 토큰: 메시지마다 늘어난 컨텍스트(입력 증가분은 직전 메시지 주인, 출력은 그 메시지 주인)를 주인에게 더한다. 위임 관련 · 공통 나누기는 예전 턴과 같은 방식이다.
function Split-TurnQuestions {
    param($Turn, $FinalUsage, $BaselineCtx, [string]$FilePath, [string]$ProjectName)

    $evs = @($Turn.events)
    $qs = New-Object System.Collections.ArrayList
    $firstTs = $null
    foreach ($e0 in $evs) { if ($e0.k -eq 'start') { $firstTs = $e0.ts; break } }
    if ($null -eq $firstTs -and $evs.Count -gt 0) { $firstTs = $evs[0].ts }
    [void]$qs.Add(@{ ts = $firstTs; text = [string]$Turn.turn_ts; marked = $false })
    foreach ($e1 in $evs) {
        if ($e1.k -eq 'arrival') {
            # 행의 시각(turn_ts)은 사용자가 질문을 입력한 시각이다(Claude 에게 전달된 시각이 아니라). 몫을 나누는 기준(ts)은 전달된 시각이다.
            $inText = [string]$e1.text
            if ($e1.input) { $inText = [string]$e1.input }
            [void]$qs.Add(@{ ts = $e1.ts; text = $inText; marked = $false })
            $e1.qidx = $qs.Count - 1
        }
    }
    $nq = $qs.Count

    # 표식 -> 질문 묶기
    $entries = New-Object System.Collections.ArrayList
    foreach ($m in $evs) {
        if ($m.k -ne 'marker') { continue }
        $j = -1
        if ([int]$m.sw -ge 1 -and [int]$m.sw -le $nq) {
            $j = [int]$m.sw - 1
        } else {
            # 표식은 그 시각까지 도착한 가장 최근 질문의 작업 시작이다. 그 질문이 이미 표식을 받았으면(예상을 다시 기록한 경우) 새 표식으로 세지 않는다.
            # (질문마다 표식을 남기지 못하는 일이 많아, 가장 오래된 질문부터 짝짓지 않는다: 그러면 나중 표식이 앞선 질문에 붙는다)
            $latest = -1
            for ($qi = 0; $qi -lt $nq; $qi++) {
                $qq = $qs.Item($qi)
                if ($qq.ts -le $m.ts) { $latest = $qi }
            }
            if ($latest -ge 0) {
                $ql = $qs.Item($latest)
                if (-not $ql.marked) { $j = $latest; $ql.marked = $true }
            }
        }
        if ($j -ge 0) { [void]$entries.Add(@{ ts = $m.ts; q = $j }) }
    }
    for ($qi = 0; $qi -lt $nq; $qi++) {
        $qq = $qs.Item($qi)
        if (-not $qq.marked) { [void]$entries.Add(@{ ts = $qq.ts; q = $qi }) }
    }
    $sorted = @($entries | Sort-Object { $_.ts }, { $_.q })
    $ownerAt = {
        param($t)
        $o = 0
        foreach ($en in $sorted) { if ($en.ts -le $t) { $o = [int]$en.q } else { break } }
        return $o
    }

    # 이벤트마다 주인과 시간
    $dur = @{}; $qEnd = @{}; $cmdSub = @{}; $polls = @{}; $toolSub = @{}; $subIds = @{}; $taskIds = @{}
    for ($qi = 0; $qi -lt $nq; $qi++) { $dur[$qi] = 0.0; $cmdSub[$qi] = 0; $polls[$qi] = 0; $toolSub[$qi] = 0; $subIds[$qi] = @{}; $taskIds[$qi] = @{} }
    $msgOwner = @{}
    $prevTs = $null
    $prevOwner = 0
    foreach ($ev in $evs) {
        $own = 0
        if ($ev.k -eq 'arrival') { $own = [int]$ev.qidx } else { $own = [int](& $ownerAt $ev.ts) }
        $ev.owner = $own
        if ($null -ne $prevTs) {
            $g = ($ev.ts - $prevTs).TotalSeconds
            if ($g -gt 0) {
                if ($g -gt 300.0) { $g = 300.0 }
                $gOwn = $own
                if ($ev.k -eq 'arrival' -or $ev.k -eq 'marker') { $gOwn = $prevOwner }
                $dur[$gOwn] = [double]$dur[$gOwn] + $g
            }
        }
        $prevTs = $ev.ts
        $prevOwner = $own
        if (-not $qEnd.ContainsKey($own) -or $ev.ts -gt $qEnd[$own]) { $qEnd[$own] = $ev.ts }
        if ($ev.k -eq 'asst') {
            if ($ev.mid -and -not $msgOwner.ContainsKey([string]$ev.mid)) { $msgOwner[[string]$ev.mid] = $own }
            $cmdSub[$own] = [int]$cmdSub[$own] + [int]$ev.sub
            $polls[$own] = [int]$polls[$own] + [int]$ev.poll
        } elseif ($ev.k -eq 'result') {
            $toolSub[$own] = [int]$toolSub[$own] + [int]$ev.tsub
            foreach ($sid in @($ev.subIds)) { $subIds[$own][[string]$sid] = $true }
            foreach ($tid in @($ev.tasks)) { $taskIds[$own][[string]$tid] = $true }
        }
    }

    # 토큰: 메시지 순서대로 늘어난 컨텍스트를 주인에게
    $tot = @{}; $attrDel = @{}; $attrTot = @{}; $common = @{}; $outSum = @{}; $crSum = @{}; $calls = @{}; $callsRel = @{}; $msgCount = @{}
    for ($qi = 0; $qi -lt $nq; $qi++) { $tot[$qi] = 0.0; $attrDel[$qi] = 0.0; $attrTot[$qi] = 0.0; $common[$qi] = 0.0; $outSum[$qi] = 0; $crSum[$qi] = 0; $calls[$qi] = 0; $callsRel[$qi] = 0; $msgCount[$qi] = 0 }
    $msgIds = @($Turn.msg_ids)
    $prevTotal = $BaselineCtx
    for ($i = 0; $i -lt $msgIds.Count; $i++) {
        $mid = [string]$msgIds[$i]
        if (-not $FinalUsage.ContainsKey($mid)) { continue }
        $u = $FinalUsage[$mid]
        $own = 0
        if ($msgOwner.ContainsKey($mid)) { $own = [int]$msgOwner[$mid] }
        $inpTotal = [double]($u.inp + $u.cc + $u.cr)
        $outI = [double]$u.out
        $gIn = 0.0
        if ($null -ne $prevTotal) {
            $gIn = $inpTotal - [double]$prevTotal
            if ($gIn -lt 0) { $gIn = 0.0 }
        }
        $prevTotal = $inpTotal + $outI

        if ($i -eq 0) {
            $common[$own] = [double]$common[$own] + $gIn
            $tot[$own] = [double]$tot[$own] + $gIn
        } else {
            $prevMid = [string]$msgIds[$i - 1]
            $prevOwn = 0
            if ($msgOwner.ContainsKey($prevMid)) { $prevOwn = [int]$msgOwner[$prevMid] }
            $prevTools = $null
            if ($Turn.msg_tools.ContainsKey($prevMid)) { $prevTools = $Turn.msg_tools[$prevMid] }
            $nPrev = 0; $rPrev = 0
            if ($prevTools) { $nPrev = $prevTools.Count; foreach ($pk in $prevTools.Keys) { if ($prevTools[$pk]) { $rPrev++ } } }
            if ($nPrev -eq 0) {
                $common[$prevOwn] = [double]$common[$prevOwn] + $gIn
            } else {
                $attrDel[$prevOwn] = [double]$attrDel[$prevOwn] + ($gIn * ([double]$rPrev / [double]$nPrev))
                $attrTot[$prevOwn] = [double]$attrTot[$prevOwn] + $gIn
            }
            $tot[$prevOwn] = [double]$tot[$prevOwn] + $gIn
        }

        $curTools = $null
        if ($Turn.msg_tools.ContainsKey($mid)) { $curTools = $Turn.msg_tools[$mid] }
        $nCur = 0; $rCur = 0
        if ($curTools) { $nCur = $curTools.Count; foreach ($ck in $curTools.Keys) { if ($curTools[$ck]) { $rCur++ } } }
        if ($nCur -eq 0) {
            $common[$own] = [double]$common[$own] + $outI
        } else {
            $attrDel[$own] = [double]$attrDel[$own] + ($outI * ([double]$rCur / [double]$nCur))
            $attrTot[$own] = [double]$attrTot[$own] + $outI
        }
        $tot[$own] = [double]$tot[$own] + $outI
        $outSum[$own] = [int]$outSum[$own] + [int]$u.out
        $crSum[$own] = [int]$crSum[$own] + [int]$u.cr
        $calls[$own] = [int]$calls[$own] + $nCur
        $callsRel[$own] = [int]$callsRel[$own] + $rCur
        $msgCount[$own] = [int]$msgCount[$own] + 1
    }

    # 예전 방식(답변 끝 예상 줄)은 마지막 질문 몫으로 붙인다
    $lastQ = -1
    for ($qi = 0; $qi -lt $nq; $qi++) { if ([int]$msgCount[$qi] -gt 0) { $lastQ = $qi } }
    $joinedText = ((@($Turn.text_parts) -join "`n"))

    $rows = New-Object System.Collections.ArrayList
    for ($qi = 0; $qi -lt $nq; $qi++) {
        if ([int]$msgCount[$qi] -le 0) { continue }
        $qCalls = [int]$calls[$qi]
        $submits = [Math]::Max([int]$cmdSub[$qi], [Math]::Max([int]$toolSub[$qi], [int]$subIds[$qi].Count))
        # 위임은 도구 결과에 작업 번호(submitted · ===RESULT=== 등 뒤의 claude_...)가 찍힌 질문만이다. 명령이나 글에 submit-task 같은 말이 들어 있었을 뿐이면 직접 처리다
        $taskEvidence = [int]$subIds[$qi].Count + [int]$taskIds[$qi].Count
        $path = if ($submits -gt 0 -and $taskEvidence -gt 0) { 'delegate' } elseif ($qCalls -gt 0) { 'direct' } else { 'chat' }
        # 위임으로 보였는데 위임 도구 호출이 하나도 없으면(명령 글자에 submit-task 같은 말이 들어 있었을 뿐) 위임이 아니다
        if ($path -eq 'delegate' -and [int]$callsRel[$qi] -le 0 -and $qCalls -gt 0) { $path = 'direct' }

        $dTok = $null
        if ([double]$tot[$qi] -gt 0) { $dTok = [int][Math]::Round([double]$tot[$qi]) }
        $qRel = $qCalls
        $dRel = $dTok
        if ($path -eq 'delegate') {
            $qRel = [int]$callsRel[$qi]
            if ($null -eq $dTok -or $dTok -le 0) {
                $dRel = $null
            } elseif ($qRel -le 0) {
                $dRel = 0
            } elseif ($qRel -ge $qCalls) {
                $dRel = $dTok
            } else {
                $commonShare = 0.0
                if ([double]$attrTot[$qi] -gt 0) { $commonShare = [double]$common[$qi] * ([double]$attrDel[$qi] / [double]$attrTot[$qi]) }
                else { $commonShare = [double]$common[$qi] * ([double]$qRel / [double]$qCalls) }
                $dRel = [int][Math]::Round([double]$attrDel[$qi] + $commonShare)
                if ($dRel -lt 0) { $dRel = 0 }
                if ($dRel -gt $dTok) { $dRel = $dTok }
            }
        }

        $est = $null; $choice = $null; $level = $null; $reason = $null
        if ($qi -eq $lastQ) {
            $est = Get-TokenEstimate $joinedText
            $choice = Get-TokenTurnChoice $joinedText
            $level = Get-TokenTurnLevel $joinedText
            $reason = Get-TokenTurnReason $joinedText
        }
        $endIso = $null
        if ($qEnd.ContainsKey($qi)) { $endIso = ([DateTime]$qEnd[$qi]).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
        $durSec = [int][Math]::Round([double]$dur[$qi])

        [void]$rows.Add(@{
            file              = $FilePath
            turn_ts           = [string]($qs.Item($qi)).text
            project           = $ProjectName
            path              = $path
            calls             = [int]$qCalls
            calls_related     = [int]$qRel
            submits           = [int]$submits
            polls             = [int]$polls[$qi]
            out_tokens        = [int]$outSum[$qi]
            cr_tokens         = [int]$crSum[$qi]
            d_tokens          = $dTok
            d_related         = $(if ($null -eq $dRel) { $null } else { [int]$dRel })
            est_direct        = $(if ($est) { $est.Direct } else { $null })
            est_delegate      = $(if ($est) { $est.Delegate } else { $null })
            est_ver           = $(if ($est) { $est.Version } else { $null })
            est_time_direct   = $(if ($est) { $est.TimeDirect } else { $null })
            est_time_delegate = $(if ($est) { $est.TimeDelegate } else { $null })
            dur_sec           = $durSec
            choice            = $choice
            choice_reason     = $reason
            level             = $level
            end_ts            = $endIso
            task_ids          = @($taskIds[$qi].Keys)
        })
    }
    return @($rows)
}

function Measure-ClaudeTurnTokens {
    param(
        $TurnObj,
        $FinalUsage,
        $BaselineCtx,
        [string]$Path = 'delegate'
    )

    if ($null -eq $TurnObj -or $TurnObj.msg_ids.Count -eq 0) {
        return @{
            d_tokens      = $null
            calls         = 0
            calls_related = 0
            other_calls   = 0
            d_related     = $null
            other_tokens  = 0
            last_ctx_val  = $BaselineCtx
        }
    }

    $lastId = $TurnObj.msg_ids[$TurnObj.msg_ids.Count - 1]
    $fLast = $FinalUsage[$lastId]
    $lastCtxVal = [int64]([int64]$fLast.inp + [int64]$fLast.cc + [int64]$fLast.cr + [int64]$fLast.out)

    $dTokens = $null
    if ($null -ne $BaselineCtx) {
        $diff = $lastCtxVal - $BaselineCtx
        if ($diff -gt 0) {
            $dTokens = [int]$diff
        } else {
            # 턴 도중(메시지 사이)에 컨텍스트가 압축돼 끝 값이 시작보다 작아진 턴: 끝 - 시작은 쓸 수 없으므로 메시지마다 늘어난 만큼(줄어든 구간은 0)을 더해 어림한다.
            # 이 값이 없으면 압축을 낀 턴이 통계에서 통째로 빈 값이 된다. 첫 메시지에서 이미 시작 값보다 줄어든 경우(턴이 시작될 때 압축됨)는 그 첫 메시지의 입력을 새 시작 값으로 보고
            # 그 뒤 늘어난 만큼을 더한다(메시지가 둘 이상일 때만. 메시지 하나뿐이면 어림할 근거가 없어 예전처럼 빈 값).
            $growSum = 0.0
            $growPrev = [double]$BaselineCtx
            $midDrop = $false
            $rebased = $false
            for ($gi = 0; $gi -lt $TurnObj.msg_ids.Count; $gi++) {
                $gu = $FinalUsage[$TurnObj.msg_ids[$gi]]
                $gInTotal = [double]($gu.inp + $gu.cc + $gu.cr)
                $gStep = $gInTotal - $growPrev
                if ($gStep -lt 0) { if ($gi -gt 0) { $midDrop = $true } else { $rebased = $true }; $gStep = 0 }
                $growSum += $gStep + [double]$gu.out
                $growPrev = $gInTotal + [double]$gu.out
            }
            if (($midDrop -or ($rebased -and $TurnObj.msg_ids.Count -ge 2)) -and $growSum -gt 0) { $dTokens = [int][Math]::Round($growSum) }
        }
    }

    $calls = $TurnObj.tool_ids.Count
    $callsRelated = $calls
    $dRelated = $dTokens

    if ($Path -eq 'delegate') {
        $callsRelated = if ($TurnObj.ContainsKey('tool_related')) { $TurnObj.tool_related.Count } else { $calls }
        if ($null -eq $dTokens -or $dTokens -le 0) {
            $dRelated = $null
        } elseif ($callsRelated -le 0) {
            $dRelated = 0
        } elseif ($callsRelated -ge $calls) {
            $dRelated = $dTokens
        } else {
            $commonTokens = 0.0
            $attrDelTokens = 0.0
            $attrTotalTokens = 0.0
            $prevTotal = $BaselineCtx

            for ($i = 0; $i -lt $TurnObj.msg_ids.Count; $i++) {
                $mid = $TurnObj.msg_ids[$i]
                $u = $FinalUsage[$mid]
                $inpTotal = [double]($u.inp + $u.cc + $u.cr)
                $outI = [double]$u.out
                $gIn = $inpTotal - $prevTotal
                $prevTotal = $inpTotal + $outI
                # 컨텍스트가 압축되어 줄어든 구간(음수)은 위임 몫을 깎지 않게 0 으로 본다
                if ($gIn -lt 0) { $gIn = 0 }

                # (1) 입력 증가분: 첫 메시지는 공통(사용자 메시지·훅 안내 등), 그 뒤는 직전 메시지가 부른 도구의 몫(도구가 없었으면 공통)
                if ($i -eq 0) {
                    $commonTokens += $gIn
                } else {
                    $prevMid = $TurnObj.msg_ids[$i - 1]
                    $prevTools = if ($TurnObj.msg_tools.ContainsKey($prevMid)) { $TurnObj.msg_tools[$prevMid] } else { $null }
                    $nPrev = if ($prevTools) { $prevTools.Count } else { 0 }
                    if ($nPrev -eq 0) {
                        $commonTokens += $gIn
                    } else {
                        $rPrev = 0
                        foreach ($tId in $prevTools.Keys) {
                            if ($prevTools[$tId]) { $rPrev++ }
                        }
                        $ratio = [double]$rPrev / [double]$nPrev
                        $attrDelTokens += ($gIn * $ratio)
                        $attrTotalTokens += $gIn
                    }
                }

                # (2) 출력: 이 메시지가 부른 도구의 몫(위임 제출을 쓴 브리프는 위임 비용). 도구가 없는 메시지(최종 답변 등)는 공통
                $curTools = if ($TurnObj.msg_tools.ContainsKey($mid)) { $TurnObj.msg_tools[$mid] } else { $null }
                $nCur = if ($curTools) { $curTools.Count } else { 0 }
                if ($nCur -eq 0) {
                    $commonTokens += $outI
                } else {
                    $rCur = 0
                    foreach ($tId in $curTools.Keys) {
                        if ($curTools[$tId]) { $rCur++ }
                    }
                    $attrDelTokens += ($outI * ([double]$rCur / [double]$nCur))
                    $attrTotalTokens += $outI
                }
            }

            $commonDelShare = 0.0
            if ($attrTotalTokens -gt 0) {
                $commonDelShare = $commonTokens * ($attrDelTokens / $attrTotalTokens)
            } else {
                $commonDelShare = $commonTokens * ([double]$callsRelated / [double]$calls)
            }

            $dRelatedRaw = $attrDelTokens + $commonDelShare
            $dRelated = [int][Math]::Round($dRelatedRaw)
            if ($dRelated -lt 0) { $dRelated = 0 }
            if ($dRelated -gt $dTokens) { $dRelated = $dTokens }
        }
    }

    $otherCalls = [Math]::Max(0, [int]$calls - [int]$callsRelated)
    $otherTokens = 0
    if ($null -ne $dTokens -and $null -ne $dRelated -and $dTokens -gt $dRelated) {
        $otherTokens = [int]($dTokens - $dRelated)
    }

    return @{
        d_tokens      = $dTokens
        calls         = [int]$calls
        calls_related = [int]$callsRelated
        other_calls   = [int]$otherCalls
        d_related     = $(if ($null -eq $dRelated) { $null } else { [int]$dRelated })
        other_tokens  = [int]$otherTokens
        last_ctx_val  = $lastCtxVal
    }
}
function Get-TokenTurnsFromSessionFile([string]$FilePath, [string]$ProjectName, [long]$StartOffset = 0, $StartLastCtx = $null) {
    $turns = New-Object System.Collections.ArrayList
    $newOffset = $StartOffset
    $lastCtx = $StartLastCtx

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return @{ NewOffset = $StartOffset; LastCtx = $StartLastCtx; Turns = @() }
    }

    $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fileLen = $fs.Length
        if ($fileLen -lt $StartOffset) {
            $StartOffset = 0L
            $StartLastCtx = $null
            $lastCtx = $null
        }
        if ($fileLen -eq $StartOffset) {
            return @{ NewOffset = $StartOffset; LastCtx = $StartLastCtx; Turns = @() }
        }

        $fs.Seek($StartOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $bytesToRead = [int]($fileLen - $StartOffset)
        $buffer = New-Object byte[] $bytesToRead
        $readCount = $fs.Read($buffer, 0, $bytesToRead)
        if ($readCount -le 0) {
            return @{ NewOffset = $StartOffset; LastCtx = $StartLastCtx; Turns = @() }
        }

        $lastNl = -1
        for ($i = $readCount - 1; $i -ge 0; $i--) {
            if ($buffer[$i] -eq 10) {
                $lastNl = $i
                break
            }
        }
        if ($lastNl -lt 0) {
            return @{ NewOffset = $StartOffset; LastCtx = $StartLastCtx; Turns = @() }
        }

        $validByteLen = $lastNl + 1
        $newOffset = $StartOffset + $validByteLen
        $textChunk = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $validByteLen)
    } finally {
        $fs.Dispose()
    }

    Add-Type -AssemblyName System.Web.Extensions
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue

    $finalUsage = @{}
    $enqueues = New-Object System.Collections.ArrayList
    $currentTurn = $null
    $script:tokenScanPrevCtx = $StartLastCtx
    $script:tokenScanLastCtx = $StartLastCtx
    # 진행 중인(아직 다음 사용자 프롬프트가 없는) 마지막 턴의 시작 위치와 그 턴 직전의 컨텍스트.
    # 다음 갱신이 이 턴을 처음부터 다시 읽어 이어 붙은 호출·작업 번호를 잃지 않게 하려고 기억한다.
    $nextByte = 0
    $openStartOffset = $null
    $openBaseCtx = $null

    $completeTurn = {
        param($tObj)
        if ($null -eq $tObj -or $tObj.msg_ids.Count -eq 0) { return }
        $arrivalCount = 0
        foreach ($evx in $tObj.events) { if ($evx.k -eq 'arrival') { $arrivalCount++ } }
        if ($arrivalCount -gt 0) {
            # 작업 도중 새 질문이 도착했다: 질문마다 한 행(몫 나누기는 Split-TurnQuestions)
            $qRows = @(Split-TurnQuestions -Turn $tObj -FinalUsage $finalUsage -BaselineCtx $script:tokenScanPrevCtx -FilePath $FilePath -ProjectName $ProjectName)
            $lastIdQ = $tObj.msg_ids[$tObj.msg_ids.Count - 1]
            $fLastQ = $finalUsage[$lastIdQ]
            $lastCtxQ = [int64]([int64]$fLastQ.inp + [int64]$fLastQ.cc + [int64]$fLastQ.cr + [int64]$fLastQ.out)
            $script:tokenScanPrevCtx = $lastCtxQ
            $script:tokenScanLastCtx = $lastCtxQ
            foreach ($qr in $qRows) { [void]$turns.Add($qr) }
            return
        }
        $lastId = $tObj.msg_ids[$tObj.msg_ids.Count - 1]
        $calls = $tObj.tool_ids.Count
        $toolResultSubmits = [Math]::Max([int]$tObj.tool_submits, [int]$tObj.submitted_task_ids.Count)
        $submits = [Math]::Max([int]$tObj.cmd_submits, [int]$toolResultSubmits)
        $polls = [int]$tObj.cmd_polls

        # 위임은 도구 결과에 작업 번호가 찍힌 질문만이다(명령이나 글에 submit-task 같은 말이 들어 있었을 뿐이면 직접 처리)
        $taskEvidence = [int]$tObj.submitted_task_ids.Count + [int]$tObj.task_ids.Count
        $path = if ($submits -gt 0 -and $taskEvidence -gt 0) { 'delegate' } elseif ($calls -gt 0) { 'direct' } else { 'chat' }

        $measured = Measure-ClaudeTurnTokens -TurnObj $tObj -FinalUsage $finalUsage -BaselineCtx $script:tokenScanPrevCtx -Path $path
        $lastCtxVal = $measured.last_ctx_val
        $dTokens = $measured.d_tokens
        $callsRelated = $measured.calls_related
        $dRelated = $measured.d_related

        $script:tokenScanPrevCtx = $lastCtxVal
        $script:tokenScanLastCtx = $lastCtxVal

        $outSum = 0
        $crSum = 0
        foreach ($mid in $tObj.msg_ids) {
            $outSum += $finalUsage[$mid].out
            $crSum += $finalUsage[$mid].cr
        }

        $durSec = $null
        if ($tObj.event_times.Count -ge 2) {
            $sortedTimes = @($tObj.event_times | Sort-Object)
            $totalDur = 0.0
            for ($k = 0; $k -lt $sortedTimes.Count - 1; $k++) {
                $gap = ($sortedTimes[$k + 1] - $sortedTimes[$k]).TotalSeconds
                if ($gap -gt 0) {
                    if ($gap -gt 300.0) { $gap = 300.0 }
                    $totalDur += $gap
                }
            }
            $durSec = [int][Math]::Round($totalDur)
        }

        
        $joinedText = ((@($tObj.text_parts) -join "`n"))
        $est = Get-TokenEstimate $joinedText
        $estDirect = if ($est) { $est.Direct } else { $null }
        $estDelegate = if ($est) { $est.Delegate } else { $null }
        $estVer = if ($est) { $est.Version } else { $null }
        $estTimeDirect = if ($est) { $est.TimeDirect } else { $null }
        $estTimeDelegate = if ($est) { $est.TimeDelegate } else { $null }
        $choice = Get-TokenTurnChoice $joinedText
        $level = Get-TokenTurnLevel $joinedText

        $turnRow = @{
            file              = $FilePath
            turn_ts           = $tObj.turn_ts
            project           = $ProjectName
            path              = $path
            calls             = [int]$calls
            calls_related     = [int]$callsRelated
            submits           = [int]$submits
            polls             = [int]$polls
            out_tokens        = [int]$outSum
            cr_tokens         = [int]$crSum
            d_tokens          = $dTokens
            d_related         = $(if ($null -eq $dRelated) { $null } else { [int]$dRelated })
            est_direct        = $estDirect
            est_delegate      = $estDelegate
            est_ver           = $estVer
            est_time_direct   = $estTimeDirect
            est_time_delegate = $estTimeDelegate
            dur_sec           = $durSec
            choice            = $choice
            choice_reason     = (Get-TokenTurnReason $joinedText)
            level             = $level
            end_ts            = $(if ($tObj.event_times.Count -gt 0) { (@($tObj.event_times | ForEach-Object { $_.ToUniversalTime() }) | Sort-Object | Select-Object -Last 1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null })
            task_ids          = if ($tObj.ContainsKey('task_ids') -and $null -ne $tObj.task_ids) { @($tObj.task_ids.Keys) } else { @() }
        }
        [void]$turns.Add($turnRow)
    }

    $sr = New-Object System.IO.StringReader($textChunk)
    try {
        while (($line = $sr.ReadLine()) -ne $null) {
            # 이 줄이 파일에서 시작하는 바이트 위치(줄은 \n 으로 끝난다)
            $lineStartByte = [long]$StartOffset + $nextByte
            $nlIdx = [Array]::IndexOf($buffer, [byte]10, $nextByte, $validByteLen - $nextByte)
            $nextByte = if ($nlIdx -ge 0) { $nlIdx + 1 } else { $validByteLen }
                        $line = $line.Trim().TrimStart([char]0xFEFF)
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '"isSidechain"\s*:\s*true|"isMeta"\s*:\s*true') { continue }

            # 사용자가 메시지를 입력해 대기열에 넣은 시각(enqueue). 작업 도중 보낸 질문은 Claude 에게 전달되기(attachment) 전에 먼저 여기에 남는다.
            if ($line.Contains('"queue-operation"') -and $line -match '"operation"\s*:\s*"enqueue"') {
                if ($line -match '"timestamp"\s*:\s*"([^"]+)"') {
                    $enqTs = $Matches[1]
                    $enqContent = ""
                    if ($line -match '"content"\s*:\s*"((?:[^"\\]|\\.)*)"') { $enqContent = $Matches[1] }
                    [void]$enqueues.Add(@{ ts = $enqTs; content = $enqContent })
                }
                continue
            }

            # 작업 도중 사용자가 보낸 새 질문(대기열에서 Claude 에게 전달된 메시지): 이 시각부터 새 질문이 시작한다
            if ($null -ne $currentTurn -and $line.Contains('"queued_command"') -and $line -match '"type"\s*:\s*"attachment"' -and $line -match '"origin"\s*:\s*\{\s*"kind"\s*:\s*"human"') {
                $aTsText = ""
                if ($line -match '"timestamp"\s*:\s*"([^"]+)"') { $aTsText = $Matches[1] }
                # 질문을 입력한 시각: 같은 내용의 enqueue 기록이 있으면 그 시각(없으면 전달된 시각)
                $aPrompt = ""
                if ($line -match '"prompt"\s*:\s*"((?:[^"\\]|\\.)*)"') { $aPrompt = $Matches[1] }
                $aInput = $aTsText
                if ($aPrompt) {
                    for ($ei = 0; $ei -lt $enqueues.Count; $ei++) {
                        $enq = $enqueues.Item($ei)
                        if ([string]$enq.content -eq $aPrompt -and [string]$enq.ts -le $aTsText) { $aInput = [string]$enq.ts; $enqueues.RemoveAt($ei); break }
                    }
                }
                if ($aTsText) {
                    try {
                        $aTs = [DateTime]::Parse($aTsText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                        [void]$currentTurn.event_times.Add($aTs)
                        [void]$currentTurn.events.Add(@{ k = 'arrival'; ts = $aTs; text = $aTsText; input = $aInput; qidx = 0 })
                    } catch {}
                }
                continue
            }

            if ($line -match '"type"\s*:\s*"user"') {
                if ($line.Contains('"tool_result"')) {
                    $tsObj = $null
                    $evTasksR = @(); $evSubR = @(); $evTsubR = 0
                    if ($null -ne $currentTurn -and $line -match '"timestamp"\s*:\s*"([^"]+)"') {
                        try {
                            $tsObj = [DateTime]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                            [void]$currentTurn.event_times.Add($tsObj)
                        } catch {}
                    }
                    if ($null -ne $currentTurn -and $line -match '(?:===RESULT===|===PENDING===|===ERROR===)') {
                        $currentTurn.review_allowance = 3
                    }
                    if ($null -ne $currentTurn -and $line -match $script:TaskMarkPattern) {
                        $taskMatches = [regex]::Matches($line, $script:TaskMarkPattern)
                        foreach ($tm in $taskMatches) {
                            $tid = $tm.Groups[1].Value
                            if ($tid) {
                                $currentTurn.task_ids[$tid] = $true
                                $evTasksR += $tid
                            }
                        }
                    }
                    if ($null -ne $currentTurn -and $line -match '(?i)\bsubmitted[: ]') {
                        $subMatches = [regex]::Matches($line, $script:TaskSubmittedPattern)
                        if ($subMatches.Count -gt 0) {
                            foreach ($sm in $subMatches) {
                                $currentTurn.submitted_task_ids[$sm.Groups[1].Value] = $true
                                $evSubR += $sm.Groups[1].Value
                            }
                        } else {
                            $currentTurn.tool_submits++
                            $evTsubR++
                        }
                    }
                    if ($null -ne $currentTurn -and $null -ne $tsObj) {
                        [void]$currentTurn.events.Add(@{ k = 'result'; ts = $tsObj; tasks = $evTasksR; subIds = $evSubR; tsub = $evTsubR })
                    }
                    continue
                }
                try {
                    $uObj = $js.DeserializeObject($line)
                } catch {
                    continue
                }
                if (Test-TokenStatsRealUser $uObj) {
                    if ($null -ne $currentTurn -and (Test-TokenStatsContinuation $uObj)) {
                        # 컨텍스트 압축 뒤 자동으로 붙는 "이어서 진행" 메시지: 새 질문이 아니라 하던 질문의 이어짐이라 같은 작업으로 본다
                        if ($uObj.ContainsKey('timestamp')) {
                            try { [void]$currentTurn.event_times.Add([DateTime]::Parse([string]$uObj['timestamp'], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)) } catch {}
                        }
                        continue
                    }
                    if ($null -ne $currentTurn) {
                        & $completeTurn $currentTurn
                    }
                    $openStartOffset = $lineStartByte
                    $openBaseCtx = $script:tokenScanPrevCtx
                    $uTs = if ($uObj.ContainsKey('timestamp')) { [string]$uObj['timestamp'] } else { "" }
                    $currentTurn = @{
                        turn_ts            = $uTs
                        msg_ids            = New-Object System.Collections.ArrayList
                        tool_ids           = @{}
                        tool_related       = @{}
                        seen_tools         = @{}
                        msg_tools          = @{}
                        review_allowance   = 0
                        cmd_submits        = 0
                        cmd_polls          = 0
                        tool_submits       = 0
                        submitted_task_ids = @{}
                        text_parts         = New-Object System.Collections.ArrayList
                        task_ids           = @{}
                        event_times        = New-Object System.Collections.ArrayList
                        events             = New-Object System.Collections.ArrayList
                    }
                    if ($uTs) {
                        try {
                            $parsedUTs = [DateTime]::Parse($uTs, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                            [void]$currentTurn.event_times.Add($parsedUTs)
                            [void]$currentTurn.events.Add(@{ k = 'start'; ts = $parsedUTs })
                        } catch {}
                    }
                }
            } elseif ($line -match '"type"\s*:\s*"assistant"') {
                if ($null -eq $currentTurn) { continue }
                $tsObj = $null
                $lineMid = ""
                $subBefore = [int]$currentTurn.cmd_submits
                $pollBefore = [int]$currentTurn.cmd_polls
                if ($line -match '"timestamp"\s*:\s*"([^"]+)"') {
                    try {
                        $tsObj = [DateTime]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                        [void]$currentTurn.event_times.Add($tsObj)
                    } catch {}
                }
                # 질문 작업 표식: record-estimate 호출(-Switch N 은 N 번째 질문 일로 돌아왔다는 표시)
                if ($null -ne $tsObj -and $line -match '"id"\s*:\s*"toolu_' -and $line -match $script:RecordEstimateCallPattern) {
                    $mkSwitch = 0
                    if ($line -match '-Switch\s+(\d+)') { $mkSwitch = [int]$Matches[1] }
                    [void]$currentTurn.events.Add(@{ k = 'marker'; ts = $tsObj; sw = $mkSwitch })
                }
                if ($line -match '"id"\s*:\s*"(msg_[A-Za-z0-9_-]+)"') {
                    $mid = $Matches[1]
                    $lineMid = $mid
                    if (-not $finalUsage.ContainsKey($mid)) {
                        $finalUsage[$mid] = @{ inp = 0; cc = 0; cr = 0; out = 0 }
                    }
                    $uRec = $finalUsage[$mid]
                    if ($line -match '"input_tokens"\s*:\s*(\d+)') {
                        $v = [int]$Matches[1]; if ($v -gt $uRec.inp) { $uRec.inp = $v }
                    }
                    if ($line -match '"cache_creation_input_tokens"\s*:\s*(\d+)') {
                        $v = [int]$Matches[1]; if ($v -gt $uRec.cc) { $uRec.cc = $v }
                    }
                    if ($line -match '"cache_read_input_tokens"\s*:\s*(\d+)') {
                        $v = [int]$Matches[1]; if ($v -gt $uRec.cr) { $uRec.cr = $v }
                    }
                    if ($line -match '"output_tokens"\s*:\s*(\d+)') {
                        $v = [int]$Matches[1]; if ($v -gt $uRec.out) { $uRec.out = $v }
                    }
                    if (-not $currentTurn.msg_ids.Contains($mid)) {
                        [void]$currentTurn.msg_ids.Add($mid)
                    }
                }

                if ($line -match '"id"\s*:\s*"(toolu_[A-Za-z0-9_-]+)"' -and -not (Test-RecordEstimateOnlyLine $line)) {
                    $toolMatches = [regex]::Matches($line, '"id"\s*:\s*"(toolu_[A-Za-z0-9_-]+)"')
                    foreach ($tm in $toolMatches) {
                        $tid = $tm.Groups[1].Value
                        $currentTurn.tool_ids[$tid] = $true
                    }

                    $curMid = if ($line -match '"id"\s*:\s*"(msg_[A-Za-z0-9_-]+)"') { $Matches[1] } else { "" }

                    $aObj = $null
                    try { $aObj = $js.DeserializeObject($line) } catch {}
                    if ($null -ne $aObj -and $aObj.ContainsKey('message') -and $aObj['message'] -is [System.Collections.IDictionary]) {
                        $mObj = $aObj['message']
                        if (-not $curMid -and $mObj.ContainsKey('id')) { $curMid = [string]$mObj['id'] }
                        $cObj = if ($mObj.ContainsKey('content')) { $mObj['content'] } else { $null }
                        if ($cObj -is [System.Collections.IEnumerable]) {
                            foreach ($blk in $cObj) {
                                if ($blk -is [System.Collections.IDictionary] -and [string]$blk['type'] -eq 'tool_use') {
                                    $tId = [string]$blk['id']
                                    $tName = [string]$blk['name']
                                    $tInput = $blk['input']

                                    if (-not $currentTurn.seen_tools.ContainsKey($tId)) {
                                        $currentTurn.seen_tools[$tId] = $true
                                        $isDelCmd = Test-IsDelegationToolCall $tName $tInput
                                        $isRel = $false
                                        if ($isDelCmd) {
                                            $isRel = $true
                                        } elseif ($currentTurn.review_allowance -gt 0) {
                                            $isRel = $true
                                            $currentTurn.review_allowance--
                                        }
                                        if ($isRel) {
                                            $currentTurn.tool_related[$tId] = $true
                                        }
                                        if ($curMid) {
                                            if (-not $currentTurn.msg_tools.ContainsKey($curMid)) {
                                                $currentTurn.msg_tools[$curMid] = @{}
                                            }
                                            $currentTurn.msg_tools[$curMid][$tId] = $isRel
                                        }
                                    }
                                }
                            }
                        }
                    }

                    foreach ($tm in $toolMatches) {
                        $tId = $tm.Groups[1].Value
                        if (-not $currentTurn.seen_tools.ContainsKey($tId)) {
                            $currentTurn.seen_tools[$tId] = $true
                            $isDelCmd = Test-IsDelegationToolCall "" $line
                            $isRel = $false
                            if ($isDelCmd) {
                                $isRel = $true
                            } elseif ($currentTurn.review_allowance -gt 0) {
                                $isRel = $true
                                $currentTurn.review_allowance--
                            }
                            if ($isRel) {
                                $currentTurn.tool_related[$tId] = $true
                            }
                            if ($curMid) {
                                if (-not $currentTurn.msg_tools.ContainsKey($curMid)) {
                                    $currentTurn.msg_tools[$curMid] = @{}
                                }
                                $currentTurn.msg_tools[$curMid][$tId] = $isRel
                            }
                        }
                    }

                    $isSubmitName = ($line -match '(?i)submit-task(?:\.ps1)?')
                    $isVarSubmit = ($line -match '(?i)\$[a-z0-9_]+' -and $line -match '(?i)-NoWait')
                    $isInboxHeredoc = ($line -match '(?i)inbox/.*<<')
                    $isSubmitLike = ($isSubmitName -or $isVarSubmit -or $isInboxHeredoc)

                    $hasPoll = ($line -match '(?i)-Poll')
                    if ($hasPoll) {
                        $pollCount = [regex]::Matches($line, '(?i)-Poll').Count
                        $currentTurn.cmd_polls += $pollCount
                    }

                    $hasNoWait = ($line -match '(?i)-NoWait')
                    $hasHeredoc = ($line -match '<<')
                    if ($isSubmitLike) {
                        if (-not $hasPoll -or $hasNoWait -or $hasHeredoc) {
                            $noWaitCount = [regex]::Matches($line, '(?i)-NoWait').Count
                            $heredocCount = [regex]::Matches($line, '<<').Count
                            $numSubmits = [Math]::Max($noWaitCount, $heredocCount)
                            if ($numSubmits -eq 0) { $numSubmits = 1 }
                            $currentTurn.cmd_submits += $numSubmits
                        }
                    }
                }

                if ($null -ne $tsObj) {
                    [void]$currentTurn.events.Add(@{ k = 'asst'; ts = $tsObj; mid = $lineMid; sub = ([int]$currentTurn.cmd_submits - $subBefore); poll = ([int]$currentTurn.cmd_polls - $pollBefore) })
                }

                if ($line -match '예상\s*(?:토큰|시간)|토큰\s*직접|직접\s*\*\*|\[Agy 위임') {
                    # 답변 글(text 블록)만 모은다: 같은 줄의 도구 입력(tool_use)에 든 예시 꼬리 줄 · 예상 줄은 사유 · 예상으로 읽지 않는다
                    $textOnly = Get-AssistantTextBlocks $line
                    if ($textOnly) { [void]$currentTurn.text_parts.Add($textOnly) }
                }
            }
        }
        if ($null -ne $currentTurn) {
            & $completeTurn $currentTurn
        }
    } finally {
        $sr.Dispose()
    }

    # 마지막 턴은 아직 끝나지 않았을 수 있다(사용자의 다음 프롬프트가 아직 없다). 지금까지 읽은 만큼을 한 행으로 남기되,
    # 다음 갱신은 그 턴의 시작부터 다시 읽는다: 파일 끝부터 이어 읽으면 그 턴에 나중에 붙는 호출·작업 번호를 모두 버리게 된다.
    # 같은 (파일, 턴 시각) 행은 다음 갱신에서 덮어쓰므로 중복되지 않는다.
    $retOffset = $newOffset
    $retCtx = $script:tokenScanLastCtx
    if ($null -ne $currentTurn -and $null -ne $openStartOffset) {
        $retOffset = $openStartOffset
        $retCtx = $openBaseCtx
    }

    return @{
        NewOffset = $retOffset
        LastCtx   = $retCtx
        Turns     = @($turns)
    }
}

function Get-ClaudeLiveTurnMetrics {
    param(
        $Lines,
        $BaselineCtx = $null
    )

    Add-Type -AssemblyName System.Web.Extensions
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue

    $currentTurn = @{
        turn_ts            = ""
        msg_ids            = New-Object System.Collections.ArrayList
        tool_ids           = @{}
        tool_related       = @{}
        seen_tools         = @{}
        msg_tools          = @{}
        review_allowance   = 0
        cmd_submits        = 0
        cmd_polls          = 0
        tool_submits       = 0
        submitted_task_ids = @{}
        text_parts         = New-Object System.Collections.ArrayList
        task_ids           = @{}
        event_times        = New-Object System.Collections.ArrayList
    }
    $finalUsage = @{}

    foreach ($rawLine in $Lines) {
        if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
        $line = $rawLine.Trim().TrimStart([char]0xFEFF)
        if ($line -match '"isSidechain"\s*:\s*true|"isMeta"\s*:\s*true') { continue }

        if ($line -match '"type"\s*:\s*"user"') {
            if ($line.Contains('"tool_result"')) {
                if ($line -match '"timestamp"\s*:\s*"([^"]+)"') {
                    try {
                        $tsObj = [DateTime]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                        [void]$currentTurn.event_times.Add($tsObj)
                    } catch {}
                }
                if ($line -match '(?:===RESULT===|===PENDING===|===ERROR===)') {
                    $currentTurn.review_allowance = 3
                }
                if ($line -match $script:TaskMarkPattern) {
                    $taskMatches = [regex]::Matches($line, $script:TaskMarkPattern)
                    foreach ($tm in $taskMatches) {
                        $tid = $tm.Groups[1].Value
                        if ($tid) {
                            $currentTurn.task_ids[$tid] = $true
                        }
                    }
                }
                if ($line -match '(?i)\bsubmitted[: ]') {
                    $subMatches = [regex]::Matches($line, $script:TaskSubmittedPattern)
                    if ($subMatches.Count -gt 0) {
                        foreach ($sm in $subMatches) {
                            $currentTurn.submitted_task_ids[$sm.Groups[1].Value] = $true
                        }
                    } else {
                        $currentTurn.tool_submits++
                    }
                }
                continue
            }
            try {
                $uObj = $js.DeserializeObject($line)
            } catch {
                continue
            }
            if (Test-TokenStatsRealUser $uObj) {
                if (-not $currentTurn.turn_ts) {
                    $uTs = if ($uObj.ContainsKey('timestamp')) { [string]$uObj['timestamp'] } else { "" }
                    $currentTurn.turn_ts = $uTs
                    if ($uTs) {
                        try {
                            $parsedUTs = [DateTime]::Parse($uTs, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                            [void]$currentTurn.event_times.Add($parsedUTs)
                        } catch {}
                    }
                } else {
                    break
                }
            }
        } elseif ($line -match '"type"\s*:\s*"assistant"') {
            if ($line -match '"timestamp"\s*:\s*"([^"]+)"') {
                try {
                    $tsObj = [DateTime]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                    [void]$currentTurn.event_times.Add($tsObj)
                } catch {}
            }
            if ($line -match '"id"\s*:\s*"(msg_[A-Za-z0-9_-]+)"') {
                $mid = $Matches[1]
                if (-not $finalUsage.ContainsKey($mid)) {
                    $finalUsage[$mid] = @{ inp = 0; cc = 0; cr = 0; out = 0 }
                }
                $uRec = $finalUsage[$mid]
                if ($line -match '"input_tokens"\s*:\s*(\d+)') {
                    $v = [int]$Matches[1]; if ($v -gt $uRec.inp) { $uRec.inp = $v }
                }
                if ($line -match '"cache_creation_input_tokens"\s*:\s*(\d+)') {
                    $v = [int]$Matches[1]; if ($v -gt $uRec.cc) { $uRec.cc = $v }
                }
                if ($line -match '"cache_read_input_tokens"\s*:\s*(\d+)') {
                    $v = [int]$Matches[1]; if ($v -gt $uRec.cr) { $uRec.cr = $v }
                }
                if ($line -match '"output_tokens"\s*:\s*(\d+)') {
                    $v = [int]$Matches[1]; if ($v -gt $uRec.out) { $uRec.out = $v }
                }
                if (-not $currentTurn.msg_ids.Contains($mid)) {
                    [void]$currentTurn.msg_ids.Add($mid)
                }
            }

            if ($line -match '"id"\s*:\s*"(toolu_[A-Za-z0-9_-]+)"' -and -not (Test-RecordEstimateOnlyLine $line)) {
                $toolMatches = [regex]::Matches($line, '"id"\s*:\s*"(toolu_[A-Za-z0-9_-]+)"')
                foreach ($tm in $toolMatches) {
                    $tid = $tm.Groups[1].Value
                    $currentTurn.tool_ids[$tid] = $true
                }

                $curMid = if ($line -match '"id"\s*:\s*"(msg_[A-Za-z0-9_-]+)"') { $Matches[1] } else { "" }

                $aObj = $null
                try { $aObj = $js.DeserializeObject($line) } catch {}
                if ($null -ne $aObj -and $aObj.ContainsKey('message') -and $aObj['message'] -is [System.Collections.IDictionary]) {
                    $mObj = $aObj['message']
                    if (-not $curMid -and $mObj.ContainsKey('id')) { $curMid = [string]$mObj['id'] }
                    $cObj = if ($mObj.ContainsKey('content')) { $mObj['content'] } else { $null }
                    if ($cObj -is [System.Collections.IEnumerable]) {
                        foreach ($blk in $cObj) {
                            if ($blk -is [System.Collections.IDictionary] -and [string]$blk['type'] -eq 'tool_use') {
                                $tId = [string]$blk['id']
                                $tName = [string]$blk['name']
                                $tInput = $blk['input']

                                if (-not $currentTurn.seen_tools.ContainsKey($tId)) {
                                    $currentTurn.seen_tools[$tId] = $true
                                    $isDelCmd = Test-IsDelegationToolCall $tName $tInput
                                    $isRel = $false
                                    if ($isDelCmd) {
                                        $isRel = $true
                                    } elseif ($currentTurn.review_allowance -gt 0) {
                                        $isRel = $true
                                        $currentTurn.review_allowance--
                                    }
                                    if ($isRel) {
                                        $currentTurn.tool_related[$tId] = $true
                                    }
                                    if ($curMid) {
                                        if (-not $currentTurn.msg_tools.ContainsKey($curMid)) {
                                            $currentTurn.msg_tools[$curMid] = @{}
                                        }
                                        $currentTurn.msg_tools[$curMid][$tId] = $isRel
                                    }
                                }
                            }
                        }
                    }
                }

                foreach ($tm in $toolMatches) {
                    $tId = $tm.Groups[1].Value
                    if (-not $currentTurn.seen_tools.ContainsKey($tId)) {
                        $currentTurn.seen_tools[$tId] = $true
                        $isDelCmd = Test-IsDelegationToolCall "" $line
                        $isRel = $false
                        if ($isDelCmd) {
                            $isRel = $true
                        } elseif ($currentTurn.review_allowance -gt 0) {
                            $isRel = $true
                            $currentTurn.review_allowance--
                        }
                        if ($isRel) {
                            $currentTurn.tool_related[$tId] = $true
                        }
                        if ($curMid) {
                            if (-not $currentTurn.msg_tools.ContainsKey($curMid)) {
                                $currentTurn.msg_tools[$curMid] = @{}
                            }
                            $currentTurn.msg_tools[$curMid][$tId] = $isRel
                        }
                    }
                }
            }

            if ($line -match '예상\s*(?:토큰|시간)|토큰\s*직접|직접\s*\*\*|\[Agy 위임') {
                # 답변 글(text 블록)만 모은다(도구 입력에 든 예시 글은 뺀다)
                $textOnly = Get-AssistantTextBlocks $line
                if ($textOnly) { [void]$currentTurn.text_parts.Add($textOnly) }
            }
        }
    }

    if ($currentTurn.msg_ids.Count -eq 0) {
        return $null
    }

    $measured = Measure-ClaudeTurnTokens -TurnObj $currentTurn -FinalUsage $finalUsage -BaselineCtx $BaselineCtx -Path 'delegate'

    $joinedText = ((@($currentTurn.text_parts) -join "`n"))
    $est = Get-TokenEstimate $joinedText
    $estDelegate = if ($est) { $est.Delegate } else { $null }

    return [ordered]@{
        used          = $(if ($null -eq $measured.d_related) { $null } else { [int]$measured.d_related })
        calls_related = [int]$measured.calls_related
        other_calls   = [int]$measured.other_calls
        other_tokens  = [int]$measured.other_tokens
        d_tokens      = $(if ($null -eq $measured.d_tokens) { $null } else { [int]$measured.d_tokens })
        est_delegate  = $(if ($null -eq $estDelegate) { $null } else { [int]$estDelegate })
        turn_ts       = [string]$currentTurn.turn_ts
    }
}

# 이상치: 같은 경로의 최근 턴들과 비교해 실제/예상 비율이 크게 벗어난 턴(로그 기준 3 MAD) 또는 예상과 $AbsFactor 배 넘게 다른 턴.
# 둘째 기준은 예상들이 모두 크게 틀려 흩어짐이 넓을 때(기준선도 함께 넓어져 아무것도 안 잡힘)를 위한 안전장치다.
# 위임 턴의 예상은 턴 전체를 잰 값이라, 뷰어 카드와 같은 방식으로 다른 작업 실측(d_tokens - d_related)을 빼서 위임한 일만의 예상과 비교한다
# (빼고 나서 0 이하이면 위임 관련 호출 비율을 곱한다).
# 위임한 질문의 예상(est_delegate)은 질문을 받을 때 기록한 값 그대로 쓴다(화면 · 통계 API 와 같은 기준). 예전에는 그 질문의 위임 무관 작업 실측을 빼
# "위임한 일만의 예상"으로 줄였는데, 그러면 화면에 보이는 값과 보정 계수의 기준이 달라져 계수가 부풀었다. 이상치 판정 · 예상 정확도 · 보정 비율이 모두 이 함수를 쓴다.
# serve-viewer.ps1 의 Get-ViewerDelegateJobEstimate 가 같은 식이다(뷰어는 이 파일을 불러오지 않아 따로 둔다). 고치면 함께 고친다.
function Get-TokenDelegateJobEstimate([double]$Est, $DTokens, $DRelated, $Calls, $CallsRelated) {
    return $Est
}
function Get-TokenAnomalyFlags($Rows, [hashtable]$AgyMedians = @{}, [hashtable]$TaskInfo = @{}, [double]$AbsFactor = 5.0) {
    $result = @{}
    $allRows = @($Rows)
    if ($allRows.Count -eq 0) { return $result }

    function _GetVal($obj, [string]$prop) {
        if ($null -eq $obj) { return $null }
        $v = $null
        if ($obj -is [System.Collections.IDictionary] -or $obj -is [System.Collections.Generic.IDictionary[string,object]]) {
            try { $v = $obj[$prop] } catch { $v = $obj.$prop }
        } else {
            $v = $obj.$prop
        }
        if ($v -eq [DBNull]::Value) { return $null }
        return $v
    }

    $pathGroups = @{
        direct   = New-Object System.Collections.ArrayList
        delegate = New-Object System.Collections.ArrayList
    }

    foreach ($r in $allRows) {
        $p = _GetVal $r 'path'
        if ($p -ne 'direct' -and $p -ne 'delegate') { continue }
        $ver = [string](_GetVal $r 'est_ver')
        if ($ver -ne 'v2') { continue }

        $actual = $null
        $est = $null
        if ($p -eq 'direct') {
            $dTok = _GetVal $r 'd_tokens'
            $estDir = _GetVal $r 'est_direct'
            if ($null -ne $dTok -and $null -ne $estDir) {
                $actual = [double]$dTok
                $est = [double]$estDir
            }
        } else {
            $dRel = _GetVal $r 'd_related'
            $dTok = _GetVal $r 'd_tokens'
            $effD = if ($null -ne $dRel -and [string]$dRel -ne '') { [double]$dRel } elseif ($null -ne $dTok -and [string]$dTok -ne '') { [double]$dTok } else { $null }
            $estDel = _GetVal $r 'est_delegate'
            if ($null -ne $effD -and $null -ne $estDel) {
                $actual = [double]$effD
                $est = [double]$estDel
                $est = Get-TokenDelegateJobEstimate $est $dTok $dRel (_GetVal $r 'calls') (_GetVal $r 'calls_related')
            }
        }

        if ($null -ne $actual -and $null -ne $est -and $actual -gt 0.0 -and $est -gt 0.0) {
            $ratio = $actual / $est
            $lnR = [Math]::Log($ratio)
            [void]$pathGroups[$p].Add(@{
                Row   = $r
                Ratio = $ratio
                LnR   = $lnR
            })
        }
    }

    foreach ($pKey in @('direct', 'delegate')) {
        $items = $pathGroups[$pKey]
        if ($items.Count -lt 10) { continue }

        $lnList = New-Object System.Collections.ArrayList
        foreach ($it in $items) { [void]$lnList.Add($it.LnR) }
        $med = Get-TokenMedian $lnList
        if ($null -eq $med) { continue }

        $devs = New-Object System.Collections.ArrayList
        foreach ($val in $lnList) {
            [void]$devs.Add([Math]::Abs($val - $med))
        }
        $mad = Get-TokenMedian $devs
        # MAD 가 0 이면 흩어짐 기준은 쓰지 않고 절대 기준만 본다
        $threshold = if ($null -ne $mad -and $mad -gt 0.0) { 3.0 * 1.4826 * $mad } else { [double]::PositiveInfinity }
        $absLimit = [Math]::Log($AbsFactor)

        foreach ($it in $items) {
            $diff = [Math]::Abs($it.LnR - $med)
            if ($diff -gt $threshold -or [Math]::Abs($it.LnR) -gt $absLimit) {
                $r = $it.Row
                $file = [string](_GetVal $r 'file')
                $turnTs = [string](_GetVal $r 'turn_ts')
                $key = "$file|$turnTs"

                $cause = $null

                # 1. agy_slow: 그 턴에 연결된 작업 중 하나라도 elapsed > 3 x $AgyMedians[수준키]
                if ($null -ne $TaskInfo -and $TaskInfo.ContainsKey($key)) {
                    $taskList = @($TaskInfo[$key])
                    foreach ($t in $taskList) {
                        $m = [string](_GetVal $t 'model')
                        $mLower = $m.ToLower()
                        $levelKey = if ($mLower -match 'low') { 'low' } elseif ($mLower -match 'medium') { 'medium' } elseif ($mLower -match 'high') { 'high' } else { $null }
                        if ($levelKey -and $null -ne $AgyMedians -and $AgyMedians.ContainsKey($levelKey)) {
                            $el = _GetVal $t 'elapsed'
                            if ($null -eq $el) { $el = _GetVal $t 'elapsed_sec' }
                            $elVal = 0.0
                            if ($null -ne $el -and [double]::TryParse([string]$el, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$elVal)) {
                                $medSec = [double]$AgyMedians[$levelKey]
                                if ($elVal -gt (3.0 * $medSec)) {
                                    $cause = 'agy_slow'
                                    break
                                }
                            }
                        }
                    }
                }

                # 2. scope: path='delegate' 이고 est_direct 가 있고 est_direct - (d_tokens - COALESCE(d_related, d_tokens)) <= 0
                if ($null -eq $cause -and $pKey -eq 'delegate') {
                    $ed = _GetVal $r 'est_direct'
                    if ($null -ne $ed -and [string]$ed -ne '') {
                        $edVal = [double]$ed
                        $dTok = [double](_GetVal $r 'd_tokens')
                        $dRel = _GetVal $r 'd_related'
                        $effRel = if ($null -ne $dRel -and [string]$dRel -ne '') { [double]$dRel } else { $dTok }
                        $otherTokens = $dTok - $effRel
                        if (($edVal - $otherTokens) -le 0.0) {
                            $cause = 'scope'
                        }
                    }
                }

                # 3. weak_estimate: level 칸이 NULL(수준 태그가 없던 예전 규칙으로 쓴 예상)
                if ($null -eq $cause) {
                    $lv = _GetVal $r 'level'
                    if ($null -eq $lv -or [string]$lv -eq '') {
                        $cause = 'weak_estimate'
                    }
                }

                # 4. unknown: 그 밖
                if ($null -eq $cause) {
                    $cause = 'unknown'
                }

                $result[$key] = $cause
            }
        }
    }

    return $result
}

# 예상 보정 계수: 최근 턴의 실제 ÷ 예상 중앙값(ratio)을 다음 예상에 곱할 계수로 쓴다. 입력은 예상 ÷ 실제 목록(표의 비율의 역수).
# 표본이 5개 미만이면 보정하지 않고(factor 1.0), 그 이상에서는 표본이 적을수록 1 쪽으로 당긴다: factor = 1 + (ratio - 1) x n / (n + 10).
# 고정 상수가 아니라 통계를 갱신할 때마다(Get-TokenCalibration 이 돌 때마다) 최근 표본으로 다시 계산한다.
function Get-TokenCorrection($EstOverActual) {
    $inv = New-Object System.Collections.ArrayList
    foreach ($x in @($EstOverActual)) { if ([double]$x -gt 0) { [void]$inv.Add(1.0 / [double]$x) } }
    if ($inv.Count -lt 5) { return [ordered]@{ ratio = $null; n = [int]$inv.Count; factor = 1.0 } }
    $ratio = [Math]::Max(0.2, [Math]::Min(5.0, [double](Get-TokenMedian $inv)))
    $w = [double]$inv.Count / ([double]$inv.Count + 10.0)
    return [ordered]@{ ratio = [Math]::Round($ratio, 2); n = [int]$inv.Count; factor = [Math]::Round(1.0 + ($ratio - 1.0) * $w, 2) }
}

function Get-TokenCalibration {
    param(
        [string]$DbPath = "",
        [string]$RuntimeDir = "",
        [int]$WindowDays = 60,
        [int]$MaxPerPath = 300
    )
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $DbPath) {
        $dataDir = if (Get-Command Get-AgyDataDir -CommandType Function -ErrorAction SilentlyContinue) {
            Get-AgyDataDir $RuntimeDir
        } else {
            $trimmed = $RuntimeDir.TrimEnd('\', '/')
            if ((Split-Path -Leaf $trimmed) -eq "runtime") { Join-Path (Split-Path $trimmed -Parent) "data" } else { Join-Path $trimmed "data" }
        }
        $DbPath = Join-Path $dataDir "delegate.db"
    } else {
        $dataDir = Split-Path $DbPath -Parent
    }

    $target = 20
    if ($env:AGY_COLLECT_TARGET -ne $null -and $env:AGY_COLLECT_TARGET -ne "") {
        $parsedTarget = 0
        if ([int]::TryParse([string]$env:AGY_COLLECT_TARGET, [ref]$parsedTarget)) {
            $target = [Math]::Max(0, $parsedTarget)
        }
    }

    $db = $null
    try {
        $db = Open-AgyDb $DbPath
    } catch {
        $active = if ($target -le 0) { $false } else { $true }
        $defaultLevels = [ordered]@{
            direct = [ordered]@{
                low    = [ordered]@{ a = 800; b = 1300; n = 0; required = 1000; cv = $null; source = "overall" }
                medium = [ordered]@{ a = 800; b = 1300; n = 0; required = 1000; cv = $null; source = "overall" }
                high   = [ordered]@{ a = 800; b = 1300; n = 0; required = 1000; cv = $null; source = "overall" }
            }
            delegate = [ordered]@{
                low    = [ordered]@{ a = 2500; b = 1000; n = 0; required = 1000; cv = $null; source = "overall" }
                medium = [ordered]@{ a = 2500; b = 1000; n = 0; required = 1000; cv = $null; source = "overall" }
                high   = [ordered]@{ a = 2500; b = 1000; n = 0; required = 1000; cv = $null; source = "overall" }
            }
            time_direct = [ordered]@{
                low    = [ordered]@{ a_s = 11; b_s = 15; n = 0; required = 1000; cv = $null; source = "overall" }
                medium = [ordered]@{ a_s = 11; b_s = 15; n = 0; required = 1000; cv = $null; source = "overall" }
                high   = [ordered]@{ a_s = 11; b_s = 15; n = 0; required = 1000; cv = $null; source = "overall" }
            }
        }
        return [ordered]@{
            updated                 = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            window_days             = $WindowDays
            direct                  = [ordered]@{ a = 800; b = 1300; n = 0; source = "default"; window_days = 60 }
            delegate                = [ordered]@{ a = 2500; b = 1000; n = 0; source = "default"; window_days = 60 }
            levels                  = $defaultLevels
            estimate_accuracy       = [ordered]@{ n = 0; direct_ratio_median = $null; delegate_ratio_median = $null; v1_excluded_n = 0 }
            correction              = [ordered]@{ direct = [ordered]@{ ratio = $null; n = 0; factor = 1.0 }; delegate = [ordered]@{ ratio = $null; n = 0; factor = 1.0 } }
            anomalies               = [ordered]@{
                recent_days = 7
                n           = 0
                by_cause    = [ordered]@{
                    agy_slow      = 0
                    scope         = 0
                    weak_estimate = 0
                    unknown       = 0
                }
            }
            collect                 = [ordered]@{ active = [bool]$active; delegate_n = 0; target = [int]$target }
            context_reread_per_call = $null
            time                    = [ordered]@{
                direct       = [ordered]@{ a_s = 11; b_s = 15; n = 0; source = "default" }
                agy_median_s = [ordered]@{
                    low    = 16
                    medium = 60
                    high   = 444
                    n      = [ordered]@{ low = 0; medium = 0; high = 0 }
                }
            }
        }
    }
    try {
        $hasLevelCol = $false
        try {
            $ttCols = @($db.Query("PRAGMA table_info(token_turns)", $null) | ForEach-Object { [string]$_['name'] })
            if ($ttCols -contains 'level') { $hasLevelCol = $true }
        } catch {}
        $levelColSql = if ($hasLevelCol) { ", level" } else { "" }

        $cutIso30 = (Get-Date).ToUniversalTime().AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ss')
        $cutSpace30 = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd HH:mm:ss')
        $cutIso60 = (Get-Date).ToUniversalTime().AddDays(-60).ToString('yyyy-MM-ddTHH:mm:ss')
        $cutSpace60 = (Get-Date).AddDays(-60).ToString('yyyy-MM-dd HH:mm:ss')

        # 기본 30일 창을 사용하고, 표본이 20개 미만이면 60일로 창을 넓힌다
        $dirRows = @($db.Query(
            "SELECT calls, d_tokens$levelColSql FROM token_turns WHERE calls >= 1 AND d_tokens IS NOT NULL AND path = 'direct' AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC LIMIT ?",
            [object[]]@($cutIso30, $cutSpace30, [long]$MaxPerPath)
        ))
        $dirWindowDays = 30
        if ($dirRows.Count -lt 20) {
            $dirRows = @($db.Query(
                "SELECT calls, d_tokens$levelColSql FROM token_turns WHERE calls >= 1 AND d_tokens IS NOT NULL AND path = 'direct' AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC LIMIT ?",
                [object[]]@($cutIso60, $cutSpace60, [long]$MaxPerPath)
            ))
            $dirWindowDays = 60
        }
        $dirPoints = New-Object System.Collections.ArrayList
        foreach ($r in $dirRows) {
            [void]$dirPoints.Add(@{ calls = [int]$r['calls']; d = [int]$r['d_tokens'] })
        }
        $dirResult = Get-TheilSenEstimator -Points $dirPoints -DefaultA 800 -DefaultB 1300

        $delRows = @($db.Query(
            "SELECT calls, d_tokens, calls_related, d_related$levelColSql FROM token_turns WHERE COALESCE(calls_related, calls) >= 1 AND COALESCE(d_related, d_tokens) IS NOT NULL AND path = 'delegate' AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC LIMIT ?",
            [object[]]@($cutIso30, $cutSpace30, [long]$MaxPerPath)
        ))
        $delWindowDays = 30
        if ($delRows.Count -lt 20) {
            $delRows = @($db.Query(
                "SELECT calls, d_tokens, calls_related, d_related$levelColSql FROM token_turns WHERE COALESCE(calls_related, calls) >= 1 AND COALESCE(d_related, d_tokens) IS NOT NULL AND path = 'delegate' AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC LIMIT ?",
                [object[]]@($cutIso60, $cutSpace60, [long]$MaxPerPath)
            ))
            $delWindowDays = 60
        }
        $delPoints = New-Object System.Collections.ArrayList
        foreach ($r in $delRows) {
            $c = if ($r['calls_related'] -ne $null -and $r['calls_related'] -ne [DBNull]::Value) { [int]$r['calls_related'] } else { [int]$r['calls'] }
            $d = if ($r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { [int]$r['d_related'] } else { [int]$r['d_tokens'] }
            [void]$delPoints.Add(@{ calls = $c; d = $d })
        }
        $delResult = Get-TheilSenEstimator -Points $delPoints -DefaultA 2500 -DefaultB 1000

        $accRows = @($db.Query(
            "SELECT path, est_direct, est_delegate, est_factor_direct, est_factor_delegate, d_tokens, d_related, calls, calls_related, est_ver FROM token_turns WHERE calls >= 1 AND COALESCE(d_related, d_tokens) IS NOT NULL AND COALESCE(d_related, d_tokens) > 0 AND path IN ('direct', 'delegate') AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC",
            [object[]]@($cutIso60, $cutSpace60)
        ))
        $dirRatios = New-Object System.Collections.ArrayList
        $delRatios = New-Object System.Collections.ArrayList
        $dirRecent = New-Object System.Collections.ArrayList   # 보정 계수용: 가장 최근 30턴(행이 최신순으로 온다)
        $delRecent = New-Object System.Collections.ArrayList
        $v1Count = 0
        foreach ($r in $accRows) {
            $ver = [string]$r['est_ver']
            if ($ver -eq 'v1') {
                $v1Count++
                continue
            }
            if ($ver -ne 'v2') {
                continue
            }
            # 실제로 간 길(path)로 나눈다: 직접 턴은 직접 예상 ÷ 실제, 위임 턴은 위임한 일만의 예상 ÷ 위임 관련 실제(통계 화면과 같은 기준)
            $pth = [string]$r['path']
            $d = [double]$r['d_tokens']
            $dDel = if ($r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { [double]$r['d_related'] } else { $d }
            if ($pth -eq 'direct' -and $null -ne $r['est_direct'] -and $r['est_direct'] -ne [DBNull]::Value -and $d -gt 0) {
                [void]$dirRatios.Add([double]$r['est_direct'] / $d)
                # 보정 계수용: 기록할 때 곱했던 계수로 나눠 보정 전 예상으로 비율을 낸다(계수가 되먹임으로 흔들리지 않게)
                $fd = if ($r['est_factor_direct'] -ne $null -and $r['est_factor_direct'] -ne [DBNull]::Value -and [double]$r['est_factor_direct'] -gt 0) { [double]$r['est_factor_direct'] } else { 1.0 }
                if ($dirRecent.Count -lt 30) { [void]$dirRecent.Add(([double]$r['est_direct'] / $fd) / $d) }
            } elseif ($pth -eq 'delegate' -and $null -ne $r['est_delegate'] -and $r['est_delegate'] -ne [DBNull]::Value -and $dDel -gt 0) {
                $jobEstCal = Get-TokenDelegateJobEstimate ([double]$r['est_delegate']) $r['d_tokens'] $r['d_related'] $r['calls'] $r['calls_related']
                [void]$delRatios.Add($jobEstCal / $dDel)
                $fl = if ($r['est_factor_delegate'] -ne $null -and $r['est_factor_delegate'] -ne [DBNull]::Value -and [double]$r['est_factor_delegate'] -gt 0) { [double]$r['est_factor_delegate'] } else { 1.0 }
                if ($delRecent.Count -lt 30) {
                    $jobEstRaw = Get-TokenDelegateJobEstimate (([double]$r['est_delegate']) / $fl) $r['d_tokens'] $r['d_related'] $r['calls'] $r['calls_related']
                    [void]$delRecent.Add($jobEstRaw / $dDel)
                }
            }
        }
        $totalAccN = $dirRatios.Count + $delRatios.Count
        $dirRatioMed = if ($dirRatios.Count -gt 0) { [Math]::Round([double](Get-TokenMedian $dirRatios), 1) } else { $null }
        $delRatioMed = if ($delRatios.Count -gt 0) { [Math]::Round([double](Get-TokenMedian $delRatios), 1) } else { $null }
        $corrDirect = Get-TokenCorrection $dirRecent
        $corrDelegate = Get-TokenCorrection $delRecent

        # 캐시 재읽기 중앙값 (호출당 cr_tokens / calls)
        $crList = New-Object System.Collections.ArrayList
        try {
            $crRows = @($db.Query(
                "SELECT calls, cr_tokens FROM token_turns WHERE calls >= 1 AND cr_tokens IS NOT NULL AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END)",
                [object[]]@($cutIso60, $cutSpace60)
            ))
            foreach ($crR in $crRows) {
                $cVal = [double]$crR['calls']
                $crVal = [double]$crR['cr_tokens']
                if ($cVal -gt 0) {
                    [void]$crList.Add($crVal / $cVal)
                }
            }
        } catch {}
        $contextRereadMed = if ($crList.Count -gt 0) { [int][Math]::Round([double](Get-TokenMedian $crList)) } else { $null }

        # 시간 direct Theil-Sen 추정
        $timeDirRows = @($db.Query(
            "SELECT calls, dur_sec$levelColSql FROM token_turns WHERE calls >= 1 AND dur_sec IS NOT NULL AND path = 'direct' AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC LIMIT ?",
            [object[]]@($cutIso30, $cutSpace30, [long]$MaxPerPath)
        ))
        if ($timeDirRows.Count -lt 20) {
            $timeDirRows = @($db.Query(
                "SELECT calls, dur_sec$levelColSql FROM token_turns WHERE calls >= 1 AND dur_sec IS NOT NULL AND path = 'direct' AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END) ORDER BY turn_ts DESC LIMIT ?",
                [object[]]@($cutIso60, $cutSpace60, [long]$MaxPerPath)
            ))
        }
        $timeDirPoints = New-Object System.Collections.ArrayList
        foreach ($r in $timeDirRows) {
            [void]$timeDirPoints.Add(@{ calls = [int]$r['calls']; dur = [int]$r['dur_sec'] })
        }
        $timeDirResult = Get-TheilSenTimeEstimator -Points $timeDirPoints -DefaultA 11 -DefaultB 15

        # 시간 agy 중앙값 (tasks 테이블에서 최근 30일 status='OK' 작업)
        $lowMed = 16
        $medMed = 60
        $highMed = 444
        $lowN = 0
        $medN = 0
        $highN = 0
        $lowList = New-Object System.Collections.ArrayList
        $medList = New-Object System.Collections.ArrayList
        $highList = New-Object System.Collections.ArrayList

        try {
            $taskRows = @($db.Query(
                "SELECT model, elapsed_sec FROM tasks WHERE status = 'OK' AND elapsed_sec IS NOT NULL AND elapsed_sec <> '' AND (CASE WHEN timestamp LIKE '%T%' THEN timestamp >= ? ELSE timestamp >= ? END)",
                [object[]]@($cutIso30, $cutSpace30)
            ))
            foreach ($tr in $taskRows) {
                $mName = ([string]$tr['model']).ToLower()
                $elVal = 0.0
                if ([double]::TryParse([string]$tr['elapsed_sec'], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$elVal)) {
                    if ($mName -match 'low') {
                        [void]$lowList.Add($elVal)
                    } elseif ($mName -match 'medium') {
                        [void]$medList.Add($elVal)
                    } elseif ($mName -match 'high') {
                        [void]$highList.Add($elVal)
                    }
                }
            }

            $calcRobustMed = {
                param($list, [int]$defaultMed)
                if ($null -eq $list -or $list.Count -eq 0) {
                    return @{ Median = $defaultMed; N = 0 }
                }
                $initMed = [double](Get-TokenMedian $list)
                $cutoff = $initMed * 3.0
                $filtered = New-Object System.Collections.ArrayList
                foreach ($v in $list) {
                    if ([double]$v -le $cutoff) {
                        [void]$filtered.Add([double]$v)
                    }
                }
                if ($filtered.Count -gt 0) {
                    $finalMed = [int][Math]::Round([double](Get-TokenMedian $filtered))
                    return @{ Median = $finalMed; N = [int]$filtered.Count }
                } else {
                    $finalMed = [int][Math]::Round($initMed)
                    return @{ Median = $finalMed; N = 0 }
                }
            }

            $lowRobust = &$calcRobustMed $lowList 16
            $medRobust = &$calcRobustMed $medList 60
            $highRobust = &$calcRobustMed $highList 444

            $lowMed = $lowRobust.Median
            $medMed = $medRobust.Median
            $highMed = $highRobust.Median
            $lowN = $lowRobust.N
            $medN = $medRobust.N
            $highN = $highRobust.N
        } catch {}

        $agyMedianObj = [ordered]@{
            low    = [int]$lowMed
            medium = [int]$medMed
            high   = [int]$highMed
            n      = [ordered]@{
                low    = [int]$lowN
                medium = [int]$medN
                high   = [int]$highN
            }
        }

        # 이상치 판정 및 DB 갱신
        $taskInfo = @{}
        try {
            $linkRows = @($db.Query(
                "SELECT l.file, l.turn_ts, t.model, t.elapsed_sec FROM token_task_links l JOIN tasks t ON l.task_id = t.task_id",
                $null
            ))
            foreach ($lr in $linkRows) {
                $k = "$($lr['file'])|$($lr['turn_ts'])"
                if (-not $taskInfo.ContainsKey($k)) {
                    $taskInfo[$k] = New-Object System.Collections.ArrayList
                }
                $elVal = 0.0
                if ($null -ne $lr['elapsed_sec'] -and $lr['elapsed_sec'] -ne [DBNull]::Value) {
                    [void][double]::TryParse([string]$lr['elapsed_sec'], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$elVal)
                }
                [void]$taskInfo[$k].Add(@{
                    model   = [string]$lr['model']
                    elapsed = $elVal
                })
            }
        } catch {}

        $hasAnomalyCol = $false
        try {
            if ($ttCols -contains 'anomaly') { $hasAnomalyCol = $true }
        } catch {}
        $anomalyColSql = if ($hasAnomalyCol) { ", anomaly" } else { "" }

        $all60Rows = @($db.Query(
            "SELECT file, turn_ts, path, calls, calls_related, d_tokens, d_related, est_direct, est_delegate, est_ver, dur_sec, est_time_direct, est_time_delegate$levelColSql$anomalyColSql FROM token_turns WHERE (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END)",
            [object[]]@($cutIso60, $cutSpace60)
        ))
        $agyMediansHt = @{
            low    = [int]$lowMed
            medium = [int]$medMed
            high   = [int]$highMed
        }
        $anomalyFlags = Get-TokenAnomalyFlags $all60Rows $agyMediansHt $taskInfo

        if ($hasAnomalyCol) {
            try {
                Invoke-AgyDbTransaction $db {
                    [void]$db.Execute(
                        "UPDATE token_turns SET anomaly = NULL WHERE (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END)",
                        [object[]]@($cutIso60, $cutSpace60)
                    )
                    foreach ($aKey in $anomalyFlags.Keys) {
                        $parts = $aKey.Split('|')
                        if ($parts.Length -ge 2) {
                            $aFile = $parts[0]
                            $aTurnTs = $parts[1..($parts.Length - 1)] -join '|'
                            $aCause = [string]$anomalyFlags[$aKey]
                            [void]$db.Execute(
                                "UPDATE token_turns SET anomaly = ? WHERE file = ? AND turn_ts = ?",
                                [object[]]@($aCause, $aFile, $aTurnTs)
                            )
                        }
                    }
                }
            } catch {}
        }

        $cutIso7 = (Get-Date).ToUniversalTime().AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ss')
        $cutSpace7 = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd HH:mm:ss')
        $recent7Anomalies = 0
        $causeCounts = [ordered]@{
            agy_slow      = 0
            scope         = 0
            weak_estimate = 0
            unknown       = 0
        }
        foreach ($r in $all60Rows) {
            $ts = [string]$r['turn_ts']
            $isRecent7 = if ($ts -match 'T') { $ts -ge $cutIso7 } else { $ts -ge $cutSpace7 }
            if ($isRecent7) {
                $k = "$($r['file'])|$ts"
                if ($anomalyFlags.ContainsKey($k)) {
                    $recent7Anomalies++
                    $c = [string]$anomalyFlags[$k]
                    if ($causeCounts.Contains($c)) {
                        $causeCounts[$c]++
                    } else {
                        $causeCounts['unknown']++
                    }
                }
            }
        }
        $anomaliesObj = [ordered]@{
            recent_days = 7
            n           = [int]$recent7Anomalies
            by_cause    = $causeCounts
        }

        $delN = 0
        try {
            $delCountQuery = "SELECT COUNT(*) AS n FROM token_turns WHERE path = 'delegate' AND COALESCE(d_related, d_tokens) IS NOT NULL AND (CASE WHEN turn_ts LIKE '%T%' THEN turn_ts >= ? ELSE turn_ts >= ? END)"
            $delCountRows = @($db.Query($delCountQuery, [object[]]@($cutIso60, $cutSpace60)))
            if ($delCountRows.Count -gt 0 -and $null -ne $delCountRows[0]['n'] -and $delCountRows[0]['n'] -ne [DBNull]::Value) {
                $delN = [int]$delCountRows[0]['n']
            }
        } catch {
            $delN = 0
        }
        $active = if ($target -le 0) { $false } else { [bool]($delN -lt $target) }

        $levelsObj = [ordered]@{
            direct      = (Get-TokenLevelFits $dirRows 'direct' $hasLevelCol $dirResult)
            delegate    = (Get-TokenLevelFits $delRows 'delegate' $hasLevelCol $delResult)
            time_direct = (Get-TokenLevelFits $timeDirRows 'time' $hasLevelCol $timeDirResult)
        }

        $calData = [ordered]@{
            updated           = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            window_days       = $WindowDays
            direct            = [ordered]@{
                a           = [int]$dirResult.a
                b           = [int]$dirResult.b
                n           = [int]$dirResult.n
                source      = [string]$dirResult.source
                window_days = [int]$dirWindowDays
            }
            delegate          = [ordered]@{
                a           = [int]$delResult.a
                b           = [int]$delResult.b
                n           = [int]$delResult.n
                source      = [string]$delResult.source
                window_days = [int]$delWindowDays
            }
            estimate_accuracy = [ordered]@{
                n                     = [int]$totalAccN
                direct_ratio_median   = $dirRatioMed
                delegate_ratio_median = $delRatioMed
                v1_excluded_n         = [int]$v1Count
            }
            correction        = [ordered]@{ direct = $corrDirect; delegate = $corrDelegate }
            anomalies         = $anomaliesObj
            collect           = [ordered]@{
                active     = [bool]$active
                delegate_n = [int]$delN
                target     = [int]$target
            }
            context_reread_per_call = $contextRereadMed
            time              = [ordered]@{
                direct       = [ordered]@{
                    a_s    = [int]$timeDirResult.a_s
                    b_s    = [int]$timeDirResult.b_s
                    n      = [int]$timeDirResult.n
                    source = [string]$timeDirResult.source
                }
                agy_median_s = $agyMedianObj
            }
            levels            = $levelsObj
        }

        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        $json = ConvertTo-Json -InputObject $calData -Depth 8
        $calFile = Join-Path $dataDir "calibration.json"
        [System.IO.File]::WriteAllText($calFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        return $calData
    } finally {
        if ($null -ne $db) { $db.Dispose() }
    }
}

# 진행 중인 턴(turn_ts 이후)에서 가장 최근에 기록한 예상을 돌려준다(위임 탭의 진행 중 카드용). 위임을 보내기 전에 이미 정해진 값이다. 없으면 $null.
# ToTs 를 주면(위임을 보낸 시각) 그 시각까지의 기록만 보고, 그 사이 질문 전환 표시(kind=switch, switch_to=N)를 따라 그 시각에 일하던 질문의 기록을 고른다.
# 질문 번호는 그 기간 안 예상 기록의 순서다(질문마다 한 번 기록하므로). 나중 질문이 기록해도 앞 위임의 값은 바뀌지 않는다.
function Get-RecordedEstimate([string]$DbPath, [string]$Project, [string]$FromTs, [string]$ToTs = "", [string]$Session = "") {
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath) -or -not $Project -or -not $FromTs) { return $null }
    $db = $null
    try {
        $db = Open-AgyDb $DbPath
        $hasSession = $false
        if ($Session) {
            try {
                foreach ($ci in @($db.Query("PRAGMA table_info(token_estimates)", $null))) {
                    if ([string]$ci['name'] -eq 'session') { $hasSession = $true; break }
                }
            } catch {}
        }
        $sql = "SELECT est_direct, est_delegate, est_time_direct, est_time_delegate, kind, switch_to FROM token_estimates WHERE project = ? AND recorded_at >= ?"
        $args2 = @($Project, $FromTs)
        if ($ToTs) { $sql += " AND recorded_at <= ?"; $args2 += $ToTs }
        if ($Session -and $hasSession) {
            $sql += " AND (session IS NULL OR session = ?)"
            $args2 += $Session
        }
        $rows = @($db.Query($sql + " ORDER BY recorded_at ASC", [object[]]$args2))
        $qrecs = New-Object System.Collections.ArrayList
        $active = $null
        foreach ($row in $rows) {
            $kd = if ($null -eq $row['kind'] -or $row['kind'] -eq [DBNull]::Value) { "" } else { [string]$row['kind'] }
            if ($kd -eq 'switch') {
                $n = if ($null -eq $row['switch_to'] -or $row['switch_to'] -eq [DBNull]::Value) { 0 } else { [int]$row['switch_to'] }
                if ($n -ge 1 -and $n -le $qrecs.Count) { $active = $qrecs.Item($n - 1) }
                continue
            }
            if ($kd -eq 'backfill') { continue }
            [void]$qrecs.Add($row)
            $active = $row
        }
        if ($null -eq $active) { return $null }
        $o = [ordered]@{}
        foreach ($k in @('est_direct', 'est_delegate', 'est_time_direct', 'est_time_delegate')) {
            $v = $active[$k]
            $o[$k] = if ($null -eq $v -or $v -eq [DBNull]::Value) { $null } else { [int][Math]::Round([double]$v) }
        }
        return $o
    } catch { return $null } finally { if ($db) { $db.Dispose() } }
}

# 이어서 시작한 세션(resume · 압축 뒤 새 세션)의 대화 기록 파일은 앞 세션의 턴을 그대로 복사해 담는다. 그러면 같은 턴이 파일마다 한 줄씩 겹쳐 쌓여
# 통계가 두 번 세어지고, 기록한 예상은 그중 한 줄에만 붙어 나머지는 빈 값이 된다. 같은 (프로젝트, 턴 시작 시각)은 한 줄만 남긴다.
# 남기는 줄: 기록한 예상이 붙은 것 > 작업 연결이 있는 것 > 파일 경로 순. 지우는 줄의 작업 연결은 남기는 줄로 옮긴다. 몇 번을 돌려도 같은 결과(멱등)다. 지운 줄 수를 돌려준다.
function Remove-DuplicateTurns($Db) {
    $groups = @($Db.Query("SELECT project, turn_ts FROM token_turns WHERE turn_ts LIKE '%T%' GROUP BY project, turn_ts HAVING COUNT(*) > 1", $null))
    $removed = 0
    foreach ($g in $groups) {
        $rows = @($Db.Query("SELECT t.file AS file, (CASE WHEN t.est_direct IS NOT NULL OR t.est_delegate IS NOT NULL THEN 1 ELSE 0 END) AS has_est, (SELECT COUNT(*) FROM token_task_links l WHERE l.file = t.file AND l.turn_ts = t.turn_ts) AS nlink FROM token_turns t WHERE t.project = ? AND t.turn_ts = ? ORDER BY has_est DESC, nlink DESC, t.file ASC", [object[]]@([string]$g['project'], [string]$g['turn_ts'])))
        if ($rows.Count -lt 2) { continue }
        $keep = [string]$rows[0]['file']
        for ($i = 1; $i -lt $rows.Count; $i++) {
            $drop = [string]$rows[$i]['file']
            [void]$Db.Execute("UPDATE token_task_links SET file = ? WHERE file = ? AND turn_ts = ?", [object[]]@($keep, $drop, [string]$g['turn_ts']))
            [void]$Db.Execute("DELETE FROM token_turns WHERE file = ? AND turn_ts = ?", [object[]]@($drop, [string]$g['turn_ts']))
            $removed++
        }
    }
    return $removed
}

# Claude Code 프로젝트 폴더 이름 규칙: 작업 폴더 경로의 영문 · 숫자가 아닌 글자를 모두 - 로 바꾼다(D:\Repos\a.b -> D--Repos-a-b).
function ConvertTo-ClaudeProjectName([string]$Cwd) {
    if (-not $Cwd) { return "" }
    return ($Cwd.Trim().TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-')
}

# 대화 기록에 작업 번호가 남지 않은 위임(스크립트가 대신 제출해 결과가 화면에만 찍힌 경우 등)을, 제출 시각에 진행 중이던 질문에 잇는다.
# 제출 시각은 작업 번호(claude_<epoch>_N)에서 구한다. 위임 지시문에 @cwd 가 있으면 그 폴더의 프로젝트 질문만 보고,
# 없으면 그 시각에 진행 중이던 질문이 한 프로젝트에만 있을 때만 잇는다(여러 세션이 겹치면 어느 질문 몫인지 알 수 없어 건너뛴다). 이은 작업 수를 돌려준다.
function Add-OrphanTaskLinks($Db) {
    $linked = 0
    $orphans = @($Db.Query("SELECT t.task_id AS task_id, t.question AS question FROM tasks t WHERE t.task_id LIKE 'claude_%' AND NOT EXISTS (SELECT 1 FROM token_task_links l WHERE l.task_id = t.task_id)", $null))
    foreach ($o in $orphans) {
        $tid = [string]$o['task_id']
        if ($tid -notmatch '^claude_(\d{9,11})_\d+') { continue }
        $subIso = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $subPlus = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1] - 5).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $q = [string]$o['question']
        $proj = ""
        if ($q -match '(?m)^\s*@cwd:\s*(.+?)\s*$') { $proj = ConvertTo-ClaudeProjectName $Matches[1] }
        $cands = @($Db.Query("SELECT file, turn_ts, project FROM token_turns WHERE turn_ts LIKE '%T%' AND turn_ts <= ? AND end_ts IS NOT NULL AND end_ts >= ? ORDER BY turn_ts DESC", [object[]]@($subIso, $subPlus)))
        if ($proj) { $cands = @($cands | Where-Object { [string]$_['project'] -eq $proj }) }
        if ($cands.Count -eq 0) { continue }
        $projs = @($cands | ForEach-Object { [string]$_['project'] } | Select-Object -Unique)
        if ($projs.Count -ne 1) { continue }
        $pick = $cands[0]
        [void]$Db.Execute("INSERT INTO token_task_links (task_id, file, turn_ts) VALUES (?, ?, ?) ON CONFLICT(task_id) DO NOTHING", [object[]]@($tid, [string]$pick['file'], [string]$pick['turn_ts']))
        $linked++
    }
    return $linked
}

# record-estimate.ps1 이 token_estimates 에 남긴 예상을 질문 행에 붙인다: 같은 프로젝트에서 질문이 시작한 뒤(turn_ts) 끝나기 전(end_ts)에 기록된 것.
# 질문 시작 시각과 똑같은 시각의 기록(나중에 질문 원문만 보고 채운 예상)은 끝 시각이 없는 옛 행에도 붙는다.
# - 예상 값은 최초 기록으로 고정한다: 한 질문에 다시 기록해도(경고를 보고 선택을 바꾼 경우 등) 토큰 · 시간 예상은 처음 값 그대로이고 선택 · 사유 · 수준만 바뀐다.
#   (나중에 원문만 보고 채운 예상(backfill)이 붙어 있던 행은 그 질문 때 실제로 기록한 값이 이긴다)
# - 붙인 기록은 merged = 1 로 표시해 다음 수집에서는 다시 보지 않는다(매번 전체를 다시 붙이면 수집이 수 초씩 느려진다). 아직 행이 없는 기록(진행 중인 질문)은 남겨 두었다 다음에 붙인다.
#   -All 이면 표시와 상관없이 전부 다시 본다(행을 처음부터 다시 만든 뒤).
# - 기록할 때의 작업 폴더가 프로젝트의 하위 폴더였으면(cd 로 옮긴 뒤 기록) 프로젝트 이름이 길어져 맞는 행이 없다. 그때는 그 이름의 앞부분인 프로젝트 중 가장 긴 것에서 찾는다.
# 기록에 세션 번호가 있으면 그 세션 파일의 질문에만 붙인다(같은 프로젝트에서 세션 여러 개를 동시에 써도 섞이지 않는다). 세션 번호가 없는 옛 기록만 프로젝트와 시각으로 찾는다. 붙인 기록 수를 돌려준다. 몇 번을 돌려도 같은 결과(멱등)다.
function Merge-RecordedEstimates($Db, [int]$Days = 3650, [switch]$All) {
    $cut = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ss")
    $hasMerged = $false
    $hasSession = $false
    try {
        foreach ($ci in @($Db.Query("PRAGMA table_info(token_estimates)", $null))) {
            if ([string]$ci['name'] -eq 'merged') { $hasMerged = $true }
            if ([string]$ci['name'] -eq 'session') { $hasSession = $true }
        }
    } catch {}
    $where = "recorded_at >= ?"
    if ($hasMerged -and -not $All) {
        $where += " AND COALESCE(merged, 0) = 0"
    }
    $sessionCol = if ($hasSession) { ", session" } else { "" }
    $ests = @($Db.Query("SELECT id, recorded_at, project, est_direct, est_delegate, est_time_direct, est_time_delegate, choice, level, factor_direct, factor_delegate, kind, reason$sessionCol FROM token_estimates WHERE $where ORDER BY recorded_at ASC, id ASC", [object[]]@($cut)))
    if ($ests.Count -eq 0) { return 0 }
    $projNames = $null
    $merged = 0
    foreach ($e in $ests) {
        if ([string]$e['kind'] -eq 'switch') { continue }
        $rec = [string]$e['recorded_at']
        $lowIso = ([datetime]::Parse($rec, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)).AddSeconds(-3).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $findSql = "SELECT file, turn_ts, est_ver, est_kind, est_direct, est_delegate FROM token_turns WHERE project = ? AND turn_ts LIKE '%T%' AND turn_ts <= ? AND ((end_ts IS NOT NULL AND end_ts >= ?) OR turn_ts = ?) ORDER BY turn_ts DESC LIMIT 1"
        $estProj = [string]$e['project']
        $sessionVal = if ($hasSession -and $e.ContainsKey('session') -and $null -ne $e['session'] -and $e['session'] -ne [DBNull]::Value) { [string]$e['session'] } else { "" }
        $rows = @()
        if ($sessionVal) {
            $findSessionSql = "SELECT file, turn_ts, est_ver, est_kind, est_direct, est_delegate FROM token_turns WHERE file LIKE ? AND turn_ts LIKE '%T%' AND turn_ts <= ? AND ((end_ts IS NOT NULL AND end_ts >= ?) OR turn_ts = ?) ORDER BY turn_ts DESC LIMIT 1"
            $rows = @($Db.Query($findSessionSql, [object[]]@(('%' + $sessionVal + '.jsonl'), $rec, $lowIso, $rec)))
        }
        # 세션 번호가 있는데 그 세션 파일에 아직 행이 없으면 10분은 기다린다(그 세션의 질문 행이 곧 수집될 수 있다. 바로 프로젝트 기준으로 찾으면 같은 프로젝트의 다른 세션 질문에 붙는다).
        # 10분이 지나도 없으면 이어 시작한 세션이 앞 세션 질문을 복사해 다른 파일 쪽 행만 남은 경우로 보고 프로젝트 기준으로 찾는다
        if ($rows.Count -eq 0 -and $sessionVal -and -not $All) {
            $recAt = [datetime]::Parse($rec, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            if (((Get-Date).ToUniversalTime() - $recAt).TotalMinutes -lt 10) { continue }
        }
        if ($rows.Count -eq 0) {
            $rows = @($Db.Query($findSql, [object[]]@($estProj, $rec, $lowIso, $rec)))
            if ($rows.Count -eq 0 -and $estProj) {
                if ($null -eq $projNames) { $projNames = @($Db.Query("SELECT DISTINCT project FROM token_turns WHERE project IS NOT NULL", $null) | ForEach-Object { [string]$_['project'] } | Sort-Object { $_.Length } -Descending) }
                foreach ($pn in $projNames) {
                    if ($pn -and $estProj.Length -gt $pn.Length -and $estProj.StartsWith($pn + "-", [System.StringComparison]::OrdinalIgnoreCase)) {
                        $rows = @($Db.Query($findSql, [object[]]@($pn, $rec, $lowIso, $rec)))
                        if ($rows.Count -gt 0) { break }
                    }
                }
            }
        }
        if ($rows.Count -eq 0) { continue }
        $row0 = $rows[0]
        $val = { param($k) if ($e[$k] -eq $null -or $e[$k] -eq [DBNull]::Value) { $null } else { $e[$k] } }
        $rowKind = if ($null -eq $row0['est_kind'] -or $row0['est_kind'] -eq [DBNull]::Value) { "" } else { [string]$row0['est_kind'] }
        $rowHasEst = (($null -ne $row0['est_direct'] -and $row0['est_direct'] -ne [DBNull]::Value) -or ($null -ne $row0['est_delegate'] -and $row0['est_delegate'] -ne [DBNull]::Value))
        # est_kind: record = 그 질문 때 기록한 값(고정), backfill = 나중에 원문만 보고 채운 값, 빈 값 = 답변 끝 예상 줄(옛 방식)에서 읽은 값
        $rowHasLive = ($rowKind -eq 'record' -and $rowHasEst)
        $estIsBackfill = ([string]$e['kind'] -eq 'backfill')
        if ($rowHasLive -and $estIsBackfill) {
            # 그 질문 때 실제로 기록한 값이 있으면 나중에 채운 예상은 붙이지 않는다
        } elseif ($rowHasLive) {
            # 예상 값은 처음 기록 그대로 두고, 선택 · 사유 · 수준만 새 기록을 따른다
            [void]$Db.Execute(
                "UPDATE token_turns SET choice = COALESCE(?, choice), choice_reason = COALESCE(?, choice_reason), level = COALESCE(?, level) WHERE file = ? AND turn_ts = ?",
                [object[]]@((& $val 'choice'), (& $val 'reason'), (& $val 'level'), [string]$row0['file'], [string]$row0['turn_ts'])
            )
        } else {
            [void]$Db.Execute(
                "UPDATE token_turns SET est_direct = ?, est_delegate = ?, est_time_direct = ?, est_time_delegate = ?, est_ver = 'v2', choice = COALESCE(?, choice), choice_reason = COALESCE(?, choice_reason), level = COALESCE(?, level), est_factor_direct = ?, est_factor_delegate = ?, est_kind = ? WHERE file = ? AND turn_ts = ?",
                [object[]]@((& $val 'est_direct'), (& $val 'est_delegate'), (& $val 'est_time_direct'), (& $val 'est_time_delegate'), (& $val 'choice'), (& $val 'reason'), (& $val 'level'), (& $val 'factor_direct'), (& $val 'factor_delegate'), $(if ($estIsBackfill) { 'backfill' } else { 'record' }), [string]$row0['file'], [string]$row0['turn_ts'])
            )
        }
        if ($hasMerged) { [void]$Db.Execute("UPDATE token_estimates SET merged = 1 WHERE id = ?", [object[]]@([long]$e['id'])) }
        $merged++
    }
    return $merged
}
function Update-TokenStats {
    param(
        [string]$DbPath = "",
        [string]$ProjectsDir = "",
        [string]$RuntimeDir = "",
        [switch]$Backfill
    )
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $DbPath) {
        $dataDir = if (Get-Command Get-AgyDataDir -CommandType Function -ErrorAction SilentlyContinue) {
            Get-AgyDataDir $RuntimeDir
        } else {
            $trimmed = $RuntimeDir.TrimEnd('\', '/')
            if ((Split-Path -Leaf $trimmed) -eq "runtime") { Join-Path (Split-Path $trimmed -Parent) "data" } else { Join-Path $trimmed "data" }
        }
        $DbPath = Join-Path $dataDir "delegate.db"
    }
    if (-not $ProjectsDir) {
        if ($env:CLAUDE_PROJECTS_DIR) {
            $ProjectsDir = $env:CLAUDE_PROJECTS_DIR
        } else {
            $ProjectsDir = Join-Path $home_ ".claude\projects"
        }
    }

    $lockPath = Join-Path $RuntimeDir "token-stats.lock"
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $age = (Get-Date) - (Get-Item -LiteralPath $lockPath).LastWriteTime
            if ($age.TotalMinutes -lt 10) {
                return
            }
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        } catch {
            return
        }
    }
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    # 없을 때만 만든다(확인과 만들기를 한 번에 해서 수집기 둘이 동시에 시작해도 하나만 돈다)
    try {
        $lockFs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $lockBytes = [System.Text.Encoding]::ASCII.GetBytes([string]$PID); $lockFs.Write($lockBytes, 0, $lockBytes.Length) } finally { $lockFs.Dispose() }
    } catch {
        return
    }

    try {
        $db = Open-AgyDb $DbPath
        try {
            # 5: 컨텍스트가 압축된 턴(턴 도중 · 시작할 때)도 늘어난 만큼으로 토큰을 어림하도록 바뀌어(빈 값이던 턴), 최근 7일 파일을 한 번 다시 읽는다(3 -> 4 와 같은 방식)
            # 6: 한 번의 작업 도중 새 질문이 오면 질문마다 한 행으로 센다(턴이 아니라 질문이 통계 단위). 컨텍스트 압축 뒤 "이어서 진행" 메시지는 새 턴이 아니다. 최근 7일 파일을 한 번 다시 읽는다
            # 7: 답변 끝 꼬리 줄의 사유(choice_reason)를 모은다. 최근 7일 파일을 한 번 다시 읽는다
            # 8: 위임은 도구 결과에 작업 번호가 찍힌 질문만(명령 글자만으로는 위임이 아니다). 최근 7일 파일을 한 번 다시 읽고, 그보다 옛 행은 작업 연결이 없으면 직접으로 고친다
            # 9: 작업 번호는 제출 스크립트가 줄 맨 앞에 찍은 것만 읽는다(인용된 출력 속 번호 제외). 최근 7일 파일을 한 번 다시 읽는다
            $targetRuleVer = "9"
            $savedRuleVer = Get-AgyMeta $db "token_rule_ver"
            $recentResetOnly = $false
            $fixOldDelegatePath = ($null -ne $savedRuleVer -and [int]$savedRuleVer -ge 2 -and [int]$savedRuleVer -lt 8)
            $mergeAll = [bool]$Backfill
            if ($Backfill -or $null -eq $savedRuleVer -or [int]$savedRuleVer -lt 2) {
                [void]$db.Execute("UPDATE token_files SET offset = 0, last_ctx = NULL", $null)
                Set-AgyMeta $db "token_rule_ver" $targetRuleVer
            } elseif ([int]$savedRuleVer -lt [int]$targetRuleVer) {
                # v2 -> v3: 예전에는 진행 중인 턴을 중간까지만 저장하고 파일 끝부터 이어 읽어 그 턴의 나머지(호출·작업 번호)를 잃었다.
                # 최근 7일 안에 바뀐 파일만 처음부터 다시 읽는다(옛 파일 전체를 다시 읽으면 보관 기간이 지난 턴이 되살아난다).
                $recentResetOnly = $true
                Set-AgyMeta $db "token_rule_ver" $targetRuleVer
            }

            $countBefore = [int64]($db.Query("SELECT COUNT(*) AS c FROM token_turns", $null))[0]['c']
            $sessionFiles = New-Object System.Collections.ArrayList
            if (Test-Path -LiteralPath $ProjectsDir) {
                foreach ($projDir in @(Get-ChildItem -LiteralPath $ProjectsDir -Directory -ErrorAction SilentlyContinue)) {
                    $pName = $projDir.Name
                    foreach ($sf in @(Get-ChildItem -LiteralPath $projDir.FullName -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)) {
                        [void]$sessionFiles.Add(@{ File = $sf.FullName; Project = $pName })
                    }
                }
            }

            if ($recentResetOnly) {
                $recentCut = (Get-Date).AddDays(-7)
                foreach ($rf in $sessionFiles) {
                    $rfi = Get-Item -LiteralPath $rf.File -ErrorAction SilentlyContinue
                    if ($rfi -and $rfi.LastWriteTime -ge $recentCut) {
                        [void]$db.Execute("UPDATE token_files SET offset = 0, last_ctx = NULL WHERE path = ?", [object[]]@($rf.File))
                    }
                }
            }

            $totalTurnsAdded = 0
            $filesProcessed = 0

            foreach ($item in $sessionFiles) {
                $fPath = $item.File
                $pName = $item.Project

                $rows = @($db.Query("SELECT offset, last_ctx FROM token_files WHERE path = ?", [object[]]@($fPath)))
                $offset = 0L
                $lastCtx = $null
                if ($rows.Count -gt 0) {
                    $offset = [int64]$rows[0]["offset"]
                    if ($null -ne $rows[0]["last_ctx"] -and $rows[0]["last_ctx"] -ne [DBNull]::Value) {
                        $lastCtx = [int64]$rows[0]["last_ctx"]
                    }
                }

                $scanResult = Get-TokenTurnsFromSessionFile -FilePath $fPath -ProjectName $pName -StartOffset $offset -StartLastCtx $lastCtx
                $scanTurns = @($scanResult.Turns)
                if ($scanResult.NewOffset -ne $offset -or $scanTurns.Count -gt 0) {
                    $filesProcessed++
                    if ($offset -eq 0) { $mergeAll = $true }
                    Invoke-AgyDbTransaction $db {
                        if ($offset -eq 0) {
                            # 파일을 처음부터 다시 읽었으면 이번에 나오지 않은 옛 행(예: 이어서 진행 메시지가 따로 세던 턴)과 그 작업 연결을 지우고 새로 채운다
                            $keepTs = @{}
                            foreach ($kt in $scanTurns) { $keepTs[[string]$kt.turn_ts] = $true }
                            foreach ($oldRow in @($db.Query("SELECT turn_ts FROM token_turns WHERE file = ?", [object[]]@($fPath)))) {
                                if (-not $keepTs.ContainsKey([string]$oldRow['turn_ts'])) {
                                    [void]$db.Execute("DELETE FROM token_turns WHERE file = ? AND turn_ts = ?", [object[]]@($fPath, [string]$oldRow['turn_ts']))
                                }
                            }
                            [void]$db.Execute("DELETE FROM token_task_links WHERE file = ?", [object[]]@($fPath))
                        }
                        foreach ($t in $scanTurns) {
                            [void]$db.Execute(
                                "INSERT INTO token_turns (file, turn_ts, project, path, calls, submits, polls, out_tokens, d_tokens, est_direct, est_delegate, choice, choice_reason, est_ver, cr_tokens, dur_sec, est_time_direct, est_time_delegate, calls_related, d_related, level, end_ts) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(file, turn_ts) DO UPDATE SET project=excluded.project, path=excluded.path, calls=excluded.calls, submits=excluded.submits, polls=excluded.polls, out_tokens=excluded.out_tokens, d_tokens=COALESCE(excluded.d_tokens, token_turns.d_tokens), est_direct=CASE WHEN token_turns.est_kind IS NOT NULL THEN token_turns.est_direct ELSE excluded.est_direct END, est_delegate=CASE WHEN token_turns.est_kind IS NOT NULL THEN token_turns.est_delegate ELSE excluded.est_delegate END, choice=CASE WHEN token_turns.est_kind IS NOT NULL THEN COALESCE(token_turns.choice, excluded.choice) ELSE excluded.choice END, choice_reason=COALESCE(excluded.choice_reason, token_turns.choice_reason), est_ver=CASE WHEN token_turns.est_kind IS NOT NULL THEN 'v2' ELSE excluded.est_ver END, cr_tokens=excluded.cr_tokens, dur_sec=excluded.dur_sec, est_time_direct=CASE WHEN token_turns.est_kind IS NOT NULL THEN token_turns.est_time_direct ELSE excluded.est_time_direct END, est_time_delegate=CASE WHEN token_turns.est_kind IS NOT NULL THEN token_turns.est_time_delegate ELSE excluded.est_time_delegate END, calls_related=excluded.calls_related, d_related=COALESCE(excluded.d_related, token_turns.d_related), level=COALESCE(excluded.level, token_turns.level), end_ts=COALESCE(excluded.end_ts, token_turns.end_ts)",
                                [object[]]@($t.file, $t.turn_ts, $t.project, $t.path, [long]$t.calls, [long]$t.submits, [long]$t.polls, [long]$t.out_tokens, $(if ($null -eq $t.d_tokens) { $null } else { [long]$t.d_tokens }), $(if ($null -eq $t.est_direct) { $null } else { [double]$t.est_direct }), $(if ($null -eq $t.est_delegate) { $null } else { [double]$t.est_delegate }), $t.choice, $t.choice_reason, $t.est_ver, $(if ($null -eq $t.cr_tokens) { $null } else { [long]$t.cr_tokens }), $(if ($null -eq $t.dur_sec) { $null } else { [long]$t.dur_sec }), $(if ($null -eq $t.est_time_direct) { $null } else { [long]$t.est_time_direct }), $(if ($null -eq $t.est_time_delegate) { $null } else { [long]$t.est_time_delegate }), $(if ($null -eq $t.calls_related) { $null } else { [long]$t.calls_related }), $(if ($null -eq $t.d_related) { $null } else { [long]$t.d_related }), $t.level, $t.end_ts)
                            )
                            if ($t.task_ids) {
                                foreach ($tid in $t.task_ids) {
                                    if ($tid) {
                                        [void]$db.Execute(
                                            "INSERT INTO token_task_links (task_id, file, turn_ts) VALUES (?, ?, ?) ON CONFLICT(task_id) DO NOTHING",
                                            [object[]]@($tid, $t.file, $t.turn_ts)
                                        )
                                    }
                                }
                            }
                            $totalTurnsAdded++
                        }
                        [void]$db.Execute(
                            "INSERT INTO token_files (path, offset, last_ctx) VALUES (?, ?, ?) ON CONFLICT(path) DO UPDATE SET offset=excluded.offset, last_ctx=excluded.last_ctx",
                            [object[]]@($fPath, [long]$scanResult.NewOffset, $(if ($null -eq $scanResult.LastCtx) { $null } else { [long]$scanResult.LastCtx }))
                        )
                    }
                }
            }

            # 이어서 시작한 세션이 앞 세션의 턴을 복사해 담아 겹친 줄을 정리한다(예상을 붙이기 전에 해서 한 줄에만 붙게 한다)
            try { Invoke-AgyDbTransaction $db { [void](Remove-DuplicateTurns $db) } } catch {}

            # 대화 기록에 작업 번호가 남지 않은 위임을 제출 시각에 진행 중이던 질문에 잇는다(그래야 위임 카드와 통계에 잡힌다)
            try { Invoke-AgyDbTransaction $db { [void](Add-OrphanTaskLinks $db) } } catch {}

            # 결정 시점에 기록한 예상(record-estimate.ps1)을 그 시각에 진행 중이던 턴에 붙인다
            # 새 기록만 붙인다. 파일을 처음부터 다시 읽어 행을 새로 만든 수집에서는 전부 다시 붙인다(예상 값은 최초 기록으로 고정이라 결과는 같다)
            try { Invoke-AgyDbTransaction $db { [void](Merge-RecordedEstimates $db -All:$mergeAll) } } catch {}

            # 규칙 8 로 올라올 때 한 번: 다시 읽지 않은 옛 행 중 위임 작업 연결이 하나도 없는 "위임" 행은 명령 글자만 보고 잘못 분류된 것이라 직접으로 고친다
            if ($fixOldDelegatePath) {
                try { [void]$db.Execute("UPDATE token_turns SET path = 'direct' WHERE path = 'delegate' AND calls > 0 AND NOT EXISTS (SELECT 1 FROM token_task_links l WHERE l.file = token_turns.file AND l.turn_ts = token_turns.turn_ts)", $null) } catch {}
            }

            # 기존 행 est_ver 채우기 (est 값은 있고 est_ver 가 NULL 인 행은 v1)
            [void]$db.Execute("UPDATE token_turns SET est_ver = 'v1' WHERE (est_ver IS NULL OR est_ver = '') AND (est_direct IS NOT NULL OR est_delegate IS NOT NULL)", $null)

            $countAfter = [int64]($db.Query("SELECT COUNT(*) AS c FROM token_turns", $null))[0]['c']
            $totalTurnsAdded = [int]($countAfter - $countBefore)

            $cal = Get-TokenCalibration -DbPath $DbPath -RuntimeDir $RuntimeDir
            $summary = "토큰 통계 갱신 완료: 파일 {0}개 확인({1}개 갱신), 새 턴 {2}개, 직접 a={3} b={4}(n={5}, {6}), 위임 a={7} b={8}(n={9}, {10})" -f $sessionFiles.Count, $filesProcessed, $totalTurnsAdded, $cal.direct.a, $cal.direct.b, $cal.direct.n, $cal.direct.source, $cal.delegate.a, $cal.delegate.b, $cal.delegate.n, $cal.delegate.source
            Write-Output $summary
        } finally {
            $db.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
}

function Show-TokenStatsReport {
    param(
        [string]$DbPath = "",
        [string]$RuntimeDir = ""
    )
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $DbPath) {
        $dataDir = if (Get-Command Get-AgyDataDir -CommandType Function -ErrorAction SilentlyContinue) {
            Get-AgyDataDir $RuntimeDir
        } else {
            $trimmed = $RuntimeDir.TrimEnd('\', '/')
            if ((Split-Path -Leaf $trimmed) -eq "runtime") { Join-Path (Split-Path $trimmed -Parent) "data" } else { Join-Path $trimmed "data" }
        }
        $DbPath = Join-Path $dataDir "delegate.db"
    }

    $cal = Get-TokenCalibration -DbPath $DbPath -RuntimeDir $RuntimeDir

    Write-Output "================================================================================"
    Write-Output "  토큰 예상·실측 보정 보고서 (최근 60일 기준)"
    Write-Output "================================================================================"
    Write-Output ("  직접 처리 : d ≈ {0} + {1} × calls  (표본 {2}개, {3})" -f $cal.direct.a, $cal.direct.b, $cal.direct.n, $(if ($cal.direct.source -eq 'measured') { '실측' } else { '기본값' }))
    Write-Output ("  agy 위임  : d ≈ {0} + {1} × calls  (표본 {2}개, {3})" -f $cal.delegate.a, $cal.delegate.b, $cal.delegate.n, $(if ($cal.delegate.source -eq 'measured') { '실측' } else { '기본값' }))
    Write-Output ""
    Write-Output "  예상 정확도 (선택 길의 예상 ÷ 실제 d, v2 기준):"
    $dirAcc = if ($null -ne $cal.estimate_accuracy.direct_ratio_median) { "{0:0.0}배" -f $cal.estimate_accuracy.direct_ratio_median } else { "-" }
    $delAcc = if ($null -ne $cal.estimate_accuracy.delegate_ratio_median) { "{0:0.0}배" -f $cal.estimate_accuracy.delegate_ratio_median } else { "-" }
    $v1Suffix = if ($cal.estimate_accuracy.v1_excluded_n -and $cal.estimate_accuracy.v1_excluded_n -gt 0) { " [옛 형식 {0}건(제외)]" -f $cal.estimate_accuracy.v1_excluded_n } else { "" }
    Write-Output ("    - 직접 선택: {0} / 위임 선택: {1} (전체 {2}건){3}" -f $dirAcc, $delAcc, $cal.estimate_accuracy.n, $v1Suffix)

    if ($null -ne $cal.time -and $null -ne $cal.time.direct) {
        Write-Output ("  시간 예상: 직접 ≈ {0}초 + {1}초 × calls (표본 {2}개, {3})" -f $cal.time.direct.a_s, $cal.time.direct.b_s, $cal.time.direct.n, $(if ($cal.time.direct.source -eq 'measured') { '실측' } else { '기본값' }))
    }
    Write-Output ""
    Write-Output "  최근 20턴 예상 대 실제:"
    Write-Output ("  {0,-16} {1,-12} {2,-8} {3,4} {4,8} {5,8} {6,8} {7,8} {8,8} {9,-8} {10,8} {11,8}" -f "시각", "프로젝트", "길", "호출", "재읽기", "A출력", "D증가", "예상직접", "예상위임", "선택", "활동시간", "예상시간")
    Write-Output ("  " + ("-" * 104))

    $db = Open-AgyDb $DbPath
    try {
        $recentRows = @($db.Query("SELECT turn_ts, project, path, calls, calls_related, cr_tokens, out_tokens, d_tokens, d_related, est_direct, est_delegate, choice, dur_sec, est_time_direct, est_time_delegate FROM token_turns ORDER BY turn_ts DESC LIMIT 20", $null))
        foreach ($r in $recentRows) {
            $ts = if ($r['turn_ts']) { [string]$r['turn_ts'] } else { "" }
            if ($ts.Length -gt 16) { $ts = $ts.Substring(0, 16) }
            $prj = if ($r['project']) { [string]$r['project'] } else { "" }
            if ($prj.Length -gt 12) { $prj = $prj.Substring(0, 12) }
            $pth = [string]$r['path']
            $cls = if ($pth -eq 'delegate' -and $r['calls_related'] -ne $null -and $r['calls_related'] -ne [DBNull]::Value) { [int]$r['calls_related'] } else { [int]$r['calls'] }
            $cr = if ($null -ne $r['cr_tokens'] -and $r['cr_tokens'] -ne [DBNull]::Value) { [string]$r['cr_tokens'] } else { "-" }
            $out = [int]$r['out_tokens']
            $dVal = if ($pth -eq 'delegate' -and $r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { $r['d_related'] } else { $r['d_tokens'] }
            $d = if ($null -ne $dVal -and $dVal -ne [DBNull]::Value) { [string]$dVal } else { "-" }
            $ed = if ($null -ne $r['est_direct'] -and $r['est_direct'] -ne [DBNull]::Value) { [string][int]$r['est_direct'] } else { "-" }
            $el = if ($null -ne $r['est_delegate'] -and $r['est_delegate'] -ne [DBNull]::Value) { [string][int]$r['est_delegate'] } else { "-" }
            $ch = if ($null -ne $r['choice'] -and $r['choice'] -ne [DBNull]::Value) { [string]$r['choice'] } else { "-" }
            $durStr = Format-DurationText $r['dur_sec']
            $estTimeVal = if ($ch -eq 'direct') { $r['est_time_direct'] } elseif ($ch -eq 'delegate') { $r['est_time_delegate'] } else { if ($null -ne $r['est_time_direct']) { $r['est_time_direct'] } else { $r['est_time_delegate'] } }
            $estTimeStr = Format-DurationText $estTimeVal

            Write-Output ("  {0,-16} {1,-12} {2,-8} {3,4} {4,8} {5,8} {6,8} {7,8} {8,8} {9,-8} {10,8} {11,8}" -f $ts, $prj, $pth, $cls, $cr, $out, $d, $ed, $el, $ch, $durStr, $estTimeStr)
        }

        $crPerCallStr = if ($null -ne $cal.context_reread_per_call) { ("{0} 토큰" -f $cal.context_reread_per_call) } else { "-" }
        Write-Output ("  호출당 캐시 재읽기 중앙값: {0}" -f $crPerCallStr)

        Write-Output ""
        Write-Output "  위임한 턴 최근 10개 (path=delegate):"
        $delTurns = @($db.Query("SELECT turn_ts, project, d_tokens, d_related, est_direct, est_delegate FROM token_turns WHERE path = 'delegate' AND (est_direct IS NOT NULL OR est_delegate IS NOT NULL) ORDER BY turn_ts DESC LIMIT 10", $null))
        if ($delTurns.Count -eq 0) {
            Write-Output "    아직 없음"
            Write-Output "  요약: 아직 없음"
        } else {
            $delRatios = New-Object System.Collections.ArrayList
            foreach ($r in $delTurns) {
                $ed = if ($null -ne $r['est_direct'] -and $r['est_direct'] -ne [DBNull]::Value) { [string][int]$r['est_direct'] } else { "-" }
                $el = if ($null -ne $r['est_delegate'] -and $r['est_delegate'] -ne [DBNull]::Value) { [string][int]$r['est_delegate'] } else { "-" }
                $dVal = if ($r['d_related'] -ne $null -and $r['d_related'] -ne [DBNull]::Value) { $r['d_related'] } else { $r['d_tokens'] }
                $d = if ($null -ne $dVal -and $dVal -ne [DBNull]::Value) { [string]$dVal } else { "-" }
                if ($null -ne $r['est_delegate'] -and $r['est_delegate'] -ne [DBNull]::Value -and $null -ne $dVal -and [double]$dVal -gt 0) {
                    [void]$delRatios.Add([double]$r['est_delegate'] / [double]$dVal)
                }
                Write-Output ("    예상 직접 {0} · 예상 위임 {1} · 실제(위임에 쓴 토큰) {2}" -f $ed, $el, $d)
            }
            $medStr = if ($delRatios.Count -gt 0) { "{0:0.0}배" -f [Math]::Round([double](Get-TokenMedian $delRatios), 1) } else { "-" }
            Write-Output ("  요약: {0}건, 선택한 길의 예상÷실제 중앙값 {1}" -f $delTurns.Count, $medStr)
        }

        Write-Output ""
        Write-Output "  직접 처리한 턴 최근 10개 (path=direct):"
        $dirTurns = @($db.Query("SELECT turn_ts, project, d_tokens, est_direct, est_delegate FROM token_turns WHERE path = 'direct' AND (est_direct IS NOT NULL OR est_delegate IS NOT NULL) ORDER BY turn_ts DESC LIMIT 10", $null))
        if ($dirTurns.Count -eq 0) {
            Write-Output "    아직 없음"
            Write-Output "  요약: 아직 없음"
        } else {
            $dirRatios = New-Object System.Collections.ArrayList
            foreach ($r in $dirTurns) {
                $ed = if ($null -ne $r['est_direct'] -and $r['est_direct'] -ne [DBNull]::Value) { [string][int]$r['est_direct'] } else { "-" }
                $el = if ($null -ne $r['est_delegate'] -and $r['est_delegate'] -ne [DBNull]::Value) { [string][int]$r['est_delegate'] } else { "-" }
                $d = if ($null -ne $r['d_tokens'] -and $r['d_tokens'] -ne [DBNull]::Value) { [string]$r['d_tokens'] } else { "-" }
                if ($null -ne $r['est_direct'] -and $r['est_direct'] -ne [DBNull]::Value -and $null -ne $r['d_tokens'] -and [double]$r['d_tokens'] -gt 0) {
                    [void]$dirRatios.Add([double]$r['est_direct'] / [double]$r['d_tokens'])
                }
                Write-Output ("    예상 직접 {0} · 예상 위임 {1} · 실제(직접 작업에 쓴 토큰) {2}" -f $ed, $el, $d)
            }
            $medStr = if ($dirRatios.Count -gt 0) { "{0:0.0}배" -f [Math]::Round([double](Get-TokenMedian $dirRatios), 1) } else { "-" }
            Write-Output ("  요약: {0}건, 선택한 길의 예상÷실제 중앙값 {1}" -f $dirTurns.Count, $medStr)
        }
    } finally {
        $db.Dispose()
    }
    Write-Output "================================================================================"
}

if ($Update) {
    Update-TokenStats -DbPath $DbPath -ProjectsDir $ProjectsDir -RuntimeDir $RuntimeDir
}
if ($Backfill) {
    Update-TokenStats -DbPath $DbPath -ProjectsDir $ProjectsDir -RuntimeDir $RuntimeDir -Backfill
}
if ($Report) {
    Show-TokenStatsReport -DbPath $DbPath -RuntimeDir $RuntimeDir
}
