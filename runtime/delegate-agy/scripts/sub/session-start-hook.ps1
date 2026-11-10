# session-start-hook.ps1
# Claude Code SessionStart 훅: 새 세션이 시작될 때 agy 워처를 창 없이 켜고,
# Claude 에게 samjil-delegate-agy 스킬을 먼저 따르라는 문맥을 넣습니다(표준 출력이 세션 문맥이 됩니다).
#   - 워처가 이미 켜져 있으면 아무것도 켜지 않습니다.
#   - 사용자가 stop-agy 로 일부러 끈 상태(manual_stop.flag)면 켜지 않습니다.
#   - 켜는 일은 기다리지 않고 백그라운드로 맡겨, 세션 시작을 늦추지 않습니다.
#   - calibration.json 이 30분 이상 지났거나 없으면 token-stats.ps1 -Update 를 백그라운드로 띄웁니다.
#   - [토큰 예상] 줄을 출력해 최신 실측 보정 식을 알려 줍니다.
# 어떤 경우에도 오류로 세션 시작을 막지 않도록 항상 종료 코드 0 으로 끝납니다.
param(
    [string]$RuntimeDir = "",
    [string]$EnsureScript = "",
    [string]$TokenStatsScript = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $RuntimeDir) { $RuntimeDir = Join-Path $home_ ".samjil\delegate-agy\runtime" }
    if (-not $EnsureScript) { $EnsureScript = Join-Path $PSScriptRoot "ensure-agy-running.ps1" }
    if (-not $TokenStatsScript) { $TokenStatsScript = Join-Path $PSScriptRoot "token-stats.ps1" }

    $state = "UNKNOWN"
    if (Test-Path -LiteralPath $EnsureScript) {
        $check = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EnsureScript -RuntimeDir $RuntimeDir -CheckOnly -StaleThresholdSeconds 0 2>$null)
        $word = ((@($check) -join "").Trim())
        if ($word -in @("ALIVE", "DEAD", "MANUAL_STOP")) { $state = $word }
    }

    $watcherLine = switch ($state) {
        "ALIVE"       { "agy 워처: 켜져 있음." }
        "DEAD" {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$EnsureScript`"",
                "-RuntimeDir", "`"$RuntimeDir`"", "-ConfirmDelaySeconds", "0", "-StaleThresholdSeconds", "0") | Out-Null
            "agy 워처: 꺼져 있어 세션 시작 훅이 창 없이 켜는 중. 위임 직전에 ensure-agy-running.ps1 -CheckOnly 로 ALIVE 인지 다시 본다."
        }
        "MANUAL_STOP" { "agy 워처: 사용자가 일부러 꺼 둔 상태라 켜지 않았다. 위임하려면 켜도 되는지 먼저 묻는다." }
        default       { "agy 워처: 상태를 확인하지 못했다(런타임이 설치돼 있지 않을 수 있다). 위임 없이 직접 처리하고 install.ps1 실행을 안내한다." }
    }

    $layoutScript = Join-Path $PSScriptRoot "agy-layout.ps1"
    $dataDir = if (Test-Path -LiteralPath $layoutScript) {
        . $layoutScript
        Get-AgyDataDir $RuntimeDir
    } else {
        $trimmed = $RuntimeDir.TrimEnd('\', '/')
        if ((Split-Path -Leaf $trimmed) -eq "runtime") { Join-Path (Split-Path $trimmed -Parent) "data" } else { Join-Path $trimmed "data" }
    }

    $calFile = Join-Path $dataDir "calibration.json"
    $needUpdate = $true
    if (Test-Path -LiteralPath $calFile) {
        try {
            $age = (Get-Date) - (Get-Item -LiteralPath $calFile).LastWriteTime
            if ($age.TotalMinutes -lt 30) { $needUpdate = $false }
        } catch {}
    }

    if ($needUpdate -and (Test-Path -LiteralPath $TokenStatsScript)) {
        try {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$TokenStatsScript`"",
                "-Update", "-RuntimeDir", "`"$RuntimeDir`"") | Out-Null
        } catch {}
    }

    $cal = $null
    if (Test-Path -LiteralPath $calFile) {
        try {
            $raw = Get-Content -LiteralPath $calFile -Raw -Encoding UTF8
            if ($raw -and $raw.Trim()) { $cal = $raw | ConvertFrom-Json }
        } catch {}
    }

    $formatK = {
        param([double]$val)
        $k = $val / 1000.0
        if ($k -eq [Math]::Floor($k)) { return ("{0:0}k" -f $k) }
        else { return ("{0:0.#}k" -f $k) }
    }

    $dirA = 800.0; $dirB = 1300.0
    $delA = 2500.0; $delB = 1000.0
    $totalN = 0
    $isDefault = $true

    if ($null -ne $cal -and $null -ne $cal.direct -and $null -ne $cal.delegate) {
        try {
            $dirA = [double]$cal.direct.a
            $dirB = [double]$cal.direct.b
            $delA = [double]$cal.delegate.a
            $delB = [double]$cal.delegate.b
            $nDir = if ($cal.direct.n) { [int]$cal.direct.n } else { 0 }
            $nDel = if ($cal.delegate.n) { [int]$cal.delegate.n } else { 0 }
            $totalN = $nDir + $nDel
            $isDefault = ($cal.direct.source -eq "default" -and $cal.delegate.source -eq "default")
        } catch {}
    }

    $suffix = if ($isDefault) { " (아직 실측이 적어 기본값)" } else { "" }
    $kDirA = & $formatK $dirA
    $kDirB = & $formatK $dirB
    $kDelA = & $formatK $delA
    $kDelB = & $formatK $delB
    $tokenLine = "[토큰 예상] 최근 실측 {0}턴 기준 — 직접 ≈ {1} + {2} × 예상 도구 호출 수, 위임 ≈ {3} + {4} × 예상 도구 호출 수(제출·결과 읽기·검토 포함). 호출 수를 세어 두 값을 비교한다.{5}" -f $totalN, $kDirA, $kDirB, $kDelA, $kDelB, $suffix

    $timeDirA = 11
    $timeDirB = 15
    $agyLow = 16
    $agyMed = 60
    $agyHigh = 444

    if ($null -ne $cal -and $null -ne $cal.time) {
        try {
            if ($null -ne $cal.time.direct) {
                if ($null -ne $cal.time.direct.a_s) { $timeDirA = [int]$cal.time.direct.a_s }
                if ($null -ne $cal.time.direct.b_s) { $timeDirB = [int]$cal.time.direct.b_s }
            }
            if ($null -ne $cal.time.agy_median_s) {
                if ($null -ne $cal.time.agy_median_s.low) { $agyLow = [int]$cal.time.agy_median_s.low }
                if ($null -ne $cal.time.agy_median_s.medium) { $agyMed = [int]$cal.time.agy_median_s.medium }
                if ($null -ne $cal.time.agy_median_s.high) { $agyHigh = [int]$cal.time.agy_median_s.high }
            }
        } catch {}
    }

    $lowUnitStr = if ($agyLow -lt 60) { "{0}초" -f [int][Math]::Round($agyLow) } else { "{0}분" -f [int][Math]::Round($agyLow / 60.0) }
    $medUnitStr = if ($agyMed -lt 60) { "{0}초" -f [int][Math]::Round($agyMed) } else { "{0}분" -f [Math]::Max(1, [int][Math]::Round($agyMed / 60.0)) }
    $highUnitStr = if ($agyHigh -lt 60) { "{0}초" -f [int][Math]::Round($agyHigh) } else { "{0}분" -f [Math]::Max(1, [int][Math]::Round($agyHigh / 60.0)) }

    $timeLine = "[시간 예상] 최근 실측 — 직접 ≈ {0}초 + {1}초 × 호출 수, 위임 ≈ 15초 × 내 호출 수 + agy 처리(low 약 {2}, medium 약 {3}, high 약 {4}) + 앞 작업 대기." -f $timeDirA, $timeDirB, $lowUnitStr, $medUnitStr, $highUnitStr

    # [수준별 예상] 프롬프트 수준(낮음/보통/높음)별 식. 표본이 모자란 수준은 전체 식을 쓴다고 알려 준다.
    $levelLine = $null
    if ($null -ne $cal -and $null -ne $cal.levels -and $null -ne $cal.levels.direct -and $null -ne $cal.levels.delegate) {
        try {
            $lvParts = New-Object System.Collections.ArrayList
            foreach ($lvPair in @(@('low', '낮음'), @('medium', '보통'), @('high', '높음'))) {
                $ld = $cal.levels.direct.($lvPair[0])
                $lg = $cal.levels.delegate.($lvPair[0])
                if ($null -eq $ld -or $null -eq $lg) { continue }
                if ($ld.source -eq 'overall' -and $lg.source -eq 'overall') {
                    [void]$lvParts.Add(("{0} — 표본 모자람(직접 {1}/{2}, 위임 {3}/{4}) → 전체 식" -f $lvPair[1], [int]$ld.n, [int]$ld.required, [int]$lg.n, [int]$lg.required))
                } else {
                    $dTxt = if ($ld.source -eq 'level') { "직접 ≈ {0} + {1} × 호출" -f (& $formatK ([double]$ld.a)), (& $formatK ([double]$ld.b)) } else { "직접 전체 식({0}/{1})" -f [int]$ld.n, [int]$ld.required }
                    $gTxt = if ($lg.source -eq 'level') { "위임 ≈ {0} + {1} × 호출" -f (& $formatK ([double]$lg.a)), (& $formatK ([double]$lg.b)) } else { "위임 전체 식({0}/{1})" -f [int]$lg.n, [int]$lg.required }
                    [void]$lvParts.Add(("{0} — {1}, {2}" -f $lvPair[1], $dTxt, $gTxt))
                }
            }
            if ($lvParts.Count -gt 0) {
                $levelLine = "[수준별 예상] " + ($lvParts -join " | ") + ". 프롬프트 수준을 먼저 정하고(낮음: 설명·확인 또는 한 곳 수정, 보통: 파일 1~3개 수정과 간단한 시험, 높음: 원인 찾기·여러 파일 설계·화면과 서버와 시험을 함께 바꿈) 그 수준의 식에 호출 수를 넣는다. 표본이 모자란 수준은 위 전체 식을 쓴다."
            }
        } catch {}
    }

    $anomalyLine = $null
    if ($null -ne $cal -and $null -ne $cal.anomalies -and [int]$cal.anomalies.n -gt 0) {
        try {
            $anomN = [int]$cal.anomalies.n
            $bc = $cal.anomalies.by_cause
            $causeParts = New-Object System.Collections.ArrayList
            if ($null -ne $bc) {
                if ($bc.agy_slow -and [int]$bc.agy_slow -gt 0) { [void]$causeParts.Add("agy 지연 $([int]$bc.agy_slow)") }
                if ($bc.scope -and [int]$bc.scope -gt 0) { [void]$causeParts.Add("예상 범위 불일치 $([int]$bc.scope)") }
                if ($bc.weak_estimate -and [int]$bc.weak_estimate -gt 0) { [void]$causeParts.Add("근거 약한 예상 $([int]$bc.weak_estimate)") }
                if ($bc.unknown -and [int]$bc.unknown -gt 0) { [void]$causeParts.Add("원인 모름 $([int]$bc.unknown)") }
            }
            $causeStr = if ($causeParts.Count -gt 0) { " — " + ($causeParts -join ", ") } else { "" }
            $anomalyLine = "[이상치] 최근 7일 {0}건{1}. 뷰어 카드의 이상치 표시를 보고 원인을 확인한다." -f $anomN, $causeStr
        } catch {}
    }

    $target = 20
    if ($env:AGY_COLLECT_TARGET -ne $null -and $env:AGY_COLLECT_TARGET -ne "") {
        $parsed = 0
        if ([int]::TryParse([string]$env:AGY_COLLECT_TARGET, [ref]$parsed)) {
            $target = [Math]::Max(0, $parsed)
        }
    } elseif ($null -ne $cal -and $null -ne $cal.collect -and $null -ne $cal.collect.target) {
        $target = [int]$cal.collect.target
    }

    $collectN = 0
    if ($null -ne $cal -and $null -ne $cal.collect -and $null -ne $cal.collect.delegate_n) {
        $collectN = [int]$cal.collect.delegate_n
    }

    $collectActive = if ($target -le 0) {
        $false
    } else {
        if ($null -ne $cal -and $null -ne $cal.collect -and $null -ne $cal.collect.active -and ($env:AGY_COLLECT_TARGET -eq $null -or $env:AGY_COLLECT_TARGET -eq "")) {
            [bool]$cal.collect.active
        } else {
            [bool]($collectN -lt $target)
        }
    }

    Write-Output "[samjil-delegate-agy] 이 세션의 모든 작업 요청은 응답 전에 samjil-delegate-agy 스킬을 먼저 불러와 따른다. 기본은 agy 위임이고, 설계와 가장 어려운 조각만 Claude 가 직접 한다."
    Write-Output $watcherLine
    Write-Output $tokenLine
    Write-Output $timeLine
    if ($levelLine) { Write-Output $levelLine }
    if ($anomalyLine) { Write-Output $anomalyLine }
    if ($collectActive) {
        Write-Output ("수집 모드: 위임 표본 {0}/{1} — 이 PC 의 위임 통계가 아직 적어서, 직접 처리 대상 1~4(맥락 필요·설계/가장 어려움·틀리면 비용 큼·Claude 전용 도구)가 아니면 토큰 비교 없이 위임한다." -f $collectN, $target)
    }
    $recScript = Join-Path (Split-Path $PSScriptRoot -Parent) "record-estimate.ps1"
    if (Test-Path -LiteralPath $recScript) {
        $corrLine = $null
        if ($null -ne $cal -and $null -ne $cal.correction) {
            try {
                $corrText = {
                    param($name, $c)
                    if ($null -ne $c -and $null -ne $c.ratio) { "{0} ×{1:0.00}(실제÷예상 중앙값 {2:0.00}, 최근 표본 {3}개)" -f $name, [double]$c.factor, [double]$c.ratio, [int]$c.n }
                    else { "{0} ×1.00(최근 표본 {1}개로 5개 미만이라 보정 안 함)" -f $name, $(if ($null -ne $c -and $null -ne $c.n) { [int]$c.n } else { 0 }) }
                }
                $corrLine = "[예상 보정] 최근 실측에서 예상이 실제와 어긋난 만큼 다음 예상을 보정한다: " + (& $corrText "직접" $cal.correction.direct) + ", " + (& $corrText "위임" $cal.correction.delegate) + ". 토큰 예상은 식으로 구한 값에 이 계수를 곱한 뒤 직접·위임을 비교하고, 기록(record-estimate)에도 곱한 값을 적고, 곱한 계수를 -FactorDirect · -FactorDelegate 로 함께 적는다(통계가 보정 전 값으로 다음 계수를 계산하려고). 계수는 표본이 적을수록 1 쪽으로 당겨져 있고 통계를 갱신할 때마다 바뀐다."
            } catch {}
        }
        if ($corrLine) { Write-Output $corrLine }
        Write-Output ("[예상 기록] 직접/위임을 정한 즉시(질문마다 한 번, 다른 도구 호출보다 먼저) 아래 명령으로 예상을 남긴다. 통계는 질문 한 건이 한 행이다. 일하는 중에 사용자가 새 질문을 보내면(도착 순서로 질문 2, 3번) 그 질문도 같은 명령으로 따로 기록하고, 앞 질문 일로 돌아오면 record-estimate.ps1 -Switch <질문 번호> 를 한 번 부른다(다른 질문 때문에 생긴 지연이 앞 질문 시간에 더해지지 않게 하는 표시). 첫 작업이 Bash 명령이면 기록을 그 명령 앞에 붙여 한 번에 실행한다(예: record-estimate … ; git status. 따로 부르면 모델이 한 번 더 돌며 대화 전체를 다시 읽는다). 그 턴의 답변 끝에는 예상 줄을 쓰지 않는다. 기록 호출은 호출 수에 세지 않는다. 토큰은 1.3k 형식, 시간은 14s 1m30s 형식: powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""{0}"" -Direct <토큰> -Delegate <토큰> -TimeDirect <시간> -TimeDelegate <시간> -Choice direct|delegate -Level low|medium|high -FactorDirect <직접 계수> -FactorDelegate <위임 계수> -Reason ""<직접/위임을 고른 이유 한 줄>"". 기록 뒤 [경고] 가 나오면 직접 처리 사유 4가지에 해당하는지 다시 따져 아니면 위임으로 바꿔 다시 기록한다" -f $recScript)
    }
} catch {
    # 훅 오류가 세션 시작을 막으면 안 된다.
}
exit 0
