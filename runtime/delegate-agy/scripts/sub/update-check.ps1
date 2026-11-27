# update-check.ps1
# 공개 GitHub 저장소(samjil/agy-agent)의 VERSION 파일을 6시간에 한 번만 확인해 새 버전 여부를 알립니다.
# dot-source 해서 함수 라이브러리로 쓰거나(-Fetch/-RunUpdate 없으면 부작용 없음),
# `-Fetch` 로 백그라운드 수집을, `-RunUpdate` 로 업데이트 설치를 실행합니다.
param(
    [switch]$Fetch,
    [switch]$RunUpdate,
    [string]$InstallRoot = ""
)

$script:SamjilUpdateCheckScriptPath = $PSCommandPath
$script:SamjilUpdateCheckScriptDir = $PSScriptRoot
$script:SamjilInstallerUrl = "https://raw.githubusercontent.com/samjil/agy-agent/main/install.ps1"

function Get-SamjilDefaultInstallRoot([string]$InstallRoot = "") {
    if ($InstallRoot) { return $InstallRoot }
    if ($env:SAMJIL_INSTALL_ROOT) { return $env:SAMJIL_INSTALL_ROOT }
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return (Join-Path $home_ ".samjil")
}

function Get-SamjilUpdateCachePath([string]$InstallRoot = "") {
    return (Join-Path (Get-SamjilDefaultInstallRoot $InstallRoot) "cache\update-check.json")
}

