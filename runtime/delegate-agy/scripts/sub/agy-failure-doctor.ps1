# agy-failure-doctor.ps1
# WP-Doctor: 위임 실패·취소 자동 분류, 진단 요약, 처리 표시(ack), 자가 개선 위임 브리프 생성 모듈.
# 뷰어(serve-viewer.ps1), CLI(diagnose-failures.ps1), 세션 시작 훅(session-start-hook.ps1)에서 dot-source 해서 사용합니다.
# 주의: dot-source 시 부작용이 없도록 상수·함수 정의만 포함합니다.

$script:AgyFailureRuleVersion = 2

function Ensure-AgyDbLoaded {
    if (-not (Get-Command Open-AgyDb -ErrorAction SilentlyContinue) -or -not (Get-Command Open-AgyDbReadOnly -ErrorAction SilentlyContinue)) {
        $dbLib = Join-Path $PSScriptRoot 'agy-db.ps1'
        if (Test-Path -LiteralPath $dbLib -PathType Leaf) { . $dbLib }
    }
}

function Get-AgyDoctorProp {
    param(
        $Record,
        [string[]]$Names,
        $Default = $null
    )
    if ($null -eq $Record) { return $Default }
    foreach ($name in $Names) {
        if ($Record -is [System.Collections.IDictionary]) {
            if ($Record.Contains($name)) {
                $val = $Record[$name]
                if ($null -ne $val -and -not ($val -is [DBNull])) { return $val }
            }
            foreach ($k in $Record.Keys) {
                if ([string]::Equals([string]$k, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $val = $Record[$k]
                    if ($null -ne $val -and -not ($val -is [DBNull])) { return $val }
                }
            }
        } else {
            $prop = $Record.PSObject.Properties[$name]
            if ($null -ne $prop -and $null -ne $prop.Value -and -not ($prop.Value -is [DBNull])) {
                return $prop.Value
            }
        }
    }
    return $Default
}

function ConvertTo-AgyDoctorDouble {
    param($Value, [double]$Default = 0)
    if ($null -eq $Value -or $Value -is [DBNull]) { return $Default }
    $s = ([string]$Value).Trim()
    if (-not $s) { return $Default }
    $parsed = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function ConvertTo-AgyDoctorUtcDateTime {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $null
    }
    if ($parsed.Kind -eq [System.DateTimeKind]::Utc) { return $parsed }
    if ($parsed.Kind -eq [System.DateTimeKind]::Local) { return $parsed.ToUniversalTime() }
    return [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Local).ToUniversalTime()
}

function ConvertTo-AgyDoctorLocalDateTime {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $null
    }
    if ($parsed.Kind -eq [System.DateTimeKind]::Utc) { return $parsed.ToLocalTime() }
    return $parsed
}

function Get-AgyFailureAnswerHead {
    param([string]$AnswerText)
    if ([string]::IsNullOrWhiteSpace($AnswerText)) { return '' }
    $lines = @($AnswerText -split "\r?\n")
    $idx = 0
    # 맨 앞의 '>' 로 시작하는 경고 줄(및 직후 빈 줄)은 건너뛰고 실제 첫 문단만 판정에 쓴다.
    while ($idx -lt $lines.Count) {
        $trimmed = $lines[$idx].TrimStart()
        if ($trimmed.StartsWith('>') -or [string]::IsNullOrWhiteSpace($lines[$idx])) {
            $idx++
        } else {
            break
        }
    }
    $head = New-Object System.Collections.Generic.List[string]
    while ($idx -lt $lines.Count) {
        if ([string]::IsNullOrWhiteSpace($lines[$idx])) { break }
        [void]$head.Add($lines[$idx])
        $idx++
    }
    $joined = ($head -join "`n").Trim()
    if ($joined.Length -gt 800) { $joined = $joined.Substring(0, 800) }
    return $joined
}

