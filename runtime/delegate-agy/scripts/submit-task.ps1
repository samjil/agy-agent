# submit-task.ps1
# agy 위임 작업을 inbox 에 넣고 결과를 기다리는 한 줄짜리 도구입니다. Claude 가 위임 때마다 긴 bash(런타임 폴더 찾기 + 폴링 루프)를
# 새로 쓰지 않아도 되게 하려는 것입니다(출력 토큰 절약, 스크립트 실수 방지).
#
# 사용법 (지시문은 표준입력으로 받습니다):
#   powershell.exe -NoProfile -File "$env:USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1" <<'EOF'
#   @cwd: C:\project
#   <지시문>
#   EOF
#
#   -File <경로>        표준입력 대신 지시문 파일을 읽는다
#   -NoWait             넣기만 하고 작업 ID 만 출력한다(여러 개를 병렬로 보낼 때). 나중에 -Poll 로 기다린다
#   -Poll <ID>...       이미 보낸 작업(들)의 결과를 기다린다(쉼표·공백으로 여러 개). 시간 초과로 끝난 뒤 다시 확인할 때도 쓴다
#   -WaitSeconds <초>   기다리는 최대 시간(기본 170 — device_bash 한 호출이 3분 제한이라 그 안에 돌아오게)
#   -MaxWaitSec <초>    -WaitSeconds 와 같은 뜻이고, 주면 그것을 쓴다(폴 시작 기준 그 시간까지만 기다림, 연장 없음)
#   -CancelOnTimeout    기다리는 시간이 다 됐는데 안 끝난 작업을 취소한다. -MaxWaitSec 를 안 주면 작업 시작(claim started_at 또는 ID 제출 시각) 기준
#                       단계의 대기 한도(config\models.json 의 wait_sec: quick 3분 · build 8분 · build-hard 12분 · feature · feature-carbon · think · think-carbon · deep 20분)까지 기다린다.
#                       한도가 지나도 작업이 계속 진행 중이거나(대화 활동·도구 출력) 백그라운드 도구가 도는 중이면 대기를 연장하며, 5분간 진행이 없고 도는 백그라운드 도구도 없을 때나 2시간 절대 한도를 넘길 때만 취소한다.
#                       대기열에서 다른 작업 실행으로 차례를 기다리는 중이어도 워처가 살아 있으면 취소하지 않는다. 백그라운드 대기로 쓴다
#   지시문 맨 위에 "@model: <단계>" 를 쓰면 그 단계로 보낸다(quick · build · build-hard · feature · feature-carbon · think · think-carbon · deep). 없으면 워처가 quick/build 중에서 고른다.
#   지시문 맨 위에 "@cmd: <명령>"(goal · swarm · run-workflow · boost · browser · plan) · "@mode: <모드>"(plan · accept-edits · auto) 를 쓰면 실행 명령과 권한 모드를 함께 넘긴다.
#   새로 넣으면 표준 오류에 "[단계] <단계> (<모델>) · 대기 한도 <초>" 한 줄을 알린다.
#   지시문 맨 위에 "@reason: <한 줄>" 을 쓰면 위임 사유로 기록하고(claude-meta\<ID>.json 의 reason) agy 에 보내는 지시문에서는 뺀다.
#   -Cancel <ID>...     작업(들)을 취소한다: 대기 중이면 지시 파일을 치우고, 실행 중이면 작업자 프로세스 트리를 끝낸다. 기록 상태는 CANCELLED
#
# 출력(표준 출력):
#   submitted: <ID>                      (새로 넣었을 때)
#   ===RESULT=== <ID>  + 응답 본문         (응답 파일이 생김. 실패 사유도 응답으로 올 수 있으니 본문을 읽는다)
#   ===ERROR=== <ID>   + 거절 사유 또는 error.log 본문 (답변이 나오기 전에 실패함: 거절된 모델, 없는 폴더, 또는 오류 로그)
#   ===PENDING=== <ID> + 진행 상태 한 줄    (시간 안에 안 끝남: 경과 시간·모델·마지막 단계. 작업은 계속 돌고 있다 — 다시 제출하지 말고 -Poll 로 확인)
#   ===CANCELLED=== <ID> + 취소 사유       (취소됨: -Cancel 이나 -CancelOnTimeout 의 결과. 이미 취소된 작업을 -Poll 해도 이렇게 나온다)
#   ===DONE=== <ID>                       (-Cancel 했는데 이미 끝나 있어 취소하지 않음. 결과는 -Poll 로 읽는다)
#   ===NOTFOUND=== <ID>                   (-Cancel 했는데 대기열에도 실행 목록에도 없음)
# 종료 코드: 0 모두 결과 있음 / 1 오류가 있음 / 2 아직 진행 중 / 3 입력·환경 오류(런타임 폴더 없음, 지시문이 비었음 등) / 4 시간 초과로 취소함(-CancelOnTimeout)
#
# 컨텍스트 알림: 새로 제출할 때 Claude 대화 기록 끝에서 컨텍스트 크기를 읽어, 기준(기본 200000 토큰, 환경변수 AGY_CTX_SUBAGENT_THRESHOLD)을 넘으면
#   표준 오류에 한 줄 알린다("위임 절차는 서브에이전트에 맡기세요"). 제출은 그대로 진행한다.

param(
    [string]$File = "",
    [string[]]$Poll = @(),
    [string[]]$Cancel = @(),
    [switch]$NoWait,
    [int]$WaitSeconds = 170,
    [int]$MaxWaitSec = 0,
    [switch]$CancelOnTimeout,
    [string]$RuntimeDir = ""
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8 } catch {}

function Stop-WithCode([int]$Code, [string]$Message) {
    if ($Message) { [Console]::Error.WriteLine($Message) }
    exit $Code
}

# 런타임 폴더: -RuntimeDir > 환경변수 AGY_DELEGATE_RUNTIME > 이 스크립트 옆(설치 위치 ~/.samjil/delegate-agy/scripts -> ../runtime) > 예전 설치 이름들
. (Join-Path $PSScriptRoot "sub\agy-layout.ps1")
$progressLib = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
if (Test-Path -LiteralPath $progressLib) { . $progressLib }

