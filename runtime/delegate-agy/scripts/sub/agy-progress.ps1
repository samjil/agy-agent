# agy-progress.ps1
# watch-agy.ps1이 agy 호출 하나를 기다리는 동안 "아직 일하는 중인가, 멈췄는가"를 판단하는
# 헬퍼 모음입니다. dot-source해서 씁니다: `. (Join-Path $PSScriptRoot "agy-progress.ps1")`
#
# 왜 필요한가:
#   예전에는 호출 하나에 고정 600초 마감만 있었습니다. 그런데 저장소 여러 개를 가로지르는
#   검토 같은 작업은 정상적으로도 10분 넘게 걸리고(120~145단계), 마감에 걸리면 이미 끝낸
#   결과(결과 파일까지 써 둔 것)도 실패로 기록되고 버려졌습니다. 그래서 절대 마감을 늘리고,
#   대신 "새 단계가 계속 기록되는지"로 멈춤을 따로 판정합니다.
#
# 신호:
#   agy는 단계를 하나 끝낼 때마다 대화 기록을 씁니다(확인: 진행 중인 작업의 기록 파일에
#   방금 끝난 단계가 이미 들어 있음). 이 파일들의 마지막 수정 시각을 "마지막 활동"으로 봅니다.
#     <AgyHome>\conversations\<id>.db
#     <AgyHome>\brain\<id>\.system_generated\logs\transcript_full.jsonl
#   CPU 사용량은 신호로 쓸 수 없습니다. 모델 응답을 기다리는 동안 agy는 거의 놀기 때문입니다
#   (실측: 작업 중인데 10초에 CPU 0.1초).
#
# 멈춤 기준(워처의 $AgyStallSeconds)의 근거:
#   정상 작업에서 새 단계 사이가 가장 길게 비었던 것은 113초였습니다(5건, 약 640단계 관찰).
#   관찰이 5건뿐이라 이보다 오래 조용한 정상 작업이 없다고 보장하지는 못합니다.
#   실제로 5.4분(324초) 동안 새 단계가 없어 끊은 적이 있다(2026-10-14 22:25). 마지막 단계는 도구 결과였지만 agy 의 자체 로그(cli-*.log)에는
#   그 뒤 모델 요청이 하나도 없어서, 그 건은 agy 가 실제로 멈춘 것이었다(끊은 게 맞다). 끊을 때 마지막 단계를 로그에 남기고(Get-AgyLastStepSummary),
#   기준은 환경변수 AGY_STALL_SECONDS(기본 300)로 바꿀 수 있게 했다.
#   반대로 오탐은 따로 있었다: 오래 걸리는 명령을 agy 가 백그라운드로 돌려 두고 기다리는 동안은 새 단계가 없다(7분짜리 명령을 5분 시점에 끊는 것을
#   재현). 그래서 "끝났다는 알림이 아직 없는 백그라운드 도구"가 있으면 멈춤으로 보지 않는다(Get-AgyPendingBackgroundTasks).
#
# 대화를 못 찾거나 어느 것인지 모호하면 멈춤 판정을 하지 않습니다(절대 마감만 적용).
# 멀쩡히 일하는 작업을 잘못 끊는 쪽이 이 개선이 막으려던 바로 그 피해이기 때문입니다.

# agy가 대화/기록을 저장하는 루트. agy가 저장 위치를 바꾸면 AGY_HOME 으로 지정할 수 있습니다.
function Get-AgyHomeDir {
    if ($env:AGY_HOME) { return $env:AGY_HOME }
    return (Join-Path $env:USERPROFILE ".gemini\antigravity-cli")
}

# agy 인자 목록에서 `--conversation <id>`의 id를 꺼냅니다(이어가기 호출). 없으면 $null.
function Get-AgyConversationIdFromArgs($agyArgs) {
    $list = @($agyArgs)
    for ($i = 0; $i -lt ($list.Count - 1); $i++) {
        if ($list[$i] -eq '--conversation') { return [string]$list[$i + 1] }
    }
    return $null
}

# 이번 호출이 만든 대화를 찾습니다. 반환: @{ State = ...; Id = ... }
#   found       - 찾음(Id 사용 가능). 이어가기 호출이면 이미 아는 id를 그대로 씁니다.
#   none        - 시작 이후 새로 생긴 대화가 아직 없음(조금 더 기다려 볼 수 있음)
#   ambiguous   - 시작 직후 창 안에 대화가 둘 이상 생겨 어느 것인지 알 수 없음
#   unavailable - 대화 폴더 자체가 없음(agy 저장 방식이 바뀌었을 수 있음)
# 새 대화는 호출을 시작한 시각 직후 WindowSeconds 안에 만들어진 것만 후보로 봅니다
# (실측: 시작 후 약 7초 안에 생김). 그보다 늦게 생긴 다른 agy 대화는 무시합니다.
# 대화 기록 맨 앞(첫 질문 줄)에 표식 글이 들어 있는가. 기록이 아직 없거나 읽을 수 없으면 $false.
function Test-AgyConversationHasMarker($AgyHome, [string]$Id, [string]$Marker) {
    if (-not $Marker) { return $false }
    $path = Get-AgyTranscriptPath $AgyHome $Id
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $buf = New-Object byte[] ([int][Math]::Min(16384, $fs.Length))
        $n = $fs.Read($buf, 0, $buf.Length)
        return ([System.Text.Encoding]::UTF8.GetString($buf, 0, $n)).Contains($Marker)
    } catch { return $false } finally { if ($fs) { $fs.Dispose() } }
}

