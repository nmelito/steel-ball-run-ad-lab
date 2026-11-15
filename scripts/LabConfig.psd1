#
# Steel Ball Run AD Lab - network configuration
# ------------------------------------------------------------------
# Spoiler-free: this is the ONLY file you should need to open.
# Edit the IPs / adapter name here if your hypervisor network differs
# from the defaults. Account passwords live in LabSecrets.psd1, which
# contains lab solutions - you never need to open it.
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
}