function Get-AgyFailureCategoryMeta {
    param([string]$Category)
    switch ($Category) {
        'user_cancelled' {
            return @{
                label          = '사용자 취소'
                severity       = 'low'
                root_cause     = '사용자 요청으로 위임이 취소되었습니다.'
                recommendation = '조치 불필요(정상적인 사용자 취소).'
            }
        }
        'brief_problem' {
            return @{
                label          = '브리프 문제'
                severity       = 'high'
                root_cause     = '브리프 변수 확장, 잘못된 @cwd/@model 지정 또는 필수 정보 부족으로 실패했습니다.'
                recommendation = "브리프는 따옴표 있는 here-doc(<<'EOF')으로 보내고 @cwd · @model 값을 확인한다."
            }
        }
        'content_blocked' {
            return @{
                label          = '안전 필터 차단'
                severity       = 'medium'
                root_cause     = '모델의 콘텐츠 안전 필터 또는 사용 정책 제한에 걸려 응답이 차단되었습니다.'
                recommendation = '브리프 표현과 입력 파일 내용을 점검해 정책에 걸릴 수 있는 문구를 다듬은 뒤 재시도하세요.'
            }
        }
        'quota_exhausted' {
            return @{
                label          = '한도 소진'
                severity       = 'high'
                root_cause     = '계정 또는 모델의 API 사용 한도(429 / RESOURCE_EXHAUSTED)가 소진되었습니다.'
                recommendation = '재설정 시각까지 부계정 · 다른 한도 묶음 모델로 보내거나 직접 처리. 워처는 소진 뒤 같은 묶음 폴백을 건너뛰고 표시 파일로 바로 실패한다.'
            }
        }
        'server_overloaded' {
            return @{
                label          = '서버 과부하(503)'
                severity       = 'medium'
                root_cause     = '백엔드 서버가 일시적으로 과부하(503 / UNAVAILABLE / No capacity) 상태입니다.'
                recommendation = '잠시 뒤 재시도, @model 을 모델 이름 하나로 고정하지 말고 단계 이름으로 보내 폴백을 허용.'
            }
        }
        'model_error' {
            return @{
                label          = '모델 오류 · 400'
                severity       = 'high'
                root_cause     = '지정한 모델이 가용 목록에 없거나 요청 인자 오류(400 / INVALID_ARGUMENT)로 거부되었습니다.'
                recommendation = 'agy models 로 가용 목록 갱신, models.json · models.local.json 단계 모델 확인.'
            }
        }
        'transient_backend' {
            return @{
                label          = '일시 오류'
                severity       = 'low'
                root_cause     = '에이전트 백엔드 연결 끊김, 스트림 중단 또는 일시적 인증 지연이 발생했습니다.'
                recommendation = '잠시 뒤 같은 작업을 재시도하고, 반복되면 agy 로그인 및 네트워크 상태를 확인하세요.'
            }
        }
        'watcher_problem' {
            return @{
                label          = '워처 · 작업자 문제'
                severity       = 'high'
                root_cause     = '워처 또는 작업자 프로세스가 예기치 않게 종료되거나 결과 없이 중단되었습니다.'
                recommendation = "watcher.log 의 작업 ID 줄과 '작업자 오류' 줄 확인, 워처 재시작."
            }
        }
        'timeout' {
            return @{
                label          = '시간 초과'
                severity       = 'medium'
                root_cause     = '최대 대기 시간 또는 실행 시간 한도를 넘겨 작업이 중단/취소되었습니다.'
                recommendation = '작업을 더 작은 단위로 분할하거나 대기 시간 설정을 확인한 뒤 재시도하세요.'
            }
        }
        'stalled' {
            return @{
                label          = '멈춤'
                severity       = 'medium'
                root_cause     = '일정 시간 동안 작업 진행이나 응답이 없어 멈춤으로 중단되었습니다.'
                recommendation = 'watcher.log 와 진행 기록을 확인하고 작업을 작은 단위로 나눠 재시도하세요.'
            }
        }
        'account_problem' {
            return @{
                label          = '계정 · 부계정 문제'
                severity       = 'medium'
                root_cause     = '부계정 오프라인 · 미로그인 또는 주 계정 폴백 차단으로 작업을 실행할 수 없습니다.'
                recommendation = '부계정 로그인 상태(switch-sub-agy.ps1)와 계정 풀 폴백 설정을 확인하세요.'
            }
        }
        default {
            return @{
                label          = '미분류'
                severity       = 'low'
                root_cause     = '알려진 실패·취소 패턴과 일치하지 않는 오류입니다.'
                recommendation = '답 전문과 watcher.log 를 보고 분류 규칙 추가 검토.'
            }
        }
    }
}

function Get-AgyFailureCategory {
    param($Record)

    if ($null -eq $Record) { return $null }
    $status = ([string](Get-AgyDoctorProp $Record @('status') '')).Trim().ToUpperInvariant()
    if ($status -eq 'OK') { return $null }

    $errText = [string](Get-AgyDoctorProp $Record @('error') '')
    $ansText = [string](Get-AgyDoctorProp $Record @('answer') '')
    $noteText = [string](Get-AgyDoctorProp $Record @('account_note') '')
    $questionText = [string](Get-AgyDoctorProp $Record @('question', 'summary') '')
    $cwdText = [string](Get-AgyDoctorProp $Record @('cwd') '')

    $ansHead = Get-AgyFailureAnswerHead $ansText
    $judgeParts = @($ansHead, $errText, $noteText) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $judgeText = ($judgeParts -join "`n").Trim()

    $detail = ''
    foreach ($ln in @($judgeText -split "\r?\n")) {
        $tr = $ln.Trim()
        if ($tr) { $detail = $tr; break }
    }
    if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) }

    $category = 'unknown'
    if ($judgeText -match '사용자 요청으로 취소') {
        $category = 'user_cancelled'
    } elseif (($judgeText -match '(?im)지정한 @cwd 경로를 찾을 수 없습니다|지정한 @model 을 쓸 수 없습니다|^\[NEED INFO\]|지시문 점검|brief.?lint') -or ($cwdText -match '\$[A-Za-z_]') -or ($questionText -match '(?im)^@cwd\b[^\r\n]*\$[A-Za-z_]')) {
        $category = 'brief_problem'
    } elseif ($judgeText -match '(?i)content safety|safety filters?|Prohibited Use') {
        $category = 'content_blocked'
    } elseif ($judgeText -match '(?i)Individual quota reached|RESOURCE_EXHAUSTED|\b429\b|rate.?limit|too many requests|quota (?:exceeded|reached|exhausted)|한도 소진') {
        $category = 'quota_exhausted'
    } elseif ($judgeText -match '(?i)UNAVAILABLE|code 503|\b503\b|No capacity|high traffic|overloaded') {
        $category = 'server_overloaded'
    } elseif ($judgeText -match '(?i)is not recognized as a known model|invalid model selection|\b400\b|INVALID_ARGUMENT|Bad Request') {
        $category = 'model_error'
    } elseif ($judgeText -match '(?i)empty conversation id|authentication failed or timed out|stream was interrupted|connection (?:reset|closed)') {
        $category = 'transient_backend'
    } elseif ($judgeText -match '끝내지 못하고 사라졌습니다|작업자가 시작한 뒤 결과 없이|작업자 오류|작업자를 띄우지 못했|워처가 (?:꺼|멈)|agy 실행 중 오류') {
        $category = 'watcher_problem'
    } elseif ($judgeText -match '(?i)최대 대기 시간[^\r\n]*넘겨 중단|지나도 끝나지 않아 취소|timed out|시간 초과') {
        $category = 'timeout'
    } elseif ($judgeText -match '진행이 없어 취소|후에도 멈춤|응답 없이[^\r\n]*멈춰|멈춤 확인') {
        $category = 'stalled'
    } elseif ($judgeText -match '(?i)부계정[^\r\n]*(?:사용할 수 없|오프라인|로그인)|fallback_to_primary=false') {
        $category = 'account_problem'
    }

    $meta = Get-AgyFailureCategoryMeta $category
    return [pscustomobject]@{
        category       = $category
        label          = $meta.label
        severity       = $meta.severity
        root_cause     = $meta.root_cause
        recommendation = $meta.recommendation
        detail         = $detail
    }
}

