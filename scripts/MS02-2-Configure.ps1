<#
.SYNOPSIS
    MS02 (MONUMENTVALLEY) - stage 2: WinRM access for svc_tusk, a SYSTEM service with
    a weak DACL (privesc), admin-only script containing d.brando's credentials, flags.

.DESCRIPTION
    Run as the LOCAL Administrator (MONUMENTVALLEY\Administrator) after the machine
    has joined the domain and DC01-2-Configure.ps1 has created the domain users.

    Vulnerabilities configured:
      * SBR\svc_tusk is in the local 'Remote Management Users' group (WinRM foothold).
      * Service 'CorpseTracker' runs as LocalSystem and grants SBR\svc_tusk
        SERVICE_CHANGE_CONFIG + START/STOP -> binPath hijack to SYSTEM.
      * C:\RaceOps\Sync-Riders.ps1 (Administrators only) hard-codes SBR\d.brando's password.
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
$node = $cfg.Nodes.MS02
$nb   = $cfg.NetBIOSName

if ($env:COMPUTERNAME -ne $node.Name -or -not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    throw "Run Member-1-JoinDomain.ps1 -Role MS02 first."
}

$tuskAccount = New-Object System.Security.Principal.NTAccount($nb, 'svc_tusk')
try {
    $tuskSid = $tuskAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
} catch {
    throw "Cannot resolve $nb\svc_tusk. Run DC01-2-Configure.ps1 on the DC first."
}

# ------------------------------------------------------------------ Remote access
Enable-LabRemoteAccess
Write-Step "Granting $nb\svc_tusk WinRM access (Remote Management Users)"
$rmu = Get-LocalGroupMember -Group 'Remote Management Users' -ErrorAction SilentlyContinue |
    Where-Object { $_.SID.Value -eq $tuskSid }
if (-not $rmu) { Add-LocalGroupMember -Group 'Remote Management Users' -Member "$nb\svc_tusk" }

# ------------------------------------------------------------------ Vulnerable service
$svcName = 'CorpseTracker'
$svcDir  = 'C:\Program Files\Steel Ball Run\Corpse Tracker'
$svcExe  = Join-Path $svcDir 'CorpseTracker.exe'

Write-Step "Building $svcName service binary"
New-Item -ItemType Directory -Path $svcDir -Force | Out-Null
if (-not (Test-Path $svcExe)) {
    Add-Type -ReferencedAssemblies System.ServiceProcess -OutputAssembly $svcExe -OutputType WindowsApplication -TypeDefinition @'
using System;
using System.IO;
using System.ServiceProcess;
using System.Timers;

public class CorpseTracker : ServiceBase
{
    private Timer timer;
    public CorpseTracker() { ServiceName = "CorpseTracker"; }

    protected override void OnStart(string[] args)
    {
        timer = new Timer(60000);
        timer.Elapsed += delegate {
            try {
                File.AppendAllText(@"C:\ProgramData\CorpseTracker.log",
                    DateTime.Now.ToString("s") + " Scanning for Saint's Corpse parts... none found.\r\n");
            } catch { }
        };
        timer.Start();
    }

    protected override void OnStop() { if (timer != null) timer.Stop(); }

    public static void Main() { ServiceBase.Run(new CorpseTracker()); }
}
'@
}
Set-Content -Path (Join-Path $svcDir 'README.txt') -Encoding ASCII -Value @"
Saint's Corpse Tracker v0.9 (beta)
Telemetry agent for the Steel Ball Run race office.
Service account for remote telemetry collection: $nb\svc_tusk
NOTE (h.pants): gave svc_tusk rights to restart/reconfigure the tracker service so the
telemetry team stops asking me. TODO: tighten this before the race starts.
"@

