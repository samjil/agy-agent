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
    [switch]$SkipPermissions = $true
)

# 콘솔에서 한글이 깨지지 않도록 출력 인코딩을 UTF-8로 고정합니다.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

if (-not $RepoRoot) {
    $parent = Split-Path -Path $PSScriptRoot -Parent
    if ((Split-Path -Leaf $PSScriptRoot) -eq "sub") {
        $RepoRoot = Split-Path -Path $parent -Parent
    } else {
        $RepoRoot = $parent
    }
}

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



# 동시에 돌릴 작업 수. 1 이면 예전처럼 한 번에 하나씩 처리한다.
if ($MaxParallel -le 0) {
    $MaxParallel = 5
    if ($env:AGY_MAX_PARALLEL -match '^\d+$' -and [int]$env:AGY_MAX_PARALLEL -gt 0) { $MaxParallel = [int]$env:AGY_MAX_PARALLEL }
}

# --- 모델 우선순위 ---

# agy 응답 JSON에는 모델명이 담겨오지 않습니다 (CLI 자체 한계). 그래서 "어떤 모델을 썼는지

# 사후에 알아내는" 대신 "어떤 모델을 쓸지 우리가 --model로 직접 지정"하는 방식을 씁니다.

# 맨 위(가장 강력한 모델)부터 순서대로 시도하고, 쿼터 초과/일시적 사용 불가 오류가 나면

# 자동으로 다음 순위 모델로 넘어갑니다. 우리가 지정해서 성공한 값이므로 model 컬럼은 100%

# 정확합니다. 아래 ID 목록은 지금 계정에서 실제로 쓸 수 있는 모델입니다(2026-11 기준: 3.8 flash 의 high/medium/low 세 개뿐).

# Gemini 계열 모델만 사용합니다(Claude/GPT-OSS 제외). 새 모델이 나오면 `agy models` 로 ID 를 확인해서 여기에 다시 적는다.

$ModelPriority = @(

    "gemini-3.8-flash-high",

    "gemini-3.8-flash-medium",

    "gemini-3.8-flash-low"

)



# 이 패턴에 걸리는 오류일 때만 "다음 모델로 자동 폴백"합니다 (쿼터 초과/요청 과다/일시적

# 사용 불가 등). 프롬프트 자체 문제 같은, 모델을 바꿔도 똑같이 실패할 오류까지 모든 모델로

# 재시도하면 시간만 낭비하므로 걸러냅니다.

$FallbackErrorPattern = '(?i)(quota|rate.?limit|429|resource.?exhausted|overloaded|unavailable|capacity|too many requests|exceeded|throttle)'

# --- 요청에서 고르는 모델 (@model:) ---
# 지시파일 맨 위에 "@model: <ID>" 줄을 쓰면 위의 우선순위 목록 대신 그 모델 하나만 씁니다.
# 지정한 모델이 쿼터 초과/사용 불가여도 다른 모델로 자동 전환하지 않고 실패로 기록합니다
# (원하지 않은 모델의 결과를 조용히 받지 않게 하려는 것이고, 어떻게 할지는 Claude 가 사용자에게 묻습니다).
# Gemini 계열만 허용합니다(위 정책과 같음). 우선순위 목록과 같은 3.8 flash 세 단계입니다.
# 이 목록에 없는 값은 agy 를 부르지 않고 바로 실패 처리합니다.
$SelectableModels = @(@("gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low") + $ModelPriority | Select-Object -Unique)

# 지시파일 맨 위의 "@키: 값" 줄(순서 무관, 여러 줄 가능)을 읽고, 그 형식이 아닌 첫 줄부터를 프롬프트 본문으로 돌려줍니다.
#   @cwd:     agy 의 워크스페이스에 추가할 폴더 (--add-dir). 여러 줄 가능: 줄마다 폴더 하나, 폴더마다 --add-dir 를 한 번씩 넘긴다(줄 순서 유지, 같은 경로는 대소문자·끝의 \ 를 무시하고 한 번만)
#   @session: 대화를 이어갈 세션 이름
#   @model:   이번 호출에 쓸 모델 하나 (위 $SelectableModels)
#   @raw:     true 면 워처가 표준 규칙(DO NOT COMMIT 등, agy-rules.ps1)을 프롬프트에 자동으로 붙이지 않는다
#   @upgrade: true 면 @session 으로 이어가는 대화에 다른 @model 을 줘도 오류 대신 "모델 승격"을 한다: 새 대화를 시작하고 이전 질문·답 글을 지시문 위에 붙인다(Resolve-RequestedModel)
# 반환: @{ Cwd; Session; Model; Raw; Upgrade; Prompt }  (Cwd 는 폴더 배열이고 없으면 빈 배열, Session/Model 은 없으면 $null, Raw/Upgrade 는 $true/$false)
function ConvertFrom-TaskDirectives([string]$rawText) {
    $cwdRaw = New-Object System.Collections.ArrayList; $session = $null; $model = $null; $raw = $false; $upgrade = $false
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
    return @{ Cwd = @(ConvertTo-CwdList $cwdRaw.ToArray()); Session = $session; Model = $model; Raw = $raw; Upgrade = $upgrade; Prompt = $prompt }
}

# 요청한 @model 을 확인합니다. 반환: @{ Model = <정식 ID 또는 $null>; Error = <사용자에게 보일 사유 또는 $null> }
#   - 목록에 없으면 오류(대소문자는 구분하지 않고 정식 ID 로 바꿔 줍니다).
#   - 이어가는 세션(@session 으로 기존 대화를 잇는 경우)은 agy 가 시작할 때의 모델을 유지하므로,
#     다른 모델을 요청하면 조용히 무시하지 않고 오류로 알립니다(원래 대화를 지키려는 것: 실수로 모델을 잘못 적어도 대화가 바뀌지 않는다).
#   - 단 @upgrade: true 를 명시했으면 오류 대신 Upgrade = $true 로 돌려줍니다(호출한 쪽이 새 대화를 시작하고 이전 질문·답 글을 붙인다).
#     이어가는 대화가 없거나 모델이 같으면 @upgrade 는 할 일이 없다(Upgrade = $false).
function Resolve-RequestedModel([string]$requested, [string]$conversationId, [string]$knownModel, [string]$sessionName, [bool]$upgrade = $false) {
    if (-not $requested) { return @{ Model = $null; Error = $null } }
    $canonical = @($SelectableModels | Where-Object { $_ -ieq $requested }) | Select-Object -First 1
    if (-not $canonical) {
        return @{ Model = $null; Error = "지정한 @model 을 쓸 수 없습니다: $requested (쓸 수 있는 모델: $($SelectableModels -join ', '))" }
    }
    if ($conversationId -and ($canonical -ne $knownModel)) {
        if ($upgrade) { return @{ Model = $canonical; Error = $null; Upgrade = $true } }
        $was = if ($knownModel) { $knownModel } else { "기록 없음" }
        return @{ Model = $canonical; Error = "이어가는 세션 '$sessionName' 은 시작할 때의 모델($was)로 계속됩니다. 다른 모델($canonical)을 쓰려면 @upgrade: true 를 지시문에 추가해 새 대화로 승격하거나(이전 질문·답 글을 붙여 줍니다. 파일 읽기 기록은 이어지지 않습니다), @session 없이 보내거나 새 세션 이름으로 보내세요." }
    }
    return @{ Model = $canonical; Error = $null; Upgrade = $false }
}



