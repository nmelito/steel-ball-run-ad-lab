<#
.SYNOPSIS
    MS01 (SANDIEGO) - stage 2: race registration web app (vulnerable upload),
    autologon credentials stored as an LSA secret, and flags.

.DESCRIPTION
    Run as the LOCAL Administrator (SANDIEGO\Administrator) after the machine has
    joined the domain. Requires the web\ folder next to this script.

    Vulnerabilities configured:
      * register.aspx only validates the client-supplied Content-Type header,
        files land in /uploads/ where ASP.NET executes them.
      * The IIS app pool identity holds SeImpersonatePrivilege (default) -> potato.
      * Winlogon autologon for SBR\g.zeppeli with the password stored as the
        'DefaultPassword' LSA secret (recoverable as SYSTEM).
#>
[CmdletBinding()]
param(
    # Keep C:\LabSetup (for re-running while testing). Default: delete it - it contains every password.
    [switch]$KeepSetupFiles,
    # Skip the final reboot (which clears setup-time credentials from memory).
    [switch]$NoReboot,
    # Allow running as a domain account (NOT recommended: its creds become dumpable).
    [switch]$AllowDomainAccount
)

. "$PSScriptRoot\LabCommon.ps1"
Assert-Admin
Assert-LocalAdminSession -AllowDomainAccount:$AllowDomainAccount
$cfg  = Get-LabConfig
$node = $cfg.Nodes.MS01

if ($env:COMPUTERNAME -ne $node.Name -or -not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    throw "Run Member-1-JoinDomain.ps1 -Role MS01 first."
}

# ------------------------------------------------------------------ IIS + ASP.NET
Write-Step 'Installing IIS with ASP.NET 4.x'
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Console | Out-Null
Import-Module WebAdministration

$siteRoot = 'C:\inetpub\steelballrun'
$poolName = 'SBRRegistration'
$siteName = 'SteelBallRun'

Write-Step "Deploying race website to $siteRoot"
New-Item -ItemType Directory -Path $siteRoot -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'web\*') -Destination $siteRoot -Recurse -Force
New-Item -ItemType Directory -Path "$siteRoot\uploads" -Force | Out-Null

if (Get-Website -Name 'Default Web Site') {
    Write-Step 'Removing Default Web Site'
    Remove-Website -Name 'Default Web Site'
}
if (-not (Test-Path "IIS:\AppPools\$poolName")) {
    New-WebAppPool -Name $poolName | Out-Null
}
Set-ItemProperty "IIS:\AppPools\$poolName" -Name managedRuntimeVersion -Value 'v4.0'
Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType -Value ApplicationPoolIdentity

if (-not (Get-Website -Name $siteName)) {
    New-Website -Name $siteName -Port 80 -PhysicalPath $siteRoot -ApplicationPool $poolName -Force | Out-Null
}
Start-Website -Name $siteName -ErrorAction SilentlyContinue

# App pool identity can write uploads (that's the bug's blast radius).
icacls "$siteRoot\uploads" /grant "IIS AppPool\${poolName}:(OI)(CI)M" | Out-Null
Enable-NetFirewallRule -DisplayGroup 'World Wide Web Services (HTTP)' -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ Autologon / LSA secret
Write-Step 'Configuring system settings'
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class LabLsaSecret
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }

    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_OBJECT_ATTRIBUTES
    {
        public int Length; public IntPtr RootDirectory; public IntPtr ObjectName;
        public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService;
    }

    [DllImport("advapi32.dll")] private static extern uint LsaOpenPolicy(IntPtr SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] private static extern uint LsaStorePrivateData(IntPtr PolicyHandle, ref LSA_UNICODE_STRING KeyName, ref LSA_UNICODE_STRING PrivateData);
    [DllImport("advapi32.dll")] private static extern uint LsaClose(IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] private static extern int LsaNtStatusToWinError(uint Status);

    private static LSA_UNICODE_STRING Make(string s)
    {
        LSA_UNICODE_STRING u = new LSA_UNICODE_STRING();
        u.Buffer = Marshal.StringToHGlobalUni(s);
        u.Length = (ushort)(s.Length * 2);
        u.MaximumLength = (ushort)(s.Length * 2 + 2);
        return u;
    }

    public static void Store(string key, string value)
    {
        LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
        IntPtr policy;
        uint status = LsaOpenPolicy(IntPtr.Zero, ref oa, 0x00000020 /* POLICY_CREATE_SECRET */, out policy);
        if (status != 0) throw new Win32Exception(LsaNtStatusToWinError(status));
        LSA_UNICODE_STRING k = Make(key);
        LSA_UNICODE_STRING v = Make(value);
        try
        {
            status = LsaStorePrivateData(policy, ref k, ref v);
            if (status != 0) throw new Win32Exception(LsaNtStatusToWinError(status));
        }
        finally
        {
            Marshal.FreeHGlobal(k.Buffer);
            Marshal.FreeHGlobal(v.Buffer);
            LsaClose(policy);
        }
    }
}
'@

$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $winlogon -Name AutoAdminLogon    -Value '1'
Set-ItemProperty -Path $winlogon -Name DefaultUserName   -Value 'g.zeppeli'
Set-ItemProperty -Path $winlogon -Name DefaultDomainName -Value $cfg.NetBIOSName
Remove-ItemProperty -Path $winlogon -Name DefaultPassword -ErrorAction SilentlyContinue  # not in plaintext registry...
[LabLsaSecret]::Store('DefaultPassword', $cfg.Passwords['g.zeppeli'])                   # ...only in the LSA secret

# ------------------------------------------------------------------ Remote access + flags
Enable-LabRemoteAccess

Write-Step 'Writing flags'
New-LabFlag -Path 'C:\inetpub\local.txt' -ReadAccess @("IIS AppPool\$poolName")
New-LabFlag -Path 'C:\Users\Administrator\Desktop\proof.txt'

Complete-LabSetup -Message 'MS01 configuration complete.' -KeepSetupFiles:$KeepSetupFiles -NoReboot:$NoReboot