function ConvertFrom-SamjilIsoTime($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) {
        return $Value.UtcDateTime
    }
    $s = ([string]$Value).Trim()
    if (-not $s) { return $null }
    [DateTimeOffset]$dto = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Read-SamjilUpdateCache([string]$InstallRoot = "") {
    $path = Get-SamjilUpdateCachePath $InstallRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Trim()
        if (-not $raw) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Merge-SamjilUpdateCacheFields($Prev, [System.Collections.IDictionary]$Updates) {
    $merged = [ordered]@{}
    if ($null -ne $Prev) {
        foreach ($p in $Prev.PSObject.Properties) {
            $merged[$p.Name] = $p.Value
        }
    }
    foreach ($k in $Updates.Keys) {
        $merged[$k] = $Updates[$k]
    }
    return $merged
}

function Write-SamjilUpdateCache([string]$InstallRoot = "", [System.Collections.IDictionary]$Data) {
    try {
        $path = Get-SamjilUpdateCachePath $InstallRoot
        $dir = [System.IO.Path]::GetDirectoryName($path)
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $json = ($Data | ConvertTo-Json -Depth 4) + "`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $tmp = Join-Path $dir ("update-check.{0}.tmp" -f ([Guid]::NewGuid().ToString("N")))
        try {
            [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
            Move-Item -LiteralPath $tmp -Destination $path -Force
        } catch {
            try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
            [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
        }
    } catch {}
}

# "<short hash> <YYYY-MM-DD>[ dev]" 형식의 버전 문자열을 해석한다. "$Format..." 등 잘못된 문자열은 $null.
function ConvertFrom-SamjilVersionText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.TrimStart([char]0xFEFF).Trim()
    if ($t -cnotmatch '^([0-9a-f]{7,40}) (\d{4}-\d{2}-\d{2})( dev)?$') { return $null }
    $hash = $matches[1]
    $dateStr = $matches[2]
    $isDev = [bool]($matches[3])
    [datetime]$dt = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($dateStr, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
        return $null
    }
    return @{
        Hash = $hash
        Date = $dt
        Dev  = $isDev
        Text = $t
    }
}

function Get-SamjilInstalledVersion {
    param([string]$InstallRoot = "")
    $root = Get-SamjilDefaultInstallRoot $InstallRoot
    $verPath = Join-Path $root "VERSION"
    if (-not (Test-Path -LiteralPath $verPath -PathType Leaf)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($verPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Trim()
        return (ConvertFrom-SamjilVersionText $raw)
    } catch {
        return $null
    }
}

function Test-SamjilVersionNewer($Local, $Remote) {
    if ($null -eq $Local -or $null -eq $Remote) { return $false }
    if ($Local.Dev) { return $false }
    if ($Remote.Date -gt $Local.Date) { return $true }
    if ($Remote.Date -eq $Local.Date -and $Remote.Hash -ne $Local.Hash) { return $true }
    return $false
}

function Test-SamjilUpdateCheckDisabled {
    param([string]$InstallRoot = "")
    if ($env:SAMJIL_NO_UPDATE_CHECK -eq "1") { return $true }
    $root = Get-SamjilDefaultInstallRoot $InstallRoot
    $flagPath = Join-Path $root "no-update-check"
    return (Test-Path -LiteralPath $flagPath -PathType Leaf)
}

function Test-SamjilUpdateFetchDue {
    param([string]$InstallRoot = "")
    if (Test-SamjilUpdateCheckDisabled -InstallRoot $InstallRoot) { return $false }
    $local = Get-SamjilInstalledVersion -InstallRoot $InstallRoot
    if ($null -ne $local -and $local.Dev) { return $false }
    $cache = Read-SamjilUpdateCache $InstallRoot
    if ($null -eq $cache) { return $true }
    $checkedAt = if ($cache.PSObject.Properties["checked_at"]) { ConvertFrom-SamjilIsoTime $cache.checked_at } else { $null }
    if ($null -eq $checkedAt) { return $true }
    $ageHours = ([datetime]::UtcNow - $checkedAt).TotalHours
    $ok = ($cache.PSObject.Properties["ok"] -and [bool]$cache.ok)
    # 같은 날 다시 배포한 릴리스도 늦지 않게 알리도록 성공 캐시는 6시간만 쓴다(파일 하나만 받는 요청이라 부담이 작다)
    if ($ok) { return ($ageHours -ge 6.0) }
    return ($ageHours -ge 6.0)
}

function Invoke-SamjilUpdateFetch {
    param(
        [string]$InstallRoot = "",
        [scriptblock]$Fetcher = $null
    )
    try {
        if (-not (Test-SamjilUpdateFetchDue -InstallRoot $InstallRoot)) { return }

        $parsed = $null
        try {
            $rawText = ""
            if ($null -ne $Fetcher) {
                $rawText = [string](& $Fetcher)
            } elseif ($env:AGY_TEST_UPDATE_FAIL -eq "1") {
                throw "test failure"
            } elseif (Test-Path Env:\AGY_TEST_UPDATE_TEXT) {
                $rawText = [string]$env:AGY_TEST_UPDATE_TEXT
            } else {
                try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
                $resp = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/samjil/agy-agent/main/VERSION" -UseBasicParsing -TimeoutSec 3 -UserAgent "agy-agent-update-check" -ErrorAction Stop
                $rawText = [string]$resp.Content
            }
            $parsed = ConvertFrom-SamjilVersionText $rawText
        } catch {
            $parsed = $null
        }

        $prev = Read-SamjilUpdateCache $InstallRoot
        $prevLatest = if ($prev -and $prev.PSObject.Properties["latest"] -and $null -ne $prev.latest) { [string]$prev.latest } else { $null }
        $prevNotifiedVer = if ($prev -and $prev.PSObject.Properties["notified_version"] -and $null -ne $prev.notified_version) { [string]$prev.notified_version } else { $null }
        $prevNotifiedAt = if ($prev -and $prev.PSObject.Properties["notified_at"] -and $null -ne $prev.notified_at) { $prev.notified_at } else { $null }
        $nowIso = [datetime]::UtcNow.ToString("o")
        if ($null -ne $parsed) {
            $data = Merge-SamjilUpdateCacheFields $prev ([ordered]@{
                checked_at       = $nowIso
                ok               = $true
                latest           = $parsed.Text
                notified_version = $prevNotifiedVer
                notified_at      = $prevNotifiedAt
            })
            Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data $data
        } else {
            $data = Merge-SamjilUpdateCacheFields $prev ([ordered]@{
                checked_at       = $nowIso
                ok               = $false
                latest           = $prevLatest
                notified_version = $prevNotifiedVer
                notified_at      = $prevNotifiedAt
            })
            Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data $data
        }
    } catch {}
}

function Get-SamjilUpdateNotice {
    param(
        [string]$InstallRoot = "",
        [switch]$ForSession
    )
    if (Test-SamjilUpdateCheckDisabled -InstallRoot $InstallRoot) { return $null }
    $local = Get-SamjilInstalledVersion -InstallRoot $InstallRoot
    if ($null -eq $local) { return $null }
    $cache = Read-SamjilUpdateCache $InstallRoot
    if ($null -eq $cache -or -not $cache.PSObject.Properties["latest"] -or -not $cache.latest) { return $null }
    $remote = ConvertFrom-SamjilVersionText ([string]$cache.latest)
    if (-not (Test-SamjilVersionNewer $local $remote)) { return $null }

    if ($ForSession) {
        $nVer = if ($cache.PSObject.Properties["notified_version"] -and $null -ne $cache.notified_version) { [string]$cache.notified_version } else { "" }
        $nAt = if ($cache.PSObject.Properties["notified_at"]) { ConvertFrom-SamjilIsoTime $cache.notified_at } else { $null }
        if ($nVer -eq $remote.Text -and $null -ne $nAt -and (([datetime]::UtcNow - $nAt).TotalDays -lt 7.0)) {
            return $null
        }
    }

    return @{
        Installed = $local.Text
        Latest    = $remote.Text
        Available = $true
    }
}

function Set-SamjilUpdateNotified {
    param(
        [string]$InstallRoot = "",
        [Parameter(Mandatory = $true)][string]$Version
    )
    try {
        $prev = Read-SamjilUpdateCache $InstallRoot
        $checkedAt = if ($prev -and $prev.PSObject.Properties["checked_at"] -and $null -ne $prev.checked_at) { $prev.checked_at } else { $null }
        $ok = if ($prev -and $prev.PSObject.Properties["ok"]) { [bool]$prev.ok } else { $true }
        $latest = if ($prev -and $prev.PSObject.Properties["latest"] -and $null -ne $prev.latest) { [string]$prev.latest } else { $Version }
        $data = Merge-SamjilUpdateCacheFields $prev ([ordered]@{
            checked_at       = $checkedAt
            ok               = $ok
            latest           = $latest
            notified_version = $Version
            notified_at      = [datetime]::UtcNow.ToString("o")
        })
        Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data $data
    } catch {}
}

function Set-SamjilUpdateGated {
    param(
        [string]$InstallRoot = "",
        [Parameter(Mandatory = $true)][string]$Version
    )
    try {
        $prev = Read-SamjilUpdateCache $InstallRoot
        $data = Merge-SamjilUpdateCacheFields $prev ([ordered]@{
            gated_version = $Version
            gated_at      = [datetime]::UtcNow.ToString("o")
        })
        Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data $data
    } catch {}
}

function Test-SamjilSubmitUpdateGate {
    param([string]$InstallRoot = "")
    try {
        if (Test-SamjilUpdateCheckDisabled -InstallRoot $InstallRoot) { return $null }
        $notice = Get-SamjilUpdateNotice -InstallRoot $InstallRoot
        if ($null -eq $notice -or -not $notice.Available) { return $null }
        $cache = Read-SamjilUpdateCache $InstallRoot
        if ($null -eq $cache) { return $null }
        $gVer = if ($cache.PSObject.Properties["gated_version"] -and $null -ne $cache.gated_version) { [string]$cache.gated_version } else { "" }
        $gAt = if ($cache.PSObject.Properties["gated_at"]) { ConvertFrom-SamjilIsoTime $cache.gated_at } else { $null }
        if ($gVer -eq $notice.Latest -and $null -ne $gAt -and (([datetime]::UtcNow - $gAt).TotalHours -lt 24.0)) {
            return $null
        }
        Set-SamjilUpdateGated -InstallRoot $InstallRoot -Version $notice.Latest
        return @{
            Installed = $notice.Installed
            Latest    = $notice.Latest
        }
    } catch {
        return $null
    }
}

function Start-SamjilUpdateHiddenPowerShell([string[]]$ArgumentList) {
    try {
        $spawnLib = Join-Path $script:SamjilUpdateCheckScriptDir "agy-spawn.ps1"
        if (Test-Path -LiteralPath $spawnLib -PathType Leaf) {
            if (-not (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue)) {
                . $spawnLib
            }
            if (Get-Command Start-AgyHiddenDetachedProcess -ErrorAction SilentlyContinue) {
                $pid0 = Start-AgyHiddenDetachedProcess -FilePath "powershell.exe" -ArgumentList $ArgumentList
                if ($pid0 -ge 0) { return $true }
            }
        }
        $sh = New-Object -ComObject WScript.Shell
        $q = [char]34
        $cmd = "powershell.exe " + ((@($ArgumentList) | ForEach-Object {
            $s = [string]$_
            if ($s -match '[\s"]') { $q + ($s -replace '"', '\"') + $q } else { $s }
        }) -join " ")
        [void]$sh.Run($cmd, 0, $false)
        return $true
    } catch {
        try {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList $ArgumentList | Out-Null
            return $true
        } catch {
            return $false
        }
    }
}

function Start-SamjilUpdateFetchBackground {
    param([string]$InstallRoot = "")
    try {
        if ($env:AGY_TEST_NO_UPDATE_FETCH -eq "1") { return }
        if (-not (Test-SamjilUpdateFetchDue -InstallRoot $InstallRoot)) { return }
        $root = Get-SamjilDefaultInstallRoot $InstallRoot
        $scriptPath = $script:SamjilUpdateCheckScriptPath
        if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return }
        [void](Start-SamjilUpdateHiddenPowerShell @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-Fetch", "-InstallRoot", $root))
    } catch {}
}

function Get-SamjilUpdateRunStatePath([string]$InstallRoot = "") {
    return (Join-Path (Get-SamjilDefaultInstallRoot $InstallRoot) "cache\update-run.json")
}

function Get-SamjilUpdateRunLogPath([string]$InstallRoot = "") {
    return (Join-Path (Get-SamjilDefaultInstallRoot $InstallRoot) "cache\update-run.log")
}

function Write-SamjilUpdateRunState([string]$InstallRoot = "", [System.Collections.IDictionary]$Data) {
    try {
        $path = Get-SamjilUpdateRunStatePath $InstallRoot
        $dir = [System.IO.Path]::GetDirectoryName($path)
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $json = ($Data | ConvertTo-Json -Depth 4) + "`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $tmp = Join-Path $dir ("update-run.{0}.tmp" -f ([Guid]::NewGuid().ToString("N")))
        try {
            [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
            Move-Item -LiteralPath $tmp -Destination $path -Force
        } catch {
            try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
            [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
        }
    } catch {}
}

function Get-SamjilUpdateRunState {
    param([string]$InstallRoot = "")
    try {
        $path = Get-SamjilUpdateRunStatePath $InstallRoot
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Trim()
        if (-not $raw) { return $null }
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { return $null }
        $state = if ($obj.PSObject.Properties["state"] -and $null -ne $obj.state) { [string]$obj.state } else { "" }
        $startedAt = if ($obj.PSObject.Properties["started_at"] -and $null -ne $obj.started_at) { [string]$obj.started_at } else { $null }
        $finishedAt = if ($obj.PSObject.Properties["finished_at"] -and $null -ne $obj.finished_at) { [string]$obj.finished_at } else { $null }
        $message = if ($obj.PSObject.Properties["message"] -and $null -ne $obj.message) { [string]$obj.message } else { "" }

        if ($state -eq "running") {
            $startedDt = ConvertFrom-SamjilIsoTime $startedAt
            if ($null -ne $startedDt -and (([datetime]::UtcNow - $startedDt).TotalMinutes -ge 30.0)) {
                $state = "failed"
                $message = "시간 초과"
            }
        }

        return @{
            State      = $state
            StartedAt  = $startedAt
            FinishedAt = $finishedAt
            Message    = $message
        }
    } catch {
        return $null
    }
}

function Invoke-SamjilUpdateRun {
    param(
        [string]$InstallRoot = "",
        [scriptblock]$Installer = $null
    )
    try {
        $startedIso = [datetime]::UtcNow.ToString("o")
        Write-SamjilUpdateRunState -InstallRoot $InstallRoot -Data ([ordered]@{
            state       = "running"
            started_at  = $startedIso
            finished_at = $null
            message     = ""
        })

        $logPath = Get-SamjilUpdateRunLogPath $InstallRoot
        $logDir = [System.IO.Path]::GetDirectoryName($logPath)
        if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        try {
            [System.IO.File]::AppendAllText($logPath, ("=== [{0}] 업데이트 시작 ===`r`n" -f $startedIso), $utf8NoBom)
        } catch {}

        $exitCode = 1
        $errReason = ""
        $outLines = New-Object System.Collections.Generic.List[string]

        if ($null -ne $Installer) {
            try {
                $raw = @(& $Installer 2>&1)
                $foundCode = $false
                for ($i = 0; $i -lt $raw.Count; $i++) {
                    $item = $raw[$i]
                    if ($i -eq ($raw.Count - 1) -and ($item -is [int] -or $item -is [long] -or $item -is [short] -or $item -is [byte])) {
                        $exitCode = [int]$item
                        $foundCode = $true
                    } else {
                        [void]$outLines.Add([string]$item)
                    }
                }
                if (-not $foundCode) {
                    $exitCode = 0
                }
            } catch {
                $exitCode = 1
                $errReason = [string]$_.Exception.Message
                if ($errReason) { [void]$outLines.Add($errReason) }
            }
        } else {
            try {
                $cmd = "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm '$script:SamjilInstallerUrl' | iex"
                $childArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd)
                $spawnLib = Join-Path $script:SamjilUpdateCheckScriptDir "agy-spawn.ps1"
                $ranViaSpawn = $false
                if (Test-Path -LiteralPath $spawnLib -PathType Leaf) {
                    if (-not (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue)) {
                        . $spawnLib
                    }
                    if (Get-Command Invoke-AgyHiddenWithOutput -ErrorAction SilentlyContinue) {
                        $res = Invoke-AgyHiddenWithOutput -FilePath "powershell.exe" -ArgumentList $childArgs -TimeoutSeconds 1800
                        $ranViaSpawn = $true
                        if ($res.StdOut) { [void]$outLines.Add([string]$res.StdOut) }
                        if ($res.StdErr) { [void]$outLines.Add([string]$res.StdErr) }
                        if ($res.TimedOut) {
                            $exitCode = 1
                            $errReason = "시간 초과"
                        } else {
                            $exitCode = [int]$res.ExitCode
                        }
                    }
                }
                if (-not $ranViaSpawn) {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "powershell.exe"
                    $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -Command "' + ($cmd -replace '"', '\"') + '"')
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
                    $p = [System.Diagnostics.Process]::Start($psi)
                    $stdOut = $p.StandardOutput.ReadToEnd()
                    $stdErr = $p.StandardError.ReadToEnd()
                    [void]$p.WaitForExit(1800000)
                    if (-not $p.HasExited) {
                        try { $p.Kill() } catch {}
                        $exitCode = 1
                        $errReason = "시간 초과"
                    } else {
                        $exitCode = [int]$p.ExitCode
                    }
                    if ($stdOut) { [void]$outLines.Add($stdOut) }
                    if ($stdErr) { [void]$outLines.Add($stdErr) }
                }
            } catch {
                $exitCode = 1
                $errReason = [string]$_.Exception.Message
                if ($errReason) { [void]$outLines.Add($errReason) }
            }
        }

        $finishedIso = [datetime]::UtcNow.ToString("o")
        try {
            $logBody = ($outLines.ToArray() -join "`r`n")
            if ($logBody) {
                [System.IO.File]::AppendAllText($logPath, ($logBody.TrimEnd("`r", "`n") + "`r`n"), $utf8NoBom)
            }
            [System.IO.File]::AppendAllText($logPath, ("=== [{0}] 종료 코드 {1} ===`r`n" -f $finishedIso, $exitCode), $utf8NoBom)
        } catch {}

        if ($exitCode -eq 0) {
            Write-SamjilUpdateRunState -InstallRoot $InstallRoot -Data ([ordered]@{
                state       = "done"
                started_at  = $startedIso
                finished_at = $finishedIso
                message     = ""
            })
        } else {
            $shortMsg = $errReason
            if (-not $shortMsg -and $outLines.Count -gt 0) {
                for ($j = $outLines.Count - 1; $j -ge 0; $j--) {
                    $candLines = @(([string]$outLines[$j]) -split "`r?`n" | Where-Object { $_.Trim() })
                    if ($candLines.Count -gt 0) {
                        $shortMsg = $candLines[$candLines.Count - 1].Trim()
                        break
                    }
                }
            }
            if (-not $shortMsg) {
                $shortMsg = "설치 스크립트 실패 (종료 코드 $exitCode)"
            }
            if ($shortMsg.Length -gt 200) { $shortMsg = $shortMsg.Substring(0, 200) }
            Write-SamjilUpdateRunState -InstallRoot $InstallRoot -Data ([ordered]@{
                state       = "failed"
                started_at  = $startedIso
                finished_at = $finishedIso
                message     = $shortMsg
            })
        }
    } catch {}
}

function Start-SamjilUpdate {
    param([string]$InstallRoot = "")
    try {
        $cur = Get-SamjilUpdateRunState -InstallRoot $InstallRoot
        if ($null -ne $cur -and $cur.State -eq "running") {
            return @{
                Started = $false
                Message = "업데이트가 이미 실행 중입니다."
            }
        }
        if ($env:AGY_TEST_NO_UPDATE_RUN -eq "1") {
            return @{
                Started = $true
                Message = "업데이트를 시작했습니다."
            }
        }
        $root = Get-SamjilDefaultInstallRoot $InstallRoot
        $scriptPath = $script:SamjilUpdateCheckScriptPath
        if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            return @{
                Started = $false
                Message = "update-check.ps1 을 찾지 못했습니다."
            }
        }
        $ok = Start-SamjilUpdateHiddenPowerShell @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-RunUpdate", "-InstallRoot", $root)
        if ($ok) {
            return @{
                Started = $true
                Message = "업데이트를 시작했습니다."
            }
        }
        return @{
            Started = $false
            Message = "업데이트 프로세스를 시작하지 못했습니다."
        }
    } catch {
        return @{
            Started = $false
            Message = "업데이트 시작 중 오류가 발생했습니다."
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    if ($Fetch) {
        Invoke-SamjilUpdateFetch -InstallRoot $InstallRoot
    } elseif ($RunUpdate) {
        Invoke-SamjilUpdateRun -InstallRoot $InstallRoot
    }
}
