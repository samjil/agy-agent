# agy-spawn.ps1
# 백그라운드 자식 프로세스를 콘솔 창 없이(CREATE_NO_WINDOW + STARTF_USESHOWWINDOW/SW_HIDE)
# 부모 핸들·파이프 상속 제어(bInheritHandles)와 함께 띄우는 공용 헬퍼입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-spawn.ps1")`
#
# 해결하는 문제:
#   1) 일반 ProcessStartInfo(.NET Framework 4.x / PS 5.1)는 UseShellExecute=false 일 때 WindowStyle=Hidden 을 무시합니다.
#      CreateNoWindow=true 만으로는 자식 프로세스(예: agy.exe 가 내부에서 부르는 agy.exe --version)가 새 콘솔 창(conhost/WT)을
#      잠깐 띄웠다 사라지는 깜빡임이 생길 수 있습니다.
#   2) Win32 CreateProcessW(CREATE_NO_WINDOW + STARTF_USESHOWWINDOW + SW_HIDE) 로 띄워 창이 보이지 않게 합니다.
#   3) 분리 실행(Start-AgyHiddenDetachedProcess)은 bInheritHandles=false 로 훅/워처의 stdout/stderr 파이프를 물려주지 않습니다.
#      출력을 받는 실행(Invoke-AgyHiddenWithOutput · Start-AgySpawnedProcess)은 표준 핸들을 넘겨야 하므로 bInheritHandles=true 이고,
#      부모 쪽 파이프 끝은 상속되지 않게(SetHandleInformation) 막습니다.
#   4) 출력을 받는 실행은 자식을 작업 개체(Job Object)에 넣어, 시간 초과 때 손자 프로세스까지 한꺼번에 끝냅니다.
#      손자가 파이프를 쥐고 있어도 출력 읽기는 정해진 시간만 기다리고 그때까지 받은 내용으로 돌아옵니다(무기한 대기 없음).
#
# 형식 이름의 V2: Add-Type 형식은 한 세션에서 다시 정의할 수 없어, 같은 세션에 예전 정의가 먼저 로드돼 있으면 새 멤버가 없습니다.
# C# 정의를 바꾸면 이름 끝의 버전(V2)을 올리고, 확인도 실제로 쓰는 형식 이름으로 합니다.

