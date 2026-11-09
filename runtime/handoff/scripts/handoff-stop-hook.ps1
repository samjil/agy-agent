# handoff-stop-hook.ps1
# Claude Code 의 Stop 훅. Claude 가 턴을 끝내려 할 때 핸드오프 채널을 보고 "자동 이어가기"를 한다.
#   1) agy 가 회신(a2c, 상태 '보냄')을 남겨 두었으면: 턴을 끝내지 않고(decision: block) 그 회신을 처리하라고 알린다.
#      -> 사용자가 "메시지 확인해줘"라고 말하지 않아도 같은 세션에서 이어서 처리한다.
#   2) 방금(기본 10분 안에) Claude 가 agy 에게 메시지(c2a)를 보냈고 agy 가 아직 답하지 않았으면: 회신이 올 때까지
#      (기본 30분) 기다렸다가 오면 1)처럼 이어 간다. agy 쪽은 워처(핸드오프 펌프)가 자동으로 처리한다.
#   3) 그 밖에는 아무 일도 하지 않는다(턴이 그대로 끝난다).
# 훅 입력(stdin, JSON): cwd, session_id, stop_hook_active ... 출력(stdout): 비우거나 {"decision":"block","reason":...} / {"systemMessage":...}
# 어떤 오류가 나도 조용히 끝낸다 — 훅이 사용자의 세션을 막으면 안 된다.
#
# 등록: install.ps1 -HandoffAutoHook (register-handoff-hook.ps1 이 ~/.claude/settings.json 의 hooks.Stop 에 넣는다).
# 끄기: 채널 폴더(또는 채널 루트)에 AUTO.off 파일을 둔다. 한도(왕복 6회/60분)와 안전장치는 handoff-pump.ps1 머리말 참고.
#
# stop_hook_active 는 보지 않는다: 이 훅은 새 agy 회신이 있을 때만 막고(회신은 유한하다), 같은 회신은 최대 2번까지만 막고
# 넘어가며, 펌프가 왕복 한도를 지켜 무한히 이어질 수 없다.
#
# 같은 채널을 세션 둘 이상이 함께 쓸 수 있다(저장소 하나에 Claude 창이 여럿). 그래서 Claude 가 쓴 c2a 에 `세션:`(그 세션의 ID)을 적어 두고,
# agy 회신은 그 c2a 를 쓴 세션에게만 알린다(주인이 없거나 주인 세션이 한 시간 넘게 조용하면 아무 세션이나 받는다).
#
# 조절용 환경변수: SAMJIL_HANDOFF_WAIT_SECONDS(기본 1800) · SAMJIL_HANDOFF_SENT_WITHIN_MINUTES(기본 10) ·
#   SAMJIL_HANDOFF_UNREAD_HOURS(기본 6) · SAMJIL_HANDOFF_MAX_BLOCKS(같은 회신당, 기본 2) · SAMJIL_HANDOFF_POLL_SECONDS(기본 3) ·
#   SAMJIL_HANDOFF_DEBUG=1 (오류를 stderr 로 보여 준다)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8 } catch {}

