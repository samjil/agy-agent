# agy-quota.ps1
# agy 의 남은 한도(`agy -p "/usage"`)를 읽어 캐시하는 공용 헬퍼입니다(뷰어의 한도 크기 추정이 씁니다).
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-quota.ps1")`
#
# - `agy -p "/usage"` 출력에는 이메일이나 안내 문구가 섞일 수 있습니다.
#   정해진 탭 구분 한도 줄(`^(.+?)\t(.+?)\t(\d{1,3})%\t(\S+)$`)만 읽고 이메일 등은 저장하거나 기록하지 않습니다.
# - 캐시 파일은 <runtime dir>\agy-quota.json (기본 10분 보관)이며, 실패 시 기존 정상 캐시를 덮어쓰지 않습니다.

function ConvertTo-AgyUtcDateTime([string]$Text) {
    $s = ([string]$Text).Trim()
    if (-not $s) { return $null }
    $dt = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
        return $dt.ToUniversalTime()
    }
    return $null
}

# `agy -p "/usage"` 출력에서 Gemini 주간/5시간 한도와 Argon 주간 한도를 뽑는다.
# 반환: @{ gemini_weekly=@{pct;reset}; gemini_5h=@{pct;reset}; argon_weekly=@{pct;reset} } (못 찾은 키는 생략)
function ConvertFrom-AgyUsageText([string]$Text) {
    $result = [ordered]@{}
    if (-not $Text) { return $result }
    foreach ($line in ([string]$Text -split "`r?`n")) {
        if ($line -match '^(.+?)\t(.+?)\t(\d{1,3})%\t(\S+)$') {
            $group = $Matches[1].Trim()
            $label = $Matches[2].Trim()
            $pct = [int]$Matches[3]
            $reset = $Matches[4].Trim()
            if ($group -ieq 'Gemini Models') {
                if ($label -imatch 'Weekly') {
                    $result.gemini_weekly = [ordered]@{ pct = $pct; reset = $reset }
                } elseif ($label -imatch 'Five\s*Hour') {
                    $result.gemini_5h = [ordered]@{ pct = $pct; reset = $reset }
                }
            } elseif ($group -imatch 'Argon' -and $label -imatch 'Weekly') {
                $result.argon_weekly = [ordered]@{ pct = $pct; reset = $reset }
            }
        }
    }
    return $result
}

# `agy -p "/usage"` 를 콘솔 창 없이 실행해 표준 출력을 돌려준다. 실패하거나 시간 안에 끝나지 않으면 $null.
function Invoke-AgyUsageCommand([string]$AgyExe = "agy", [int]$TimeoutSec = 20) {
    $exe = $AgyExe
    if ($exe -eq "agy") {
        try {
            $cmd = Get-Command agy -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd -and $cmd.Source) { $exe = [string]$cmd.Source }
        } catch {}
    }
    if (-not (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue)) {
        $spawnLib = Join-Path $PSScriptRoot "agy-spawn.ps1"
        if (-not (Test-Path -LiteralPath $spawnLib)) { $spawnLib = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-spawn.ps1" }
        if (Test-Path -LiteralPath $spawnLib) { . $spawnLib }
    }
    if (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue) {
        $res = Invoke-AgyHiddenWithOutput -FilePath $exe -ArgumentList @("-p", "/usage") -TimeoutSeconds $TimeoutSec
        if ($res -and $res.Pid -ge 0) {
            if ($res.TimedOut) { return $null }
            if ($res.ExitCode -eq 0 -and $res.StdOut) { return [string]$res.StdOut }
            return $null
        }
    }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $exe
        $psi.Arguments              = '-p "/usage"'
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        try { $p.StandardInput.Close() } catch {}
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return $null
        }
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { return $null }
        $out = [string]$outTask.Result
        if (-not $out) { return $null }
        return $out
    } catch {
        return $null
    } finally {
        if ($p) { try { $p.Dispose() } catch {} }
    }
}

function Read-AgyQuotaCache([string]$CacheFile) {
    if (-not $CacheFile -or -not (Test-Path -LiteralPath $CacheFile)) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($CacheFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $obj = $text | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj) { return $null }
        $snap = [ordered]@{}
        if ($obj.PSObject.Properties['checked_at'] -and $obj.checked_at) {
            $snap.checked_at = [string]$obj.checked_at
        }
        $hasData = $false
        foreach ($k in @('gemini_weekly', 'gemini_5h', 'argon_weekly')) {
            if ($obj.PSObject.Properties[$k] -and $null -ne $obj.$k) {
                $entry = $obj.$k
                if ($null -ne $entry.pct -and $entry.reset) {
                    $snap[$k] = [ordered]@{ pct = [int]$entry.pct; reset = [string]$entry.reset }
                    $hasData = $true
                }
            }
        }
        if (-not $hasData) { return $null }
        return $snap
    } catch {
        return $null
    }
}

# 한도 스냅샷을 돌려준다.
# - 캐시 파일이 $MaxAgeSec 보다 젊으면 그대로 돌려준다.
# - 그렇지 않으면 `agy -p "/usage"`(또는 $Runner)를 실행해 파싱하고 임시 파일+이동으로 원자적으로 저장한다.
# - 실패하거나 파싱된 값이 없으면 기존 캐시를 덮어쓰지 않고, 2시간 미만인 기존 캐시가 있으면 대신 돌려주고 없으면 $null.
function Get-AgyQuotaSnapshot([string]$CacheFile, [int]$MaxAgeSec = 600, [scriptblock]$Runner = $null, [string]$AgyExe = "agy", [int]$TimeoutSec = 20, [datetime]$NowUtc = [datetime]::MinValue) {
    $now = if ($NowUtc -eq [datetime]::MinValue) { [datetime]::UtcNow } else { $NowUtc.ToUniversalTime() }
    $cached = Read-AgyQuotaCache $CacheFile
    $cacheAgeSec = $null
    if ($cached -and $cached.checked_at) {
        $checkedDt = ConvertTo-AgyUtcDateTime ([string]$cached.checked_at)
        if ($null -ne $checkedDt) {
            $cacheAgeSec = ($now - $checkedDt).TotalSeconds
            if ($cacheAgeSec -lt $MaxAgeSec) {
                return $cached
            }
        }
    }

    $raw = $null
    try {
        if ($Runner) { $raw = & $Runner } else { $raw = Invoke-AgyUsageCommand $AgyExe $TimeoutSec }
    } catch {
        $raw = $null
    }

    $parsed = ConvertFrom-AgyUsageText ([string]$raw)
    $parsedKeys = @($parsed.Keys)
    if ($parsedKeys.Count -gt 0) {
        $snap = [ordered]@{ checked_at = $now.ToString("yyyy-MM-ddTHH:mm:ssZ") }
        foreach ($k in $parsedKeys) { $snap[$k] = $parsed[$k] }
        if ($CacheFile) {
            $tmp = "$CacheFile.$PID.tmp"
            try {
                $dir = Split-Path -Path $CacheFile -Parent
                if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Force -Path $dir | Out-Null
                }
                $json = $snap | ConvertTo-Json -Compress -Depth 5
                [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
                Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue
                [System.IO.File]::Move($tmp, $CacheFile)
            } catch {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        return $snap
    }

    # 실패하거나 파싱된 항목이 없으면 기존 정상 캐시를 지우지 않는다(2시간 미만이면 재사용).
    if ($cached -and $null -ne $cacheAgeSec -and $cacheAgeSec -lt 7200) {
        return $cached
    }
    return $null
}