function Update-AgyFailureRecords {
    param(
        [string]$DbPath = '',
        [datetime]$NowUtc = [datetime]::UtcNow,
        [int]$BusyMs = 10000
    )

    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return 0 }
    Ensure-AgyDbLoaded

    $utcNow = $NowUtc.ToUniversalTime()
    $nowIso = $utcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $cutoffUtc = $utcNow.AddDays(-3)

    $db = Open-AgyDb $DbPath $BusyMs
    try {
        $changed = Invoke-AgyDbTransaction $db {
            $backfilledVal = Get-AgyMeta $db 'failures_backfilled'
            $doBackfill = [string]::IsNullOrWhiteSpace($backfilledVal)

            $sql = @"
SELECT t.task_id, t.timestamp, t.status, t.question, t.answer, t.account_note, t.elapsed_sec, t.model, t.account,
       tf.acked_at AS tf_acked_at, tf.ack_note AS tf_ack_note
FROM tasks t
LEFT JOIN task_failures tf ON tf.task_id = t.task_id
WHERE UPPER(COALESCE(t.status, '')) IN ('ERROR', 'CANCELLED', 'BLOCKED')
  AND (tf.task_id IS NULL OR (tf.acked_at IS NULL AND COALESCE(tf.rule_version, 0) < ?))
"@
            $rows = @($db.Query($sql, [object[]]@([int]$script:AgyFailureRuleVersion)))
            $n = 0
            foreach ($r in $rows) {
                $tId = if ($r['task_id']) { [string]$r['task_id'] } else { '' }
                if (-not $tId) { continue }
                $failedAt = if ($null -ne $r['timestamp']) { [string]$r['timestamp'] } else { '' }
                $recObj = @{
                    task_id      = $tId
                    status       = if ($r['status']) { ([string]$r['status']).Trim().ToUpperInvariant() } else { 'ERROR' }
                    answer       = if ($r['answer']) { [string]$r['answer'] } else { '' }
                    question     = if ($r['question']) { [string]$r['question'] } else { '' }
                    account_note = if ($r['account_note']) { [string]$r['account_note'] } else { '' }
                    elapsed_sec  = ConvertTo-AgyDoctorDouble $r['elapsed_sec'] 0
                    model        = if ($r['model']) { [string]$r['model'] } else { '' }
                    account      = if ($r['account']) { [string]$r['account'] } else { '' }
                }
                $diag = Get-AgyFailureCategory $recObj
                if ($null -eq $diag) { continue }

                $ackedAt = if ($null -ne $r['tf_acked_at'] -and [string]$r['tf_acked_at'] -ne '') { [string]$r['tf_acked_at'] } else { $null }
                $ackNote = if ($null -ne $r['tf_ack_note'] -and [string]$r['tf_ack_note'] -ne '') { [string]$r['tf_ack_note'] } else { $null }

                if ($null -eq $ackedAt) {
                    if ($diag.category -eq 'user_cancelled') {
                        $ackedAt = $nowIso
                        if (-not $ackNote) { $ackNote = '사용자 취소(자동 처리)' }
                    } elseif ($doBackfill -and $failedAt) {
                        $fUtc = ConvertTo-AgyDoctorUtcDateTime $failedAt
                        if ($null -ne $fUtc -and $fUtc -lt $cutoffUtc) {
                            $ackedAt = $nowIso
                            if (-not $ackNote) { $ackNote = '도입 전 기록(자동 처리)' }
                        }
                    }
                }

                [void]$db.Execute(
                    'INSERT OR REPLACE INTO task_failures (task_id, category, label, detail, failed_at, classified_at, rule_version, acked_at, ack_note) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [object[]]@($tId, $diag.category, $diag.label, $diag.detail, $failedAt, $nowIso, [int]$script:AgyFailureRuleVersion, $ackedAt, $ackNote)
                )
                $n++
            }

            if ($doBackfill) {
                Set-AgyMeta $db 'failures_backfilled' $nowIso
            }
            return $n
        }
        return [int]$changed
    } finally {
        $db.Dispose()
    }
}

function Build-AgyFailureInboxFromDb {
    param(
        $Db,
        [int]$Days = 30
    )
    if ($Days -lt 1) { $Days = 1 }
    $hasTable = @($Db.Query("SELECT 1 AS ok FROM sqlite_master WHERE type='table' AND name='task_failures' LIMIT 1", $null))
    if ($hasTable.Count -eq 0) {
        return [pscustomobject]@{ total = 0; categories = @() }
    }
    $rows = @($Db.Query("SELECT task_id, category, label, failed_at FROM task_failures WHERE acked_at IS NULL ORDER BY failed_at DESC, task_id DESC", $null))
    $cutoffLocal = (Get-Date).AddDays(-$Days)
    $groups = @{}
    $total = 0
    foreach ($r in $rows) {
        $failedAt = if ($null -ne $r['failed_at']) { [string]$r['failed_at'] } else { '' }
        if ($failedAt) {
            $localDt = ConvertTo-AgyDoctorLocalDateTime $failedAt
            if ($null -ne $localDt -and $localDt -lt $cutoffLocal) { continue }
        }
        $total++
        $cat = [string]$r['category']
        $meta = Get-AgyFailureCategoryMeta $cat
        $lbl = if ($null -ne $r['label'] -and [string]$r['label']) { [string]$r['label'] } else { $meta.label }
        $tId = if ($null -ne $r['task_id']) { [string]$r['task_id'] } else { '' }
        if (-not $groups.ContainsKey($cat)) {
            $groups[$cat] = @{
                category       = $cat
                label          = $lbl
                count          = 0
                latest_at      = $failedAt
                task_ids       = (New-Object System.Collections.Generic.List[string])
                recommendation = $meta.recommendation
            }
        }
        $g = $groups[$cat]
        $g.count++
        if (-not $g.latest_at -and $failedAt) { $g.latest_at = $failedAt }
        if ($tId -and $g.task_ids.Count -lt 3 -and -not $g.task_ids.Contains($tId)) {
            [void]$g.task_ids.Add($tId)
        }
    }
    $cats = @($groups.Values | ForEach-Object {
        [pscustomobject]@{
            category       = $_.category
            label          = $_.label
            count          = [int]$_.count
            latest_at      = $_.latest_at
            task_ids       = @($_.task_ids.ToArray())
            recommendation = $_.recommendation
        }
    } | Sort-Object -Property @{ Expression = { -$_.count } }, category)
    return [pscustomobject]@{
        total      = $total
        categories = @($cats)
    }
}

