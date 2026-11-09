# log-qa.ps1
# watch-agy.ps1가 관리하는 것과 같은 기록 저장소(data\delegate.db 의 tasks 표)에
# Q&A 한 건을 추가로 남깁니다. 워처(inbox 파일 위임) 경로를 거치지 않고
# 다른 통로(예: antigravity MCP 직접 호출)로 주고받은 질문/답변을 같은 웹 뷰어에서
# 함께 볼 수 있게 하기 위한 것입니다.
#
# watch-agy.ps1이 쓰는 기록과 구분할 수 있도록 모든 레코드에 "source" 필드를 남깁니다:
#   - "bridge" : inbox 파일 위임 -> watch-agy.ps1이 agy CLI를 호출한 기록
#   - "mcp"    : Claude가 antigravity MCP(ask_antigravity 등)를 직접 호출한 기록
#
# 이 기록은 토큰·소요시간 칸이 비어 있고 source 칸이 채워져 있습니다. 모델별 사용량 집계(tools\export-usage-csv.ps1 -Summary)는
# source 가 빈 행(워처가 실제 agy CLI 를 부른 작업)만 세므로, 성격이 다른 MCP 호출이 섞여 집계가 왜곡되지 않습니다.
#
# 사용법:
#   .\log-qa.ps1 -Source mcp -QuestionFile q.txt -AnswerFile a.txt -Model "Gemini 3.1 Pro High"

param(
    [string]$RepoRoot   = "",
    [string]$RuntimeDir = "",
    [Parameter(Mandatory = $true)][ValidateSet("mcp", "bridge")][string]$Source,
    [Parameter(Mandatory = $true)][string]$QuestionFile,
    [Parameter(Mandatory = $true)][string]$AnswerFile,
    [string]$Model  = "",
    [string]$Status = "OK",
    [string]$TaskId = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

# 참고: [Parameter(Mandatory=...)] 속성이 있는 "고급" 스크립트는 파라미터 바인딩 단계에서
# $PSScriptRoot가 아직 채워지지 않은 경우가 있어(watch-agy.ps1 등 단순 param 스크립트와
# 다른 점), 기본값 식이 아니라 본문에서 안전하게 다시 계산합니다.
if (-not $RepoRoot) {
    $root = $PSScriptRoot
    if (-not $root -and $MyInvocation.MyCommand.Path) { $root = Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
    $parent = Split-Path -Path $root -Parent
    if ((Split-Path -Leaf $root) -eq "sub") {
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
. (Join-Path $PSScriptRoot "agy-layout.ps1")
$AgyDbPath = (Get-AgyLayout $RuntimeDir).DbPath

if (-not (Test-Path $QuestionFile)) { throw "QuestionFile을 찾을 수 없습니다: $QuestionFile" }
if (-not (Test-Path $AnswerFile))   { throw "AnswerFile을 찾을 수 없습니다: $AnswerFile" }


if (-not $TaskId) {
    $rand = -join ((48..57 + 97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $TaskId = "{0}_{1}_{2}" -f $Source, (Get-Date -Format "yyyyMMdd_HHmmss"), $rand
}

# New-QaRecord / Truncate-Text 등은 watch-agy.ps1과 공유합니다
# (common.ps1 참고 - 두 곳에 복사해두면 한쪽만 고치고 놓치는 사고가 나기 쉽습니다).
$commonFile = Join-Path $PSScriptRoot "common.ps1"
if (-not (Test-Path $commonFile)) {
    $commonFile = Join-Path (Split-Path $PSScriptRoot -Parent) "common.ps1"
}
. $commonFile

# [string] 캐스팅이 중요합니다: Get-Content -Raw가 돌려주는 문자열에는 PSPath/PSProvider/
# PSDrive 같은 숨은 ETS NoteProperty가 붙어 있어서, 캐스팅 없이 그대로 해시테이블에 넣고
# ConvertTo-Json으로 직렬화하면 그 파일시스템 메타데이터(드라이브 정보 등)까지 깊이
# 재귀적으로 통째로 직렬화되어 몇십 MB짜리 레코드가 만들어집니다(실제로 겪은 사고).
$qText = [string](Get-Content -Raw -Path $QuestionFile -Encoding UTF8)
$aText = [string](Get-Content -Raw -Path $AnswerFile -Encoding UTF8)

$rec = New-QaRecord ([ordered]@{
    timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    computer_name = $env:COMPUTERNAME
    task_id       = $TaskId
    source        = $Source
    model         = $Model
    status        = $Status
    question      = $qText
    answer        = $aText
})

# 같은 작업 ID 가 이미 있으면 덮어쓰지 않고 오류로 알린다(InsertOnly). DB 를 잠깐 못 쓰면 pending 폴더에 두었다가 다음 기록 때 가져온다.
$result = Write-QaRecordToDb $AgyDbPath $rec 'InsertOnly'
if ($result -eq 'skipped') { throw "이미 존재하는 task_id입니다: $TaskId" }
$note = if ($result -eq 'pending') { " (DB 가 잠겨 있어 pending 폴더에 두었습니다. 다음 기록 때 가져옵니다)" } else { "" }
Write-Host "기록 저장: task_id=$TaskId source=$Source -> $AgyDbPath$note"

