# watch-agy.ps1

# Antigravity CLI(agy) 파일 기반 지시/응답 워처 (PC별 독립 실행)

#

# 사용법:

#   1) runtime\inbox 폴더에 .txt 또는 .md 파일을 만들고 그 안에 agy에게 시킬 지시문을

#      적어 저장합니다. (예: inbox\작업1.md)

#   2) 이 스크립트를 PowerShell에서 실행해 둔 채로 둡니다.

#      감지되면 자동으로 agy CLI를 호출해서 처리하고,

#      runtime\outbox 폴더에 같은 이름 + .response.md 파일로 답변을 저장합니다.

#      처리한 지시파일은 data\tasks\processed 폴더로 이동합니다.

#   3) 종료하려면 이 창에서 Ctrl+C 를 누르세요.

#

# 설계 (docs\설계.md 3.2절 참고):

#   - 이 repo를 PC마다 각자 clone해서 쓰므로 "인스턴스 폴더"(PC별 하위 폴더) 개념이

#     없습니다. runtime\ 폴더 자체가 이미 이 PC 전용입니다 (.gitignore로 git 추적 제외).

#   - 화면 표시는 이 스크립트가 아니라 serve-report.ps1이 띄우는 로컬 웹 서버 + web\

#     페이지가 담당합니다. 이 스크립트는 data\delegate.db 의 위임 기록만 관리합니다.

#

# 주의: --dangerously-skip-permissions 는 헤드리스 실행 중 권한 확인 프롬프트 때문에

#       멈추는 것을 막기 위한 것입니다. agy가 실행할 수 있는 작업 범위를 신뢰할 수 있을 때만

#       사용하세요. 필요 없다면 아래에서 이 옵션을 지우세요.



param(
    [string]$RepoRoot    = "",
    [string]$RuntimeDir  = "",
    [int]$PollSeconds    = 2,
    [int]$MaxParallel    = 0,       # 한 번에 돌릴 작업 수(0 이면 환경변수 AGY_MAX_PARALLEL, 그것도 없으면 5)
    [string]$WorkerTask  = "",      # 내부용: 지시파일 하나만 처리하고 끝나는 작업자 모드(워처가 작업마다 띄운다)
    [switch]$SkipPermissions = $true,
    [string]$SubSlot      = "",     # 내부용: 부계정 워처/작업자 모드 슬롯 ID (예: sub1)
    [string]$SubBridgeDir = ""      # 내부용: 부계정 브리지 루트 경로 재정의
)

# 콘솔에서 한글이 깨지지 않도록 출력 인코딩을 UTF-8로 고정합니다.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$script:IsSubWatcher = -not [string]::IsNullOrWhiteSpace($SubSlot)
$script:RestartRequested = $false
$script:LastHandledRefreshSignalStamp = ""
$script:LastHandledQuotaSignalStamp = ""
$script:LastSubQuotaRefreshAt = $null
$script:WarnedRestartSignalLocked = $false

if (-not $RepoRoot) {
    $parent = Split-Path -Path $PSScriptRoot -Parent
    if ((Split-Path -Leaf $PSScriptRoot) -eq "sub") {
        $RepoRoot = Split-Path -Path $parent -Parent
    } else {
        $RepoRoot = $parent
    }
}

if (-not $script:IsSubWatcher) {
    if (-not $RuntimeDir) {
        if ($env:AGY_DELEGATE_RUNTIME) {
            $RuntimeDir = $env:AGY_DELEGATE_RUNTIME
        } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime")) {
            $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
        } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {
            $RuntimeDir = Join-Path $RepoRoot "runtime"
        } else {
            $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
        }
    }
}



# 동시에 돌릴 작업 수. 1 이면 예전처럼 한 번에 하나씩 처리한다.
if ($MaxParallel -le 0) {
    $MaxParallel = 5
    if ($env:AGY_MAX_PARALLEL -match '^\d+$' -and [int]$env:AGY_MAX_PARALLEL -gt 0) { $MaxParallel = [int]$env:AGY_MAX_PARALLEL }
}

# --- 모델 단계 (config\models.json) ---

# agy 응답 JSON에는 모델명이 담겨오지 않습니다 (CLI 자체 한계). 그래서 "어떤 모델을 쓸지 우리가 --model로 직접 지정"하고,
# 성공한 모델을 기록합니다(그래서 model 컬럼은 정확합니다).
# 모델은 단계(quick · build · build-hard · feature · feature-carbon · think · think-carbon · deep)로 고르고, 단계마다 주 모델과 폴백 순서가 설정 파일에 있습니다:
#   <delegate-agy>\config\models.json (기본, 동기화 · 설치가 덮어씀) + models.local.json (사용자 덮어쓰기). 읽기는 agy-models.ps1.
# 설정은 작업마다 다시 읽습니다(바꿔도 워처를 다시 켤 필요가 없습니다).
# 워처가 켜질 때 `agy models` 로 실제로 쓸 수 있는 모델 목록을 받아 $AvailableModelsFile 에 적고, 작업자는 그 목록에 없는 모델을 건너뜁니다.
$modelsLibFile = Join-Path $PSScriptRoot "agy-models.ps1"
if (-not (Test-Path $modelsLibFile)) { $modelsLibFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-models.ps1" }
. $modelsLibFile
$subBridgeLibFile = Join-Path $PSScriptRoot "agy-sub-bridge.ps1"
if (-not (Test-Path $subBridgeLibFile)) { $subBridgeLibFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-sub-bridge.ps1" }
if (Test-Path $subBridgeLibFile) { . $subBridgeLibFile }
$AvailableModelsFile = if ($RuntimeDir) { Join-Path $RuntimeDir "agy-models-available.json" } else { "" }

function Get-WatcherModelConfig { return (Get-AgyModelConfig) }

# 워처가 이번에 켜질 때 확인한 모델 목록(없거나 못 읽으면 빈 배열 = 확인하지 않은 것으로 보고 거르지 않는다).
# 워처는 켜질 때 먼저 이 파일을 지우고, 확인에 성공했을 때만 다시 쓴다(Update-AgyAvailableModelsFile).
function Get-WatcherAvailableModels {
    return @(Read-AgyAvailableModelsFile $AvailableModelsFile)
}

# 모델을 고르지 않았고 자동 선택도 꺼졌을 때 쓰는 단계(설정의 auto.write, 기본 build)의 모델 순서
function Get-WatcherDefaultChain {
    $cfg = Get-WatcherModelConfig
    $tier = if ($cfg.Auto -and $cfg.Auto.write) { [string]$cfg.Auto.write } else { "build" }
    $avail = @(Get-WatcherAvailableModels)
    return @(Get-AgyTierChain $cfg $tier $avail)
}

# 이 패턴에 걸리는 오류일 때만 "다음 모델로 자동 폴백"합니다 (쿼터 초과/요청 과다/일시적
# 사용 불가 등). 프롬프트 자체 문제 같은, 모델을 바꿔도 똑같이 실패할 오류까지 모든 모델로
# 재시도하면 시간만 낭비하므로 걸러냅니다.
$FallbackErrorPattern = '(?i)(quota|rate.?limit|429|resource.?exhausted|overloaded|unavailable|capacity|too many requests|exceeded|throttle|empty conversation id|authentication failed or timed out|is not recognized as a known model)'

# 폴백 대상 오류 판정: 일반 한도 · 과부하($FallbackErrorPattern) 또는 -xhigh 모델에서 effort/xhigh/thinking level 관련 HTTP 400.
function Test-AgyFallbackError([string]$ErrorText, [string]$Model) {
    if (-not $ErrorText) { return $false }
    if ($ErrorText -match $FallbackErrorPattern) { return $true }
    if ($Model -match '(?i)-xhigh$' -and
        $ErrorText -match '(?i)(?:\b400\b|HTTP\s*400|status(?:\s*code)?\s*[:=]?\s*400)' -and
        $ErrorText -match '(?i)(effort|xhigh|extra.?high|thinking.?level|thinking_level|thinking.?budget|reasoning.?effort)') {
        return $true
    }
    return $false
}

# --- 요청에서 고르는 모델 (@model:) ---
# 지시파일 맨 위에 "@model: <단계 또는 모델>" 줄을 씁니다.
#   단계 이름(quick · build · build-hard · feature · feature-carbon · think · think-carbon · deep, 옛 별칭 low · medium · high · think-argon · feature-argon): 그 단계의 주 모델부터, 폴백 순서대로.
#   모델 이름(설정의 allowed): 그 모델 하나만 씁니다. 쿼터 초과/사용 불가여도 다른 모델로 자동 전환하지 않고 실패로 기록합니다
#   (원하지 않은 모델의 결과를 조용히 받지 않게 하려는 것이고, 어떻게 할지는 Claude 가 정합니다).
# 단계도 모델도 아닌 값은 agy 를 부르지 않고 바로 실패 처리합니다.

# 지시파일 맨 위의 "@키: 값" 줄(순서 무관, 여러 줄 가능)을 읽고, 그 형식이 아닌 첫 줄부터를 프롬프트 본문으로 돌려줍니다.
#   @cwd:     agy 의 워크스페이스에 추가할 폴더 (--add-dir). 여러 줄 가능: 줄마다 폴더 하나, 폴더마다 --add-dir 를 한 번씩 넘긴다(줄 순서 유지, 같은 경로는 대소문자·끝의 \ 를 무시하고 한 번만)
#   @session: 대화를 이어갈 세션 이름
#   @model:   이번 호출의 모델 단계(quick · build · ...) 또는 모델 이름 하나 (위 설명)
#   @cmd:     실행 슬래시 명령(goal · swarm · run-workflow · boost · browser · plan). 파일 참조 시에도 명령이 확장되게 넘긴다
#   @mode:    실행 모드(plan · accept-edits · auto -> --mode 인자)
#   @raw:     true 면 워처가 표준 규칙(DO NOT COMMIT 등, agy-rules.ps1)을 프롬프트에 자동으로 붙이지 않는다
#   @upgrade: true 면 @session 으로 이어가는 대화에 다른 @model 을 줘도 오류 대신 "모델 승격"을 한다: 새 대화를 시작하고 이전 질문·답 글을 지시문 위에 붙인다(Resolve-RequestedModel)
# 반환: @{ Cwd; Session; Model; Cmd; Mode; Raw; Upgrade; Prompt }  (Cwd 는 폴더 배열이고 없으면 빈 배열, Session/Model/Cmd/Mode 는 없으면 $null, Raw/Upgrade 는 $true/$false)
function ConvertFrom-TaskDirectives([string]$rawText) {
    $cwdRaw = New-Object System.Collections.ArrayList; $session = $null; $model = $null; $cmd = $null; $mode = $null; $raw = $false; $upgrade = $false
    $prompt = $rawText
    while ($prompt.Length -gt 0) {
        $firstLine = ($prompt -split "`r?`n", 2)[0]
        if ($firstLine -match '^\s*$') {
            # 빈 줄은 건너뛰고 계속 파싱합니다
        } elseif ($firstLine -match '^\ufeff?@cwd:\s*(.+)$') {
            [void]$cwdRaw.Add($Matches[1].Trim())
        } elseif ($firstLine -match '^\ufeff?@session:\s*(.+)$') {
            $session = $Matches[1].Trim()
        } elseif ($firstLine -match '^\ufeff?@model:\s*(.+)$') {
            $model = $Matches[1].Trim()
        } elseif ($firstLine -match '^\ufeff?@cmd:\s*(.+)$') {
            $cmd = $Matches[1].Trim()
        } elseif ($firstLine -match '^\ufeff?@mode:\s*(.+)$') {
            $mode = $Matches[1].Trim()
        } elseif ($firstLine -match '^\ufeff?@raw:\s*(.+)$') {
            $raw = ConvertTo-AgyDirectiveFlag $Matches[1]
        } elseif ($firstLine -match '^\ufeff?@upgrade:\s*(.+)$') {
            $upgrade = ConvertTo-AgyDirectiveFlag $Matches[1]
        } else {
            break
        }
        $rest = ($prompt -split "`r?`n", 2)
        $prompt = if ($rest.Length -gt 1) { $rest[1] } else { "" }
    }
    return @{ Cwd = @(ConvertTo-CwdList $cwdRaw.ToArray()); Session = $session; Model = $model; Cmd = $cmd; Mode = $mode; Raw = $raw; Upgrade = $upgrade; Prompt = $prompt }
}

# 요청한 @model 을 확인합니다.
# 반환: @{ Model = <첫 모델 또는 $null>; Chain = <시도할 모델 순서>; Tier = <단계 이름 또는 "">; Kind = 'tier'|'model'|$null; Error; Upgrade }
#   - 단계 이름이면 그 단계의 모델 순서(폴백 포함, 워처가 확인한 목록에 없는 모델은 뺌), 모델 이름이면 그 모델 하나.
#   - 단계도 모델도 아니면 오류(대소문자는 구분하지 않고 정식 이름으로 바꿔 줍니다).
#   - 이어가는 세션(@session 으로 기존 대화를 잇는 경우)은 agy 가 시작할 때의 모델을 유지하므로,
#     다른 모델을 요청하면 조용히 무시하지 않고 오류로 알립니다(원래 대화를 지키려는 것: 실수로 모델을 잘못 적어도 대화가 바뀌지 않는다).
#     단계를 요청했으면 시작 모델이 그 단계의 모델 순서 안에 있을 때 같은 것으로 봅니다(폴백으로 시작한 대화도 그대로 잇는다).
#   - 단 @upgrade: true 를 명시했으면 오류 대신 Upgrade = $true 로 돌려줍니다(호출한 쪽이 새 대화를 시작하고 이전 질문·답 글을 붙인다).
#     이어가는 대화가 없거나 모델이 같으면 @upgrade 는 할 일이 없다(Upgrade = $false).
function Resolve-RequestedModel([string]$requested, [string]$conversationId, [string]$knownModel, [string]$sessionName, [bool]$upgrade = $false) {
    if (-not $requested) { return @{ Model = $null; Chain = @(); Tier = ""; Kind = $null; Error = $null; Upgrade = $false } }
    $spec = Resolve-AgyModelSpec $requested (Get-WatcherModelConfig) (Get-WatcherAvailableModels)
    if ($spec.Kind -eq "unknown") {
        return @{ Model = $null; Chain = @(); Tier = ""; Kind = $null; Error = $spec.Error; Upgrade = $false }
    }
    $base = @{ Model = [string]$spec.Model; Chain = @($spec.Chain); Tier = [string]$spec.Tier; Kind = [string]$spec.Kind; Error = $null; Upgrade = $false }
    if ($conversationId) {
        $same = if ($spec.Kind -eq "tier") { [bool]($knownModel -and (@($spec.Chain) -icontains $knownModel)) } else { [string]$spec.Model -ieq $knownModel }
        if (-not $same) {
            if ($upgrade) { $base.Upgrade = $true; return $base }
            $was = if ($knownModel) { $knownModel } else { "기록 없음" }
            $base.Error = "이어가는 세션 '$sessionName' 은 시작할 때의 모델($was)로 계속됩니다. 다른 모델($($spec.Model))을 쓰려면 @upgrade: true 를 지시문에 추가해 새 대화로 승격하거나(이전 질문·답 글을 붙여 줍니다. 파일 읽기 기록은 이어지지 않습니다), @session 없이 보내거나 새 세션 이름으로 보내세요."
            return $base
        }
    }
    return $base
}



$ComputerName = $env:COMPUTERNAME

if (-not $ComputerName) { $ComputerName = "(알수없음)" }



# 폴더 배치(runtime / data)는 agy-layout.ps1 한 곳에서 정한다. 옛 배치(runtime\outbox · runtime\logs\agy.db 등)면 폴더를 만들기 전에 먼저 옮긴다.
$layoutFile = Join-Path $PSScriptRoot "agy-layout.ps1"
if (-not (Test-Path $layoutFile)) { $layoutFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-layout.ps1" }
. $layoutFile
if ($script:IsSubWatcher) {
    $script:SubBridgeRoot = if (-not [string]::IsNullOrWhiteSpace($SubBridgeDir)) { $SubBridgeDir.Trim() } else { Get-AgySubBridgeRoot $null }
    $script:SubLayout     = Get-AgySubSlotLayout $script:SubBridgeRoot $SubSlot $ComputerName
    Initialize-AgySubSlotDirectories $script:SubLayout | Out-Null
    $RuntimeDir   = $script:SubLayout.SlotRoot
    $Layout       = @{
        DataDir         = $script:SubLayout.SlotRoot
        DbPath          = ""
        ProcessedDir    = (Join-Path $script:SubLayout.SlotRoot "processed")
        OutboxDir       = $script:SubLayout.OutboxDir
        StuckDir        = (Join-Path $script:SubLayout.SlotRoot "stuck")
        ScreenshotsDir  = (Join-Path $script:SubLayout.SlotRoot "screenshots")
        CacheDir        = (Join-Path $script:SubLayout.StatusDir "cache")
        BackupsDir      = (Join-Path $script:SubLayout.StatusDir "backups")
        InboxDir        = $script:SubLayout.InboxDir
        RunningDir      = $script:SubLayout.RunningDir
        PromptsDir      = $script:SubLayout.PromptsDir
        HeartbeatDir    = $script:SubLayout.HeartbeatDir
        LogsDir         = $script:SubLayout.StatusDir
        LockFile        = $script:SubLayout.LockFile
        StopSignalFile  = (Join-Path $script:SubLayout.StatusDir "stop.signal")
        ManualStopFlag  = (Join-Path $script:SubLayout.StatusDir "manual_stop.flag")
        CurrentTaskFile = (Join-Path $script:SubLayout.StatusDir "current_task.json")
    }
    $InboxDir     = $script:SubLayout.InboxDir
    $OutboxDir    = $script:SubLayout.OutboxDir
    $ProcessedDir = $Layout.ProcessedDir
    $StuckDir     = $Layout.StuckDir
    $LogsDir      = $script:SubLayout.StatusDir
    $RunningDir   = $script:SubLayout.RunningDir
    $LogFile      = Join-Path $LogsDir ("sub-watcher_{0}.log" -f $script:SubLayout.SlotId)
    $HeartbeatDir = $script:SubLayout.HeartbeatDir
    $HeartbeatFile = $script:SubLayout.HeartbeatFile
    $HeartbeatIntervalSec = 5
    $LockFile     = $script:SubLayout.LockFile
    $AvailableModelsFile = Join-Path $script:SubLayout.StatusDir "agy-models-available.json"
} else {
    $legacyMoved = Move-AgyLegacyLayout $RuntimeDir
    $Layout       = Get-AgyLayout $RuntimeDir $ComputerName
    $InboxDir     = $Layout.InboxDir
    $OutboxDir    = $Layout.OutboxDir
    $ProcessedDir = $Layout.ProcessedDir
    $StuckDir     = $Layout.StuckDir
    $LogsDir      = $Layout.LogsDir
    # 지금 돌고 있는 작업마다 <작업 ID>.json 표시 파일을 둔다(작업자 프로세스 PID·세션·폴더·모델). 워처와 뷰어가 읽는다.
    $RunningDir   = $Layout.RunningDir

    New-Item -ItemType Directory -Force -Path $InboxDir, $OutboxDir, $ProcessedDir, $StuckDir, $LogsDir, $RunningDir, $Layout.DataDir, $Layout.BackupsDir, $Layout.CacheDir | Out-Null

    # logs 폴더에는 진짜 런타임 로그(watcher.log 등)만 기록합니다.
    $LogFile        = Join-Path $LogsDir "watcher.log"

    $HeartbeatDir  = $Layout.HeartbeatDir
    New-Item -ItemType Directory -Force -Path $HeartbeatDir | Out-Null
    $HeartbeatFile = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $ComputerName)
    $HeartbeatIntervalSec = 10
    $LockFile = $Layout.LockFile
    $AvailableModelsFile = Join-Path $RuntimeDir "agy-models-available.json"
}

$LogMaxBytes    = 5MB      # 이 크기를 넘으면 오래된 부분을 잘라냅니다.

$LogKeepLines   = 2000     # 자를 때 남겨둘 최근 줄 수.

# 다른 스코프(엔진 종료 이벤트 핸들러 등)에서도 로그 파일 경로를 참조할 수 있도록 전역에도 둡니다.

$global:LogFile = $LogFile

$script:LastHeartbeatAt = [datetime]::MinValue



# 정지 신호 파일: stop-agy.ps1이 이 파일을 만들어두면, 아래 메인 루프가 폴링할 때마다

# 확인해서(Stop-Process로 강제로 죽이지 않고) 스스로 정상 종료합니다.

$StopSignalFile = $Layout.StopSignalFile



# 수동 정지 표시 파일: stop-agy.ps1이 정지 신호와 함께 이 파일도 남겨둡니다.

# watch-agy.ps1이 시작될 때(아래) 이 파일을 지우므로("다시 켜졌다"는 뜻), 워치독

# (ensure-agy-running.ps1)은 이 파일이 남아있는 동안은 "사용자가 일부러 끈 상태"로

# 판단하고 자동으로 재시작하지 않습니다.

$ManualStopFlag = $Layout.ManualStopFlag

# 공통 함수(세션 관리, 뮤텍스 락, 샤드/인덱스 관리 등)를 가져옵니다.
$commonFile = Join-Path $PSScriptRoot "common.ps1"
if (-not (Test-Path $commonFile)) {
    $commonFile = Join-Path (Split-Path $PSScriptRoot -Parent) "common.ps1"
}
. $commonFile


# 작업자 모드에서는 줄마다 "[작업 ID] "를 붙여 여러 작업의 로그가 섞여도 구분되게 한다.
$script:LogPrefix = ""
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $($script:LogPrefix)$msg"
    Write-Host $line
    try {
        if (-not (Test-Path $LogsDir)) {
            New-Item -ItemType Directory -Force -Path $LogsDir -ErrorAction SilentlyContinue | Out-Null
        }
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {
            Invoke-WithRuntimeLock {
                if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {
                    $tail = Get-Content -Path $LogFile -Tail $LogKeepLines -ErrorAction SilentlyContinue
                    Set-Content -Path $LogFile -Value $tail -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            } 10
        }
        # 다른 프로세스가 같은 순간 쓰고 있으면 잠깐 기다렸다가 다시 쓴다
        for ($try = 0; $try -lt 10; $try++) {
            try {
                [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
                break
            } catch { Start-Sleep -Milliseconds (20 + 20 * $try) }
        }
    } catch {}
}



# --- 사용량(모델/토큰/소요시간) 기록 ---
# 사용량은 위임 기록 DB(agy.db 의 tasks 표)에 작업 끝에 한 행씩 쓴다. CSV 는 필요할 때 tools\export-usage-csv.ps1 로 만든다.

# 참고: agy.exe 응답 JSON에는 model, cost 필드가 없습니다 (CLI 자체 한계, 2026-09 확인).
#       cost_usd는 알아낼 방법이 없어 칸에서 뺐습니다. model은 우리가 --model로 직접
#       지정해서 성공한 값이므로 그대로 신뢰해서 기록합니다.



function Get-JsonField($obj, [string[]]$paths) {

    foreach ($p in $paths) {

        $cur = $obj

        $ok = $true

        foreach ($part in ($p -split '\.')) {

            if ($null -ne $cur -and ($cur.PSObject.Properties.Name -contains $part)) {

                $cur = $cur.$part

            } else {

                $ok = $false

                break

            }

        }

        if ($ok -and $null -ne $cur -and $cur -ne "") { return $cur }

    }

    return $null

}






# ============================================================================

# 위임 기록 저장소 (SQLite: data\delegate.db, 접근은 agy-db.ps1)
# ----------------------------------------------------------------------------
#   tasks 표         : 작업 한 건이 한 줄. 사용량(토큰·모델)은 작업이 끝날 때 먼저 넣고(Write-UsageRow), 질문·답·과정은 지시파일을
#                      processed 로 옮긴 직후에 채운다(Complete-TaskQaRecord). 답이 채워진 줄이 "끝난 기록"이고 뷰어는 그것만 보인다.
#   agy_sessions 표  : @session: <이름> 으로 이어가는 agy 대화의 이름 <-> conversation_id (common.ps1 의 Read-Session/Write-Session).
#
# 화면은 뷰어(serve-viewer.ps1)가 이 DB 를 읽어 /api/qa/records 로 내보냅니다.
# ============================================================================

$AgyDbPath        = $Layout.DbPath
$KeepMonths       = 3      # 위임 기록 DB 와 위임 작업 파일(data 폴더)은 이보다 오래되면 워처가 켜질 때 자동으로 지웁니다.
# 기록에 저장하는 "과정"(agy 가 부른 도구 목록)의 최대 개수. 한 작업이 100~수백 번 도구를 부르는 일이 있어
# 기록이 커지는 것을 막는다. 1,500 단계를 넘으면 앞 300번과 뒤 1,200번을 남기고 가운데는 생략 표지 하나로 접는다.
$QaProcessMaxSteps = 1500

$SessionMaxAgeDays = 30    # 이보다 오래 안 쓴 세션은 자동으로 정리합니다.



# New-QaRecord / Read-Session / Write-Session 등은 common.ps1에서, DB 함수는 agy-db.ps1에서 로드됨
# 호출 하나가 "일하는 중인지 멈췄는지" 판정하는 헬퍼(agy-progress.ps1). 테스트: tests\delegate-agy
$progressFile = Join-Path $PSScriptRoot "agy-progress.ps1"
if (-not (Test-Path $progressFile)) {
    $progressFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-progress.ps1"
}
. $progressFile

# 요청의 난이도로 모델의 노력 단계(low / medium / high)를 자동으로 고르는 헬퍼(agy-autotier.ps1). 테스트: tests\delegate-agy
$autoTierFile = Join-Path $PSScriptRoot "agy-autotier.ps1"
if (-not (Test-Path $autoTierFile)) {
    $autoTierFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-autotier.ps1"
}
. $autoTierFile

# 폴더(@cwd)를 여는 코딩 위임에 표준 규칙(DO NOT COMMIT · FOREGROUND · 한글 답변 등)을 호출 직전에 붙이는 헬퍼(agy-rules.ps1). 테스트: tests\delegate-agy
$rulesFile = Join-Path $PSScriptRoot "agy-rules.ps1"
if (-not (Test-Path $rulesFile)) {
    $rulesFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-rules.ps1"
}
. $rulesFile

# 코딩 위임 전후의 git 상태(HEAD · 브랜치 · stash)를 비교해 agy 가 임의로 바꿨으면 응답 맨 위에 경고를 붙이는 안전장치(agy-gitguard.ps1). 테스트: tests\delegate-agy
$gitGuardFile = Join-Path $PSScriptRoot "agy-gitguard.ps1"
if (-not (Test-Path $gitGuardFile)) {
    $gitGuardFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-gitguard.ps1"
}
. $gitGuardFile

# 백그라운드 프로세스 무창 실행 헬퍼(agy-spawn.ps1). CreateProcessW(CREATE_NO_WINDOW + STARTF_USESHOWWINDOW/SW_HIDE)
$spawnFile = Join-Path $PSScriptRoot "agy-spawn.ps1"
if (-not (Test-Path $spawnFile)) {
    $spawnFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-spawn.ps1"
}
if (Test-Path $spawnFile) { . $spawnFile }

# 위임 작업 파일(processed · outbox · 스크린샷 등) 보관 기간 정리(agy-retention.ps1). 테스트: tests\delegate-agy\agy-retention.tests.ps1
$retentionFile = Join-Path $PSScriptRoot "agy-retention.ps1"
if (-not (Test-Path $retentionFile)) {
    $retentionFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-retention.ps1"
}
. $retentionFile

# agy 남은 한도 실측 파싱 · 캐시(agy-quota.ps1). 테스트: tests\delegate-agy\agy-quota.tests.ps1
$quotaLibFile = Join-Path $PSScriptRoot "agy-quota.ps1"
if (-not (Test-Path $quotaLibFile)) {
    $quotaLibFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-quota.ps1"
}
if (Test-Path $quotaLibFile) { . $quotaLibFile }
$usageHistLibFile = Join-Path $PSScriptRoot "usage-history.ps1"
if (-not (Test-Path $usageHistLibFile)) {
    $usageHistLibFile = Join-Path (Split-Path $PSScriptRoot -Parent) "usage-history.ps1"
}
if (Test-Path $usageHistLibFile) { . $usageHistLibFile }

$doctorLib = Join-Path $PSScriptRoot "agy-failure-doctor.ps1"
if (Test-Path -LiteralPath $doctorLib) { try { . $doctorLib } catch {} }

$script:LastFailureDoctorAt = [datetime]::MinValue

if ($script:IsSubWatcher) {
    try {
        $subStartCfg = Get-WatcherModelConfig
        if ($subStartCfg -and $subStartCfg.SubAccounts -and $subStartCfg.SubAccounts.AgyBinDir) {
            $bDirW = [string]$subStartCfg.SubAccounts.AgyBinDir
            if ((Test-Path -LiteralPath $bDirW -PathType Container) -and ($env:PATH -notlike "*$bDirW*")) {
                $env:PATH = "$bDirW;$env:PATH"
            }
        }
    } catch {}
}



# 워처가 켜질 때 한 번만: 보관 기간이 지난 기록을 정리합니다.

function Initialize-QaStore {
    if ($script:IsSubWatcher -or -not $AgyDbPath) { return }
    try {
        $filesRemoved = Remove-DelegationFilesOlderThan $RuntimeDir $KeepMonths
        if ($filesRemoved -gt 0) { Log "보관 기간($KeepMonths 개월)이 지난 위임 작업 파일 $filesRemoved 개를 정리했습니다." }
    } catch {
        Log "위임 작업 파일 정리 중 오류: $($_.Exception.Message)"
    }
    try {
        $removed = Remove-QaRecordsOlderThan $AgyDbPath $KeepMonths
        if ($removed -gt 0) { Log "보관 기간($KeepMonths 개월)이 지난 기록 $removed 건을 정리했습니다." }
    } catch {
        Log "기록 저장소 초기화 중 오류: $($_.Exception.Message)"
    }
}



# tasks 표의 행 하나(없는 칸은 NULL)로 완성된 기록 레코드를 만듭니다.
# Sync-QaStore(사용량 행만 있는 작업을 채움)와 작업자의 마무리(Complete-TaskQaRecord)가 같은 레코드를 만들도록 한 곳에 둡니다.
# $QuestionPath 를 주면 그 지시파일을 질문으로 쓰고, 안 주면 processed 폴더에서 작업 ID 로 찾습니다.
function New-QaRecordFromRow($r, [string]$QuestionPath = "", [string]$ExplicitTranscriptPath = "") {
    $taskId = [string]$r.task_id

    if (-not $QuestionPath) {
        $qFile = Get-ChildItem -Path $ProcessedDir -Filter "$taskId.*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($qFile) { $QuestionPath = $qFile.FullName }
    }
    $qText = if ($QuestionPath -and (Test-Path -LiteralPath $QuestionPath)) {
        Get-Content -Raw -LiteralPath $QuestionPath -Encoding UTF8 -ErrorAction SilentlyContinue
    } else { "(원본 지시파일을 찾을 수 없음 - 이미 정리되었을 수 있습니다)" }

    $aPath = Join-Path $OutboxDir "$taskId.response.md"
    $aText = if (Test-Path $aPath) {
        Get-Content -Raw -Path $aPath -Encoding UTF8 -ErrorAction SilentlyContinue
    } else { "(응답 파일 없음)" }

    # 과정(agy 가 부른 도구 목록)도 같이 기록한다. agy 의 대화 기록은 나중에 정리될 수 있어서 작업이 끝난 직후에
    # 저장해 둔다. 대화 기록을 못 읽으면(대화 id 없음/파일 없음) $null = "모름", 읽었는데 도구를 안 썼으면 @() = "없음".
    $processSteps = $null
    $tPath = if ($ExplicitTranscriptPath -and (Test-Path -LiteralPath $ExplicitTranscriptPath -PathType Leaf)) {
        $ExplicitTranscriptPath
    } elseif ($r.session_id) {
        Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$r.session_id)
    } else {
        $null
    }
    if ($tPath -and (Test-Path -LiteralPath $tPath)) {
        $since = $null
        if ($r.session -and $r.timestamp -and $null -ne $r.elapsed_sec -and ([string]$r.elapsed_sec) -ne "") {
            try {
                $tsDate = [datetime]::Parse([string]$r.timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
                $el = [double]$r.elapsed_sec
                $since = $tsDate.AddSeconds(-($el + 5))
            } catch {}
        }
        $processSteps = @((Read-AgyProcessSteps $tPath 0 $QaProcessMaxSteps 500 300 $since).Steps)
    }

    $rowDict = [ordered]@{
        timestamp       = [string]$r.timestamp
        computer_name   = [string]$r.computer_name
        task_id         = $taskId
        model           = [string]$r.model
        attempts        = [string]$r.attempts
        tried_models    = [string]$r.tried_models
        input_tokens    = [string]$r.input_tokens
        output_tokens   = [string]$r.output_tokens
        thinking_tokens = [string]$r.thinking_tokens
        total_tokens    = [string]$r.total_tokens
        elapsed_sec     = [string]$r.elapsed_sec
        status          = [string]$r.status
        session         = [string]$r.session
        session_id      = [string]$r.session_id
        account         = if ($r.PSObject.Properties['account'] -and $r.account) { [string]$r.account } else { "primary" }
        question        = $qText
        answer          = $aText
        process         = $processSteps
    }
    if ($r.PSObject.Properties['fallback_from'] -and $r.fallback_from) { $rowDict['fallback_from'] = [string]$r.fallback_from }
    if ($r.PSObject.Properties['account_note'] -and $r.account_note)   { $rowDict['account_note']  = [string]$r.account_note }
    if ($r.cum_input_tokens)    { $rowDict['cum_input_tokens']    = [string]$r.cum_input_tokens }
    if ($r.cum_output_tokens)   { $rowDict['cum_output_tokens']   = [string]$r.cum_output_tokens }
    if ($r.cum_thinking_tokens) { $rowDict['cum_thinking_tokens'] = [string]$r.cum_thinking_tokens }
    if ($r.cum_total_tokens)    { $rowDict['cum_total_tokens']    = [string]$r.cum_total_tokens }
    if ($r.usage_basis)         { $rowDict['usage_basis']         = [string]$r.usage_basis }
    return New-QaRecord $rowDict
}

# 사용량 행만 있고 질문·답이 아직 안 채워진 작업을 찾아서 채웁니다(워처가 켜질 때, 사라진 작업을 정리할 때).
function Sync-QaStore {
    $added = 0
    try {
        foreach ($r in @(Get-QaIncompleteRows $AgyDbPath)) {
            if ([string]::IsNullOrWhiteSpace([string]$r.task_id)) { continue }
            $rec = New-QaRecordFromRow $r
            if ((Write-QaRecordToDb $AgyDbPath $rec 'FillIfIncomplete') -eq 'saved') { $added++ }
        }
    } catch {
        Log "기록 저장소 동기화 중 오류: $($_.Exception.Message)"
    }
    return $added
}

# agy 위임이 끝난 직후 남은 한도를 실측해 task_quota 표에 기록한다(최초 1회, 덮어쓰지 않음).
# 실패해도 워처 루프나 완료 기록 저장을 막지 않는다.
function Save-TaskFinishQuota([string]$TaskId, $Row, [scriptblock]$UsageRunner = $null, [datetime]$NowUtc = [datetime]::MinValue) {
    try {
        if (-not $TaskId -or $null -eq $Row) { return $false }
        $model = [string]$Row.model
        if ($model -notmatch '(?i)gemini|orchestrator') { return $false }

        $tok = 0L
        if (-not [long]::TryParse([string]$Row.total_tokens, [ref]$tok) -or $tok -le 0) { return $false }
        if (-not (Get-Command ConvertFrom-AgyUsageText -ErrorAction SilentlyContinue)) { return $false }

        $raw = $null
        if ($null -ne $UsageRunner) {
            $raw = & $UsageRunner
        } elseif (Test-Path Env:\AGY_TEST_USAGE_TEXT) {
            $raw = $env:AGY_TEST_USAGE_TEXT
        } elseif (Get-Command Invoke-AgyUsageCommand -ErrorAction SilentlyContinue) {
            $raw = Invoke-AgyUsageCommand "agy" 20
        }
        if (-not $raw) { return $false }

        $parsed = (ConvertFrom-AgyUsageText ([string]$raw))
        if (-not $parsed.Contains('gemini_5h') -and -not $parsed.Contains('gemini_weekly')) { return $false }

        $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
        $measuredAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")

        # 방금 받은 신선한 출력으로 agy-quota.json 캐시도 함께 갱신한다.
        if ($RuntimeDir -and (Get-Command Get-AgyQuotaSnapshot -ErrorAction SilentlyContinue)) {
            $qCacheFile = Join-Path $RuntimeDir "agy-quota.json"
            $rawCopy = [string]$raw
            try { [void](Get-AgyQuotaSnapshot $qCacheFile 0 { return $rawCopy } -NowUtc $now) } catch {}
        }

        $fiveUsed = $null; $fiveReset = $null
        if ($parsed.Contains('gemini_5h')) {
            $e5 = $parsed.Item('gemini_5h')
            $fiveUsed = 100.0 - [double]$e5.pct
            $fiveReset = [string]$e5.reset
        }
        $weekUsed = $null; $weekReset = $null
        if ($parsed.Contains('gemini_weekly')) {
            $ew = $parsed.Item('gemini_weekly')
            $weekUsed = 100.0 - [double]$ew.pct
            $weekReset = [string]$ew.reset
        }

        $concurrent = 0
        if ($RunningDir -and (Test-Path -LiteralPath $RunningDir -PathType Container)) {
            $ownClaimName = "{0}.json" -f $TaskId
            $otherClaims = @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ine $ownClaimName })
            if ($otherClaims.Count -gt 0) { $concurrent = 1 }
        }

        if ($AgyDbPath -and (Get-Command Save-TaskQuota -ErrorAction SilentlyContinue)) {
            $db = Open-AgyDb $AgyDbPath
            try {
                return [bool](Save-TaskQuota $db $TaskId $measuredAt $fiveUsed $fiveReset $weekUsed $weekReset $concurrent)
            } finally {
                $db.Dispose()
            }
        }
        return $false
    } catch {
        Log "한도 실측 저장 중 오류($TaskId): $($_.Exception.Message)"
        return $false
    }
}

# 위임이 끝난 직후 대화 기록에서 실제 실행 모델별 토큰을 task_models 표에 저장한다(최초 1회, 덮어쓰지 않음).
# 실패해도 워처 루프나 완료 기록 저장을 막지 않는다.
function Save-TaskFinishModels([string]$TaskId, $Row, $ProcessSteps = $null, [string]$TranscriptPath = "") {
    try {
        if (-not $TaskId -or $null -eq $Row -or -not $AgyDbPath) { return $false }
        if (-not (Get-Command Save-TaskModels -ErrorAction SilentlyContinue)) { return $false }
        if (-not (Get-Command New-AgyUsageState -ErrorAction SilentlyContinue)) { return $false }

        $tp = $null
        if ($TranscriptPath -and (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) {
            $tp = $TranscriptPath
        } elseif ($Row.session_id) {
            $sid = [string]$Row.session_id
            if (Get-Command Get-AgyTranscriptUsageFile -ErrorAction SilentlyContinue) {
                $tp = Get-AgyTranscriptUsageFile (Get-AgyHomeDir) $sid
            } else {
                $cand = Get-AgyTranscriptPath (Get-AgyHomeDir) $sid
                if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) { $tp = $cand }
            }
        }
        if (-not $tp) { return $false }

        $st = New-AgyUsageState $tp
        Update-AgyUsageState $st
        $range = if (Get-Command Resolve-AgyTaskStepRange -ErrorAction SilentlyContinue) {
            Resolve-AgyTaskStepRange $st $ProcessSteps $Row
        } else {
            @{ MinStep = 0; MaxStep = 0 }
        }
        $sum = Get-AgyUsageSummary $st $range.MaxStep $null $range.MinStep
        if ($null -eq $sum) { return $false }
        # 컨텍스트 크기(실측 통계가 보여 준다)는 모델 기록이 없어도 따로 남긴다.
        if (Get-Command Save-TaskContext -ErrorAction SilentlyContinue) { try { [void](Save-TaskContext $AgyDbPath $TaskId $sum.Context) } catch {} }
        if (@($sum.ByModel).Count -eq 0) { return $false }
        return [bool](Save-TaskModels $AgyDbPath $TaskId $sum.ByModel)
    } catch {
        Log "모델별 토큰 저장 중 오류($TaskId): $($_.Exception.Message)"
        return $false
    }
}

# 작업자가 작업 하나를 끝낼 때의 마무리: 지시파일을 processed 로 옮기고, 그 작업의 행(사용량 행은 Write-UsageRow 가 먼저 넣었다)에
# 질문·답·과정을 채운다. 작업자는 작업마다 새 프로세스라 전체 기록을 읽지 않고 이 한 건만 다룬다.
# 사용량 행이 없거나 채우다 오류가 나면 미완료 작업 전체를 채우는 보충(Update-QAReport)으로 물러선다.
function Complete-TaskQaRecord([string]$TaskId, [string]$SourcePath, [string]$DonePath, [string]$ExplicitTranscriptPath = "", $ExplicitModels = $null, $ExplicitContextTokens = $null) {
    Move-Item -Path $SourcePath -Destination $DonePath -Force
    try {
        $row = Get-QaTaskRow $AgyDbPath $TaskId
        if ($null -eq $row) { Update-QAReport; return }       # 사용량 행을 못 썼다: 있는 미완료 작업이라도 채워 둔다
        if ($null -ne $row.answer) { return }                  # 이미 채워졌다(워처가 켜질 때의 보충이 먼저 한 경우)
        $rec = New-QaRecordFromRow $row $DonePath $ExplicitTranscriptPath
        if ((Write-QaRecordToDb $AgyDbPath $rec 'FillIfIncomplete') -eq 'pending') { Log "기록을 DB 에 바로 쓰지 못해 pending 폴더에 두었습니다: $TaskId" }
        $rowAcct = if ($row.PSObject.Properties['account'] -and $row.account) { [string]$row.account } else { "primary" }
        if ($rowAcct -eq "primary" -and (Get-Command Save-TaskFinishQuota -ErrorAction SilentlyContinue)) {
            try { [void](Save-TaskFinishQuota $TaskId $row) } catch {}
        }
        if ($null -ne $ExplicitContextTokens -and (Get-Command Save-TaskContext -ErrorAction SilentlyContinue)) {
            try { [void](Save-TaskContext $AgyDbPath $TaskId $ExplicitContextTokens) } catch {}
        }
        $savedModels = $false
        if ($null -ne $ExplicitModels -and @($ExplicitModels).Count -gt 0 -and (Get-Command Save-TaskModels -ErrorAction SilentlyContinue)) {
            try { $savedModels = [bool](Save-TaskModels $AgyDbPath $TaskId @($ExplicitModels)) } catch {}
        }
        if (-not $savedModels -and (Get-Command Save-TaskFinishModels -ErrorAction SilentlyContinue)) {
            try { [void](Save-TaskFinishModels $TaskId $row $rec['process'] $ExplicitTranscriptPath) } catch {}
        }
    } catch {
        Log "기록 저장소에 작업 한 건을 채우다 오류가 나서 전체 보충으로 대신합니다: $($_.Exception.Message)"
        Update-QAReport
    }
}

# 사용량 행(tasks 표)을 쓴다: 작업이 끝났을 때 한 번.
function Write-UsageRow($taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, [string]$session = "", [string]$sessionId = "", $cumInputTokens = $null, $cumOutputTokens = $null, $cumThinkingTokens = $null, $cumTotalTokens = $null, [string]$usageBasis = "", [string]$account = "primary", [string]$fallbackFrom = "", [string]$accountNote = "") {
    try {
        $acctNorm = if ([string]::IsNullOrWhiteSpace($account)) { "primary" } else { $account.Trim() }
        $recDict = [ordered]@{
            timestamp       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            computer_name   = $ComputerName
            task_id         = [string]$taskId
            model           = $model
            attempts        = $attempts
            tried_models    = $triedModels
            input_tokens    = $inputTokens
            output_tokens   = $outputTokens
            thinking_tokens = $thinkingTokens
            total_tokens    = $totalTokens
            elapsed_sec     = $elapsedSec
            status          = $status
            session         = $session
            session_id      = $sessionId
            account         = $acctNorm
        }
        if (-not [string]::IsNullOrWhiteSpace($fallbackFrom)) { $recDict['fallback_from'] = $fallbackFrom.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($accountNote))  { $recDict['account_note']  = $accountNote.Trim() }
        if ($null -ne $cumInputTokens)    { $recDict['cum_input_tokens']    = [string]$cumInputTokens }
        if ($null -ne $cumOutputTokens)   { $recDict['cum_output_tokens']   = [string]$cumOutputTokens }
        if ($null -ne $cumThinkingTokens) { $recDict['cum_thinking_tokens'] = [string]$cumThinkingTokens }
        if ($null -ne $cumTotalTokens)    { $recDict['cum_total_tokens']    = [string]$cumTotalTokens }
        if ($usageBasis)                  { $recDict['usage_basis']         = [string]$usageBasis }
        $rec = New-QaRecord $recDict
        # 같은 작업 ID 의 사용량 행이 이미 있으면 먼저 쓴 것을 둔다(InsertOnly). DB 를 잠깐 못 쓰면 pending 폴더에 두었다가 다음에 가져온다.
        if ((Write-QaRecordToDb $AgyDbPath $rec 'InsertOnly') -eq 'pending') { Log "사용량 기록을 DB 에 바로 쓰지 못해 pending 폴더에 두었습니다: $taskId" }
    } catch {
        Log "사용량 기록 중 오류: $($_.Exception.Message)"
    }
}
function Update-QAReport {
    if ($script:IsSubWatcher -or -not $AgyDbPath) { return }
    [void](Sync-QaStore)
}

function Get-SubTaskBaseId([string]$FileName) {
    if ($FileName -match '^(.+?)\.task\.json$') { return $Matches[1] }
    return [System.IO.Path]::GetFileNameWithoutExtension($FileName)
}

function Sync-SubTranscriptMirror([string]$AgyHome, [string]$ConvId, [string]$TaskId, [int64]$LastLen = -1) {
    if (-not $script:IsSubWatcher -or [string]::IsNullOrWhiteSpace($ConvId) -or [string]::IsNullOrWhiteSpace($TaskId)) { return $LastLen }
    try {
        $src = $null
        if (Get-Command Get-AgyTranscriptPath -ErrorAction SilentlyContinue) {
            $cand = Get-AgyTranscriptPath $AgyHome $ConvId
            if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) { $src = $cand }
            elseif ($cand) {
                $alt = Join-Path (Split-Path -Parent $cand) "transcript.jsonl"
                if (Test-Path -LiteralPath $alt -PathType Leaf) { $src = $alt }
            }
        }
        if (-not $src) { return $LastLen }
        $fi = Get-Item -LiteralPath $src -ErrorAction SilentlyContinue
        if ($null -eq $fi -or $fi.Length -le 0) { return $LastLen }
        $dst = Join-Path $script:SubLayout.TranscriptsDir ("{0}.jsonl" -f $TaskId)
        $dstExists = Test-Path -LiteralPath $dst -PathType Leaf
        if ($dstExists -and $fi.Length -eq $LastLen) { return $LastLen }

        $fs = New-Object System.IO.FileStream($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            if ($dstExists -and $LastLen -gt 0 -and $fi.Length -gt $LastLen) {
                $deltaLen = [int]($fi.Length - $LastLen)
                [void]$fs.Seek($LastLen, [System.IO.SeekOrigin]::Begin)
                $deltaBytes = New-Object byte[] $deltaLen
                $deltaRead = 0
                while ($deltaRead -lt $deltaLen) {
                    $r = $fs.Read($deltaBytes, $deltaRead, ($deltaLen - $deltaRead))
                    if ($r -le 0) { break }
                    $deltaRead += $r
                }
                if ($deltaRead -gt 0) {
                    $appFs = New-Object System.IO.FileStream($dst, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
                    try { $appFs.Write($deltaBytes, 0, $deltaRead) } finally { $appFs.Dispose() }
                }
                return [int64]($LastLen + $deltaRead)
            }

            $bytes = New-Object byte[] $fs.Length
            $offset = 0
            while ($offset -lt $bytes.Length) {
                $read = $fs.Read($bytes, $offset, ($bytes.Length - $offset))
                if ($read -le 0) { break }
                $offset += $read
            }
            $tmp = "{0}.{1}.tmp" -f $dst, $PID
            $outFs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $outFs.Write($bytes, 0, $offset) } finally { $outFs.Dispose() }
            if ($dstExists) {
                try {
                    [System.IO.File]::Replace($tmp, $dst, [NullString]::Value, $true)
                } catch {
                    [void](Remove-AgyFileSafe $dst)
                    [System.IO.File]::Move($tmp, $dst)
                }
            } else {
                [System.IO.File]::Move($tmp, $dst)
            }
            return [int64]$offset
        } finally {
            $fs.Dispose()
        }
    } catch { return $LastLen }
}