function Resolve-RuntimeDirForSubmit([string]$Given) {
    $cands = @()
    if ($Given) { $cands += $Given }
    if ($env:AGY_DELEGATE_RUNTIME) { $cands += $env:AGY_DELEGATE_RUNTIME }
    $cands += (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime")
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    foreach ($n in @(".samjil\delegate-agy", ".samjil\samjil-delegate-agy", ".samjil\agent-delegate-agy", ".samjil\delegate", ".agent-delegate")) {
        $cands += (Join-Path $home_ ($n + "\runtime"))
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c "inbox") -PathType Container)) { return $c }
    }
    return $null
}

function Read-AllStdin {
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, $utf8)
    return $reader.ReadToEnd()
}

function Read-TextFile([string]$Path) {
    return ([System.IO.File]::ReadAllText($Path, $utf8)).TrimStart([char]0xFEFF)
}

function Test-TaskDone([string]$Id) {
    foreach ($n in @("$Id.response.md", "$Id.error.log")) {
        $p = Join-Path $script:OutboxDir $n
        if ((Test-Path -LiteralPath $p -PathType Leaf) -and ((Get-Item -LiteralPath $p).Length -gt 0)) { return $true }
    }
    return $false
}

# 아직 끝나지 않은 작업의 상태를 한 줄로: 대기열 / 실행 중(경과·모델·마지막 단계) / 접수 기록 없음
function Get-PendingStatus([string]$Id) {
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    $claimPath = Join-Path $runningDir "$Id.json"
    $parts = @()
    $claim = $null
    if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
        try { $claim = Read-TextFile $claimPath | ConvertFrom-Json } catch { $claim = $null }
    }
    if ($claim) {
        $startText = if ($claim.started_at) { [string]$claim.started_at } else { [string]$claim.started }
        $st = [datetime]::MinValue
        if ($startText -and [datetime]::TryParse($startText, [ref]$st)) {
            $parts += ("경과 {0}분" -f [math]::Floor(((Get-Date) - $st).TotalMinutes))
        }
        if ($claim.model) { $parts += ("모델 " + [string]$claim.model) }
        if ($claim.session) { $parts += ("세션 " + [string]$claim.session) }
        $conv = [string]$claim.conversation_id
        if ($conv) {
            try {
                $progress = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
                if (Test-Path -LiteralPath $progress) {
                    . $progress
                    $step = Format-AgyLastStep (Get-AgyLastStepSummary (Get-AgyHomeDir) $conv)
                    if ($step) { $parts += $step }
                }
            } catch {}
        } else {
            $parts += "agy 대화를 시작하는 중"
        }
        return ("진행 중 · " + ($parts -join " · "))
    }
    $queued = @(Get-ChildItem -LiteralPath (Join-Path $script:RuntimeDirResolved "inbox") -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Id })
    if ($queued.Count -gt 0) {
        $running = @(Get-ChildItem -LiteralPath $runningDir -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
        $text = "대기열에서 기다리는 중(지금 도는 작업 ${running}개)"
        $hb = @(Get-ChildItem -LiteralPath (Get-AgyLayout $script:RuntimeDirResolved).HeartbeatDir -Filter "hb_*.txt" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($hb.Count -eq 0 -or ((Get-Date) - $hb[0].LastWriteTime).TotalMinutes -gt 5) { $text += " · 워처 하트비트가 없습니다: 워처가 꺼져 있는지 확인하세요" }
        return $text
    }
    return "접수 기록 없음(inbox 에도 실행 목록에도 없음): 작업 ID 를 확인하세요"
}

# 워처가 살아있는지(최근 30초 이내 하트비트) 확인한다
function Test-SubmitWatcherAlive {
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $hbDir = $layout.HeartbeatDir
    if (-not (Test-Path -LiteralPath $hbDir -PathType Container)) { return $false }
    $hb = @(Get-ChildItem -LiteralPath $hbDir -Filter "hb_*.txt" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($hb.Count -gt 0 -and ((Get-Date) - $hb[0].LastWriteTime).TotalSeconds -le 30) { return $true }
    return $false
}

# 다른 작업이 실제로 실행 중인지(PID 프로세스 살아있음) 확인한다
function Test-OtherTaskRunning([string]$MyTaskId) {
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    if (-not (Test-Path -LiteralPath $runningDir -PathType Container)) { return $false }
    foreach ($f in @(Get-ChildItem -LiteralPath $runningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        if ([System.IO.Path]::GetFileNameWithoutExtension($f.Name) -eq $MyTaskId) { continue }
        try {
            $claim = Read-TextFile $f.FullName | ConvertFrom-Json
            if ($claim) {
                $claimPid = 0
                try { $claimPid = [int]$claim.pid } catch { $claimPid = 0 }
                if ($claimPid -gt 0) {
                    $p = Get-Process -Id $claimPid -ErrorAction SilentlyContinue
                    if ($p -and -not $p.HasExited) { return $true }
                }
            }
        } catch {}
    }
    return $false
}

# 작업 시작 시각: 실행 중 claim started_at > 작업 ID 에 담긴 제출 시각(claude_<epoch>_N) > 폴 시작 시각(fallback)
function Get-TaskStartTime([string]$Id, [datetime]$Fallback) {
    $runningDir = (Get-AgyLayout $script:RuntimeDirResolved).RunningDir
    $claimPath = Join-Path $runningDir "$Id.json"
    if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
        try {
            $claim = Read-TextFile $claimPath | ConvertFrom-Json
            if ($claim) {
                $startText = if ($claim.started_at) { [string]$claim.started_at } else { [string]$claim.started }
                $st = [datetime]::MinValue
                if ($startText -and [datetime]::TryParse($startText, [ref]$st)) {
                    return $st
                }
            }
        } catch {}
    }
    if ($Id -match '^claude_(\d{9,11})_\d+$') {
        try {
            return [DateTimeOffset]::FromUnixTimeSeconds([int64]$Matches[1]).LocalDateTime
        } catch {}
    }
    return $Fallback
}

$script:CancelledPrefix = "취소됨(CANCELLED):"

# 모델 단계 설정(config\models.json)과 자동 선택 규칙. 대기 한도(-CancelOnTimeout 의 기본값)를 단계에서 읽는다.
$script:ModelsReady = $false
try {
    . (Join-Path $PSScriptRoot "sub\agy-models.ps1")
    $autoTierLib = Join-Path $PSScriptRoot "sub\agy-autotier.ps1"
    if (Test-Path -LiteralPath $autoTierLib) { . $autoTierLib }
    $rulesLibForSubmit = Join-Path $PSScriptRoot "sub\agy-rules.ps1"
    if (Test-Path -LiteralPath $rulesLibForSubmit) { . $rulesLibForSubmit }
    $script:ModelsReady = $true
} catch {}

# 지시문 맨 위 지시어(@model · @session · @cwd · @cmd · @mode)로 워처가 쓸 단계와 대기 한도를 짐작한다(워처와 같은 규칙).
# 반환: @{ Tier; Model; WaitSec; Cmd; Mode } (설정을 못 읽으면 $null)
function Get-BriefTierInfo([string]$Text) {
    if (-not $script:ModelsReady) { return $null }
    $cfg = Get-AgyModelConfig
    $model = ""; $session = ""; $hasCwd = $false; $cmd = ""; $mode = ""; $body = [string]$Text
    while ($body.Length -gt 0) {
        $parts = $body -split "`r?`n", 2
        $line = $parts[0]
        if ($line -match '^\s*$') { }
        elseif ($line -match '^﻿?@model:\s*(.+)$') { $model = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@session:\s*(.+)$') { $session = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@cwd:\s*(.+)$') { $hasCwd = $true }
        elseif ($line -match '^﻿?@cmd:\s*(.+)$') { $cmd = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@mode:\s*(.+)$') { $mode = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@(raw|upgrade|reason):') { }
        else { break }
        $body = if ($parts.Length -gt 1) { $parts[1] } else { "" }
    }
    $cmdName = ""
    $cmdDisplay = ""
    if ($cmd -and (Get-Command Resolve-AgySlashCommand -ErrorAction SilentlyContinue)) {
        $cr = Resolve-AgySlashCommand $cmd
        if ($cr -and $cr.Valid) { $cmdName = [string]$cr.Name; $cmdDisplay = [string]$cr.Command }
    } elseif (-not $cmd -and (Get-Command Split-AgyLeadingSlashCommand -ErrorAction SilentlyContinue)) {
        $lc = Split-AgyLeadingSlashCommand $body
        if ($lc.Command) { $cmdName = [string]$lc.Name; $cmdDisplay = [string]$lc.Command; $body = [string]$lc.Body }
    }
    $modeName = ""
    if ($mode -and (Get-Command Resolve-AgyExecutionMode -ErrorAction SilentlyContinue)) {
        $mr = Resolve-AgyExecutionMode $mode
        if ($mr -and $mr.Valid) { $modeName = [string]$mr.Mode }
    }
    $writeTier = if ($cfg.Auto -and $cfg.Auto.write -and $cfg.Tiers.Contains([string]$cfg.Auto.write)) { [string]$cfg.Auto.write } else { "build" }
    $tier = ""
    $resolvedModel = ""
    $waitSec = 0
    if ($model) {
        $spec = Resolve-AgyModelSpec $model $cfg
        if ($spec -and $spec.Kind -eq "tier") { $tier = [string]$spec.Tier }
        elseif ($spec -and $spec.Kind -eq "model") {
            $tier = [string]$spec.Tier
            $resolvedModel = [string]$spec.Model
            $waitSec = if ($spec.WaitSec -gt 0) { [int]$spec.WaitSec } else { [int]$cfg.Tiers[$writeTier].WaitSec }
        }
    }
    if (-not $resolvedModel) {
        if (-not $tier) {
            if (-not $session -and (Get-Command Get-AgyAutoTier -ErrorAction SilentlyContinue) -and (Test-AgyAutoTierEnabled)) {
                try { $tier = [string](Get-AgyAutoTier $body $hasCwd).Tier } catch { $tier = "" }
            }
            if (-not $tier -or -not $cfg.Tiers.Contains($tier)) { $tier = $writeTier }
        }
        $resolvedModel = [string]$cfg.Tiers[$tier].Model
        $waitSec = [int]$cfg.Tiers[$tier].WaitSec
    }
    if ($cmdName -in @('swarm', 'run-workflow', 'boost')) {
        $waitSec = [Math]::Max($waitSec, 1200)
    }
    return @{ Tier = $tier; Model = $resolvedModel; WaitSec = $waitSec; Cmd = $cmdDisplay; Mode = $modeName }
}

# 작업 하나의 대기 한도(초). 실행 표시 파일의 단계(워처가 정한 것) > 지시문에서 짐작한 단계 > 0(모름)
function Get-TaskWaitSec([string]$Id) {
    if (-not $script:ModelsReady) { return 0 }
    try {
        $cfg = Get-AgyModelConfig
        $claimPath = Join-Path (Get-AgyLayout $script:RuntimeDirResolved).RunningDir "$Id.json"
        if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
            $claim = Read-TextFile $claimPath | ConvertFrom-Json
            $t = [string]$claim.tier
            if ($t -and $cfg.Tiers.Contains($t)) { return [int]$cfg.Tiers[$t].WaitSec }
        }
        foreach ($ext in @(".md", ".txt")) {
            $brief = Join-Path (Join-Path $script:RuntimeDirResolved "inbox") "$Id$ext"
            if (Test-Path -LiteralPath $brief -PathType Leaf) {
                $info = Get-BriefTierInfo (Read-TextFile $brief)
                if ($info) { return [int]$info.WaitSec }
            }
        }
    } catch {}
    return 0
}

# 지시문 맨 위 "@키: 값" 줄들 가운데 "@reason: <사유>" 를 떼어 낸다. 사유는 통계용 기록(claude-meta)에만 남기고 agy 에는 보내지 않는다.
# 돌려주는 값: @{ Text = <@reason 줄을 뺀 지시문>; Reason = <사유(없으면 "")> }. @reason 줄이 없으면 지시문은 한 글자도 바뀌지 않는다.
function Split-TaskReason([string]$Text) {
    $parts = [regex]::Split([string]$Text, '(?<=\n)')
    $kept = New-Object System.Collections.ArrayList
    $reason = ""
    $inHeader = $true
    foreach ($part in $parts) {
        if ($inHeader) {
            $m = [regex]::Match($part, '^\ufeff?\s*@([A-Za-z]+)\s*:(.*)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if (-not $m.Success) { $inHeader = $false }
            elseif ($m.Groups[1].Value -ieq 'reason') {
                if (-not $reason) { $reason = (($m.Groups[2].Value -replace '\s+', ' ').Trim()) }
                continue
            }
        }
        [void]$kept.Add($part)
    }
    if ($reason.Length -gt 200) { $reason = $reason.Substring(0, 200) }
    return @{ Text = ($kept -join ''); Reason = $reason }
}

# 지시문 앞의 "@키: 값" 줄(@cwd · @model 등)을 빼고 질문 본문만 남긴다(취소 기록의 질문 칸용).
function Get-TaskBodyText([string]$Text) {
    $lines = @(([string]$Text) -split "`r?`n")
    $i = 0
    while ($i -lt $lines.Count -and $lines[$i] -match '^\s*@[A-Za-z]+\s*:') { $i++ }
    if ($i -ge $lines.Count) { return "" }
    return (($lines[$i..($lines.Count - 1)]) -join "`n").Trim()
}

# 취소를 마무리한다: 응답 파일(취소 사유)을 쓰고, 지시 파일이 inbox 에 남아 있으면 processed 로 옮기고, 실행 표시를 지우고, 기록(DB)에 CANCELLED 로 남긴다.
function Complete-CancelledTask([string]$Id, [string]$Reason, $Claim = $null) {
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $message = "$script:CancelledPrefix $Reason"
    $outFile = Join-Path $script:OutboxDir "$Id.response.md"
    $taskText = ""
    $claimPath = Join-Path $layout.RunningDir "$Id.json"
    if ($null -eq $Claim -and (Test-Path -LiteralPath $claimPath -PathType Leaf)) {
        try { $Claim = Read-TextFile $claimPath | ConvertFrom-Json } catch { $Claim = $null }
    }
    foreach ($ext in @(".md", ".txt")) {
        $cand = Join-Path $inboxDir ($Id + $ext)
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            try { $taskText = Read-TextFile $cand } catch {}
            try {
                New-Item -ItemType Directory -Force -Path $layout.ProcessedDir | Out-Null
                Move-Item -LiteralPath $cand -Destination (Join-Path $layout.ProcessedDir ($Id + $ext)) -Force
            } catch { Remove-Item -LiteralPath $cand -Force -ErrorAction SilentlyContinue }
        }
    }
    if (-not $taskText) {
        $proc = Join-Path $layout.ProcessedDir "$Id.md"
        if (-not (Test-Path -LiteralPath $proc)) { $proc = Join-Path $layout.ProcessedDir "$Id.txt" }
        if (Test-Path -LiteralPath $proc -PathType Leaf) { try { $taskText = Read-TextFile $proc } catch {} }
    }
    $existing = $false
    if ((Test-Path -LiteralPath $outFile -PathType Leaf) -and ((Get-Item -LiteralPath $outFile).Length -gt 0)) { $existing = $true }
    Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $layout.RunningDir "$Id.cancel") -Force -ErrorAction SilentlyContinue
    # 응답 파일이 이미 있으면 워처가 취소를 마무리하고 기록(DB)까지 남긴 것이므로 덮어쓰지 않는다.
    if ($existing) { return }

    $session = if ($Claim -and $Claim.session) { [string]$Claim.session } else { "" }
    $model = if ($Claim -and $Claim.model) { [string]$Claim.model } else { "" }
    $triedModels = if ($Claim -and $Claim.tried) { [string]$Claim.tried } else { "" }
    $convId = if ($Claim -and $Claim.conversation_id) { [string]$Claim.conversation_id } else { "" }
    $startedDt = $null
    $elapsedSec = ""
    $startText = if ($Claim -and $Claim.started_at) { [string]$Claim.started_at } elseif ($Claim -and $Claim.started) { [string]$Claim.started } else { "" }
    if ($startText) {
        $parsedStart = [datetime]::MinValue
        if ([datetime]::TryParse($startText, [ref]$parsedStart)) {
            $startedDt = $parsedStart
            $elapsedSec = [string][math]::Round([math]::Max(0.0, ((Get-Date) - $parsedStart).TotalSeconds), 1)
        }
    }

    $answer = $message
    $processSteps = $null
    if ($convId) {
        try {
            if (-not (Get-Command Get-AgyCancelledWorkText -ErrorAction SilentlyContinue)) {
                $pLib = Join-Path $PSScriptRoot "sub\agy-progress.ps1"
                if (Test-Path -LiteralPath $pLib) { . $pLib }
            }
            $agyHomeDir = Get-AgyHomeDir
            $workText = Get-AgyCancelledWorkText $agyHomeDir $convId $startedDt
            if ($workText) { $answer = $message + "`n`n" + $workText }
            $tPath = Get-AgyTranscriptPath $agyHomeDir $convId
            if ($tPath -and (Test-Path -LiteralPath $tPath -PathType Leaf)) {
                $since = if ($session -and $startedDt) { $startedDt.AddSeconds(-5) } else { $null }
                $processSteps = @((Read-AgyProcessSteps $tPath 0 1500 500 300 $since).Steps)
            }
        } catch {}
    }

    New-Item -ItemType Directory -Force -Path $script:OutboxDir | Out-Null
    [System.IO.File]::WriteAllText($outFile, $answer, $utf8)

    try {
        . (Join-Path $PSScriptRoot "sub\agy-db.ps1")
        $rec = [ordered]@{
            timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            computer_name = [string]$env:COMPUTERNAME
            task_id       = $Id
            model         = $model
            tried_models  = $triedModels
            elapsed_sec   = $elapsedSec
            status        = "CANCELLED"
            session       = $session
            session_id    = $convId
            question      = (Get-TaskBodyText $taskText)
            answer        = $answer
            process       = $processSteps
        }
        [void](Write-QaRecordToDb $layout.DbPath $rec 'Upsert')
    } catch {}
}