function Get-AgyFailureInbox {
    param(
        [string]$DbPath = '',
        [int]$Days = 30,
        [int]$BusyMs = 3000
    )
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) {
        return [pscustomobject]@{ total = 0; categories = @() }
    }
    Ensure-AgyDbLoaded
    $db = Open-AgyDbReadOnly $DbPath $BusyMs
    try {
        return (Build-AgyFailureInboxFromDb $db $Days)
    } finally {
        $db.Dispose()
    }
}

function Ensure-AgyFailureAckStatusColumn {
    param($Db)
    if ($null -eq $Db) { return }
    $hasTable = @($Db.Query("SELECT 1 AS ok FROM sqlite_master WHERE type='table' AND name='task_failures' LIMIT 1", $null))
    if ($hasTable.Count -eq 0) { return }
    $cols = @($Db.Query("PRAGMA table_info(task_failures)", $null))
    $hasCol = $false
    foreach ($c in $cols) {
        if ($c['name'] -and [string]::Equals([string]$c['name'], 'ack_status', [System.StringComparison]::OrdinalIgnoreCase)) {
            $hasCol = $true
            break
        }
    }
    if (-not $hasCol) {
        [void]$Db.Execute("ALTER TABLE task_failures ADD COLUMN ack_status TEXT", $null)
    }
}

