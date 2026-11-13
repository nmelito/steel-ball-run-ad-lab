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
    $path = Join-Path $PSScriptRoot 'LabConfig.psd1'
    if (-not (Test-Path $path)) { throw "LabConfig.psd1 not found next to the script ($path)." }
    Import-PowerShellDataFile -Path $path
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
    Write-Done "Flag written: $Path"
}

function Clear-LabHistory {
    # Don't leave setup commands lying around for players to find.
    try {
        $hist = (Get-PSReadLineOption).HistorySavePath
        if ($hist -and (Test-Path $hist)) { Remove-Item $hist -Force }
    } catch { }
}

function Write-CleanupReminder {
    Write-Host ''
    Write-Host '=====================================================================' -ForegroundColor Yellow
    Write-Host ' Setup scripts contain every lab password. When the lab is finished:' -ForegroundColor Yellow
    Write-Host '   Remove-Item C:\LabSetup -Recurse -Force' -ForegroundColor Yellow
    Write-Host ' then take a clean snapshot of this VM.' -ForegroundColor Yellow
    Write-Host '=====================================================================' -ForegroundColor Yellow
}