# Marker: 이 호출의 질문에만 들어 있는 글(프롬프트 파일 이름, 또는 지시문 첫머리). 여러 작업이 동시에 새 대화를 시작해
# 후보가 둘 이상일 때, 대화 기록 맨 앞에 이 표식이 든 대화를 내 것으로 고른다(딱 하나일 때만).
function Resolve-AgyConversation($AgyHome, $KnownId, [datetime]$StartedAt, [int]$WindowSeconds = 120, [string]$Marker = "") {
    $convDir = Join-Path $AgyHome "conversations"
    if (-not (Test-Path -LiteralPath $convDir -PathType Container)) {
        return @{ State = 'unavailable'; Id = $null }
    }
    if ($KnownId) { return @{ State = 'found'; Id = [string]$KnownId } }

    $from = $StartedAt.AddSeconds(-2)
    $to   = $StartedAt.AddSeconds($WindowSeconds)
    $candidates = @(Get-ChildItem -LiteralPath $convDir -Filter '*.db' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -ge $from -and $_.CreationTime -le $to })

    if ($candidates.Count -eq 1) { return @{ State = 'found'; Id = $candidates[0].BaseName } }
    if ($candidates.Count -gt 1 -and $Marker) {
        $mine = @($candidates | Where-Object { Test-AgyConversationHasMarker $AgyHome $_.BaseName $Marker })
        if ($mine.Count -eq 1) { return @{ State = 'found'; Id = $mine[0].BaseName } }
    }
    if ($candidates.Count -gt 1) { return @{ State = 'ambiguous'; Id = $null } }
    return @{ State = 'none'; Id = $null }
}

# 그 대화의 마지막 활동 시각(대화 DB와 기록 파일 중 더 늦은 수정 시각). 파일이 없으면 $null.
function Get-AgyConversationActivity($AgyHome, $Id) {
    $paths = @(
        (Join-Path $AgyHome "conversations\$Id.db"),
        (Join-Path $AgyHome "brain\$Id\.system_generated\logs\transcript_full.jsonl")
    )
    $latest = $null
    foreach ($p in $paths) {
        $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if ($item -and (($null -eq $latest) -or ($item.LastWriteTime -gt $latest))) {
            $latest = $item.LastWriteTime
        }
    }
    return $latest
}

# agy 가 "백그라운드 작업"으로 돌려 둔 도구 중 아직 끝났다는 알림이 없는 것의 목록(작업 ID 들). 없으면 빈 배열.
# 오래 걸리는 명령(빌드·시험·긴 대기 등)은 agy 가 10초쯤 기다리다 백그라운드로 넘기고, 그 명령이 끝날 때까지 새 단계를 하나도 쓰지 않고 기다린다.
# 이때는 멈춘 것이 아니므로 멈춤 판정에서 빼야 한다. 실제로 7분 걸리는 명령을 돌리던 정상 작업이 5분 시점에 "멈춤"으로 끊긴 것을 재현했다.
# 대화 기록(transcript_full.jsonl)에 agy 가 직접 남기는 짝으로 판단한다(여러 대화의 기록에서 시작:끝 건수가 거의 1:1 임을 확인):
#   시작: "status":"RUNNING" 단계의 글에 "Tool is running as a background task with task id: <대화 ID>/task-N"
#   끝:   SYSTEM_MESSAGE 단계의 글에 "sender=<대화 ID>/task-N ... finished with result: ..."
# 시작은 있는데 같은 task-N 의 끝이 아직 없으면 "도는 중"이다. 도는 중인 명령이 영영 안 끝나는 경우는 절대 마감(AgyTimeoutSeconds)이 끊는다.
function Get-AgyPendingBackgroundTasks($AgyHome, $Id) {
    $tp = Get-AgyTranscriptPath $AgyHome $Id
    if (-not $tp -or -not (Test-Path -LiteralPath $tp)) { return @() }
    $started = [ordered]@{}
    $finished = @{}
    try {
        $fs = New-Object System.IO.FileStream($tp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            while (($line = $sr.ReadLine()) -ne $null) {
                if ($line.IndexOf('"status":"RUNNING"', [System.StringComparison]::Ordinal) -ge 0 -or $line -match '"status"\s*:\s*"RUNNING"') {
                    if ($line -match 'Tool is running as a background task with task id: ([A-Za-z0-9-]+/task-\d+)') { $started[$Matches[1]] = $true }
                } elseif ($line.IndexOf('SYSTEM_MESSAGE', [System.StringComparison]::Ordinal) -ge 0) {
                    foreach ($m in [regex]::Matches($line, 'sender=([A-Za-z0-9-]+/task-\d+)')) { $finished[$m.Groups[1].Value] = $true }
                }
            }
        } finally { $fs.Dispose() }
    } catch { return @() }
    $pending = @()
    foreach ($k in $started.Keys) { if (-not $finished.ContainsKey($k)) { $pending += $k } }
    return @($pending)
}