function Format-AgyCmdArg([string]$Arg) {
    if ($null -eq $Arg -or $Arg.Length -eq 0) { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq [char]92) {
            $backslashes++
        } elseif ($ch -eq [char]34) {
            [void]$sb.Append([string]::new([char]92, $backslashes * 2 + 1))
            [void]$sb.Append('"')
            $backslashes = 0
        } else {
            if ($backslashes -gt 0) { [void]$sb.Append([string]::new([char]92, $backslashes)); $backslashes = 0 }
            [void]$sb.Append($ch)
        }
    }
    if ($backslashes -gt 0) { [void]$sb.Append([string]::new([char]92, $backslashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# 인자는 따옴표 없는 원래 값으로 넘긴다. 여기서 Windows 규칙(CommandLineToArgvW)대로 감싸므로,
# 미리 따옴표를 붙여 넘기면 따옴표가 값의 일부로 전달된다.
function Build-AgyCommandLine([string]$FilePath, [string[]]$ArgumentList) {
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Format-AgyCmdArg $FilePath))
    foreach ($a in @($ArgumentList)) {
        if ($null -eq $a) { continue }
        [void]$parts.Add((Format-AgyCmdArg ([string]$a)))
    }
    return ($parts.ToArray() -join ' ')
}

function Ensure-AgySpawnTypesLoaded {
    if ("AgySpawnedProcessV2" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public static class AgySpawnNativeV2 {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_ATTRIBUTES {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        public int bInheritHandle;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, ref SECURITY_ATTRIBUTES lpPipeAttributes, uint nSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetHandleInformation(IntPtr hObject, uint dwMask, uint dwFlags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcessW(
        string lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint ResumeThread(IntPtr hThread);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool TerminateJobObject(IntPtr hJob, uint uExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, ref JOBOBJECT_BASIC_LIMIT_INFORMATION info, uint cbInfoLength);

    public const uint CREATE_NO_WINDOW = 0x08000000;
    public const uint CREATE_SUSPENDED = 0x00000004;
    public const int STARTF_USESHOWWINDOW = 0x00000001;
    public const int STARTF_USESTDHANDLES = 0x00000100;
    public const uint HANDLE_FLAG_INHERIT = 0x00000001;
    public const uint WAIT_OBJECT_0 = 0;
    public const uint INFINITE = 0xFFFFFFFF;
    public const int JobObjectBasicLimitInformation = 2;
    public const uint JOB_OBJECT_LIMIT_BREAKAWAY_OK = 0x00000800;

    public class SpawnResult {
        public int Pid;
        public int ExitCode;
        public string StdOut;
        public string StdErr;
        public bool TimedOut;
    }

    // 출력을 받는 실행으로 띄운 프로세스. 프로세스 핸들 · 작업 개체 핸들 · 부모 쪽 읽기 파이프를 담는다.
    public sealed class Launched {
        public int Pid;
        public IntPtr Process;
        public IntPtr Job;
        public IntPtr OutRead;
        public IntPtr ErrRead;
    }

    public static void CloseIf(ref IntPtr h) {
        if (h != IntPtr.Zero) { CloseHandle(h); h = IntPtr.Zero; }
    }

    public static uint ToWaitMs(int ms) { return ms < 0 ? INFINITE : (uint)ms; }

    public static bool IsSignaled(IntPtr h) {
        return h == IntPtr.Zero || WaitForSingleObject(h, 0) == WAIT_OBJECT_0;
    }

    // 1. 분리 실행: 기다리지 않고 PID 만 돌려준다(핸들 상속 없음, 창 없음).
    public static int StartHiddenDetached(string commandLine, string workingDir) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = 0; // SW_HIDE

        PROCESS_INFORMATION pi;
        StringBuilder cmdBuf = new StringBuilder(commandLine);
        bool ok = CreateProcessW(null, cmdBuf, IntPtr.Zero, IntPtr.Zero, false, CREATE_NO_WINDOW, IntPtr.Zero,
            string.IsNullOrEmpty(workingDir) ? null : workingDir, ref si, out pi);
        if (!ok) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        int pid = pi.dwProcessId;
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pid;
    }

    // 파이프 하나를 만들고 부모 쪽 끝은 상속되지 않게 한다. 실패하면 만든 핸들을 닫고 예외.
    static void MakePipe(ref SECURITY_ATTRIBUTES sa, bool childReads, out IntPtr parentEnd, out IntPtr childEnd) {
        IntPtr r, w;
        if (!CreatePipe(out r, out w, ref sa, 0)) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        IntPtr p = childReads ? w : r;
        IntPtr c = childReads ? r : w;
        if (!SetHandleInformation(p, HANDLE_FLAG_INHERIT, 0)) {
            int err = Marshal.GetLastWin32Error();
            CloseHandle(r);
            CloseHandle(w);
            throw new Win32Exception(err);
        }
        parentEnd = p;
        childEnd = c;
    }

    // 표준 입력은 곧바로 EOF, 표준 출력 · 오류는 파이프로 받는다. 자식은 멈춘 상태로 만들어 작업 개체에 넣은 뒤 깨운다.
    public static Launched LaunchRedirected(string commandLine, string workingDir) {
        SECURITY_ATTRIBUTES sa = new SECURITY_ATTRIBUTES();
        sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
        sa.bInheritHandle = 1;
        sa.lpSecurityDescriptor = IntPtr.Zero;

        IntPtr outRead = IntPtr.Zero, outWrite = IntPtr.Zero;
        IntPtr errRead = IntPtr.Zero, errWrite = IntPtr.Zero;
        IntPtr inRead = IntPtr.Zero, inWrite = IntPtr.Zero;
        IntPtr job = IntPtr.Zero;
        IntPtr hProcess = IntPtr.Zero, hThread = IntPtr.Zero;
        try {
            MakePipe(ref sa, false, out outRead, out outWrite);
            MakePipe(ref sa, false, out errRead, out errWrite);
            MakePipe(ref sa, true, out inWrite, out inRead);
            CloseIf(ref inWrite); // 표준 입력은 바로 EOF

            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
            si.wShowWindow = 0; // SW_HIDE
            si.hStdInput = inRead;
            si.hStdOutput = outWrite;
            si.hStdError = errWrite;

            PROCESS_INFORMATION pi;
            StringBuilder cmdBuf = new StringBuilder(commandLine);
            bool ok = CreateProcessW(null, cmdBuf, IntPtr.Zero, IntPtr.Zero, true, CREATE_NO_WINDOW | CREATE_SUSPENDED, IntPtr.Zero,
                string.IsNullOrEmpty(workingDir) ? null : workingDir, ref si, out pi);
            if (!ok) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            hProcess = pi.hProcess;
            hThread = pi.hThread;

            // 자식의 쓰기 끝은 부모에서 닫아야 자식이 끝날 때 EOF 가 온다
            CloseIf(ref outWrite);
            CloseIf(ref errWrite);
            CloseIf(ref inRead);

            job = CreateJobObjectW(IntPtr.Zero, null);
            if (job != IntPtr.Zero) {
                // 자손이 스스로 작업 개체에서 벗어나겠다고 요청하면 허용한다(그 요청이 실패해 agy 가 깨지지 않게)
                JOBOBJECT_BASIC_LIMIT_INFORMATION li = new JOBOBJECT_BASIC_LIMIT_INFORMATION();
                li.LimitFlags = JOB_OBJECT_LIMIT_BREAKAWAY_OK;
                SetInformationJobObject(job, JobObjectBasicLimitInformation, ref li, (uint)Marshal.SizeOf(typeof(JOBOBJECT_BASIC_LIMIT_INFORMATION)));
                if (!AssignProcessToJobObject(job, hProcess)) {
                    CloseIf(ref job); // 작업 개체 없이 진행(시간 초과 때는 프로세스만 끝낸다)
                }
            }
            if (ResumeThread(hThread) == 0xFFFFFFFF) {
                int err = Marshal.GetLastWin32Error();
                TerminateProcess(hProcess, 1);
                throw new Win32Exception(err);
            }

            Launched l = new Launched();
            l.Pid = pi.dwProcessId;
            l.Process = hProcess;
            l.Job = job;
            l.OutRead = outRead;
            l.ErrRead = errRead;
            hProcess = IntPtr.Zero;
            job = IntPtr.Zero;
            outRead = IntPtr.Zero;
            errRead = IntPtr.Zero;
            return l;
        } finally {
            CloseIf(ref hThread);
            CloseIf(ref hProcess);
            CloseIf(ref job);
            CloseIf(ref outRead);
            CloseIf(ref outWrite);
            CloseIf(ref errRead);
            CloseIf(ref errWrite);
            CloseIf(ref inRead);
            CloseIf(ref inWrite);
        }
    }

    // 프로세스 트리를 끝낸다(작업 개체가 있으면 그 안의 자손까지).
    public static void KillTree(Launched l) {
        if (l == null) return;
        if (l.Job != IntPtr.Zero) { TerminateJobObject(l.Job, 1); }
        if (l.Process != IntPtr.Zero) { TerminateProcess(l.Process, 1); }
    }

    public static void Release(Launched l) {
        if (l == null) return;
        CloseIf(ref l.Process);
        CloseIf(ref l.Job); // 작업 개체를 닫아도 자식은 끝나지 않는다(KILL_ON_JOB_CLOSE 를 쓰지 않음)
    }

    static int Remaining(DateTime until) {
        double ms = (until - DateTime.UtcNow).TotalMilliseconds;
        return ms <= 0 ? 0 : (int)ms;
    }

    // 2. 짧은 명령: 끝날 때까지(최대 timeoutMs) 기다리고 출력을 모아 돌려준다.
    //    시간 초과면 트리째 끝내고 TimedOut=true. 출력 읽기는 어떤 경우에도 정해진 시간 넘게 기다리지 않는다.
    public static SpawnResult RunHiddenWithOutput(string commandLine, string workingDir, int timeoutMs) {
        Launched l = LaunchRedirected(commandLine, workingDir);
        AgyPipeReaderV2 outR = new AgyPipeReaderV2(l.OutRead);
        AgyPipeReaderV2 errR = new AgyPipeReaderV2(l.ErrRead);
        l.OutRead = IntPtr.Zero;
        l.ErrRead = IntPtr.Zero;
        SpawnResult res = new SpawnResult();
        res.Pid = l.Pid;
        res.ExitCode = -1;
        try {
            if (WaitForSingleObject(l.Process, ToWaitMs(timeoutMs)) != WAIT_OBJECT_0) {
                res.TimedOut = true;
                KillTree(l);
                WaitForSingleObject(l.Process, 5000);
            }
            uint code;
            if (IsSignaled(l.Process) && GetExitCodeProcess(l.Process, out code)) {
                res.ExitCode = (int)code;
            }
            DateTime until = DateTime.UtcNow.AddMilliseconds(res.TimedOut ? 1000 : 5000);
            outR.WaitForEof(Remaining(until));
            errR.WaitForEof(Remaining(until));
            res.StdOut = outR.Text;
            res.StdErr = errR.Text;
            return res;
        } finally {
            Release(l);
        }
    }
}

// 파이프를 별도 스레드에서 끝(EOF)까지 읽어 모은다. 기다리는 쪽은 시간 제한을 두고, 그때까지 받은 내용을 읽을 수 있다.
public sealed class AgyPipeReaderV2 {
    private readonly StringBuilder _sb = new StringBuilder();
    private readonly ManualResetEvent _done = new ManualResetEvent(false);

    public AgyPipeReaderV2(IntPtr handle) {
        Thread t = new Thread(() => {
            try {
                using (FileStream fs = new FileStream(new SafeFileHandle(handle, true), FileAccess.Read, 4096, false))
                using (StreamReader r = new StreamReader(fs, Encoding.UTF8, true)) {
                    char[] buf = new char[4096];
                    int n;
                    while ((n = r.Read(buf, 0, buf.Length)) > 0) {
                        lock (_sb) { _sb.Append(buf, 0, n); }
                    }
                }
            } catch {
            } finally {
                _done.Set();
            }
        });
        t.IsBackground = true;
        t.Start();
    }

    public bool WaitForEof(int timeoutMs) { return _done.WaitOne(timeoutMs < 0 ? Timeout.Infinite : timeoutMs); }

    public bool Completed { get { return _done.WaitOne(0); } }

    public string Text { get { lock (_sb) { return _sb.ToString(); } } }
}

// 3. 긴 작업: System.Diagnostics.Process 와 비슷한 모양(Id · WaitForExit · HasExited · ExitCode · Kill · Dispose)으로 쓴다.
public sealed class AgySpawnedProcessV2 : IDisposable {
    private AgySpawnNativeV2.Launched _l;
    private AgyPipeReaderV2 _out;
    private AgyPipeReaderV2 _err;
    private bool _disposed;

    public int Id { get; private set; }

    // 끝난 뒤 남은 출력을 받을 때 EOF 를 기다리는 최대 시간(밀리초). 손자가 파이프를 쥐고 있어도 여기까지만 기다린다.
    public int OutputDrainMs = 10000;

    public static AgySpawnedProcessV2 Start(string commandLine, string workingDir) {
        AgySpawnNativeV2.Launched l = AgySpawnNativeV2.LaunchRedirected(commandLine, workingDir);
        AgySpawnedProcessV2 p = new AgySpawnedProcessV2();
        p._l = l;
        p.Id = l.Pid;
        p._out = new AgyPipeReaderV2(l.OutRead);
        p._err = new AgyPipeReaderV2(l.ErrRead);
        l.OutRead = IntPtr.Zero;
        l.ErrRead = IntPtr.Zero;
        return p;
    }

    public bool WaitForExit(int timeoutMs) {
        if (_l == null || _l.Process == IntPtr.Zero) return true;
        return AgySpawnNativeV2.WaitForSingleObject(_l.Process, AgySpawnNativeV2.ToWaitMs(timeoutMs)) == AgySpawnNativeV2.WAIT_OBJECT_0;
    }

    public void WaitForExit() { WaitForExit(-1); }

    // 종료 코드(259 = STILL_ACTIVE)가 아니라 핸들의 신호 상태로 판단한다.
    public bool HasExited {
        get { return _l == null || AgySpawnNativeV2.IsSignaled(_l.Process); }
    }

    // 아직 끝나지 않았거나 핸들을 닫았으면 -1
    public int ExitCode {
        get {
            if (_l == null || _l.Process == IntPtr.Zero) return -1;
            if (!AgySpawnNativeV2.IsSignaled(_l.Process)) return -1;
            uint code;
            if (AgySpawnNativeV2.GetExitCodeProcess(_l.Process, out code)) return (int)code;
            return -1;
        }
    }

    public string StandardOutput {
        get {
            if (_out == null) return "";
            _out.WaitForEof(OutputDrainMs);
            return _out.Text;
        }
    }

    public string StandardError {
        get {
            if (_err == null) return "";
            _err.WaitForEof(OutputDrainMs);
            return _err.Text;
        }
    }

    public void Kill() {
        if (_l != null) AgySpawnNativeV2.KillTree(_l);
    }

    public void Dispose() {
        if (_disposed) return;
        _disposed = true;
        AgySpawnNativeV2.Release(_l);
    }
}
"@
}

# 1. 백그라운드 분리 실행 (기다리지 않고 바로 반환, 파이프 상속 없음, 창 없음)
#    -NoShellFallback: 실패하면 WScript.Shell 로 대신 띄우지 않고 -1 을 돌려준다(호출한 쪽이 PID 로 시작을 확인하고 직접 대체할 때).
#    WScript.Shell 로 대신 띄운 경우에는 PID 를 알 수 없어 0 을 돌려준다.
function Start-AgyHiddenDetachedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [switch]$NoShellFallback
    )

    $cmdLine = Build-AgyCommandLine $FilePath $ArgumentList
    $cwd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $null } else { $WorkingDirectory.Trim() }

    try {
        Ensure-AgySpawnTypesLoaded
        return [int][AgySpawnNativeV2]::StartHiddenDetached($cmdLine, $cwd)
    } catch {
        if ($NoShellFallback) { return -1 }
        try {
            $sh = New-Object -ComObject WScript.Shell
            if ($cwd) { try { $sh.CurrentDirectory = $cwd } catch {} }
            [void]$sh.Run($cmdLine, 0, $false)
            return 0
        } catch {
            return -1
        }
    }
}

# 2. 짧은 명령 실행 및 출력 수집 (타임아웃 대기, 출력 캡처, 창 없음)
#    시간 초과면 프로세스 트리를 끝내고 TimedOut=$true 로 곧바로 돌아온다(손자가 파이프를 쥐고 있어도 오래 걸리지 않는다).
#    헬퍼 자체가 실패하면 Pid=-1.
function Invoke-AgyHiddenWithOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [int]$TimeoutSeconds = 30
    )

    $cmdLine = Build-AgyCommandLine $FilePath $ArgumentList
    $cwd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $null } else { $WorkingDirectory.Trim() }

    try {
        Ensure-AgySpawnTypesLoaded
        $res = [AgySpawnNativeV2]::RunHiddenWithOutput($cmdLine, $cwd, $TimeoutSeconds * 1000)
        return [pscustomobject]@{
            Pid      = $res.Pid
            ExitCode = $res.ExitCode
            StdOut   = [string]$res.StdOut
            StdErr   = [string]$res.StdErr
            TimedOut = [bool]$res.TimedOut
        }
    } catch {
        return [pscustomobject]@{
            Pid      = -1
            ExitCode = -1
            StdOut   = ""
            StdErr   = $_.Exception.Message
            TimedOut = $false
        }
    }
}

# 3. 긴 작업 실행용 관리 프로세스 생성 (출력 스트림 비동기 읽기, 진행 점검 루프 지원, 창 없음)
#    실패하면 예외를 그대로 던진다(호출한 쪽이 System.Diagnostics.Process 로 대신한다).
function Start-AgySpawnedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = ""
    )

    $cmdLine = Build-AgyCommandLine $FilePath $ArgumentList
    $cwd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $null } else { $WorkingDirectory.Trim() }

    Ensure-AgySpawnTypesLoaded
    return [AgySpawnedProcessV2]::Start($cmdLine, $cwd)
}
