# common.ps1
# watch-agy.ps1과 log-qa.ps1이 함께 쓰는 헬퍼 모음입니다(위임 기록 틀, 세션 연속성, 폴더 목록 규칙).
# dot-source해서 씁니다: `. (Join-Path $PSScriptRoot "common.ps1")`
#
# 기록과 세션은 SQLite(delegate-agy\data\delegate.db)에 있고, 접근은 같은 폴더의 agy-db.ps1 이 맡습니다. 이 파일은 그 위에 도메인 규칙만 얹습니다.
#
# 왜 따로 뺐는가: 예전에 이 함수들이 두 파일에 복사돼 있었는데, 한쪽만 고치고 다른 쪽을
# 놓치면 같은 버그(예: ETS 속성이 붙은 문자열을 그대로 직렬화해 레코드가 수십 MB로
# 부풀던 문제)가 조용히 재발할 수 있었습니다. 한 곳에서만 관리하도록 통합했습니다.
#
# 이 파일을 dot-source하는 스크립트는 아래 변수를 먼저 정의해 둬야 합니다:
#   $AgyDbPath  - data\delegate.db 경로

# DB 접근 모듈(agy-db.ps1). 이 파일과 같은 폴더에 있다.
$agyDbModule = Join-Path $PSScriptRoot "agy-db.ps1"
if (-not (Test-Path -LiteralPath $agyDbModule)) { $agyDbModule = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-db.ps1" }
. $agyDbModule

# PowerShell 5.1의 ConvertTo-Json은 한글 등 비ASCII 문자를 유니코드 이스케이프로 바꿔버려서
# 파일을 직접 열었을 때 읽을 수가 없습니다. 제어문자는 규격대로 그대로 두고 나머지만 실제
# 글자로 되돌려서, "메모장으로 열어도 바로 읽히는" JSON을 만듭니다.
function ConvertTo-ReadableJson($InputObject, [int]$Depth = 6, [switch]$Pretty) {
    try {
        $json = if ($Pretty) {
            ConvertTo-Json -InputObject $InputObject -Depth $Depth
        } else {
            ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress
        }
        if ($null -eq $json) { return "" }
        # 역슬래시가 짝수 개 앞선 \uXXXX 만 이스케이프 표기다. 홀수 개면 본문에 원래 있던
        # 글자(지시문 속 "\ufeff" 처럼)라, 바꾸면 역슬래시가 홀로 남아 그 줄 전체가 JSON 으로
        # 안 읽힌다. 큰따옴표 · 역슬래시도 글자로 풀면 문자열이 끊기므로 그대로 둔다.
        return [regex]::Replace($json, '(?<!\\)((?:\\\\)*)\\u([0-9a-fA-F]{4})', {
            param($m)
            $code = [Convert]::ToInt32($m.Groups[2].Value, 16)
            if ($code -lt 0x20 -or $code -eq 0x22 -or $code -eq 0x5C) { return $m.Value }
            return $m.Groups[1].Value + [string][char]$code
        })
    } catch {
        return ""
    }
}

# 글이 maxLen 을 넘으면 자르고 안내 문구를 붙인다. null 은 빈 문자열.
function Truncate-Text($s, [int]$maxLen) {
    if ($null -eq $s) { return "" }
    if ($s.Length -gt $maxLen) {
        return $s.Substring(0, $maxLen) + "`n... (내용이 길어 일부 생략됨 - 전체 내용은 outbox/processed 폴더의 원본 파일 참고)"
    }
    return $s
}

# 기록 저장소(agy.db 의 tasks 표)에 넣을 레코드 하나를 만든다. 쓰기 경로가 여럿(워처의 작업 마무리·워처 시작 때의 전체 동기화, log-qa.ps1)이라
# 레코드 모양이 따로 놀지 않도록 한 곳에서 만든다.
#  - 칸 순서는 아래 목록을 따르고, Values 에 있는 칸만 넣는다(예: source 는 log-qa 의 기록에만, 토큰 칸은 워처의 기록에만 있다)
#  - 모르는 칸 이름이 들어오면 오류다(오타로 칸이 조용히 빠지는 것을 막는다)
#  - 글 칸은 모두 [string] 으로 바꾼다: Get-Content -Raw 가 돌려주는 문자열에는 PSPath·PSDrive 같은 숨은 속성이 붙어 있어, 그대로 직렬화하면
#    파일시스템 정보까지 통째로 직렬화되어 몇십 MB 짜리 레코드가 된다(실제로 겪은 사고)
#  - question·answer 는 20000자로 자른다. process(도구 목록)는 있는 그대로 둔다("모름"=$null 과 "없음"=빈 배열을 구별하므로)
function New-QaRecord([System.Collections.IDictionary]$Values) {
    $fields = $script:QaRecordFields    # 칸 목록은 agy-db.ps1 에 있다(저장소와 뷰어 API 가 같은 목록을 쓴다)
    foreach ($k in $Values.Keys) {
        if ($fields -notcontains [string]$k) { throw "기록에 없는 칸 이름입니다: $k" }
    }
    $rec = [ordered]@{}
    foreach ($k in $fields) {
        if (-not $Values.Contains($k)) { continue }
        $v = $Values[$k]
        if ($k -eq 'process') { $rec[$k] = $v }
        elseif ($k -eq 'question' -or $k -eq 'answer') { $rec[$k] = (Truncate-Text ([string]$v) 20000) }
        else { $rec[$k] = [string]$v }
    }
    return $rec
}

# ============================================================================
# 세션 연속성 (@session: <이름>)
# ----------------------------------------------------------------------------
# agy는 매번 빈 상태로 시작하는 게 기본이지만, agy CLI 자체가 --conversation <id>로
# 대화를 이어갈 수 있는 기능을 지원합니다(응답 JSON의 conversation_id를 그대로 다음
# 호출에 넘기면 됨 - 2026-09 확인). 이 파일들은 "사람이 붙인 세션 이름" <-> "agy의
# conversation_id"를 매핑해서, 지시파일에 매번 긴 UUID를 안 적어도 되게 해줍니다.
#
# 세션 하나당 agy_sessions 표의 한 줄(agy.db)로 관리합니다. 작업자가 여럿 동시에 돌 수 있어서 읽고-고쳐-쓰는 구간(Write-Session)은
# DB 트랜잭션(BEGIN IMMEDIATE) 안에서 합니다. 예전의 세션 파일은 tools\migrate-to-sqlite.ps1 이 한 번에 가져옵니다.
#
# 대화가 만료/유실됐을 때: agy는 에러로 죽지 않고 조용히 새 conversation_id로
# 폴백합니다(직접 검증함 - 존재하지 않는 conversation_id를 줘도 exit 0, status
# SUCCESS로 새로 시작함). 그래서 우리 쪽에서 "이어붙이기 실패 시 재시도" 로직이
# 따로 필요 없고, 매 호출 후 응답의 conversation_id로 레지스트리를 덮어쓰기만
# 하면 자동으로 복구됩니다.
# ============================================================================

# 세션 정보를 읽습니다. 없거나 손상됐으면 $null (그러면 호출부는 "새 세션 시작"으로
# 처리하면 됩니다 - agy의 자체 폴백과 같은 방향이라 자연스럽게 맞물립니다).
function Read-Session([string]$Name) {
    try { return (Get-AgySession $AgyDbPath $Name) } catch { return $null }
}

# @cwd(작업 폴더) 값을 폴더 경로 배열로 바꿉니다. 문자열 하나(예전 세션 파일이나 @cwd 한 줄)든 배열(여러 폴더)이든 받고,
# 비어 있는 값과 중복(대소문자, 끝의 \ 또는 / 무시)은 뺍니다. 줄 순서는 유지합니다. 읽을 수 없는 값은 빈 배열.
# (뷰어의 serve-viewer.ps1 에 같은 규칙의 사본이 있습니다 - tests\delegate-agy\cwd-list.tests.ps1 이 둘이 같은지 확인합니다.)
function ConvertTo-CwdList($Value) {
    $out = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($v in @($Value)) {
        if ($null -eq $v) { continue }
        $s = ([string]$v).Trim()
        if (-not $s) { continue }
        $key = $s.TrimEnd([char]92, [char]47).ToLowerInvariant()
        if (-not $key) { $key = $s.ToLowerInvariant() }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$out.Add($s)
    }
    return @($out.ToArray())
}

# 이번 호출에 쓸 폴더 목록. 이번 지시파일에 @cwd 가 하나라도 있으면 이번 목록만 쓰고(세션의 폴더와 합치지 않는다),
# 하나도 없으면 세션에 저장된 목록을 이어서 쓴다(sticky). 세션의 값은 문자열(예전 파일)이든 배열이든 읽는다.
# 모델 승격(@upgrade)으로 새 대화를 시작할 때, 이전 대화의 마지막 질문·답을 글로 지시문 위에 붙인다.
# 새 대화는 이전 대화에서 agy 가 읽은 파일·도구 기록을 이어받지 못한다(그건 agy 쪽에만 있다). 질문·답 글만 넘기므로 필요한 파일은 agy 가 다시 읽어야 한다.
#   $History   Get-AgySessionHistory 의 결과(오래된 것부터)   $FromModel/$ToModel 모델 이름(없으면 빈 글자)   $Prompt 이번 지시문 본문
# 질문의 앞쪽 @지시어 줄은 떼고, 질문은 3000자·답은 6000자에서 자른다.
function New-AgyUpgradeContext($History, [string]$FromModel, [string]$ToModel, [string]$Prompt, [int]$MaxQuestion = 3000, [int]$MaxAnswer = 6000) {
    $from = if ($FromModel) { $FromModel } else { "기록 없음" }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[이전 대화 요약 — 모델을 올리면서($from -> $ToModel) 새 대화로 시작합니다. 이전 대화에서 읽은 파일과 도구 실행 기록은 이어지지 않으니, 필요한 파일은 다시 읽으세요. 아래는 같은 세션의 직전 질문과 답입니다.]")
    $items = @($History)
    if ($items.Count -eq 0) { [void]$sb.AppendLine("(이전 질문·답 기록을 찾지 못했습니다.)") }
    $i = 0
    foreach ($h in $items) {
        $i++
        $q = ([string]$h.Question -replace '^(\s*@\w+:[^\r\n]*\r?\n)+', '').Trim()
        if ($q.Length -gt $MaxQuestion) { $q = $q.Substring(0, $MaxQuestion) + "`n(... 이하 생략)" }
        $a = ([string]$h.Answer).Trim()
        if ($a.Length -gt $MaxAnswer) { $a = $a.Substring(0, $MaxAnswer) + "`n(... 이하 생략)" }
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("### 직전 질문 $i ($($h.Timestamp))")
        [void]$sb.AppendLine($q)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("### 직전 답 $i")
        [void]$sb.AppendLine($a)
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("[이전 대화 끝 — 아래가 이번 요청입니다]")
    [void]$sb.AppendLine("")
    return ($sb.ToString() + $Prompt)
}

function Resolve-TaskCwds($DirectiveCwds, $SessionCwd) {
    $own = @(ConvertTo-CwdList $DirectiveCwds)
    if ($own.Count -gt 0) { return $own }
    return @(ConvertTo-CwdList $SessionCwd)
}

# 없는 폴더만 골라 돌려줍니다(모두 있으면 빈 배열).
function Get-MissingCwds($Cwds) {
    $missing = @(@($Cwds) | Where-Object { $_ -and -not (Test-Path -LiteralPath $_) })
    return $missing
}

function Write-Session([string]$Name, [string]$ConversationId, [string[]]$Cwd, [string]$Model) {
    $key = Get-AgySessionKey $Name
    $db = Open-AgyDb $AgyDbPath
    try {
        # 읽고-고쳐-쓰는 구간을 한 트랜잭션으로 묶는다: 같은 세션을 두 작업자가 거의 동시에 마쳐도 횟수가 하나씩 늘어난다
        Invoke-AgyDbTransaction $db {
            $existing = Get-AgySessionRow $db $key
            $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $createdAt = if ($existing -and $existing.created_at) { [string]$existing.created_at } else { $now }
            $turnCount = 1
            if ($existing -and $existing.turn_count) { $turnCount = [int]$existing.turn_count + 1 }

            # 세션을 이어가는 호출은 실제 모델명을 모르고 "(session)" 자리표시자만 넘어옵니다
            # (watch-agy.ps1의 Invoke-AgyWithFallback 참고). 그걸 그대로 덮어쓰면 세션을 시작할 때
            # 기록해둔 진짜 모델명이 다음 호출부터 영영 사라지므로, 그럴 땐 기존 값을 유지합니다.
            $resolvedModel = $Model
            if ((-not $resolvedModel) -or ($resolvedModel -eq "(session)")) {
                if ($existing -and $existing.model) { $resolvedModel = [string]$existing.model }
            }
            Set-AgySessionRow $db $key $ConversationId @(ConvertTo-CwdList $Cwd) $resolvedModel $createdAt $now $turnCount
        }
    } finally { $db.Dispose() }
}

# 오래(기본 30일) 안 쓴 세션 파일은 정리합니다. qa-jsonl의 12개월 보관 정리와 같은 패턴.
function Remove-StaleSessions([int]$MaxAgeDays = 30) {
    try { [void](Remove-AgySessionsOlderThan $AgyDbPath $MaxAgeDays) } catch {}
}

# 여러 프로세스(워처, 작업자, log-qa.ps1)가 같은 파일을 만지므로, 쓰는 구간을 이 PC 전체에서
# 하나만 들어가게 이름 있는 뮤텍스로 묶는다. 런타임 폴더마다 이름이 달라서 다른 런타임(시험용 등)과는 서로 막지 않는다.
function Invoke-WithRuntimeLock([scriptblock]$Block, [int]$TimeoutSeconds = 60) {
    $baseDir = if ($RuntimeDir) { $RuntimeDir } elseif ($DataDir) { Split-Path (Split-Path $DataDir -Parent) -Parent } else { $PSScriptRoot }
    $sha = New-Object System.Security.Cryptography.SHA1Managed
    $hash = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseDir.ToLowerInvariant().TrimEnd('\', '/')))).Replace('-', '')
    $mutex = New-Object System.Threading.Mutex($false, "Local\samjil-agy-$hash")
    $got = $false
    try {
        try { $got = $mutex.WaitOne($TimeoutSeconds * 1000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        & $Block
    } finally {
        if ($got) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