function Set-AgyFailureAck {
    param(
        [string]$DbPath = '',
        [string[]]$TaskId = @(),
        [string[]]$Category = @(),
        [switch]$All,
        [string]$Note = '',
        [string]$Status = 'resolved',
        [datetime]$NowUtc = [datetime]::UtcNow,
        [int]$BusyMs = 10000
    )
    $cleanIds = @($TaskId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
    $cleanCats = @($Category | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
    if (-not $All -and $cleanIds.Count -eq 0 -and $cleanCats.Count -eq 0) { return 0 }
    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return 0 }

    $normStatus = if ([string]::IsNullOrWhiteSpace($Status)) { 'resolved' } else { $Status.Trim().ToLowerInvariant() }
    if ($normStatus -notin @('resolved', 'failed', 'open')) { $normStatus = 'resolved' }

    Ensure-AgyDbLoaded
    $nowIso = $NowUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $noteVal = if ([string]::IsNullOrWhiteSpace($Note)) { $null } else { $Note.Trim() }

    $db = Open-AgyDb $DbPath $BusyMs
    try {
        $changed = Invoke-AgyDbTransaction $db {
            $hasTable = @($db.Query("SELECT 1 AS ok FROM sqlite_master WHERE type='table' AND name='task_failures' LIMIT 1", $null))
            if ($hasTable.Count -eq 0) { return 0 }
            Ensure-AgyFailureAckStatusColumn $db

            $whereParts = New-Object System.Collections.Generic.List[string]
            $bindArgs = New-Object System.Collections.Generic.List[object]

            if ($normStatus -eq 'open') {
                [void]$whereParts.Add('acked_at IS NOT NULL')
            } elseif ($normStatus -eq 'resolved') {
                [void]$whereParts.Add("(acked_at IS NULL OR COALESCE(ack_status, '') = 'failed')")
                [void]$bindArgs.Add($nowIso)
                [void]$bindArgs.Add($normStatus)
                [void]$bindArgs.Add($noteVal)
            } else {
                [void]$whereParts.Add("COALESCE(ack_status, '') <> 'failed'")
                [void]$bindArgs.Add($nowIso)
                [void]$bindArgs.Add($normStatus)
                [void]$bindArgs.Add($noteVal)
            }

            if (-not $All) {
                if ($cleanIds.Count -gt 0) {
                    $marks = (@($cleanIds | ForEach-Object { '?' }) -join ',')
                    [void]$whereParts.Add("task_id IN ($marks)")
                    foreach ($id in $cleanIds) { [void]$bindArgs.Add($id) }
                }
                if ($cleanCats.Count -gt 0) {
                    $marks = (@($cleanCats | ForEach-Object { '?' }) -join ',')
                    [void]$whereParts.Add("category IN ($marks)")
                    foreach ($c in $cleanCats) { [void]$bindArgs.Add($c) }
                }
            }

            if ($normStatus -eq 'open') {
                $sql = "UPDATE task_failures SET acked_at = NULL, ack_status = NULL, ack_note = NULL WHERE " + ($whereParts -join ' AND ')
            } else {
                $sql = "UPDATE task_failures SET acked_at = ?, ack_status = ?, ack_note = ? WHERE " + ($whereParts -join ' AND ')
            }
            return $db.Execute($sql, $bindArgs.ToArray())
        }
        return [int]$changed
    } finally {
        $db.Dispose()
    }
}

function Get-AgyFailureDiagnosticsMap {
    param([object[]]$Records)
    $map = @{}
    if ($null -eq $Records) { return $map }
    foreach ($rec in @($Records)) {
        if ($null -eq $rec) { continue }
        $id = [string](Get-AgyDoctorProp $rec @('task_id', 'id') '')
        if (-not $id) { continue }
        $existingCat = [string](Get-AgyDoctorProp $rec @('category') '')
        if ($existingCat) {
            $map[$id] = @{
                category       = $existingCat
                label          = [string](Get-AgyDoctorProp $rec @('label') '')
                root_cause     = [string](Get-AgyDoctorProp $rec @('root_cause') '')
                recommendation = [string](Get-AgyDoctorProp $rec @('recommendation') '')
                detail         = [string](Get-AgyDoctorProp $rec @('detail') '')
            }
            continue
        }
        $diag = Get-AgyFailureCategory $rec
        if ($null -eq $diag) { continue }
        $map[$id] = @{
            category       = $diag.category
            label          = $diag.label
            root_cause     = $diag.root_cause
            recommendation = $diag.recommendation
            detail         = $diag.detail
        }
    }
    return $map
}

function Get-AgySuspectedFilesForCategory {
    param([string]$Category)
    switch ($Category) {
        'quota_exhausted'   { return @('runtime/delegate-agy/scripts/sub/agy-models.ps1', 'runtime/delegate-agy/scripts/sub/watch-agy.ps1') }
        'server_overloaded' { return @('runtime/delegate-agy/scripts/sub/agy-models.ps1', 'runtime/delegate-agy/scripts/sub/watch-agy.ps1') }
        'model_error'       { return @('runtime/delegate-agy/scripts/sub/agy-models.ps1', 'runtime/delegate-agy/scripts/sub/watch-agy.ps1') }
        'watcher_problem'   { return @('runtime/delegate-agy/scripts/sub/watch-agy.ps1', 'runtime/delegate-agy/scripts/sub/agy-progress.ps1', 'runtime/delegate-agy/scripts/submit-task.ps1') }
        'stalled'           { return @('runtime/delegate-agy/scripts/sub/watch-agy.ps1', 'runtime/delegate-agy/scripts/sub/agy-progress.ps1', 'runtime/delegate-agy/scripts/submit-task.ps1') }
        'timeout'           { return @('runtime/delegate-agy/scripts/sub/watch-agy.ps1', 'runtime/delegate-agy/scripts/sub/agy-progress.ps1', 'runtime/delegate-agy/scripts/submit-task.ps1') }
        'brief_problem'     { return @('runtime/delegate-agy/scripts/sub/agy-brief-lint.ps1', 'runtime/delegate-agy/scripts/submit-task.ps1') }
        'account_problem'   { return @('runtime/delegate-agy/scripts/sub/agy-sub-bridge.ps1') }
        'transient_backend' { return @('runtime/delegate-agy/scripts/sub/agy-sub-bridge.ps1', 'runtime/delegate-agy/scripts/sub/watch-agy.ps1') }
        'content_blocked'   { return @('runtime/delegate-agy/scripts/submit-task.ps1') }
        'user_cancelled'    { return @() }
        default             { return @('runtime/delegate-agy/scripts/sub/watch-agy.ps1') }
    }
}

function Format-AgyFixBrief {
    param($Diagnostics)
    if ($null -eq $Diagnostics) { return '' }
    $totalFailed = [int](Get-AgyDoctorProp $Diagnostics @('total_failed') 0)
    if ($totalFailed -le 0) { return '' }

    $days = [int](Get-AgyDoctorProp $Diagnostics @('days') 14)
    $countsByStatus = Get-AgyDoctorProp $Diagnostics @('counts_by_status') $null
    $errCnt = if ($countsByStatus) { [int](Get-AgyDoctorProp $countsByStatus @('ERROR') 0) } else { 0 }
    $canCnt = if ($countsByStatus) { [int](Get-AgyDoctorProp $countsByStatus @('CANCELLED') 0) } else { 0 }
    $blkCnt = if ($countsByStatus) { [int](Get-AgyDoctorProp $countsByStatus @('BLOCKED') 0) } else { 0 }

    $resSummary = Get-AgyDoctorProp $Diagnostics @('resolution_summary') $null
    $resResolved  = if ($resSummary) { [int](Get-AgyDoctorProp $resSummary @('resolved') 0) } else { 0 }
    $resFailed    = if ($resSummary) { [int](Get-AgyDoctorProp $resSummary @('failed') 0) } else { 0 }
    $resRemaining = if ($resSummary) { [int](Get-AgyDoctorProp $resSummary @('remaining') 0) } else { [int](Get-AgyDoctorProp $Diagnostics @('unacked_total') $totalFailed) }

    $samples = @(Get-AgyDoctorProp $Diagnostics @('samples', 'records') @())
    $actionableSamples = @($samples | Where-Object {
        $null -ne $_ -and
        ([string](Get-AgyDoctorProp $_ @('category') '')) -ne 'user_cancelled' -and
        ([string](Get-AgyDoctorProp $_ @('ack_status') $(if ([bool](Get-AgyDoctorProp $_ @('acked') $false)) { 'resolved' } else { 'open' }))) -in @('open', 'failed')
    })

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# WP-Doctor 자가 개선 위임 브리프 (최근 ${days}일)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 1. 실패 · 처리 현황 요약")
    [void]$sb.AppendLine(("- 총 실패/취소/차단: {0}건 (ERROR={1}, CANCELLED={2}, BLOCKED={3})" -f $totalFailed, $errCnt, $canCnt, $blkCnt))
    [void]$sb.AppendLine(("- 처리 상태: 완료 {0}건 · 처리 실패 {1}건 · 남은 건 {2}건" -f $resResolved, $resFailed, $resRemaining))

    # 미처리(남은 건)와 처리 실패 건이 모두 없으면 과거 완료 건을 중복 지시하지 않는다.
    if ($samples.Count -gt 0 -and $actionableSamples.Count -eq 0 -and $resRemaining -le 0 -and $resFailed -le 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## 2. 조치 필요 항목")
        [void]$sb.AppendLine("- 현재 처리할 남은 실패·취소 항목이 없습니다. (최근 ${days}일 기록 ${totalFailed}건 모두 처리 완료)")
        return $sb.ToString().TrimEnd()
    }

    $suspected = New-Object System.Collections.Generic.List[string]
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 2. 조치 대상 원인 분류 (미처리 · 처리 실패만)")

    if ($actionableSamples.Count -gt 0) {
        $actGroups = @{}
        foreach ($s in $actionableSamples) {
            $cKey = [string](Get-AgyDoctorProp $s @('category') 'unknown')
            if (-not $actGroups.ContainsKey($cKey)) {
                $meta = Get-AgyFailureCategoryMeta $cKey
                $actGroups[$cKey] = @{
                    category       = $cKey
                    label          = [string](Get-AgyDoctorProp $s @('label') $meta.label)
                    severity       = [string](Get-AgyDoctorProp $s @('severity') $meta.severity)
                    root_cause     = [string](Get-AgyDoctorProp $s @('root_cause') $meta.root_cause)
                    recommendation = [string](Get-AgyDoctorProp $s @('recommendation') $meta.recommendation)
                    open_count     = 0
                    failed_count   = 0
                    items          = (New-Object System.Collections.Generic.List[object])
                }
            }
            $g = $actGroups[$cKey]
            $aSt = [string](Get-AgyDoctorProp $s @('ack_status') 'open')
            if ($aSt -eq 'failed') { $g.failed_count++ } else { $g.open_count++ }
            if ($g.items.Count -lt 3) { [void]$g.items.Add($s) }
        }
        $orderedAct = @($actGroups.Values | Sort-Object -Property @{ Expression = { -($_.open_count + $_.failed_count) } }, category)
        foreach ($g in $orderedAct) {
            $cntTotal = $g.open_count + $g.failed_count
            $stateText = if ($g.failed_count -gt 0 -and $g.open_count -gt 0) {
                "남은 $($g.open_count)건 · 처리 실패 $($g.failed_count)건"
            } elseif ($g.failed_count -gt 0) {
                "처리 실패 $($g.failed_count)건"
            } else {
                "남은 $($g.open_count)건"
            }
            [void]$sb.AppendLine(('- [{0}] **{1}** (`{2}`): {3}건 ({4})' -f $g.severity.ToUpperInvariant(), $g.label, $g.category, $cntTotal, $stateText))
            [void]$sb.AppendLine(("  - 추정 원인: {0}" -f $g.root_cause))
            [void]$sb.AppendLine(("  - 권장 조치: {0}" -f $g.recommendation))
            [void]$sb.AppendLine("  - 실제 오류 사례:")
            foreach ($it in $g.items) {
                $tid = [string](Get-AgyDoctorProp $it @('task_id', 'id') '')
                $catAt = [string](Get-AgyDoctorProp $it @('created_at') '')
                $det = ([string](Get-AgyDoctorProp $it @('detail') '') -replace '\r?\n', ' ').Trim()
                if ($det.Length -gt 160) { $det = $det.Substring(0, 157) + '...' }
                $stTag = if (([string](Get-AgyDoctorProp $it @('ack_status') 'open')) -eq 'failed') { '[처리 실패]' } else { '[미처리]' }
                [void]$sb.AppendLine(("    - {0} {1} · `{2}`: {3}" -f $stTag, $catAt, $tid, $det))
            }
            foreach ($sf in (Get-AgySuspectedFilesForCategory $g.category)) {
                if (-not $suspected.Contains($sf)) { [void]$suspected.Add($sf) }
            }
        }
    } else {
        # samples 가 비어 있는 합성 입력(단위 테스트 등) 폴백
        $byCategory = @(Get-AgyDoctorProp $Diagnostics @('by_category') @())
        foreach ($cat in $byCategory) {
            $cName = [string](Get-AgyDoctorProp $cat @('category') '')
            if ($cName -eq 'user_cancelled') { continue }
            $cLabel = [string](Get-AgyDoctorProp $cat @('label') '')
            $cCount = [int](Get-AgyDoctorProp $cat @('count') 0)
            $cSev = [string](Get-AgyDoctorProp $cat @('severity') 'low')
            $cCause = [string](Get-AgyDoctorProp $cat @('root_cause') '')
            $cRec = [string](Get-AgyDoctorProp $cat @('recommendation') '')
            $sampleIds = @((Get-AgyDoctorProp $cat @('sample_ids') @()) | ForEach-Object { [string]$_ } | Where-Object { $_ })
            $idText = if ($sampleIds.Count -gt 0) { ($sampleIds -join ', ') } else { '-' }
            [void]$sb.AppendLine(('- [{0}] **{1}** (`{2}`): {3}건' -f $cSev.ToUpperInvariant(), $cLabel, $cName, $cCount))
            [void]$sb.AppendLine(("  - 추정 원인: {0}" -f $cCause))
            [void]$sb.AppendLine(("  - 권장 조치: {0}" -f $cRec))
            [void]$sb.AppendLine(("  - 대표 작업 ID: {0}" -f $idText))
            foreach ($sf in (Get-AgySuspectedFilesForCategory $cName)) {
                if (-not $suspected.Contains($sf)) { [void]$suspected.Add($sf) }
            }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 3. 점검 대상 파일")
    foreach ($sf in $suspected) {
        [void]$sb.AppendLine(('- `{0}`' -f $sf))
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 4. 개선 및 결과 기록 지시사항")
    [void]$sb.AppendLine("1. 위 미처리·처리 실패 원인부터 실제 오류 사례와 점검 대상 파일의 방어 로직을 확인·수정하세요.")
    [void]$sb.AppendLine("2. 수정 후 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only <관련시험>`으로 회귀가 없음을 확인하세요.")
    [void]$sb.AppendLine("3. 처리 결과를 `diagnose-failures.ps1 -Ack -Category <분류> -Status resolved|failed -Note `"<조치 요약>`"`으로 기록하세요.")
    return $sb.ToString().TrimEnd()
}

function Invoke-AgyFailureDiagnostics {
    param(
        [string]$DbPath = '',
        [int]$Days = 14,
        [int]$Limit = 200,
        [string]$ViewerBaseUrl = ''
    )

    if ($Days -lt 1) { $Days = 1 }
    if ($Limit -lt 1) { $Limit = 1 }

    $nowUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $emptyResult = [pscustomobject]@{
        generated_at        = $nowUtc
        days                = $Days
        limit               = $Limit
        total_scanned       = 0
        total_failed        = 0
        counts_by_status    = [pscustomobject]@{ ERROR = 0; CANCELLED = 0; BLOCKED = 0 }
        by_category         = @()
        samples             = @()
        records             = @()
        unacked_total       = 0
        unacked_by_category = @()
        fix_brief           = ''
    }

    if (-not $DbPath -or -not (Test-Path -LiteralPath $DbPath -PathType Leaf)) {
        return $emptyResult
    }

    Ensure-AgyDbLoaded

    $db = Open-AgyDbReadOnly $DbPath
    $rows = @()
    $ackMap = @{}
    $inbox = [pscustomobject]@{ total = 0; categories = @() }
    try {
        $sql = "SELECT task_id, timestamp, model, tried_models, attempts, elapsed_sec, status, question, answer, process, account, fallback_from, account_note, updated_seq FROM tasks WHERE UPPER(COALESCE(status, '')) IN ('ERROR', 'CANCELLED', 'BLOCKED') ORDER BY timestamp DESC, updated_seq DESC"
        $rows = @($db.Query($sql, $null))

        $hasFailuresTable = @($db.Query("SELECT 1 AS ok FROM sqlite_master WHERE type='table' AND name='task_failures' LIMIT 1", $null))
        if ($hasFailuresTable.Count -gt 0) {
            $hasAckStatusCol = $false
            foreach ($ci in @($db.Query("PRAGMA table_info(task_failures)", $null))) {
                if ($ci['name'] -and [string]::Equals([string]$ci['name'], 'ack_status', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $hasAckStatusCol = $true; break
                }
            }
            $tfSql = if ($hasAckStatusCol) {
                "SELECT task_id, acked_at, ack_status, ack_note FROM task_failures"
            } else {
                "SELECT task_id, acked_at, NULL AS ack_status, ack_note FROM task_failures"
            }
            foreach ($tfRow in @($db.Query($tfSql, $null))) {
                $tfId = if ($null -ne $tfRow['task_id']) { [string]$tfRow['task_id'] } else { '' }
                if (-not $tfId) { continue }
                $ackedAtVal = if ($null -ne $tfRow['acked_at']) { [string]$tfRow['acked_at'] } else { '' }
                $ackStatusRaw = if ($null -ne $tfRow['ack_status']) { ([string]$tfRow['ack_status']).Trim().ToLowerInvariant() } else { '' }
                $ackNoteVal = if ($null -ne $tfRow['ack_note']) { [string]$tfRow['ack_note'] } else { '' }
                $isAckedRow = (-not [string]::IsNullOrWhiteSpace($ackedAtVal))
                $normAckSt = if (-not $isAckedRow) { 'open' } elseif ($ackStatusRaw -eq 'failed') { 'failed' } else { 'resolved' }
                $ackMap[$tfId] = @{
                    acked      = $isAckedRow
                    acked_at   = $ackedAtVal
                    ack_status = $normAckSt
                    ack_note   = $ackNoteVal
                }
            }
            $inbox = Build-AgyFailureInboxFromDb $db $Days
        }
    } finally {
        $db.Dispose()
    }

    $cutoffLocal = (Get-Date).AddDays(-$Days)
    $filtered = New-Object System.Collections.Generic.List[object]

    foreach ($r in $rows) {
        $tsStr = if ($r['timestamp']) { [string]$r['timestamp'] } else { '' }
        $include = $true
        if ($tsStr) {
            $localDt = ConvertTo-AgyDoctorLocalDateTime $tsStr
            if ($null -ne $localDt -and $localDt -lt $cutoffLocal) { $include = $false }
        }
        if ($include) {
            [void]$filtered.Add($r)
        }
    }

    $totalFailed = $filtered.Count
    $statusCounts = @{ ERROR = 0; CANCELLED = 0; BLOCKED = 0 }
    $catGroups = @{}
    $sampleList = New-Object System.Collections.Generic.List[object]
    $baseUrl = if ($ViewerBaseUrl) { $ViewerBaseUrl.TrimEnd('/') } else { '' }

    $idx = 0
    foreach ($r in $filtered) {
        $st = if ($r['status']) { ([string]$r['status']).Trim().ToUpperInvariant() } else { 'ERROR' }
        if ($statusCounts.ContainsKey($st)) { $statusCounts[$st]++ }

        $tId = if ($r['task_id']) { [string]$r['task_id'] } else { '' }
        $tsStr = if ($r['timestamp']) { [string]$r['timestamp'] } else { '' }
        $durSec = ConvertTo-AgyDoctorDouble $r['elapsed_sec'] 0
        $waitSec = 0
        if ($tId -match '^claude_(\d{9,11})_\d+' -and $tsStr) {
            try {
                $createdEpoch = [double]$Matches[1]
                $endEpoch = [double]([DateTimeOffset][datetime]::Parse($tsStr, [System.Globalization.CultureInfo]::InvariantCulture)).ToUnixTimeSeconds()
                $wCalc = $endEpoch - $durSec - $createdEpoch
                if ($wCalc -ge 0 -and $wCalc -lt 604800) { $waitSec = [int][Math]::Round($wCalc) }
            } catch {}
        }

        $recObj = @{
            task_id      = $tId
            status       = $st
            answer       = if ($r['answer']) { [string]$r['answer'] } else { '' }
            question     = if ($r['question']) { [string]$r['question'] } else { '' }
            account_note = if ($r['account_note']) { [string]$r['account_note'] } else { '' }
            elapsed_sec  = $durSec
            wait_sec     = $waitSec
            model        = if ($r['model']) { [string]$r['model'] } else { '' }
            account      = if ($r['account']) { [string]$r['account'] } else { '' }
        }
        $diag = Get-AgyFailureCategory $recObj
        $catKey = $diag.category

        if (-not $catGroups.ContainsKey($catKey)) {
            $catGroups[$catKey] = @{
                category       = $catKey
                label          = $diag.label
                severity       = $diag.severity
                count          = 0
                root_cause     = $diag.root_cause
                recommendation = $diag.recommendation
                sample_ids     = (New-Object System.Collections.Generic.List[string])
            }
        }
        $grp = $catGroups[$catKey]
        $grp.count++
        if ($tId -and $grp.sample_ids.Count -lt 5 -and -not $grp.sample_ids.Contains($tId)) {
            [void]$grp.sample_ids.Add($tId)
        }

        if ($idx -lt $Limit) {
            $rawExcerpt = if ($recObj.answer) { $recObj.answer } elseif ($recObj.account_note) { $recObj.account_note } else { $recObj.question }
            $excerpt = ($rawExcerpt -replace '\s+', ' ').Trim()
            if ($excerpt.Length -gt 180) { $excerpt = $excerpt.Substring(0, 177) + '...' }
            $viewerUrl = if ($baseUrl -and $tId) { "{0}/#/qa?task={1}" -f $baseUrl, [uri]::EscapeDataString($tId) } else { '' }

            $isAcked = $false
            $ackedAt = ''
            $ackStatus = 'open'
            $ackNote = ''
            if ($tId -and $ackMap.ContainsKey($tId)) {
                $isAcked = [bool]$ackMap[$tId].acked
                $ackedAt = [string]$ackMap[$tId].acked_at
                $ackStatus = [string]$ackMap[$tId].ack_status
                $ackNote = [string]$ackMap[$tId].ack_note
            }

            [void]$sampleList.Add([pscustomobject]@{
                id             = $tId
                task_id        = $tId
                status         = $st
                category       = $diag.category
                label          = $diag.label
                severity       = $diag.severity
                root_cause     = $diag.root_cause
                recommendation = $diag.recommendation
                detail         = $diag.detail
                bridge_slot    = $recObj.account
                tier           = $recObj.model
                wait_sec       = $waitSec
                duration_sec   = [int][Math]::Round($durSec)
                created_at     = $tsStr
                viewer_url     = $viewerUrl
                excerpt        = $excerpt
                acked          = $isAcked
                acked_at       = $ackedAt
                ack_status     = $ackStatus
                ack_note       = $ackNote
            })
        }
        $idx++
    }

    # user_cancelled 는 total 에는 포함하되 by_category 에서는 맨 뒤로 보낸다.
    $sortedCats = @($catGroups.Values | ForEach-Object {
        [pscustomobject]@{
            category       = $_.category
            label          = $_.label
            severity       = $_.severity
            count          = [int]$_.count
            root_cause     = $_.root_cause
            recommendation = $_.recommendation
            sample_ids     = @($_.sample_ids.ToArray())
        }
    } | Sort-Object -Property @{ Expression = { if ($_.category -eq 'user_cancelled') { 1 } else { 0 } } }, @{ Expression = { -$_.count } }, category)

    $samplesArr = @($sampleList.ToArray())
    $resResolvedCnt = 0
    $resFailedCnt = 0
    $resRemainingCnt = 0
    $handledList = New-Object System.Collections.Generic.List[object]
    foreach ($sItem in $samplesArr) {
        $stAck = [string]$sItem.ack_status
        if ($stAck -eq 'resolved') {
            $resResolvedCnt++
            [void]$handledList.Add($sItem)
        } elseif ($stAck -eq 'failed') {
            $resFailedCnt++
            [void]$handledList.Add($sItem)
        } else {
            $resRemainingCnt++
        }
    }
    $handledArr = @($handledList.ToArray() | Sort-Object -Property @{ Expression = { $_.acked_at }; Descending = $true }, @{ Expression = { $_.created_at }; Descending = $true } | Select-Object -First 50)
    $result = [pscustomobject]@{
        generated_at        = $nowUtc
        days                = $Days
        limit               = $Limit
        total_scanned       = $totalFailed
        total_failed        = $totalFailed
        counts_by_status    = [pscustomobject]@{
            ERROR     = $statusCounts['ERROR']
            CANCELLED = $statusCounts['CANCELLED']
            BLOCKED   = $statusCounts['BLOCKED']
        }
        resolution_summary  = [pscustomobject]@{
            total     = $totalFailed
            resolved  = $resResolvedCnt
            failed    = $resFailedCnt
            remaining = $resRemainingCnt
        }
        by_category         = @($sortedCats)
        samples             = $samplesArr
        records             = $samplesArr
        handled_records     = $handledArr
        unacked_total       = [int]$inbox.total
        unacked_by_category = @($inbox.categories)
        fix_brief           = ''
    }
    $result.fix_brief = Format-AgyFixBrief $result
    return $result
}