# 작업 하나를 취소한다. 돌려주는 값: cancelled | done(이미 끝남) | notfound
function Invoke-CancelTask([string]$Id, [string]$Reason) {
    if (Test-TaskDone $Id) { return "done" }
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $claimPath = Join-Path $layout.RunningDir "$Id.json"
    for ($round = 0; $round -lt 2; $round++) {
        $claim = $null
        if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
            try { $claim = Read-TextFile $claimPath | ConvertFrom-Json } catch { $claim = $null }
        }
        $claimPid = 0
        if ($claim) { try { $claimPid = [int]$claim.pid } catch { $claimPid = 0 } }
        if ($claimPid -gt 0) {
            # 실행 중: 워처가 "취소" 로 마무리하도록 표시를 남기고, 작업자 프로세스 트리(agy 포함)를 끝낸다.
            [System.IO.File]::WriteAllText((Join-Path $layout.RunningDir "$Id.cancel"), $Reason, $utf8)
            $proc = Get-Process -Id $claimPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") {
                try { & taskkill.exe /PID $claimPid /T /F 2>&1 | Out-Null } catch {}
            }
            # 워처가 살아 있으면 곧 표시를 보고 응답 · 기록을 남긴다. 잠시 기다려 보고, 안 되면(워처가 꺼져 있음) 여기서 마무리한다.
            for ($w = 0; $w -lt 20 -and -not (Test-TaskDone $Id); $w++) { Start-Sleep -Milliseconds 500 }
            Complete-CancelledTask $Id $Reason $claim
            return "cancelled"
        }
        # 대기 중: 지시 파일을 치운다(워처가 그 사이 가져갔으면 다시 확인한다)
        $queued = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Id })
        if ($queued.Count -gt 0) {
            if (-not $claim) {
                Complete-CancelledTask $Id $Reason
                return "cancelled"
            }
            Start-Sleep -Milliseconds 700   # 워처가 막 시작하는 중(실행 표시는 있고 PID 는 아직 0): 잠깐 뒤 다시 본다
            continue
        }
        if (-not $claim) { break }
        Start-Sleep -Milliseconds 700
    }
    if (Test-TaskDone $Id) { return "done" }
    return "notfound"
}