# 멈춤으로 판정했을 때 남길 진단: 대화 기록의 마지막 단계가 무엇이었는가.
# "새 단계가 안 쌓인다"만으로는 agy 가 정말 멈췄는지, 모델이 긴 응답을 만드는 중인지, 도구(오래 걸리는 명령)가 도는 중인지 가릴 수 없다.
# 마지막 단계의 모양으로 짐작만 해서 로그에 남긴다(판정에는 쓰지 않는다):
#   도구를 부르는 모델 응답(PLANNER_RESPONSE + tool_calls)이 마지막   -> 'tool-running'    그 도구가 아직 도는 중일 수 있다
#   도구 결과·사용자 입력 같은 다른 단계가 마지막                       -> 'model-generating' 모델 응답을 기다리는 중이거나 agy 가 멈춘 것일 수 있다(어제 사례는 agy 의 로그에 다음 모델 요청이 아예 없었다)
#   도구 없이 끝난 모델 응답이 마지막                                   -> 'model-finishing'
# 마지막 줄이 아주 클 수 있어(긴 응답) 줄 전체를 JSON 으로 읽지 않고 필요한 글자만 정규식으로 뽑는다.
# 반환: @{ Index; Type; Status; Tools = @(도구 이름); Hint } 또는 읽을 수 없으면 $null.
function Get-AgyLastStepSummary($AgyHome, $Id) {
    $tp = Get-AgyTranscriptPath $AgyHome $Id
    if (-not $tp -or -not (Test-Path -LiteralPath $tp)) { return $null }
    $text = $null
    try {
        $fs = New-Object System.IO.FileStream($tp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            if ($len -le 0) { return $null }
            $take = [int][Math]::Min([long]1048576, $len)
            [void]$fs.Seek($len - $take, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $take
            $got = 0
            while ($got -lt $take) { $n = $fs.Read($buf, $got, $take - $got); if ($n -le 0) { break }; $got += $n }
            $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $got)
        } finally { $fs.Dispose() }
    } catch { return $null }
    $lines = @($text -split "\r?\n" | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) { return $null }
    # 파일 끝에서 쓰는 중이라 줄이 끊겨 있을 수 있으니, 단계 번호가 읽히는 가장 마지막 줄을 쓴다
    $line = $null
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '"step_index"\s*:\s*\d+') { $line = $lines[$i]; break }
    }
    if (-not $line) { return $null }
    $idx = $null; if ($line -match '"step_index"\s*:\s*(\d+)') { $idx = [int]$Matches[1] }
    $type = ""; if ($line -match '"type"\s*:\s*"([A-Z_]+)"') { $type = $Matches[1] }
    $status = ""; if ($line -match '"status"\s*:\s*"([A-Z_]+)"') { $status = $Matches[1] }
    $tools = @()
    $tc = $line.IndexOf('"tool_calls"', [System.StringComparison]::Ordinal)
    if ($tc -ge 0) {
        foreach ($m in [regex]::Matches($line.Substring($tc), '"name"\s*:\s*"([A-Za-z0-9_]+)"')) { $tools += $m.Groups[1].Value }
    }
    $hint = 'model-generating'
    if ($type -eq 'PLANNER_RESPONSE') { $hint = $(if ($tools.Count -gt 0) { 'tool-running' } else { 'model-finishing' }) }
    return @{ Index = $idx; Type = $type; Status = $status; Tools = @($tools); Hint = $hint }
}

# 위 요약을 로그 한 줄로 만든다. 요약이 없으면 빈 문자열.
function Format-AgyLastStep($Summary) {
    if ($null -eq $Summary) { return "" }
    $hintText = switch ($Summary.Hint) {
        'tool-running'     { "도구가 아직 도는 중일 수 있음" }
        'model-generating' { "모델 응답을 기다리는 중이거나 agy 가 멈춘 것일 수 있음" }
        'model-finishing'  { "모델이 응답을 마무리하는 중일 수 있음" }
        default            { "" }
    }
    $toolText = if (@($Summary.Tools).Count -gt 0) { " 도구: " + (@($Summary.Tools) -join ",") } else { "" }
    return ("마지막 단계 #{0} {1} {2}{3} ({4})" -f $Summary.Index, $Summary.Type, $Summary.Status, $toolText, $hintText).Trim()
}

# agy 가 최종 응답까지 대화 기록에 남겼는데 프로세스가 끝나지 않아(실측: 응답 완료 뒤 5분 넘게 안 끝남) 멈춤으로 끊게 되는 경우를 위해,
# 대화 기록의 마지막 단계가 "도구 호출이 없는 모델 응답(PLANNER_RESPONSE, DONE)"이면 그 내용을 돌려준다. 그 응답이 곧 답이다.
# 마지막 단계가 그게 아니거나(도구 호출이 붙음, 아직 RUNNING, 뒤에 다른 단계가 있음), 내용이 비었거나, 줄이 끊겨 읽을 수 없으면 $null.
# 반환: @{ Text = <응답 전문>; Index = <단계 번호> } 또는 $null.
function Get-AgyFinalResponse($AgyHome, $Id, [int]$MaxBytes = 8388608) {
    $tp = Get-AgyTranscriptPath $AgyHome $Id
    if (-not $tp -or -not (Test-Path -LiteralPath $tp)) { return $null }
    $text = $null
    try {
        $fs = New-Object System.IO.FileStream($tp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            $take = [int][Math]::Min([long]$MaxBytes, $len)
            [void]$fs.Seek($len - $take, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $take
            $got = 0
            while ($got -lt $take) { $n = $fs.Read($buf, $got, $take - $got); if ($n -le 0) { break }; $got += $n }
            $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $got)
        } finally { $fs.Dispose() }
    } catch { return $null }
    # 마지막 줄만 본다. 요약 함수(Get-AgyLastStepSummary)는 파일 끝 1MB 만 읽어서 아주 긴 마지막 줄을 못 보고 앞 단계를 마지막으로 착각할 수 있다.
    $lines = @($text -split "\r?\n" | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) { return $null }
    try { $o = $lines[$lines.Count - 1] | ConvertFrom-Json } catch { return $null }
    if ($null -eq $o -or [string]$o.type -ne 'PLANNER_RESPONSE' -or [string]$o.status -ne 'DONE') { return $null }
    if (@($o.tool_calls | Where-Object { $null -ne $_ }).Count -gt 0) { return $null }
    $content = [string]$o.content
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }
    return @{ Text = $content; Index = [int]$o.step_index }
}
# 환경변수에서 "초" 설정을 읽는다. 없거나 숫자가 아니거나 최솟값보다 작으면 기본값. (워처의 마감·멈춤 기준을 환경변수로 바꿀 수 있게 하는 곳이다.)
function Get-AgySecondsSetting([string]$EnvName, [int]$Default, [int]$Min) {
    $v = [Environment]::GetEnvironmentVariable($EnvName)
    if ($v -match '^\d{1,9}$' -and [int64]$v -ge $Min) { return [int]$v }
    return $Default
}

