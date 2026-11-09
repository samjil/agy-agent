# handoff-pump.ps1
# 핸드오프 "자동 이어가기"의 agy 쪽 펌프. watch-agy.ps1 의 메인 루프가 몇 초마다 Invoke-HandoffPump 을 부른다(dot-source 해서 씀).
#
# 하는 일
#   1) 채널(~/.samjil/handoff/<프로젝트>)의 원장에서 Claude 가 보낸(c2a) 새 메시지(상태 '보냄')를 찾아
#      agy 위임 지시파일(inbox)로 만든다. 상태는 '읽음'으로 바꾼다.
#   2) 그 위임이 끝나면(outbox 에 응답이 생기면) agy 의 최종 답변을 회신 메시지(a2c)로 채널에 기록하고
#      원래 메시지를 '처리됨'으로 바꾼다. 실패하면 '보류' + 실패 알림 회신을 남긴다.
#   Claude 쪽은 이 회신을 Stop 훅(handoff-stop-hook.ps1)이 보고 같은 세션에서 이어 간다.
#
# 안전장치 (사용자와 정한 값)
#   - 기본 켜짐. 채널 폴더의 AUTO.off(또는 채널 루트의 AUTO.off)가 있으면 그 채널(전체)을 건드리지 않는다.
#   - 한 대화 줄기의 왕복 한도: 최근 60분 안에 위임 6회(AGY_HANDOFF_MAX_ROUNDS). 넘으면 멈추고 AUTO.json 에
#     halted 를 적는다(뷰어가 "사용자 확인 필요"로 보여 준다). 한도 창이 지나거나 사용자가 초기화하면 다시 돈다.
#   - 최근 AGY_HANDOFF_MAX_AGE_HOURS(기본 2)시간 안에 쓴 메시지만 처리한다. 쌓여 있던 옛 '보냄' 메시지를 갑자기 실행하지 않는다.
#   - 한 채널에서는 한 번에 하나만 위임한다(같은 agy 대화를 동시에 만지지 않게).
#   - agy 가 직접 회신 파일을 썼으면(규약대로) 그것을 두고 중복 회신을 쓰지 않는다.
# 이 파일의 함수는 호출하는 쪽이 정의한 Log 함수가 있으면 로그를 남긴다(handoff-lib.ps1 의 Write-HandoffLog).

# 채널 이름을 작업 ID·세션 이름에 쓸 수 있는 글자로.
function ConvertTo-HandoffSafeName([string]$Name) {
    $s = [regex]::Replace([string]$Name, '[^A-Za-z0-9가-힣_-]+', '-').Trim('-')
    if (-not $s) { $s = "channel" }
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    return $s
}

# 메시지 머리말의 `위임모델:` 값을 모델 단계로 해석한다. low|medium|high 또는 gemini-3.8-flash-low|medium|high 만 받는다.
# 자동 단계 선택(agy-autotier.ps1)은 코드 블록·번호 단계·검증 명령이 든 잘 쓴 명세를 "복잡한 일"로 보고 high 로 보내는데,
# 명세가 이미 정해진 구현이면 보내는 쪽(Claude)이 단계를 직접 정할 수 있게 한다. 값이 없거나 모르는 값이면 $null(자동 선택으로 넘어간다).
# 반환: @{ Tier; Model; Reason } ($Auto 와 같은 모양)
function Get-HandoffModelOverride([string]$Value) {
    $v = ([string]$Value).Trim().ToLowerInvariant()
    if (-not $v) { return $null }
    $tier = ""
    $model = ""
    if ($v -match '^(low|medium|high)$') { $tier = $v; $model = "gemini-3.8-flash-$v" }
    elseif ($v -match '^gemini-3\.8-flash-(low|medium|high)$') { $tier = $Matches[1]; $model = $v }
    else { return $null }
    return @{ Tier = $tier; Model = $model; Reason = "메시지 머리말 위임모델: $($Value.Trim())" }
}