# agy 한 번 호출이 이 시간을 넘기면 강제로 중단하고 그 작업을 실패 처리합니다.

# (없으면 agy가 멈췄을 때 워처 전체가 무한정 묶입니다 - 실제로 agy가 콘솔 입력을

#  기다리는 바람에 워처가 13분 넘게 그 자리에서 멈춘 적이 있습니다.)

$AgyTimeoutSeconds = 1800
$AgyTimeoutSeconds = Get-AgySecondsSetting 'AGY_TIMEOUT_SECONDS' 1800 60   # 환경변수 AGY_TIMEOUT_SECONDS(60 이상)로 바꿀 수 있다
# 절대 마감을 넘겨도 agy 가 진짜 일하는 중이면(새 단계·도구 출력·CPU) 바로 끊지 않고 이 시간까지 더 기다린다. 이 시간이 지나면 일하는 중이어도 끊는다.
$AgyHardTimeoutSeconds = [Math]::Max((Get-AgySecondsSetting 'AGY_HARD_TIMEOUT_SECONDS' 7200 60), $AgyTimeoutSeconds)   # 환경변수 AGY_HARD_TIMEOUT_SECONDS 로 바꿀 수 있다(마감보다 작으면 마감과 같게)

# 위 절대 마감과 별개로, agy 대화 기록에 새 단계가 이 시간 동안 하나도 없으면 "확인 중"으로 전환해
# 모델 요청 진행 중(cli-*.log) · 도구 자식 프로세스 CPU 활동을 확인하고, 활성 신호도 없이 유예 시간(AGY_STALL_GRACE_SECONDS)이
# 지나면 실행을 중단한 뒤 같은 대화에 진행 상황을 묻습니다(최대 2회).
# 이 값의 근거와 한계는 agy-progress.ps1 머리말을 보세요.
$AgyStallSeconds = 300
$AgyStallSeconds = Get-AgySecondsSetting 'AGY_STALL_SECONDS' 300 30   # 환경변수 AGY_STALL_SECONDS(30 이상)로 바꿀 수 있다
$AgyStallGraceSeconds = 300
$AgyStallGraceSeconds = Get-AgySecondsSetting 'AGY_STALL_GRACE_SECONDS' 300 0    # 환경변수 AGY_STALL_GRACE_SECONDS(0 이상)로 바꿀 수 있다
$AgyThinkMaxSeconds = 1200
$AgyThinkMaxSeconds = Get-AgySecondsSetting 'AGY_THINK_MAX_SECONDS' 1200 30   # 환경변수 AGY_THINK_MAX_SECONDS(30 이상, 기본 1200 = 총 침묵 20분)로 바꿀 수 있다
$AgyToolMaxSeconds = 1800
$AgyToolMaxSeconds = Get-AgySecondsSetting 'AGY_TOOL_MAX_SECONDS' 1800 30     # 환경변수 AGY_TOOL_MAX_SECONDS(30 이상, 기본 1800 = 총 침묵 30분)로 바꿀 수 있다
$AgyStallProbeIntervalSeconds = 60   # 확인 중/생각 중/명령 실행 중 재확인 주기(초)
$AgyStallMaxAsks = 2                 # 작업당 같은 대화에 진행 상황을 묻는 최대 횟수
$AgyStallAskPrompt = "직전 실행이 응답 없이 10분 넘게 멈춰 중단했습니다. 대화 기록을 보고 판단하세요. 1) 이미 끝났다면 최종 답변만 그대로 다시 쓰세요. 2) 남은 일이 있으면 이어서 끝까지 진행하고 최종 답변을 쓰세요. 3) 진행할 수 없으면 첫 줄에 [진행 불가] 와 사유를 쓰세요."
# 마감/멈춤을 점검하는 주기(초)
$AgyPollSeconds = 30
# 오래 걸리는 호출의 진행 상황(경과 시간, 마지막 활동)을 로그에 남기는 주기(초)
$AgyProgressLogSeconds = 600
# 시작 직후 이번 호출이 만든 대화를 찾는 데 쓰는 시간 창(초)
$AgyConversationWindowSeconds = 120



