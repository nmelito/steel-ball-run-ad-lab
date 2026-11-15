#
# Steel Ball Run AD Lab - shared helper functions (dot-sourced by every setup script)
#
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Done {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session (Run as Administrator).'
    }
}

function Get-LabConfig {
    # LabConfig.psd1  = network settings (safe to open and edit)
    # LabSecrets.psd1 = account passwords (SPOILERS - never needs to be opened)
    $path        = Join-Path $PSScriptRoot 'LabConfig.psd1'
    $secretsPath = Join-Path $PSScriptRoot 'LabSecrets.psd1'
    foreach ($p in $path, $secretsPath) {
        if (-not (Test-Path $p)) { throw "$(Split-Path $p -Leaf) not found next to the script. Copy the whole scripts folder." }
    }
    $cfg = Import-PowerShellDataFile -Path $path
    $cfg.Passwords = (Import-PowerShellDataFile -Path $secretsPath).Passwords
    return $cfg
}

function Get-LabAdapter {
    param($Config)
    if ($Config.InterfaceAlias) {
        return Get-NetAdapter -Name $Config.InterfaceAlias
    }
    $up = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    if ($up.Count -ne 1) {
        $names = ($up | ForEach-Object Name) -join ', '
        throw "Found $($up.Count) active adapters ($names). Set InterfaceAlias in LabConfig.psd1 to the lab network adapter."
    }
    return $up[0]
}

function Set-LabStaticIP {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$IPAddress,
        [Parameter(Mandatory)] [string[]]$DnsServers
    )
    $adapter = Get-LabAdapter -Config $Config
    $idx = $adapter.ifIndex

    $current = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object IPAddress -eq $IPAddress
    if (-not $current) {
        Write-Step "Setting static IP $IPAddress/$($Config.PrefixLength) on '$($adapter.Name)'"
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled
        Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
        $params = @{ InterfaceIndex = $idx; IPAddress = $IPAddress; PrefixLength = $Config.PrefixLength }
        if ($Config.Gateway) { $params.DefaultGateway = $Config.Gateway }
        New-NetIPAddress @params | Out-Null
    } else {
        Write-Step "Static IP $IPAddress already configured"
    }
    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $DnsServers
}

function Remove-LabDefender {
    # Returns $true if a reboot is required.
    $feature = Get-WindowsFeature -Name Windows-Defender -ErrorAction SilentlyContinue
    if ($feature -and $feature.Installed) {
        Write-Step 'Removing Microsoft Defender (lab only - reboot required)'
        Uninstall-WindowsFeature -Name Windows-Defender | Out-Null
        return $true
    }
    Write-Step 'Microsoft Defender already removed'
    return $false
}

function Enable-LabRemoteAccess {
    Write-Step 'Enabling SMB, RDP and WinRM firewall rules'
    Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
}

function New-LabFlag {
    # Writes a random 32-char hex flag and locks it down to Administrators/SYSTEM
    # plus any extra principals given in -ReadAccess.
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$ReadAccess = @()
    )
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    $flag = [guid]::NewGuid().ToString('N')
    Set-Content -Path $Path -Value $flag -NoNewline -Encoding ASCII
    icacls $Path /inheritance:r /grant:r '*S-1-5-32-544:(F)' '*S-1-5-18:(F)' | Out-Null
    foreach ($p in $ReadAccess) { icacls $Path /grant "${p}:(R)" | Out-Null }
}

function Clear-LabHistory {
    # Don't leave setup commands lying around for players to find.
    try {
        $hist = (Get-PSReadLineOption).HistorySavePath
        if ($hist -and (Test-Path $hist)) { Remove-Item $hist -Force }
    } catch { }
}

function Assert-LocalAdminSession {
    # On member servers, any domain-account logon/elevation leaves credentials in LSASS
    # (and a cached DCC2 hash in the registry) that players can dump with mimikatz -
    # an unintended shortcut. Member configuration must run as the LOCAL Administrator.
    param([switch]$AllowDomainAccount)
    if ($env:USERDOMAIN -ieq $env:COMPUTERNAME) { return }
    $msg = "You are running as a DOMAIN account ($env:USERDOMAIN\$env:USERNAME). Its credentials will be " +
           "dumpable from this server and give players a shortcut to Domain Admin. Sign out, log on as " +
           ".\Administrator (local) and run the script again."
    if ($AllowDomainAccount) { Write-Warning $msg } else { throw $msg }
}

function Remove-LabSetupFiles {
    # Deletes the folder these scripts live in (normally C:\LabSetup). It holds every
    # lab password, so it must not survive into the playable lab.
    $dir = (Resolve-Path $PSScriptRoot).Path.TrimEnd('\')
    $looksLikeLabFolder = (Test-Path (Join-Path $dir 'LabConfig.psd1')) -and (Test-Path (Join-Path $dir 'LabCommon.ps1'))
    $isProtected = $dir.Length -le 3 -or $dir -ieq $env:USERPROFILE -or $dir -ieq $env:SystemRoot -or
                   $dir -ieq $env:ProgramFiles -or $dir -ieq (Join-Path $env:SystemDrive 'Users')
    if (-not $looksLikeLabFolder -or $isProtected) {
        Write-Warning "Not deleting '$dir' automatically (doesn't look like a dedicated lab folder). Delete the lab scripts manually as the local Administrator."
        return
    }

    Write-Step "Deleting setup files in $dir"
    Set-Location -Path "$env:SystemDrive\"
    [Environment]::CurrentDirectory = "$env:SystemDrive\"
    try {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
        Write-Done 'Setup files deleted'
    } catch {
        # Something holds a handle (e.g. an Explorer window). Delete at next boot as SYSTEM instead.
        Write-Warning "Could not delete now ($($_.Exception.Message)). Scheduling deletion at next boot."
        $action  = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c rd /s /q `"$dir`" & schtasks /delete /tn LabSetupCleanup /f"
        $trigger = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -TaskName 'LabSetupCleanup' -Action $action -Trigger $trigger `
            -User 'NT AUTHORITY\SYSTEM' -RunLevel Highest -Force | Out-Null
    }
}

function Complete-LabSetup {
    # Final step of every *-2-Configure.ps1: clear history, delete the setup files,
    # and reboot so no setup-time credentials remain in memory.
    param([string]$Message, [switch]$KeepSetupFiles, [switch]$NoReboot)
    Clear-LabHistory
    Write-Done $Message

    if ($KeepSetupFiles) {
        Write-Warning "-KeepSetupFiles: $PSScriptRoot still contains every lab password. Re-run without -KeepSetupFiles (or delete it as the local Administrator) before snapshotting or playing."
    } else {
        Remove-LabSetupFiles
    }

    if ($NoReboot) {
        Write-Warning '-NoReboot: reboot before snapshotting/playing so no setup credentials remain in memory.'
        return
    }
    Write-Step 'Rebooting in 15 seconds to clear setup credentials from memory (Ctrl+C to cancel)'
    Start-Sleep -Seconds 15
    Restart-Computer -Force
}