# 프로세스와 그 모든 자손이 지금까지 쓴 CPU 시간(초)의 합. 모델 응답을 기다리는 동안 agy 는 거의 놀지만, 도구(빌드·시험 등)가 도는 동안에는
# 자손 프로세스가 CPU 를 쓴다. 두 시점의 차이로 "지금 뭔가 하고 있는가"를 본다.
function Get-AgyTreeCpuSeconds([int]$RootPid) {
    $kids = @{}
    foreach ($p in @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue)) {
        $pp = [int]$p.ParentProcessId
        if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object System.Collections.ArrayList }
        [void]$kids[$pp].Add([int]$p.ProcessId)
    }
    $seen = @{}
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($RootPid)
    $total = 0.0
    while ($queue.Count -gt 0) {
        $id = [int]$queue.Dequeue()
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        try { $total += (Get-Process -Id $id -ErrorAction Stop).TotalProcessorTime.TotalSeconds } catch {}
        if ($kids.ContainsKey($id)) { foreach ($c in $kids[$id]) { $queue.Enqueue($c) } }
    }
    return $total
}

# 그 대화의 백그라운드 도구 로그 파일(brain\<id>\.system_generated\tasks\*.log)이 마지막으로 바뀐 시각. 없으면 $null.
# 도구가 출력을 내는 동안에는 이 파일이 자란다.
function Get-AgyTaskLogActivity($AgyHome, $Id) {
    $tp = Get-AgyTranscriptPath $AgyHome $Id
    if (-not $tp) { return $null }
    $dir = Join-Path (Split-Path (Split-Path $tp -Parent) -Parent) "tasks"
    $latest = $null
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.log" -File -ErrorAction SilentlyContinue)) {
        if (($null -eq $latest) -or ($f.LastWriteTime -gt $latest)) { $latest = $f.LastWriteTime }
    }
    return $latest
}

# 절대 마감(AgyTimeoutSeconds)을 넘긴 호출이 "진짜 일하는 중인가, 멈춘 것인가". 반환: @{ Alive; Reason(일하는 근거); Note(멈췄다고 볼 때의 설명) }
# 아래 중 하나라도 최근 WindowSeconds 안에 있으면 일하는 중이다:
#   1) 대화 기록·DB 에 새 단계가 기록됨  2) 백그라운드 도구의 로그 파일이 바뀜  3) agy 와 자손 프로세스가 CPU 를 일정량(기본: 창의 1%, 최소 1초) 이상 씀
# 전부 없으면 멈춘 것이다. CPU 표본(CpuSamples: @{ At; Cpu } 목록)의 앞쪽 기록이 아직 창만큼 쌓이지 않았으면 판단하지 않고 "일하는 중"으로 둔다(근거 없이 끊지 않는다).
# 한계: 30분 넘게 출력도 CPU 도 쓰지 않고 가만히 기다리는 명령(예: 아주 긴 sleep)은 멈춘 것과 구별할 수 없어 멈춘 것으로 본다.
function Test-AgyAliveAtCap($AgyHome, $ConvId, [datetime]$Now, [int]$WindowSeconds, $CpuSamples, [double]$MinCpuSeconds = 0) {
    # CPU 를 얼마나 써야 "일하는 중"인가: 기본은 창 길이의 1%(최소 1초). 5분 창이면 3초 - 빌드·시험이면 훨씬 많이 쓰고, 멈춘 agy 와 유휴 MCP 서버는 거의 안 쓴다.
    # (창 없이 숨겨 띄운 프로세스는 Windows 가 CPU 를 아껴 써서 코어 하나를 다 쓰는 반복문도 실제로는 25% 쯤만 쓴다 - 시험에서 확인.)
    if ($MinCpuSeconds -le 0) { $MinCpuSeconds = [Math]::Max(1.0, 0.01 * $WindowSeconds) }
    if ($ConvId) {
        $act = Get-AgyConversationActivity $AgyHome $ConvId
        if ($act -and (($Now - $act).TotalSeconds -lt $WindowSeconds)) {
            return @{ Alive = $true; Reason = ("{0}초 전에 새 단계가 기록됨" -f [int]($Now - $act).TotalSeconds); Note = "" }
        }
        $tl = Get-AgyTaskLogActivity $AgyHome $ConvId
        if ($tl -and (($Now - $tl).TotalSeconds -lt $WindowSeconds)) {
            return @{ Alive = $true; Reason = ("{0}초 전에 백그라운드 도구가 출력을 냄" -f [int]($Now - $tl).TotalSeconds); Note = "" }
        }
    }
    $samples = @($CpuSamples)
    if ($samples.Count -lt 2) { return @{ Alive = $true; Reason = "활동 이력이 아직 모자라 확인을 더 모음"; Note = "" } }
    $last = $samples[$samples.Count - 1]
    $base = $null
    foreach ($s in $samples) { if (($last.At - $s.At).TotalSeconds -ge $WindowSeconds) { $base = $s } }
    if ($null -eq $base) { return @{ Alive = $true; Reason = "활동 이력이 아직 모자라 확인을 더 모음"; Note = "" } }
    $delta = [double]$last.Cpu - [double]$base.Cpu
    if ($delta -ge $MinCpuSeconds) {
        return @{ Alive = $true; Reason = ("최근 {0}초 동안 CPU 를 {1:N1}초 사용" -f $WindowSeconds, $delta); Note = "" }
    }
    return @{ Alive = $false; Reason = ""; Note = ("최근 {0}초 동안 새 단계·도구 로그·CPU 활동이 모두 없어" -f $WindowSeconds) }
}

