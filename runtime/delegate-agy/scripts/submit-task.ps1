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
#
# 출력(표준 출력):
#   submitted: <ID>                      (새로 넣었을 때)
#   ===RESULT=== <ID>  + 응답 본문         (응답 파일이 생김. 실패 사유도 응답으로 올 수 있으니 본문을 읽는다)
#   ===ERROR=== <ID>   + error.log 본문   (응답 없이 오류 로그만 있음)
#   ===PENDING=== <ID> + 진행 상태 한 줄    (시간 안에 안 끝남: 경과 시간·모델·마지막 단계. 작업은 계속 돌고 있다 — 다시 제출하지 말고 -Poll 로 확인)
# 종료 코드: 0 모두 결과 있음 / 1 오류가 있음 / 2 아직 진행 중 / 3 입력·환경 오류(런타임 폴더 없음, 지시문이 비었음 등)

param(
    [string]$File = "",
    [string[]]$Poll = @(),
    [switch]$NoWait,
    [int]$WaitSeconds = 170,
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

$script:RuntimeDirResolved = Resolve-RuntimeDirForSubmit $RuntimeDir
if (-not $script:RuntimeDirResolved) { Stop-WithCode 3 "위임 런타임 폴더(~/.samjil/delegate-agy/runtime)를 찾지 못했습니다. install.ps1 로 설치돼 있는지 확인하세요." }
$script:OutboxDir = (Get-AgyLayout $script:RuntimeDirResolved).OutboxDir
$inboxDir = Join-Path $script:RuntimeDirResolved "inbox"

# 기다릴 작업 ID 들
$ids = @()
foreach ($p in @($Poll)) { foreach ($x in ([string]$p -split '[,\s]+')) { if ($x) { $ids += $x } } }
foreach ($id in $ids) { if ($id -notmatch '^[A-Za-z0-9_-]{1,80}$') { Stop-WithCode 3 "작업 ID 형식이 맞지 않습니다: $id" } }

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
    # 브리프 점검(경고만): 검증 방법·범위 제한·대상 파일이 빠졌거나 너무 길면 보내기 전에 알린다. 위임은 그대로 진행한다. AGY_BRIEF_LINT=off 로 끈다.
    try {
        $lintLib = Join-Path $PSScriptRoot "sub\agy-brief-lint.ps1"
        if (Test-Path -LiteralPath $lintLib) {
            . $lintLib
            if (Test-AgyBriefLintEnabled) {
                $briefWarnings = @(Get-AgyBriefWarnings $text)
                foreach ($bw in $briefWarnings) { [Console]::Error.WriteLine("[브리프 점검] " + $bw) }
                if ($briefWarnings.Count -gt 0) { [Console]::Error.WriteLine("[브리프 점검] 위 항목은 경고일 뿐이라 위임은 그대로 진행합니다. 다음 위임부터 반영하거나, 빠진 것을 바로 채워 다시 보내려면 이 작업을 취소하세요.") }
            }
        }
    } catch {}
    $id = "claude_{0}_{1}" -f ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()), (Get-Random -Minimum 0 -Maximum 32768)
    # 쓰는 도중의 파일을 워처가 읽지 않게 임시 이름으로 쓰고 바꿔치기한다(.tmp 는 워처가 보지 않는다)
    $tmp = Join-Path $inboxDir "$id.md.tmp"
    [System.IO.File]::WriteAllText($tmp, $text, $utf8)
    Move-Item -LiteralPath $tmp -Destination (Join-Path $inboxDir "$id.md")
    Write-Output "submitted: $id"
    if ($NoWait) { exit 0 }
    $ids = @($id)
}

# 기다리기: 처음 60초는 3초 간격, 그 뒤는 10초 간격(대기는 이 프로세스 안에서 돌아 Claude 토큰을 쓰지 않는다)
$startedWait = Get-Date
$deadline = $startedWait.AddSeconds([math]::Max(0, $WaitSeconds))
while ($true) {
    $pending = @($ids | Where-Object { -not (Test-TaskDone $_) })
    if ($pending.Count -eq 0 -or (Get-Date) -ge $deadline) { break }
    $interval = if (((Get-Date) - $startedWait).TotalSeconds -lt 60) { 3 } else { 10 }
    $left = ($deadline - (Get-Date)).TotalSeconds
    Start-Sleep -Seconds ([math]::Max(1, [math]::Min($interval, [math]::Floor($left))))
}

$exit = 0
foreach ($id in $ids) {
    $resp = Join-Path $script:OutboxDir "$id.response.md"
    $err = Join-Path $script:OutboxDir "$id.error.log"
    if ((Test-Path -LiteralPath $resp -PathType Leaf) -and ((Get-Item -LiteralPath $resp).Length -gt 0)) {
        Write-Output "===RESULT=== $id"
        Write-Output (Read-TextFile $resp)
    } elseif ((Test-Path -LiteralPath $err -PathType Leaf) -and ((Get-Item -LiteralPath $err).Length -gt 0)) {
        Write-Output "===ERROR=== $id"
        Write-Output (Read-TextFile $err)
        if ($exit -lt 1) { $exit = 1 }
    } else {
        Write-Output ("===PENDING=== $id " + (Get-PendingStatus $id))
        $exit = 2
    }
}
exit $exit
