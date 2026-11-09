# 콘솔 창이 잠깐 떴다 사라지는 일이 어떤 프로세스 때문인지 알아내려고 오래 켜 두는 감시기(개발·진단용, 설치본에는 들어가지 않는다).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\watch-console-windows.ps1                 # 24시간 감시(기본)
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\watch-console-windows.ps1 -Hours 8
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\watch-console-windows.ps1 -Summary        # 쌓인 기록을 "누가 만들었나" 별로 요약
# 창 없이 띄우기: [System.Diagnostics.Process]::Start 로 CreateNoWindow=true 로 시작하면 된다(이 스크립트 자신이 창을 만들지 않는다).
#
# 하는 일: 10ms 마다 화면에 보이는 콘솔 창(ConsoleWindowClass / Windows Terminal 의 호스팅 창 / PseudoConsoleWindow)을 세다가,
# 새 창이 생기면 그 순간의 프로세스 목록을 보고 "그 콘솔을 만든 프로세스(conhost 의 부모)"와 그 부모 사슬을 기록에 남긴다.
# 이렇게 하면 창을 띄운 쪽이 워처·agy 인지, 다른 프로그램(예: VS Code 의 docker 호출)인지 가려낼 수 있다.
# 기록: ~\.samjil\logs\console-window-watch.log (한 줄에 창 하나). 30분마다 "alive" 줄을 남겨 살아 있음을 알린다.

param(
    [double]$Hours = 24,
    [switch]$Summary,
    [string]$LogPath = (Join-Path $env:USERPROFILE ".samjil\logs\console-window-watch.log")
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath -Parent) | Out-Null

if ($Summary) {
    if (-not (Test-Path -LiteralPath $LogPath)) { Write-Host "기록이 없습니다: $LogPath"; exit 0 }
    $lines = @(Get-Content -LiteralPath $LogPath -Encoding UTF8)
    $events = @($lines | Where-Object { $_ -match ' WINDOW ' })
    Write-Host ("기록 {0}줄 / 새 콘솔 창 {1}건" -f $lines.Count, $events.Count)
    $groups = $events | ForEach-Object { if ($_ -match 'culprit=(\S+)') { $Matches[1] } else { "(알 수 없음)" } } | Group-Object | Sort-Object Count -Descending
    foreach ($g in $groups) { Write-Host ("  {0,4}건  {1}" -f $g.Count, $g.Name) }
    Write-Host "최근 5건:"
    $events | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" }
    exit 0
}

# 한 번에 하나만 돈다
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\samjil-console-window-watch", [ref]$createdNew)
if (-not $createdNew) { Write-Host "이미 감시 중입니다."; exit 0 }

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ConWinSnap {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static List<string> Snap() {
    var res = new List<string>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      var sb = new StringBuilder(256); GetClassName(h, sb, 256);
      string c = sb.ToString();
      if (c == "ConsoleWindowClass" || c == "CASCADIA_HOSTING_WINDOW_CLASS" || c == "PseudoConsoleWindow") {
        uint pid; GetWindowThreadProcessId(h, out pid);
        res.Add(h.ToInt64() + "|" + c + "|" + pid);
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
"@

function Write-Log([string]$text) {
    [System.IO.File]::AppendAllText($LogPath, ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + $text + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}
function Short([string]$s, [int]$n = 120) { $t = ("" + $s) -replace '\s+', ' '; if ($t.Length -gt $n) { return $t.Substring(0, $n) } else { return $t } }

# 프로세스 목록 한 장: pid -> @{ Name; Parent; Cmd; Created }
function Get-ProcTable {
    $t = @{}
    foreach ($p in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $t[[int]$p.ProcessId] = @{ Name = [string]$p.Name; Parent = [int]$p.ParentProcessId; Cmd = [string]$p.CommandLine; Created = $p.CreationDate }
    }
    return $t
}
function Get-Chain($table, [int]$pid0, [int]$depth = 4) {
    $names = @(); $cur = $pid0
    for ($i = 0; $i -lt $depth; $i++) {
        if (-not $table.ContainsKey($cur)) { break }
        $names += ("{0}[{1}]" -f $table[$cur].Name, $cur)
        $cur = $table[$cur].Parent
    }
    return ($names -join " <- ")
}

$base = @{}
foreach ($x in [ConWinSnap]::Snap()) { $base[$x] = $true }
$seen = @{}
$end = (Get-Date).AddHours($Hours)
$nextAlive = (Get-Date).AddMinutes(30)
Write-Log ("START 감시를 시작합니다 (PID {0}, {1}시간, 기존 창 {2}개는 제외)" -f $PID, $Hours, $base.Count)
try {
    while ((Get-Date) -lt $end) {
        foreach ($x in [ConWinSnap]::Snap()) {
            if ($base.ContainsKey($x) -or $seen.ContainsKey($x)) { continue }
            $seen[$x] = $true
            $parts = $x -split '\|'
            $ownerPid = [int]$parts[2]
            $table = Get-ProcTable
            # 새로 생긴 conhost(= 이 창의 콘솔을 만든 클라이언트의 자식)를 찾아, 그 부모를 "만든 쪽"으로 본다
            $cut = (Get-Date).AddSeconds(-4)
            $recentConhost = @($table.GetEnumerator() | Where-Object { $_.Value.Name -eq "conhost.exe" -and $_.Value.Created -gt $cut })
            $culprit = "(알 수 없음)"; $chain = ""; $clientCmd = ""
            if ($recentConhost.Count -gt 0) {
                # 가장 최근에 생긴 conhost 의 부모가 콘솔 클라이언트다
                $ch = $recentConhost | Sort-Object { $_.Value.Created } -Descending | Select-Object -First 1
                $clientPid = $ch.Value.Parent
                if ($table.ContainsKey($clientPid)) {
                    $culprit = $table[$clientPid].Name
                    $clientCmd = Short $table[$clientPid].Cmd 140
                    $chain = Get-Chain $table $clientPid 5
                }
            }
            Write-Log ("WINDOW class={0} hwnd={1} owner={2} culprit={3} chain=[{4}] cmd=[{5}]" -f $parts[1], $parts[0], $ownerPid, $culprit, $chain, $clientCmd)
        }
        if ((Get-Date) -ge $nextAlive) { Write-Log "alive"; $nextAlive = (Get-Date).AddMinutes(30) }
        Start-Sleep -Milliseconds 10
    }
    Write-Log "END 감시 시간이 끝났습니다"
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
