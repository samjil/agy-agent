# setup-sub-accounts.ps1
# Windows 부계정(agy-sub1, agy-sub2, ...) 멀티 계정 위임 풀의 초기 구성 · ACL · 정션 · 작업 스케줄러 등록 스크립트.
#
# 주의:
#   - 단일 계정 기본 사용자에게는 이 스크립트가 필요하지 않으며(install.ps1 은 이 스크립트를 호출하지 않습니다),
#     sub_accounts 설정이 없거나 enabled=false 일 때는 기존 단일 계정 동작과 100% 동일하게 돌아갑니다.
#   - Windows 계정 생성, C:\ProgramData ACL, 작업 스케줄러 등록을 위해 관리자 권한 PowerShell 에서 실행해야 합니다.
#   - 작업에 쓰는 부계정 비밀번호는 LogonType=Password 스케줄 작업 등록에만 사용되며 빈 비밀번호는 허용되지 않습니다.
#
# 사용법:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup-sub-accounts.ps1 -Slots sub1,sub2
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup-sub-accounts.ps1 -DryRun

param(
    [string[]]$Slots = @("sub1", "sub2"),
    [string]$UserPrefix = "agy-",
    [string]$PrimaryUser = $env:USERNAME,
    [string]$BridgeDir = "C:\ProgramData\samjil\sub-bridge",
    [string]$SharedDelegateDir = "C:\ProgramData\samjil\delegate-agy",
    [string]$PrimaryHome = $env:USERPROFILE,
    [string]$ModelsLocalPath = "",
    [string]$SourceDelegateDir = "",
    [switch]$DryRun,
    [switch]$SkipAdminCheck,
    [switch]$SkipAccountCreation,
    [switch]$SkipTaskRegistration,
    [switch]$SkipAcl,
    [switch]$SkipJunctions,
    [string]$PasswordPlainText = ""
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Test-IsAdministrator {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Assert-SetupSubAdminPrivilege {
    param([bool]$IsAdmin, [bool]$DryRun, [bool]$SkipAdminCheck)
    if ($IsAdmin -or $DryRun -or $SkipAdminCheck) { return $true }
    throw "관리자 권한이 필요합니다. 시작 메뉴에서 PowerShell을 '관리자 권한으로 실행'한 뒤 setup-sub-accounts.ps1 을 다시 실행해 주세요 (단순 미리보기는 -DryRun 사용)."
}

function ConvertTo-OrderedMap {
    param($InputObj)
    if ($null -eq $InputObj) { return $null }
    if ($InputObj -is [System.Collections.IDictionary]) {
        $ord = [ordered]@{}
        foreach ($k in $InputObj.Keys) { $ord[[string]$k] = ConvertTo-OrderedMap $InputObj[$k] }
        return $ord
    }
    if ($InputObj -is [pscustomobject]) {
        $ord = [ordered]@{}
        foreach ($p in $InputObj.PSObject.Properties) { $ord[[string]$p.Name] = ConvertTo-OrderedMap $p.Value }
        return $ord
    }
    if (($InputObj -is [System.Collections.IEnumerable]) -and -not ($InputObj -is [string])) {
        $arr = New-Object System.Collections.ArrayList
        foreach ($item in $InputObj) { [void]$arr.Add((ConvertTo-OrderedMap $item)) }
        return ,$arr.ToArray()
    }
    return $InputObj
}

function Merge-SubAccountsModelsLocalJson {
    param(
        [string]$ExistingJson = "",
        [object[]]$SlotConfigs = @(),
        [string]$BridgeDir = "C:\ProgramData\samjil\sub-bridge",
        [string]$SharedDelegateDir = "C:\ProgramData\samjil\delegate-agy",
        [string]$AgyBinDir = ""
    )
    $root = [ordered]@{}
    if ($ExistingJson -and $ExistingJson.Trim()) {
        $parsed = ConvertFrom-Json -InputObject $ExistingJson
        $converted = ConvertTo-OrderedMap $parsed
        if ($converted -is [System.Collections.IDictionary]) { $root = $converted }
    }

    $existingSub = if ($root.Contains("sub_accounts") -and ($root["sub_accounts"] -is [System.Collections.IDictionary])) { $root["sub_accounts"] } else { $null }
    $existingSlotsById = @{}
    if ($existingSub -and $existingSub.Contains("slots") -and $existingSub["slots"]) {
        foreach ($es in @($existingSub["slots"])) {
            if ($es -is [System.Collections.IDictionary] -and $es["id"]) {
                $existingSlotsById[[string]$es["id"]] = $es
            }
        }
    }

    $mergedSlots = New-Object System.Collections.ArrayList
    foreach ($sc in @($SlotConfigs)) {
        $sid = [string]$sc.id
        $prevSlot = if ($existingSlotsById.ContainsKey($sid)) { $existingSlotsById[$sid] } else { $null }
        $label = if ($prevSlot -and $prevSlot["label"]) { [string]$prevSlot["label"] } elseif ($sc.label) { [string]$sc.label } else { $sid }
        $maxPar = if ($prevSlot -and $null -ne $prevSlot["max_parallel"]) { [int]$prevSlot["max_parallel"] } elseif ($null -ne $sc.max_parallel) { [int]$sc.max_parallel } else { 5 }
        [void]$mergedSlots.Add([ordered]@{
            id           = $sid
            windows_user = [string]$sc.windows_user
            label        = $label
            max_parallel = $maxPar
        })
    }

    $modelPattern = if ($existingSub -and $existingSub["model_pattern"]) { [string]$existingSub["model_pattern"] } else { "^gemini-4-hydrogen-" }
    $ackTimeout = if ($existingSub -and $null -ne $existingSub["ack_timeout_sec"]) { [int]$existingSub["ack_timeout_sec"] } else { 12 }
    $cooldownSec = if ($existingSub -and $null -ne $existingSub["cooldown_sec"]) { [int]$existingSub["cooldown_sec"] } else { 60 }
    $fallbackPri = if ($existingSub -and $null -ne $existingSub["fallback_to_primary"]) { [bool]$existingSub["fallback_to_primary"] } else { $true }
    $asyncUsage = if ($existingSub -and $null -ne $existingSub["async_usage_check"]) { [bool]$existingSub["async_usage_check"] } else { $true }
    $priCmds = if ($existingSub -and $existingSub["primary_only_cmds"]) { @($existingSub["primary_only_cmds"]) } else { @("browser") }
    $resolvedAgyBin = if ($AgyBinDir) { $AgyBinDir } elseif ($existingSub -and $existingSub["agy_bin_dir"]) { [string]$existingSub["agy_bin_dir"] } else { "" }

    $subOut = [ordered]@{
        enabled             = $true
        bridge_dir          = $BridgeDir
        shared_delegate_dir = $SharedDelegateDir
        model_pattern       = $modelPattern
        ack_timeout_sec     = $ackTimeout
        cooldown_sec        = $cooldownSec
        fallback_to_primary = $fallbackPri
        async_usage_check   = $asyncUsage
        primary_only_cmds   = @($priCmds)
        slots               = @($mergedSlots.ToArray())
    }
    if ($resolvedAgyBin) { $subOut["agy_bin_dir"] = $resolvedAgyBin }
    $root["sub_accounts"] = $subOut

    return (ConvertTo-Json -InputObject $root -Depth 20)
}

function Remove-SensitiveSettingsKeys {
    param($Node)
    if ($null -eq $Node) { return $null }
    if ($Node -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $Node.Keys) {
            $ks = [string]$k
            if ($ks -match '(?i)(oauth|token|api[-_]?key|secret|password|credential|auth|mcp|cookie|session)') { continue }
            $out[$ks] = Remove-SensitiveSettingsKeys $Node[$k]
        }
        return $out
    }
    if (($Node -is [System.Collections.IEnumerable]) -and -not ($Node -is [string])) {
        $arr = New-Object System.Collections.ArrayList
        foreach ($item in $Node) { [void]$arr.Add((Remove-SensitiveSettingsKeys $item)) }
        return ,$arr.ToArray()
    }
    return $Node
}

function New-SubAccountNonSecretSettingsJson {
    param(
        [string]$PrimarySettingsJson = "",
        [string[]]$ExtraWorkspaces = @()
    )
    $safeAllowed = @(
        "allowNonWorkspaceAccess", "artifactReviewPolicy", "trustedWorkspaces",
        "approvalMode", "autoAccept", "ui", "editor", "theme", "locale", "language",
        "telemetry", "general"
    )
    $out = [ordered]@{}
    if ($PrimarySettingsJson -and $PrimarySettingsJson.Trim()) {
        $rawObj = ConvertTo-OrderedMap (ConvertFrom-Json -InputObject $PrimarySettingsJson)
        if ($rawObj -is [System.Collections.IDictionary]) {
            foreach ($k in $rawObj.Keys) {
                $ks = [string]$k
                if ($safeAllowed -notcontains $ks) { continue }
                if ($ks -match '(?i)(oauth|token|api[-_]?key|secret|password|credential|auth|mcp|cookie|session)') { continue }
                $out[$ks] = Remove-SensitiveSettingsKeys $rawObj[$k]
            }
        }
    }

    $out["allowNonWorkspaceAccess"] = $true

    $wsSet = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($out.Contains("trustedWorkspaces") -and $out["trustedWorkspaces"]) {
        foreach ($w in @($out["trustedWorkspaces"])) {
            $ws = [string]$w
            if ($ws -and $seen.Add($ws)) { [void]$wsSet.Add($ws) }
        }
    }
    foreach ($ew in @($ExtraWorkspaces)) {
        $ews = [string]$ew
        if ($ews -and $seen.Add($ews)) { [void]$wsSet.Add($ews) }
    }
    if ($wsSet.Count -gt 0) {
        $out["trustedWorkspaces"] = @($wsSet.ToArray())
    }

    return (ConvertTo-Json -InputObject $out -Depth 20)
}

function Get-SubAccountJunctionSpecs {
    param(
        [Parameter(Mandatory = $true)][string]$PrimaryHome,
        [Parameter(Mandatory = $true)][string]$SubHome
    )
    $agentsSrc = Join-Path $PrimaryHome ".agents\skills"
    $rulesSrc = Join-Path $PrimaryHome ".gemini\config\rules"
    $specs = @(
        [pscustomobject]@{
            LinkPath     = Join-Path $SubHome ".agents\skills"
            TargetPath   = $agentsSrc
            Required     = $true
            SourceExists = (Test-Path -LiteralPath $agentsSrc -PathType Container)
            Description  = "공용 스킬 정션(.agents\skills -> 본계정)"
        },
        [pscustomobject]@{
            LinkPath     = Join-Path $SubHome ".claude\skills"
            TargetPath   = $agentsSrc
            Required     = $false
            SourceExists = (Test-Path -LiteralPath $agentsSrc -PathType Container)
            Description  = "Claude 스킬 정션(.claude\skills -> 본계정 .agents\skills)"
        },
        [pscustomobject]@{
            LinkPath     = Join-Path $SubHome ".gemini\config\skills"
            TargetPath   = $agentsSrc
            Required     = $false
            SourceExists = (Test-Path -LiteralPath $agentsSrc -PathType Container)
            Description  = "Gemini 스킬 정션(.gemini\config\skills -> 본계정 .agents\skills)"
        },
        [pscustomobject]@{
            LinkPath     = Join-Path $SubHome ".gemini\config\rules"
            TargetPath   = $rulesSrc
            Required     = $false
            SourceExists = (Test-Path -LiteralPath $rulesSrc -PathType Container)
            Description  = "Gemini 전역 규칙 정션(.gemini\config\rules -> 본계정)"
        }
    )
    return $specs
}

function New-SubWatcherTaskXml {
    param(
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$SlotId,
        [Parameter(Mandatory = $true)][string]$BridgeDir,
        [Parameter(Mandatory = $true)][string]$SharedDelegateDir
    )
    $esc = { param([string]$v) [System.Security.SecurityElement]::Escape($v) }
    $supScript = Join-Path $SharedDelegateDir "scripts\sub\sub-supervisor.ps1"
    $argsStr = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -SubSlot {1} -BridgeDir "{2}"' -f $supScript, $SlotId, $BridgeDir
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Samjil Agy Sub-Account Watcher Supervisor ($(& $esc $SlotId))</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$(& $esc $UserId)</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$(& $esc $argsStr)</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

function Get-SubCreateProfileBufferCapacity {
    <# Win32 userenv!CreateProfile RPC 는 MAX_PATH(260) 초과 버퍼를 0x800706F7 로 거부하므로 260 을 유지한다. #>
    return 260
}

function Resolve-SubUserProfileDir {
    param([string]$WindowsUser, [string]$ComputerName = $env:COMPUTERNAME)
    try {
        $nt = New-Object System.Security.Principal.NTAccount($ComputerName, $WindowsUser)
        $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
        if (Test-Path -LiteralPath $regPath) {
            $pImg = (Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue).ProfileImagePath
            if ($pImg) { return [string]$pImg }
        }
        try {
            if (-not ("SamjilNativeProfile" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SamjilNativeProfile {
    [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int CreateProfile([MarshalAs(UnmanagedType.LPWStr)] string pszUserSid,
                                            [MarshalAs(UnmanagedType.LPWStr)] string pszUserName,
                                            [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszProfilePath,
                                            uint cchProfilePath);
}
"@ -ErrorAction SilentlyContinue | Out-Null
            }
            $cap = Get-SubCreateProfileBufferCapacity
            $sb = New-Object System.Text.StringBuilder $cap
            $hr = [SamjilNativeProfile]::CreateProfile($sid, $WindowsUser, $sb, [uint32]$sb.Capacity)
            if ($hr -eq 0 -or $hr -eq -2147024713) { # S_OK or ERROR_ALREADY_EXISTS
                $resolved = $sb.ToString()
                if ($resolved -and (Test-Path -LiteralPath $resolved)) { return $resolved }
                if (Test-Path -LiteralPath $regPath) {
                    $pImg2 = (Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue).ProfileImagePath
                    if ($pImg2) { return [string]$pImg2 }
                }
            } else {
                Write-Warning ("CreateProfile({0}) 반환 코드 HRESULT=0x{1:X8}" -f $WindowsUser, $hr)
            }
        } catch {
            Write-Warning ("CreateProfile({0}) 호출 오류: {1}" -f $WindowsUser, $_.Exception.Message)
        }
    } catch {}
    $fallback = Join-Path (Split-Path $env:USERPROFILE -Parent) $WindowsUser
    return $fallback
}

function Get-SubBridgeSlotAclArgs {
    param(
        [Parameter(Mandatory = $true)][string]$SlotRoot,
        [Parameter(Mandatory = $true)][string]$PrimaryPrincipal,
        [Parameter(Mandatory = $true)][string]$SubPrincipal
    )
    return @(
        $SlotRoot, "/inheritance:r",
        "/grant", "SYSTEM:(OI)(CI)F",
        "/grant", "Administrators:(OI)(CI)F",
        "/grant", "${PrimaryPrincipal}:(OI)(CI)M",
        "/grant", "${SubPrincipal}:(OI)(CI)M",
        "/C", "/Q"
    )
}

function Invoke-IcaclsGrant {
    param([string]$TargetPath, [string]$Principal, [string]$Rights, [switch]$InheritContainer)
    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    $perm = if ($InheritContainer) { "${Principal}:(OI)(CI)$Rights" } else { "${Principal}:$Rights" }
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & icacls.exe $TargetPath /grant $perm /C /Q 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($code -ne 0) {
        throw "ACL 부여 실패 ($TargetPath -> $perm): $out"
    }
}

function Get-SubAncestorDirectories {
    <# PrimaryHome(포함)부터 TargetPath 의 직계 부모까지 상위 디렉터리 목록을 위에서 아래 순으로 돌려준다. #>
    param(
        [Parameter(Mandatory = $true)][string]$PrimaryHome,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )
    $list = New-Object System.Collections.ArrayList
    $normHome = $PrimaryHome.TrimEnd('\')
    $anc = Split-Path $TargetPath -Parent
    while ($anc -and $anc.StartsWith($normHome, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$list.Add($anc)
        if ($anc.TrimEnd('\') -ieq $normHome) { break }
        $next = Split-Path $anc -Parent
        if ($next -eq $anc) { break }
        $anc = $next
    }
    [void]$list.Reverse()
    $outArr = @($list.ToArray())
    return $outArr
}

function Grant-SubAncestorTraverseAndRead {
    <# 본계정 프로필 아래 경로까지 Traverse(X) 를 부여하고 대상 경로에 (OI)(CI)(RX) 를 부여한다. #>
    param(
        [Parameter(Mandatory = $true)][string]$PrimaryHome,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$Principal
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    foreach ($anc in @(Get-SubAncestorDirectories -PrimaryHome $PrimaryHome -TargetPath $TargetPath)) {
        Invoke-IcaclsGrant -TargetPath $anc -Principal $Principal -Rights "(NP)(X,RA,REA,RC,S)"
    }
    Invoke-IcaclsGrant -TargetPath $TargetPath -Principal $Principal -Rights "(RX)" -InheritContainer
}

function New-SubDirectoryJunction {
    <# 공백 포함 경로에도 중첩 따옴표 깨짐 없이 NTFS 디렉터리 정션(mklink /J)을 생성한다. #>
    param(
        [Parameter(Mandatory = $true)][string]$LinkPath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = '/c mklink /J "' + $LinkPath + '" "' + $TargetPath + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        $msg = (($stdout + "`r`n" + $stderr).Trim())
        throw "정션 생성 실패 ($LinkPath -> $TargetPath, 종료코드=$($proc.ExitCode)): $msg"
    }
    return $stdout
}

function Ensure-SubLocalGroupMembership {
    <# New-LocalUser 로 만든 부계정이 로캘과 무관하게 BUILTIN\Users(S-1-5-32-545) 에 속하도록 보장한다. #>
    param([Parameter(Mandatory = $true)][string]$WindowsUser)
    $usersSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    $usersGroupFull = $usersSid.Translate([System.Security.Principal.NTAccount]).Value
    $usersGroupName = ($usersGroupFull -split '\\')[-1]
    try {
        Add-LocalGroupMember -Group $usersGroupName -Member $WindowsUser -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        if ($msg -notmatch '(?i)(already|member|이미|1378)') {
            throw "부계정 Users 그룹 추가 실패 ($WindowsUser -> $usersGroupFull): $msg"
        }
    }
}

function Grant-SubBatchLogonRight {
    <# LSA LsaAddAccountRights 로 LogonType=Password 작업에 필요한 SeBatchLogonRight(배치 작업으로 로그온)를 부여한다. #>
    param([Parameter(Mandatory = $true)][string]$AccountName)
    if (-not ("SamjilLsaUserRightHelper" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;

public static class SamjilLsaUserRightHelper {
    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_OBJECT_ATTRIBUTES {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_UNICODE_STRING {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    private const uint POLICY_LOOKUP_NAMES = 0x0800;
    private const uint POLICY_CREATE_ACCOUNT = 0x0010;
    private const uint POLICY_VIEW_LOCAL_INFORMATION = 0x0001;

    [DllImport("advapi32.dll", PreserveSig = true)]
    private static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle);

    [DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
    private static extern uint LsaAddAccountRights(IntPtr PolicyHandle, IntPtr AccountSid, LSA_UNICODE_STRING[] UserRights, uint CountOfRights);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint LsaClose(IntPtr PolicyHandle);

    [DllImport("advapi32.dll")]
    private static extern uint LsaNtStatusToWinError(uint status);

    public static void AddPrivilege(string accountName, string privilegeName) {
        IntPtr policyHandle = IntPtr.Zero;
        var systemName = new LSA_UNICODE_STRING();
        var objectAttributes = new LSA_OBJECT_ATTRIBUTES();
        objectAttributes.Length = Marshal.SizeOf(objectAttributes);
        uint nts = LsaOpenPolicy(ref systemName, ref objectAttributes, POLICY_LOOKUP_NAMES | POLICY_CREATE_ACCOUNT | POLICY_VIEW_LOCAL_INFORMATION, out policyHandle);
        if (nts != 0) throw new Win32Exception((int)LsaNtStatusToWinError(nts));
        try {
            var account = new NTAccount(accountName);
            var sid = (SecurityIdentifier)account.Translate(typeof(SecurityIdentifier));
            byte[] sidBytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(sidBytes, 0);
            IntPtr sidPtr = Marshal.AllocHGlobal(sidBytes.Length);
            Marshal.Copy(sidBytes, 0, sidPtr, sidBytes.Length);
            try {
                var userRights = new LSA_UNICODE_STRING[1];
                userRights[0] = new LSA_UNICODE_STRING();
                userRights[0].Buffer = Marshal.StringToHGlobalUni(privilegeName);
                userRights[0].Length = (ushort)(privilegeName.Length * 2);
                userRights[0].MaximumLength = (ushort)((privilegeName.Length + 1) * 2);
                try {
                    nts = LsaAddAccountRights(policyHandle, sidPtr, userRights, 1);
                    if (nts != 0) throw new Win32Exception((int)LsaNtStatusToWinError(nts));
                } finally {
                    Marshal.FreeHGlobal(userRights[0].Buffer);
                }
            } finally {
                Marshal.FreeHGlobal(sidPtr);
            }
        } finally {
            if (policyHandle != IntPtr.Zero) LsaClose(policyHandle);
        }
    }
}
"@ -ErrorAction Stop | Out-Null
    }
    [SamjilLsaUserRightHelper]::AddPrivilege($AccountName, "SeBatchLogonRight")
}

function Register-SubWatcherScheduledTask {
    <# schtasks.exe 명령줄 인자 충돌(/XML+/RU+/RP)과 비밀번호 노출 없이 Schedule.Service COM 으로 작업을 등록·즉시 기동한다. #>
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$XmlText,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$PlainPassword
    )
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $folder = $svc.GetFolder("\")
    $TASK_CREATE_OR_UPDATE = 6
    $TASK_LOGON_PASSWORD = 1
    $regTask = $folder.RegisterTask($TaskName, $XmlText, $TASK_CREATE_OR_UPDATE, $UserId, $PlainPassword, $TASK_LOGON_PASSWORD, $null)
    try {
        [void]$regTask.Run($null)
    } catch {
        Write-Warning ("스케줄 작업은 등록되었으나 즉시 실행(Run)에서 경고가 발생했습니다 ($TaskName): " + $_.Exception.Message)
    }
    return $regTask
}

if ($MyInvocation.InvocationName -eq '.') { return }

[void](Assert-SetupSubAdminPrivilege -IsAdmin (Test-IsAdministrator) -DryRun ([bool]$DryRun) -SkipAdminCheck ([bool]$SkipAdminCheck))

$expandedSlots = @()
foreach ($rawSlot in @($Slots)) {
    foreach ($part in ([string]$rawSlot -split ',')) {
        $trimmed = $part.Trim()
        if ($trimmed) { $expandedSlots += $trimmed }
    }
}
$Slots = @($expandedSlots)
foreach ($s in @($Slots)) {
    if ([string]::IsNullOrWhiteSpace($s) -or $s -notmatch '^[A-Za-z0-9_-]{1,32}$') {
        throw "잘못된 슬롯 ID 입니다: [$s] (영문/숫자/-/_ 만 허용)"
    }
}
if (@($Slots).Count -eq 0) { throw "최소 1개 이상의 -Slots 가 필요합니다." }

if (-not $SourceDelegateDir) { $SourceDelegateDir = Split-Path $PSScriptRoot -Parent }
if (-not $ModelsLocalPath) { $ModelsLocalPath = Join-Path $PrimaryHome ".samjil\delegate-agy\config\models.local.json" }

. (Join-Path $PSScriptRoot "sub\agy-models.ps1")
. (Join-Path $PSScriptRoot "sub\agy-sub-bridge.ps1")

$slotConfigs = @()
for ($idx = 0; $idx -lt @($Slots).Count; $idx++) {
    $sid = [string]$Slots[$idx]
    $winUser = "$UserPrefix$sid"
    $lbl = if ($sid -match '^sub(\d+)$') { "Sub$($Matches[1])" } else { $sid }
    $slotConfigs += [ordered]@{
        id           = $sid
        windows_user = $winUser
        label        = $lbl
        max_parallel = 5
    }
}

$agyCmdResolved = Get-Command agy -ErrorAction SilentlyContinue
$resolvedAgyBinDir = if ($agyCmdResolved -and $agyCmdResolved.Source) { Split-Path $agyCmdResolved.Source -Parent } else { "" }

$existingLocalJson = if (Test-Path -LiteralPath $ModelsLocalPath -PathType Leaf) { [System.IO.File]::ReadAllText($ModelsLocalPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) } else { "" }
$mergedLocalJson = Merge-SubAccountsModelsLocalJson -ExistingJson $existingLocalJson -SlotConfigs $slotConfigs -BridgeDir $BridgeDir -SharedDelegateDir $SharedDelegateDir -AgyBinDir $resolvedAgyBinDir

$primarySettingsPath = Join-Path $PrimaryHome ".gemini\antigravity-cli\settings.json"
$primarySettingsRaw = if (Test-Path -LiteralPath $primarySettingsPath -PathType Leaf) { [System.IO.File]::ReadAllText($primarySettingsPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) } else { "" }
$subSettingsJson = New-SubAccountNonSecretSettingsJson -PrimarySettingsJson $primarySettingsRaw

if ($DryRun) {
    Write-Host "[DryRun] 멀티 계정 부계정 풀 구성 미리보기 (실제 변경 없음)" -ForegroundColor Cyan
    Write-Host "  슬롯           : $(($slotConfigs | ForEach-Object { "$($_.id) ($($_.windows_user))" }) -join ', ')"
    Write-Host "  공용 스크립트  : $SharedDelegateDir"
    Write-Host "  브리지 경로    : $BridgeDir"
    Write-Host "  models.local   : $ModelsLocalPath"
    foreach ($sc in $slotConfigs) {
        $fakeSubHome = Join-Path (Split-Path $PrimaryHome -Parent) $sc.windows_user
        $jSpecs = @(Get-SubAccountJunctionSpecs -PrimaryHome $PrimaryHome -SubHome $fakeSubHome)
        Write-Host ("  [{0}] 정션 대상 {1}개, 스케줄 작업 samjil-agy-sub-{0} (LogonType=Password)" -f $sc.id, $jSpecs.Count)
    }
    return [pscustomobject]@{
        DryRun            = $true
        Slots             = $slotConfigs
        BridgeDir         = $BridgeDir
        SharedDelegateDir = $SharedDelegateDir
        ModelsLocalPath   = $ModelsLocalPath
        MergedModelsLocal = $mergedLocalJson
        SubSettingsJson   = $subSettingsJson
    }
}

$needsPassword = (-not $SkipAccountCreation) -or (-not $SkipTaskRegistration)
$plainPw = $PasswordPlainText
$bstrPtr = [IntPtr]::Zero
try {
    if ($needsPassword -and [string]::IsNullOrEmpty($plainPw)) {
        $secPw = Read-Host "부계정($($Slots -join ', ')) 공용 비밀번호를 입력하세요 (LogonType=Password 스케줄 작업용 · 빈 비밀번호 불가)" -AsSecureString
        $bstrPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPw)
        $plainPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstrPtr)
        if ([string]::IsNullOrEmpty($plainPw)) {
            throw "빈 비밀번호는 Task Scheduler(LogonType=Password) 에 사용할 수 없습니다."
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    # 1. 공용 실행 본체 복사 (C:\ProgramData\samjil\delegate-agy)
    $sharedScripts = Join-Path $SharedDelegateDir "scripts"
    $sharedConfig = Join-Path $SharedDelegateDir "config"
    New-Item -ItemType Directory -Force -Path $sharedScripts, $sharedConfig | Out-Null
    $srcScripts = Join-Path $SourceDelegateDir "scripts"
    $srcConfig = Join-Path $SourceDelegateDir "config"
    if (Test-Path -LiteralPath $srcScripts) { Copy-Item -Path (Join-Path $srcScripts "*") -Destination $sharedScripts -Recurse -Force }
    if (Test-Path -LiteralPath $srcConfig) {
        $modelsJsonSrc = Join-Path $srcConfig "models.json"
        if (Test-Path -LiteralPath $modelsJsonSrc) { Copy-Item -LiteralPath $modelsJsonSrc -Destination (Join-Path $sharedConfig "models.json") -Force }
    }
    Write-Host "[+] 공용 delegate-agy 스크립트 복사 완료: $SharedDelegateDir" -ForegroundColor Green

    # 2. models.local.json 병합 저장 (본계정 + 공용)
    New-Item -ItemType Directory -Force -Path (Split-Path $ModelsLocalPath -Parent) | Out-Null
    [System.IO.File]::WriteAllText($ModelsLocalPath, ($mergedLocalJson + "`r`n"), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sharedConfig "models.local.json"), ($mergedLocalJson + "`r`n"), $utf8NoBom)
    Write-Host "[+] models.local.json 병합 완료: $ModelsLocalPath" -ForegroundColor Green

    # 3. 브리지 디렉터리 및 ACL (Users 상속 제거해 슬롯 간 교차 열람 차단)
    $bridgeSlotsRoot = Join-Path $BridgeDir "slots"
    New-Item -ItemType Directory -Force -Path $BridgeDir, $bridgeSlotsRoot | Out-Null
    if (-not $SkipAcl) {
        Invoke-IcaclsGrant -TargetPath $SharedDelegateDir -Principal "$env:COMPUTERNAME\$PrimaryUser" -Rights "M" -InheritContainer
        foreach ($bdRoot in @($BridgeDir, $bridgeSlotsRoot)) {
            $outBd = & icacls.exe $bdRoot /inheritance:r /grant "SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "$env:COMPUTERNAME\${PrimaryUser}:(OI)(CI)M" /C /Q 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "브리지 ACL 초기화 실패 ($bdRoot): $outBd" }
        }
    }

    foreach ($sc in $slotConfigs) {
        $sid = [string]$sc.id
        $winUser = [string]$sc.windows_user
        $layout = Get-AgySubSlotLayout -BridgeRoot $BridgeDir -SlotId $sid
        [void](Initialize-AgySubSlotDirectories $layout)

        # 4. Windows 로컬 부계정 생성 / 비밀번호 갱신 (만료 없음)
        if (-not $SkipAccountCreation) {
            $secForCreate = if (-not [string]::IsNullOrEmpty($plainPw)) { ConvertTo-SecureString -String $plainPw -AsPlainText -Force } else { $null }
            $existingUser = $null
            try { $existingUser = Get-LocalUser -Name $winUser -ErrorAction SilentlyContinue } catch {}
            if (-not $existingUser) {
                New-LocalUser -Name $winUser -Password $secForCreate -FullName "Samjil Agy Sub ($sid)" -Description "Samjil multi-account delegate-agy worker ($sid)" -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
                Write-Host "[+] Windows 부계정 생성 완료: $winUser" -ForegroundColor Green
            } else {
                if ($null -ne $secForCreate) {
                    Set-LocalUser -Name $winUser -Password $secForCreate -PasswordNeverExpires $true -ErrorAction SilentlyContinue
                } else {
                    Set-LocalUser -Name $winUser -PasswordNeverExpires $true -ErrorAction SilentlyContinue
                }
                Write-Host "[i] 기존 Windows 부계정 확인 및 비밀번호/만료 설정 갱신: $winUser" -ForegroundColor Gray
            }
            Ensure-SubLocalGroupMembership -WindowsUser $winUser
        }

        # 5. 브리지 슬롯(Users 상속 제거 + 자기 슬롯만 M) + 공용 스크립트 + 스킬 정션(상위 Traverse 포함) + agy CLI ACL
        if (-not $SkipAcl) {
            Invoke-IcaclsGrant -TargetPath $BridgeDir -Principal "$env:COMPUTERNAME\$winUser" -Rights "(NP)(RX)"
            Invoke-IcaclsGrant -TargetPath $bridgeSlotsRoot -Principal "$env:COMPUTERNAME\$winUser" -Rights "(NP)(RX)"
            $slotAclArgs = @(Get-SubBridgeSlotAclArgs -SlotRoot $layout.SlotRoot -PrimaryPrincipal "$env:COMPUTERNAME\$PrimaryUser" -SubPrincipal "$env:COMPUTERNAME\$winUser")
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $slotAclOut = & icacls.exe @slotAclArgs 2>&1 | Out-String
                $slotAclCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $prevEap
            }
            if ($slotAclCode -ne 0) { throw "슬롯 ACL 격리 실패 ($($layout.SlotRoot)): $slotAclOut" }
            Invoke-IcaclsGrant -TargetPath $SharedDelegateDir -Principal "$env:COMPUTERNAME\$winUser" -Rights "(RX)" -InheritContainer
            $agentsSkills = Join-Path $PrimaryHome ".agents\skills"
            if (Test-Path -LiteralPath $agentsSkills) {
                Grant-SubAncestorTraverseAndRead -PrimaryHome $PrimaryHome -TargetPath $agentsSkills -Principal "$env:COMPUTERNAME\$winUser"
            }
            $geminiRules = Join-Path $PrimaryHome ".gemini\config\rules"
            if (Test-Path -LiteralPath $geminiRules) {
                Grant-SubAncestorTraverseAndRead -PrimaryHome $PrimaryHome -TargetPath $geminiRules -Principal "$env:COMPUTERNAME\$winUser"
            }
            if ($resolvedAgyBinDir -and $resolvedAgyBinDir.StartsWith($PrimaryHome, [System.StringComparison]::OrdinalIgnoreCase)) {
                $agyGrantRoot = if ((Split-Path -Leaf $resolvedAgyBinDir) -ieq "bin") { Split-Path $resolvedAgyBinDir -Parent } else { $resolvedAgyBinDir }
                Write-Host "[i] agy CLI 가 본계정 폴더 아래에 있습니다($agyGrantRoot). 부계정 실행을 위해 Traverse/읽기-실행 ACL 을 부여합니다." -ForegroundColor Yellow
                Grant-SubAncestorTraverseAndRead -PrimaryHome $PrimaryHome -TargetPath $agyGrantRoot -Principal "$env:COMPUTERNAME\$winUser"
            }
        }

        # 6. 프로필 초기화 + 비비밀 settings.json (mcp_config.json 미복사) + 스킬 정션
        $subHome = Resolve-SubUserProfileDir -WindowsUser $winUser
        if (Test-Path -LiteralPath $subHome -PathType Container) {
            $subAgyCfgDir = Join-Path $subHome ".gemini\antigravity-cli"
            New-Item -ItemType Directory -Force -Path $subAgyCfgDir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $subAgyCfgDir "settings.json"), ($subSettingsJson + "`r`n"), $utf8NoBom)

            if (-not $SkipJunctions) {
                $jSpecs = @(Get-SubAccountJunctionSpecs -PrimaryHome $PrimaryHome -SubHome $subHome)
                foreach ($js in $jSpecs) {
                    if (-not $js.SourceExists) { continue }
                    New-Item -ItemType Directory -Force -Path (Split-Path $js.LinkPath -Parent) | Out-Null
                    if (Test-Path -LiteralPath $js.LinkPath) {
                        $exItem = Get-Item -LiteralPath $js.LinkPath -Force
                        if ($exItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                        Write-Host "[!] 기존 폴더가 있어 정션을 건너뜁니다(직접 정리 후 재실행): $($js.LinkPath)" -ForegroundColor Yellow
                        continue
                    }
                    try {
                        [void](New-SubDirectoryJunction -LinkPath $js.LinkPath -TargetPath $js.TargetPath)
                        Write-Host "[+] 정션 연결 완료: $($js.LinkPath) -> $($js.TargetPath)" -ForegroundColor Green
                    } catch {
                        Write-Warning $_.Exception.Message
                    }
                }
            }
        } else {
            Write-Host "[!] 부계정 프로필 폴더를 아직 찾을 수 없어 settings.json/정션을 건너뜁니다(첫 로그인 또는 작업 실행 후 setup 재실행): $subHome" -ForegroundColor Yellow
        }

        # 7. 작업 스케줄러 등록 (SeBatchLogonRight + Schedule.Service COM LogonType=Password)
        if (-not $SkipTaskRegistration) {
            $taskName = "samjil-agy-sub-$sid"
            $taskUserId = "$env:COMPUTERNAME\$winUser"
            try {
                Grant-SubBatchLogonRight -AccountName $taskUserId
            } catch {
                Write-Warning ("배치 로그온 권한(SeBatchLogonRight) 자동 부여 경고 ($taskUserId): " + $_.Exception.Message)
            }
            $xmlText = New-SubWatcherTaskXml -UserId $taskUserId -SlotId $sid -BridgeDir $BridgeDir -SharedDelegateDir $SharedDelegateDir
            [void](Register-SubWatcherScheduledTask -TaskName $taskName -XmlText $xmlText -UserId $taskUserId -PlainPassword $plainPw)
            Write-Host "[+] 스케줄 작업 등록 및 시작 완료: $taskName ($taskUserId)" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "================ 다음 필수 절차 (부계정 최초 로그인) ================" -ForegroundColor Cyan
    foreach ($sc in $slotConfigs) {
        Write-Host ("  1) {0} 로그인: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{1}\scripts\switch-sub-agy.ps1`" -Slot {0}" -f $sc.id, $SharedDelegateDir) -ForegroundColor White
    }
    Write-Host "  2) 본계정 프로필 아래 저장소(@cwd)에 위임할 때는 해당 폴더에 부계정 수정 권한(icacls ... /grant <계정>:(OI)(CI)M) 및 git safe.directory 를 부여해 주세요." -ForegroundColor Gray
    Write-Host "=====================================================================" -ForegroundColor Cyan
} finally {
    $plainPw = $null
    if ($bstrPtr -ne [IntPtr]::Zero) {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
    }
}
