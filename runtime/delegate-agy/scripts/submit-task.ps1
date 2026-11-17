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
#   -MaxWaitSec <초>    -WaitSeconds 와 같은 뜻이고, 주면 그것을 쓴다(그 시간까지만 기다림)
#   -CancelOnTimeout    기다리는 시간이 다 됐는데 안 끝난 작업을 취소한다. -MaxWaitSec 를 안 주면 작업 단계의 대기 한도까지 기다린다
#                       (config\models.json 의 wait_sec: quick 3분 · build 8분 · build-hard 12분 · feature · think · deep 20분). 백그라운드 대기로 쓴다
#   지시문 맨 위에 "@model: <단계>" 를 쓰면 그 단계로 보낸다(quick · build · build-hard · feature · think · deep). 없으면 워처가 quick/build 중에서 고른다.
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

$script:CancelledPrefix = "취소됨(CANCELLED):"

# 모델 단계 설정(config\models.json)과 자동 선택 규칙. 대기 한도(-CancelOnTimeout 의 기본값)를 단계에서 읽는다.
$script:ModelsReady = $false
try {
    . (Join-Path $PSScriptRoot "sub\agy-models.ps1")
    $autoTierLib = Join-Path $PSScriptRoot "sub\agy-autotier.ps1"
    if (Test-Path -LiteralPath $autoTierLib) { . $autoTierLib }
    $script:ModelsReady = $true
} catch {}