$ComputerName = $env:COMPUTERNAME

if (-not $ComputerName) { $ComputerName = "(알수없음)" }



# 폴더 배치(runtime / data)는 agy-layout.ps1 한 곳에서 정한다. 옛 배치(runtime\outbox · runtime\logs\agy.db 등)면 폴더를 만들기 전에 먼저 옮긴다.
$layoutFile = Join-Path $PSScriptRoot "agy-layout.ps1"
if (-not (Test-Path $layoutFile)) { $layoutFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-layout.ps1" }
. $layoutFile
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

$LogMaxBytes    = 5MB      # 이 크기를 넘으면 오래된 부분을 잘라냅니다.

$LogKeepLines   = 2000     # 자를 때 남겨둘 최근 줄 수.



# 다른 스코프(엔진 종료 이벤트 핸들러 등)에서도 로그 파일 경로를 참조할 수 있도록 전역에도 둡니다.

$global:LogFile = $LogFile



# 하트비트 파일: 워처가 살아있는 동안 주기적으로 현재 시각으로 갱신됩니다.

# Stop-Process -Force / 작업 관리자 강제 종료처럼 로그를 남길 틈도 없이 프로세스가 죽는

# 경우는 이 파일의 마지막 수정 시각이 오래된 채로 멈춰 있는 것으로 "사후에" 알아챌 수 있습니다

# (그런 강제 종료 자체를 코드로 가로챌 방법은 없습니다 - OS 차원의 제약입니다).

# 이 PC 하나만 쓰므로 파일 이름에 컴퓨터 이름을 꼭 붙일 필요는 없지만, 나중에 로그만

# 보고도 출처를 알 수 있도록 그대로 유지합니다. 로컬 전용이라 동기화 부담이 없으므로

# 주기를 짧게 잡아도 무방합니다.

$HeartbeatDir  = $Layout.HeartbeatDir

New-Item -ItemType Directory -Force -Path $HeartbeatDir | Out-Null

$HeartbeatFile = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $ComputerName)

$HeartbeatIntervalSec = 10



# 잠금 파일: 이 워처 프로세스의 PID를 적어둡니다.

# "프로세스 목록에서 watch-agy.ps1을 찾기"로 생존을 판단하는 방식은 실패해서 워처가

# 하나 더 뜨는 사고로 이어진 적이 있습니다. PID를 파일에 적어두면 워치독이 그 PID만

# 확인하면 되므로 훨씬 확실합니다. 정상 종료 시에는 아래 finally에서 이 파일을 지웁니다.

$LockFile = $Layout.LockFile

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

# 위임 작업 파일(processed · outbox · 스크린샷 등) 보관 기간 정리(agy-retention.ps1). 테스트: tests\delegate-agy\agy-retention.tests.ps1
$retentionFile = Join-Path $PSScriptRoot "agy-retention.ps1"
if (-not (Test-Path $retentionFile)) {
    $retentionFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-retention.ps1"
}
. $retentionFile

# 핸드오프 "자동 이어가기" 펌프(워처 본체만 씀): 채널에 Claude 가 새 메시지를 보내면 agy 에게 위임하고, 답이 오면 회신 메시지로 기록한다.
# 못 찾거나 불러오지 못해도 워처의 본래 일(inbox 위임)에는 영향이 없다. 함수 정의는 handoff-pump.ps1 머리말 참고. 테스트: tests\handoff
$script:HandoffPumpReady = $false
$script:LastHandoffPumpAt = [datetime]::MinValue
if (-not $WorkerTask) {
    try {
        $handoffLib = $null
        foreach ($c in @((Join-Path $PSScriptRoot "..\..\..\handoff\scripts\handoff-lib.ps1"),
                         (Join-Path $env:USERPROFILE ".samjil\handoff\scripts\handoff-lib.ps1"))) {
            if (Test-Path -LiteralPath $c) { $handoffLib = $c; break }
        }
        $handoffPump = Join-Path $PSScriptRoot "handoff-pump.ps1"
        if ($handoffLib -and (Test-Path -LiteralPath $handoffPump)) {
            . $handoffLib
            . $handoffPump
            $script:HandoffPumpReady = $true
        }
    } catch {
        $script:HandoffPumpReady = $false
    }
}



# 워처가 켜질 때 한 번만: 보관 기간이 지난 기록을 정리합니다.

function Initialize-QaStore {
    try {
        $filesRemoved = Remove-DelegationFilesOlderThan $RuntimeDir $KeepMonths
        if ($filesRemoved -gt 0) { Log "보관 기간($KeepMonths 개월)이 지난 위임 작업 파일 $filesRemoved 개를 정리했습니다." }
    } catch {
        Log "위임 작업 파일 정리 중 오류: $($_.Exception.Message)"
    }
    try {
        # 핸드오프 채널의 오래된 메시지·원장(같은 보관 기간). 핸드오프 모듈이 올라와 있을 때만(워처 본체).
        if (Get-Command Remove-HandoffOlderThan -CommandType Function -ErrorAction SilentlyContinue) {
            $handoffRemoved = Remove-HandoffOlderThan $KeepMonths
            if ($handoffRemoved -gt 0) { Log "보관 기간($KeepMonths 개월)이 지난 핸드오프 메시지 $handoffRemoved 건을 정리했습니다." }
        }
    } catch {
        Log "핸드오프 정리 중 오류: $($_.Exception.Message)"
    }
    try {
        $removed = Remove-QaRecordsOlderThan $AgyDbPath $KeepMonths
        if ($removed -gt 0) { Log "보관 기간($KeepMonths 개월)이 지난 기록 $removed 건을 정리했습니다." }
    } catch {
        Log "기록 저장소 초기화 중 오류: $($_.Exception.Message)"
    }
    try {
        $tokenTurnsRemoved = Remove-TokenTurnsOlderThan $AgyDbPath 60
        if ($tokenTurnsRemoved -gt 0) { Log "보관 기간(60일)이 지난 토큰 통계 턴 $tokenTurnsRemoved 건을 정리했습니다." }
    } catch {
        Log "토큰 통계 정리 중 오류: $($_.Exception.Message)"
    }
}