# 협의(핸드오프)의 기본 모델 단계. 협의는 정확도와 성능이 목적이라 자동 선택(짧은 확인은 low)을 쓰지 않고 기본을 high 로 둔다.
# 환경변수 AGY_HANDOFF_MODEL: low|medium|high|gemini-3.8-flash-* 이면 그 값, `auto` 면 $null(자동 선택으로 넘어간다), 없으면 high.
# 메시지 머리말의 `위임모델:` 은 이 기본값보다 우선한다. 알 수 없는 값은 high 로 본다.
# 반환: @{ Tier; Model; Reason } 또는 $null (자동 선택)
function Get-HandoffDefaultModel {
    $v = ([string]$env:AGY_HANDOFF_MODEL).Trim()
    if ($v.ToLowerInvariant() -eq "auto") { return $null }
    if (-not $v) { $v = "high" }
    $m = Get-HandoffModelOverride $v
    if (-not $m) { $m = Get-HandoffModelOverride "high" }
    $m.Reason = "협의 기본 단계 $($m.Tier) (AGY_HANDOFF_MODEL 로 바꿈, auto 면 자동 선택)"
    return $m
}

function Get-HandoffMaxAgeHours {
    if ($env:AGY_HANDOFF_MAX_AGE_HOURS -match '^\d+(\.\d+)?$' -and [double]$env:AGY_HANDOFF_MAX_AGE_HOURS -gt 0) { return [double]$env:AGY_HANDOFF_MAX_AGE_HOURS }
    return 2.0
}

# 채널의 agy 대화(@session) 이름. agy 대화는 시작할 때의 모델을 유지하므로, 낮은 단계(low/medium)는 단계별로 대화를 따로 둔다.
# high 는 예전과 같은 이름(handoff-<채널>)이라 이미 있는 대화를 그대로 이어 쓴다. 단계가 다르면 대화가 이어지지 않지만,
# 이전 메시지는 채널 폴더(INDEX.md, msg\)에 있어 agy 가 읽을 수 있다.
function Get-HandoffSessionName([string]$SafeChannel, $Auto = $null, [string]$Tier = "") {
    if (-not $Tier -and $Auto) { $Tier = [string]$Auto.Tier }
    if ($Tier -eq "low" -or $Tier -eq "medium") { return "handoff-$SafeChannel-$Tier" }
    return "handoff-$SafeChannel"
}

# 지시파일 맨 위 @session/@cwd 지시어 + 본문. 본문에는 이번 메시지 전문을 담아 agy 가 파일을 못 읽어도 처리할 수 있게 한다.
function New-HandoffDispatchText([string]$ChannelName, [string]$ChannelDir, [string]$RepoPath, $Row, [string]$MsgPath, [string]$MsgText, $Auto = $null) {
    $safe = ConvertTo-HandoffSafeName $ChannelName
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("@session: $(Get-HandoffSessionName $safe $Auto)")
    # 낮은 단계(low/medium)로 자동 선택했으면 그 모델을 지정한다. high 는 지정하지 않아 기본 우선순위(쿼터 초과 때 폴백)를 그대로 쓴다.
    if ($Auto -and [string]$Auto.Tier -ne "high" -and [string]$Auto.Model) { [void]$lines.Add("@model: $($Auto.Model)") }
    # @raw 를 쓰지 않는다: 워처가 표준 규칙(DO NOT COMMIT · 포그라운드 실행 · 필요한 파일만 수정 · 한글 답변, agy-rules.ps1)을 이 지시문 끝에 붙인다.
    # 핸드오프 agy 는 저장소 폴더를 열고 소스를 고치므로 위임 때와 같은 안전 규칙이 필요하다. 이 지시문이 이미 같은 뜻의 문장을 담고 있으면 그 규칙만 건너뛴다.
    [void]$lines.Add("@cwd: $ChannelDir")
    if ($RepoPath) { [void]$lines.Add("@cwd: $RepoPath") }
    $body = [string]$MsgText
    if ($body.Length -gt 12000) { $body = $body.Substring(0, 12000) + "`n`n(... 이하 생략: 전문은 위 메시지 파일에 있습니다)" }
    $repoLine = if ($RepoPath) { "저장소 $RepoPath 에서 직접 처리하세요." } else { "저장소 경로를 알 수 없습니다. BRIEF.md 를 보고, 그래도 모르면 작업하지 말고 [사용자 확인 필요] 로 물어보세요." }
    $text = @"
samjil-handoff 채널 '$ChannelName' 의 agy 로서, Claude 가 보낸 메시지 #$($Row.Num) "$($Row.Title)" 를 처리해 주세요.
(자동 이어가기입니다. 당신의 최종 답변이 그대로 회신 메시지가 되어 Claude 에게 전달되고, Claude 는 그것을 읽고 이어서 답하거나 사용자에게 보고합니다.)

## 이번 메시지 ($MsgPath)

$body

## 처리 방법

1. 프로젝트 맥락은 $ChannelDir\BRIEF.md 에 있습니다(필요하면 읽으세요). 이전 대화는 같은 폴더의 INDEX.md 와 msg\ 에 있습니다.
2. 요청한 작업이 있으면 $repoLine
3. 확인하지 않은 것을 확인했다고 쓰지 마세요. 빌드·테스트 같은 상태는 실제로 돌려 본 출력만 적고, 실측값에는 산식을 함께 적으세요.
4. 회신 메시지 파일과 INDEX.md 는 직접 만들거나 고치지 마세요. 워처가 당신의 최종 답변을 회신 메시지로 저장합니다.
5. 최종 답변은 이 형식으로 쓰세요.

   ## 요약
   - 무엇을 했나 / 무엇이 문제인가 (한 줄)
   - 어디를 고쳤나 (파일:줄)
   - 어떻게 검증했나
   - 화면/동작에서 확인할 것 (한 줄)

   ---

   (이하 근거·상세)

6. 요구가 모호하거나 사용자가 정해야 하는 것이 있으면 작업을 멈추고, 최종 답변의 첫 줄에 [사용자 확인 필요] 와 질문을 적으세요. 이때는 Claude 가 사용자에게 물어야 합니다.
7. 화면을 확인해야 하는 일이면 브라우저 도구(chrome-devtools-mcp: 페이지 열기·스크린샷·DOM 스냅샷)로 로컬 화면을 직접 열어 1차 확인·실측하고, 확인한 값과 사용자가 교차 확인할 곳을 "화면에서 확인할 것"에 적으세요.
"@
    [void]$lines.Add($text)
    return (($lines.ToArray()) -join "`n")
}

