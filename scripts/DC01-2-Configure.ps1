<#
.SYNOPSIS
    DC01 (PHILADELPHIA) - stage 2: populate steelballrun.local with users, groups,
    vulnerable configurations, red herrings and the DC proof flag.

.DESCRIPTION
    Run once as SBR\Administrator after DC01-1-Promote.ps1 has finished.
    Safe to re-run (idempotent): existing objects are updated, not duplicated.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot\LabCommon.ps1"
Assert-Admin
$cfg = Get-LabConfig
$pw  = $cfg.Passwords

Import-Module ActiveDirectory
$domain   = Get-ADDomain
$domainDN = $domain.DistinguishedName
$upnSuffix = $cfg.DomainName

# ------------------------------------------------------------------ OUs
Write-Step 'Creating OUs'
$ouRoot = "OU=Steel Ball Run,$domainDN"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouRoot'")) {
    New-ADOrganizationalUnit -Name 'Steel Ball Run' -Path $domainDN -ProtectedFromAccidentalDeletion $false
}
foreach ($ou in 'Race Staff', 'Riders', 'Service Accounts', 'Groups') {
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq 'OU=$ou,$ouRoot'")) {
        New-ADOrganizationalUnit -Name $ou -Path $ouRoot -ProtectedFromAccidentalDeletion $false
    }
}
$ouStaff  = "OU=Race Staff,$ouRoot"
$ouRiders = "OU=Riders,$ouRoot"
$ouSvc    = "OU=Service Accounts,$ouRoot"
$ouGroups = "OU=Groups,$ouRoot"

# ------------------------------------------------------------------ Groups
Write-Step 'Creating groups'
$groups = @(
    @{ Name = 'Race Officials';           Desc = 'Steel Ball Run race officials and judges' },
    @{ Name = 'Riders';                   Desc = 'Registered Steel Ball Run competitors' },
    @{ Name = 'Legacy Service Accounts';  Desc = 'Old service accounts pending password rotation (see PSO)' }
)
foreach ($g in $groups) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($g.Name)'")) {
        New-ADGroup -Name $g.Name -GroupScope Global -GroupCategory Security -Path $ouGroups -Description $g.Desc
    }
}

# Fine-grained password policy so the legacy service account can hold a weak password
# (the Default Domain Policy is left untouched).
$psoName = 'SBR Legacy Service Accounts'
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$psoName'")) {
    Write-Step 'Creating fine-grained password policy for legacy service accounts'
    New-ADFineGrainedPasswordPolicy -Name $psoName -Precedence 10 `
        -ComplexityEnabled $false -MinPasswordLength 4 -PasswordHistoryCount 0 `
        -ReversibleEncryptionEnabled $false -LockoutThreshold 0
    Add-ADFineGrainedPasswordPolicySubject -Identity $psoName -Subjects 'Legacy Service Accounts'
}

