#
# Steel Ball Run AD Lab - shared configuration
# ------------------------------------------------------------------
# Every setup script reads this file. Edit IPs / adapter name here
# if your hypervisor network differs from the defaults.
#
# WARNING: this file contains every lab password (it IS the answer key).
# Delete C:\LabSetup from each VM after setup completes.
#
@{
    DomainName     = 'steelballrun.local'
    NetBIOSName    = 'SBR'

    # Network (isolated / host-only network shared with your Kali VM)
    PrefixLength   = 24
    Gateway        = ''          # leave empty for an isolated host-only network
    InterfaceAlias = ''          # leave empty to auto-pick the single 'Up' adapter

    Nodes = @{
        DC01 = @{ Name = 'PHILADELPHIA';   IP = '192.168.56.10' }
        MS01 = @{ Name = 'SANDIEGO';       IP = '192.168.56.11' }
        MS02 = @{ Name = 'MONUMENTVALLEY'; IP = '192.168.56.12' }
    }

    # ---- Vulnerable / path-relevant accounts (do not change unless you
    #      also update docs/ANSWER-KEY.md) ----
    Passwords = @{
        'f.valentine' = 'D1rtyD33dsD0neDirtCheap!'   # Domain Admin (not crackable, not needed)
        'g.zeppeli'   = 'Ny0h0h0!Valkyrie'           # MS01 autologon (LSA secret)
        'svc_tusk'    = 'valkyrie'                   # Kerberoastable, in rockyou.txt
        'd.brando'    = 'Sc4ryM0nst3rs!'             # Hard-coded in admin script on MS02
        'p.loco'      = 'Lucky#Horseshoe#1890!'      # AS-REP roastable red herring (uncrackable)
        'svc_sql'     = 'Philly#Ledger-1890-Rac3!'   # Kerberoastable red herring (uncrackable; must not contain 'svc'/'sql' - complexity rule)
        'w.kepipo'    = 'Naples1890!'                # Disabled account, password in description
    }
}