# 위임 기록 DB(tasks 표)에서 이 작업의 사용량 행(가장 먼저 쓴 것). 없으면 $null.
function Get-HandoffUsageRow([string]$DbPath, [string]$TaskId) {
    if (-not $DbPath) { return $null }
    try { return (Get-QaTaskRow $DbPath $TaskId) } catch { return $null }
}

function Get-HandoffSessionModel([string]$DbPath, [string]$SessionName) {
    if (-not $DbPath -or -not $SessionName) { return "" }
    try {
        $s = Get-AgySession $DbPath $SessionName
        if ($s -and $s.model -and [string]$s.model -ne "(session)") { return [string]$s.model }
    } catch {}
    return ""
}

# agy 답변 -> 회신 본문. BOM 과 agy 가 스스로 붙인 머리말(--- ... ---)을 떼고, "## 요약"이 없으면 안내 요약을 앞에 붙인다.
function ConvertTo-HandoffReplyBody([string]$Response) {
    $t = ([string]$Response).TrimStart([char]0xFEFF).Trim()
    if ($t.StartsWith("---")) {
        $m = [regex]::Match($t, '^---\s*\r?\n.*?\r?\n---\s*\r?\n', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) { $t = $t.Substring($m.Length).Trim() }
    }
    if (-not $t) { $t = "(agy 가 빈 답변을 돌려줬습니다)" }
    if ($t -notmatch '(?m)^##\s*요약') {
        $t = "## 요약`n`n- 자동 회신: agy 의 최종 답변 전문입니다(요약 블록 없이 도착해 그대로 옮겼습니다).`n`n---`n`n" + $t
    }
    return $t
}

function Test-HandoffRecentRow($Row, [double]$MaxAgeHours) {
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Row.Time, [ref]$t)) { return $false }
    return ($t -ge (Get-Date).AddHours(-$MaxAgeHours))
}

# agy 가 규약대로 직접 회신 파일을 썼는가: 위임 이후에 생긴 a2c 행 중 머리말의 답장대상이 이 번호인 것.
function Test-HandoffAgyAlreadyReplied([string]$ChannelDir, [string]$Num) {
    foreach ($r in @(Read-HandoffIndex $ChannelDir)) {
        if ($r.Dir -ne "a2c" -or [int]$r.Num -le [int]$Num) { continue }
        $f = Get-HandoffMessageFile $ChannelDir $r.Num
        if (-not $f) { continue }
        $h = Read-HandoffFrontMatter $f.FullName
        if ($h["답장대상"] -eq $Num -and $h["자동"] -ne "예") { return $true }
    }
    return $false
}