# ------------------------------------------------------------------ Users
function New-RandomPassword {
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%^*-_'
    $body = -join (1..20 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return "Aa1!$body"
}

function Set-LabUser {
    param(
        [string]$Sam, [string]$Given, [string]$Surname, [string]$Path,
        [string]$Password, [string]$Description = '', [string]$Title = '',
        [string[]]$Groups = @(), [switch]$Disabled
    )
    $generated = -not $Password
    if ($generated) { $Password = New-RandomPassword }
    $display = ("$Given $Surname").Trim()
    $user = Get-ADUser -Filter "SamAccountName -eq '$Sam'"
    if (-not $user) {
        # Create disabled with no password first, so group-based PSOs apply before the password is set.
        $newParams = @{
            Name = $display; DisplayName = $display; GivenName = $Given
            SamAccountName = $Sam; UserPrincipalName = "$Sam@$upnSuffix"; Path = $Path
            Enabled = $false; PasswordNeverExpires = $true
        }
        if ($Surname) { $newParams.Surname = $Surname }
        New-ADUser @newParams
    }
    $setParams = @{ Identity = $Sam; PasswordNeverExpires = $true }
    if ($Description) { $setParams.Description = $Description }
    if ($Title)       { $setParams.Title = $Title }
    Set-ADUser @setParams
    foreach ($g in $Groups) { Add-ADGroupMember -Identity $g -Members $Sam -ErrorAction SilentlyContinue }
    # Complexity rejects passwords containing any 3+ char token of the display name
    # (split on spaces, '_', '.', '-', etc.). Random passwords can rarely hit that, so retry.
    for ($attempt = 1; ; $attempt++) {
        try {
            Set-ADAccountPassword -Identity $Sam -Reset -NewPassword (ConvertTo-SecureString $Password -AsPlainText -Force)
            break
        } catch [Microsoft.ActiveDirectory.Management.ADPasswordComplexityException] {
            if (-not $generated -or $attempt -ge 5) {
                throw "Password for '$Sam' rejected by domain policy. Fixed passwords in LabConfig.psd1 must be 7+ chars, " +
                      "use 3 of 4 character classes, and must not contain the username or any 3+ char part of the display name ('$display'). $_"
            }
            $Password = New-RandomPassword
        }
    }
    if ($Disabled) { Disable-ADAccount -Identity $Sam } else { Enable-ADAccount -Identity $Sam }
}

Write-Step 'Creating race staff'
Set-LabUser -Sam 's.steel'     -Given 'Steven' -Surname 'Steel'     -Path $ouStaff -Title 'Race Organizer'           -Groups 'Race Officials'
Set-LabUser -Sam 'l.steel'     -Given 'Lucy'   -Surname 'Steel'     -Path $ouStaff -Title 'Organizer Office'
Set-LabUser -Sam 'h.pants'     -Given 'Hot'    -Surname 'Pants'     -Path $ouStaff -Title 'Race Judge'               -Groups 'Race Officials'
Set-LabUser -Sam 'f.valentine' -Given 'Funny'  -Surname 'Valentine' -Path $ouStaff -Title 'President (Sponsor)'      -Password $pw['f.valentine'] -Groups 'Domain Admins'
Set-LabUser -Sam 'w.kepipo'    -Given 'Wekapipo' -Surname ''        -Path $ouStaff -Title 'Security (on leave)'      -Password $pw['w.kepipo'] `
            -Description "Account on hold while on leave. Temp password: $($pw['w.kepipo'])" -Disabled

Write-Step 'Creating riders'
Set-LabUser -Sam 'j.joestar'   -Given 'Johnny'   -Surname 'Joestar'  -Path $ouRiders -Title 'Rider #3'     -Groups 'Riders'
Set-LabUser -Sam 'g.zeppeli'   -Given 'Gyro'     -Surname 'Zeppeli'  -Path $ouRiders -Title 'Rider #?'     -Password $pw['g.zeppeli'] -Groups 'Riders'
Set-LabUser -Sam 'd.brando'    -Given 'Diego'    -Surname 'Brando'   -Path $ouRiders -Title 'Rider #?'     -Password $pw['d.brando']  -Groups 'Riders'
Set-LabUser -Sam 'p.loco'      -Given 'Pocoloco' -Surname ''         -Path $ouRiders -Title 'Rider #?'     -Password $pw['p.loco']    -Groups 'Riders'
Set-LabUser -Sam 'm.tim'       -Given 'Mountain' -Surname 'Tim'      -Path $ouRiders -Title 'Rider (Cowboy)' -Groups 'Riders'
Set-LabUser -Sam 's.man'       -Given 'Sandman'  -Surname ''         -Path $ouRiders -Title 'Rider'          -Groups 'Riders'
Set-LabUser -Sam 'r.roadagain' -Given 'Ringo'    -Surname 'Roadagain' -Path $ouRiders -Title 'Rider (Gunslinger)' -Groups 'Riders'

Write-Step 'Creating service accounts'
Set-LabUser -Sam 'svc_tusk' -Given 'svc_tusk' -Surname '' -Path $ouSvc -Password $pw['svc_tusk'] `
            -Description 'Corpse Tracker telemetry service (MONUMENTVALLEY)' -Groups 'Legacy Service Accounts'
Set-LabUser -Sam 'svc_sql'  -Given 'svc_sql'  -Surname '' -Path $ouSvc -Password $pw['svc_sql'] `
            -Description 'Race results SQL service (decommissioned)'

# ------------------------------------------------------------------ Roastable accounts
Write-Step 'Configuring SPNs (Kerberoasting)'
Set-ADUser -Identity 'svc_tusk' -Replace @{ servicePrincipalName = @("HTTP/tracker.$($cfg.DomainName):8080") }
Set-ADUser -Identity 'svc_sql'  -Replace @{ servicePrincipalName = @("MSSQLSvc/philadelphia.$($cfg.DomainName):1433") }
# "Legacy" accounts: explicitly RC4-only so fully patched DCs still issue $krb5tgs$23$ tickets.
foreach ($svc in 'svc_tusk', 'svc_sql') {
    Set-ADUser -Identity $svc -Replace @{ 'msDS-SupportedEncryptionTypes' = 4 }
}

Write-Step 'Configuring AS-REP roastable red herring (p.loco)'
Set-ADAccountControl -Identity 'p.loco' -DoesNotRequirePreAuth $true

# ------------------------------------------------------------------ ACL attack chain
#   d.brando --GenericAll--> [Race Officials] --WriteDacl--> domain root (=> DCSync)
Write-Step 'Configuring ACL chain: d.brando -> Race Officials -> domain'
function Add-LabAce {
    param([string]$TargetDN, [System.Security.Principal.SecurityIdentifier]$Sid,
          [System.DirectoryServices.ActiveDirectoryRights]$Rights)
    $acl = Get-Acl -Path "AD:$TargetDN"
    $rules = $acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])
    $exists = $rules | Where-Object {
        $_.IdentityReference -eq $Sid -and
        ($_.ActiveDirectoryRights -band $Rights) -eq $Rights -and $_.AccessControlType -eq 'Allow'
    }
    if (-not $exists) {
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($Sid, $Rights, 'Allow')
        $acl.AddAccessRule($ace)
        Set-Acl -Path "AD:$TargetDN" -AclObject $acl
    }
}
$diegoSid    = (Get-ADUser 'd.brando').SID
$officials   = Get-ADGroup 'Race Officials'
Add-LabAce -TargetDN $officials.DistinguishedName -Sid $diegoSid      -Rights GenericAll
Add-LabAce -TargetDN $domainDN                    -Sid $officials.SID -Rights WriteDacl

# ------------------------------------------------------------------ Flag
Write-Step 'Writing DC proof flag'
New-LabFlag -Path 'C:\Users\Administrator\Desktop\proof.txt'

Clear-LabHistory
Write-Done 'DC01 configuration complete. Join MS01 and MS02 to the domain next.'
Write-CleanupReminder
