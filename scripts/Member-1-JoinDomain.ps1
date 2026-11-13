<#
.SYNOPSIS
    MS01 / MS02 - stage 1: static IP, DNS -> DC, remove Defender, rename + join domain.

.EXAMPLE
    .\Member-1-JoinDomain.ps1 -Role MS01     # on the SANDIEGO VM
    .\Member-1-JoinDomain.ps1 -Role MS02     # on the MONUMENTVALLEY VM

.NOTES
    Run as the local Administrator. You will be prompted for domain admin credentials
    (SBR\Administrator). The machine reboots when done.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('MS01', 'MS02')] [string]$Role
)

. "$PSScriptRoot\LabCommon.ps1"
Assert-Admin
$cfg  = Get-LabConfig
$node = $cfg.Nodes[$Role]
$dc   = $cfg.Nodes.DC01

$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.PartOfDomain -and $cs.Domain -eq $cfg.DomainName -and $env:COMPUTERNAME -eq $node.Name) {
    Write-Done "$($node.Name) is already joined to $($cfg.DomainName). Run $Role-2-Configure.ps1."
    return
}

Set-LabStaticIP -Config $cfg -IPAddress $node.IP -DnsServers @($dc.IP)
$null = Remove-LabDefender

Write-Step "Checking that $($cfg.DomainName) resolves via $($dc.IP)"
Clear-DnsClientCache
Resolve-DnsName -Name $cfg.DomainName -Server $dc.IP -ErrorAction Stop | Out-Null

$cred = Get-Credential -Message "Domain admin credentials for $($cfg.DomainName)" -UserName "$($cfg.NetBIOSName)\Administrator"

Write-Step "Joining $($cfg.DomainName) as $($node.Name) - the machine will reboot"
$joinParams = @{ DomainName = $cfg.DomainName; Credential = $cred; Restart = $true; Force = $true }
if ($env:COMPUTERNAME -ne $node.Name) { $joinParams.NewName = $node.Name }
Add-Computer @joinParams
