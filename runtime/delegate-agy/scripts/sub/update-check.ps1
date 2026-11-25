# update-check.ps1
# 공개 GitHub 저장소(samjil/agy-agent)의 VERSION 파일을 하루 한 번만 확인해 새 버전 여부를 알립니다.
# dot-source 해서 함수 라이브러리로 쓰거나(-Fetch 없으면 부작용 없음), `-Fetch` 로 백그라운드 수집만 실행합니다.
param(
    [switch]$Fetch,
    [string]$InstallRoot = ""
)

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
    $t = $Text.Trim()
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
    $cache = Read-SamjilUpdateCache $InstallRoot
    if ($null -eq $cache) { return $true }
    $checkedAt = if ($cache.PSObject.Properties["checked_at"]) { ConvertFrom-SamjilIsoTime $cache.checked_at } else { $null }
    if ($null -eq $checkedAt) { return $true }
    $ageHours = ([datetime]::UtcNow - $checkedAt).TotalHours
    $ok = ($cache.PSObject.Properties["ok"] -and [bool]$cache.ok)
    if ($ok) { return ($ageHours -ge 24.0) }
    return ($ageHours -ge 6.0)
}

function Invoke-SamjilUpdateFetch {
    param(
        [string]$InstallRoot = "",
        [scriptblock]$Fetcher = $null
    )
    try {
        if (-not (Test-SamjilUpdateFetchDue -InstallRoot $InstallRoot)) { return }
        $prev = Read-SamjilUpdateCache $InstallRoot
        $prevLatest = if ($prev -and $prev.PSObject.Properties["latest"] -and $null -ne $prev.latest) { [string]$prev.latest } else { $null }
        $prevNotifiedVer = if ($prev -and $prev.PSObject.Properties["notified_version"] -and $null -ne $prev.notified_version) { [string]$prev.notified_version } else { $null }
        $prevNotifiedAt = if ($prev -and $prev.PSObject.Properties["notified_at"] -and $null -ne $prev.notified_at) { $prev.notified_at } else { $null }

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

        $nowIso = [datetime]::UtcNow.ToString("o")
        if ($null -ne $parsed) {
            Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data ([ordered]@{
                checked_at       = $nowIso
                ok               = $true
                latest           = $parsed.Text
                notified_version = $prevNotifiedVer
                notified_at      = $prevNotifiedAt
            })
        } else {
            Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data ([ordered]@{
                checked_at       = $nowIso
                ok               = $false
                latest           = $prevLatest
                notified_version = $prevNotifiedVer
                notified_at      = $prevNotifiedAt
            })
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
        Write-SamjilUpdateCache -InstallRoot $InstallRoot -Data ([ordered]@{
            checked_at       = $checkedAt
            ok               = $ok
            latest           = $latest
            notified_version = $Version
            notified_at      = [datetime]::UtcNow.ToString("o")
        })
    } catch {}
}

if ($Fetch -and $MyInvocation.InvocationName -ne ".") {
    Invoke-SamjilUpdateFetch -InstallRoot $InstallRoot
}