$script:RuntimeDirResolved = Resolve-RuntimeDirForSubmit $RuntimeDir
if (-not $script:RuntimeDirResolved) { Stop-WithCode 3 "위임 런타임 폴더(~/.samjil/delegate-agy/runtime)를 찾지 못했습니다. install.ps1 로 설치돼 있는지 확인하세요." }
$script:OutboxDir = (Get-AgyLayout $script:RuntimeDirResolved).OutboxDir
$inboxDir = Join-Path $script:RuntimeDirResolved "inbox"

# 기다릴 작업 ID 들
$ids = @()
foreach ($p in @($Poll)) { foreach ($x in ([string]$p -split '[,\s]+')) { if ($x) { $ids += $x } } }
foreach ($id in $ids) { if ($id -notmatch '^[A-Za-z0-9_-]{1,80}$') { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: $id" } }

# -Cancel: 작업(들)을 취소하고 끝낸다
$cancelIds = @()
foreach ($p in @($Cancel)) { foreach ($x in ([string]$p -split '[,\s]+')) { if ($x) { $cancelIds += $x } } }
foreach ($id in $cancelIds) { if ($id -notmatch '^[A-Za-z0-9_-]{1,80}$') { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: $id" } }
if ($cancelIds.Count -gt 0) {
    $cancelExit = 0
    foreach ($id in $cancelIds) {
        $res = Invoke-CancelTask $id "사용자 요청으로 취소했습니다."
        switch ($res) {
            "cancelled" { Write-Output "===CANCELLED=== $id" }
            "done"      { Write-Output "===DONE=== $id"; Write-Output "이미 끝나 있어 취소하지 않았습니다. 결과는 -Poll 로 읽으세요." }
            default     { Write-Output "===NOTFOUND=== $id"; Write-Output "대기열에도 실행 목록에도 없습니다. 작업 ID 를 확인하세요."; $cancelExit = 1 }
        }
    }
    exit $cancelExit
}

if ($ids.Count -eq 0) {
    # 새로 넣기
    $text = $null
    if ($File) {
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { Stop-WithCode 3 "지시문 파일이 없습니다: $File" }
        $text = Read-TextFile $File
    } elseif ([Console]::IsInputRedirected) {
        $text = (Read-AllStdin).TrimStart([char]0xFEFF)
    }
    if (-not $text -or -not $text.Trim()) { Stop-WithCode 3 "지시문이 비었습니다. 표준입력(heredoc)이나 -File 로 지시문을 주세요." }
    # "@reason: <사유>" 줄은 기록용이다: 떼어 두었다가 claude-meta 에 남기고, agy 에 보내는 지시문에는 넣지 않는다.
    $taskReason = ""
    $split = Split-TaskReason $text
    if ($split.Reason) { $taskReason = $split.Reason; $text = $split.Text }
    if (-not $text.Trim()) { Stop-WithCode 3 "지시문이 비었습니다. @reason 줄 말고 지시문 본문을 주세요." }
    # 브리프 점검(경고만): 검증 방법·범위 제한·대상 파일이 빠졌거나 너무 길면 보내기 전에 알린다. 위임은 그대로 진행한다. AGY_BRIEF_LINT=off 로 끈다.
    try {
        $lintLib = Join-Path $PSScriptRoot "sub\agy-brief-lint.ps1"
        if (Test-Path -LiteralPath $lintLib) {
            . $lintLib
            if (Test-AgyBriefLintEnabled) {
                $briefWarnings = @(Get-AgyBriefWarnings $text)
                $isKorean = ((Get-AgyReplyLanguage) -eq "Korean")
                $prefix = if ($isKorean) { "[브리프 점검] " } else { "[Brief check] " }
                $tail = if ($isKorean) {
                    "[브리프 점검] 위 항목은 경고일 뿐이라 위임은 그대로 진행합니다. 다음 위임부터 반영하거나, 빠진 것을 바로 채워 다시 보내려면 이 작업을 취소하세요."
                } else {
                    "[Brief check] These are warnings only; the task was submitted. Fix them next time, or cancel this task and resend with the missing parts."
                }
                foreach ($bw in $briefWarnings) { [Console]::Error.WriteLine($prefix + $bw) }
                if ($briefWarnings.Count -gt 0) { [Console]::Error.WriteLine($tail) }
            }
        }
    } catch {}
    $id = "claude_{0}_{1}" -f ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()), (Get-Random -Minimum 0 -Maximum 32768)
    # 이 위임을 보낸 Claude 모델·effort 정보를 기억한다(뷰어 진행 중 카드 및 방금 끝난 카드 표시용).
    # 같은 대화 기록 끝에서 컨텍스트 크기도 읽어, 크면 위임 절차(제출 · 대기 · 검토)를 서브에이전트에 맡기라고 알린다.
    $metaObj = [ordered]@{}
    try {
        $sessId = $env:CLAUDE_CODE_SESSION_ID
        if ($sessId) {
            $transcriptLib = Join-Path $PSScriptRoot "sub\claude-transcript.ps1"
            if (Test-Path -LiteralPath $transcriptLib) {
                . $transcriptLib
                $mainTranscriptPath = Resolve-ClaudeTranscriptPath -SessionId $sessId
                $lastUsage = if ($mainTranscriptPath) { Get-ClaudeTranscriptLastUsage -TranscriptPath $mainTranscriptPath } else { $null }
                $subAgent = if ($mainTranscriptPath) { Find-ClaudeSubmittingSubagent -MainTranscriptPath $mainTranscriptPath } else { $null }
                $ctxThreshold = 200000
                if ($env:AGY_CTX_SUBAGENT_THRESHOLD -match '^\d+$') { $ctxThreshold = [int]$env:AGY_CTX_SUBAGENT_THRESHOLD }
                # 서브에이전트가 제출한 경우에는 본 세션이 아니라 서브에이전트 자신의 컨텍스트 크기로 판단한다.
                $effectiveCtx = if ($subAgent) { [long]$subAgent.ctx } elseif ($lastUsage -and $lastUsage.ctx) { [long]$lastUsage.ctx } else { 0L }
                if ($effectiveCtx -gt $ctxThreshold) {
                    # 이미 제출한 뒤라, 지금 할 수 있는 일(남은 대기 · 검토를 넘기기)을 알린다. 다음 위임부터는 질문 시점의 훅 알림을 보고 처음부터 서브에이전트에 맡긴다.
                    [Console]::Error.WriteLine(("[컨텍스트 {0}k] 컨텍스트가 큽니다(기준 {1}k). 제출은 됐으니 이 작업의 대기 · diff 검토 · 시험은 본 세션에서 하지 말고, 서브에이전트 하나(저렴한 모델)에 아래 작업 ID 와 확인할 시험 명령을 넘겨 맡긴 뒤 5줄 보고만 받으세요(본 세션은 호출마다 대화 전체를 다시 읽습니다)." -f [int][math]::Round($effectiveCtx / 1000.0), [int]($ctxThreshold / 1000)))
                }
                if ($lastUsage -and $lastUsage.model) {
                    $metaObj['model'] = $lastUsage.model
                    $metaObj['effort'] = $lastUsage.effort
                    $metaObj['session'] = $sessId
                }
                if ($subAgent) {
                    if ($subAgent.model)  { $metaObj['agent_model']  = [string]$subAgent.model }
                    if ($subAgent.effort) { $metaObj['agent_effort'] = [string]$subAgent.effort }
                    if ($subAgent.id)     { $metaObj['agent_id']     = [string]$subAgent.id }
                    if ($subAgent.type)   { $metaObj['agent_type']   = [string]$subAgent.type }
                    if ($subAgent.desc)   { $metaObj['agent_desc']   = [string]$subAgent.desc }
                    if (-not $metaObj.Contains('session')) { $metaObj['session'] = $sessId }
                }
            }
        }
    } catch {}
    # 메타 파일: Claude 모델을 알았거나 사유(@reason)가 있을 때 남긴다. 사유는 실측 통계가 나중에 읽으므로 통계 보관 기간(90일)만큼 둔다.
    try {
        if ($taskReason) { $metaObj['reason'] = $taskReason }
        if ($metaObj.Count -gt 0) {
            $metaDir = Join-Path $script:RuntimeDirResolved "claude-meta"
            if (-not (Test-Path -LiteralPath $metaDir -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $metaDir | Out-Null
            }
            $metaPath = Join-Path $metaDir "$id.json"
            [System.IO.File]::WriteAllText($metaPath, ($metaObj | ConvertTo-Json -Compress), $utf8)

            $cutoff = (Get-Date).AddDays(-90)
            Get-ChildItem -LiteralPath $metaDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    # 쓰는 도중의 파일을 워처가 읽지 않게 임시 이름으로 쓰고 바꿔치기한다(.tmp 는 워처가 보지 않는다)
    $tmp = Join-Path $inboxDir "$id.md.tmp"
    [System.IO.File]::WriteAllText($tmp, $text, $utf8)
    Move-Item -LiteralPath $tmp -Destination (Join-Path $inboxDir "$id.md")
    Write-Output "submitted: $id"
    try {
        $tierInfo = Get-BriefTierInfo $text
        if ($tierInfo) {
            $extraInfo = ""
            if ($tierInfo.Cmd) { $extraInfo += " · 명령 $($tierInfo.Cmd)" }
            if ($tierInfo.Mode) { $extraInfo += " · 모드 $($tierInfo.Mode)" }
            [Console]::Error.WriteLine(("[단계] {0} ({1}){2} · 대기 한도 {3}초(-CancelOnTimeout 의 기본값)" -f $(if ($tierInfo.Tier) { $tierInfo.Tier } else { "모델 지정" }), $tierInfo.Model, $extraInfo, $tierInfo.WaitSec))
        }
    } catch {}
    if ($NoWait) { exit 0 }
    $ids = @($id)
}

# 기다리기: -MaxWaitSec 가 주어지거나 -CancelOnTimeout 이 없으면 기존처럼 폴 시작 기준 대기.
# -CancelOnTimeout 만 준 경우: 작업 시작(claim started_at 또는 ID 제출 시각) 기준 단계 한도까지 대기하며,
# 한도가 지나도 활동(대화/도구 로그)이 있으면 멈출 때까지 대기를 연장하고 10초마다 재확인한다.
$timedOut = @()
$startedWait = Get-Date

if ($MaxWaitSec -gt 0 -or -not $CancelOnTimeout) {
    $effectiveWait = if ($MaxWaitSec -gt 0) { $MaxWaitSec } else { $WaitSeconds }
    $deadline = $startedWait.AddSeconds([math]::Max(0, $effectiveWait))
    while ($true) {
        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) })
        if ($pending.Count -eq 0 -or (Get-Date) -ge $deadline) { break }
        $interval = if (((Get-Date) - $startedWait).TotalSeconds -lt 60) { 3 } else { 10 }
        $left = ($deadline - (Get-Date)).TotalSeconds
        Start-Sleep -Seconds ([math]::Max(1, [math]::Min($interval, [math]::Floor($left))))
    }
    if ($CancelOnTimeout) {
        foreach ($pid_ in @($ids | Where-Object { -not (Test-TaskDone $_) })) {
            [void](Invoke-CancelTask $pid_ ("기다리는 한도({0}초)가 지나도 끝나지 않아 취소했습니다. 직접 처리하세요." -f $effectiveWait))
            $timedOut += $pid_
        }
    }
} else {
    # -CancelOnTimeout 만 주어진 경우: 작업별 시작 시각 기준 + 진행 중 대기 연장 규칙
    $stallSec = Get-AgySecondsSetting "AGY_STALL_SECONDS" 300 30
    $hardTimeoutSec = Get-AgySecondsSetting "AGY_HARD_TIMEOUT_SECONDS" 7200 60
    $recheckSec = 10.0
    if ($env:AGY_POLL_RECHECK_SEC -match '^\d+(\.\d+)?$') {
        $recheckSec = [double]$env:AGY_POLL_RECHECK_SEC
    }
    $agyHome = Get-AgyHomeDir
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $runningDir = $layout.RunningDir
    $extendedPrinted = @{}
    $bgExtendedPrinted = @{}

    while ($true) {
        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) -and ($timedOut -notcontains $_) })
        if ($pending.Count -eq 0) { break }

        $now = Get-Date

        foreach ($id in $pending) {
            $tStart = Get-TaskStartTime $id $startedWait
            $tLimit = Get-TaskWaitSec $id
            if ($tLimit -le 0) { $tLimit = $WaitSeconds }
            $elapsed = ($now - $tStart).TotalSeconds

            # 절대 마감: 작업 시작으로부터 AGY_HARD_TIMEOUT_SECONDS(기본 7200) 경과 시 취소
            if ($elapsed -ge $hardTimeoutSec) {
                $reason = "절대 대기 한도({0}초)가 지나 취소했습니다. 직접 처리하세요." -f $hardTimeoutSec
                [void](Invoke-CancelTask $id $reason)
                $timedOut += $id
                continue
            }

            # 단계 한도 전이면 계속 대기
            if ($elapsed -lt $tLimit) {
                continue
            }

            # 단계 대기 한도 초과: 실행 중/대기열/활동 상태 판정
            $claimPath = Join-Path $runningDir "$id.json"
            $claim = $null
            if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
                try { $claim = Read-TextFile $claimPath | ConvertFrom-Json } catch { $claim = $null }
            }

            if ($claim) {
                $convId = [string]$claim.conversation_id
                if ($convId) {
                    $actConv = Get-AgyConversationActivity $agyHome $convId
                    $actTask = Get-AgyTaskLogActivity $agyHome $convId
                    $actChild = Get-AgyChildConversationActivity $agyHome $convId

                    $latestAct = $null
                    $actReason = ""
                    if ($actConv -and ($null -eq $latestAct -or $actConv -gt $latestAct)) {
                        $latestAct = $actConv
                        $actReason = "새 단계 기록됨"
                    }
                    if ($actTask -and ($null -eq $latestAct -or $actTask -gt $latestAct)) {
                        $latestAct = $actTask
                        $actReason = "백그라운드 도구 출력"
                    }
                    if ($actChild -and ($null -eq $latestAct -or $actChild -gt $latestAct)) {
                        $latestAct = $actChild
                        $actReason = "하위 에이전트 활동"
                    }

                    $agoSec = if ($latestAct) { [int][Math]::Max(0, ($now - $latestAct).TotalSeconds) } else { [int][Math]::Max(0, $elapsed) }
                    if ($latestAct -and ($agoSec -lt $stallSec)) {
                        # 활동 진행 중: 대기 연장 및 re-check 안내 1회 출력
                        if (-not $extendedPrinted.ContainsKey($id)) {
                            [Console]::Error.WriteLine(("[대기 연장] {0}: 한도 {1}초가 지났지만 {2}초 전에도 진행했습니다({3}). 멈출 때까지 계속 기다립니다." -f $id, $tLimit, $agoSec, $actReason))
                            $extendedPrinted[$id] = $true
                        }
                    } else {
                        # 멈춤 후보: 최근 stall window 동안 활동 없음. 다만 agy 가 백그라운드로 돌린 도구가 아직 안 끝났으면 기다린다(워처와 같은 판정).
                        $bgPending = @(Get-AgyPendingBackgroundTasks $agyHome $convId)
                        if ($bgPending.Count -gt 0) {
                            if (-not $bgExtendedPrinted.ContainsKey($id)) {
                                [Console]::Error.WriteLine(("[대기 연장] {0}: 한도 {1}초가 지났고 {2}초 넘게 새 기록이 없지만 agy 가 백그라운드로 돌린 도구 {3}건({4})이 아직 끝나지 않아 기다립니다. 워처의 절대 마감이나 {5}초 절대 한도에서 끝납니다." -f $id, $tLimit, $stallSec, $bgPending.Count, ($bgPending -join ', '), $hardTimeoutSec))
                                $bgExtendedPrinted[$id] = $true
                            }
                        } else {
                            $cancelReason = "기다리는 한도({0}초)가 지났고 최근 {1}초 동안 진행이 없어 취소했습니다. 직접 처리하세요." -f $tLimit, $stallSec
                            [void](Invoke-CancelTask $id $cancelReason)
                            $timedOut += $id
                        }
                    }
                } else {
                    # claim 에 conversation_id 가 아직 없음: limit + window 넘었으면 멈춤으로 취소
                    if ($elapsed -ge ($tLimit + $stallSec)) {
                        $cancelReason = "기다리는 한도({0}초)가 지났고 최근 {1}초 동안 진행이 없어 취소했습니다. 직접 처리하세요." -f $tLimit, $stallSec
                        [void](Invoke-CancelTask $id $cancelReason)
                        $timedOut += $id
                    }
                }
            } else {
                # running 목록에 없음: 대기열(inbox) 확인
                $queued = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $id })
                if ($queued.Count -gt 0) {
                    $watcherAlive = Test-SubmitWatcherAlive
                    $otherRunning = Test-OtherTaskRunning $id
                    if ($watcherAlive -and $otherRunning) {
                        # 워처가 살아있고 다른 작업이 돌고 있음: 차례 기다리는 중
                        if (-not $extendedPrinted.ContainsKey($id)) {
                            [Console]::Error.WriteLine(("[대기 연장] {0}: 아직 차례를 기다리는 중입니다." -f $id))
                            $extendedPrinted[$id] = $true
                        }
                    } elseif (-not $watcherAlive) {
                        # 워처가 꺼져 있음
                        $cancelReason = "기다리는 한도({0}초)가 지났고 워처가 꺼져 있어 취소했습니다. 직접 처리하세요." -f $tLimit
                        [void](Invoke-CancelTask $id $cancelReason)
                        $timedOut += $id
                    }
                } else {
                    # inbox 에도 running 에도 없음
                    if (Test-TaskDone $id) { continue }
                    $cancelReason = "기다리는 한도({0}초)가 지나도 끝나지 않아 취소했습니다. 직접 처리하세요." -f $tLimit
                    [void](Invoke-CancelTask $id $cancelReason)
                    $timedOut += $id
                }
            }
        }

        $pending = @($ids | Where-Object { -not (Test-TaskDone $_) -and ($timedOut -notcontains $_) })
        if ($pending.Count -eq 0) { break }

        $anyOverLimit = $false
        foreach ($wid in $pending) {
            $ws = Get-TaskStartTime $wid $startedWait
            $wl = Get-TaskWaitSec $wid; if ($wl -le 0) { $wl = $WaitSeconds }
            if (($now - $ws).TotalSeconds -ge $wl) { $anyOverLimit = $true; break }
        }
        $interval = if ($anyOverLimit -or (($now - $startedWait).TotalSeconds -ge 60)) { $recheckSec } else { [Math]::Min(3.0, $recheckSec) }
        if ($interval -ge 1.0) {
            Start-Sleep -Seconds ([int][Math]::Round($interval))
        } else {
            Start-Sleep -Milliseconds ([int]($interval * 1000))
        }
    }
}

