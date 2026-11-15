#
# !!! SPOILER WARNING !!!
# ------------------------------------------------------------------
# This file contains every lab password and what each account is for -
# effectively the answer key. You never need to open it to build the lab.
# If you intend to play the lab, close it now.
#
# Builders: do not change these unless you also update docs/ANSWER-KEY.md.
# Fixed passwords must satisfy domain complexity (7+ chars, 3 of 4 character
# classes, no 3+ char piece of the account's display name) except svc_tusk,
# which is covered by a fine-grained password policy.
#
@{
    Passwords = @{
        'f.valentine' = 'D1rtyD33dsD0neDirtCheap!'   # Domain Admin (not crackable, not needed)
        'g.zeppeli'   = 'Ny0h0h0!Valkyrie'           # MS01 autologon (LSA secret)
        'svc_tusk'    = 'valkyrie'                   # Kerberoastable, in rockyou.txt
        'd.brando'    = 'Sc4ryM0nst3rs!'             # Hard-coded in admin script on MS02
        'p.loco'      = 'Lucky#Horseshoe#1890!'      # AS-REP roastable red herring (uncrackable)
        'svc_sql'     = 'Philly#Ledger-1890-Rac3!'   # Kerberoastable red herring (uncrackable; must not contain 'svc'/'sql')
        'w.kepipo'    = 'Naples1890!'                # Disabled account, password in description
    }
}