# 위임 하나가 끝났을 때 채널에 결과를 적는다. 끝나지 않았으면 $false.
function Complete-HandoffDispatch([string]$ChannelDir, $Disp, $Ctx) {
    $taskId = [string]$Disp.task_id
    $num = [string]$Disp.num
    $respPath = Join-Path $Ctx.OutboxDir "$taskId.response.md"
    $errPath = Join-Path $Ctx.OutboxDir "$taskId.error.log"
    $started = [datetime]::MinValue
    [void][datetime]::TryParse([string]$Disp.at, [ref]$started)

    $hasResp = (Test-Path -LiteralPath $respPath -PathType Leaf)
    $hasErr = (Test-Path -LiteralPath $errPath -PathType Leaf)
    $usage = Get-HandoffUsageRow $Ctx.DbPath $taskId
    $age = if ($started -ne [datetime]::MinValue) { ((Get-Date) - $started).TotalHours } else { 0 }

    if (-not $hasResp -and -not $hasErr) {
        if ($age -lt 3) { return $false }
        $failure = "agy 가 3시간이 지나도록 답하지 않아 자동 이어가기를 포기했습니다. 워처가 꺼져 있었거나 지시파일이 지워졌을 수 있습니다."
        $respText = ""
    } else {
        # 응답 파일이 usage 행보다 먼저 생긴다. 행이 곧 쓰이니 잠깐(60초) 기다린다.
        if ($hasResp -and -not $usage -and -not $hasErr) {
            $respAge = ((Get-Date) - (Get-Item -LiteralPath $respPath).LastWriteTime).TotalSeconds
            if ($respAge -lt 60) { return $false }
        }
        $respText = ""
        if ($hasResp) { try { $respText = [System.IO.File]::ReadAllText($respPath, [System.Text.Encoding]::UTF8) } catch { $respText = "" } }
        $failure = $null
        if ($usage -and [string]$usage.status -eq "ERROR") {
            $failure = if ($respText.Trim()) { $respText.Trim() } else { "agy 실행이 실패했습니다." }
        } elseif ($hasErr -and -not $hasResp) {
            $failure = try { ([System.IO.File]::ReadAllText($errPath, [System.Text.Encoding]::UTF8)).Trim() } catch { "agy 실행 오류" }
        }
    }

    $origRow = @(Read-HandoffIndex $ChannelDir | Where-Object { $_.Num -eq $num }) | Select-Object -First 1
    $origTitle = if ($origRow) { [string]$origRow.Title } else { "" }
    $replyTitleBase = ($origTitle -replace '^(Re:\s*)+', '').Trim()

    if ($failure) {
        $body = "## 요약`n`n- agy 자동 처리에 실패했습니다 (메시지 #$num).`n- 사유는 아래에 있습니다. 같은 요청을 다시 보내거나 사용자에게 알려 주세요.`n- 자동 이어가기는 이 메시지에서 멈춥니다.`n`n---`n`n$failure"
        $model = if ($usage -and [string]$usage.model -ne "(session)") { [string]$usage.model } else { "" }
        $newNum = Add-HandoffMessage $ChannelDir "a2c" ("자동 처리 실패: " + $replyTitleBase) $body $num $model $true "보냄"
        [void](Set-HandoffStatus $ChannelDir $num "보류")
        Write-HandoffLog "핸드오프 [$(Split-Path -Leaf $ChannelDir)] #$num 자동 처리 실패 -> 보류, 알림 회신 #$newNum"
        return $true
    }

    if (Test-HandoffAgyAlreadyReplied $ChannelDir $num) {
        [void](Set-HandoffStatus $ChannelDir $num "처리됨")
        Write-HandoffLog "핸드오프 [$(Split-Path -Leaf $ChannelDir)] #$num agy 가 직접 회신을 남겨 중복 회신을 쓰지 않았습니다"
        return $true
    }

    $model = ""
    if ($usage -and [string]$usage.model -and [string]$usage.model -ne "(session)") { $model = [string]$usage.model }
    if (-not $model) { $model = Get-HandoffSessionModel $Ctx.DbPath (Get-HandoffSessionName (ConvertTo-HandoffSafeName (Split-Path -Leaf $ChannelDir)) $null ([string]$Disp.tier)) }
    $newNum = Add-HandoffMessage $ChannelDir "a2c" ("Re: " + $replyTitleBase) (ConvertTo-HandoffReplyBody $respText) $num $model $true "보냄"
    if (-not $newNum) {
        Write-HandoffLog "핸드오프 [$(Split-Path -Leaf $ChannelDir)] #$num 회신 메시지를 쓰지 못했습니다(다음 점검 때 다시 시도)"
        return $false
    }
    [void](Set-HandoffStatus $ChannelDir $num "처리됨")
    Write-HandoffLog "핸드오프 [$(Split-Path -Leaf $ChannelDir)] #$num 처리 -> 회신 #$newNum (모델: $(if ($model) { $model } else { '미확인' }))"
    return $true
}