if (-not (Get-Service -Name $svcName -ErrorAction SilentlyContinue)) {
    Write-Step "Creating service $svcName (LocalSystem, automatic)"
    New-Service -Name $svcName -BinaryPathName "`"$svcExe`"" -DisplayName "Saint's Corpse Tracker" `
        -Description 'Steel Ball Run checkpoint telemetry agent.' -StartupType Automatic | Out-Null
} else {
    # Restore the original binPath in case a previous run of the lab hijacked it.
    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    $wmiSvc = Get-CimInstance Win32_Service -Filter "Name='$svcName'"
    $null = Invoke-CimMethod -InputObject $wmiSvc -MethodName Change -Arguments @{
        PathName = "`"$svcExe`""; StartName = 'LocalSystem'; StartMode = 'Automatic'
    }
}

Write-Step "Granting $nb\svc_tusk SERVICE_CHANGE_CONFIG / START / STOP on $svcName"
$sddl = ((sc.exe sdshow $svcName) -join '').Trim()
if ($sddl -notmatch [regex]::Escape($tuskSid)) {
    $ace = "(A;;CCDCLCSWRPWPDTLOCRRC;;;$tuskSid)"
    $i = $sddl.IndexOf('S:(')
    $newSddl = if ($i -ge 0) { $sddl.Insert($i, $ace) } else { $sddl + $ace }
    sc.exe sdset $svcName $newSddl | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sc.exe sdset failed ($LASTEXITCODE)" }
}
Start-Service -Name $svcName -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ Loot for the next hop
Write-Step 'Creating C:\RaceOps (Administrators only) with hard-coded d.brando credentials'
$opsDir = 'C:\RaceOps'
New-Item -ItemType Directory -Path $opsDir -Force | Out-Null
Set-Content -Path (Join-Path $opsDir 'Sync-Riders.ps1') -Encoding ASCII -Value @"
# Sync-Riders.ps1 - pulls the latest rider standings into the Race Officials share.
# Runs nightly from the race office. Owner: Diego asked for this so he can check standings.
# TODO: move these creds into a gMSA before the Philadelphia stage.

`$user = '$nb\d.brando'
`$pass = ConvertTo-SecureString '$($cfg.Passwords['d.brando'])' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential(`$user, `$pass)

`$standings = Invoke-Command -ComputerName $($cfg.Nodes.DC01.Name) -Credential `$cred -ScriptBlock {
    Get-ADGroupMember 'Riders' | Select-Object -ExpandProperty SamAccountName
}
`$standings | Out-File C:\RaceOps\standings.txt
"@
Set-Content -Path (Join-Path $opsDir 'standings.txt') -Encoding ASCII -Value "g.zeppeli`r`nj.joestar`r`nd.brando`r`np.loco`r`ns.man"
# Lock the folder to Administrators/SYSTEM, then make the files inherit from it.
# (Don't use /T here: it strips each file's inherited ACEs but the (OI)(CI) grants don't
#  apply to files, leaving them with an EMPTY DACL that denies even Administrators.)
icacls $opsDir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-18:(OI)(CI)(F)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed on $opsDir ($LASTEXITCODE)" }
icacls "$opsDir\*" /reset | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls /reset failed on $opsDir files ($LASTEXITCODE)" }

# ------------------------------------------------------------------ Flags
Write-Step "Creating svc_tusk profile (logs on once) for local.txt"
$tuskCred = New-Object System.Management.Automation.PSCredential(
    "$nb\svc_tusk", (ConvertTo-SecureString $cfg.Passwords['svc_tusk'] -AsPlainText -Force))
try {
    Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/c exit' `
        -Credential $tuskCred -LoadUserProfile -Wait -WorkingDirectory "$env:SystemRoot\System32"
} catch {
    Write-Warning "Could not pre-create the svc_tusk profile: $_"
}
$profilePath = (Get-CimInstance Win32_UserProfile | Where-Object SID -eq $tuskSid).LocalPath
if (-not $profilePath) {
    Write-Warning 'svc_tusk profile not found - falling back to C:\Users\Public\Desktop\local.txt'
    New-LabFlag -Path 'C:\Users\Public\Desktop\local.txt' -ReadAccess @("$nb\svc_tusk")
} else {
    New-LabFlag -Path (Join-Path $profilePath 'Desktop\local.txt') -ReadAccess @("$nb\svc_tusk")
}
New-LabFlag -Path 'C:\Users\Administrator\Desktop\proof.txt'

Complete-LabSetup -Message 'MS02 configuration complete.' -KeepSetupFiles:$KeepSetupFiles -NoReboot:$NoReboot