$exit = 0
foreach ($id in $ids) {
    $resp = Join-Path $script:OutboxDir "$id.response.md"
    $err = Join-Path $script:OutboxDir "$id.error.log"
    $hasResp = (Test-Path -LiteralPath $resp -PathType Leaf) -and ((Get-Item -LiteralPath $resp).Length -gt 0)
    $hasErr = (Test-Path -LiteralPath $err -PathType Leaf) -and ((Get-Item -LiteralPath $err).Length -gt 0)

    $isRejected = $false
    $errText = ""
    if ($hasErr) {
        $errText = Read-TextFile $err
        if ($errText -match '^\ufeff?지정한 @(model|cwd|cmd|mode) ') {
            $isRejected = $true
        }
    }

    if ($isRejected) {
        Write-Output "===ERROR=== $id"
        Write-Output $errText
        if ($exit -lt 1) { $exit = 1 }
    } elseif ($hasResp) {
        $respText = Read-TextFile $resp
        if ($respText.StartsWith($script:CancelledPrefix)) {
            Write-Output "===CANCELLED=== $id"
            if ($timedOut -contains $id -and $exit -ne 1) { $exit = 4 }
        } else {
            Write-Output "===RESULT=== $id"
        }
        Write-Output $respText
    } elseif ($hasErr) {
        Write-Output "===ERROR=== $id"
        Write-Output $errText
        if ($exit -lt 1) { $exit = 1 }
    } else {
        Write-Output ("===PENDING=== $id " + (Get-PendingStatus $id))
        $exit = 2
    }
}
exit $exit
