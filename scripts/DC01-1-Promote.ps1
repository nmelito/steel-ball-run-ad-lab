<#
.SYNOPSIS
    DC01 (PHILADELPHIA) - stage 1: network, rename, remove Defender, promote to DC.

.DESCRIPTION
    Run TWICE from an elevated PowerShell prompt as the local Administrator:
      Run 1: sets static IP, renames the host, removes Defender, reboots.
      Run 2: installs AD DS and creates the steelballrun.local forest (auto reboot).
    After the second reboot, log in as SBR\Administrator and run DC01-2-Configure.ps1.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot\LabCommon.ps1"
Assert-Admin
$cfg  = Get-LabConfig
$node = $cfg.Nodes.DC01

# DC points DNS at itself (127.0.0.1 after promotion handles the rest)
Set-LabStaticIP -Config $cfg -IPAddress $node.IP -DnsServers @('127.0.0.1')

$reboot = Remove-LabDefender

if ($env:COMPUTERNAME -ne $node.Name) {
    Write-Step "Renaming computer $env:COMPUTERNAME -> $($node.Name)"
    Rename-Computer -NewName $node.Name -Force
    $reboot = $true
}

if ($reboot) {
    Write-Done 'Stage 1a complete. Rebooting - run this script again after login.'
    Start-Sleep -Seconds 5
    Restart-Computer -Force
    return
}

if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
    Write-Done 'This server is already a domain controller. Run DC01-2-Configure.ps1.'
    return
}

Write-Step 'Installing AD DS role'
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

$dsrm = Read-Host -AsSecureString 'Enter a Directory Services Restore Mode (DSRM) password'

Write-Step "Creating forest $($cfg.DomainName) ($($cfg.NetBIOSName)) - the server will reboot"
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName $cfg.DomainName `
    -DomainNetbiosName $cfg.NetBIOSName `
    -DomainMode WinThreshold `
    -ForestMode WinThreshold `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -NoRebootOnCompletion:$false `
    -Force