# agy를 "백그라운드 작업"으로 한 번 실행하고, 타임아웃을 걸어 기다립니다.
# agy 는 창이 아예 없는 프로세스(CreateNoWindow)로 직접 띄웁니다. 예전처럼 Start-Job 으로 PowerShell 을 한 겹 더 띄우고
# 그 안에서 chcp·agy 를 부르면, 환경에 따라 콘솔 창이 잠깐 떴다 사라지는 일이 생길 수 있어서입니다.
# 콘솔이 붙어 있지 않으므로 agy(또는 agy가 실행한 명령)가 입력을 요구해도 즉시 EOF 가 되어 무한 대기에 빠지지 않습니다
# (표준입력을 바로 닫는다). 이것이 "agy가 콘솔 입력을 기다리며 워처가 13분 넘게 멈춘" 사고의 방지책이고,
# 타임아웃은 그 밖의 이유로 멈추는 경우를 위한 안전장치입니다.
#
# 반환: @{ TimedOut = $true/$false; Raw = <agy 표준출력(문자열)> }
function Invoke-AgyOnce($agyArgs, $errFile, $workDir, [string]$marker = "", [string]$initialProbeState = "") {
    # agy 에 넘길 인자 하나를 명령줄 조각으로 만든다(공백·따옴표·끝의 역슬래시를 Windows 규칙대로 감싼다).
    function ConvertTo-AgyCommandLineArg([string]$Arg) {
        if ($null -eq $Arg) { return '""' }
        if ($Arg.Length -gt 0 -and $Arg -notmatch '[\s"]') { return $Arg }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $backslashes = 0
        foreach ($ch in $Arg.ToCharArray()) {
            if ($ch -eq [char]92) {
                $backslashes++
            } elseif ($ch -eq [char]34) {
                [void]$sb.Append([string]::new([char]92, $backslashes * 2 + 1))
                [void]$sb.Append('"')
                $backslashes = 0
            } else {
                if ($backslashes -gt 0) { [void]$sb.Append([string]::new([char]92, $backslashes)); $backslashes = 0 }
                [void]$sb.Append($ch)
            }
        }
        if ($backslashes -gt 0) { [void]$sb.Append([string]::new([char]92, $backslashes * 2)) }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    $proc       = $null
    $outTask    = $null
    $errTask    = $null
    $useSpawned = $false
    try {
        $agyCmd = Get-Command agy -CommandType Application -ErrorAction Stop | Select-Object -First 1
        if (-not (Get-Command Start-AgySpawnedProcess -ErrorAction SilentlyContinue)) {
            $candidates = @()
            if ($PSScriptRoot) {
                $candidates += (Join-Path $PSScriptRoot "agy-spawn.ps1")
                $pParent = Split-Path $PSScriptRoot -Parent
                if ($pParent) { $candidates += (Join-Path $pParent "agy-spawn.ps1") }
            }
            if ($script:SubDir) { $candidates += (Join-Path $script:SubDir "agy-spawn.ps1") }
            $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
            $candidates += (Join-Path $home_ ".samjil\delegate-agy\scripts\sub\agy-spawn.ps1")
            foreach ($c in $candidates) {
                if ($c -and (Test-Path -LiteralPath $c)) { . $c; break }
            }
        }
        $spawnCwd = if ($workDir -and (Test-Path -LiteralPath $workDir)) { [string]$workDir } else { "" }
        if (Get-Command Start-AgySpawnedProcess -ErrorAction SilentlyContinue) {
            # 무창 헬퍼가 실패하면(형식 로드 · 파이프 · CreateProcess 오류) 작업을 실패시키지 않고 아래 기본 방식으로 대신한다
            try {
                $proc = Start-AgySpawnedProcess -FilePath $agyCmd.Source -ArgumentList $agyArgs -WorkingDirectory $spawnCwd
                $useSpawned = $true
            } catch {
                $proc = $null
                $useSpawned = $false
                Log "  창 없는 실행 헬퍼로 agy 를 띄우지 못해 기본 방식으로 대신합니다: $($_.Exception.Message)"
            }
        }
        if (-not $useSpawned) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = $agyCmd.Source
            $psi.Arguments              = (@($agyArgs | ForEach-Object { ConvertTo-AgyCommandLineArg ([string]$_) }) -join ' ')
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true
            $psi.RedirectStandardInput  = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            # agy 는 UTF-8 로 돌려준다. 이걸 명시하지 않으면 한글이 시스템 코드페이지(CP949)로 잘못 읽혀 전부 깨진다.
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
            if ($workDir -and (Test-Path -LiteralPath $workDir)) { $psi.WorkingDirectory = $workDir }
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            [void]$proc.Start()
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            try { $proc.StandardInput.Close() } catch {}
        }
    } catch {
        $startError = "agy 실행 프로세스를 시작하지 못했습니다: $($_.Exception.Message)"
        if ($proc) { try { $proc.Dispose() } catch {} }
        return @{ TimedOut = $false; Raw = $null; ExecutionError = $startError; StdErr = $startError }
    }
    # 절대 마감(AgyTimeoutSeconds)까지 기다리되, AgyPollSeconds마다 깨어나 "아직 일하는가"를 봅니다.
    # 대화 기록에 새 단계가 계속 쌓이면 일하는 중이므로 그대로 두고, AgyStallSeconds 동안
    # 하나도 없으면 멈춘 것으로 보고 중단합니다.
    $startedAt       = Get-Date
    $agyHome         = Get-AgyHomeDir
    $knownConv       = Get-AgyConversationIdFromArgs $agyArgs
    $convId          = $null
    $stallCheck      = $true     # 대화를 못 찾거나 모호하면 $false: 절대 마감만 적용
    $stopReason      = $null     # 'cap'(마감을 넘겼고 활동이 없음) | 'hard'(최대 대기 시간) | 'stall'(멈춤)
    $lastActivity    = $null
    $stopNow         = $null
    $nextProgressLog = $AgyProgressLogSeconds
    $nextBgLog       = 0         # 백그라운드 도구를 기다린다는 로그를 5분에 한 번만 남기려고
    $nextCapLog      = 0         # 절대 마감 이후 "작업 중이라 계속 기다림" 로그 주기
    $cpuSamples      = New-Object System.Collections.ArrayList   # 마감이 가까워지면 모으는 CPU 사용 표본(마감 이후 활동 확인용)
    $toolCpuSamples  = New-Object System.Collections.ArrayList   # 도구 자식 프로세스 CPU 표본(MCP 제외)
    $capNote         = ""
    $probeState      = ""
    $probeSince      = $null
    $graceSince      = $null
    $lastProbeAt     = [datetime]::MinValue
    $graceSeconds    = if ($null -ne $AgyStallGraceSeconds) { [int]$AgyStallGraceSeconds } else { 0 }
    $probeInterval   = if ($null -ne $AgyStallProbeIntervalSeconds -and [int]$AgyStallProbeIntervalSeconds -gt 0) { [int]$AgyStallProbeIntervalSeconds } else { 60 }
    $thinkMaxSeconds = if ($null -ne $AgyThinkMaxSeconds -and [int]$AgyThinkMaxSeconds -gt 0) { [int]$AgyThinkMaxSeconds } else { 1200 }
    $toolMaxSeconds  = if ($null -ne $AgyToolMaxSeconds -and [int]$AgyToolMaxSeconds -gt 0) { [int]$AgyToolMaxSeconds } else { 1800 }
    # 절대 마감 값이 없으면($null) "$elapsed -ge $null" 이 늘 참이라 첫 폴링에서 끊긴다: 기본값으로 막는다(이 함수 안에서만).
    if ($null -eq $AgyHardTimeoutSeconds -or [int]$AgyHardTimeoutSeconds -le 0) { $AgyHardTimeoutSeconds = 7200 }
    $lastSubFullPollAt = $startedAt
    $lastMirrorLen = [int64]-1
    $lastClaimActIso = ""
    $lastClaimActWriteAt = [datetime]::MinValue
    $finished        = $false
    while ($true) {
        $waitMs = if ($script:IsSubWatcher) { 500 } else { [int]($AgyPollSeconds * 1000) }
        $finished = $proc.WaitForExit($waitMs)
        if ($finished) { break }
        $now     = Get-Date
        $elapsed = ($now - $startedAt).TotalSeconds
        if ($script:IsSubWatcher -and $script:CurrentTaskId) {
            $cancelMarker = Join-Path $RunningDir ("{0}.cancel" -f $script:CurrentTaskId)
            if (Test-Path -LiteralPath $cancelMarker) { $stopReason = 'cancel'; $stopNow = $now; break }
            if ($stallCheck -and -not $convId) {
                $foundEarly = Resolve-AgyConversation $agyHome $knownConv $startedAt $AgyConversationWindowSeconds $marker
                if ($foundEarly.State -eq 'found') {
                    $convId = $foundEarly.Id
                    if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                        Write-RunningClaim $script:CurrentTaskId @{ conversation_id = [string]$convId }
                    }
                }
            }
            if ($convId) {
                $lastMirrorLen = Sync-SubTranscriptMirror $agyHome $convId $script:CurrentTaskId $lastMirrorLen
                if ((($now - $lastClaimActWriteAt).TotalSeconds -ge 3) -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                    $actNow = $null
                    try { $actNow = Get-AgyConversationActivity $agyHome $convId } catch {}
                    if (Get-Command Get-AgyChildConversationActivity -ErrorAction SilentlyContinue) {
                        try {
                            $cActNow = Get-AgyChildConversationActivity $agyHome $convId
                            if ($cActNow -and (($null -eq $actNow) -or ($cActNow -gt $actNow))) { $actNow = $cActNow }
                        } catch {}
                    }
                    if (Get-Command Get-AgyTaskLogActivity -ErrorAction SilentlyContinue) {
                        try {
                            $tActNow = Get-AgyTaskLogActivity $agyHome $convId
                            if ($tActNow -and (($null -eq $actNow) -or ($tActNow -gt $actNow))) { $actNow = $tActNow }
                        } catch {}
                    }
                    if ($actNow) {
                        $actIso = $actNow.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                        if ($actIso -ne $lastClaimActIso) {
                            $lastClaimActIso = $actIso
                            $lastClaimActWriteAt = $now
                            Write-RunningClaim $script:CurrentTaskId @{ last_activity_utc = $actIso }
                        }
                    }
                }
            }
            if ($elapsed -lt $AgyHardTimeoutSeconds -and (($now - $lastSubFullPollAt).TotalSeconds -lt $AgyPollSeconds)) { continue }
            $lastSubFullPollAt = $now
        }
        if ($elapsed -ge $AgyHardTimeoutSeconds) { $stopReason = 'hard'; $stopNow = $now; break }
        # 마감 직전부터 CPU 표본을 모은다(마감 이후 "진짜 일하는 중인가"를 두 시점의 차이로 보려고)
        if ($elapsed -ge ($AgyTimeoutSeconds - 2 * $AgyStallSeconds)) {
            [void]$cpuSamples.Add(@{ At = $now; Cpu = (Get-AgyTreeCpuSeconds $proc.Id) })
            while ($cpuSamples.Count -gt 0 -and (($now - $cpuSamples[0].At).TotalSeconds -gt (3 * $AgyStallSeconds))) { $cpuSamples.RemoveAt(0) }
        }
        # 절대 마감에 닿아도 바로 끊지 않는다. 그 시점에 agy 가 진짜 일하는 중인지(새 단계·도구 출력·CPU·모델 요청 진행 중) 확인해, 일하면 최대 대기 시간(AgyHardTimeoutSeconds)까지
        # 계속 기다리고 아무 활동도 없으면 멈춘 것으로 보고 끊는다.
        if ($elapsed -ge $AgyTimeoutSeconds) {
            if ($convId) {
                $lastActivity = Get-AgyConversationActivity $agyHome $convId
                if (Get-Command Get-AgyChildConversationActivity -ErrorAction SilentlyContinue) {
                    $childAct = Get-AgyChildConversationActivity $agyHome $convId
                    if ($childAct -and (($null -eq $lastActivity) -or ($childAct -gt $lastActivity))) { $lastActivity = $childAct }
                }
                if (Get-Command Get-AgyToolChildCpuSeconds -ErrorAction SilentlyContinue) {
                    try {
                        $tc = Get-AgyToolChildCpuSeconds $proc.Id
                        [void]$toolCpuSamples.Add(@{ At = $now; Cpu = [double]$tc.TotalCpu; HasToolChild = [bool]$tc.HasToolChild })
                        while ($toolCpuSamples.Count -gt 0 -and (($now - $toolCpuSamples[0].At).TotalSeconds -gt 120)) { $toolCpuSamples.RemoveAt(0) }
                    } catch {}
                }
                if ($probeState -and -not (Test-AgyStalled $lastActivity $startedAt $now $AgyStallSeconds)) {
                    $probeState = ""
                    $probeSince = $null
                    $graceSince = $null
                    $lastProbeAt = [datetime]::MinValue
                    $initialProbeState = ""
                    if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                        Write-RunningClaim $script:CurrentTaskId @{ probe_state = ""; probe_since = "" }
                    }
                }
            }
            $alive = Test-AgyAliveAtCap $agyHome $convId $now $AgyStallSeconds $cpuSamples
            if (-not $alive.Alive -and $convId -and (Get-Command Get-AgyStallProbeSignal -ErrorAction SilentlyContinue)) {
                $capSig = Get-AgyStallProbeSignal $agyHome $convId $proc.Id $startedAt $lastActivity $toolCpuSamples $now
                if ($capSig.Active) {
                    $capRef = $startedAt
                    if (($null -ne $lastActivity) -and ($lastActivity -gt $capRef)) { $capRef = $lastActivity }
                    $capIdleSec = ($now - $capRef).TotalSeconds
                    if ($capSig.State -eq 'thinking' -and $capIdleSec -ge $thinkMaxSeconds) {
                        Log ("  멈춤 확인: thinking 상태가 최대 허용 침묵({0}초)을 넘어 중단하고 이어서 묻기로 전환합니다 (침묵 {1}초, 대화 {2})" -f $thinkMaxSeconds, [int]$capIdleSec, $convId)
                        $stopReason = 'stall'; $stopNow = $now; break
                    }
                    if ($capSig.State -eq 'tool running' -and $capIdleSec -ge $toolMaxSeconds) {
                        Log ("  멈춤 확인: tool running 상태가 최대 허용 침묵({0}초)을 넘어 중단하고 이어서 묻기로 전환합니다 (침묵 {1}초, 대화 {2})" -f $toolMaxSeconds, [int]$capIdleSec, $convId)
                        $stopReason = 'stall'; $stopNow = $now; break
                    }
                    $alive = @{ Alive = $true; Reason = [string]$capSig.Reason; Note = "" }
                }
            }
            if (-not $alive.Alive) { $capNote = [string]$alive.Note; $stopReason = 'cap'; $stopNow = $now; break }
            if ($elapsed -ge $nextCapLog) {
                Log ("  절대 마감 {0}초를 넘겼지만 작업 중으로 보여({1}) 끊지 않고 기다립니다. 최대 {2}초까지." -f $AgyTimeoutSeconds, $alive.Reason, $AgyHardTimeoutSeconds)
                $nextCapLog = $elapsed + $AgyProgressLogSeconds
            }
            continue    # 마감 이후의 판단은 위 확인이 맡는다(아래 멈춤 점검은 건너뛴다)
        }
        if ($stallCheck -and -not $convId) {
            $found = Resolve-AgyConversation $agyHome $knownConv $startedAt $AgyConversationWindowSeconds $marker
            if ($found.State -eq 'found') {
                $convId = $found.Id
                # 동시에 도는 작업이 여럿이어도 뷰어가 이 작업의 진행을 읽을 수 있게 대화 ID 를 작업 표시 파일에 적어 둔다
                if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                    Write-RunningClaim $script:CurrentTaskId @{ conversation_id = [string]$convId }
                }
            } elseif ($found.State -eq 'unavailable') {
                $stallCheck = $false
                Log "  멈춤 점검 불가: agy 대화 폴더를 찾을 수 없습니다 ($agyHome). 절대 마감 $AgyTimeoutSeconds 초만 적용합니다."
            } elseif ($found.State -eq 'ambiguous') {
                if ($marker -and $elapsed -le $AgyConversationWindowSeconds) {
                    # 표식으로 내 대화를 가려내는 중이다(대화 기록이 아직 안 써졌을 수 있다). 다음 점검 때 다시 본다.
                } else {
                    $stallCheck = $false
                    Log "  멈춤 점검 불가: 시작 직후 새 대화가 둘 이상이라 이번 호출의 것을 가릴 수 없습니다. 절대 마감 $AgyTimeoutSeconds 초만 적용합니다."
                }
            } elseif ($elapsed -gt $AgyConversationWindowSeconds) {
                $stallCheck = $false
                Log "  멈춤 점검 불가: 시작 후 $AgyConversationWindowSeconds 초 안에 새 대화가 보이지 않습니다. 절대 마감 $AgyTimeoutSeconds 초만 적용합니다."
            }
        }
        if ($stallCheck -and $convId) {
            $lastActivity = Get-AgyConversationActivity $agyHome $convId
            if (Get-Command Get-AgyChildConversationActivity -ErrorAction SilentlyContinue) {
                $childAct = Get-AgyChildConversationActivity $agyHome $convId
                if ($childAct -and (($null -eq $lastActivity) -or ($childAct -gt $lastActivity))) { $lastActivity = $childAct }
            }
            $refActivity = $startedAt
            if (($null -ne $lastActivity) -and ($lastActivity -gt $refActivity)) { $refActivity = $lastActivity }
            $idleNowSec = ($now - $refActivity).TotalSeconds

            # 1차 침묵 기준 90초 전부터(또는 확인 중일 때) 도구 자식 프로세스(MCP 제외)의 CPU 표본을 모은다
            $toolSampleLead = [Math]::Max([Math]::Min(2.0, 0.5 * $AgyStallSeconds), [double]($AgyStallSeconds - 90))
            if (($idleNowSec -ge $toolSampleLead -or $probeState) -and (Get-Command Get-AgyToolChildCpuSeconds -ErrorAction SilentlyContinue)) {
                try {
                    $tc = Get-AgyToolChildCpuSeconds $proc.Id
                    [void]$toolCpuSamples.Add(@{ At = $now; Cpu = [double]$tc.TotalCpu; HasToolChild = [bool]$tc.HasToolChild })
                    while ($toolCpuSamples.Count -gt 0 -and (($now - $toolCpuSamples[0].At).TotalSeconds -gt 120)) { $toolCpuSamples.RemoveAt(0) }
                } catch {}
            }

            if (-not (Test-AgyStalled $lastActivity $startedAt $now $AgyStallSeconds)) {
                # 새 단계가 기록되어 침묵 상태가 풀렸으면 probe 상태를 비운다
                if ($probeState -or ($initialProbeState -eq 'asked' -and $null -ne $lastActivity -and $lastActivity -gt $startedAt)) {
                    $probeState = ""
                    $probeSince = $null
                    $graceSince = $null
                    $lastProbeAt = [datetime]::MinValue
                    $initialProbeState = ""
                    if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                        Write-RunningClaim $script:CurrentTaskId @{ probe_state = ""; probe_since = "" }
                    }
                }
            } else {
                # 오래 걸리는 명령을 agy 가 백그라운드로 돌려 두고 기다리는 중이면 새 단계가 없는 게 정상이다. 끊지 않는다(절대 마감은 그대로).
                $bgPending = @(Get-AgyPendingBackgroundTasks $agyHome $convId)
                if ($bgPending.Count -gt 0) {
                    if ($probeState) {
                        $probeState = ""
                        $probeSince = $null
                        $graceSince = $null
                        if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                            Write-RunningClaim $script:CurrentTaskId @{ probe_state = ""; probe_since = "" }
                        }
                    }
                    if ($elapsed -ge $nextBgLog) {
                        Log ("  새 단계가 {0}초 넘게 없지만 agy 가 백그라운드로 돌린 도구 {1}건이 아직 끝나지 않아 멈춤으로 보지 않고 기다립니다 ({2}). 절대 마감 {3}초까지." -f $AgyStallSeconds, $bgPending.Count, ($bgPending -join ', '), $AgyTimeoutSeconds)
                        $nextBgLog = $elapsed + 300
                    }
                } else {
                    # 1차 침묵 기준 도달: 바로 끊지 않고 확인 중 -> cli-*.log 모델 요청/도구 자식 CPU 확인 -> 유예 시간 경과 시 중단
                    $firstProbe = ($null -eq $probeSince)
                    if ($firstProbe) {
                        $probeSince = $now
                        $graceSince = $now
                        $probeState = "checking"
                        if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                            Write-RunningClaim $script:CurrentTaskId @{ probe_state = "checking"; probe_since = $probeSince.ToString("yyyy-MM-dd HH:mm:ss") }
                        }
                        Log ("  멈춤 확인: 새 단계가 {0}초 넘게 없어 생각 중인지 확인합니다 (대화 {1}, 유예 {2}초)" -f $AgyStallSeconds, $convId, $graceSeconds)
                    }
                    if ($firstProbe -or (($now - $lastProbeAt).TotalSeconds -ge $probeInterval)) {
                        $lastProbeAt = $now
                        $sig = if (Get-Command Get-AgyStallProbeSignal -ErrorAction SilentlyContinue) {
                            Get-AgyStallProbeSignal $agyHome $convId $proc.Id $startedAt $lastActivity $toolCpuSamples $now
                        } else {
                            @{ Active = $false; State = ""; Reason = "" }
                        }
                        if ($sig.Active) {
                            $newState = [string]$sig.State
                            $graceSince = $null
                            if ($probeState -ne $newState) {
                                $probeState = $newState
                                if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                                    Write-RunningClaim $script:CurrentTaskId @{ probe_state = $probeState; probe_since = $probeSince.ToString("yyyy-MM-dd HH:mm:ss") }
                                }
                                Log ("  멈춤 확인: 활성 신호 감지({0}, {1}) -> 계속 기다립니다 (대화 {2})" -f $probeState, $sig.Reason, $convId)
                            }
                        } else {
                            if ($null -eq $graceSince) { $graceSince = $now }
                            if ($probeState -ne "checking") {
                                $probeState = "checking"
                                if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                                    Write-RunningClaim $script:CurrentTaskId @{ probe_state = "checking"; probe_since = $probeSince.ToString("yyyy-MM-dd HH:mm:ss") }
                                }
                                Log ("  멈춤 확인: 활성 신호가 사라져 유예 대기로 전환합니다 (대화 {0}, 유예 {1}초)" -f $convId, $graceSeconds)
                            }
                        }
                    }
                    if ($probeState -eq 'thinking' -and $idleNowSec -ge $thinkMaxSeconds) {
                        Log ("  멈춤 확인: thinking 상태가 최대 허용 침묵({0}초)을 넘어 중단하고 이어서 묻기로 전환합니다 (침묵 {1}초, 대화 {2})" -f $thinkMaxSeconds, [int]$idleNowSec, $convId)
                        $stopReason = 'stall'; $stopNow = $now; break
                    }
                    if ($probeState -eq 'tool running' -and $idleNowSec -ge $toolMaxSeconds) {
                        Log ("  멈춤 확인: tool running 상태가 최대 허용 침묵({0}초)을 넘어 중단하고 이어서 묻기로 전환합니다 (침묵 {1}초, 대화 {2})" -f $toolMaxSeconds, [int]$idleNowSec, $convId)
                        $stopReason = 'stall'; $stopNow = $now; break
                    }
                    if ($null -ne $graceSince -and (($now - $graceSince).TotalSeconds -ge $graceSeconds)) {
                        $stopReason = 'stall'; $stopNow = $now; break
                    }
                }
            }
        }
        if ($elapsed -ge $nextProgressLog) {
            $nextProgressLog += $AgyProgressLogSeconds
            if ($convId -and $lastActivity) {
                $idleNow = [math]::Max(0, [int](($now - $lastActivity).TotalSeconds))
                Log ("  진행 점검: 경과 {0}초, 마지막 활동 {1}초 전 - 작업 중으로 보고 계속 기다립니다 (대화 {2})" -f [int]$elapsed, $idleNow, $convId)
            } else {
                Log ("  진행 점검: 경과 {0}초 (마지막 활동은 확인할 수 없음)" -f [int]$elapsed)
            }
        }
    }
    if (-not $finished) {
        $idleSeconds = $null
        $lastText    = "확인 불가"
        if ($stopReason -eq 'stall') {
            $ref = $startedAt
            if (($null -ne $lastActivity) -and ($lastActivity -gt $ref)) { $ref = $lastActivity }
            $idleSeconds = ($stopNow - $ref).TotalSeconds
            $lastText    = $ref.ToString("HH:mm:ss")
        }
        # 대상은 "이 워처의 자손인 agy"만입니다. 이름만으로 고르면 사용자가 직접 띄운 다른 agy까지 죽입니다.
        foreach ($agyPid in @(Get-DescendantProcessIdsByName $PID "agy")) {
            Stop-ProcessTree $agyPid
        }
        try { if (-not $proc.HasExited) { Stop-ProcessTree $proc.Id } } catch {}
        try { $proc.Dispose() } catch {}
        if ($script:IsSubWatcher -and $convId -and $script:CurrentTaskId) {
            [void](Sync-SubTranscriptMirror $agyHome $convId $script:CurrentTaskId $lastMirrorLen)
        }
        $lastStepText = ""
        if ($convId) { try { $lastStepText = Format-AgyLastStep (Get-AgyLastStepSummary $agyHome $convId) } catch {} }
        return @{ TimedOut = $true; Raw = $null; Reason = $stopReason; IdleSeconds = $idleSeconds; LastActivity = $lastText; ConversationId = $convId; LastStep = $lastStepText; CapNote = $capNote }
    }
    # 끝났다: 남은 출력을 마저 받는다(비동기로 읽던 스트림이 닫힐 때까지).
    try { $proc.WaitForExit() } catch {}
    if ($script:IsSubWatcher -and $convId -and $script:CurrentTaskId) {
        [void](Sync-SubTranscriptMirror $agyHome $convId $script:CurrentTaskId $lastMirrorLen)
    }
    $outText = ""
    $errText = ""
    if ($useSpawned) {
        try { $outText = [string]$proc.StandardOutput } catch {}
        try { $errText = [string]$proc.StandardError } catch {}
    } else {
        try { $outText = [string]$outTask.Result } catch {}
        try { $errText = [string]$errTask.Result } catch {}
    }
    try { $proc.Dispose() } catch {}
    # 표준오류는 여기서 파일에 쓰지 않고 돌려준다. error.log 는 응답 파일을 쓴 뒤에 쓰도록 호출한 쪽(Invoke-InboxTaskBody)이 맡는다:
    # Claude 의 점검 루프는 비어 있지 않은 error.log 를 보면 "오류"로 끝내므로, 성공했는데 agy 가 남긴 잡음(stderr)이
    # 응답 파일보다 먼저 보이면 잘못된 오류가 된다.
    if ([string]::IsNullOrWhiteSpace($outText)) {
        return @{ TimedOut = $false; Raw = $null; StdErr = $errText; ConversationId = $convId }
    }
    # 하나의 문자열로 돌려준다(줄 배열로 넘기면 ConvertFrom-Json 이 줄마다 따로 해석해 배열이 되어 필드를 못 읽는다).
    return @{ TimedOut = $false; Raw = $outText.Trim(); StdErr = $errText; ConversationId = $convId }
}

# $conversationId가 없으면: 모델 순서($modelChain, 단계의 주 모델 + 폴백)를 차례로 시도합니다.

# $conversationId가 있으면(@session:으로 이어가는 경우): --conversation으로 그 대화를

# 이어가는 호출 한 번만 합니다 - 모델은 그 대화가 시작될 때 쓴 걸 agy가 그대로 유지하므로

# --model도, 폴백 후보 목록도 필요 없습니다(직접 검증함). agy는 conversation_id가

# 만료/유실됐어도 에러 없이 조용히 새 대화로 시작해주므로, 성공 응답에서 conversation_id가

# 우리가 보낸 것과 다르면 그걸로 "세션이 갱신됐다"는 걸 알아챕니다.

# 쿼터 초과 등 폴백 대상 오류면(새 세션 시도일 때만) 다음 모델로, 그 외 오류면 즉시 중단합니다.

# --- 지시문 전달 방식: 인라인(-p "글") 또는 파일 참조(-p "@파일") ---
# 같은 질문을 두 방식으로 50회 보내 비교한 결과, 답과 특수문자 전달(따옴표·역슬래시·셸 기호·한글·이모지·여러 줄)은 같았고
# 파일 참조는 agy 가 파일을 도구로 한 번 더 읽는 탓에 호출마다 입력이 약 2,500토큰 더 들었다. 그래서 짧은 지시는 인라인으로 보낸다.
# 인라인을 쓰지 않는 경우(파일 참조 유지): 지시문이 길 때, @ 로 시작할 때(실제 파일 경로면 agy 가 그 파일을 끼워 넣는다),
# 표식이 다른 실행 중 작업과 겹치거나 없을 때(표식으로 이 호출의 agy 대화를 가려내야 멈춤 판정과 뷰어 진행 표시가 맞는다).
$InlinePromptMaxChars = 8000

# 지시문 첫 줄에서 표식을 뽑는다: 따옴표·역슬래시 앞까지(대화 기록은 JSON 이라 그 글자들이 이스케이프돼 그대로 찾을 수 없다), 12자 이상일 때만, 60자까지.
function Get-AgyPromptMarker([string]$Prompt) {
    if (-not $Prompt) { return "" }
    $firstLine = ($Prompt -split "[\r\n]")[0]
    $cut = [regex]::Replace($firstLine, '[\\"].*$', '')
    if ($cut.Length -ge 12) { return $cut.Substring(0, [Math]::Min(60, $cut.Length)) }
    return ""
}

# 이 지시문을 어떤 방식으로 넘길지 정한다. OtherMarkers: 지금 도는 다른 작업들의 표식, OtherCount: 지금 도는 다른 작업 수.
# 돌려주는 값: @{ Mode = 'inline'|'file'; Marker = <인라인일 때의 표식>; Reason = 'long'|'at'|'marker'|'no-marker'|'' }
function Get-AgyPromptDelivery([string]$Prompt, [string[]]$OtherMarkers, [int]$OtherCount) {
    if ($Prompt.Length -gt $InlinePromptMaxChars) { return @{ Mode = 'file'; Marker = ''; Reason = 'long' } }
    if ($Prompt.TrimStart().StartsWith('@')) { return @{ Mode = 'file'; Marker = ''; Reason = 'at' } }
    $marker = Get-AgyPromptMarker $Prompt
    if (-not $marker) {
        # 표식이 없으면 동시에 도는 작업이 있을 때 대화를 가릴 수 없다. 혼자 돌 때만 인라인.
        if ($OtherCount -gt 0) { return @{ Mode = 'file'; Marker = ''; Reason = 'no-marker' } }
        return @{ Mode = 'inline'; Marker = ''; Reason = '' }
    }
    # 대화 기록 맨 앞에 표식이 들어 있는지를 포함 검사로 보므로, 한쪽이 다른 쪽을 품어도 겹친 것이다
    foreach ($m in @($OtherMarkers)) {
        if ($m -and ($m.Contains($marker) -or $marker.Contains($m))) { return @{ Mode = 'file'; Marker = ''; Reason = 'marker' } }
    }
    return @{ Mode = 'inline'; Marker = $marker; Reason = '' }
}

# 지금 돌고 있는 다른 작업(자기 제외)의 인라인 표식과 작업 수. 작업 표시 파일(running)에서 읽는다.
function Get-OtherRunningMarkers([string]$ExceptTaskId) {
    $markers = @(); $total = 0
    if (Test-Path -LiteralPath $RunningDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            $c = Read-RunningClaim $f.FullName
            if ($null -eq $c -or [string]$c.task_id -eq $ExceptTaskId) { continue }
            $total++
            if ($c.marker) { $markers += [string]$c.marker }
        }
    }
    return @{ Markers = $markers; Total = $total }
}