# tasks 표의 행 하나(없는 칸은 NULL)로 완성된 기록 레코드를 만듭니다.
# Sync-QaStore(사용량 행만 있는 작업을 채움)와 작업자의 마무리(Complete-TaskQaRecord)가 같은 레코드를 만들도록 한 곳에 둡니다.
# $QuestionPath 를 주면 그 지시파일을 질문으로 쓰고, 안 주면 processed 폴더에서 작업 ID 로 찾습니다.
function New-QaRecordFromRow($r, [string]$QuestionPath = "") {
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
    if ($r.session_id) {
        $tPath = Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$r.session_id)
        if ($tPath -and (Test-Path -LiteralPath $tPath)) {
            $since = $null
            if ($r.session -and $r.timestamp -and $null -ne $r.elapsed_sec) {
                try {
                    $tsDate = [datetime]::Parse([string]$r.timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
                    $el = [double]$r.elapsed_sec
                    $since = $tsDate.AddSeconds(-($el + 5))
                } catch {}
            }
            $processSteps = @((Read-AgyProcessSteps $tPath 0 $QaProcessMaxSteps 500 300 $since).Steps)
        }
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
        question        = $qText
        answer          = $aText
        process         = $processSteps
    }
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

# 작업자가 작업 하나를 끝낼 때의 마무리: 지시파일을 processed 로 옮기고, 그 작업의 행(사용량 행은 Write-UsageRow 가 먼저 넣었다)에
# 질문·답·과정을 채운다. 작업자는 작업마다 새 프로세스라 전체 기록을 읽지 않고 이 한 건만 다룬다.
# 사용량 행이 없거나 채우다 오류가 나면 미완료 작업 전체를 채우는 보충(Update-QAReport)으로 물러선다.
function Complete-TaskQaRecord([string]$TaskId, [string]$SourcePath, [string]$DonePath) {
    Move-Item -Path $SourcePath -Destination $DonePath -Force
    try {
        $row = Get-QaTaskRow $AgyDbPath $TaskId
        if ($null -eq $row) { Update-QAReport; return }       # 사용량 행을 못 썼다: 있는 미완료 작업이라도 채워 둔다
        if ($null -ne $row.answer) { return }                  # 이미 채워졌다(워처가 켜질 때의 보충이 먼저 한 경우)
        $rec = New-QaRecordFromRow $row $DonePath
        if ((Write-QaRecordToDb $AgyDbPath $rec 'FillIfIncomplete') -eq 'pending') { Log "기록을 DB 에 바로 쓰지 못해 pending 폴더에 두었습니다: $TaskId" }
    } catch {
        Log "기록 저장소에 작업 한 건을 채우다 오류가 나서 전체 보충으로 대신합니다: $($_.Exception.Message)"
        Update-QAReport
    }
}

# 위임이 끝났을 때 백그라운드에서 토큰 통계를 비동기로 갱신한다. 10분 이내 재시작은 건너뛴다.
function Start-TokenStatsTrigger {
    param([switch]$Force)
    try {
        $tokenStatsScript = Join-Path $PSScriptRoot "token-stats.ps1"
        if (-not (Test-Path -LiteralPath $tokenStatsScript)) { return }
        $dataDir = if ($Layout -and $Layout.DataDir) { $Layout.DataDir } else { Split-Path $AgyDbPath -Parent }
        $triggerFile = Join-Path $dataDir "token-stats-last-trigger.txt"
        if (-not $Force -and (Test-Path -LiteralPath $triggerFile)) {
            try {
                $raw = [System.IO.File]::ReadAllText($triggerFile, [System.Text.Encoding]::UTF8)
                if ($raw -and $raw.Trim()) {
                    $lastTime = [DateTime]::Parse($raw.Trim(), $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                    if ([Math]::Abs(((Get-Date) - $lastTime).TotalMinutes) -lt 10) {
                        return
                    }
                }
            } catch {}
        }
        [System.IO.File]::WriteAllText($triggerFile, (Get-Date).ToString("o"), [System.Text.Encoding]::UTF8)

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tokenStatsScript`" -Update -RuntimeDir `"$RuntimeDir`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.RedirectStandardInput = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($null -ne $proc) {
            try { $proc.StandardInput.Close() } catch {}
        }
    } catch {
        Log "토큰 통계 갱신 프로세스 시작 실패: $($_.Exception.Message)"
    }
}


# 사용량 행(tasks 표)을 쓴다: 작업이 끝났을 때 한 번.
function Write-UsageRow($taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, [string]$session = "", [string]$sessionId = "", $cumInputTokens = $null, $cumOutputTokens = $null, $cumThinkingTokens = $null, $cumTotalTokens = $null, [string]$usageBasis = "") {
    try {
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
        }
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
function Update-QAReport { [void](Sync-QaStore) }

# agy 한 번 호출이 이 시간을 넘기면 강제로 중단하고 그 작업을 실패 처리합니다.

# (없으면 agy가 멈췄을 때 워처 전체가 무한정 묶입니다 - 실제로 agy가 콘솔 입력을

#  기다리는 바람에 워처가 13분 넘게 그 자리에서 멈춘 적이 있습니다.)

$AgyTimeoutSeconds = 1800
$AgyTimeoutSeconds = Get-AgySecondsSetting 'AGY_TIMEOUT_SECONDS' 1800 60   # 환경변수 AGY_TIMEOUT_SECONDS(60 이상)로 바꿀 수 있다
# 절대 마감을 넘겨도 agy 가 진짜 일하는 중이면(새 단계·도구 출력·CPU) 바로 끊지 않고 이 시간까지 더 기다린다. 이 시간이 지나면 일하는 중이어도 끊는다.
$AgyHardTimeoutSeconds = [Math]::Max((Get-AgySecondsSetting 'AGY_HARD_TIMEOUT_SECONDS' 7200 60), $AgyTimeoutSeconds)   # 환경변수 AGY_HARD_TIMEOUT_SECONDS 로 바꿀 수 있다(마감보다 작으면 마감과 같게)

# 위 절대 마감과 별개로, agy 대화 기록에 새 단계가 이 시간 동안 하나도 없으면 "멈춘 것"으로 보고
# 중단합니다. 단계가 계속 기록되는 동안은(= 일하는 중) 절대 마감까지 기다립니다.
# 이 값의 근거와 한계는 agy-progress.ps1 머리말을 보세요.
$AgyStallSeconds = 300
$AgyStallSeconds = Get-AgySecondsSetting 'AGY_STALL_SECONDS' 300 30   # 환경변수 AGY_STALL_SECONDS(30 이상)로 바꿀 수 있다
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
function Invoke-AgyOnce($agyArgs, $errFile, $workDir, [string]$marker = "") {
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
    $proc    = $null
    $outTask = $null
    $errTask = $null
    try {
        $agyCmd = Get-Command agy -CommandType Application -ErrorAction Stop | Select-Object -First 1
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
    $capNote         = ""
    $finished        = $false
    while ($true) {
        $finished = $proc.WaitForExit([int]($AgyPollSeconds * 1000))
        if ($finished) { break }
        $now     = Get-Date
        $elapsed = ($now - $startedAt).TotalSeconds
        if ($elapsed -ge $AgyHardTimeoutSeconds) { $stopReason = 'hard'; $stopNow = $now; break }
        # 마감 직전부터 CPU 표본을 모은다(마감 이후 "진짜 일하는 중인가"를 두 시점의 차이로 보려고)
        if ($elapsed -ge ($AgyTimeoutSeconds - 2 * $AgyStallSeconds)) {
            [void]$cpuSamples.Add(@{ At = $now; Cpu = (Get-AgyTreeCpuSeconds $proc.Id) })
            while ($cpuSamples.Count -gt 0 -and (($now - $cpuSamples[0].At).TotalSeconds -gt (3 * $AgyStallSeconds))) { $cpuSamples.RemoveAt(0) }
        }
        # 절대 마감에 닿아도 바로 끊지 않는다. 그 시점에 agy 가 진짜 일하는 중인지(새 단계·도구 출력·CPU) 확인해, 일하면 최대 대기 시간(AgyHardTimeoutSeconds)까지
        # 계속 기다리고 아무 활동도 없으면 멈춘 것으로 보고 끊는다.
        if ($elapsed -ge $AgyTimeoutSeconds) {
            $alive = Test-AgyAliveAtCap $agyHome $convId $now $AgyStallSeconds $cpuSamples
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
            if (Test-AgyStalled $lastActivity $startedAt $now $AgyStallSeconds) {
                # 오래 걸리는 명령을 agy 가 백그라운드로 돌려 두고 기다리는 중이면 새 단계가 없는 게 정상이다. 끊지 않는다(절대 마감은 그대로).
                $bgPending = @(Get-AgyPendingBackgroundTasks $agyHome $convId)
                if ($bgPending.Count -gt 0) {
                    if ($elapsed -ge $nextBgLog) {
                        Log ("  새 단계가 {0}초 넘게 없지만 agy 가 백그라운드로 돌린 도구 {1}건이 아직 끝나지 않아 멈춤으로 보지 않고 기다립니다 ({2}). 절대 마감 {3}초까지." -f $AgyStallSeconds, $bgPending.Count, ($bgPending -join ', '), $AgyTimeoutSeconds)
                        $nextBgLog = $elapsed + 300
                    }
                } else {
                    $stopReason = 'stall'; $stopNow = $now; break
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
        $lastStepText = ""
        if ($convId) { try { $lastStepText = Format-AgyLastStep (Get-AgyLastStepSummary $agyHome $convId) } catch {} }
        return @{ TimedOut = $true; Raw = $null; Reason = $stopReason; IdleSeconds = $idleSeconds; LastActivity = $lastText; ConversationId = $convId; LastStep = $lastStepText; CapNote = $capNote }
    }
    # 끝났다: 남은 출력을 마저 받는다(비동기로 읽던 스트림이 닫힐 때까지).
    try { $proc.WaitForExit() } catch {}
    $outText = ""
    $errText = ""
    try { $outText = [string]$outTask.Result } catch {}
    try { $errText = [string]$errTask.Result } catch {}
    try { $proc.Dispose() } catch {}
    # 표준오류는 여기서 파일에 쓰지 않고 돌려준다. error.log 는 응답 파일을 쓴 뒤에 쓰도록 호출한 쪽(Invoke-InboxTaskBody)이 맡는다:
    # Claude 의 점검 루프는 비어 있지 않은 error.log 를 보면 "오류"로 끝내므로, 성공했는데 agy 가 남긴 잡음(stderr)이
    # 응답 파일보다 먼저 보이면 잘못된 오류가 된다.
    if ([string]::IsNullOrWhiteSpace($outText)) {
        return @{ TimedOut = $false; Raw = $null; StdErr = $errText }
    }
    # 하나의 문자열로 돌려준다(줄 배열로 넘기면 ConvertFrom-Json 이 줄마다 따로 해석해 배열이 되어 필드를 못 읽는다).
    return @{ TimedOut = $false; Raw = $outText.Trim(); StdErr = $errText }
}

# $conversationId가 없으면: $ModelPriority 목록을 순서대로 시도합니다(기존 동작).

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

function Invoke-AgyWithFallback($safePrompt, $targetCwd, [bool]$skipPerm, $errFile, [string]$conversationId = "", [string]$knownModel = "", [string]$taskId = "", [string]$promptFile = "", [string]$requestedModel = "", [string]$autoModel = "") {
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
    }

    $overallStart = Get-Date
    # 주의: 여기서 @($null)을 쓰면 안 됩니다 - PowerShell은 "원소가 $null 하나뿐인 배열"을
    # if/스크립트 출력 캡처 과정에서 그냥 $null로 뭉개버려서(직접 겪음: $candidates.Count가
    # 0이 되고 foreach가 한 번도 안 돎), 세션을 이어가려던 호출이 조용히 아무것도 안 하고
    # "실패(시도한 모델: )"로 끝나버립니다. 그래서 $null이 아닌 문자열 자리표시자를 씁니다.
    # 이어가는 세션: 호출 한 번. @model 로 지정했으면 그 모델 하나만(폴백 없음). 아니면 우선순위 목록.
    # @() 로 감싸는 이유: if 식은 원소 하나짜리 배열을 문자열로 풀어서 $candidates[-1] 이 마지막 "글자"가 된다.
    # 자동 선택($autoModel, 낮은 단계)은 지정이 아니라 "먼저 시도할 모델"이라, 쿼터 초과 같은 오류면 우선순위 목록으로 이어서 폴백한다.
    $candidates = @(if ($conversationId) { "(continue)" } elseif ($requestedModel) { $requestedModel } elseif ($autoModel) { @($autoModel) + @($ModelPriority | Where-Object { $_ -ne $autoModel }) } else { $ModelPriority })

    foreach ($candidate in $candidates) {
        $result.Attempts++
        $result.TriedModels += $candidate

        # 지시문 전달 방식(인라인 / 파일 참조)과 표식. 인라인이면 표식을 작업 표시 파일에 적어 둬서, 같은 표식으로 시작하는 다른 작업이 파일 참조로 비켜 가게 한다.
        $plainPrompt = ([string]$safePrompt).Replace('\"', '"')
        $hasPromptFile = [bool]($promptFile -and (Test-Path -LiteralPath $promptFile))
        $delivery = @{ Mode = 'inline'; Marker = (Get-AgyPromptMarker $plainPrompt); Reason = '' }
        if ($hasPromptFile) {
            $others = Get-OtherRunningMarkers $taskId
            $delivery = Get-AgyPromptDelivery $plainPrompt $others.Markers $others.Total
        }
        if ($taskId) { try { Write-RunningClaim $taskId @{ marker = [string]$(if ($delivery.Mode -eq 'inline') { $delivery.Marker } else { '' }) } } catch {} }

        # 웹 뷰어 실시간 표시용: 현재 실행 중인 작업과 모델 정보를 current_task.json에 기록
        $modelForReport = if ($conversationId) {
            if ($knownModel) { $knownModel } else { $ModelPriority[0] }
        } else {
            $candidate
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
                Write-RunningClaim $taskId @{ model = $modelForReport; attempt = $result.Attempts; started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
            } catch {}
        }

        # 프롬프트 인자: 위에서 정한 방식(인라인 글 또는 @임시프롬프트파일)
        $promptArg = if ($delivery.Mode -eq 'file') { "@$promptFile" } else { $plainPrompt }
        $agyArgs = @('-p', $promptArg, '--output-format', 'json')

        if ($conversationId) { $agyArgs += @('--conversation', $conversationId) } else { $agyArgs += @('--model', $candidate) }

        foreach ($dir in @($targetCwd)) { if ($dir) { $agyArgs += @('--add-dir', [string]$dir) } }

        if ($skipPerm)  { $agyArgs += '--dangerously-skip-permissions' }

        # 동시에 도는 다른 작업과 대화를 헷갈리지 않게, 이 호출의 질문에만 들어 있는 글(표식)을 함께 넘긴다:
        # 파일 참조면 그 파일 이름, 인라인이면 지시문 첫 줄(따옴표·역슬래시 앞까지, 12자 이상일 때만).
        $marker = if ($delivery.Mode -eq 'file') { [System.IO.Path]::GetFileName($promptFile) } else { [string]$delivery.Marker }
        if ($delivery.Mode -eq 'file' -and $delivery.Reason) { Log "  -> 지시문을 파일 참조로 넘깁니다($($delivery.Reason))" }
        $call = Invoke-AgyOnce $agyArgs $errFile $RuntimeDir $marker
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
                break
            }
        }

        if ($call.TimedOut) {

            if ($call.Reason -eq 'stall') {
                $idleMin = [math]::Round($call.IdleSeconds / 60, 1)
                $result.ErrorMessage = "agy가 $idleMin 분 동안 진행하지 않아 중단했습니다 (멈춤 판정: 마지막 활동 $($call.LastActivity), 대화 ID $($call.ConversationId))"
                Log "  멈춤: 대화 기록에 새 단계가 $idleMin 분 동안 없어 강제로 중단했습니다 (마지막 활동 $($call.LastActivity), 대화 $($call.ConversationId)). 이 작업은 실패로 기록합니다."
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

            # 성공

            $result.Success        = $true

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

            break

        }



        # status == ERROR

        $errText = if ($json.error) { [string]$json.error } else { "" }

        $result.RawJson = $raw

        $result.ErrorMessage = $errText



        $isLast = ($candidate -eq $candidates[-1])

        if (-not $isLast -and $errText -match $FallbackErrorPattern) {

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
            if ([string]$ct.task_id -eq $taskId) { Remove-Item -Path $currentTaskFile -Force -ErrorAction SilentlyContinue }
        } catch { Remove-Item -Path $currentTaskFile -Force -ErrorAction SilentlyContinue }
    }

    return $result

}



# ----------------------------------------------------------------------------
# 동시 실행: 작업 표시 파일, 충돌 판정, 작업자 프로세스
# ----------------------------------------------------------------------------

# 표시 파일(running\<작업 ID>.json)을 읽는다. 없거나 반쯤 쓴 파일이면 $null.
function Read-RunningClaim([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $t = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        if (-not $t.Trim()) { return $null }
        return (ConvertFrom-Json -InputObject $t -ErrorAction Stop)
    } catch { return $null }
}

# 표시 파일에 필드를 합쳐 쓴다(이미 있는 필드는 그대로 두고 준 것만 덮는다). 임시 파일에 쓰고 바꿔치기해서 읽는 쪽이 반쯤 쓴 파일을 보지 않는다.
function Write-RunningClaim([string]$TaskId, [hashtable]$Fields) {
    if (-not $TaskId) { return }
    try {
        if (-not (Test-Path -LiteralPath $RunningDir)) { New-Item -ItemType Directory -Force -Path $RunningDir | Out-Null }
        $path = Join-Path $RunningDir ("{0}.json" -f $TaskId)
        $data = [ordered]@{ task_id = $TaskId }
        $old = Read-RunningClaim $path
        if ($old) { foreach ($p in $old.PSObject.Properties) { $data[$p.Name] = $p.Value } }
        foreach ($k in $Fields.Keys) { $data[$k] = $Fields[$k] }
        $tmp = "$path.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $data -Compress -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {}
}

function Remove-RunningClaim([string]$TaskId) {
    if (-not $TaskId) { return }
    Remove-Item -LiteralPath (Join-Path $RunningDir ("{0}.json" -f $TaskId)) -Force -ErrorAction SilentlyContinue
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
    # PID 가 아직 채워지지 않은 표시(띄우는 도중 워처가 멈춘 것)는 시작도 못 한 작업이다: 표시만 지워 다시 시작하게 한다
    $deadPid = 0
    try { $deadPid = [int]$Claim.pid } catch { $deadPid = 0 }
    if ($deadPid -le 0) { Remove-Item -LiteralPath $ClaimPath -Force -ErrorAction SilentlyContinue; return }
    $inboxFile = $null
    foreach ($ext in @(".md", ".txt")) {
        $cand = Join-Path $InboxDir ($taskId + $ext)
        if (Test-Path -LiteralPath $cand) { $inboxFile = $cand; break }
    }
    if ($inboxFile) {
        $msg = "작업을 처리하던 프로세스가 끝내지 못하고 사라졌습니다(워처를 껐거나 강제 종료됐을 수 있습니다). 같은 지시를 다시 보내 주세요."
        Log "실패: $taskId - $msg"
        $outFile = Join-Path $OutboxDir "$taskId.response.md"
        if (-not (Test-Path -LiteralPath $outFile)) { Set-Content -Path $outFile -Value $msg -Encoding UTF8 }
        Write-UsageRow $taskId $null $null $null $null $null $null $null $null "ERROR" ([string]$Claim.session) ""
        Move-Item -LiteralPath $inboxFile -Destination (Join-Path $ProcessedDir (Split-Path $inboxFile -Leaf)) -Force -ErrorAction SilentlyContinue
        Update-QAReport
    }
    Remove-Item -LiteralPath $ClaimPath -Force -ErrorAction SilentlyContinue
}

# 지금 돌고 있는 작업들의 표시 목록. 죽은 작업의 표시는 여기서 정리한다.
function Get-RunningClaims {
    $alive = @()
    if (Test-Path -LiteralPath $RunningDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            $c = Read-RunningClaim $f.FullName
            if ($null -eq $c) {
                # 읽을 수 없는 표시 파일은 오래되면(쓰다 만 것) 지운다
                if (((Get-Date) - $f.LastWriteTime).TotalSeconds -gt 120) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
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

# 작업자 프로세스(보이지 않는 창)를 띄워 지시파일 하나를 처리하게 한다. 띄웠으면 $true.
# 작업자는 watch-agy.ps1 을 그대로 쓰되 명령줄에 "watch-agy.ps1" 이 나타나지 않게 얇은 껍데기(agy-task-worker.ps1)로 띄운다 —
# start-agy/ensure-agy-running 이 명령줄의 그 이름으로 워처를 찾기 때문에, 작업자가 워처로 오인되어 종료되는 일을 막는다.
function Start-InboxWorker([System.IO.FileInfo]$File, [string]$Session, $Cwds) {
    $taskId = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $wrapper = Join-Path $PSScriptRoot "agy-task-worker.ps1"
    if (-not (Test-Path -LiteralPath $wrapper)) {
        Log "오류: 작업자 스크립트를 찾을 수 없습니다: $wrapper (install.ps1 을 다시 실행해 주세요)"
        return $false
    }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$wrapper`"",
        "-RepoRoot", "`"$RepoRoot`"", "-RuntimeDir", "`"$RuntimeDir`"", "-WorkerTask", "`"$($File.FullName)`"")
    if ($SkipPermissions) { $argList += "-SkipPermissions" }
    try {
        # 표시 파일을 먼저 만들어 두고(PID 는 0) 띄운 뒤 PID 를 채운다: 그 사이 다른 쪽이 "안 도는 작업"으로 보지 않게
        Write-RunningClaim $taskId @{ pid = 0; session = $Session; cwds = @($Cwds); started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); watcher_pid = $PID }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = ($argList -join " ")
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $proc = [System.Diagnostics.Process]::Start($psi)
        Write-RunningClaim $taskId @{ pid = $proc.Id }
        Log "작업 시작: $($File.Name) (작업자 PID $($proc.Id)$(if ($Session) { ", 세션: $Session" }))"
        return $true
    } catch {
        Log "작업자를 띄우지 못했습니다: $($_.Exception.Message)"
        Remove-RunningClaim $taskId
        return $false
    }
}

# 지시파일 하나를 끝까지 처리한다(작업자 모드의 본체). 끝나면 표시 파일을 지운다.
function Invoke-InboxTask([string]$TaskPath) {
    $file = Get-Item -LiteralPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $file) { return }
    $taskKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($WorkerTask) { $script:LogPrefix = "[$taskKey] " }
    # 표시 파일의 PID 를 내 것으로 확정한다(껍데기 프로세스가 곧 이 프로세스다)
    Write-RunningClaim $taskKey @{ pid = $PID }
    $script:CurrentTaskId = $taskKey
    try {
        Invoke-InboxTaskBody $file
    } finally {
        Remove-RunningClaim $taskKey
    }
}

# 한 지시파일을 처리하는 본체(예전에 메인 루프 안에 있던 부분)

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

    $conversationId = ""

    $knownModel     = ""

    if ($sessionName) {

        $existingSession = Read-Session $sessionName

        if ($existingSession) {

            if ($existingSession.conversation_id) { $conversationId = [string]$existingSession.conversation_id }

            # 이번 호출에 @cwd 가 하나라도 있으면 이번 목록만, 없으면 세션의 목록(예전 파일의 문자열 하나도 읽는다)
            $targetCwds = @(Resolve-TaskCwds $targetCwds $existingSession.cwd)

            if ($existingSession.model) { $knownModel = [string]$existingSession.model }

        }

    }



    # @model 검사: 쓸 수 없는 모델이면 agy 를 부르지 않고 바로 실패 처리합니다(@cwd 오류와 같은 방식).
    $modelCheck = Resolve-RequestedModel $requestedModel $conversationId $knownModel $sessionName ([bool]$directives.Upgrade)
    if ($modelCheck.Error) {
        Set-Content -Path $outFile -Value $modelCheck.Error -Encoding UTF8
        Log "실패: $($modelCheck.Error)"
        Write-UsageRow $baseName $null $null $requestedModel $null $null $null $null $null "ERROR" $sessionName $conversationId
        Complete-TaskQaRecord $baseName $file.FullName $doneFile
        Start-TokenStatsTrigger
        return
    }
    $requestedModel = $modelCheck.Model
    if ($requestedModel) { Log "  -> 지정 모델(@model): $requestedModel (다른 모델로 자동 전환하지 않음)" }

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

    # 모델을 지정하지 않았고 새 대화(@session 없음)면 요청 난이도로 노력 단계를 자동 선택한다(agy-autotier.ps1).
    # 분명히 쉬운 일만 low/medium 으로 낮추고, 애매하거나 어려우면 지금처럼 우선순위 목록(high)을 쓴다. 이어가는 세션은 시작할 때의 모델을 유지한다.
    $autoModel = ""
    if (-not $requestedModel -and -not $sessionName -and (Test-AgyAutoTierEnabled)) {
        $autoTier = Get-AgyAutoTier $promptText (@($targetCwds).Count -gt 0)
        if ($autoTier.Tier -ne "high") { $autoModel = [string]$autoTier.Model }
        Log "  -> 모델 자동 선택: $($autoTier.Tier) ($($autoTier.Reason))$(if ($autoModel) { " -> $autoModel 먼저, 안 되면 기본 우선순위" } else { " -> 기본 우선순위" })"
    }

    $missingCwds = @(Get-MissingCwds $targetCwds)
    if ($missingCwds.Count -gt 0) {
        Set-Content -Path $outFile -Value "지정한 @cwd 경로를 찾을 수 없습니다: $($missingCwds -join ', ')" -Encoding UTF8
        Log "실패: @cwd 경로 없음 ($($missingCwds -join ', '))"
        # agy를 호출하지 않고 여기서 바로 실패 처리하는 경우도, 나중에 "이 작업이
        # 있었는지" 조회할 수 있도록 다른 실패와 똑같이 위임 기록 DB 에 남깁니다
        # (여기서 기록하지 않으면 outbox에는 파일이 남는데 기록에서는 통째로 빠집니다).
        Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId

        Complete-TaskQaRecord $baseName $file.FullName $doneFile

        Start-TokenStatsTrigger
        return
    }



    foreach ($cwdPath in $targetCwds) {

        Log "  -> 대상 폴더(--add-dir): $cwdPath"

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

    try {
        # 프롬프트 길이와 무관하게 항상 임시 프롬프트 파일(@$tempPromptFile)을 사용하여
        # 명령줄 따옴표/이스케이프 깨짐을 방지하고 병렬 실행 시 고유한 대화 식별 Marker를 보장합니다.
        $promptsDir = $Layout.PromptsDir
        if (-not (Test-Path -LiteralPath $promptsDir)) {
            New-Item -ItemType Directory -Force -Path $promptsDir | Out-Null
        }
        # 폴더(@cwd)를 여는 작업에는 표준 규칙을 붙인다(@raw: true 면 안 붙임). 위임 기록에는 원본 지시문이 남는다(여기서는 agy 에 넘길 프롬프트만 바꾼다).
        $withRules = Add-AgyStandardRules $promptText (@($targetCwds).Count -gt 0) ([bool]$directives.Raw)
        $promptForAgy = [string]$withRules.Text
        if (@($withRules.Added).Count -gt 0) { Log "  -> 표준 규칙 자동 추가: $(@($withRules.Added) -join ', ')" }
        $tempPromptFile = Join-Path $promptsDir "prompt_$baseName.txt"
        [System.IO.File]::WriteAllText($tempPromptFile, $promptForAgy, (New-Object System.Text.UTF8Encoding($false)))
        $safePrompt = $promptForAgy -replace '"', '\"'

        $agyResult = Invoke-AgyWithFallback -safePrompt $safePrompt -targetCwd $targetCwds -skipPerm:$SkipPermissions -errFile $errFile -conversationId $conversationId -knownModel $knownModel -taskId $baseName -promptFile $tempPromptFile -requestedModel $requestedModel -autoModel $autoModel

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

        if ($agyResult.Success) {
            Set-Content -Path $outFile -Value ($guardBanner + $agyResult.Response) -Encoding UTF8

            # 이어가는 세션에서 agy 가 보고하는 duration_seconds 는 그 대화를 처음 연 때부터의 누적이라(사이에 쉰 시간 포함) 이번 호출의 시간이 아니다.
            # 그래서 이어가는 호출은 워처가 잰 이번 호출의 시간을 쓴다.
            $useAgyDuration = [bool]$agyResult.AgyDuration -and -not $conversationId
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
                $tPath = if ($effectiveSessionId) { Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$effectiveSessionId) } else { $null }
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

            Write-UsageRow $baseName $recModel $recAttempts $recTried $recInTok $recOutTok $recThinkTok $recTotTok $recElapsed "OK" $sessionName $effectiveSessionId $cumInTok $cumOutTok $cumThinkTok $cumTotTok $usageBasis

            if ($sessionName -and $agyResult.ConversationId) {
                Write-Session -Name $sessionName -ConversationId $agyResult.ConversationId -Cwd $targetCwds -Model $agyResult.ModelUsed
            }
        } else {
            $failMsg = "agy 실행 실패 (시도한 모델: $triedStr) - $($agyResult.ErrorMessage)"
            if ($requestedModel -and -not $conversationId) { $failMsg += " [@model 로 지정한 모델이라 다른 모델로 자동 전환하지 않았습니다]" }

            Set-Content -Path $outFile -Value ($guardBanner + $failMsg) -Encoding UTF8
            Log $failMsg
            $recElapsed = $agyResult.ElapsedSec
            Write-UsageRow $baseName $null $recAttempts $recTried $null $null $null $null $recElapsed "ERROR" $sessionName $effectiveSessionId
        }

    } catch {
        $errMsg = "agy 실행 중 오류: $($_.Exception.Message)"
        Set-Content -Path $outFile -Value $errMsg -Encoding UTF8
        Log $errMsg
        Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId
    } finally {
        if ($tempPromptFile -and (Test-Path -LiteralPath $tempPromptFile)) {
            Remove-Item -LiteralPath $tempPromptFile -Force -ErrorAction SilentlyContinue
        }
    }



    # error.log(agy 의 표준오류)는 응답 파일을 쓴 뒤에 쓴다(Invoke-AgyOnce 주석 참고). 쓸 내용이 없어도 빈 파일을 남겨 예전 동작을 유지한다.
    if ($agyStderr -ne $null) {
        try { [System.IO.File]::WriteAllText($errFile, [string]$agyStderr, (New-Object System.Text.UTF8Encoding($true))) } catch {}
    }

    # 지시파일을 processed 로 옮긴 뒤에 기록 저장소에 덧붙여야 방금 처리한 작업의 질문 내용도 바로 담긴다.
    Complete-TaskQaRecord $baseName $file.FullName $doneFile

    $forceTrigger = $false

    try {
        if ($recStatus -eq "OK" -and $recModel -and $recElapsed) {
            $dataDir = if ($Layout -and $Layout.DataDir) { $Layout.DataDir } else { Split-Path $AgyDbPath -Parent }
            $calFile = Join-Path $dataDir "calibration.json"
            if (Test-Path -LiteralPath $calFile) {
                $calObj = Get-Content -LiteralPath $calFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $mLower = ([string]$recModel).ToLower()
                $levelKey = if ($mLower -match 'low') { 'low' } elseif ($mLower -match 'medium') { 'medium' } elseif ($mLower -match 'high') { 'high' } else { $null }
                if ($levelKey -and $calObj.time -and $calObj.time.agy_median_s) {
                    $medVal = $calObj.time.agy_median_s.$levelKey
                    $elVal = 0.0
                    if ($medVal -and [double]::TryParse([string]$recElapsed, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$elVal)) {
                        if ($elVal -gt (3.0 * [double]$medVal)) {
                            $forceTrigger = $true
                        }
                    }
                }
            }
        }
    } catch {}

    if ($forceTrigger) {
        Start-TokenStatsTrigger -Force
    } else {
        Start-TokenStatsTrigger
    }
}

# 작업자 모드: 지시파일 하나만 처리하고 끝낸다(워처 본체는 시작하지 않는다)
if ($WorkerTask) {
    Invoke-InboxTask $WorkerTask
    exit 0
}

$script:Stopping = $false
$script:SeenFiles = @{}


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

Log "  모델 우선순위          : $($ModelPriority -join ' -> ')"
Log "  지정 가능 모델(@model:): $($SelectableModels -join ', ')"
Log "  모델 자동 선택         : $(if (Test-AgyAutoTierEnabled) { '켜짐 (AGY_AUTO_MODEL=off 로 끔)' } else { '꺼짐 (AGY_AUTO_MODEL)' })"

Log "  컴퓨터 이름            : $ComputerName"

Log "종료하려면 Ctrl+C 를 누르세요."

Log "------------------------------------------------------------"



if (Test-Path $StopSignalFile) {

    Remove-Item -Path $StopSignalFile -Force -ErrorAction SilentlyContinue

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

    Remove-Item -Path $ManualStopFlag -Force -ErrorAction SilentlyContinue

    Log "수동 정지 표시를 해제했습니다 (워처가 다시 시작됨 -> 워치독이 정상적으로 감시를 재개합니다)."

}



Initialize-QaStore
Update-QAReport

New-Item -ItemType Directory -Force -Path $RunningDir -ErrorAction SilentlyContinue | Out-Null
Remove-StaleSessions -MaxAgeDays $SessionMaxAgeDays



try {

    while ($true) {

        # stop-agy.ps1이 만든 정지 신호 파일이 있으면, 강제 종료가 아니라 정상적으로

        # 이 루프를 빠져나가서 아래 finally 블록의 정상 종료 로그를 그대로 남깁니다.

        if ((Test-Path $StopSignalFile) -and -not $script:Stopping) {
            Remove-Item -Path $StopSignalFile -Force -ErrorAction SilentlyContinue
            $script:Stopping = $true
            $nowRunning = @(Get-RunningClaims).Count
            Log "정지 신호 파일 감지 -> 새 작업은 더 받지 않고, 실행 중인 작업 ${nowRunning}건이 끝나면 정상 종료합니다."
        }



        # --- 디스패처: 작업마다 작업자 프로세스를 띄워 여러 작업을 동시에 돌린다 ---
        # 규칙: 같은 @session 이름이면서 작업 폴더(@cwd)가 겹치는 작업끼리만 차례로 한다(같은 대화·같은 폴더를 동시에 만지지 않게).
        #       세션이 다르거나, 같은 세션이어도 폴더가 서로 다르면(겹치지 않으면) 함께 돌린다. 동시에 도는 수는 $MaxParallel 까지.
        $claims = @(Get-RunningClaims)
        if ($script:Stopping) {
            if ($claims.Count -eq 0) {
                Log "실행 중이던 작업이 모두 끝나 정상 종료합니다."
                break
            }
        } else {
            $reserved = New-Object System.Collections.ArrayList
            foreach ($c in $claims) { [void]$reserved.Add(@{ Session = [string]$c.session; Cwds = @($c.cwds) }) }
            # 지금 돌고 있는(이번 점검에서 시작한 것 포함) 작업의 세션 이름: 같은 세션을 다른 폴더에서 또 시작할 때 경고하려고 든다
            $activeSessions = New-Object System.Collections.ArrayList
            foreach ($c in $claims) { if ([string]$c.session) { [void]$activeSessions.Add([string]$c.session) } }
            $runningIds = @($claims | ForEach-Object { [string]$_.task_id })
            $slots = $MaxParallel - $claims.Count

            $files = @(Get-ChildItem -Path $InboxDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in ".txt", ".md" } |
                Sort-Object CreationTime)

            # 사라진 파일의 기록은 버린다
            foreach ($seenKey in @($script:SeenFiles.Keys)) {
                if (-not (Test-Path -LiteralPath $seenKey)) { $script:SeenFiles.Remove($seenKey) }
            }

            foreach ($file in $files) {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ($runningIds -contains $baseName) { continue }

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

                # 이 작업의 세션·폴더(세션에 저장된 폴더 포함)를 읽는다
                $taskSession = ""
                $taskCwds = @()
                try {
                    $rawText = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                    $dir = ConvertFrom-TaskDirectives $rawText
                    $taskSession = [string]$dir.Session
                    $taskCwds = @($dir.Cwd)
                    if ($taskSession) {
                        $sess = Read-Session $taskSession
                        if ($sess) { $taskCwds = @(Resolve-TaskCwds $taskCwds $sess.cwd) }
                    }
                } catch {}

                $conflict = $false
                foreach ($r in $reserved) {
                    if (Test-TaskConflict $taskSession $taskCwds $r.Session $r.Cwds) { $conflict = $true; break }
                }
                # 시작하지 못하는 작업도 자리를 잡아 둔다: 같은 세션·폴더의 뒤 작업이 앞질러 시작하지 않게
                [void]$reserved.Add(@{ Session = $taskSession; Cwds = $taskCwds })
                if ($conflict -or $slots -le 0) { continue }

                if (Start-InboxWorker $file $taskSession $taskCwds) {
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



        # 핸드오프 자동 이어가기: 5초마다 채널을 점검한다(정지 중에는 새 일을 시작하지 않는다). 어떤 오류도 워처를 멈추지 않는다.
        if ($script:HandoffPumpReady -and -not $script:Stopping -and ((Get-Date) - $script:LastHandoffPumpAt).TotalSeconds -ge 5) {
            $script:LastHandoffPumpAt = Get-Date
            try {
                Invoke-HandoffPump @{ InboxDir = $InboxDir; OutboxDir = $OutboxDir; DbPath = $AgyDbPath }
            } catch {}
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

            Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue

        }

        Remove-Item -Path $HeartbeatFile -Force -ErrorAction SilentlyContinue

    } catch {}



    if (-not $global:AgyWatcherExitLogged) {

        $global:AgyWatcherExitLogged = $true

        Log "------------------------------------------------------------"

        Log "===== 워처 종료 (Ctrl+C 또는 스크립트 종료) ====="

        Log "------------------------------------------------------------"

    }

}