function Get-EnvNumber([string]$Name, [double]$Default) {
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v -match '^\d+(\.\d+)?$' -and [double]$v -gt 0) { return [double]$v }
    return $Default
}
function Write-HookJson($Obj) {
    $json = $Obj | ConvertTo-Json -Compress -Depth 5
    $bytes = $utf8.GetBytes($json)
    $out = [Console]::OpenStandardOutput()
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}
function Test-WatcherAliveForHook {
    $rt = $env:AGY_DELEGATE_RUNTIME
    if (-not $rt) {
        $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
        $rt = Join-Path $home_ ".samjil/delegate-agy/runtime"
    }
    $hbDir = Join-Path $rt "heartbeat"
    if (-not (Test-Path -LiteralPath $hbDir -PathType Container)) { return $false }
    $hb = @(Get-ChildItem -LiteralPath $hbDir -Filter "hb_*.txt" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($hb.Count -eq 0) { return $false }
    return (((Get-Date) - $hb[0].LastWriteTime).TotalSeconds -le 300)
}
# 대화 기록(transcript_path, JSONL)의 끝에서 가장 최근 assistant 메시지의 모델 ID 와 노력 단계(그 줄의 effort. 이번 턴만 다르게 준 값 perTurnEffort 가 있으면 그것)를 읽는다.
# 반환: @{ Model; Effort }. 못 읽으면 둘 다 "". (노력은 대화 기록 줄에 effort 로 남는다: Claude Code 2.1.x 에서 확인)
function Get-TranscriptModelInfo([string]$TranscriptPath) {
    $none = @{ Model = ""; Effort = "" }
    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) { return $none }
    $fs = [System.IO.File]::Open($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $take = [long][math]::Min($fs.Length, 262144)
        [void]$fs.Seek($fs.Length - $take, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]$take)
        $got = 0
        while ($got -lt $take) {
            $n = $fs.Read($buf, $got, [int]$take - $got)
            if ($n -le 0) { break }
            $got += $n
        }
        $text = $utf8.GetString($buf, 0, $got)
    } finally { $fs.Dispose() }
    $lines = $text -split "`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i]
        if ($l.IndexOf('"model"') -lt 0) { continue }
        try { $o = $l | ConvertFrom-Json } catch { continue }       # 잘린 첫 줄 등
        $m = ""
        if ($o -and $o.message -and $o.message.model) { $m = [string]$o.message.model }
        if ($m -and $m -notlike "<*" -and $m -like "claude*") {
            $eff = ""
            if ($o.PSObject.Properties["perTurnEffort"] -and $o.perTurnEffort -is [string] -and $o.perTurnEffort.Trim()) { $eff = $o.perTurnEffort.Trim() }
            elseif ($o.PSObject.Properties["effort"] -and $o.effort -is [string] -and $o.effort.Trim()) { $eff = $o.effort.Trim() }
            return @{ Model = $m; Effort = $eff }
        }
    }
    return $none
}
function Test-WithinMinutes($Row, [double]$Minutes) {
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Row.Time, [ref]$t)) { return $false }
    return ($t -ge (Get-Date).AddMinutes(-$Minutes))
}

# 대화 기록 끝부분의 글자(찾아볼 용도). 못 읽으면 "".
function Get-TranscriptTailText([string]$TranscriptPath, [long]$MaxBytes) {
    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) { return "" }
    try {
        $fs = [System.IO.File]::Open($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $take = [long][math]::Min($fs.Length, $MaxBytes)
            [void]$fs.Seek($fs.Length - $take, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ([int]$take)
            $got = 0
            while ($got -lt $take) {
                $n = $fs.Read($buf, $got, [int]$take - $got)
                if ($n -le 0) { break }
                $got += $n
            }
            return $utf8.GetString($buf, 0, $got)
        } finally { $fs.Dispose() }
    } catch { return "" }
}