function Invoke-AgyWithFallback($safePrompt, $targetCwd, [bool]$skipPerm, $errFile, [string]$conversationId = "", [string]$knownModel = "", [string]$taskId = "", [string]$promptFile = "", [string[]]$modelChain = @(), [string]$tier = "", [string]$slashCommand = "", [string]$executionMode = "") {
    $result = [ordered]@{
        Success        = $false
        Response       = $null
        RawJson        = $null
        ModelUsed      = $null
        Attempts       = 0
        TriedModels    = @()
        InTok          = $null
        OutTok         = $null
        ThinkTok       = $null
        TotTok         = $null
        AgyDuration    = $null
        ElapsedSec     = 0
        ErrorMessage   = $null
        ConversationId = $null
        SessionRenewed = $false
        StdErr         = ""
        Tier           = ""
        AskCount       = 0
        Blocked        = $false
        TimedOutReason = ""
    }

    $overallStart = Get-Date
    # 주의: 여기서 @($null)을 쓰면 안 됩니다 - PowerShell은 "원소가 $null 하나뿐인 배열"을
    # if/스크립트 출력 캡처 과정에서 그냥 $null로 뭉개버려서(직접 겪음: $candidates.Count가
    # 0이 되고 foreach가 한 번도 안 돎), 세션을 이어가려던 호출이 조용히 아무것도 안 하고
    # "실패(시도한 모델: )"로 끝나버립니다. 그래서 $null이 아닌 문자열 자리표시자를 씁니다.
    # 이어가는 세션: 호출 한 번. 아니면 호출한 쪽이 정한 모델 순서($modelChain: 단계면 주 모델 + 폴백, 모델 이름이면 그 하나).
    # 순서가 비어 있으면 기본 단계(build)의 순서. 한도 · 과부하 오류일 때만 다음 모델로 넘어간다(아래 $FallbackErrorPattern).
    # @() 로 감싸는 이유: if 식은 원소 하나짜리 배열을 문자열로 풀어서 $candidates[-1] 이 마지막 "글자"가 된다.
    $chain = @(@($modelChain) | Where-Object { $_ })
    if ($chain.Count -eq 0) { $chain = @(Get-WatcherDefaultChain) }
    $candidates = @(if ($conversationId) { "(continue)" } else { $chain })
    $result.Tier = $tier
    $refreshedModelsOnce = $false
    $skipGroups = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    # @cwd 가 있으면 첫 번째 실존 폴더를 agy 프로세스의 작업 폴더(실행 위치)로 쓴다(없으면 $RuntimeDir).
    $agyWorkDir = $RuntimeDir
    foreach ($dir in @($targetCwd)) {
        if ($null -ne $dir -and -not [string]::IsNullOrWhiteSpace([string]$dir) -and (Test-Path -LiteralPath ([string]$dir) -PathType Container)) {
            $agyWorkDir = [string]$dir
            break
        }
    }

    for ($ci = 0; $ci -lt $candidates.Count; $ci++) {
        $candidate = $candidates[$ci]
        if (-not $conversationId -and $skipGroups.Count -gt 0) {
            $candGroup = Get-AgyQuotaGroup $candidate
            if ($candGroup -and $skipGroups.Contains($candGroup)) {
                continue
            }
        }
        $candidateTransientRetried = $false
        $modelSucceededOrBlocked = $false
        while ($true) {
        $result.Attempts++
        $result.TriedModels += $candidate

        # 지시문 전달 방식(인라인 / 파일 참조)과 표식. 인라인이면 표식을 작업 표시 파일에 적어 둬서, 같은 표식으로 시작하는 다른 작업이 파일 참조로 비켜 가게 한다.
        $plainPrompt = ([string]$safePrompt).Replace('\"', '"')
        $inlinePrompt = if ($slashCommand) { "$slashCommand $plainPrompt" } else { $plainPrompt }
        $hasPromptFile = [bool]($promptFile -and (Test-Path -LiteralPath $promptFile))
        $delivery = @{ Mode = 'inline'; Marker = (Get-AgyPromptMarker $inlinePrompt); Reason = '' }
        if ($hasPromptFile) {
            $others = Get-OtherRunningMarkers $taskId
            $delivery = Get-AgyPromptDelivery $inlinePrompt $others.Markers $others.Total
        }
        if ($taskId) { try { Write-RunningClaim $taskId @{ marker = [string]$(if ($delivery.Mode -eq 'inline') { $delivery.Marker } else { '' }) } } catch {} }

        # 웹 뷰어 실시간 표시용: 현재 실행 중인 작업과 모델 정보를 current_task.json에 기록
        $modelForReport = if ($conversationId) {
            if ($knownModel) { $knownModel } else { "(session)" }
        } else {
            $candidate
        }
        if ($result.Attempts -gt 1 -and -not $conversationId) {
            $result.AskCount = 0
            $result.ConversationId = $null
        }
        $currentTaskFile = $Layout.CurrentTaskFile
        if ($taskId) {
            try {
                [ordered]@{
                    task_id    = $taskId
                    model      = $modelForReport
                    attempt    = $result.Attempts
                    started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                } | ConvertTo-Json -Compress | Set-Content -Path $currentTaskFile -Encoding UTF8 -ErrorAction SilentlyContinue
                # 작업마다 따로 있는 표시 파일에도 모델·시도를 적는다(뷰어가 어느 작업이 어떤 모델로 도는지 읽는다)
                $claimFields = @{ model = $modelForReport; tier = [string]$tier; attempt = $result.Attempts; started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
                if (-not $conversationId -and $result.TriedModels) {
                    $claimFields['tried'] = ($result.TriedModels -join ' -> ')
                }
                if ($result.Attempts -gt 1 -and -not $conversationId) {
                    $claimFields['probe_state']     = ""
                    $claimFields['probe_since']     = ""
                    $claimFields['ask_count']       = 0
                    $claimFields['conversation_id'] = ""
                }
                Write-RunningClaim $taskId $claimFields
            } catch {}
        }

        # 프롬프트 인자: 위에서 정한 방식(인라인 글 또는 @임시프롬프트파일). 슬래시 명령은 파일 참조 앞에도 붙여 agy 가 명령을 확장하게 한다.
        $promptArg = if ($delivery.Mode -eq 'file') {
            if ($slashCommand) { "$slashCommand @$promptFile" } else { "@$promptFile" }
        } else {
            $inlinePrompt
        }
        $agyArgs = @('-p', $promptArg, '--output-format', 'json')

        if ($conversationId) { $agyArgs += @('--conversation', $conversationId) } else { $agyArgs += @('--model', $candidate) }
        if ($executionMode)  { $agyArgs += @('--mode', $executionMode) }

        foreach ($dir in @($targetCwd)) { if ($dir) { $agyArgs += @('--add-dir', [string]$dir) } }

        if ($skipPerm)  { $agyArgs += '--dangerously-skip-permissions' }

        # 동시에 도는 다른 작업과 대화를 헷갈리지 않게, 이 호출의 질문에만 들어 있는 글(표식)을 함께 넘긴다:
        # 파일 참조면 그 파일 이름, 인라인이면 지시문 첫 줄(따옴표·역슬래시 앞까지, 12자 이상일 때만).
        $marker = if ($delivery.Mode -eq 'file') { [System.IO.Path]::GetFileName($promptFile) } else { [string]$delivery.Marker }
        if ($delivery.Mode -eq 'file' -and $delivery.Reason) { Log "  -> 지시문을 파일 참조로 넘깁니다($($delivery.Reason))" }

        $askCount = 0
        $resumeConvId = ""
        $maxAsks = if ($null -ne $AgyStallMaxAsks) { [int]$AgyStallMaxAsks } else { 2 }
        $askPrompt = if ($AgyStallAskPrompt) { [string]$AgyStallAskPrompt } else { "직전 실행이 응답 없이 10분 넘게 멈춰 중단했습니다. 대화 기록을 보고 판단하세요. 1) 이미 끝났다면 최종 답변만 그대로 다시 쓰세요. 2) 남은 일이 있으면 이어서 끝까지 진행하고 최종 답변을 쓰세요. 3) 진행할 수 없으면 첫 줄에 [진행 불가] 와 사유를 쓰세요." }
        $currentArgs = $agyArgs
        $currentMarker = $marker
        $currentInitialProbe = ""
        $call = $null
        $recoveredDone = $false
        while ($true) {
            $call = Invoke-AgyOnce $currentArgs $errFile $agyWorkDir $currentMarker $currentInitialProbe
            if ($call.StdErr) { $result.StdErr = [string]$call.StdErr }

            # 멈춤·마감으로 끊았는데 agy 가 이미 최종 응답을 대화 기록에 남겼다면(응답을 마친 뒤 프로세스만 안 끝난 경우, 실측 2건) 실패가 아니라 그 응답을 답으로 회수한다.
            # 'hard'(최대 대기 시간)는 일하는 중이었던 것이라 회수하지 않는다. 사용량(토큰)은 agy 의 JSON 응답에만 있어 이 경우 비워 둔다.
            if ($call.TimedOut -and @('stall', 'cap') -contains [string]$call.Reason -and $call.ConversationId) {
                $recovered = $null
                try { $recovered = Get-AgyFinalResponse (Get-AgyHomeDir) ([string]$call.ConversationId) } catch { $recovered = $null }
                if ($recovered) {
                    $result.Success        = $true
                    $result.Response       = [string]$recovered.Text
                    $result.ModelUsed      = if ($conversationId) { $knownModel } else { $candidate }
                    $result.ConversationId = [string]$call.ConversationId
                    $result.StdErr         = "agy 프로세스가 끝나지 않아 워처가 끊었지만(사유: $($call.Reason)), 대화 기록(단계 #$($recovered.Index))에 최종 응답이 이미 있어 그 내용을 답으로 회수했습니다. 토큰 사용량은 agy 의 JSON 응답이 없어 기록하지 못했습니다."
                    Log "  회수: agy 가 끝나지 않아 끊었지만 대화 $($call.ConversationId)의 최종 응답(단계 #$($recovered.Index), $($recovered.Text.Length)자)이 이미 있어 성공으로 처리합니다. (토큰 사용량은 기록하지 못함)"
                    $recoveredDone = $true
                    break
                }
            }

            # 유예 시간까지 지나 멈춘 경우: 대화 ID 가 있고 질문 횟수가 최대치(기본 2회) 미만이면 같은 대화에 진행 상황을 묻는다.
            if ($call.TimedOut -and $call.Reason -eq 'stall' -and $call.ConversationId -and $askCount -lt $maxAsks) {
                $askCount++
                $resumeConvId = [string]$call.ConversationId
                $result.AskCount = $askCount
                $result.ConversationId = $resumeConvId
                if ($taskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                    Write-RunningClaim $taskId @{
                        probe_state     = "asked"
                        ask_count       = $askCount
                        probe_since     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        conversation_id = $resumeConvId
                    }
                }
                Log ("  멈춤 확인: 이어서 물음 {0}/{1} (대화 {2})" -f $askCount, $maxAsks, $resumeConvId)
                $resumeArgs = @('--conversation', $resumeConvId, '-p', $askPrompt, '--output-format', 'json')
                $resumeModel = if ($conversationId) { $knownModel } else { $candidate }
                if ($resumeModel -and $resumeModel -ne '(continue)' -and $resumeModel -ne '(session)') {
                    $resumeArgs += @('--model', $resumeModel)
                }
                if ($executionMode) { $resumeArgs += @('--mode', $executionMode) }
                foreach ($dir in @($targetCwd)) { if ($dir) { $resumeArgs += @('--add-dir', [string]$dir) } }
                if ($skipPerm) { $resumeArgs += '--dangerously-skip-permissions' }
                $currentArgs = $resumeArgs
                $currentMarker = ""
                $currentInitialProbe = "asked"
                continue
            }
            break
        }
        if ($recoveredDone) { break }

        if ($call.TimedOut) {
            $result.TimedOutReason = [string]$call.Reason
            if ($call.ConversationId) { $result.ConversationId = [string]$call.ConversationId }
            if ($call.Reason -eq 'stall') {
                $idleMin = [math]::Round($call.IdleSeconds / 60, 1)
                $askNote = if ($askCount -gt 0) { " (이어서 물음 ${askCount}/${maxAsks}회 후에도 멈춤)" } else { "" }
                $result.ErrorMessage = "agy가 $idleMin 분 동안 진행하지 않아 중단했습니다$askNote (멈춤 판정: 마지막 활동 $($call.LastActivity), 대화 ID $($call.ConversationId))"
                Log "  멈춤: 대화 기록에 새 단계가 $idleMin 분 동안 없어 강제로 중단했습니다$askNote (마지막 활동 $($call.LastActivity), 대화 $($call.ConversationId)). 이 작업은 실패로 기록합니다."
                if ($call.LastStep) { Log "    $($call.LastStep)"; $result.ErrorMessage += " [$($call.LastStep)]" }
            } else {
                $capMsg = if ($call.Reason -eq 'hard') { "agy 호출이 최대 대기 시간 $AgyHardTimeoutSeconds 초를 넘겨 중단했습니다 (작업 중이었지만 더 기다리지 않음)" } else { "agy 호출이 $AgyTimeoutSeconds 초를 넘겼고 $($call.CapNote) 멈춘 것으로 보고 중단했습니다 (타임아웃)" }
                $result.ErrorMessage = $capMsg
                Log "  타임아웃: $capMsg 이 작업은 실패로 기록합니다."
            }

            break

        }

        $raw = $call.Raw

        $json = $null

        try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }

        if ($null -eq $json) {

            # JSON 파싱 자체가 실패 - agy 실행이 비정상 종료된 경우. 모델 문제가 아닐 가능성이
            # 높으므로 다음 모델로 넘어가지 않고 여기서 중단합니다.
            $result.RawJson = $raw
            if ($call.ExecutionError) {
                $result.ErrorMessage = "agy 실행 오류: $($call.ExecutionError)"
                Log "  오류: $($call.ExecutionError)"
            } else {
                $result.ErrorMessage = "agy 응답을 JSON으로 해석할 수 없음"
            }

            break

        }



        if ($json.status -ne "ERROR" -and $json.response) {

            # 이어서 물은 응답이 "[진행 불가]"로 시작하면 실패로 기록하되 답변은 그대로 보존한다.
            $respStr = [string]$json.response
            $isBlocked = ($askCount -gt 0 -and ($respStr.TrimStart() -match '^\[진행 불가\]'))
            if ($isBlocked) {
                $result.Success      = $false
                $result.Blocked      = $true
                $result.ErrorMessage = $respStr.Trim()
            } else {
                $result.Success      = $true
            }

            $result.Response       = $json.response

            $result.RawJson        = $raw

            $result.ModelUsed      = if ($conversationId) {

                # 세션에 실제로 기록된 모델명이 없으면 추측해서 채우지 않습니다 - 검증 안 된
                # 값을 사실처럼 기록하지 않는다는 원칙(SKILL.md 참고). 빈 값으로 두면
                # 사용량 행(tasks 표)에서 이미 "(모델 미확정/실패)"로 집계됩니다.
                $knownModel

            } else {

                $candidate

            }

            $result.ConversationId = [string](Get-JsonField $json @('conversation_id'))
            if (-not $result.ConversationId -and $askCount -gt 0) {
                if ($resumeConvId) { $result.ConversationId = [string]$resumeConvId }
                elseif ($call.ConversationId) { $result.ConversationId = [string]$call.ConversationId }
            }

            if ($conversationId -and $result.ConversationId -and $result.ConversationId -ne $conversationId) {

                $result.SessionRenewed = $true

                Log "  참고: 이어가려던 세션이 만료/유실된 것 같아 agy가 새 세션으로 시작했습니다."

            }

            $result.InTok    = Get-JsonField $json @('usage.input_tokens', 'usage.prompt_tokens', 'input_tokens', 'usage.tokens.input')

            $result.OutTok   = Get-JsonField $json @('usage.output_tokens', 'usage.completion_tokens', 'output_tokens', 'usage.tokens.output')

            $result.ThinkTok = Get-JsonField $json @('usage.thinking_tokens', 'usage.reasoning_tokens', 'thinking_tokens')

            $result.TotTok   = Get-JsonField $json @('usage.total_tokens', 'total_tokens', 'usage.tokens.total')

            if (-not $result.TotTok -and $result.InTok -and $result.OutTok) {

                $result.TotTok = [int]$result.InTok + [int]$result.OutTok

            }

            $result.AgyDuration = Get-JsonField $json @('duration_seconds', 'duration_ms')

            $modelSucceededOrBlocked = $true
            break

        }



        # status == ERROR

        $errText = if ($json.error) { [string]$json.error } else { "" }

        $result.RawJson = $raw

        $result.ErrorMessage = $errText

        if (-not $candidateTransientRetried -and $errText -match '(?i)(empty conversation id|authentication failed or timed out)') {
            $candidateTransientRetried = $true
            Log "  일시적 오류 감지($errText) -> 2초 후 같은 모델($candidate)로 1회 재시도합니다"
            Start-Sleep -Seconds 2
            continue
        }

        if (-not $refreshedModelsOnce -and $AvailableModelsFile -and $errText -match '(?i)(is not recognized as a known model|invalid model selection)') {
            $refreshedModelsOnce = $true
            try {
                [void](Update-AgyAvailableModelsFile $AvailableModelsFile)
                Log "  모델 미인식 오류 감지 -> agy models 가용 목록을 갱신했습니다."
            } catch {}
        }

        break
        }

        if ($modelSucceededOrBlocked) { break }
        if ($call.TimedOut) { break }
        if ($null -eq $json) { break }

        $isLast = ($ci -eq ($candidates.Count - 1))
        $isQuotaExhausted = Test-AgyQuotaExhaustedError $errText
        if ($isQuotaExhausted -and -not $script:IsSubWatcher -and $RuntimeDir) {
            $exNowUtc = [datetime]::UtcNow
            $exResetUtc = ConvertFrom-AgyResetsInText $errText $exNowUtc
            if ($null -eq $exResetUtc) { $exResetUtc = $exNowUtc.AddMinutes(60) }
            $exMsgLine = (($errText -split "`r?`n", 2)[0]).Trim()
            if ($exMsgLine.Length -gt 200) { $exMsgLine = $exMsgLine.Substring(0, 200) }
            $exModel = if ($conversationId) { if ($knownModel) { $knownModel } else { "(session)" } } else { [string]$candidate }
            $exPath = Join-Path $RuntimeDir "agy-quota-exhausted.json"
            $exTmp = "$exPath.$PID.tmp"
            try {
                $exDir = Split-Path -Path $exPath -Parent
                if ($exDir -and -not (Test-Path -LiteralPath $exDir)) {
                    New-Item -ItemType Directory -Force -Path $exDir | Out-Null
                }
                $exJson = ([ordered]@{
                    at      = $exNowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    model   = $exModel
                    until   = $exResetUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    message = $exMsgLine
                }) | ConvertTo-Json -Compress
                [System.IO.File]::WriteAllText($exTmp, $exJson, (New-Object System.Text.UTF8Encoding($false)))
                Remove-Item -LiteralPath $exPath -Force -ErrorAction SilentlyContinue
                [System.IO.File]::Move($exTmp, $exPath)
            } catch {
                Remove-Item -LiteralPath $exTmp -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $isLast -and (Test-AgyFallbackError $errText $candidate)) {
            if ($isQuotaExhausted -and -not $conversationId) {
                $curGroup = Get-AgyQuotaGroup $candidate
                if ($curGroup) {
                    [void]$skipGroups.Add($curGroup)
                    $skippedSame = New-Object System.Collections.ArrayList
                    $hasOtherGroup = $false
                    for ($ri = $ci + 1; $ri -lt $candidates.Count; $ri++) {
                        $remCand = $candidates[$ri]
                        $remGroup = Get-AgyQuotaGroup $remCand
                        if ($remGroup -eq $curGroup) {
                            [void]$skippedSame.Add($remCand)
                        } elseif (-not $skipGroups.Contains($remGroup)) {
                            $hasOtherGroup = $true
                        }
                    }
                    if ($skippedSame.Count -gt 0) {
                        Log ("  한도 소진: '{0}' 과 같은 한도 묶음({1})인 남은 후보({2})를 건너뜁니다" -f $candidate, $curGroup, ($skippedSame -join ', '))
                    }
                    if (-not $hasOtherGroup) {
                        break
                    }
                }
            }

            Log "  모델 '$candidate' 사용 불가/쿼터 초과로 다음 모델로 폴백합니다: $errText"

            continue

        } else {

            # 모델 문제가 아니거나(다른 모델로 재시도해도 동일하게 실패할 오류), 마지막 후보였음

            break

        }

    }



    $result.ElapsedSec = [math]::Round(((Get-Date) - $overallStart).TotalSeconds, 1)

    # current_task.json 은 "가장 최근에 시작한 작업"을 가리키는 호환용 파일이다. 내가 쓴 것일 때만 지운다(다른 작업이 덮어썼을 수 있다).
    $currentTaskFile = $Layout.CurrentTaskFile
    if ($taskId -and (Test-Path $currentTaskFile)) {
        try {
            $ct = [System.IO.File]::ReadAllText($currentTaskFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ([string]$ct.task_id -eq $taskId) { [void](Remove-AgyFileSafe $currentTaskFile) }
        } catch { [void](Remove-AgyFileSafe $currentTaskFile) }
    }

    return $result

}



# ----------------------------------------------------------------------------
# 동시 실행: 작업 표시 파일, 충돌 판정, 작업자 프로세스
# ----------------------------------------------------------------------------

# 표시 파일(running\<작업 ID>.json)을 읽는다. 없거나 반쯤 쓴 파일이면 $null.
# 다른 프로세스가 읽고 쓰는 중 잠깐 잠겨도(IOException) FileShare.ReadWrite|Delete 로 몇 번 재시도해 읽는다.
function Read-RunningClaim([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    for ($try = 0; $try -lt 5; $try++) {
        $fs = $null
        $sr = $null
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            $t = $sr.ReadToEnd()
            if ($t) { $t = $t.TrimStart([char]0xFEFF) }
            if (-not $t -or -not $t.Trim()) { return $null }
            return (ConvertFrom-Json -InputObject $t -ErrorAction Stop)
        } catch {
            if ($try -lt 4) { Start-Sleep -Milliseconds 20 }
        } finally {
            if ($sr) { try { $sr.Dispose() } catch {} }
            if ($fs) { try { $fs.Dispose() } catch {} }
        }
    }
    return $null
}

$script:ClaimMemory = @{}

# 표시 파일에 필드를 합쳐 쓴다(이미 있는 필드는 그대로 두고 준 것만 덮는다). 임시 파일에 쓰고 바꿔치기해서 읽는 쪽이 반쯤 쓴 파일을 보지 않는다.
function Write-RunningClaim([string]$TaskId, [hashtable]$Fields) {
    if (-not $TaskId) { return }
    if ($null -eq $script:ClaimMemory) { $script:ClaimMemory = @{} }
    $tmp = ""
    try {
        if (-not (Test-Path -LiteralPath $RunningDir)) { New-Item -ItemType Directory -Force -Path $RunningDir | Out-Null }
        $path = Join-Path $RunningDir ("{0}.json" -f $TaskId)
        $data = [ordered]@{ task_id = $TaskId }
        if ($script:ClaimMemory.ContainsKey($TaskId) -and $null -ne $script:ClaimMemory[$TaskId]) {
            $mem = $script:ClaimMemory[$TaskId]
            foreach ($mk in $mem.Keys) { $data[$mk] = $mem[$mk] }
        }
        $old = Read-RunningClaim $path
        if ($null -eq $old -and [System.IO.File]::Exists($path) -and -not $script:ClaimMemory.ContainsKey($TaskId) -and -not $Fields.ContainsKey('pid')) {
            return
        }
        if ($old) { foreach ($p in $old.PSObject.Properties) { $data[$p.Name] = $p.Value } }
        foreach ($k in $Fields.Keys) { $data[$k] = $Fields[$k] }
        if ($script:CurrentTaskId -eq $TaskId -and (-not $data.Contains('pid') -or [int]$data['pid'] -le 0)) {
            $data['pid'] = $PID
        }
        $memCopy = @{}
        foreach ($dk in $data.Keys) { $memCopy[$dk] = $data[$dk] }
        $script:ClaimMemory[$TaskId] = $memCopy
        $tmp = "$path.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $data -Compress -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        if ([System.IO.File]::Exists($path)) {
            [System.IO.File]::Replace($tmp, $path, [NullString]::Value, $true)
        } else {
            [System.IO.File]::Move($tmp, $path)
        }
    } catch {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Remove-RunningClaim([string]$TaskId) {
    if (-not $TaskId) { return }
    if ($null -ne $script:ClaimMemory -and $script:ClaimMemory.ContainsKey($TaskId)) { [void]$script:ClaimMemory.Remove($TaskId) }
    [void](Remove-AgyFileSafe (Join-Path $RunningDir ("{0}.json" -f $TaskId)))
}

# 표시 파일이 가리키는 작업자 프로세스가 살아 있는가
function Test-ClaimAlive($Claim) {
    $claimPid = 0
    try { $claimPid = [int]$Claim.pid } catch { $claimPid = 0 }
    if ($claimPid -le 0) { return $false }
    $p = Get-Process -Id $claimPid -ErrorAction SilentlyContinue
    return [bool]($p -and -not $p.HasExited -and $p.ProcessName -eq "powershell")
}

# 작업자가 끝내지 못하고 사라졌는데 지시파일이 inbox 에 그대로 남은 경우: 영원히 다시 시도하지 않도록 실패로 기록하고 옮긴다.
function Resolve-DeadClaim($Claim, [string]$ClaimPath) {
    $taskId = [string]$Claim.task_id
    # PID 가 아직 채워지지 않은 표시(띄우는 도중 워처가 멈춘 것)는 20초가 지났을 때만 지운다(기동 중인 작업자를 죽은 것으로 오인하지 않게)
    $deadPid = 0
    try { $deadPid = [int]$Claim.pid } catch { $deadPid = 0 }
    if ($deadPid -le 0) {
        $cfItem = Get-Item -LiteralPath $ClaimPath -ErrorAction SilentlyContinue
        if ($cfItem -and ((Get-Date) - $cfItem.LastWriteTime).TotalSeconds -lt 20) { return }
        [void](Remove-AgyFileSafe $ClaimPath)
        return
    }
    $inboxFile = $null
    $exts = if ($script:IsSubWatcher) { @(".task.json", ".md", ".txt") } else { @(".md", ".txt") }
    foreach ($ext in $exts) {
        $cand = Join-Path $InboxDir ($taskId + $ext)
        if (Test-Path -LiteralPath $cand) { $inboxFile = $cand; break }
    }
    # submit-task.ps1 -Cancel 이 작업자를 끝내기 전에 남기는 취소 표시(running\<ID>.cancel): 있으면 실패가 아니라 취소로 마무리한다
    $cancelMarker = Join-Path $RunningDir ("{0}.cancel" -f $taskId)
    $cancelReason = ""
    $wasCancelled = $false
    if (Test-Path -LiteralPath $cancelMarker) {
        $wasCancelled = $true
        try { $cancelReason = ([System.IO.File]::ReadAllText($cancelMarker, [System.Text.Encoding]::UTF8)).Trim() } catch {}
    }
    if ($inboxFile) {
        $msg = if ($wasCancelled) { "취소됨(CANCELLED): " + $(if ($cancelReason) { $cancelReason } else { "사용자 요청으로 취소했습니다." }) } else { "작업을 처리하던 프로세스가 끝내지 못하고 사라졌습니다(워처를 껐거나 강제 종료됐을 수 있습니다). 같은 지시를 다시 보내 주세요." }
        Log "$(if ($wasCancelled) { '취소' } else { '실패' }): $taskId - $msg"
        $claimModel = if ($Claim.model) { [string]$Claim.model } else { $null }
        $claimTried = if ($Claim.tried) { [string]$Claim.tried } else { $null }
        $claimSession = if ($Claim.session) { [string]$Claim.session } else { "" }
        $claimConvId = if ($Claim.conversation_id) { [string]$Claim.conversation_id } else { "" }
        $claimAccount = if ($Claim.PSObject.Properties['account'] -and $Claim.account) { [string]$Claim.account } else { "primary" }
        $claimFallbackFrom = if ($Claim.PSObject.Properties['fallback_from'] -and $Claim.fallback_from) { [string]$Claim.fallback_from } else { "" }
        $startedDt = $null
        $elapsedSec = $null
        $startText = if ($Claim.started_at) { [string]$Claim.started_at } elseif ($Claim.started) { [string]$Claim.started } else { "" }
        if ($startText) {
            $parsedStart = [datetime]::MinValue
            if ([datetime]::TryParse($startText, [ref]$parsedStart)) {
                $startedDt = $parsedStart
                $elapsedSec = [math]::Round([math]::Max(0.0, ((Get-Date) - $parsedStart).TotalSeconds), 1)
            }
        }
        $respText = $msg
        $workText = ""
        if ($claimConvId) {
            try {
                $workText = Get-AgyCancelledWorkText (Get-AgyHomeDir) $claimConvId $startedDt
                if ($workText) { $respText = $msg + "`n`n" + $workText }
            } catch {}
        }
        $outFile = Join-Path $OutboxDir "$taskId.response.md"
        if (-not (Test-Path -LiteralPath $outFile)) {
            [System.IO.File]::WriteAllText($outFile, $respText, (New-Object System.Text.UTF8Encoding($false)))
        }
        if ($script:IsSubWatcher) {
            $resFile = Join-Path $OutboxDir "$taskId.result.json"
            if (-not (Test-Path -LiteralPath $resFile)) {
                $stStr = if ($wasCancelled) { "CANCELLED" } else { "ERROR" }
                [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
                    task_id             = $taskId
                    slot_id             = $script:SubLayout.SlotId
                    status              = $stStr
                    fallback_eligible   = $false
                    error_message       = $msg
                    response_file       = $outFile
                    raw_file            = ""
                    error_log_file      = ""
                    model_used          = $claimModel
                    attempts            = $null
                    tried_models        = $claimTried
                    conversation_id     = $claimConvId
                    in_tokens           = $null
                    out_tokens          = $null
                    thinking_tokens     = $null
                    total_tokens        = $null
                    agy_duration        = $null
                    models              = @()
                    context_tokens      = $null
                    timed_out_reason    = if ($wasCancelled) { "cancel" } else { "dead_worker" }
                    cancelled_work_text = [string]$workText
                }))
            }
            [void](Remove-AgyFileSafe $inboxFile)
        } else {
            Write-UsageRow $taskId $claimModel $null $claimTried $null $null $null $null $elapsedSec $(if ($wasCancelled) { "CANCELLED" } else { "ERROR" }) $claimSession $claimConvId $null $null $null $null "" $claimAccount $claimFallbackFrom ""
            Move-Item -LiteralPath $inboxFile -Destination (Join-Path $ProcessedDir (Split-Path $inboxFile -Leaf)) -Force -ErrorAction SilentlyContinue
            Update-QAReport
        }
    }
    if ($wasCancelled) { [void](Remove-AgyFileSafe $cancelMarker) }
    [void](Remove-AgyFileSafe $ClaimPath)
}

# 지금 돌고 있는 작업들의 표시 목록. 죽은 작업의 표시는 여기서 정리한다.
function Get-RunningClaims {
    $alive = @()
    if (Test-Path -LiteralPath $RunningDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            $c = Read-RunningClaim $f.FullName
            if ($null -eq $c) {
                # 읽을 수 없는 표시 파일은 오래되면(쓰다 만 것) 지운다
                if (((Get-Date) - $f.LastWriteTime).TotalSeconds -gt 120) { [void](Remove-AgyFileSafe $f.FullName) }
                continue
            }
            if (Test-ClaimAlive $c) { $alive += $c } else { Resolve-DeadClaim $c $f.FullName }
        }
    }
    return @($alive)
}

# 폴더 경로를 비교용으로 정리한다(대소문자·끝의 구분자·슬래시 방향 무시)
function ConvertTo-SpaceKey([string]$Path) {
    $p = ([string]$Path).Trim().Replace('/', '\').TrimEnd('\').ToLowerInvariant()
    return $p
}

# 지금 도는 다른 작업 중 이 폴더들과 겹치는 폴더를 연 것의 수(git 안전장치가 "변화의 원인이 다른 작업일 수 있다"고 알리는 데 쓴다).
function Get-OverlappingRunningCount([string]$ExceptTaskId, $Cwds) {
    $n = 0
    try {
        if (@($Cwds).Count -eq 0) { return 0 }
        foreach ($f in @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            $c = Read-RunningClaim $f.FullName
            if ($null -eq $c -or [string]$c.task_id -eq $ExceptTaskId -or @($c.cwds).Count -eq 0) { continue }
            if (Test-SpaceOverlap $Cwds @($c.cwds)) { $n++ }
        }
    } catch {}
    return $n
}

# 두 작업의 "공간"(작업 폴더들)이 겹치는가: 같은 폴더이거나 한쪽이 다른 쪽의 상위 폴더이면 겹친다.
# 폴더가 하나도 없는 작업은 폴더로 구분할 수 없으므로 겹치는 것으로 본다(같은 세션끼리 차례로 하는 쪽이 안전하다).
function Test-SpaceOverlap($CwdsA, $CwdsB) {
    $a = @(@($CwdsA) | Where-Object { $_ } | ForEach-Object { ConvertTo-SpaceKey $_ })
    $b = @(@($CwdsB) | Where-Object { $_ } | ForEach-Object { ConvertTo-SpaceKey $_ })
    if ($a.Count -eq 0 -or $b.Count -eq 0) { return $true }
    foreach ($x in $a) {
        foreach ($y in $b) {
            if ($x -eq $y -or $x.StartsWith($y + '\') -or $y.StartsWith($x + '\')) { return $true }
        }
    }
    return $false
}

# 두 작업을 동시에 돌리면 안 되는가: 세션 이름이 같고(비어 있지 않고) 공간이 겹칠 때만 그렇다.
function Test-TaskConflict([string]$SessionA, $CwdsA, [string]$SessionB, $CwdsB) {
    if (-not $SessionA -or -not $SessionB) { return $false }
    if ($SessionA -ne $SessionB) { return $false }
    return (Test-SpaceOverlap $CwdsA $CwdsB)
}

# 작업자 powershell 에 넘길 인자(따옴표 없는 원래 값). 시험: tests\delegate-agy\agy-spawn.tests.ps1
function Get-InboxWorkerArgs([string]$Wrapper, [string]$TaskPath, [string]$RepoRootValue, [string]$RuntimeDirValue, [bool]$Skip = $false, [string]$SubSlotValue = "", [string]$SubBridgeDirValue = "") {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Wrapper,
        "-RepoRoot", $RepoRootValue, "-RuntimeDir", $RuntimeDirValue, "-WorkerTask", $TaskPath)
    if ($Skip) { $a += "-SkipPermissions" }
    if (-not [string]::IsNullOrWhiteSpace($SubSlotValue)) {
        $a += @("-SubSlot", $SubSlotValue)
        if (-not [string]::IsNullOrWhiteSpace($SubBridgeDirValue)) {
            $a += @("-SubBridgeDir", $SubBridgeDirValue)
        }
    }
    return $a
}

# 띄운 작업자가 실제로 시작했는가. $TimeoutMs 동안 살아 있거나, 그 전에 끝났더라도 지시 파일을 옮겼으면(처리함) $true.
# 곧바로 끝났는데 지시 파일이 그대로면 $false(인자 오류 등으로 시작도 못 한 것).
function Wait-InboxWorkerStarted([int]$WorkerPid, [string]$TaskPath, [int]$TimeoutMs = 1500) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue)) {
            return (-not (Test-Path -LiteralPath $TaskPath))
        }
        Start-Sleep -Milliseconds 100
    }
    return $true
}