# 채널 하나를 점검한다.
function Invoke-HandoffPumpChannel([string]$ChannelDir, $Ctx) {
    if (Test-HandoffAutoDisabled $ChannelDir) { return }
    $name = Split-Path -Leaf $ChannelDir
    $state = Read-HandoffAutoState $ChannelDir
    $maxRounds = Get-HandoffMaxRounds

    # 1) 진행 중인 위임이 끝났는지
    $inFlight = $null
    foreach ($d in @($state.dispatches)) {
        if (-not $d -or $d.done) { continue }
        $finished = $false
        try { $finished = Complete-HandoffDispatch $ChannelDir $d $Ctx } catch { Write-HandoffLog "핸드오프 [$name] 완료 처리 오류: $($_.Exception.Message)" }
        if ($finished) {
            $script:__hpNum = [string]$d.num
            Update-HandoffAutoState $ChannelDir {
                param($s)
                foreach ($x in @($s.dispatches)) { if ($x -and [string]$x.num -eq $script:__hpNum) { $x.done = $true } }
            }
        } else { $inFlight = $d }
    }
    if ($inFlight) { return }   # 한 채널에서는 한 번에 하나만

    # 2) 새 메시지
    $state = Read-HandoffAutoState $ChannelDir
    if ($state.halted) {
        # 한도 창이 지났으면 자동으로 다시 시작(대화 줄기 한도로 멈춘 것은 시간이 지나도 풀리지 않는다. 뷰어의 "한도 초기화"로 푼다)
        if ($state.halted_reason -notlike "대화 줄기*" -and (Get-HandoffRounds $state $script:HandoffAutoWindowMinutes) -lt $maxRounds) {
            Update-HandoffAutoState $ChannelDir { param($s) $s.halted = $false; $s.halted_at = ""; $s.halted_reason = "" }
            Write-HandoffLog "핸드오프 [$name] 한도 창이 지나 자동 이어가기를 다시 시작합니다"
            $state = Read-HandoffAutoState $ChannelDir
        } else { return }
    }
    $maxAge = Get-HandoffMaxAgeHours
    $pending = @(Read-HandoffIndex $ChannelDir | Where-Object { $_.Dir -eq "c2a" -and $_.Status -eq "보냄" -and (Test-HandoffRecentRow $_ $maxAge) })
    foreach ($row in $pending) {
        $known = @(@($state.dispatches) | Where-Object { $_ -and [string]$_.num -eq $row.Num })
        if ($known.Count -gt 0) { [void](Set-HandoffStatus $ChannelDir $row.Num "읽음"); continue }   # 이미 위임했는데 상태가 안 바뀐 것을 바로잡는다

        if ((Get-HandoffRounds $state $script:HandoffAutoWindowMinutes) -ge $maxRounds) {
            $script:__hpMax = $maxRounds
            Update-HandoffAutoState $ChannelDir {
                param($s)
                $s.halted = $true
                $s.halted_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                $s.halted_reason = "자동 왕복 한도($($script:__hpMax)회/$($script:HandoffAutoWindowMinutes)분)에 도달해 멈췄습니다. 사용자 확인이 필요합니다."
            }
            Write-HandoffLog "핸드오프 [$name] 자동 왕복 한도($maxRounds회)에 도달해 멈춥니다. #$($row.Num) 는 보냄 상태로 둡니다"
            return
        }

        $threadMax = Get-HandoffMaxThreadRounds
        if ((Get-HandoffThreadRounds $ChannelDir $state $row.Num) -ge $threadMax) {
            $script:__hpThreadMax = $threadMax
            Update-HandoffAutoState $ChannelDir {
                param($s)
                $s.halted = $true
                $s.halted_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                $s.halted_reason = "대화 줄기 왕복 한도($($script:__hpThreadMax)회)에 도달해 멈췄습니다. 사용자 확인이 필요합니다."
            }
            Write-HandoffLog "핸드오프 [$name] 대화 줄기 왕복 한도($threadMax회)에 도달해 멈춥니다. #$($row.Num) 는 보냄 상태로 둡니다"
            return
        }

        $msgFile = Get-HandoffMessageFile $ChannelDir $row.Num
        $msgText = if ($msgFile) { try { [System.IO.File]::ReadAllText($msgFile.FullName, [System.Text.Encoding]::UTF8) } catch { "" } } else { "" }
        if (-not $msgText) { $msgText = "(메시지 파일 msg\$($row.Num)-*.md 를 읽지 못했습니다. 제목만 보고 판단하지 말고 파일을 직접 읽으세요.)" }
        $repo = Get-HandoffRepoPath $ChannelDir
        # 메시지 내용(제목 + 본문)으로 노력 단계를 자동 선택한다. 채널은 늘 폴더를 열므로 폴더 있음으로 본다(파일을 바꾸는 일이면 high).
        # 메시지 머리말에 `위임모델:` 이 있으면 자동 선택보다 그것을 따른다(자동 선택을 꺼 둔 때도 명시한 값은 따른다).
        $auto = $null
        if ($msgFile) {
            try {
                $overrideRaw = [string](Read-HandoffFrontMatter $msgFile.FullName)["위임모델"]
                $auto = Get-HandoffModelOverride $overrideRaw
                if (-not $auto -and $overrideRaw.Trim()) { Write-HandoffLog "핸드오프 [$name] #$($row.Num) 머리말의 위임모델 '$overrideRaw' 은(는) low|medium|high 또는 gemini-3.8-flash-<단계> 가 아니라서 무시하고 자동 선택합니다" }
            } catch { $auto = $null }
        }
        if (-not $auto) { $auto = Get-HandoffDefaultModel }   # 머리말이 없으면 협의 기본 단계(high). auto 로 두면 아래 자동 선택
        if (-not $auto -and (Get-Command Test-AgyAutoTierEnabled -ErrorAction SilentlyContinue) -and (Test-AgyAutoTierEnabled)) {
            try { $auto = Get-AgyAutoTier ("$($row.Title)`n$msgText") $true } catch { $auto = $null }
        }
        $text = New-HandoffDispatchText $name $ChannelDir $repo $row $(if ($msgFile) { $msgFile.FullName } else { "" }) $msgText $auto

        $taskId = "handoff_{0}_{1}_{2}" -f (ConvertTo-HandoffSafeName $name), $row.Num, (Get-Date -Format "HHmmss")
        $taskPath = Join-Path $Ctx.InboxDir "$taskId.md"
        try {
            New-Item -ItemType Directory -Force -Path $Ctx.InboxDir | Out-Null
            [System.IO.File]::WriteAllText($taskPath, $text, (New-Object System.Text.UTF8Encoding($false)))
        } catch {
            Write-HandoffLog "핸드오프 [$name] #$($row.Num) 위임 지시파일을 쓰지 못했습니다: $($_.Exception.Message)"
            return
        }
        $script:__hpNum = [string]$row.Num; $script:__hpTask = $taskId; $script:__hpTier = if ($auto) { [string]$auto.Tier } else { "" }
        Update-HandoffAutoState $ChannelDir {
            param($s)
            $s.dispatches = @(@($s.dispatches) + @(@{ num = $script:__hpNum; task_id = $script:__hpTask; at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); done = $false; tier = $script:__hpTier }))
        }
        [void](Set-HandoffStatus $ChannelDir $row.Num "읽음")
        Write-HandoffLog "핸드오프 [$name] #$($row.Num) '$($row.Title)' -> agy 에게 위임 ($taskId)$(if ($repo) { '' } else { ' [저장소 경로를 몰라 채널 폴더만 엽니다]' })$(if ($auto) { " [모델 자동 선택: $($auto.Tier) - $($auto.Reason)]" })"
        return    # 한 번에 하나
    }
}

# 모든 채널을 점검한다. 호출하는 쪽(워처)이 몇 초 간격으로 부른다. 어떤 오류도 밖으로 내보내지 않는다.
function Invoke-HandoffPump($Ctx) {
    try {
        foreach ($dir in @(Get-HandoffChannelDirs)) {
            try { Invoke-HandoffPumpChannel $dir $Ctx } catch { Write-HandoffLog "핸드오프 펌프 오류 [$(Split-Path -Leaf $dir)]: $($_.Exception.Message)" }
        }
    } catch {}
}