# 멈췄는가: 마지막 활동(없으면, 또는 호출 시작보다 옛날이면 호출 시작 시각)으로부터
# StallSeconds 이상 지났으면 $true. 이어가기 호출은 대화 파일이 이미 옛날 것일 수 있어서
# 호출 시작 시각을 하한으로 둡니다.
function Test-AgyStalled($LastActivity, [datetime]$StartedAt, [datetime]$Now, [int]$StallSeconds) {
    $ref = $StartedAt
    if (($null -ne $LastActivity) -and ($LastActivity -gt $ref)) { $ref = $LastActivity }
    return (($Now - $ref).TotalSeconds -ge $StallSeconds)
}

# RootPid 의 자손 프로세스 중 이름이 ProcessName 인 것의 PID 목록.
# 시간 초과로 끊을 때 "이번 호출이 띄운 agy"만 정확히 가리기 위해 씁니다. 이름만으로 고르면
# 이 워처와 상관없는 다른 agy(사용자가 직접 띄운 것, 다른 워처의 것)까지 죽일 수 있습니다.
function Get-DescendantProcessIdsByName([int]$RootPid, [string]$ProcessName = "agy") {
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $parentOf = @{}
    foreach ($p in $all) { $parentOf[[int]$p.ProcessId] = [int]$p.ParentProcessId }
    $hits = @()
    foreach ($p in $all) {
        if ($p.Name -ne "$ProcessName.exe") { continue }
        $cur = [int]$p.ParentProcessId
        for ($depth = 0; ($depth -lt 32) -and ($cur -gt 0); $depth++) {
            if ($cur -eq $RootPid) { $hits += [int]$p.ProcessId; break }
            if (-not $parentOf.ContainsKey($cur)) { break }
            $cur = $parentOf[$cur]
        }
    }
    return $hits
}