function Start-InboxWorkerFallbackProcess([string[]]$ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = ($ArgList -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $proc = [System.Diagnostics.Process]::Start($psi)
    return $proc.Id
}

# 한 라운드에 여러 작업자를 연속으로 띄운 뒤, 시작 확인(1.5초 대기 및 실패 시 기본 방식 재시도)을 한 번에 묶어 확인한다.
# 작업자마다 1.5초씩 직렬로 기다리면 뒤 작업자 기동이 그만큼 늦어져 동시 실행 폭이 줄어드는 문제를 막는다.
function Confirm-InboxWorkersStarted([System.Collections.IList]$Workers, [int]$TimeoutMs = 1500) {
    if ($null -eq $Workers -or $Workers.Count -eq 0) { return }
    while ($true) {
        $pendingCheck = $false
        $now = Get-Date
        foreach ($w in $Workers) {
            if ($w.Done) { continue }
            $alive = ($null -ne (Get-Process -Id ([int]$w.WorkerPid) -ErrorAction SilentlyContinue))
            if (-not $alive) {
                $w.Done = $true
                if (Test-Path -LiteralPath ([string]$w.TaskPath)) {
                    Log "경고: 작업자(PID $($w.WorkerPid))가 시작 직후 끝났고 지시 파일이 그대로 남아 있습니다: $($w.FileName). 기본 방식으로 다시 띄웁니다."
                    try {
                        $newPid = Start-InboxWorkerFallbackProcess $w.ArgList
                        if ((Get-Process -Id $newPid -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath ([string]$w.TaskPath))) {
                            Write-RunningClaim ([string]$w.TaskId) @{ pid = $newPid }
                            Log "작업 재시작: $($w.FileName) (작업자 PID $newPid)"
                        } else {
                            Remove-RunningClaim ([string]$w.TaskId)
                        }
                    } catch {
                        Log "작업자를 다시 띄우지 못했습니다: $($_.Exception.Message)"
                        Remove-RunningClaim ([string]$w.TaskId)
                    }
                }
            } elseif ($now -ge $w.Deadline) {
                $w.Done = $true
            } else {
                $pendingCheck = $true
            }
        }
        if (-not $pendingCheck) { break }
        Start-Sleep -Milliseconds 100
    }
}

# 작업자 프로세스(보이지 않는 창)를 띄워 지시파일 하나를 처리하게 한다. 띄웠으면 $true.
# 작업자는 watch-agy.ps1 을 그대로 쓰되 명령줄에 "watch-agy.ps1" 이 나타나지 않게 얇은 껍데기(agy-task-worker.ps1)로 띄운다 —
# start-agy/ensure-agy-running 이 명령줄의 그 이름으로 워처를 찾기 때문에, 작업자가 워처로 오인되어 종료되는 일을 막는다.
function Start-InboxWorker([System.IO.FileInfo]$File, [string]$Session, $Cwds, [System.Collections.IList]$DeferredChecks = $null) {
    $taskId = Get-SubTaskBaseId $File.Name
    $wrapper = Join-Path $PSScriptRoot "agy-task-worker.ps1"
    if (-not (Test-Path -LiteralPath $wrapper)) {
        Log "오류: 작업자 스크립트를 찾을 수 없습니다: $wrapper (install.ps1 을 다시 실행해 주세요)"
        return $false
    }
    # 따옴표 없는 원래 값. agy-spawn 헬퍼가 인자마다 Windows 규칙대로 감싼다(미리 따옴표를 붙이면 따옴표가 한 번 더
    # 이스케이프되어 powershell 이 -File 경로를 찾지 못하고 바로 끝난다). 아래 기본 방식(ProcessStartInfo)에만 따옴표를 붙인다.
    $rawArgs = if ($script:IsSubWatcher) {
        @(Get-InboxWorkerArgs $wrapper $File.FullName $RepoRoot $RuntimeDir ([bool]$SkipPermissions) $script:SubLayout.SlotId $script:SubBridgeRoot)
    } else {
        @(Get-InboxWorkerArgs $wrapper $File.FullName $RepoRoot $RuntimeDir ([bool]$SkipPermissions))
    }
    $argList = @($rawArgs | ForEach-Object { if ([string]$_ -match '\s') { "`"$_`"" } else { [string]$_ } })
    try {
        # 표시 파일을 먼저 만들어 두고(PID 는 0) 띄운 뒤 PID 를 채운다: 그 사이 다른 쪽이 "안 도는 작업"으로 보지 않게
        Write-RunningClaim $taskId @{ pid = 0; session = $Session; cwds = @($Cwds); started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); watcher_pid = $PID }
        $workerPid = 0
        $usedDetached = $false
        if (-not (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue)) {
            $spawnFile = Join-Path $PSScriptRoot "agy-spawn.ps1"
            if (-not (Test-Path $spawnFile)) { $spawnFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-spawn.ps1" }
            if (Test-Path $spawnFile) { . $spawnFile }
        }
        if (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue) {
            $workerPid = Start-AgyHiddenDetachedProcess -FilePath "powershell.exe" -ArgumentList $rawArgs -WorkingDirectory $RuntimeDir -NoShellFallback
            if ($workerPid -gt 0) {
                $usedDetached = $true
                # 일괄 확인 리스트가 없으면 기존처럼 즉시 시작 여부를 확인한다
                if ($null -eq $DeferredChecks -and -not (Wait-InboxWorkerStarted $workerPid $File.FullName)) {
                    Log "경고: 작업자(PID $workerPid)가 시작 직후 끝났고 지시 파일이 그대로 남아 있습니다: $($File.Name). 기본 방식으로 다시 띄웁니다."
                    $workerPid = 0
                    $usedDetached = $false
                }
            }
        }
        if ($workerPid -le 0) {
            $workerPid = Start-InboxWorkerFallbackProcess $argList
        }
        if ((Get-Process -Id $workerPid -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $File.FullName)) {
            Write-RunningClaim $taskId @{ pid = $workerPid }
            if ($usedDetached -and $null -ne $DeferredChecks) {
                [void]$DeferredChecks.Add(@{
                    TaskId    = $taskId
                    TaskPath  = $File.FullName
                    FileName  = $File.Name
                    WorkerPid = $workerPid
                    ArgList   = $argList
                    Deadline  = (Get-Date).AddMilliseconds(1500)
                    Done      = $false
                })
            }
        } else {
            Remove-RunningClaim $taskId
        }
        Log "작업 시작: $($File.Name) (작업자 PID $workerPid$(if ($Session) { ", 세션: $Session" }))"
        return $true
    } catch {
        Log "작업자를 띄우지 못했습니다: $($_.Exception.Message)"
        Remove-RunningClaim $taskId
        return $false
    }
}

function Format-WorkerExceptionLog($ErrorRecord) {
    $msg = if ($ErrorRecord -and $ErrorRecord.Exception) { [string]$ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    $stackLines = @()
    if ($ErrorRecord -and $ErrorRecord.ScriptStackTrace) {
        $stackLines = @(([string]$ErrorRecord.ScriptStackTrace -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 2)
    }
    $stackPart = if ($stackLines.Count -gt 0) { " @ " + ($stackLines -join " | ") } else { "" }
    return "작업자 오류: $msg$stackPart"
}

function Complete-InboxTaskAsError([System.IO.FileInfo]$File, [string]$Message) {
    if ($null -eq $File) { return }
    $taskId = Get-SubTaskBaseId $File.Name
    $outFile = Join-Path $OutboxDir "$taskId.response.md"
    $doneFile = Join-Path $ProcessedDir $File.Name
    try {
        if (-not (Test-Path -LiteralPath $OutboxDir)) { New-Item -ItemType Directory -Force -Path $OutboxDir | Out-Null }
        if (-not (Test-Path -LiteralPath $outFile)) {
            [System.IO.File]::WriteAllText($outFile, $Message, (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch {
        try { Log "오류 응답 파일 쓰기 실패($taskId): $($_.Exception.Message)" } catch {}
    }
    if ($script:IsSubWatcher) {
        try {
            if (Get-Command Write-SubCancelledResult -ErrorAction SilentlyContinue) {
                Write-SubCancelledResult $taskId $Message $null
            }
        } catch {
            try { Log "부계정 오류 결과 쓰기 실패($taskId): $($_.Exception.Message)" } catch {}
        }
        try {
            if (Test-Path -LiteralPath $File.FullName) {
                [void](Remove-AgyFileSafe $File.FullName)
            }
        } catch {}
    } else {
        try {
            Write-UsageRow $taskId $null $null $null $null $null $null $null $null "ERROR" "" ""
        } catch {
            try { Log "오류 사용량 기록 실패($taskId): $($_.Exception.Message)" } catch {}
        }
        try {
            if (Test-Path -LiteralPath $File.FullName) {
                Complete-TaskQaRecord $taskId $File.FullName $doneFile
            }
        } catch {
            try { Log "오류 기록 보충 실패($taskId): $($_.Exception.Message)" } catch {}
        }
        if (Test-Path -LiteralPath $File.FullName) {
            try {
                if (-not (Test-Path -LiteralPath $ProcessedDir)) { New-Item -ItemType Directory -Force -Path $ProcessedDir | Out-Null }
                Move-Item -LiteralPath $File.FullName -Destination $doneFile -Force
            } catch {
                try { Log "오류 지시 파일 이동 실패($taskId): $($_.Exception.Message)" } catch {}
            }
        }
    }
    try { Remove-RunningClaim $taskId } catch {}
}

# 지시파일 하나를 끝까지 처리한다(작업자 모드의 본체). 끝나면 표시 파일을 지운다.
function Invoke-InboxTask([string]$TaskPath) {
    $file = Get-Item -LiteralPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $file) { return }
    $taskKey = Get-SubTaskBaseId $file.Name
    if ($WorkerTask) { $script:LogPrefix = "[$taskKey] " }

    $slotTag = if ($script:IsSubWatcher) { "sub_" + $script:SubLayout.SlotId } else { "pri" }
    $mtxName = "Local\SamjilAgyWorker_{0}_{1}" -f $slotTag, ($taskKey -replace '[^A-Za-z0-9_-]', '_')
    $mtx = $null
    $acquired = $false
    try {
        $mtx = New-Object System.Threading.Mutex($false, $mtxName)
        try {
            $acquired = $mtx.WaitOne(0)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            Log "경고: 이미 다른 작업자가 처리 중이어서 중복 실행을 건너뜁니다: $taskKey"
            return
        }
        # 표시 파일의 PID 를 내 것으로 확정한다(껍데기 프로세스가 곧 이 프로세스다)
        $script:CurrentTaskId = $taskKey
        Write-RunningClaim $taskKey @{ pid = $PID }
        try {
            if ($script:IsSubWatcher) {
                Invoke-InboxSubWorkerTask $file
            } else {
                Invoke-InboxTaskBody $file
            }
        } catch {
            $errRec = $_
            $exMsg = if ($errRec.Exception) { [string]$errRec.Exception.Message } else { [string]$errRec }
            try { Log (Format-WorkerExceptionLog $errRec) } catch {}
            if (Test-Path -LiteralPath $file.FullName) {
                $errOutMsg = "agy 실행 중 오류(작업자): $exMsg. 같은 지시를 다시 보내거나 직접 처리하세요."
                Complete-InboxTaskAsError $file $errOutMsg
            }
        }
    } finally {
        if ($acquired) {
            Remove-RunningClaim $taskKey
            if ($mtx) { try { $mtx.ReleaseMutex() } catch {} }
        }
        if ($mtx) { try { $mtx.Dispose() } catch {} }
    }
}

function Test-AgySubFallbackError([string]$ErrorMessage, [string]$StdErr, [string]$RawJson, [string]$Model) {
    $combined = ("{0}`n{1}`n{2}" -f [string]$ErrorMessage, [string]$StdErr, [string]$RawJson)
    if (Test-AgyFallbackError ([string]$ErrorMessage) $Model) { return $true }
    if (Test-AgyFallbackError $combined $Model) { return $true }
    if ($combined -match '(?i)(unauthenticated|unauthorized|invalid.?credential|credential.*missing|login required|not logged in|oauth.*(fail|expired|missing)|token.?expired|\b401\b|\b403\b|permission_denied)') {
        return $true
    }
    return $false
}

function Write-SubCancelledResult([string]$TaskId, [string]$ReasonText = "", $Claim = $null) {
    $msg = "취소됨(CANCELLED): " + $(if ($ReasonText) { $ReasonText } else { "사용자 요청으로 취소했습니다." })
    $outFile = Join-Path $OutboxDir "$TaskId.response.md"
    $resFile = Join-Path $OutboxDir "$TaskId.result.json"
    $workText = ""
    $claimConvId = if ($Claim -and $Claim.conversation_id) { [string]$Claim.conversation_id } else { "" }
    if ($claimConvId -and (Get-Command Get-AgyCancelledWorkText -ErrorAction SilentlyContinue)) {
        $startedDt = $null
        $startText = if ($Claim.started_at) { [string]$Claim.started_at } elseif ($Claim.started) { [string]$Claim.started } else { "" }
        if ($startText) { [void][datetime]::TryParse($startText, [ref]$startedDt) }
        try { $workText = Get-AgyCancelledWorkText (Get-AgyHomeDir) $claimConvId $startedDt } catch {}
    }
    $respBody = if ($workText) { $msg + "`n`n" + $workText } else { $msg }
    if (-not (Test-Path -LiteralPath $outFile)) {
        [System.IO.File]::WriteAllText($outFile, $respBody, (New-Object System.Text.UTF8Encoding($false)))
    }
    if (-not (Test-Path -LiteralPath $resFile)) {
        [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
            task_id             = $TaskId
            slot_id             = $script:SubLayout.SlotId
            status              = "CANCELLED"
            fallback_eligible   = $false
            error_message       = $msg
            response_file       = $outFile
            raw_file            = ""
            error_log_file      = ""
            model_used          = if ($Claim -and $Claim.model) { [string]$Claim.model } else { "" }
            attempts            = if ($Claim -and $Claim.attempt) { [int]$Claim.attempt } else { $null }
            tried_models        = if ($Claim -and $Claim.tried) { [string]$Claim.tried } else { "" }
            conversation_id     = $claimConvId
            in_tokens           = $null
            out_tokens          = $null
            thinking_tokens     = $null
            total_tokens        = $null
            agy_duration        = $null
            models              = @()
            context_tokens      = $null
            timed_out_reason    = "cancel"
            cancelled_work_text = [string]$workText
        }))
    }
}

function Invoke-InboxSubWorkerTask([System.IO.FileInfo]$file) {
    $payload = Read-BridgeJson $file.FullName
    $fallbackBaseId = Get-SubTaskBaseId $file.Name
    $rawTaskId = if ($payload -and $payload.task_id) { [string]$payload.task_id } else { $fallbackBaseId }
    $baseName = if (Test-AgyBridgeSafeId $rawTaskId) { $rawTaskId } else { $fallbackBaseId }
    $outFile = Join-Path $OutboxDir "$baseName.response.md"
    $errFile = Join-Path $OutboxDir "$baseName.error.log"
    $rawFile = Join-Path $OutboxDir "$baseName.raw.json"
    $resFile = Join-Path $OutboxDir "$baseName.result.json"

    $agyStderr = ""
    $asyncUsageCheck = $true
    $finalStatus = "ERROR"
    $fallbackEligible = $false
    try {
        if ($payload -and $payload.task_id -and -not (Test-AgyBridgeSafeId ([string]$payload.task_id))) {
            $errMsg = "유효하지 않은 브리지 task_id 가 거부되었습니다: $($payload.task_id)"
            [System.IO.File]::WriteAllText($outFile, $errMsg, (New-Object System.Text.UTF8Encoding($false)))
            [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
                task_id = $baseName; slot_id = $script:SubLayout.SlotId; status = "ERROR"; fallback_eligible = $false;
                error_message = $errMsg; response_file = $outFile; raw_file = ""; error_log_file = "";
                model_used = ""; attempts = 0; tried_models = ""; conversation_id = "";
                in_tokens = $null; out_tokens = $null; thinking_tokens = $null; total_tokens = $null; agy_duration = $null;
                models = @(); context_tokens = $null; timed_out_reason = ""; cancelled_work_text = ""
            }))
            return
        }
        if ($null -eq $payload) {
            $errMsg = "부계정 작업 JSON($($file.Name))을 읽을 수 없습니다."
            [System.IO.File]::WriteAllText($outFile, $errMsg, (New-Object System.Text.UTF8Encoding($false)))
            [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
                task_id = $baseName; slot_id = $script:SubLayout.SlotId; status = "ERROR"; fallback_eligible = $false;
                error_message = $errMsg; response_file = $outFile; raw_file = ""; error_log_file = "";
                model_used = ""; attempts = 0; tried_models = ""; conversation_id = "";
                in_tokens = $null; out_tokens = $null; thinking_tokens = $null; total_tokens = $null; agy_duration = $null;
                models = @(); context_tokens = $null; timed_out_reason = ""; cancelled_work_text = ""
            }))
            return
        }

        if ($null -ne $payload.async_usage_check) { $asyncUsageCheck = [bool]$payload.async_usage_check }
        $sessionName = if ($payload.session) { [string]$payload.session } else { "" }
        $convId      = if ($payload.conversation_id) { [string]$payload.conversation_id } else { "" }
        $knownModel  = if ($payload.known_model) { [string]$payload.known_model } else { "" }
        $promptPath  = if ($payload.prompt_file) { [string]$payload.prompt_file } else { "" }
        $cwds        = @($payload.cwds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        $modelChain  = @($payload.model_chain | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        $tier        = if ($payload.tier) { [string]$payload.tier } else { "" }
        $slashCmd    = if ($payload.slash_command) { [string]$payload.slash_command } else { "" }
        $execMode    = if ($payload.execution_mode) { [string]$payload.execution_mode } else { "" }

        $promptText = ""
        if ($promptPath -and (Test-AgySubPathUnderRoot $promptPath $script:SubLayout.PromptsDir) -and (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
            $promptText = [System.IO.File]::ReadAllText($promptPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        } elseif ($promptPath -and -not (Test-AgySubPathUnderRoot $promptPath $script:SubLayout.PromptsDir)) {
            Log "보안 경고: 허용되지 않은 prompt_file 경로를 무시합니다: $promptPath"
        } elseif ($payload.raw_prompt_preview) {
            $promptText = [string]$payload.raw_prompt_preview
        }

        $filteredChain = @($modelChain)
        $avail = @(Get-WatcherAvailableModels)
        if (-not $convId -and $avail.Count -gt 0 -and $filteredChain.Count -gt 0) {
            $filteredChain = @($filteredChain | Where-Object { $avail -icontains $_ })
            if ($filteredChain.Count -eq 0) {
                $errMsg = "부계정 '$($script:SubLayout.SlotId)' 에서 요청한 모델($($modelChain -join ', '))을 사용할 수 없습니다(agy models 미보유)."
                [System.IO.File]::WriteAllText($outFile, $errMsg, (New-Object System.Text.UTF8Encoding($false)))
                [System.IO.File]::WriteAllText($errFile, "", (New-Object System.Text.UTF8Encoding($true)))
                [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
                    task_id = $baseName; slot_id = $script:SubLayout.SlotId; status = "ERROR"; fallback_eligible = $true;
                    error_message = $errMsg; response_file = $outFile; raw_file = ""; error_log_file = $errFile;
                    model_used = ""; attempts = 0; tried_models = ($modelChain -join ' -> '); conversation_id = "";
                    in_tokens = $null; out_tokens = $null; thinking_tokens = $null; total_tokens = $null; agy_duration = $null;
                    models = @(); context_tokens = $null; timed_out_reason = ""; cancelled_work_text = ""
                }))
                $fallbackEligible = $true
                return
            }
        }

        $safePrompt = $promptText -replace '"', '\"'
        $origEnvSubSlot = $env:AGY_SUB_SLOT
        $env:AGY_SUB_SLOT = $script:SubLayout.SlotId
        try {
            $agyResult = Invoke-AgyWithFallback -safePrompt $safePrompt -targetCwd $cwds -skipPerm:$SkipPermissions -errFile $errFile -conversationId $convId -knownModel $knownModel -taskId $baseName -promptFile $promptPath -modelChain $filteredChain -tier $tier -slashCommand $slashCmd -executionMode $execMode
        } finally {
            if ($null -eq $origEnvSubSlot) { Remove-Item Env:\AGY_SUB_SLOT -ErrorAction SilentlyContinue } else { $env:AGY_SUB_SLOT = $origEnvSubSlot }
        }
        $agyStderr = if ($null -ne $agyResult.StdErr) { [string]$agyResult.StdErr } else { "" }

        $effectiveConvId = if ($agyResult.ConversationId) { [string]$agyResult.ConversationId } elseif ($convId) { $convId } else { "" }
        if ($effectiveConvId) {
            [void](Sync-SubTranscriptMirror (Get-AgyHomeDir) $effectiveConvId $baseName -1)
        }

        $recTried = ($agyResult.TriedModels -join " -> ")
        $modelsList = New-Object System.Collections.ArrayList
        $ctxTokens = $null
        $recInTok = $agyResult.InTok; $recOutTok = $agyResult.OutTok; $recThinkTok = $agyResult.ThinkTok; $recTotTok = $agyResult.TotTok
        if ($effectiveConvId -and (Get-Command New-AgyUsageState -ErrorAction SilentlyContinue)) {
            try {
                $tPath = Get-AgyTranscriptPath (Get-AgyHomeDir) $effectiveConvId
                $compactT = if ($tPath) { Join-Path (Split-Path -Parent $tPath) "transcript.jsonl" } else { $null }
                $actualT = if ($compactT -and (Test-Path -LiteralPath $compactT)) { $compactT } elseif ($tPath -and (Test-Path -LiteralPath $tPath)) { $tPath } else { $null }
                if ($actualT) {
                    $stU = New-AgyUsageState $actualT
                    Update-AgyUsageState $stU
                    $sinceStart = (Get-Date).AddSeconds(-([double]$agyResult.ElapsedSec + 5))
                    $sumU = Get-AgyUsageSummary $stU 0 $sinceStart
                    if ($sumU) {
                        if ($sumU.Context -gt 0) { $ctxTokens = [int64]$sumU.Context }
                        foreach ($bm in @($sumU.ByModel)) {
                            [void]$modelsList.Add([ordered]@{
                                model    = [string]$bm.Model
                                input    = [int64]$bm.Input
                                cache    = [int64]$bm.Cache
                                output   = [int64]$bm.Output
                                thinking = [int64]$bm.Thinking
                                steps    = [int]$bm.Steps
                            })
                        }
                        if ($sumU.Turns -gt 0 -and $null -eq $recTotTok -and ($sumU.Input -gt 0 -or $sumU.Output -gt 0 -or $sumU.Total -gt 0)) {
                            $recInTok = $sumU.Input; $recOutTok = $sumU.Output; $recTotTok = $sumU.Total
                            if ($sumU.Thinking -gt 0) { $recThinkTok = $sumU.Thinking }
                        }
                    }
                }
            } catch {}
        }

        if ($agyResult.RawJson) {
            [System.IO.File]::WriteAllText($rawFile, [string]$agyResult.RawJson, (New-Object System.Text.UTF8Encoding($false)))
        } else {
            $rawFile = ""
        }

        $cancelMarker = Join-Path $RunningDir ("{0}.cancel" -f $baseName)
        $workText = ""
        $isCancelled = ($agyResult.TimedOutReason -eq 'cancel') -or (Test-Path -LiteralPath $cancelMarker)
        if ($isCancelled) {
            $finalStatus = "CANCELLED"
            $fallbackEligible = $false
            $cancelReason = ""
            if (Test-Path -LiteralPath $cancelMarker) {
                try { $cancelReason = ([System.IO.File]::ReadAllText($cancelMarker, [System.Text.Encoding]::UTF8)).Trim() } catch {}
            }
            $msg = "취소됨(CANCELLED): " + $(if ($cancelReason) { $cancelReason } else { "사용자 요청으로 취소했습니다." })
            if ($effectiveConvId -and (Get-Command Get-AgyCancelledWorkText -ErrorAction SilentlyContinue)) {
                try {
                    $cSince = (Get-Date).AddSeconds(-([double]$agyResult.ElapsedSec + 5))
                    $workText = Get-AgyCancelledWorkText (Get-AgyHomeDir) $effectiveConvId $cSince
                } catch {}
            }
            $respBody = if ($workText) { $msg + "`n`n" + $workText } else { $msg }
            [System.IO.File]::WriteAllText($outFile, $respBody, (New-Object System.Text.UTF8Encoding($false)))
            $errMsgOut = $msg
        } elseif ($agyResult.Success) {
            $finalStatus = "OK"
            $fallbackEligible = $false
            [System.IO.File]::WriteAllText($outFile, [string]$agyResult.Response, (New-Object System.Text.UTF8Encoding($false)))
            $errMsgOut = ""
        } elseif ($agyResult.Blocked) {
            $finalStatus = "BLOCKED"
            $fallbackEligible = $false
            [System.IO.File]::WriteAllText($outFile, [string]$agyResult.Response, (New-Object System.Text.UTF8Encoding($false)))
            $errMsgOut = [string]$agyResult.ErrorMessage
        } else {
            $finalStatus = "ERROR"
            $lastTried = if (@($agyResult.TriedModels).Count -gt 0) { [string]@($agyResult.TriedModels)[-1] } elseif ($filteredChain.Count -gt 0) { [string]$filteredChain[0] } else { "" }
            $fallbackEligible = Test-AgySubFallbackError ([string]$agyResult.ErrorMessage) $agyStderr ([string]$agyResult.RawJson) $lastTried
            $errMsgOut = "agy 실행 실패 (시도한 모델: $recTried) - $($agyResult.ErrorMessage)"
            [System.IO.File]::WriteAllText($outFile, $errMsgOut, (New-Object System.Text.UTF8Encoding($false)))
        }

        [System.IO.File]::WriteAllText($errFile, $agyStderr, (New-Object System.Text.UTF8Encoding($true)))

        # .result.json 을 /usage 보다 먼저 원자 기록해 응답 지연을 0초로 유지한다
        [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
            task_id             = $baseName
            slot_id             = $script:SubLayout.SlotId
            status              = $finalStatus
            fallback_eligible   = [bool]$fallbackEligible
            error_message       = [string]$errMsgOut
            response_file       = $outFile
            raw_file            = $rawFile
            error_log_file      = $errFile
            model_used          = if ($agyResult.ModelUsed) { [string]$agyResult.ModelUsed } else { "" }
            attempts            = $agyResult.Attempts
            tried_models        = $recTried
            conversation_id     = $effectiveConvId
            in_tokens           = $recInTok
            out_tokens          = $recOutTok
            thinking_tokens     = $recThinkTok
            total_tokens        = $recTotTok
            agy_duration        = $agyResult.AgyDuration
            elapsed_sec         = $agyResult.ElapsedSec
            models              = @($modelsList)
            context_tokens      = $ctxTokens
            timed_out_reason    = [string]$agyResult.TimedOutReason
            cancelled_work_text = [string]$workText
        }))
        [void](Remove-AgyFileSafe $cancelMarker)
    } catch {
        $exMsg = "부계정 작업자 오류: $($_.Exception.Message)"
        try { [System.IO.File]::WriteAllText($outFile, $exMsg, (New-Object System.Text.UTF8Encoding($false))) } catch {}
        [void](Write-BridgeJsonAtomic $resFile ([ordered]@{
            task_id = $baseName; slot_id = $script:SubLayout.SlotId; status = "ERROR"; fallback_eligible = $false;
            error_message = $exMsg; response_file = $outFile; raw_file = ""; error_log_file = $errFile;
            model_used = ""; attempts = 0; tried_models = ""; conversation_id = "";
            in_tokens = $null; out_tokens = $null; thinking_tokens = $null; total_tokens = $null; agy_duration = $null;
            models = @(); context_tokens = $null; timed_out_reason = ""; cancelled_work_text = ""
        }))
    } finally {
        [void](Remove-AgyFileSafe $file.FullName)
    }

    # 응답 및 .result.json 기록 후 비동기 백그라운드에서 /usage 를 1회 조회해 .quota.json sidecar 를 남긴다
    if ($asyncUsageCheck -and ($finalStatus -eq "OK" -or ($finalStatus -eq "ERROR" -and $fallbackEligible))) {
        $quotaSidecar = Join-Path $OutboxDir "$baseName.quota.json"
        Start-SubSlotAsyncQuotaRefresh $baseName $quotaSidecar
    }
}

function Start-SubSlotAsyncQuotaRefresh([string]$TagId, [string]$QuotaSidecar = "") {
    if (-not $script:IsSubWatcher -or [string]::IsNullOrWhiteSpace($TagId)) { return }
    try {
        $wrapper = Join-Path $PSScriptRoot "agy-task-worker.ps1"
        if (Test-Path -LiteralPath $wrapper -PathType Leaf) {
            $usageArgs = @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapper,
                "-SubSlot", $script:SubLayout.SlotId,
                "-SubBridgeDir", $script:SubBridgeRoot,
                "-SubUsageTaskId", $TagId,
                "-SubUsageSlotFile", $script:SubLayout.QuotaFile
            )
            if (-not [string]::IsNullOrWhiteSpace($QuotaSidecar)) {
                $usageArgs += @("-SubUsageQuotaFile", $QuotaSidecar)
            }
            $launched = $false
            if (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue) {
                $uPid = Start-AgyHiddenDetachedProcess -FilePath "powershell.exe" -ArgumentList $usageArgs -WorkingDirectory $script:SubLayout.SlotRoot -NoShellFallback
                if ($uPid -gt 0) { $launched = $true }
            }
            if (-not $launched) {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "powershell.exe"
                $psi.Arguments = (@($usageArgs | ForEach-Object { if ([string]$_ -match '[\s"]') { "`"$_`"" } else { [string]$_ } }) -join ' ')
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                [void][System.Diagnostics.Process]::Start($psi)
            }
        }
    } catch {}
}

# 한 지시파일을 처리하는 본체(예전에 메인 루프 안에 있던 부분)

function Sync-SubQuotaSidecars {
    if ($script:IsSubWatcher -or -not $AgyDbPath) { return }
    try {
        $cfgNow = Get-WatcherModelConfig
        $subCfg = $cfgNow.SubAccounts
        if ($null -eq $subCfg -or -not $subCfg.Enabled) { return }
        $bridgeRoot = Get-AgySubBridgeRoot $subCfg
        foreach ($s in @($subCfg.Slots)) {
            $sid = ([string]$s.Id).Trim()
            if (-not $sid) { continue }
            $lay = Get-AgySubSlotLayout $bridgeRoot $sid
            if (-not (Test-Path -LiteralPath $lay.OutboxDir -PathType Container)) { continue }
            foreach ($qf in @(Get-ChildItem -LiteralPath $lay.OutboxDir -Filter "*.quota.json" -File -ErrorAction SilentlyContinue | Sort-Object CreationTime)) {
                $qObj = Read-BridgeJson $qf.FullName
                if ($null -eq $qObj) { continue }
                $tid = if ($qObj.task_id) { [string]$qObj.task_id } else { ([System.IO.Path]::GetFileNameWithoutExtension($qf.Name) -replace '\.quota$', '') }
                $slotId = if ($qObj.slot_id) { [string]$qObj.slot_id } else { $sid }
                $mat = if ($qObj.measured_at) { [string]$qObj.measured_at } else { ([datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")) }
                $fiveUsed = $qObj.five_used
                $weekUsed = $qObj.week_used
                $fiveReset = if ($qObj.five_reset) { [string]$qObj.five_reset } else { "" }
                $weekReset = if ($qObj.week_reset) { [string]$qObj.week_reset } else { "" }

                if (Get-Command Save-SubTaskQuota -ErrorAction SilentlyContinue) {
                    [void](Save-SubTaskQuota $AgyDbPath $tid $slotId $mat $fiveUsed $fiveReset $weekUsed $weekReset)
                }
                if ((Get-Command Add-UsageHistory -ErrorAction SilentlyContinue) -and $null -ne $fiveUsed -and $null -ne $weekUsed -and $fiveReset -and $weekReset) {
                    $atUtc = [datetime]::UtcNow
                    $parsedDto = [DateTimeOffset]::MinValue
                    if ([DateTimeOffset]::TryParse($mat, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$parsedDto)) {
                        $atUtc = $parsedDto.UtcDateTime
                    }
                    [void](Add-UsageHistory $RuntimeDir ("agy-sub:{0}" -f $slotId) $fiveUsed $fiveReset $weekUsed $weekReset -AtUtc $atUtc)
                }
                [void](Remove-AgyFileSafe $qf.FullName)
            }
        }
    } catch {}
}

function Invoke-BridgeSubAccountPool {
    param(
        [string]$TaskId,
        [string]$SessionName,
        [string]$ConversationId,
        [string]$KnownModel,
        [string]$PromptForAgy,
        [string]$RawPromptPreview,
        [string[]]$Cwds,
        [string[]]$ModelChain,
        [string]$ModelTier,
        [string]$SlashCmd,
        [string]$ExecutionMode,
        $ExistingSession,
        [bool]$Upgrade
    )
    $noRoute = @{ Handled = $false; FallbackToPrimary = $false; Account = "primary"; FallbackFrom = ""; AccountNote = ""; SubSlotsLabel = ""; Result = $null; TranscriptPath = ""; SlotLayout = $null }
    if ($script:IsSubWatcher -or -not (Get-Command Test-AgySubAccountCandidate -ErrorAction SilentlyContinue)) { return $noRoute }

    $cfgNow = Get-WatcherModelConfig
    $subCfg = $cfgNow.SubAccounts
    $firstModel = [string](@($ModelChain) | Select-Object -First 1)
    $candCheck = Test-AgySubAccountCandidate $subCfg $firstModel $SlashCmd $Cwds $ExistingSession $Upgrade
    if (-not $candCheck.Eligible) { return $noRoute }

    $bridgeRoot = Get-AgySubBridgeRoot $subCfg
    $hChain = @(Get-AgyHydrogenPrefixChain $ModelChain ([string]$subCfg.ModelPattern))
    if ($hChain.Count -eq 0) { return $noRoute }

    $ackTimeoutSec = if ($subCfg.AckTimeoutSec -gt 0) { [int]$subCfg.AckTimeoutSec } else { 12 }
    $cooldownSec   = if ($subCfg.CooldownSec -ge 0) { [int]$subCfg.CooldownSec } else { 60 }
    $slotOrder     = @(Select-AgySubSlotOrder $subCfg $bridgeRoot $Cwds $TaskId $ExistingSession)
    $failedSlots   = New-Object System.Collections.ArrayList
    $primaryCancel = Join-Path $RunningDir ("{0}.cancel" -f $TaskId)

    if ($slotOrder.Count -eq 0) {
        $busyWaitStart = Get-Date
        $busyState = Get-AgySubSlotsBusyState $subCfg $bridgeRoot
        while ($busyState.HasBusyHealthySlot -and (((Get-Date) - $busyWaitStart).TotalSeconds -lt 20) -and -not (Test-Path -LiteralPath $primaryCancel -PathType Leaf)) {
            Start-Sleep -Milliseconds 500
            $slotOrder = @(Select-AgySubSlotOrder $subCfg $bridgeRoot $Cwds $TaskId $ExistingSession)
            if ($slotOrder.Count -gt 0) { break }
            $busyState = Get-AgySubSlotsBusyState $subCfg $bridgeRoot
        }
    }

    foreach ($slotObj in $slotOrder) {
        $sid = [string]$slotObj.Id
        $slotLay = Get-AgySubSlotLayout $bridgeRoot $sid
        Initialize-AgySubSlotDirectories $slotLay | Out-Null

        # 다른 계정에서 이어받거나 첫 전환 시 conversation_id 는 전달 불가하므로 최근 대화 Q&A 문맥만 보강
        $convForSlot = $ConversationId
        $knownForSlot = $KnownModel
        $promptTextForSlot = $PromptForAgy
        $existingAcct = if ($ExistingSession -and $ExistingSession.PSObject.Properties['account'] -and $ExistingSession.account) { [string]$ExistingSession.account } else { "" }
        if ($SessionName -and $ConversationId -and $existingAcct -and ($existingAcct -ine $sid)) {
            $convForSlot = ""
            $knownForSlot = ""
            try {
                $hist = @(Get-AgySessionHistory $AgyDbPath $SessionName 2)
                if ($hist.Count -gt 0) {
                    $promptTextForSlot = New-AgyUpgradeContext $hist $KnownModel $hChain[0] $PromptForAgy
                }
            } catch {}
        }

        $slotPromptPath = Join-Path $slotLay.PromptsDir ("prompt_{0}.txt" -f $TaskId)
        [System.IO.File]::WriteAllText($slotPromptPath, $promptTextForSlot, (New-Object System.Text.UTF8Encoding($false)))
        $slotInboxPath  = Join-Path $slotLay.InboxDir ("{0}.task.json" -f $TaskId)
        $slotResPath    = Join-Path $slotLay.OutboxDir ("{0}.result.json" -f $TaskId)
        $slotClaimPath  = Join-Path $slotLay.RunningDir ("{0}.json" -f $TaskId)
        $slotCancelPath = Join-Path $slotLay.RunningDir ("{0}.cancel" -f $TaskId)
        $slotTransPath  = Join-Path $slotLay.TranscriptsDir ("{0}.jsonl" -f $TaskId)

        [void](Remove-AgyFileSafe $slotResPath)
        [void](Remove-AgyFileSafe $slotCancelPath)

        $payload = [ordered]@{
            task_id              = $TaskId
            session              = [string]$SessionName
            conversation_id      = [string]$convForSlot
            known_model          = [string]$knownForSlot
            prompt_file          = $slotPromptPath
            cwds                 = @($Cwds)
            model_chain          = @($hChain)
            tier                 = [string]$ModelTier
            slash_command        = [string]$SlashCmd
            execution_mode       = [string]$ExecutionMode
            started_from_primary = $true
            async_usage_check    = [bool]$subCfg.AsyncUsageCheck
            raw_prompt_preview   = [string]$RawPromptPreview
        }
        if (-not (Write-BridgeJsonAtomic $slotInboxPath $payload)) {
            [void]$failedSlots.Add($sid)
            continue
        }
        if (Get-Command Set-AgySubSlotDispatched -ErrorAction SilentlyContinue) {
            [void](Set-AgySubSlotDispatched $bridgeRoot $sid)
        }

        $fbBefore = ($failedSlots -join ',')
        Write-RunningClaim $TaskId @{
            account           = $sid
            bridge_slot       = $sid
            bridge_transcript = $slotTransPath
            model             = [string]$hChain[0]
            tier              = [string]$ModelTier
            fallback_from     = $fbBefore
            started_at        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }

        # 1) Ack 대기 (ack_timeout_sec 내 slot running/<id>.json 또는 outbox/<id>.result.json)
        $acked = $false
        $ackDeadline = (Get-Date).AddSeconds($ackTimeoutSec)
        while ((Get-Date) -lt $ackDeadline) {
            if (Test-Path -LiteralPath $primaryCancel -PathType Leaf) {
                try { Copy-Item -LiteralPath $primaryCancel -Destination $slotCancelPath -Force -ErrorAction SilentlyContinue } catch {}
            }
            if ((Test-Path -LiteralPath $slotResPath -PathType Leaf) -or (Test-Path -LiteralPath $slotClaimPath -PathType Leaf)) {
                $acked = $true
                break
            }
            Start-Sleep -Milliseconds 200
        }

        if (-not $acked) {
            try { [System.IO.File]::WriteAllText($slotCancelPath, "ack timeout`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
            [void](Remove-AgyFileSafe $slotInboxPath)
            [void](Remove-AgyFileSafe $slotPromptPath)
            [void](Set-AgySubSlotCooldown $bridgeRoot $sid $cooldownSec "ack timeout (${ackTimeoutSec}s)")
            [void]$failedSlots.Add($sid)
            Log "[부계정 무응답] $sid 가 ${ackTimeoutSec}초 내 작업을 인수하지 않아 다음 후보로 넘어갑니다."
            continue
        }

        # 2) 결과 대기 (.cancel 전파, conversation_id 동기화, 슬롯 워처 생존 확인)
        $slotRes = $null
        $hardWaitDeadline = (Get-Date).AddSeconds($AgyHardTimeoutSeconds + 120)
        $lastCancelRelayed = $false
        $lastSyncedSig = ""
        while ((Get-Date) -lt $hardWaitDeadline) {
            if (-not $lastCancelRelayed -and (Test-Path -LiteralPath $primaryCancel -PathType Leaf)) {
                try {
                    Copy-Item -LiteralPath $primaryCancel -Destination $slotCancelPath -Force -ErrorAction SilentlyContinue
                    $lastCancelRelayed = $true
                } catch {}
            }
            if (Test-Path -LiteralPath $slotResPath -PathType Leaf) {
                $slotRes = Read-BridgeJson $slotResPath
                if ($null -ne $slotRes) { break }
            }
            $sClaim = Read-RunningClaim $slotClaimPath
            if ($null -ne $sClaim) {
                $syncFields = [ordered]@{}
                if ($sClaim.PSObject.Properties['conversation_id'] -and $sClaim.conversation_id) { $syncFields['conversation_id'] = [string]$sClaim.conversation_id }
                if ($sClaim.PSObject.Properties['model'] -and $sClaim.model) { $syncFields['model'] = [string]$sClaim.model }
                if ($sClaim.PSObject.Properties['started_at'] -and $sClaim.started_at) { $syncFields['started_at'] = [string]$sClaim.started_at }
                if ($sClaim.PSObject.Properties['tried'] -and $null -ne $sClaim.tried) { $syncFields['tried'] = $sClaim.tried }
                if ($sClaim.PSObject.Properties['ask_count'] -and $null -ne $sClaim.ask_count) { $syncFields['ask_count'] = [int]$sClaim.ask_count }
                if ($sClaim.PSObject.Properties['last_activity_utc'] -and $sClaim.last_activity_utc) { $syncFields['last_activity_utc'] = [string]$sClaim.last_activity_utc }
                $syncFields['probe_state'] = if ($sClaim.PSObject.Properties['probe_state'] -and $sClaim.probe_state) { [string]$sClaim.probe_state } else { "" }
                $syncFields['probe_since'] = if ($sClaim.PSObject.Properties['probe_since'] -and $sClaim.probe_since) { [string]$sClaim.probe_since } else { "" }
                $curSig = (@(
                    [string]$syncFields['conversation_id'],
                    [string]$syncFields['model'],
                    [string]$syncFields['started_at'],
                    [string]$syncFields['tried'],
                    [string]$syncFields['ask_count'],
                    [string]$syncFields['last_activity_utc'],
                    [string]$syncFields['probe_state'],
                    [string]$syncFields['probe_since']
                ) -join '|')
                if ($curSig -ne $lastSyncedSig) {
                    $lastSyncedSig = $curSig
                    Write-RunningClaim $TaskId $syncFields
                }
            } else {
                # claim 도 없고 inbox 도 없고 result 도 없으면 잠깐 확인 후 비정상 종료로 간주
                Start-Sleep -Milliseconds 300
                if (Test-Path -LiteralPath $slotResPath -PathType Leaf) {
                    $slotRes = Read-BridgeJson $slotResPath
                    if ($null -ne $slotRes) { break }
                }
                if (-not (Test-Path -LiteralPath $slotInboxPath -PathType Leaf) -and -not (Test-Path -LiteralPath $slotClaimPath -PathType Leaf)) {
                    $hbUtc = Get-AgySubSlotHeartbeatUtc $slotLay
                    if ($null -eq $hbUtc -or (([datetime]::UtcNow - $hbUtc).TotalSeconds -gt 90)) {
                        break
                    }
                }
            }
            Start-Sleep -Milliseconds 250
        }

        [void](Remove-AgyFileSafe $slotPromptPath)

        if ($null -eq $slotRes) {
            [void](Remove-AgyFileSafe $slotInboxPath)
            [void](Set-AgySubSlotCooldown $bridgeRoot $sid $cooldownSec "bridge result missing or worker died")
            [void]$failedSlots.Add($sid)
            Log "[부계정 오류] $sid 결과 없이 중단되어 다음 후보로 넘어갑니다."
            continue
        }

        $resStatus = ([string]$slotRes.status).ToUpperInvariant()
        $resFallback = [bool]$slotRes.fallback_eligible
        if ($resStatus -eq "ERROR" -and $resFallback) {
            [void](Set-AgySubSlotCooldown $bridgeRoot $sid $cooldownSec ([string]$slotRes.error_message))
            [void]$failedSlots.Add($sid)
            Log "[부계정 한도/인증 오류] $sid : $($slotRes.error_message) -> 다음 후보로 전환"
            continue
        }

        return @{
            Handled           = $true
            FallbackToPrimary = $false
            Account           = $sid
            FallbackFrom      = ($failedSlots -join ',')
            AccountNote       = ""
            SubSlotsLabel     = ($failedSlots -join ', ')
            Result            = $slotRes
            TranscriptPath    = $slotTransPath
            SlotLayout        = $slotLay
        }
    }

    # 여기까지 왔으면 모든 가용 부계정이 소진/오프라인/대기포화
    $finalBusy = Get-AgySubSlotsBusyState $subCfg $bridgeRoot
    $fbList = New-Object System.Collections.ArrayList
    foreach ($fid in @($failedSlots)) {
        $fids = ([string]$fid).Trim()
        if ($fids -and ($fbList -notcontains $fids)) { [void]$fbList.Add($fids) }
    }
    foreach ($fid in @($finalBusy.FailedOrExhaustedIds)) {
        $fids = ([string]$fid).Trim()
        if ($fids -and ($fbList -notcontains $fids)) { [void]$fbList.Add($fids) }
    }
    $fbSorted = @($fbList | Sort-Object)
    $allFbStr = ($fbSorted -join ',')
    $finalAccountNote = ""
    if ($fbSorted.Count -eq 0 -and $finalBusy.HasBusyHealthySlot) {
        $allFbStr = ""
        $finalAccountNote = "sub_busy_overflow"
    }
    Write-RunningClaim $TaskId @{
        account           = "primary"
        bridge_slot       = ""
        bridge_transcript = ""
        fallback_from     = $allFbStr
    }
    return @{
        Handled           = $false
        FallbackToPrimary = [bool]$subCfg.FallbackToPrimary
        Account           = "primary"
        FallbackFrom      = $allFbStr
        AccountNote       = $finalAccountNote
        SubSlotsLabel     = ($fbSorted -join ', ')
        Result            = $null
        TranscriptPath    = ""
        SlotLayout        = $null
    }
}

function Invoke-InboxTaskBody([System.IO.FileInfo]$file) {
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    $outFile   = Join-Path $OutboxDir  "$baseName.response.md"

    $errFile   = Join-Path $OutboxDir  "$baseName.error.log"

    $doneFile  = Join-Path $ProcessedDir $file.Name



    Log "처리 중: $($file.Name)"



    $rawText = Get-Content -Raw -Path $file.FullName -Encoding UTF8

    # 지시문 맨 앞의 "[언어 규칙 — 가장 먼저 지킨다] 생각·도구 설명을 한국어로…" 문단은 쓰지 않기로 했다(사용자 결정).
    # 이미 예전 지침을 읽은 Claude 세션이 계속 붙여 보내도 agy 에 넘기지 않고, 지시파일에서도 뺀다(뷰어에도 안 보인다).
    $ruleLine = [regex]::new('(?m)^[ \t]*\[언어 규칙[^\]\r\n]*\][^\r\n]*(\r?\n|$)')
    if ($ruleLine.IsMatch($rawText)) {
        $rawText = $ruleLine.Replace($rawText, '')
        try {
            [System.IO.File]::WriteAllText($file.FullName, $rawText, (New-Object System.Text.UTF8Encoding($false)))
            Log "  -> 지시문 맨 앞의 언어 규칙 문단을 뺐습니다(사용하지 않는 규칙)"
        } catch {}
    }



    # 지시파일 맨 위에 "@키: 값" 줄이 있으면(순서 무관, 여러 줄 가능) 읽어들이고,

    # 그 형식이 아닌 첫 줄부터가 실제 프롬프트 본문입니다. 지원하는 키:

    #   @cwd:     agy의 워크스페이스에 추가할 폴더 (--add-dir). 여러 줄 가능(폴더마다 --add-dir 한 번씩)

    #   @session: 대화를 이어갈 세션 이름 (3.8절 - docs\설계.md). 같은 이름으로 다시

    #             보내면 이전 대화 맥락을 그대로 이어받습니다. 이 줄이 없으면 매번

    #             빈 상태로 새로 시작하는 기존 동작 그대로입니다.

    # (@model: <ID> 는 이번 호출에 쓸 모델 하나를 지정합니다 - ConvertFrom-TaskDirectives 참고)
    $directives     = ConvertFrom-TaskDirectives $rawText
    $targetCwds     = @($directives.Cwd)
    $sessionName    = $directives.Session
    $requestedModel = $directives.Model
    $promptText     = $directives.Prompt



    # 세션이 있으면 이전에 저장해둔 conversation_id와 model을 불러옵니다. @cwd를 이번엔

    # 안 줬으면 세션에 저장된(sticky) 폴더를 이어서 씁니다 - 매번 반복 안 해도 됩니다.

    $conversationId  = ""
    $knownModel      = ""
    $existingSession = $null

    if ($sessionName) {

        $existingSession = Read-Session $sessionName

        if ($existingSession) {

            if ($existingSession.conversation_id) { $conversationId = [string]$existingSession.conversation_id }

            # 이번 호출에 @cwd 가 하나라도 있으면 이번 목록만, 없으면 세션의 목록(예전 파일의 문자열 하나도 읽는다)
            $targetCwds = @(Resolve-TaskCwds $targetCwds $existingSession.cwd)

            if ($existingSession.model) { $knownModel = [string]$existingSession.model }

        }

    }



    # @cmd / @mode 검사: 지원하지 않는 명령이나 대화형 TUI 전용 명령은 agy 를 부르지 않고 바로 실패 처리합니다.
    $cmdCheck = if ($directives.Cmd -and (Get-Command Resolve-AgySlashCommand -ErrorAction SilentlyContinue)) { Resolve-AgySlashCommand $directives.Cmd } else { $null }
    if ($cmdCheck -and -not $cmdCheck.Valid) {
        Set-Content -Path $outFile -Value $cmdCheck.Error -Encoding UTF8
        Set-Content -Path $errFile -Value $cmdCheck.Error -Encoding UTF8
        Log "실패: $($cmdCheck.Error)"
        Write-UsageRow $baseName $null $null $requestedModel $null $null $null $null $null "ERROR" $sessionName $conversationId
        Complete-TaskQaRecord $baseName $file.FullName $doneFile
        return
    }
    $modeCheck = if ($directives.Mode -and (Get-Command Resolve-AgyExecutionMode -ErrorAction SilentlyContinue)) { Resolve-AgyExecutionMode $directives.Mode } else { $null }
    if ($modeCheck -and -not $modeCheck.Valid) {
        Set-Content -Path $outFile -Value $modeCheck.Error -Encoding UTF8
        Set-Content -Path $errFile -Value $modeCheck.Error -Encoding UTF8
        Log "실패: $($modeCheck.Error)"
        Write-UsageRow $baseName $null $null $requestedModel $null $null $null $null $null "ERROR" $sessionName $conversationId
        Complete-TaskQaRecord $baseName $file.FullName $doneFile
        return
    }
    $leadCmd = if (Get-Command Split-AgyLeadingSlashCommand -ErrorAction SilentlyContinue) { Split-AgyLeadingSlashCommand $promptText } else { @{ Name = ""; Command = ""; Body = $promptText } }
    $effectiveSlashCmd = ""
    if ($cmdCheck -and $cmdCheck.Valid) {
        $effectiveSlashCmd = [string]$cmdCheck.Command
        if ($leadCmd.Command -and ($leadCmd.Command -ieq $effectiveSlashCmd)) { $promptText = [string]$leadCmd.Body }
    } elseif ($leadCmd.Command) {
        $effectiveSlashCmd = [string]$leadCmd.Command
        $promptText = [string]$leadCmd.Body
    }
    $effectiveMode = if ($modeCheck -and $modeCheck.Valid) { [string]$modeCheck.Mode } else { "" }
    # agy --mode plan 은 내부적으로 /plan 을 자동으로 붙이므로 중복을 막는다.
    if ($effectiveMode -eq "plan" -and $effectiveSlashCmd -ieq "/plan") { $effectiveSlashCmd = "" }
    if ($effectiveSlashCmd) { Log "  -> 실행 명령(@cmd): $effectiveSlashCmd" }
    if ($effectiveMode) { Log "  -> 실행 모드(@mode): $effectiveMode" }

    # @model 검사: 쓸 수 없는 모델이면 agy 를 부르지 않고 바로 실패 처리합니다(@cwd 오류와 같은 방식).
    $modelCheck = Resolve-RequestedModel $requestedModel $conversationId $knownModel $sessionName ([bool]$directives.Upgrade)
    if ($modelCheck.Error) {
        Set-Content -Path $outFile -Value $modelCheck.Error -Encoding UTF8
        Set-Content -Path $errFile -Value $modelCheck.Error -Encoding UTF8
        Log "실패: $($modelCheck.Error)"
        Write-UsageRow $baseName $null $null $requestedModel $null $null $null $null $null "ERROR" $sessionName $conversationId
        Complete-TaskQaRecord $baseName $file.FullName $doneFile
        return
    }
    $requestedModel = $modelCheck.Model
    $modelChain = @($modelCheck.Chain)
    $modelTier = [string]$modelCheck.Tier
    if ($modelCheck.Kind -eq "tier") { Log "  -> 모델 단계(@model): $modelTier -> $($modelChain -join ' -> ') (한도 · 과부하 오류면 다음 모델)" }
    elseif ($requestedModel) { Log "  -> 지정 모델(@model): $requestedModel (다른 모델로 자동 전환하지 않음)" }

    # 모델 승격(@upgrade): 이어가던 대화(시작 모델 $knownModel)를 버리고 새 대화로 시작한다. 이전 질문·답 글(최근 2쌍)을 지시문 위에 붙인다.
    # 새 대화가 성공하면 세션의 대화 ID·모델이 새 값으로 바뀐다. 실패하면 세션은 이전 대화 그대로 남는다(Write-Session 은 성공 때만 부른다).
    if ($modelCheck.Upgrade) {
        $oldConversation = $conversationId
        $history = @()
        try { $history = @(Get-AgySessionHistory $AgyDbPath $sessionName 2) } catch { $history = @() }
        $promptText = New-AgyUpgradeContext $history $knownModel $requestedModel $promptText
        $conversationId = ""
        $knownModel = ""
        Log "  -> 모델 승격(@upgrade): 세션 '$sessionName' 의 대화(ID: $oldConversation)를 이어가지 않고 $requestedModel 로 새 대화를 시작합니다(이전 질문·답 $($history.Count)쌍을 지시문에 붙임)"
    }

    # 모델을 지정하지 않았고 새 대화(@session 없음)면 요청 내용으로 단계를 자동 선택한다(agy-autotier.ps1).
    # 자동 선택은 quick(읽기만 하는 짧은 일) / build(파일을 바꾸는 일)만 고른다. build-hard · feature · feature-carbon · think · think-carbon · deep 은 Claude 가 @model 로 적는다.
    # 이어가는 세션은 시작할 때의 모델을 유지한다.
    if (-not $requestedModel -and -not $sessionName -and (Test-AgyAutoTierEnabled)) {
        $autoTier = Get-AgyAutoTier $promptText (@($targetCwds).Count -gt 0)
        $modelTier = [string]$autoTier.Tier
        $cfgA = Get-WatcherModelConfig
        $availA = @(Get-WatcherAvailableModels)
        $modelChain = @(Get-AgyTierChain $cfgA $modelTier $availA)
        Log "  -> 모델 자동 선택: $modelTier ($($autoTier.Reason)) -> $($modelChain -join ' -> ')"
    } elseif (-not $requestedModel -and -not $conversationId) {
        $cfgD = Get-WatcherModelConfig
        $availD = @(Get-WatcherAvailableModels)
        $modelTier = if ($cfgD.Auto -and $cfgD.Auto.write) { [string]$cfgD.Auto.write } else { "build" }
        $modelChain = @(Get-AgyTierChain $cfgD $modelTier $availD)
    } elseif (-not $requestedModel -and $conversationId -and $knownModel) {
        $modelChain = @($knownModel)
    }

    $callerMetaObj = $null
    try {
        $cmPath = Join-Path (Join-Path $RuntimeDir "claude-meta") "$baseName.json"
        if (Test-Path -LiteralPath $cmPath -PathType Leaf) {
            $callerMetaObj = [System.IO.File]::ReadAllText($cmPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
        }
    } catch { $callerMetaObj = $null }
    if (-not $conversationId -and $modelCheck.Kind -ne "model" -and $null -ne $callerMetaObj -and (Get-Command Resolve-AgyCallerSameLevelSpec -ErrorAction SilentlyContinue)) {
        $matchedSpec = Resolve-AgyCallerSameLevelSpec (Get-WatcherModelConfig) @(Get-WatcherAvailableModels) $callerMetaObj ([string]$directives.Model) $modelTier ([string]$modelCheck.Kind)
        if ($matchedSpec) {
            $prevTier = $modelTier
            $modelTier = [string]$matchedSpec.Tier
            $modelChain = @($matchedSpec.Chain)
            $requestedModel = [string]$matchedSpec.Model
            Log "  -> 호출 모델 동급 맞춤($($matchedSpec.CallerDesc)): $(if ($prevTier) { $prevTier } else { 'auto' }) -> $modelTier ($($modelChain -join ' -> '))"
        }
    }

    $missingCwds = @(Get-MissingCwds $targetCwds)
    if ($missingCwds.Count -gt 0) {
        $cwdErrMsg = "지정한 @cwd 경로를 찾을 수 없습니다: $($missingCwds -join ', ')"
        Log "실패: @cwd 경로 없음 ($($missingCwds -join ', '))"
        # agy를 호출하지 않고 여기서 바로 실패 처리하는 경우도, 나중에 "이 작업이
        # 있었는지" 조회할 수 있도록 다른 실패와 똑같이 위임 기록 DB 에 남깁니다
        # (여기서 기록하지 않으면 outbox에는 파일이 남는데 기록에서는 통째로 빠집니다).
        Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId
        Set-Content -Path $errFile -Value $cwdErrMsg -Encoding UTF8
        Set-Content -Path $outFile -Value $cwdErrMsg -Encoding UTF8

        Complete-TaskQaRecord $baseName $file.FullName $doneFile
        return
    }



    foreach ($cwdPath in $targetCwds) {

        Log "  -> 대상 폴더(--add-dir): $cwdPath"

    }
    if (@($targetCwds).Count -gt 0) {
        Log "  작업 폴더(실행 위치): $(@($targetCwds)[0])"
    }

    if ($sessionName) {

        Log "  -> 세션: $sessionName$(if ($conversationId) { " (이어감, ID: $conversationId)" } else { " (새로 시작)" })"

    }



    # 폴더(@cwd)가 git 저장소면 agy 를 부르기 전의 HEAD·브랜치·stash 를 기록하고(커밋 안 한 변경은 스냅샷 참조로 보관), 끝난 뒤 비교해 경고한다(agy-gitguard.ps1).
    $gitGuard = $null
    $guardConcurrent = 0
    try {
        $gitGuard = New-AgyGitGuardState $targetCwds $baseName
        $guardConcurrent = Get-OverlappingRunningCount $baseName $targetCwds
        foreach ($gr in @($gitGuard.Repos)) {
            Log "  -> git 상태 기록: $($gr.Root) (브랜치 $($gr.Branch), HEAD $(if ($gr.Head) { $gr.Head.Substring(0, [math]::Min(8, $gr.Head.Length)) } else { '없음' })$(if ($gr.SnapRef) { ", 미커밋 변경 스냅샷 $($gr.SnapRef)" }))"
        }
    } catch { $gitGuard = $null }

    $recModel    = $null
    $recAttempts = $null
    $recTried    = ""
    $recInTok    = $null
    $recOutTok   = $null
    $recThinkTok = $null
    $recTotTok   = $null
    $recElapsed  = $null
    $recStatus   = "ERROR"
    $effectiveSessionId = $conversationId
    $agyStderr = $null    # agy 를 부르지 않은 실패에는 error.log 를 남기지 않는다(예전과 같다)
    $taskAccount = "primary"
    $taskFallbackFrom = ""
    $taskAccountNote = ""
    $accountFallbackBanner = ""
    $subTranscriptPath = ""
    $subExplicitModels = $null
    $subExplicitCtx = $null

    try {
        # 프롬프트 길이와 무관하게 항상 임시 프롬프트 파일(@$tempPromptFile)을 사용하여
        # 명령줄 따옴표/이스케이프 깨짐을 방지하고 병렬 실행 시 고유한 대화 식별 Marker를 보장합니다.
        $promptsDir = $Layout.PromptsDir
        if (-not (Test-Path -LiteralPath $promptsDir)) {
            New-Item -ItemType Directory -Force -Path $promptsDir | Out-Null
        }
        # 폴더(@cwd)를 여는 작업에는 표준 규칙을 붙인다(@raw: true 면 안 붙임). 위임 기록에는 원본 지시문이 남는다(여기서는 agy 에 넘길 프롬프트만 바꾼다).
        $withRules = Add-AgyStandardRules $promptText (@($targetCwds).Count -gt 0) ([bool]$directives.Raw) $effectiveSlashCmd
        $promptForAgy = [string]$withRules.Text
        if (@($withRules.Added).Count -gt 0) { Log "  -> 표준 규칙 자동 추가: $(@($withRules.Added) -join ', ')" }
        $tempPromptFile = Join-Path $promptsDir "prompt_$baseName.txt"
        [System.IO.File]::WriteAllText($tempPromptFile, $promptForAgy, (New-Object System.Text.UTF8Encoding($false)))
        $safePrompt = $promptForAgy -replace '"', '\"'

        $bridgeCall = Invoke-BridgeSubAccountPool -TaskId $baseName -SessionName $sessionName -ConversationId $conversationId -KnownModel $knownModel -PromptForAgy $promptForAgy -RawPromptPreview $promptText -Cwds $targetCwds -ModelChain $modelChain -ModelTier $modelTier -SlashCmd $effectiveSlashCmd -ExecutionMode $effectiveMode -ExistingSession $existingSession -Upgrade ([bool]$modelCheck.Upgrade)
        if ($bridgeCall.Handled) {
            $sr = $bridgeCall.Result
            $taskAccount = [string]$bridgeCall.Account
            $taskFallbackFrom = [string]$bridgeCall.FallbackFrom
            $subTranscriptPath = [string]$bridgeCall.TranscriptPath
            $subExplicitModels = $sr.models
            $subExplicitCtx = $sr.context_tokens
            if ($taskFallbackFrom) {
                $taskAccountNote = "$taskFallbackFrom 한도 소진/미응답으로 $taskAccount 에서 실행됨"
                Log "[부계정 대체 경고] $taskAccountNote"
            }

            $allowedOutboxDir = if ($bridgeCall.SlotLayout -and $bridgeCall.SlotLayout.OutboxDir) { [string]$bridgeCall.SlotLayout.OutboxDir } else { "" }
            $brRespText = ""
            $unsafeRespPath = $false
            if ($sr.response_file) {
                $rf = [string]$sr.response_file
                if ($allowedOutboxDir -and (Test-AgySubPathUnderRoot $rf $allowedOutboxDir)) {
                    if (Test-Path -LiteralPath $rf -PathType Leaf) {
                        $brRespText = [System.IO.File]::ReadAllText($rf, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                    }
                } else {
                    $unsafeRespPath = $true
                    Log "보안 경고: 부계정 결과 response_file 이 OutboxDir 밖을 가리켜 거부했습니다: $rf"
                }
            }
            $brRawJson = ""
            if ($sr.raw_file) {
                $rawf = [string]$sr.raw_file
                if ($allowedOutboxDir -and (Test-AgySubPathUnderRoot $rawf $allowedOutboxDir) -and (Test-Path -LiteralPath $rawf -PathType Leaf)) {
                    $brRawJson = [System.IO.File]::ReadAllText($rawf, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                } elseif ($rawf) {
                    Log "보안 경고: 부계정 결과 raw_file 이 OutboxDir 밖을 가리켜 무시합니다: $rawf"
                }
            }
            $brErrText = ""
            if ($sr.error_log_file) {
                $ef = [string]$sr.error_log_file
                if ($allowedOutboxDir -and (Test-AgySubPathUnderRoot $ef $allowedOutboxDir) -and (Test-Path -LiteralPath $ef -PathType Leaf)) {
                    $brErrText = [System.IO.File]::ReadAllText($ef, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                } elseif ($ef) {
                    Log "보안 경고: 부계정 결과 error_log_file 이 OutboxDir 밖을 가리켜 무시합니다: $ef"
                }
            }

            $srStatus = ([string]$sr.status).ToUpperInvariant()
            if ($unsafeRespPath) { $srStatus = "ERROR" }
            $triedArr = if ($sr.tried_models) { @([string]$sr.tried_models -split '\s*->\s*' | Where-Object { $_ }) } else { @() }
            $agyResult = [ordered]@{
                Success           = ($srStatus -eq "OK")
                Response          = $brRespText
                RawJson           = $brRawJson
                ModelUsed         = if ($sr.model_used) { [string]$sr.model_used } else { "" }
                Attempts          = if ($null -ne $sr.attempts) { [int]$sr.attempts } else { $triedArr.Count }
                TriedModels       = $triedArr
                InTok             = $sr.in_tokens
                OutTok            = $sr.out_tokens
                ThinkTok          = $sr.thinking_tokens
                TotTok            = $sr.total_tokens
                AgyDuration       = $sr.agy_duration
                ElapsedSec        = if ($null -ne $sr.elapsed_sec) { [double]$sr.elapsed_sec } elseif ($null -ne $sr.agy_duration) { [double]$sr.agy_duration } else { 0 }
                ErrorMessage      = [string]$sr.error_message
                ConversationId    = [string]$sr.conversation_id
                SessionRenewed    = $false
                StdErr            = $brErrText
                Tier              = [string]$modelTier
                AskCount          = 0
                Blocked           = ($srStatus -eq "BLOCKED")
                TimedOutReason    = if ($srStatus -eq "CANCELLED") { "cancel" } else { [string]$sr.timed_out_reason }
                CancelledWorkText = [string]$sr.cancelled_work_text
            }
        } elseif ($bridgeCall.FallbackFrom -and -not $bridgeCall.FallbackToPrimary) {
            $taskAccount = "primary"
            $taskFallbackFrom = [string]$bridgeCall.FallbackFrom
            $taskAccountNote = "부계정($taskFallbackFrom) 한도 소진/미응답 (fallback_to_primary=false)"
            $agyResult = [ordered]@{
                Success = $false; Response = $null; RawJson = ""; ModelUsed = $null; Attempts = 0; TriedModels = @();
                InTok = $null; OutTok = $null; ThinkTok = $null; TotTok = $null; AgyDuration = $null; ElapsedSec = 0;
                ErrorMessage = "가용 부계정($taskFallbackFrom)이 모두 한도 소진/오프라인이며 fallback_to_primary=false 로 주 계정 폴백이 비활성화되어 있습니다.";
                ConversationId = $conversationId; SessionRenewed = $false; StdErr = ""; Tier = $modelTier; AskCount = 0; Blocked = $false; TimedOutReason = ""
            }
        } else {
            if ($bridgeCall.FallbackFrom) {
                $taskAccount = "primary"
                $taskFallbackFrom = [string]$bridgeCall.FallbackFrom
                $taskAccountNote = "부계정($taskFallbackFrom) 한도 소진/미응답으로 주 계정 폴백"
                Log "[계정 폴백 경고] $taskAccountNote"
                if ($existingSession -and $conversationId -and $existingSession.PSObject.Properties['account'] -and ([string]$existingSession.account -notin @('', 'primary'))) {
                    try {
                        $histPri = @(Get-AgySessionHistory $AgyDbPath $sessionName 2)
                        if ($histPri.Count -gt 0) {
                            $upPriModel = if ($modelChain.Count -gt 0) { [string]$modelChain[0] } elseif ($knownModel) { [string]$knownModel } else { "gemini-4-hydrogen-medium" }
                            $upgradedPri = New-AgyUpgradeContext $histPri $knownModel $upPriModel $promptForAgy
                            [System.IO.File]::WriteAllText($tempPromptFile, $upgradedPri, (New-Object System.Text.UTF8Encoding($false)))
                            $safePrompt = $upgradedPri -replace '"', '\"'
                        }
                    } catch {}
                    $conversationId = ""
                    $knownModel = ""
                }
            } elseif ($bridgeCall.AccountNote) {
                $taskAccountNote = [string]$bridgeCall.AccountNote
            }
            $agyResult = $null
            if (-not $conversationId -and $RuntimeDir) {
                $effectiveCheckChain = if (@($modelChain).Count -gt 0) { @($modelChain) } else { @(Get-WatcherDefaultChain) }
                $allGeminiChain = ($effectiveCheckChain.Count -gt 0) -and (@($effectiveCheckChain | Where-Object { (Get-AgyQuotaGroup ([string]$_)) -ne "gemini" }).Count -eq 0)
                $exMarkerPath = Join-Path $RuntimeDir "agy-quota-exhausted.json"
                if ($allGeminiChain -and (Test-Path -LiteralPath $exMarkerPath -PathType Leaf)) {
                    $exObj = $null
                    try {
                        $exRaw = [System.IO.File]::ReadAllText($exMarkerPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                        if ($exRaw) { $exObj = $exRaw | ConvertFrom-Json -ErrorAction Stop }
                    } catch { $exObj = $null }
                    $untilUtc = $null
                    if ($exObj -and $exObj.until) {
                        $parsedDto = [DateTimeOffset]::MinValue
                        if ([DateTimeOffset]::TryParse([string]$exObj.until, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$parsedDto)) {
                            $untilUtc = $parsedDto.UtcDateTime
                        }
                    }
                    $nowUtc = [datetime]::UtcNow
                    if ($null -eq $untilUtc -or $untilUtc -le $nowUtc) {
                        [void](Remove-AgyFileSafe $exMarkerPath)
                    } elseif (Get-Command Get-AgyQuotaSnapshot -ErrorAction SilentlyContinue) {
                        $snap = $null
                        try { $snap = Get-AgyQuotaSnapshot -CacheFile (Join-Path $RuntimeDir "agy-quota.json") -MaxAgeSec 60 } catch { $snap = $null }
                        if ($null -ne $snap) {
                            $has5h = ($snap -is [System.Collections.IDictionary] -and $snap.Contains('gemini_5h')) -or ($snap.PSObject.Properties['gemini_5h'])
                            $hasWk = ($snap -is [System.Collections.IDictionary] -and $snap.Contains('gemini_weekly')) -or ($snap.PSObject.Properties['gemini_weekly'])
                            $pct5h = if ($has5h -and $null -ne $snap.gemini_5h -and $null -ne $snap.gemini_5h.pct) { [int]$snap.gemini_5h.pct } else { $null }
                            $pctWk = if ($hasWk -and $null -ne $snap.gemini_weekly -and $null -ne $snap.gemini_weekly.pct) { [int]$snap.gemini_weekly.pct } else { $null }
                            if (($null -ne $pct5h -and $pct5h -le 0) -or ($null -ne $pctWk -and $pctWk -le 0)) {
                                $untilLocalStr = $untilUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
                                $fastFailMsg = "Gemini 한도 소진(재설정 $untilLocalStr). agy 를 부르지 않고 바로 실패 처리했습니다. 재설정 뒤 다시 보내거나 직접 처리하세요."
                                Log "  빠른 실패: $fastFailMsg"
                                $agyResult = [ordered]@{
                                    Success        = $false
                                    Response       = $null
                                    RawJson        = ""
                                    ModelUsed      = $null
                                    Attempts       = 0
                                    TriedModels    = @()
                                    InTok          = $null
                                    OutTok         = $null
                                    ThinkTok       = $null
                                    TotTok         = $null
                                    AgyDuration    = $null
                                    ElapsedSec     = 0
                                    ErrorMessage   = $fastFailMsg
                                    ConversationId = ""
                                    SessionRenewed = $false
                                    StdErr         = ""
                                    Tier           = $modelTier
                                    AskCount       = 0
                                    Blocked        = $false
                                    TimedOutReason = ""
                                }
                            } elseif ($null -ne $pct5h -and $pct5h -gt 0 -and $null -ne $pctWk -and $pctWk -gt 0) {
                                [void](Remove-AgyFileSafe $exMarkerPath)
                                Log "  한도 회복 확인(5h=${pct5h}%, weekly=${pctWk}%) -> 한도 소진 표시 파일을 지우고 진행합니다."
                            }
                        }
                    }
                }
            }
            if ($null -eq $agyResult) {
                $agyResult = Invoke-AgyWithFallback -safePrompt $safePrompt -targetCwd $targetCwds -skipPerm:$SkipPermissions -errFile $errFile -conversationId $conversationId -knownModel $knownModel -taskId $baseName -promptFile $tempPromptFile -modelChain $modelChain -tier $modelTier -slashCommand $effectiveSlashCmd -executionMode $effectiveMode
            }
            if ($bridgeCall.FallbackFrom) {
                $fbModel = if ($agyResult.ModelUsed) { [string]$agyResult.ModelUsed } elseif ($modelChain.Count -gt 0) { [string]$modelChain[0] } else { "default" }
                $accountFallbackBanner = "> [경고: 부계정($($bridgeCall.SubSlotsLabel)) 한도 소진/미응답으로 주 계정($fbModel)으로 폴백 실행했습니다. 다음 턴 전에 부계정을 다른 Google 계정으로 로그인하면 다음 위임부터 다시 부계정으로 실행합니다.]`r`n`r`n"
            }
        }

        $agyStderr = [string]$agyResult.StdErr

        # agy 가 git 상태를 바꿨으면 응답 맨 위에 붙일 경고(없으면 빈 문자열). 자동으로 되돌리지는 않는다.
        $guardBanner = ""
        try {
            $guardBanner = Get-AgyGitGuardBanner $gitGuard ([math]::Max($guardConcurrent, (Get-OverlappingRunningCount $baseName $targetCwds)))
            if ($guardBanner) { Log "경고: agy 가 git 상태를 바꾼 것으로 보여 응답 맨 위에 경고를 붙였습니다" }
        } catch { $guardBanner = "" }

        if ($agyResult.RawJson) {
            Set-Content -Path (Join-Path $OutboxDir "$baseName.raw.json") -Value $agyResult.RawJson -Encoding UTF8
        }

        $triedStr = $agyResult.TriedModels -join ' -> '
        $effectiveSessionId = if ($agyResult.ConversationId) { $agyResult.ConversationId } else { $conversationId }
        $recAttempts = $agyResult.Attempts
        $recTried    = $triedStr

        $alreadyCancelled = (Test-Path -LiteralPath (Join-Path $RunningDir "$baseName.cancel"))
        if (-not $alreadyCancelled -and (Test-Path -LiteralPath $outFile)) {
            $firstOutLine = Get-Content -LiteralPath $outFile -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($firstOutLine -like "취소됨(CANCELLED):*") { $alreadyCancelled = $true }
        }
        if ($alreadyCancelled -and $agyResult.TimedOutReason -ne 'cancel') {
            Log "이미 취소된 작업이라 결과를 덮어쓰지 않습니다: $baseName"
            if (Test-Path -LiteralPath $file.FullName) {
                try { Move-Item -LiteralPath $file.FullName -Destination $doneFile -Force } catch {}
            }
            return
        }

        if ($agyResult.TimedOutReason -eq 'cancel') {
            $cancelBody = if ([string]$agyResult.Response) { [string]$agyResult.Response } elseif ($agyResult.ErrorMessage) { [string]$agyResult.ErrorMessage } else { "취소됨(CANCELLED): 사용자 요청으로 취소되었습니다." }
            $recModel = $agyResult.ModelUsed
            $recElapsed = $agyResult.ElapsedSec
            Write-UsageRow $baseName $recModel $recAttempts $recTried $null $null $null $null $recElapsed "CANCELLED" $sessionName $effectiveSessionId $null $null $null $null "" $taskAccount $taskFallbackFrom $taskAccountNote
            Set-Content -Path $outFile -Value ($accountFallbackBanner + $guardBanner + $cancelBody) -Encoding UTF8
            Log "취소됨 -> $outFile"
        } elseif ($agyResult.Success) {
            $cleanResponse = [string]$agyResult.Response
            if (Get-Command Remove-AgyGoalMarkers -ErrorAction SilentlyContinue) { $cleanResponse = Remove-AgyGoalMarkers $cleanResponse }
            if ($effectiveSessionId -and (Get-Command Get-AgyPlannerTexts -ErrorAction SilentlyContinue) -and (Get-Command Remove-AgyInterimMessages -ErrorAction SilentlyContinue)) {
                try {
                    $tp = if ($subTranscriptPath -and (Test-Path -LiteralPath $subTranscriptPath -PathType Leaf)) { $subTranscriptPath } else { Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$effectiveSessionId) }
                    $callSince = (Get-Date).AddSeconds(-([double]$agyResult.ElapsedSec + 5))
                    $plannerTexts = @(Get-AgyPlannerTexts $tp $callSince)
                    if ($plannerTexts.Count -ge 2) {
                        $strippedResponse = Remove-AgyInterimMessages $cleanResponse $plannerTexts
                        if ($strippedResponse -ne $cleanResponse) {
                            Log ("  -> 답변 앞의 중간 안내를 뺐습니다({0}자 -> {1}자)" -f $cleanResponse.Length, $strippedResponse.Length)
                            $cleanResponse = $strippedResponse
                        }
                    }
                } catch {}
            }

            # 이어가는 세션이나 멈춤 확인 후 이어서 물은 실행에서 agy 가 보고하는 duration_seconds 는 누적일 수 있으므로 워처 측정 시간을 쓴다.
            $useAgyDuration = [bool]$agyResult.AgyDuration -and -not $conversationId -and ([int]$agyResult.AskCount -le 0)
            $elapsedForLog = if ($useAgyDuration) { [math]::Round([double]$agyResult.AgyDuration, 1) } else { $agyResult.ElapsedSec }
            $timeSrc = if ($useAgyDuration) { "agy 자체 보고" } elseif ($conversationId) { "워처 측정(이어가는 세션이라 agy 보고는 누적값)" } else { "워처 측정(폴백 시도 포함 총 시간)" }
            $agyIn = $agyResult.InTok
            $agyOut = $agyResult.OutTok
            $agyThink = $agyResult.ThinkTok
            $agyTot = $agyResult.TotTok

            $cumInTok = $agyIn
            $cumOutTok = $agyOut
            $cumThinkTok = $agyThink
            $cumTotTok = $agyTot

            $recInTok = $agyIn
            $recOutTok = $agyOut
            $recThinkTok = $agyThink
            $recTotTok = $agyTot
            $usageBasis = "own"

            $isContinued = [bool]($sessionName -or $conversationId)
            if ($isContinued) {
                # 1. 대화 기록에서 Since 이후 턴의 합계를 먼저 시도한다
                $gotFromTranscript = $false
                $now = Get-Date
                $el = [double]$agyResult.ElapsedSec
                $since = $now.AddSeconds(-($el + 5))
                $tPath = if ($subTranscriptPath -and (Test-Path -LiteralPath $subTranscriptPath -PathType Leaf)) { $subTranscriptPath } elseif ($effectiveSessionId) { Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$effectiveSessionId) } else { $null }
                $compactT = if ($tPath) { Join-Path (Split-Path -Parent $tPath) "transcript.jsonl" } else { $null }
                $actualTPath = if ($compactT -and (Test-Path -LiteralPath $compactT)) { $compactT } elseif ($tPath -and (Test-Path -LiteralPath $tPath)) { $tPath } else { $null }
                if ($actualTPath -and (Get-Command Update-AgyUsageState -ErrorAction SilentlyContinue) -and (Get-Command Get-AgyUsageSummary -ErrorAction SilentlyContinue)) {
                    try {
                        $tState = New-AgyUsageState $actualTPath
                        Update-AgyUsageState $tState
                        $tSum = Get-AgyUsageSummary $tState 0 $since
                        if ($tSum -and $tSum.Turns -gt 0 -and ($tSum.Input -gt 0 -or $tSum.Output -gt 0 -or $tSum.Total -gt 0)) {
                            $recInTok = $tSum.Input
                            $recOutTok = $tSum.Output
                            $recTotTok = $tSum.Total
                            $recThinkTok = if ($tSum.Thinking -gt 0) { $tSum.Thinking } else { $null }
                            $usageBasis = "delta"
                            $gotFromTranscript = $true
                        }
                    } catch {}
                }

                # 2. 대화 기록을 못 읽었으면 같은 session_id 의 직전 기록 누적값을 뺀다
                if (-not $gotFromTranscript) {
                    $prevRow = $null
                    if ($effectiveSessionId -and (Test-Path -LiteralPath $AgyDbPath)) {
                        try {
                            $pDb = Open-AgyDb $AgyDbPath
                            try {
                                $pRows = @($pDb.Query("SELECT total_tokens, input_tokens, output_tokens, thinking_tokens, cum_total_tokens, cum_input_tokens, cum_output_tokens, cum_thinking_tokens FROM tasks WHERE session_id = ? AND status = 'OK' AND task_id != ? ORDER BY timestamp DESC, rowid DESC LIMIT 1", [object[]]@($effectiveSessionId, $baseName)))
                                if ($pRows -and $pRows.Count -gt 0) { $prevRow = $pRows[0] }
                            } finally { $pDb.Dispose() }
                        } catch {}
                    }

                    if ($prevRow -and $null -ne $agyTot -and [string]$agyTot -ne "") {
                        $pTot = 0L; $hasPTot = [int64]::TryParse($(if ($prevRow['cum_total_tokens']) { [string]$prevRow['cum_total_tokens'] } else { [string]$prevRow['total_tokens'] }), [ref]$pTot)
                        $pIn = 0L;  $hasPIn  = [int64]::TryParse($(if ($prevRow['cum_input_tokens']) { [string]$prevRow['cum_input_tokens'] } else { [string]$prevRow['input_tokens'] }), [ref]$pIn)
                        $pOut = 0L; $hasPOut = [int64]::TryParse($(if ($prevRow['cum_output_tokens']) { [string]$prevRow['cum_output_tokens'] } else { [string]$prevRow['output_tokens'] }), [ref]$pOut)
                        $pThink = 0L; $hasPThink = [int64]::TryParse($(if ($prevRow['cum_thinking_tokens']) { [string]$prevRow['cum_thinking_tokens'] } else { [string]$prevRow['thinking_tokens'] }), [ref]$pThink)

                        $cTot = [int64]$agyTot
                        $cIn = if ($null -ne $agyIn) { [int64]$agyIn } else { 0L }
                        $cOut = if ($null -ne $agyOut) { [int64]$agyOut } else { 0L }
                        $cThink = if ($null -ne $agyThink) { [int64]$agyThink } else { 0L }

                        if ($cTot -ge $pTot) {
                            $dTot = $cTot - $pTot
                            $dIn = $cIn - $pIn
                            $dOut = $cOut - $pOut
                            $dThink = $cThink - $pThink
                            $hasNeg = ($dTot -lt 0 -or $dIn -lt 0 -or $dOut -lt 0 -or $dThink -lt 0)
                            $recTotTok = [Math]::Max(0L, $dTot)
                            $recInTok = [Math]::Max(0L, $dIn)
                            $recOutTok = [Math]::Max(0L, $dOut)
                            $recThinkTok = [Math]::Max(0L, $dThink)
                            $usageBasis = if ($hasNeg) { "delta*" } else { "delta" }
                        } else {
                            # 누적이 줄었으면 새 대화로 보고 그대로
                            $recTotTok = $cTot; $recInTok = $cIn; $recOutTok = $cOut; $recThinkTok = $cThink
                            $usageBasis = "own"
                        }
                    } else {
                        # 직전 기록도 없으면 지금 값 그대로 두되 cumulative 로 표시
                        $usageBasis = "cumulative"
                    }
                } elseif ($null -eq $recThinkTok -and $null -ne $agyThink -and [string]$agyThink -ne "") {
                    # 대화 기록에는 없지만 agy 가 보고한 사고 토큰이 있으면 직전 기록과의 차이로 보충
                    try {
                        $pDb = Open-AgyDb $AgyDbPath
                        try {
                            $pRows = @($pDb.Query("SELECT thinking_tokens, cum_thinking_tokens FROM tasks WHERE session_id = ? AND status = 'OK' AND task_id != ? ORDER BY timestamp DESC, rowid DESC LIMIT 1", [object[]]@($effectiveSessionId, $baseName)))
                            if ($pRows -and $pRows.Count -gt 0) {
                                $pThink = 0L; [void][int64]::TryParse($(if ($pRows[0]['cum_thinking_tokens']) { [string]$pRows[0]['cum_thinking_tokens'] } else { [string]$pRows[0]['thinking_tokens'] }), [ref]$pThink)
                                $cThink = [int64]$agyThink
                                $recThinkTok = [Math]::Max(0L, ($cThink - $pThink))
                            } else {
                                $recThinkTok = [int64]$agyThink
                            }
                        } finally { $pDb.Dispose() }
                    } catch { $recThinkTok = $agyThink }
                }
            }

            $thinkPart = if ($recThinkTok) { "/사고:$recThinkTok" } else { "" }
            $cumPart = if ($cumTotTok -and "$cumTotTok" -ne "$recTotTok") { " (대화 누적 $cumTotTok)" } else { "" }
            $tokStr = if ($null -ne $recTotTok -and "$recTotTok" -ne "") { "$recTotTok (입력:$recInTok/출력:$recOutTok$thinkPart)$cumPart" } else { "확인불가" }
            $attemptNote = if ($agyResult.Attempts -gt 1) { " (시도: $triedStr)" } else { "" }
            $sessionNote = if ($sessionName) { " [세션: $sessionName (ID: $effectiveSessionId)]" } else { "" }

            $modelDisplay = if ($agyResult.ModelUsed) { $agyResult.ModelUsed } else { "(확인불가)" }
            Log "완료 -> $outFile"
            Log "  사용 모델: $modelDisplay$attemptNote$sessionNote | 토큰: $tokStr | 소요시간: ${elapsedForLog}초 ($timeSrc)"

            $recModel    = $agyResult.ModelUsed
            $recElapsed  = $elapsedForLog
            $recStatus   = "OK"

            Write-UsageRow $baseName $recModel $recAttempts $recTried $recInTok $recOutTok $recThinkTok $recTotTok $recElapsed "OK" $sessionName $effectiveSessionId $cumInTok $cumOutTok $cumThinkTok $cumTotTok $usageBasis $taskAccount $taskFallbackFrom $taskAccountNote

            if ($sessionName -and $agyResult.ConversationId) {
                Write-Session -Name $sessionName -ConversationId $agyResult.ConversationId -Cwd $targetCwds -Model $agyResult.ModelUsed -Account $taskAccount
            }
            Set-Content -Path $outFile -Value ($accountFallbackBanner + $guardBanner + $cleanResponse) -Encoding UTF8
        } elseif ($agyResult.Blocked) {
            # 멈춤 확인 후 이어서 물었을 때 "[진행 불가]" 로 답한 경우: 상태는 실패(ERROR)로 기록하되 답변 전문과 토큰 사용량은 그대로 남긴다.
            $blockedResp = [string]$agyResult.Response
            Log ("실패([진행 불가]): {0}" -f (($blockedResp -split "`r?`n", 2)[0]))
            $recElapsed = $agyResult.ElapsedSec
            $recModel   = $agyResult.ModelUsed
            $agyIn = $agyResult.InTok; $agyOut = $agyResult.OutTok; $agyThink = $agyResult.ThinkTok; $agyTot = $agyResult.TotTok
            $cumInTok = $agyIn; $cumOutTok = $agyOut; $cumThinkTok = $agyThink; $cumTotTok = $agyTot
            $recInTok = $agyIn; $recOutTok = $agyOut; $recThinkTok = $agyThink; $recTotTok = $agyTot
            $usageBasis = "own"
            if ([bool]($sessionName -or $conversationId) -and $effectiveSessionId) {
                $tPath = if ($subTranscriptPath -and (Test-Path -LiteralPath $subTranscriptPath -PathType Leaf)) { $subTranscriptPath } else { Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$effectiveSessionId) }
                $compactT = if ($tPath) { Join-Path (Split-Path -Parent $tPath) "transcript.jsonl" } else { $null }
                $actualTPath = if ($compactT -and (Test-Path -LiteralPath $compactT)) { $compactT } elseif ($tPath -and (Test-Path -LiteralPath $tPath)) { $tPath } else { $null }
                if ($actualTPath -and (Get-Command Update-AgyUsageState -ErrorAction SilentlyContinue) -and (Get-Command Get-AgyUsageSummary -ErrorAction SilentlyContinue)) {
                    try {
                        $tState = New-AgyUsageState $actualTPath
                        Update-AgyUsageState $tState
                        $sinceB = (Get-Date).AddSeconds(-([double]$agyResult.ElapsedSec + 5))
                        $tSum = Get-AgyUsageSummary $tState 0 $sinceB
                        if ($tSum -and $tSum.Turns -gt 0 -and ($tSum.Input -gt 0 -or $tSum.Output -gt 0 -or $tSum.Total -gt 0)) {
                            $recInTok = $tSum.Input; $recOutTok = $tSum.Output; $recTotTok = $tSum.Total
                            $recThinkTok = if ($tSum.Thinking -gt 0) { $tSum.Thinking } else { $null }
                            $usageBasis = "delta"
                        }
                    } catch {}
                }
            }
            Write-UsageRow $baseName $recModel $recAttempts $recTried $recInTok $recOutTok $recThinkTok $recTotTok $recElapsed "ERROR" $sessionName $effectiveSessionId $cumInTok $cumOutTok $cumThinkTok $cumTotTok $usageBasis $taskAccount $taskFallbackFrom $taskAccountNote
            Set-Content -Path $outFile -Value ($accountFallbackBanner + $guardBanner + $blockedResp) -Encoding UTF8
        } else {
            $failMsg = "agy 실행 실패 (시도한 모델: $triedStr) - $($agyResult.ErrorMessage)"
            if ($modelCheck.Kind -eq "model" -and -not $conversationId) { $failMsg += " [@model 로 지정한 모델이라 다른 모델로 자동 전환하지 않았습니다]" }
            if ($modelTier -and -not $conversationId) {
                $nextTier = Get-AgyEscalationTier (Get-WatcherModelConfig) $modelTier
                if ($nextTier) { $failMsg += " [단계 $modelTier. 한 단계 올려 다시 보낼 곳: $nextTier]" } else { $failMsg += " [단계 $modelTier]" }
            }
            if ($agyResult.TimedOutReason -eq 'stall' -and ($effectiveSessionId -or ($subTranscriptPath -and (Test-Path -LiteralPath $subTranscriptPath -PathType Leaf))) -and (Get-Command Get-AgyCancelledWorkText -ErrorAction SilentlyContinue)) {
                try {
                    $stallSince = (Get-Date).AddSeconds(-([double]$agyResult.ElapsedSec + 5))
                    $workText = Get-AgyCancelledWorkText (Get-AgyHomeDir) ([string]$effectiveSessionId) $stallSince $subTranscriptPath
                    if ($workText) { $failMsg = $failMsg + "`n`n" + $workText }
                } catch {}
            }

            Log $failMsg
            $recElapsed = $agyResult.ElapsedSec
            Write-UsageRow $baseName $null $recAttempts $recTried $null $null $null $null $recElapsed "ERROR" $sessionName $effectiveSessionId $null $null $null $null "" $taskAccount $taskFallbackFrom $taskAccountNote
            Set-Content -Path $outFile -Value ($accountFallbackBanner + $guardBanner + $failMsg) -Encoding UTF8
        }

    } catch {
        $errMsg = "agy 실행 중 오류: $($_.Exception.Message)"
        Log $errMsg
        Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId $null $null $null $null "" $taskAccount $taskFallbackFrom $taskAccountNote
        Set-Content -Path $outFile -Value $errMsg -Encoding UTF8
    } finally {
        if ($tempPromptFile) {
            [void](Remove-AgyFileSafe $tempPromptFile)
        }
    }



    # error.log(agy 의 표준오류)는 응답 파일을 쓴 뒤에 쓴다(Invoke-AgyOnce 주석 참고). 쓸 내용이 없어도 빈 파일을 남겨 예전 동작을 유지한다.
    if ($agyStderr -ne $null) {
        try { [System.IO.File]::WriteAllText($errFile, [string]$agyStderr, (New-Object System.Text.UTF8Encoding($true))) } catch {}
    }

    # 지시파일을 processed 로 옮긴 뒤에 기록 저장소에 덧붙여야 방금 처리한 작업의 질문 내용도 바로 담긴다.
    Complete-TaskQaRecord $baseName $file.FullName $doneFile $subTranscriptPath $subExplicitModels $subExplicitCtx
}

# 작업자 모드: 지시파일 하나만 처리하고 끝낸다(워처 본체는 시작하지 않는다)
if ($WorkerTask) {
    try {
        Invoke-InboxTask $WorkerTask
    } catch {
        $errRec = $_
        $exMsg = if ($errRec.Exception) { [string]$errRec.Exception.Message } else { [string]$errRec }
        $wFile = Get-Item -LiteralPath $WorkerTask -ErrorAction SilentlyContinue
        if (-not $script:LogPrefix -and $WorkerTask) {
            try { $script:LogPrefix = "[$(Get-SubTaskBaseId ([System.IO.Path]::GetFileName($WorkerTask)))] " } catch {}
        }
        try { Log (Format-WorkerExceptionLog $errRec) } catch {}
        if ($wFile) {
            $errOutMsg = "agy 실행 중 오류(작업자): $exMsg. 같은 지시를 다시 보내거나 직접 처리하세요."
            Complete-InboxTaskAsError $wFile $errOutMsg
        }
    }
    exit 0
}

$script:Stopping = $false
$script:SeenFiles = @{}
$script:TaskStartCounts = @{}


# --- 종료 로그 ---

# Ctrl+C로 종료되면(가장 흔한 종료 방법) 아래 while 루프를 감싼 try/finally의 finally가

# 실행되어 종료 로그가 남습니다. 추가로, PowerShell 엔진 자체가 닫히는 경우(exit 입력, 창

# 닫기 등)에 대비해 PowerShell.Exiting 이벤트에도 로그를 남기는 핸들러를 걸어둡니다.

$global:AgyWatcherExitLogged = $false



$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {

    try {

        if (-not $global:AgyWatcherExitLogged) {

            $global:AgyWatcherExitLogged = $true

            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            Add-Content -Path $global:LogFile -Value "[$ts] ------------------------------------------------------------" -Encoding UTF8

            Add-Content -Path $global:LogFile -Value "[$ts] ===== 워처 종료 (PowerShell 엔진 종료 이벤트 감지) =====" -Encoding UTF8

            Add-Content -Path $global:LogFile -Value "[$ts] ------------------------------------------------------------" -Encoding UTF8

        }

    } catch {}

}



Log "------------------------------------------------------------"

Log "===== 워처 시작 ====="

Log "  repo 루트              : $RepoRoot"

Log "  런타임 폴더            : $RuntimeDir"

Log "  지시파일 폴더 (inbox)  : $InboxDir"

Log "  답변파일 폴더 (outbox) : $OutboxDir"

Log "  처리완료 폴더          : $ProcessedDir"

Log "  로그 폴더              : $LogsDir"

$startCfg = Get-WatcherModelConfig
Log "  모델 설정 파일         : $(if (@($startCfg.Sources).Count -gt 0) { @($startCfg.Sources) -join ', ' } else { '(없음 - 내장 기본값)' })"
foreach ($w in @($startCfg.Warnings)) { Log "  경고: $w" }
foreach ($tn in $startCfg.TierNames) {
    $t = $startCfg.Tiers[$tn]
    Log ("  단계 {0,-11}: {1} (대기 한도 {2}초)" -f $tn, (@(@($t.Model) + @($t.Fallback)) -join ' -> '), $t.WaitSec)
}
Log "  모델 자동 선택         : $(if (Test-AgyAutoTierEnabled) { '켜짐 (AGY_AUTO_MODEL=off 로 끔)' } else { '꺼짐 (AGY_AUTO_MODEL)' })"

Log "  컴퓨터 이름            : $ComputerName"

Log "종료하려면 Ctrl+C 를 누르세요."

Log "------------------------------------------------------------"



if (Test-Path $StopSignalFile) {

    [void](Remove-AgyFileSafe $StopSignalFile)

    Log "이전에 남아있던 정지 신호 파일을 정리했습니다 (시작 직후 바로 멈추는 걸 방지)."

}



# restart-agy.ps1/ensure-agy-running.ps1는 시작하기 전에 살아있는지 먼저 확인하지만,

# 그 확인과 이 스크립트가 실제로 실행되는 사이에는 시간차가 있어 경쟁 상태가 생길 수

# 있습니다(예: 사용자가 start-agy.ps1을 두 번 연달아 실행). 그래서 여기서도 한 번 더,

# 이 잠금 파일이 지금 살아있는 다른 워처를 가리키는지 스스로 확인합니다 - 안 그러면

# 그냥 덮어쓰고 둘 다 같은 inbox를 폴링하게 되어 파일 이동이 충돌합니다.

if (Test-Path $LockFile) {

    $existingPid = 0

    try { $existingPid = [int]((Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue).Trim()) } catch { $existingPid = 0 }

    if ($existingPid -gt 0 -and $existingPid -ne $PID) {

        $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue

        if ($existingProc -and $existingProc.ProcessName -eq "powershell") {

            Log "다른 워처가 이미 실행 중인 것으로 보여(PID $existingPid) 시작하지 않습니다."

            Log "먼저 stop-agy.ps1로 끄거나 restart-agy.ps1로 재시작해 주세요."

            exit 1

        }

    }

}



try {

    "$PID" | Set-Content -Path $LockFile -Encoding UTF8

    Log "잠금 파일에 이 워처의 PID($PID)를 기록했습니다: $LockFile"

} catch {

    Log "잠금 파일 기록 실패(계속 진행합니다): $($_.Exception.Message)"

}



if (Test-Path $ManualStopFlag) {

    [void](Remove-AgyFileSafe $ManualStopFlag)

    Log "수동 정지 표시를 해제했습니다 (워처가 다시 시작됨 -> 워치독이 정상적으로 감시를 재개합니다)."

}



Initialize-QaStore
Update-QAReport

function Update-SubSlotStateModels([string[]]$AvailModels) {
    if (-not $script:IsSubWatcher) { return }
    try {
        $cur = ConvertTo-BridgeHashtable (Read-BridgeJson $script:SubLayout.StateFile)
        $cur["slot_id"] = $script:SubLayout.SlotId
        $cur["models"] = @($AvailModels)
        $cur["updated_at"] = ([datetime]::UtcNow.ToString("o"))
        [void](Write-BridgeJsonAtomic $script:SubLayout.StateFile $cur)
    } catch {}
}

# 설정의 모델이 실제로 있는지 워처를 켤 때마다 `agy models` 로 확인한다(창 없이 띄우므로 깜빡이지 않음, 20초 제한).
# agy 계정을 바꾸면 쓸 수 있는 모델이 달라지므로 예전 결과를 다시 쓰지 않는다. 목록은 작업자들이 읽도록 파일에 적는다.
# 실패하거나 시간 안에 끝나지 않으면 목록 파일을 지우고(= 거르지 않음) 그대로 시작한다. 없는 모델은 경고하고, 작업 때 그 단계의 다음 모델로 대신한다.
try {
    $agyExeForList = (Get-Command agy -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $avail = Update-AgyAvailableModelsFile $AvailableModelsFile $agyExeForList 20
    if ($script:IsSubWatcher) { Update-SubSlotStateModels @($avail) }
    if ($avail -and @($avail).Count -gt 0) {
        $missing = Get-AgyMissingTierModels $startCfg @($avail)
        if ($missing.Count -eq 0) { Log "모델 확인: 설정의 모델이 모두 agy 에 있습니다(agy models $(@($avail).Count)개)." }
        foreach ($tn in $missing.Keys) { Log "경고: 단계 '$tn' 의 모델 $(@($missing[$tn]) -join ', ') 이(가) agy models 에 없어 건너뜁니다(그 단계의 다음 모델로 대신)." }
    } else {
        Log "모델 확인: agy models 를 읽지 못해 확인 없이 시작합니다(설정 그대로 씀)."
    }
} catch {
    [void](Remove-AgyFileSafe $AvailableModelsFile)
    if ($script:IsSubWatcher) { Update-SubSlotStateModels @() }
    Log "모델 확인: agy 를 찾지 못해 확인 없이 시작합니다 ($($_.Exception.Message))."
}

New-Item -ItemType Directory -Force -Path $RunningDir -ErrorAction SilentlyContinue | Out-Null
if (-not $script:IsSubWatcher) {
    Remove-StaleSessions -MaxAgeDays $SessionMaxAgeDays
} else {
    try {
        if (-not (Test-Path $HeartbeatDir)) { New-Item -ItemType Directory -Force -Path $HeartbeatDir -ErrorAction SilentlyContinue | Out-Null }
        Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content -Path $HeartbeatFile -Encoding UTF8 -ErrorAction SilentlyContinue
        $script:LastHeartbeatAt = Get-Date
    } catch {}
}



try {

    while ($true) {

        # stop-agy.ps1이 만든 정지 신호 파일이 있으면, 강제 종료가 아니라 정상적으로

        # 이 루프를 빠져나가서 아래 finally 블록의 정상 종료 로그를 그대로 남깁니다.

        if ((Test-Path $StopSignalFile) -and -not $script:Stopping) {
            [void](Remove-AgyFileSafe $StopSignalFile)
            $script:Stopping = $true
            $nowRunning = @(Get-RunningClaims).Count
            Log "정지 신호 파일 감지 -> 새 작업은 더 받지 않고, 실행 중인 작업 ${nowRunning}건이 끝나면 정상 종료합니다."
        }

        if ($script:IsSubWatcher) {
            if (Test-Path -LiteralPath $script:SubLayout.RefreshSignal -PathType Leaf) {
                $sigStamp = ""
                try { $sigStamp = ([System.IO.File]::GetLastWriteTimeUtc($script:SubLayout.RefreshSignal).Ticks.ToString() + ":" + [string]([System.IO.FileInfo]$script:SubLayout.RefreshSignal).Length) } catch {}
                if (-not $sigStamp -or $sigStamp -ne $script:LastHandledRefreshSignalStamp) {
                    try {
                        $agyExeForRefresh = (Get-Command agy -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
                        $refAvail = Update-AgyAvailableModelsFile $AvailableModelsFile $agyExeForRefresh 20
                        [void](Clear-AgySubSlotCooldown $script:SubBridgeRoot $script:SubLayout.SlotId)
                        Update-SubSlotStateModels @($refAvail)
                        Start-SubSlotAsyncQuotaRefresh ("switch_" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
                        Log "refresh.signal 감지 -> 쿨다운 해제 및 agy models 재조회 완료 ($(@($refAvail).Count)개)"
                    } catch {
                        [void](Clear-AgySubSlotCooldown $script:SubBridgeRoot $script:SubLayout.SlotId)
                    } finally {
                        $removedRefresh = Remove-AgyFileSafe $script:SubLayout.RefreshSignal
                        if ($removedRefresh) {
                            $script:LastHandledRefreshSignalStamp = ""
                        } else {
                            $script:LastHandledRefreshSignalStamp = $sigStamp
                            Log ("경고: refresh.signal 삭제 권한 오류로 1회만 처리하고 건너뜁니다($($script:SubLayout.RefreshSignal)).")
                        }
                    }
                }
            } else {
                $script:LastHandledRefreshSignalStamp = ""
            }
            if (Test-Path -LiteralPath $script:SubLayout.QuotaRefreshSignal -PathType Leaf) {
                $qSigItem = Get-Item -LiteralPath $script:SubLayout.QuotaRefreshSignal -ErrorAction SilentlyContinue
                $qSigStamp = if ($null -ne $qSigItem) { "{0}|{1}" -f $qSigItem.Length, $qSigItem.LastWriteTimeUtc.Ticks } else { "" }
                if ($qSigItem -and $qSigStamp -ne $script:LastHandledQuotaSignalStamp) {
                    $nowQUtc = [datetime]::UtcNow
                    $debounced = ($null -ne $script:LastSubQuotaRefreshAt -and ($nowQUtc - $script:LastSubQuotaRefreshAt).TotalSeconds -lt 15)
                    if (-not $debounced) {
                        $script:LastSubQuotaRefreshAt = $nowQUtc
                        Start-SubSlotAsyncQuotaRefresh ("manual_" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
                        Log "quota-refresh.signal 감지 -> 비동기 한도(/usage) 재조회 시작"
                    }
                    $removedQuotaSig = Remove-AgyFileSafe $script:SubLayout.QuotaRefreshSignal
                    if ($removedQuotaSig) {
                        $script:LastHandledQuotaSignalStamp = ""
                    } else {
                        $script:LastHandledQuotaSignalStamp = $qSigStamp
                    }
                }
            } else {
                $script:LastHandledQuotaSignalStamp = ""
            }
            if ((Test-Path -LiteralPath $script:SubLayout.RestartSignal -PathType Leaf) -and -not $script:Stopping) {
                $removedRestart = Remove-AgyFileSafe $script:SubLayout.RestartSignal
                if ($removedRestart) {
                    $script:Stopping = $true
                    $script:RestartRequested = $true
                    $script:WarnedRestartSignalLocked = $false
                    Log "restart.signal 감지 -> 실행 중 작업 완료 후 exit 42 로 재시작합니다."
                } elseif (-not $script:WarnedRestartSignalLocked) {
                    $script:WarnedRestartSignalLocked = $true
                    Log ("경고: restart.signal 삭제 권한 오류로 재시작을 보류합니다($($script:SubLayout.RestartSignal)).")
                }
            } else {
                $script:WarnedRestartSignalLocked = $false
            }
            if (Test-Path -LiteralPath $RunningDir) {
                foreach ($cf in @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.cancel" -File -ErrorAction SilentlyContinue)) {
                    $cId = [System.IO.Path]::GetFileNameWithoutExtension($cf.Name)
                    if (-not $cId) { continue }
                    $cAgeSec = ([datetime]::UtcNow - $cf.LastWriteTimeUtc).TotalSeconds
                    $cPath = Join-Path $RunningDir "$cId.json"
                    $cObj = Read-RunningClaim $cPath
                    $cResPath = Join-Path $OutboxDir "$cId.result.json"
                    if ($cObj -and -not (Test-Path -LiteralPath $cResPath)) {
                        $cPid = 0
                        try { $cPid = [int]$cObj.pid } catch { $cPid = 0 }
                        if ($cAgeSec -ge 1.5 -or $cPid -le 0) {
                            if ($cPid -gt 0 -and (Get-Command Stop-ProcessTree -ErrorAction SilentlyContinue)) {
                                Stop-ProcessTree $cPid
                            }
                            $cText = ""
                            try { $cText = ([System.IO.File]::ReadAllText($cf.FullName, [System.Text.Encoding]::UTF8)).Trim() } catch {}
                            Write-SubCancelledResult $cId $cText $cObj
                            [void](Remove-AgyFileSafe (Join-Path $InboxDir "$cId.task.json"))
                            [void](Remove-AgyFileSafe $cPath)
                            [void](Remove-AgyFileSafe $cf.FullName)
                        }
                    } elseif ($cAgeSec -ge 3.0 -or (Test-Path -LiteralPath $cResPath)) {
                        [void](Remove-AgyFileSafe $cf.FullName)
                    }
                }
            }
        }



        # --- 디스패처: 작업마다 작업자 프로세스를 띄워 여러 작업을 동시에 돌린다 ---
        # 규칙: 같은 @session 이름이면서 작업 폴더(@cwd)가 겹치는 작업끼리만 차례로 한다(같은 대화·같은 폴더를 동시에 만지지 않게).
        #       세션이 다르거나, 같은 세션이어도 폴더가 서로 다르면(겹치지 않으면) 함께 돌린다. 동시에 도는 수는 $MaxParallel 까지.
        $claims = @(Get-RunningClaims)
        $isSubPaused = $script:IsSubWatcher -and (Test-Path -LiteralPath $script:SubLayout.PauseFlag)
        if ($script:Stopping) {
            if ($claims.Count -eq 0) {
                Log "실행 중이던 작업이 모두 끝나 정상 종료합니다."
                break
            }
        } elseif (-not $isSubPaused) {
            $reserved = New-Object System.Collections.ArrayList
            foreach ($c in $claims) { [void]$reserved.Add(@{ Session = [string]$c.session; Cwds = @($c.cwds) }) }
            # 지금 돌고 있는(이번 점검에서 시작한 것 포함) 작업의 세션 이름: 같은 세션을 다른 폴더에서 또 시작할 때 경고하려고 든다
            $activeSessions = New-Object System.Collections.ArrayList
            foreach ($c in $claims) { if ([string]$c.session) { [void]$activeSessions.Add([string]$c.session) } }
            $runningIds = @($claims | ForEach-Object { [string]$_.task_id })
            $slots = if (-not $script:IsSubWatcher) {
                $priRunningCount = @($claims | Where-Object { -not $_.PSObject.Properties['bridge_slot'] -or [string]::IsNullOrWhiteSpace([string]$_.bridge_slot) }).Count
                $maxTotalClaims = [Math]::Max(25, $MaxParallel * 4)
                [Math]::Min(($MaxParallel - $priRunningCount), ($maxTotalClaims - $claims.Count))
            } else {
                $MaxParallel - $claims.Count
            }

            $files = @(Get-ChildItem -Path $InboxDir -File -ErrorAction SilentlyContinue |
                Where-Object { if ($script:IsSubWatcher) { $_.Name -like "*.task.json" } else { $_.Extension -in ".txt", ".md" } } |
                Sort-Object CreationTime)

            # 사라진 파일의 기록은 버린다
            foreach ($seenKey in @($script:SeenFiles.Keys)) {
                if (-not (Test-Path -LiteralPath $seenKey)) { $script:SeenFiles.Remove($seenKey) }
            }
            $activeInboxIds = @{}
            foreach ($af in $files) {
                $activeInboxIds[(Get-SubTaskBaseId $af.Name)] = $true
            }
            foreach ($cntKey in @($script:TaskStartCounts.Keys)) {
                if (-not $activeInboxIds.ContainsKey($cntKey)) { $script:TaskStartCounts.Remove($cntKey) }
            }

            $deferredWorkerChecks = New-Object System.Collections.ArrayList
            foreach ($file in $files) {
                $baseName = Get-SubTaskBaseId $file.Name
                if ($runningIds -contains $baseName) { continue }

                if (-not $script:IsSubWatcher) {
                    # 파일이 아직 저장(쓰기) 중일 수 있으므로 크기가 한 번 더 확인할 때까지 같아야 시작한다.
                    # ($file.Length 는 열거 시점 값이라 믿지 않고 Get-Item 으로 새로 읽는다)
                    $cur = Get-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue
                    if (-not $cur) { continue }
                    $seen = $script:SeenFiles[$file.FullName]
                    if ($null -eq $seen -or $seen.Len -ne $cur.Length) {
                        $script:SeenFiles[$file.FullName] = @{ Len = $cur.Length; At = (Get-Date) }
                        continue
                    }
                    if (((Get-Date) - $seen.At).TotalMilliseconds -lt 700) { continue }
                }

                $startCount = if ($script:TaskStartCounts.ContainsKey($baseName)) { [int]$script:TaskStartCounts[$baseName] } else { 0 }
                if ($startCount -ge 3) {
                    $repeatErrMsg = "작업자가 시작한 뒤 결과 없이 끝나기를 3번 반복해 멈췄습니다(워처 · 작업자 문제). watcher.log 의 [$baseName] 줄과 '작업자 오류' 줄을 확인하세요."
                    Log "실패: $baseName - $repeatErrMsg"
                    Complete-InboxTaskAsError $file $repeatErrMsg
                    [void]$script:TaskStartCounts.Remove($baseName)
                    continue
                }

                # 이 작업의 세션·폴더(세션에 저장된 폴더 포함)를 읽는다
                $taskSession = ""
                $taskCwds = @()
                try {
                    if ($script:IsSubWatcher) {
                        $jTask = Read-BridgeJson $file.FullName
                        if ($null -eq $jTask) { continue }
                        $taskSession = [string]$jTask.session
                        $taskCwds = @($jTask.cwds)
                    } else {
                        $rawText = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                        $dir = ConvertFrom-TaskDirectives $rawText
                        $taskSession = [string]$dir.Session
                        $taskCwds = @($dir.Cwd)
                        if ($taskSession) {
                            $sess = Read-Session $taskSession
                            if ($sess) { $taskCwds = @(Resolve-TaskCwds $taskCwds $sess.cwd) }
                        }
                    }
                } catch {}

                $conflict = $false
                foreach ($r in $reserved) {
                    if (Test-TaskConflict $taskSession $taskCwds $r.Session $r.Cwds) { $conflict = $true; break }
                }
                # 시작하지 못하는 작업도 자리를 잡아 둔다: 같은 세션·폴더의 뒤 작업이 앞질러 시작하지 않게
                [void]$reserved.Add(@{ Session = $taskSession; Cwds = $taskCwds })
                if ($conflict -or $slots -le 0) { continue }

                if (Start-InboxWorker $file $taskSession $taskCwds $deferredWorkerChecks) {
                    $script:TaskStartCounts[$baseName] = $startCount + 1
                    $slots--
                    if ($taskSession) {
                        if ($activeSessions -contains $taskSession) {
                            # 서로 다른 폴더라 함께 돌리지만, agy 의 대화는 세션 이름 하나에 하나뿐이라 두 작업의 내용이 섞일 수 있다.
                            Log "주의: 세션 '$taskSession' 이 이미 다른 폴더에서 돌고 있는데 같은 이름으로 $baseName 을 시작합니다. agy 대화가 하나라 두 작업의 맥락이 섞일 수 있으니, 폴더가 다르면 세션 이름도 다르게 쓰세요."
                        }
                        [void]$activeSessions.Add($taskSession)
                    }
                }
            }
            if ($deferredWorkerChecks.Count -gt 0) {
                Confirm-InboxWorkersStarted $deferredWorkerChecks
            }
        }



        # 하트비트: $HeartbeatIntervalSec 마다만 씁니다.
        try {
            if (((Get-Date) - $script:LastHeartbeatAt).TotalSeconds -ge $HeartbeatIntervalSec) {
                if (-not (Test-Path $HeartbeatDir)) {
                    New-Item -ItemType Directory -Force -Path $HeartbeatDir -ErrorAction SilentlyContinue | Out-Null
                }
                Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content -Path $HeartbeatFile -Encoding UTF8 -ErrorAction Stop
                $script:LastHeartbeatAt = Get-Date
            }
        } catch {}



        if (-not $script:IsSubWatcher) {
            Sync-SubQuotaSidecars
            if ($AgyDbPath -and ((Get-Date) - $script:LastFailureDoctorAt).TotalSeconds -ge 60) {
                $script:LastFailureDoctorAt = Get-Date
                if (Get-Command Update-AgyFailureRecords -ErrorAction SilentlyContinue) {
                    try {
                        [void](Update-AgyFailureRecords -DbPath $AgyDbPath)
                    } catch {
                        Log "실패 원인 분류 오류: $($_.Exception.Message)"
                    }
                }
            }
        }

        Start-Sleep -Seconds $PollSeconds

    }

} catch {

    # PowerShell이 스스로 감지할 수 있는 오류(스크립트 내부 예외 등)로 루프가 죽는 경우

    # 여기서 실제 오류 내용을 로그에 남깁니다. 단, Stop-Process/작업 관리자 강제 종료처럼

    # OS가 프로세스를 그 자리에서 즉시 죽이는 경우는 어떤 프로그램의 try/catch/finally로도

    # 절대 잡을 수 없습니다 - 이런 강제종료는 위의 하트비트 파일로 사후에 감지해야 합니다.

    try {

        $global:AgyWatcherExitLogged = $true

        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        Add-Content -Path $LogFile -Value "[$ts] ------------------------------------------------------------" -Encoding UTF8

        Add-Content -Path $LogFile -Value "[$ts] ===== 워처 비정상 종료 (처리되지 않은 오류) =====" -Encoding UTF8

        Add-Content -Path $LogFile -Value "[$ts] $($_.Exception.Message)" -Encoding UTF8

        Add-Content -Path $LogFile -Value "[$ts]   위치: $($_.InvocationInfo.PositionMessage)" -Encoding UTF8

    } catch {}

} finally {

    # Ctrl+C를 포함해 이 루프가 어떤 이유로든 빠져나갈 때(catch에서 처리된 경우도 포함) 항상 실행됩니다.

    # 위 catch에서 이미 "비정상 종료" 로그를 남긴 경우는 여기서 또 남기지 않습니다.

    # 잠금 파일은 내 PID가 적혀 있을 때만 지웁니다 (다른 워처 것을 지우지 않도록).

    try {

        if ((Test-Path $LockFile) -and ((Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue).Trim() -eq "$PID")) {

            [void](Remove-AgyFileSafe $LockFile)

        }

        [void](Remove-AgyFileSafe $HeartbeatFile)

    } catch {}



    if (-not $global:AgyWatcherExitLogged) {

        $global:AgyWatcherExitLogged = $true

        Log "------------------------------------------------------------"

        Log "===== 워처 종료 (Ctrl+C 또는 스크립트 종료) ====="

        Log "------------------------------------------------------------"

    }

}

if ($script:RestartRequested) {
    exit 42
}

