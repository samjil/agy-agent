# ensure-viewer-running.ps1
# 통합 뷰어(serve-viewer.ps1)가 꺼져 있으면 콘솔 창도 브라우저 탭도 없이 백그라운드로 켭니다. 이미 떠 있으면 아무것도 하지 않습니다.
# 뷰어는 켜질 때 agy 워처도 창 없이 함께 켭니다(manual_stop.flag 가 있으면 켜지 않음). 그래서 agy 위임을 쓰려고 "뷰어와 워처가 둘 다 꺼져 있을 때"는
# 이 스크립트 하나로 둘 다 백그라운드에서 켜집니다.
#
# 사용법:
#   .\ensure-viewer-running.ps1                  # 꺼져 있으면 창 없이 켜고, 응답할 때까지 기다림
#   .\ensure-viewer-running.ps1 -CheckOnly       # 켜지 않고 상태만 출력
#   .\ensure-viewer-running.ps1 -Stop            # 창 없이 떠 있는 뷰어를 종료(창이 없어서 Ctrl+C 로 끌 수 없으므로). -Port 의 뷰어만 끕니다
#   .\ensure-viewer-running.ps1 -Port 9000       # 포트 지정(기본 8787)
#
# 출력과 종료 코드:
#   ALIVE   (0)  이미 떠 있음(켜지 않음)           DEAD    (1)  꺼져 있음(-CheckOnly)
#   STARTED (0)  방금 켰고 응답함                  FAILED  (1)  켰지만 제한 시간 안에 응답하지 않음
#   STOPPED (0)  -Stop 으로 종료함                 NONE    (0)  -Stop 인데 떠 있는 뷰어가 없음
#
# 창이 뜨지 않게 하는 방법: WScript.Shell.Run(명령, 0)으로 숨김 실행합니다(콘솔 창을 만들지 않음). 실패하면 Start-Process -WindowStyle Hidden 으로 대체합니다.

param(
    [int]$Port = 8787,
    [switch]$CheckOnly = $false,
    [switch]$Stop = $false,
    [int]$WaitSeconds = 30,
    # 뷰어 명령줄 뒤에 그대로 덧붙일 인자 문자열(시험에서 -NoAgent -DataDir "C:\x" 처럼 줄 때 씁니다).
    # 한 문자열로 받는 이유: powershell.exe -File 로 부르면 배열이 여러 인자로 쪼개져 -NoAgent 같은 값이 이 스크립트의 매개변수로 읽힙니다.
    [string]$ViewerArgs = ""
)

$ViewerScript = Join-Path $PSScriptRoot "serve-viewer.ps1"

# 이 주소가 우리 뷰어인지 확인한다: /api/status 가 JSON 으로 응답하고 watcherAlive 항목이 있어야 한다(다른 프로그램이 같은 포트를 쓰는 경우를 거른다).
function Test-ViewerAlive([int]$Port) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:{0}/api/status" -f $Port) -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -ne 200) { return $false }
        $j = $r.Content | ConvertFrom-Json -ErrorAction Stop
        return ($null -ne $j.PSObject.Properties["watcherAlive"])
    } catch { return $false }
}

# 뷰어를 창 없이 띄우는 명령줄. 브라우저 탭도 열지 않는다(-NoBrowser).
function Get-ViewerLaunchCommand([string]$ViewerScript, [int]$Port, [string]$ViewerArgs = "") {
    $q = [char]34
    $cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $q$ViewerScript$q -NoBrowser -Port $Port"
    if ($ViewerArgs.Trim()) { $cmd += " " + $ViewerArgs.Trim() }
    return $cmd
}

function Start-ViewerHidden([string]$ViewerScript, [int]$Port, [string]$ViewerArgs = "") {
    $cmd = Get-ViewerLaunchCommand $ViewerScript $Port $ViewerArgs
    try {
        $sh = New-Object -ComObject WScript.Shell
        [void]$sh.Run($cmd, 0, $false)   # 0 = 창을 만들지 않음
        return $true
    } catch {
        try {
            $psArgs = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ViewerScript`" -NoBrowser -Port $Port $ViewerArgs"
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList $psArgs | Out-Null
            return $true
        } catch { return $false }
    }
}

# 명령줄이 이 포트의 뷰어를 가리키는지. 포트를 따로 주지 않고 켠 뷰어는 기본 포트(8787)의 것이다.
function Test-ViewerCommandLineForPort([string]$CommandLine, [int]$Port) {
    if (-not $CommandLine) { return $false }
    if ($CommandLine -match '-Port[\s=]+(\d+)') { return ([int]$Matches[1] -eq $Port) }
    return ($Port -eq 8787)
}

# 이 포트의 뷰어 프로세스(powershell 본체와, serve-viewer.bat 으로 켰다면 그 cmd)를 찾는다. 다른 포트의 뷰어는 건드리지 않는다.
function Get-ViewerProcesses([int]$Port) {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and (
            ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'serve-viewer\.ps1') -or
            ($_.Name -eq 'cmd.exe' -and $_.CommandLine -match 'serve-viewer\.bat')) -and
        (Test-ViewerCommandLineForPort $_.CommandLine $Port)
    })
}

# ---- 본체: 인자 없이 dot-source 하면 함수만 정의합니다(시험용). 점(.)으로 불렀는지는 InvocationName 으로 구분합니다. ----
if ($MyInvocation.InvocationName -ne '.') {
    if ($Stop) {
        $procs = @(Get-ViewerProcesses $Port)   # 뷰어가 하나뿐이면 함수가 배열을 풀어 돌려주므로 배열로 받는다
        if ($procs.Count -eq 0) { Write-Output "NONE"; exit 0 }
        foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
        Write-Output "STOPPED"
        exit 0
    }

    if (Test-ViewerAlive $Port) { Write-Output "ALIVE"; exit 0 }
    if ($CheckOnly) { Write-Output "DEAD"; exit 1 }

    if (-not (Test-Path -LiteralPath $ViewerScript)) {
        Write-Output "FAILED"
        [Console]::Error.WriteLine("serve-viewer.ps1 을 찾지 못했습니다: $ViewerScript")
        exit 1
    }
    if (-not (Start-ViewerHidden $ViewerScript $Port $ViewerArgs)) {
        Write-Output "FAILED"
        [Console]::Error.WriteLine("뷰어를 숨김 실행하지 못했습니다.")
        exit 1
    }
    for ($i = 0; $i -lt ($WaitSeconds * 2); $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-ViewerAlive $Port) { Write-Output "STARTED"; exit 0 }
    }
    Write-Output "FAILED"
    [Console]::Error.WriteLine("뷰어를 켰지만 ${WaitSeconds}초 안에 http://127.0.0.1:$Port 가 응답하지 않았습니다.")
    exit 1
}