try {
    # 입력은 UTF-8 로 직접 읽는다(콘솔 입력 코드페이지로 읽으면 한글 경로가 깨진다)
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, $utf8)
    $raw = $reader.ReadToEnd()
    $in = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { $null }
    if (-not $in -or -not $in.cwd) { exit 0 }

    . (Join-Path $PSScriptRoot "handoff-lib.ps1")
    $ch = Resolve-HandoffChannelForCwd ([string]$in.cwd) ([string]$in.session_id)
    if (-not $ch) { exit 0 }
    if (Test-HandoffAutoDisabled $ch) { exit 0 }
    $name = Split-Path -Leaf $ch

    $waitSeconds = Get-EnvNumber "SAMJIL_HANDOFF_WAIT_SECONDS" 1800
    $sentWithin = Get-EnvNumber "SAMJIL_HANDOFF_SENT_WITHIN_MINUTES" 10
    $unreadHours = Get-EnvNumber "SAMJIL_HANDOFF_UNREAD_HOURS" 6
    $maxBlocks = [int](Get-EnvNumber "SAMJIL_HANDOFF_MAX_BLOCKS" 2)
    $poll = [int](Get-EnvNumber "SAMJIL_HANDOFF_POLL_SECONDS" 3)

    # Claude 가 쓴 c2a 에 모델·노력이 비어 있으면(쓸 때 빼먹은 경우) 이 세션의 모델과 노력 단계를 머리말에 적어 둔다 — 뷰어가 "Claude Sonnet 5.5 (High)" 로 보여 주는 근거.
    # 최근 15분 안에 보낸 것만 대상으로 해 다른 세션의 옛 메시지를 잘못 찍지 않는다.
    # 같은 채널을 쓰는 다른 세션이 쓴 c2a 에는 도장을 찍지 않는다: 이 세션의 대화 기록 끝부분에 그 파일 이름이 있을 때만(= 이 세션이 쓴 것) 찍는다.
    # 같은 때 `세션:` 도 적는다. 먼저 적은 쪽이 주인이다(쓴 세션의 턴이 끝날 때 이 훅이 가장 먼저 돈다).
    $sid = [string]$in.session_id
    $transcriptPath = [string]$in.transcript_path
    $stampInfo = Get-TranscriptModelInfo $transcriptPath
    $tailText = ""
    foreach ($r in @(Read-HandoffIndex $ch)) {
        if ($r.Dir -ne "c2a" -or -not (Test-WithinMinutes $r 15)) { continue }
        $f = Get-HandoffMessageFile $ch $r.Num
        if (-not $f) { continue }
        if (-not $sid) { continue }
        $owner = [string](Read-HandoffFrontMatter $f.FullName)["세션"]
        if (-not $owner) {
            if (-not $tailText) { $tailText = Get-TranscriptTailText $transcriptPath 1048576 }
            if ($tailText -and $tailText.Contains($f.Name)) { [void](Set-HandoffMessageField $f.FullName "세션" $sid); $owner = $sid }
        }
        if ($owner -eq $sid -and $stampInfo.Model) { [void](Set-HandoffMessageModel $f.FullName $stampInfo.Model $stampInfo.Effort) }
    }

    # 이 c2a 의 주인이 이 세션(또는 주인 없음)인가. 주인이 다른 세션이어도 그 세션의 대화 기록이 한 시간 넘게 멈춰 있거나 없으면 아무나 받는다(세션을 닫았을 때 회신이 묻히지 않게).
    function Test-OwnedByMeOrNobody([string]$Owner) {
        if (-not $Owner -or -not $sid -or $Owner -eq $sid) { return $true }
        if (-not $transcriptPath) { return $true }
        $other = Join-Path (Split-Path -Parent $transcriptPath) ($Owner + ".jsonl")
        if (-not (Test-Path -LiteralPath $other -PathType Leaf)) { return $true }
        return ((Get-Item -LiteralPath $other).LastWriteTime -lt (Get-Date).AddMinutes(-60))
    }
    function Get-RowOwner($Row) {
        $f = Get-HandoffMessageFile $ch $Row.Num
        if (-not $f) { return "" }
        return [string](Read-HandoffFrontMatter $f.FullName)["세션"]
    }
    # agy 회신(a2c)의 주인은 그 회신이 답한 c2a(답장대상)의 주인이다.
    function Test-ReplyIsMine($Row) {
        $f = Get-HandoffMessageFile $ch $Row.Num
        if (-not $f) { return $true }
        $to = [string](Read-HandoffFrontMatter $f.FullName)["답장대상"]
        if (-not $to) { return $true }
        $cf = Get-HandoffMessageFile $ch $to
        if (-not $cf) { return $true }
        return (Test-OwnedByMeOrNobody ([string](Read-HandoffFrontMatter $cf.FullName)["세션"]))
    }

    # agy 가 남긴 읽지 않은 회신(최근 것만, 같은 회신을 maxBlocks 번보다 더 막지 않는다)
    function Get-UnreadReplies {
        $state = Read-HandoffAutoState $ch
        $out = @()
        foreach ($r in @(Read-HandoffIndex $ch)) {
            if ($r.Dir -ne "a2c" -or $r.Status -ne "보냄") { continue }
            $t = [datetime]::MinValue
            if (-not [datetime]::TryParse([string]$r.Time, [ref]$t) -or $t -lt (Get-Date).AddHours(-$unreadHours)) { continue }
            $blocks = 0
            if ($state.hook_blocks.ContainsKey([string]$r.Num)) { $blocks = [int]$state.hook_blocks[[string]$r.Num] }
            if ($blocks -ge $maxBlocks) { continue }
            if (-not (Test-ReplyIsMine $r)) { continue }
            $out += $r
        }
        return @($out)
    }

    function Send-Block($unread) {
        $lines = @()
        foreach ($r in $unread) {
            $f = Get-HandoffMessageFile $ch $r.Num
            $path = if ($f) { $f.FullName } else { "(msg\$($r.Num)-*.md)" }
            $lines += ("- #{0} ({1}) {2}`n  파일: {3}" -f $r.Num, $r.Time, $r.Title, $path)
        }
        $reason = @"
핸드오프 채널 '$name' 에 agy 가 회신을 남겼습니다. 사용자가 "메시지 확인해줘"라고 말하지 않아도 지금 바로 이어서 처리하세요.

$($lines -join "`n")

처리 규칙 (samjil-handoff 스킬):
1. 위 메시지를 읽기 전에 $ch\INDEX.md 에서 그 메시지의 상태를 '읽음'으로 바꿉니다(그 줄의 상태 칸만 고치고 원장을 통째로 다시 쓰지 않습니다).
2. 메시지를 읽고 필요한 작업을 합니다. agy 가 고쳤다고 한 것은 실제로 확인한 뒤에 믿으세요. 끝나면 상태를 '처리됨'(직접 반영) 또는 '확인함'(검증만)으로 바꿉니다.
3. agy 에게 더 시킬 일이 있으면 새 메시지(c2a)를 쓰세요(머리말에 답장대상과 모델: 을 적습니다). 그러면 agy 가 자동으로 이어받고, 이 세션은 다음 회신이 올 때까지 기다렸다가 이어서 처리합니다.
4. 더 시킬 일이 없거나, 회신이 [사용자 확인 필요]로 시작하거나, 판단이 갈리는 일이면 agy 에게 보내지 말고 사용자에게 결과를 보고한 뒤 끝내세요.
5. 같은 내용을 되풀이해 주고받지 마세요. 자동 왕복은 60분에 6회까지입니다.
"@
        $reason = $reason -replace "`r`n", "`n"      # 이 파일의 줄바꿈(CRLF)이 사유에 섞이지 않게
        Update-HandoffAutoState $ch {
            param($s)
            foreach ($r in $script:__hkUnread) {
                $k = [string]$r.Num
                $n = 0
                if ($s.hook_blocks.ContainsKey($k)) { $n = [int]$s.hook_blocks[$k] }
                $s.hook_blocks[$k] = $n + 1
            }
        }
        Write-HookJson @{ decision = "block"; reason = $reason }
    }

    # 1) 이미 도착한 회신
    $unread = @(Get-UnreadReplies)
    if ($unread.Count -gt 0) { $script:__hkUnread = $unread; Send-Block $unread; exit 0 }

    # 2) 방금 보낸 메시지에 대한 회신 기다리기
    $waiting = @(Read-HandoffIndex $ch | Where-Object { $_.Dir -eq "c2a" -and ($_.Status -eq "보냄" -or $_.Status -eq "읽음") -and (Test-WithinMinutes $_ $sentWithin) -and (Test-OwnedByMeOrNobody (Get-RowOwner $_)) })
    if ($waiting.Count -eq 0) { exit 0 }
    $st = Read-HandoffAutoState $ch
    if ($st.halted) {
        Write-HookJson @{ systemMessage = "핸드오프 '$name': $($st.halted_reason) agy 에게 보낸 메시지는 대기 중입니다. 뷰어에서 확인하고 한도를 초기화하세요." }
        exit 0
    }
    if (-not (Test-WatcherAliveForHook)) {
        Write-HookJson @{ systemMessage = "핸드오프 '$name': agy 워처가 꺼져 있어(하트비트 없음) 회신을 기다리지 않습니다. start-agy.ps1 로 워처를 켜면 자동으로 이어집니다." }
        exit 0
    }
    $deadline = (Get-Date).AddSeconds($waitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $poll
        if (Test-HandoffAutoDisabled $ch) { exit 0 }
        $unread = @(Get-UnreadReplies)
        if ($unread.Count -gt 0) { $script:__hkUnread = $unread; Send-Block $unread; exit 0 }
        $st = Read-HandoffAutoState $ch
        if ($st.halted) {
            Write-HookJson @{ systemMessage = "핸드오프 '$name': $($st.halted_reason)" }
            exit 0
        }
    }
    Write-HookJson @{ systemMessage = "핸드오프 '$name': agy 회신이 $([math]::Round($waitSeconds / 60))분 안에 오지 않아 기다리기를 멈춥니다. 회신이 오면 뷰어에서 확인하거나 '메시지 확인해줘'라고 말해 주세요." }
    exit 0
} catch {
    # 조용히 끝낸다. 왜 안 되는지 볼 때만 SAMJIL_HANDOFF_DEBUG=1 로 오류를 stderr 에 낸다.
    if ($env:SAMJIL_HANDOFF_DEBUG) { [Console]::Error.WriteLine(($_ | Out-String)) }
    exit 0
}
