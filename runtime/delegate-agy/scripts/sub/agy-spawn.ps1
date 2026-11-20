# agy-spawn.ps1
# 백그라운드 자식 프로세스를 콘솔 창 없이(CREATE_NO_WINDOW) 부모 핸들·파이프 상속 없이(bInheritHandles=false) 띄우는 공용 헬퍼입니다.
# dot-source 해서 씁니다: `. (Join-Path $PSScriptRoot "agy-spawn.ps1")`
#   - 일반 ProcessStartInfo(.NET Framework 4.x / PS 5.1)는 bInheritHandles=TRUE 라서 훅의 stdout/stderr 파이프를 자식이 물려받아 종료가 지연되고,
#     Start-Process -WindowStyle Hidden 은 콘솔 창을 만들었다가 숨기므로 창이 잠깐 깜빡일 수 있습니다.
#   - Win32 CreateProcessW(CREATE_NO_WINDOW + bInheritHandles=false) 는 커널 수준에서 창 생성을 막고 부모 파이프 상속도 차단하면서 환경변수는 그대로 전달합니다.
#   - 실제 백그라운드 기동이 필요할 때만 Add-Type 을 컴파일하도록 함수 내부에서 지연 등록합니다.

function Start-AgyHiddenDetachedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = ""
    )

    function Format-CmdArg([string]$Arg) {
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

    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Format-CmdArg $FilePath))
    foreach ($a in @($ArgumentList)) {
        if ($null -eq $a) { continue }
        [void]$parts.Add((Format-CmdArg ([string]$a)))
    }
    $cmdLine = ($parts.ToArray()) -join ' '
    $cwd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $null } else { $WorkingDirectory.Trim() }

    try {
        if (-not ("AgyDetachedProcess" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class AgyDetachedProcess {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO {
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
    private struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(
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
    private static extern bool CloseHandle(IntPtr hObject);

    public static int StartHiddenDetached(string commandLine, string workingDir) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = 0x00000001; // STARTF_USESHOWWINDOW
        si.wShowWindow = 0;      // SW_HIDE

        PROCESS_INFORMATION pi;
        StringBuilder cmdBuf = new StringBuilder(commandLine);
        const uint CREATE_NO_WINDOW = 0x08000000;
        bool ok = CreateProcessW(
            null,
            cmdBuf,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            CREATE_NO_WINDOW,
            IntPtr.Zero,
            string.IsNullOrEmpty(workingDir) ? null : workingDir,
            ref si,
            out pi
        );
        if (!ok) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        int pid = pi.dwProcessId;
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pid;
    }
}
"@
        }
        return [int][AgyDetachedProcess]::StartHiddenDetached($cmdLine, $cwd)
    } catch {
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
