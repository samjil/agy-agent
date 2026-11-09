# Claude 링크 색인 백그라운드 갱신 스크립트
# Windows PowerShell 5.1 호환 (BOM 포함 UTF-8, CRLF)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IndexFile,
    [string]$DesktopDir,
    [string]$ProjectsDir
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'claude-sessions.ps1')

if ([string]::IsNullOrEmpty($DesktopDir)) {
    $DesktopDir = Get-ClaudeDesktopDir
}
if ([string]::IsNullOrEmpty($ProjectsDir)) {
    $ProjectsDir = Get-ClaudeProjectsDir
}

$parentDir = Split-Path -Parent $IndexFile
if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
    [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null
}

$runningFile = "$IndexFile.running"
$errorFile   = "$IndexFile.error"

$runningInfo = @{
    pid     = $PID
    started = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}
$noBomUtf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($runningFile, (ConvertTo-Json -InputObject $runningInfo), $noBomUtf8)

try {
    Update-ClaudeLinkIndex -IndexFile $IndexFile -DesktopDir $DesktopDir -ProjectsDir $ProjectsDir | Out-Null
    if (Test-Path -LiteralPath $errorFile) {
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    }
}
catch {
    try {
        [System.IO.File]::WriteAllText($errorFile, $_.ToString(), $noBomUtf8)
    }
    catch {}
}
finally {
    if (Test-Path -LiteralPath $runningFile) {
        Remove-Item -LiteralPath $runningFile -Force -ErrorAction SilentlyContinue
    }
}