# 프로세스와 그 자식 프로세스(agy가 띄운 MCP 서버 등)를 함께 종료합니다.
function Stop-ProcessTree([int]$ProcessId) {
    try {
        & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
    } catch {}
    # taskkill 이 못 죽였으면(권한 등) 마지막 수단으로 본체만이라도 종료
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

# ---------------------------------------------------------------------------------------------------------------
# 과정(agy 가 부른 도구 목록) 읽기
#   위임 카드의 "지금:" 줄, "과정" 구역, 기록(QA)에 저장하는 과정이 모두 이 함수들을 씁니다.
#   뷰어(serve-viewer.ps1)도 이 파일을 불러 와서 같은 코드를 씁니다.
# ---------------------------------------------------------------------------------------------------------------

# agy 도구 호출 하나가 "무엇을 어디에" 하는지 짧은 글로 만듭니다. 화면의 "지금:" 줄에서 영어 라벨(toolAction)만으로는
# 알 수 없는 실제 내용(어떤 명령, 어떤 파일, 어떤 폴더)을 보여 주기 위한 것입니다.
# 도구마다 인자 이름이 달라서 도구별로 고릅니다(agy 대화 기록 131개, 도구 호출 2,287건에서 나온 12종).
function Get-AgyToolDetail($call) {
    if ($null -eq $call -or $null -eq $call.args) { return "" }
    $a = $call.args
    $n = [string]$call.name
    $get = { param($k) $x = $a.$k; if ($null -eq $x) { "" } else { ([string]$x).Trim() } }
    $d = ""
    switch ($n) {
        'run_command'          { $d = & $get 'CommandLine' }
        'view_file' {
            $d = & $get 'AbsolutePath'
            if (-not $d) { $d = & $get 'Path' }
            $sl = & $get 'StartLine'; $el = & $get 'EndLine'
            if ($sl -and $el) { $d += " ($sl~${el}행)" }
        }
        'read_file' {
            $d = & $get 'Path'
            if (-not $d) { $d = & $get 'AbsolutePath' }
        }
        'write_to_file'        { $d = & $get 'TargetFile'; if (-not $d) { $d = & $get 'Path' } }
        'write_file'           { $d = & $get 'Path'; if (-not $d) { $d = & $get 'TargetFile' } }
        'replace_file_content' { $d = & $get 'TargetFile'; if (-not $d) { $d = & $get 'Path' } }
        'list_dir'             { $d = & $get 'DirectoryPath' }
        'find_by_name' {
            $d = & $get 'Pattern'
            $dir = & $get 'SearchDirectory'
            if ($dir) { $d += " ($dir)" }
        }
        'grep_search' {
            $d = & $get 'Query'
            $dir = & $get 'SearchPath'
            if ($dir) { $d += " ($dir)" }
        }
        'search_web'           { $d = & $get 'query' }
        'read_url_content'     { $d = & $get 'Url' }
        'manage_task' {
            $act = & $get 'Action'
            $actKo = switch -Regex ($act) {
                '^(?i:status)$'    { '상태 확인' }
                '^(?i:kill|stop)$' { '중단' }
                default            { $act }
            }
            $tid = & $get 'TaskId'
            $no = if ($tid -match 'task-(\d+)') { "#" + $Matches[1] } elseif ($tid) { $tid } else { "" }
            $d = ($actKo + " " + $no).Trim()
        }
        'schedule' {
            $sec = & $get 'DurationSeconds'; $pr = & $get 'Prompt'
            $d = $(if ($sec) { "${sec}초" } else { "" })
            if ($pr) { $d = ($d + " · " + $pr).Trim(' ', '·') }
        }
        'generate_image'       { $d = & $get 'ImageName' }
        'call_mcp_tool' {
            # 서버 이름만으로는 무엇을 했는지 알 수 없어 "도구 이름 + 핵심 인자"를 보인다(예: navigate_page url=http://localhost:5173/demo/#/select).
            $d = & $get 'ToolName'
            if (-not $d) { $d = & $get 'ServerName' }
            $mcpArgs = $a.Arguments
            if ($null -ne $mcpArgs -and $mcpArgs -isnot [string]) {
                $kv = @()
                foreach ($prop in $mcpArgs.PSObject.Properties) {
                    $v = $prop.Value
                    if ($null -eq $v -or $v -is [bool] -and -not $v) { continue }
                    $s = if ($v -is [string] -or $v -is [ValueType]) { [string]$v } else { ($v | ConvertTo-Json -Compress -Depth 3) }
                    $s = ($s -replace '\s+', ' ').Trim()
                    if ($s.Length -gt 80) { $s = $s.Substring(0, 80) + "…" }
                    if ($s) { $kv += ("{0}={1}" -f $prop.Name, $s) }
                    if ($kv.Count -ge 3) { break }
                }
                if ($kv.Count) { $d = ($d + " " + ($kv -join " ")).Trim() }
            }
        }
        default {
            # 모르는 도구: 라벨이 아닌 첫 문자열 인자를 대상으로 본다
            foreach ($prop in $a.PSObject.Properties) {
                if ($prop.Name -in @('toolAction', 'toolSummary')) { continue }
                if ($prop.Value -is [string] -and $prop.Value.Trim()) { $d = $prop.Value.Trim(); break }
            }
        }
    }
    $d = ($d -replace '\s+', ' ').Trim()
    if ($d.Length -gt 200) { $d = $d.Substring(0, 200) + "…" }
    return $d
}

# 대화 id 로 기록 파일 경로를 만듭니다. id 에 경로 문자가 섞여 있으면 $null (뷰어가 주소로 받은 값을 그대로 쓰므로 막아 둔다).
function Get-AgyTranscriptPath([string]$AgyHome, [string]$ConversationId) {
    if ($ConversationId -notmatch '^[A-Za-z0-9-]{1,80}$') { return $null }
    return (Join-Path $AgyHome ("brain\{0}\.system_generated\logs\transcript_full.jsonl" -f $ConversationId))
}

# 대화 기록(transcript_full.jsonl)에서 도구 호출 목록을 읽습니다. 반환: @{ Steps = @(...); Offset = <다음에 읽을 위치> }
#   Steps 의 각 항목: n(단계 번호) at(시각 HH:mm:ss) tool(도구 이름) detail(대상) label(agy 가 붙인 영어 설명)
#                    think(agy 의 생각, 잘라 둠) say(도구를 부르면서 agy 가 적은 진행 설명. 있을 때만) bg(백그라운드면 $true. 아니면 키 없음)
#   think/say 는 한 응답에서 부른 도구가 여러 개여도 첫 호출에만 붙습니다.
#   FromOffset 부터 읽고, 아직 줄바꿈으로 끝나지 않은 마지막 줄(agy 가 쓰는 중)은 읽지 않고 Offset 을 그 앞에 둡니다.
#   그래서 진행 중인 대화는 Offset 을 기억해 두고 새로 쌓인 부분만 이어서 읽을 수 있습니다.
#   한 위임의 과정이 1,500 단계를 넘으면 앞 300번과 뒤 1,200번을 남기고 가운데는 생략 표지([ordered]@{ skipped = N }) 하나로 접습니다.
#   Since 를 주면 그 시각(로컬) 이전의 단계는 상한을 세기 전에 건너뜁니다(이어 보낸 세션에서 이번 위임만 볼 때).
function Read-AgyProcessSteps {
    param([string]$Path, [long]$FromOffset = 0, [int]$MaxSteps = 1500, [int]$ThinkingMax = 500, [int]$SayMax = 300, $Since = $null)
    $res = [ordered]@{ Steps = @(); Offset = $FromOffset }
    if (-not $Path) { return $res }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return $res }
    if ($FromOffset -lt 0 -or $FromOffset -gt $item.Length) { $FromOffset = 0; $res.Offset = 0 }

    $sinceDt = $null
    if ($Since) {
        try {
            if ($Since -is [datetime]) { $sinceDt = $Since }
            elseif ($Since -is [DateTimeOffset]) { $sinceDt = $Since.LocalDateTime }
            else { $sinceDt = [datetime]::Parse([string]$Since, [System.Globalization.CultureInfo]::InvariantCulture) }
        } catch {}
    }

    $buf = $null; $read = 0
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        [void]$fs.Seek($FromOffset, [System.IO.SeekOrigin]::Begin)
        $len = [int]($fs.Length - $FromOffset)
        if ($len -le 0) { return $res }
        $buf = New-Object byte[] $len
        while ($read -lt $len) {
            $n = $fs.Read($buf, $read, $len - $read)
            if ($n -le 0) { break }
            $read += $n
        }
    } catch { return $res } finally { if ($fs) { $fs.Dispose() } }

    $lastNl = if ($read -gt 0) { [Array]::LastIndexOf($buf, [byte]10, $read - 1) } else { -1 }
    if ($lastNl -lt 0) { return $res }
    $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $lastNl + 1)
    $res.Offset = $FromOffset + $lastNl + 1

    $lines = @($text -split "\r?\n")
    $statusMap = @{}
    foreach ($line in $lines) {
        if (-not $line) { continue }
        if ($line -match '"step_index"\s*:\s*(\d+)') {
            $sIdx = [int]$Matches[1]
            if ($line -match 'Status:\s*(RUNNING|DONE|ERROR|CANCELLED|[A-Za-z0-9_-]+)') {
                $statusMap[$sIdx] = [string]$Matches[1]
            }
        }
    }

    $steps = New-Object System.Collections.ArrayList
    for ($lineIdx = 0; $lineIdx -lt $lines.Count; $lineIdx++) {
        $line = $lines[$lineIdx]
        if (-not $line -or $line.IndexOf('"tool_calls"') -lt 0) { continue }
        $o = $null
        try { $o = $line.TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { continue }
        if ($o.type -ne 'PLANNER_RESPONSE') { continue }
        $stepDt = $null
        $at = ""
        $ts = ""
        try {
            $parsed = [datetime]::Parse([string]$o.created_at, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
            $stepDt = $parsed.ToLocalTime()
            $at = $stepDt.ToString("HH:mm:ss")
            $ts = $stepDt.ToString("yyyy-MM-dd HH:mm:ss")
        } catch {}
        if ($sinceDt -and $stepDt -and $stepDt -lt $sinceDt) { continue }

        $think = ""
        if ($o.thinking) {
            $think = (([string]$o.thinking) -replace '\s+', ' ').Trim()
            if ($think.Length -gt $ThinkingMax) { $think = $think.Substring(0, $ThinkingMax) + "…" }
        }
        $say = ""
        if ($o.content) {
            $say = (([string]$o.content) -replace '\s+', ' ').Trim()
            if ($say.Length -gt $SayMax) { $say = $say.Substring(0, $SayMax) + "…" }
        }
        $first = $true
        foreach ($c in @($o.tool_calls)) {
            $toolName = [string]$c.name
            $label = ""
            if ($c.args) { $label = [string]$c.args.toolAction; if (-not $label) { $label = [string]$c.args.toolSummary } }
            $st = [ordered]@{
                n      = [int]$o.step_index
                at     = $at
                ts     = $ts
                tool   = $toolName
                detail = (Get-AgyToolDetail $c)
                label  = $label
                think  = $(if ($first) { $think } else { "" })
            }
            if ($first -and $say) { $st.say = $say }
            if ($toolName -eq 'run_command' -and $c.args -and ([string]$c.args.IsDaemon -match '^(?i:true|1)$')) { $st.bg = $true }
            if ($toolName -eq 'manage_task' -and $c.args) {
                $tId = [string]$c.args.TaskId
                if ($tId -match 'task-(\d+)') {
                    $st.task_no = [int]$Matches[1]
                }
                $nextStepIdx = [int]$o.step_index + 1
                if ($statusMap.ContainsKey($nextStepIdx)) {
                    $st.state = [string]$statusMap[$nextStepIdx]
                }
            }

            $filePath = ""
            if ($c.args) {
                $filePath = if ($c.args.Path) { [string]$c.args.Path }
                            elseif ($c.args.AbsolutePath) { [string]$c.args.AbsolutePath }
                            elseif ($c.args.TargetFile) { [string]$c.args.TargetFile }
                            else { "" }
            }
            if ($filePath) {
                $st.path = $filePath.Trim()
            }

            if ($toolName -in @('read_file', 'view_file')) {
                $rFrom = $null; $rTo = $null; $rTotal = $null
                for ($k = $lineIdx + 1; $k -lt $lines.Count -and $k -le ($lineIdx + 5); $k++) {
                    $kLine = $lines[$k]
                    if (-not $kLine) { continue }
                    if ($kLine.IndexOf('"PLANNER_RESPONSE"') -ge 0) { break }
                    if ($kLine -match 'Showing lines\s*(\d+)\s*(?:-|to)\s*(\d+)(?:\s+of\s+(\d+))?') {
                        $rFrom = [int]$Matches[1]
                        $rTo = [int]$Matches[2]
                        if ($Matches[3]) { $rTotal = [int]$Matches[3] }
                        if ($rTotal -eq $null -and $kLine -match 'Total Lines:\s*(\d+)') {
                            $rTotal = [int]$Matches[1]
                        }
                        break
                    }
                }
                $aFrom = if ($c.args -and $c.args.StartLine) { [int]$c.args.StartLine } else { $null }
                $aTo = if ($c.args -and $c.args.EndLine) { [int]$c.args.EndLine } else { $null }
                $from = if ($aFrom -ne $null) { $aFrom } elseif ($rFrom -ne $null) { $rFrom } else { $null }
                $to = if ($aTo -ne $null) { $aTo } elseif ($rTo -ne $null) { $rTo } else { $null }
                $total = if ($rTotal -ne $null) { $rTotal } else { $null }

                if ($from -ne $null -and $to -ne $null) {
                    $range = [ordered]@{ from = $from; to = $to }
                    if ($total -ne $null) { $range.total = $total }
                    $st.range = $range
                } elseif ($total -ne $null) {
                    $st.range = [ordered]@{ from = 1; to = $total; total = $total }
                }
            }

            [void]$steps.Add($st)
            $first = $false
        }
    }
    $allCount = $steps.Count
    if ($MaxSteps -ge 1500) {
        if ($allCount -le 1500) {
            $res.Steps = @($steps.ToArray())
        } else {
            $front = @($steps.GetRange(0, 300))
            $marker = [ordered]@{ skipped = ($allCount - 1500) }
            $back = @($steps.GetRange($allCount - 1200, 1200))
            $res.Steps = @(@($front) + @($marker) + @($back))
        }
    } elseif ($MaxSteps -gt 0) {
        if ($allCount -le $MaxSteps) {
            $res.Steps = @($steps.ToArray())
        } else {
            $res.Steps = @($steps.GetRange(0, $MaxSteps))
        }
    } else {
        $res.Steps = @($steps.ToArray())
    }
    return $res
}

# ==========================================================================
# 토큰 사용량 집계 (대화 기록 transcript 의 모델 응답 줄)
#   대화 기록에는 모델이 응답한 턴(과정) 하나마다 usage 가 있는 줄이 하나씩 있다:
#     step_index, input_tokens(캐시 밖 일반 입력), cache_read_tokens(캐시에서 읽은 입력), output_tokens(출력. 사고 토큰을 포함한다).
#   도구 실행 결과 줄에는 usage 가 없다. 같은 턴(step_index)의 usage 줄이 또 나오면 더하지 않고 마지막 값으로 덮어쓴다
#   (스트리밍 기록이 턴 처음부터 지금까지의 누적값을 거듭 내보내도 두 번 세지 않게).
#   총 토큰 = 입력 + 출력: 위임 기록 DB(agy 가 작업 끝에 알려 주는 값)와 같은 기준이다(모든 기록에서 총 = 입력 + 출력, 사고 <= 출력).
#   캐시 읽기는 총에 넣지 않고 따로 센다: 단계마다 앞 맥락을 다시 읽어 누적하면 수백만이 되어 진행 중 숫자와 끝난 뒤 숫자가 어긋난다.
#   현재 컨텍스트 = 가장 마지막 턴이 모델에 보낸 입력의 크기(캐시 밖 입력 + 캐시 읽기).
# ==========================================================================

# 새 집계 상태. Path 는 대화 기록 파일, Offset 은 다음에 읽을 위치(이어 읽기용), Turns 는 step_index -> @{ In; Cache; Out }.
function New-AgyUsageState([string]$Path) {
    return @{ Path = $Path; Offset = [long]0; Turns = @{}; Anon = 0; Touched = (Get-Date) }
}

# 파일에서 새로 쌓인 줄만 읽어 상태에 반영한다(아직 줄바꿈으로 끝나지 않은 마지막 줄은 다음에). 파일이 없거나 오류면 상태를 그대로 둔다.
function Update-AgyUsageState($State) {
    if (-not $State -or -not $State.Path -or -not (Test-Path -LiteralPath $State.Path -PathType Leaf)) { return }
    $item = Get-Item -LiteralPath $State.Path
    if ($item.Length -lt $State.Offset) { $State.Offset = [long]0; $State.Turns.Clear() }    # 파일이 줄었으면(새로 쓰임) 처음부터
    if ($item.Length -le $State.Offset) { return }
    $fs = [System.IO.File]::Open($State.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        [void]$fs.Seek($State.Offset, [System.IO.SeekOrigin]::Begin)
        $want = [int]($fs.Length - $State.Offset)
        if ($want -le 0) { return }
        $buf = New-Object byte[] $want
        $got = $fs.Read($buf, 0, $want)
        $lastNl = if ($got -gt 0) { [Array]::LastIndexOf($buf, [byte]10, $got - 1) } else { -1 }
        if ($lastNl -lt 0) { return }
        $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $lastNl + 1)
        foreach ($line in ($text -split "\r?\n")) {
            if (-not $line) { continue }
            $hasIn = $line -match '"input_tokens"\s*:\s*(\d+)'
            $inTok = if ($hasIn) { [int64]$matches[1] } else { [int64]0 }
            $hasCache = $line -match '"cache_read_tokens"\s*:\s*(\d+)'
            $cacheTok = if ($hasCache) { [int64]$matches[1] } else { [int64]0 }
            $hasOut = $line -match '"output_tokens"\s*:\s*(\d+)'
            $outTok = if ($hasOut) { [int64]$matches[1] } else { [int64]0 }
            $hasThink = $line -match '"thinking_tokens"\s*:\s*(\d+)'
            $thinkTok = if ($hasThink) { [int64]$matches[1] } else { [int64]0 }
            if (-not ($hasIn -or $hasCache -or $hasOut -or $hasThink)) { continue }
            $key = $null
            if ($line -match '"step_index"\s*:\s*(\d+)') { $key = [int]$matches[1] } else { $State.Anon++; $key = "x" + $State.Anon }
            $createdAt = $null
            if ($line -match '"created_at"\s*:\s*"([^"]+)"') {
                try {
                    $parsed = [datetime]::Parse([string]$matches[1], [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::RoundtripKind)
                    $createdAt = $parsed.ToLocalTime()
                } catch {}
            }
            $State.Turns[$key] = @{ In = $inTok; Cache = $cacheTok; Out = $outTok; Think = $thinkTok; CreatedAt = $createdAt }     # 같은 턴은 마지막 값으로 덮어쓴다
        }
        $State.Offset = $State.Offset + $lastNl + 1
    } finally { $fs.Dispose() }
    $State.Touched = Get-Date
}

# 상태에서 합계를 낸다. MaxStep 이 0 보다 크면 그 단계 번호까지의 턴만(어느 시점까지의 값이 필요할 때).
# Since 를 주면 그 시각(로컬) 이후의 턴만 합친다(이어 보낸 세션에서 이번 위임만 볼 때).
# 반환: @{ Input; Cache; Output; Thinking; Total; Context; Turns }
function Get-AgyUsageSummary($State, [int]$MaxStep = 0, $Since = $null) {
    $sinceDt = $null
    if ($Since) {
        try {
            if ($Since -is [datetime]) { $sinceDt = $Since }
            elseif ($Since -is [DateTimeOffset]) { $sinceDt = $Since.LocalDateTime }
            else { $sinceDt = [datetime]::Parse([string]$Since, [System.Globalization.CultureInfo]::InvariantCulture) }
        } catch {}
    }

    $in = [int64]0; $cache = [int64]0; $out = [int64]0; $think = [int64]0; $turns = 0
    $ctxStep = -1; $ctx = [int64]0
    if ($State -and $State.Turns) {
        foreach ($k in @($State.Turns.Keys)) {
            $isNum = ($k -is [int])
            if ($MaxStep -gt 0 -and $isNum -and $k -gt $MaxStep) { continue }
            if ($MaxStep -gt 0 -and -not $isNum) { continue }
            $v = $State.Turns[$k]

            # 컨텍스트 = 가장 마지막 턴이 모델에 보낸 입력의 크기(캐시 밖 입력 + 캐시 읽기). Since 로 필터링하지 않는다.
            if ($isNum -and $k -gt $ctxStep) { $ctxStep = $k; $ctx = $v.In + $v.Cache }

            # Since 가 있으면 그 시각 이전 턴은 합계에서 제외
            if ($sinceDt -and $v.CreatedAt -and $v.CreatedAt -lt $sinceDt) { continue }

            $in += $v.In; $cache += $v.Cache; $out += $v.Out; $think += $v.Think; $turns++
        }
    }
    return @{ Input = $in; Cache = $cache; Output = $out; Thinking = $think; Total = ($in + $out); Context = $ctx; Turns = $turns }
}