# 지시문 맨 위 지시어(@model · @session · @cwd)로 워처가 쓸 단계를 짐작한다(워처와 같은 규칙).
# 반환: @{ Tier; Model; WaitSec } (설정을 못 읽으면 $null)
function Get-BriefTierInfo([string]$Text) {
    if (-not $script:ModelsReady) { return $null }
    $cfg = Get-AgyModelConfig
    $model = ""; $session = ""; $hasCwd = $false; $body = [string]$Text
    while ($body.Length -gt 0) {
        $parts = $body -split "`r?`n", 2
        $line = $parts[0]
        if ($line -match '^\s*$') { }
        elseif ($line -match '^﻿?@model:\s*(.+)$') { $model = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@session:\s*(.+)$') { $session = $Matches[1].Trim() }
        elseif ($line -match '^﻿?@cwd:\s*(.+)$') { $hasCwd = $true }
        elseif ($line -match '^﻿?@(raw|upgrade|reason):') { }
        else { break }
        $body = if ($parts.Length -gt 1) { $parts[1] } else { "" }
    }
    $writeTier = if ($cfg.Auto -and $cfg.Auto.write -and $cfg.Tiers.Contains([string]$cfg.Auto.write)) { [string]$cfg.Auto.write } else { "build" }
    $tier = ""
    if ($model) {
        $spec = Resolve-AgyModelSpec $model $cfg
        if ($spec -and $spec.Kind -eq "tier") { $tier = [string]$spec.Tier }
        elseif ($spec -and $spec.Kind -eq "model") {
            $w = if ($spec.WaitSec -gt 0) { [int]$spec.WaitSec } else { [int]$cfg.Tiers[$writeTier].WaitSec }
            return @{ Tier = [string]$spec.Tier; Model = [string]$spec.Model; WaitSec = $w }
        }
    }
    if (-not $tier) {
        if (-not $session -and (Get-Command Get-AgyAutoTier -ErrorAction SilentlyContinue) -and (Test-AgyAutoTierEnabled)) {
            try { $tier = [string](Get-AgyAutoTier $body $hasCwd).Tier } catch { $tier = "" }
        }
        if (-not $tier -or -not $cfg.Tiers.Contains($tier)) { $tier = $writeTier }
    }
    return @{ Tier = $tier; Model = [string]$cfg.Tiers[$tier].Model; WaitSec = [int]$cfg.Tiers[$tier].WaitSec }
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
function Complete-CancelledTask([string]$Id, [string]$Reason) {
    $layout = Get-AgyLayout $script:RuntimeDirResolved
    $message = "$script:CancelledPrefix $Reason"
    $outFile = Join-Path $script:OutboxDir "$Id.response.md"
    $taskText = ""
    $session = ""
    $model = ""
    $claimPath = Join-Path $layout.RunningDir "$Id.json"
    if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
        try { $c = Read-TextFile $claimPath | ConvertFrom-Json; $session = [string]$c.session; $model = [string]$c.model } catch {}
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
    if (-not $existing) {
        New-Item -ItemType Directory -Force -Path $script:OutboxDir | Out-Null
        [System.IO.File]::WriteAllText($outFile, $message, $utf8)
    }
    Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $layout.RunningDir "$Id.cancel") -Force -ErrorAction SilentlyContinue
    try {
        . (Join-Path $PSScriptRoot "sub\agy-db.ps1")
        $rec = [ordered]@{
            timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            computer_name = [string]$env:COMPUTERNAME
            task_id       = $Id
            model         = $model
            status        = "CANCELLED"
            session       = $session
            question      = (Get-TaskBodyText $taskText)
            answer        = $message
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
            Complete-CancelledTask $Id $Reason
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
                $lastUsage = Get-ClaudeTranscriptLastUsage -SessionId $sessId
                $ctxThreshold = 200000
                # 한도 균형 모드(quota-balance.json, 6시간 안의 값)를 따른다: agy-more 80k, agy-max 30k. 환경변수가 있으면 그 값이 이긴다.
                try {
                    $qbFile = Join-Path $script:RuntimeDirResolved "quota-balance.json"
                    if (Test-Path -LiteralPath $qbFile -PathType Leaf) {
                        $qb = Read-TextFile $qbFile | ConvertFrom-Json
                        $qbAt = [datetime]::MinValue
                        if ([datetime]::TryParse([string]$qb.computed_at, [ref]$qbAt) -and ((Get-Date).ToUniversalTime() - $qbAt.ToUniversalTime()).TotalHours -lt 6) {
                            if ([string]$qb.mode -eq "agy-more") { $ctxThreshold = 80000 } elseif ([string]$qb.mode -eq "agy-max") { $ctxThreshold = 30000 }
                        }
                    }
                } catch {}
                if ($env:AGY_CTX_SUBAGENT_THRESHOLD -match '^\d+$') { $ctxThreshold = [int]$env:AGY_CTX_SUBAGENT_THRESHOLD }
                if ($lastUsage -and $lastUsage.ctx -and [long]$lastUsage.ctx -gt $ctxThreshold) {
                    [Console]::Error.WriteLine(("[컨텍스트 {0}k] 컨텍스트가 큽니다. 위임 절차는 서브에이전트에 맡기세요(호출마다 대화 전체를 다시 읽습니다)." -f [int][math]::Round([long]$lastUsage.ctx / 1000.0)))
                }
                if ($lastUsage -and $lastUsage.model) {
                    $metaObj['model'] = $lastUsage.model
                    $metaObj['effort'] = $lastUsage.effort
                    $metaObj['session'] = $sessId
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
        if ($tierInfo) { [Console]::Error.WriteLine(("[단계] {0} ({1}) · 대기 한도 {2}초(-CancelOnTimeout 의 기본값)" -f $(if ($tierInfo.Tier) { $tierInfo.Tier } else { "모델 지정" }), $tierInfo.Model, $tierInfo.WaitSec)) }
    } catch {}
    if ($NoWait) { exit 0 }
    $ids = @($id)
}

# 기다리기: 처음 60초는 3초 간격, 그 뒤는 10초 간격(대기는 이 프로세스 안에서 돌아 Claude 토큰을 쓰지 않는다)
$timedOut = @()
$startedWait = Get-Date
# -MaxWaitSec 를 주면 그 값. 안 주고 -CancelOnTimeout 이면 작업 단계의 대기 한도(여러 작업이면 가장 긴 것). 그 밖에는 -WaitSeconds.
$effectiveWait = $WaitSeconds
if ($MaxWaitSec -gt 0) {
    $effectiveWait = $MaxWaitSec
} elseif ($CancelOnTimeout) {
    $tierWait = 0
    foreach ($wid in $ids) { $w = Get-TaskWaitSec $wid; if ($w -gt $tierWait) { $tierWait = $w } }
    if ($tierWait -gt 0) { $effectiveWait = $tierWait }
}
$deadline = $startedWait.AddSeconds([math]::Max(0, $effectiveWait))
while ($true) {
    $pending = @($ids | Where-Object { -not (Test-TaskDone $_) })
    if ($pending.Count -eq 0 -or (Get-Date) -ge $deadline) { break }
    $interval = if (((Get-Date) - $startedWait).TotalSeconds -lt 60) { 3 } else { 10 }
    $left = ($deadline - (Get-Date)).TotalSeconds
    Start-Sleep -Seconds ([math]::Max(1, [math]::Min($interval, [math]::Floor($left))))
}

$exit = 0
# -CancelOnTimeout: 기다리는 시간이 다 됐는데 안 끝난 작업은 취소한다
if ($CancelOnTimeout) {
    foreach ($pid_ in @($ids | Where-Object { -not (Test-TaskDone $_) })) {
        [void](Invoke-CancelTask $pid_ ("기다리는 한도({0}초)가 지나도 끝나지 않아 취소했습니다. 직접 처리하세요." -f $effectiveWait))
        $timedOut += $pid_
    }
}
foreach ($id in $ids) {
    $resp = Join-Path $script:OutboxDir "$id.response.md"
    $err = Join-Path $script:OutboxDir "$id.error.log"
    $hasResp = (Test-Path -LiteralPath $resp -PathType Leaf) -and ((Get-Item -LiteralPath $resp).Length -gt 0)
    $hasErr = (Test-Path -LiteralPath $err -PathType Leaf) -and ((Get-Item -LiteralPath $err).Length -gt 0)

    $isRejected = $false
    $errText = ""
    if ($hasErr) {
        $errText = Read-TextFile $err
        if ($errText -match '^\ufeff?지정한 @(model|cwd) ') {
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
