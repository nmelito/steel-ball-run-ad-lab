# Lab Setup Guide

This guide builds the `steelballrun.local` lab from scratch. Budget about **60–90 minutes**, most of it spent on Windows installs and reboots.

---

## 1. Requirements

### Host
- About 16 GB RAM free (12 GB minimum), 4+ CPU cores, about 150 GB disk.
- A hypervisor: **VirtualBox**, **VMware Workstation/Player**, or **Hyper-V**.

### Images
| Image | Where to get it |
|-------|-----------------|
| Windows Server 2022 Evaluation (ISO) | [Microsoft Evaluation Center: Windows Server 2022](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022) (free, 180 days; choose **ISO downloads → 64-bit edition**) |
| Kali Linux (VM image or ISO) | [kali.org/get-kali](https://www.kali.org/get-kali/) (the pre-built **Virtual Machines** images are quickest) |

> One Windows Server ISO is enough. Install it three times, choosing **Windows Server 2022 Standard Evaluation (Desktop Experience)** each time.

### VM sizing

| VM | Hostname (set by script) | vCPU | RAM | Disk | Install option |
|----|--------------------------|------|-----|------|----------------|
| DC01 | `PHILADELPHIA` | 2 | 4 GB | 60 GB | Server 2022 Standard **(Desktop Experience)** |
| MS01 | `SANDIEGO` | 2 | 4 GB | 60 GB | Server 2022 Standard **(Desktop Experience)** |
| MS02 | `MONUMENTVALLEY` | 2 | 4 GB | 60 GB | Server 2022 Standard **(Desktop Experience)** |
| Kali | — | 2 | 4 GB | 80 GB | — |

> [!IMPORTANT]
> Install each Windows VM **from the ISO separately**. If you clone VMs, run `sysprep /generalize /oobe /shutdown` on the clone first, or duplicate machine SIDs will cause domain-join problems.
>
> Give each server's **local Administrator a different password**. If they share one, players can pass-the-hash straight from MS01 to MS02 and skip the intended path.

---

## 2. Network

All four VMs go on **one isolated network** with no internet access. The scripts default to `192.168.56.0/24`, which is VirtualBox's default host-only range.

| Hypervisor | How |
|------------|-----|
| VirtualBox | *File → Tools → Network Manager → Host-only Networks*. Use `vboxnet0` / "VirtualBox Host-Only Ethernet Adapter" (192.168.56.1/24). Attach every VM's **Adapter 1** to it. |
| VMware | *Virtual Network Editor*: create or edit a **Host-only** VMnet with subnet `192.168.56.0`, and disable its DHCP. Attach every VM to it. |
| Hyper-V | Create an **Internal** or **Private** virtual switch and attach every VM to it. |

**Kali:** give it a static address, e.g. `192.168.56.50/24`:

```bash
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.56.50/24
sudo nmcli con up "Wired connection 1"
```

**Different subnet?** Edit `scripts/LabConfig.psd1` (the `Nodes` IPs and `PrefixLength`) before running anything.

**More than one NIC on a Windows VM?** For example, a NAT adapter for updates plus the host-only one. Set `InterfaceAlias` in `LabConfig.psd1` to the host-only adapter's name (`Get-NetAdapter` shows it). Otherwise the scripts refuse to guess.

> [!TIP]
> Do Windows Updates **before** moving the VMs to the isolated network, if you want them. The setup scripts themselves need no internet access: IIS, ASP.NET and AD DS install from the Server image.

---

## 3. Get the scripts onto the VMs

On each Windows VM, copy the repo's `scripts\` folder to **`C:\LabSetup`**. You can use a shared folder, an ISO, or paste the files into a VM console. Then, in an **elevated** PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\LabSetup
Get-ChildItem -Recurse | Unblock-File
```

---

## 4. Build the Domain Controller (DC01 → `PHILADELPHIA`)

Log in as the local **Administrator**.

```powershell
.\DC01-1-Promote.ps1
```
- **Run 1:** sets the static IP, removes Defender, renames the host, then **reboots**.
- **Run 2** (log in again, same command): installs AD DS and prompts for a **DSRM password**. It creates the `steelballrun.local` forest and **reboots** again.

After the second reboot, log in as **`SBR\Administrator`** (same password as the old local admin) and run:

```powershell
cd C:\LabSetup
Set-ExecutionPolicy -Scope Process Bypass -Force
.\DC01-2-Configure.ps1
```

This creates the OUs, groups, users, SPNs, the ACL chain, the red herrings and `proof.txt`. It then **deletes `C:\LabSetup` and reboots** (see the note in §6 about `-KeepSetupFiles`).

---

## 5. Join the member servers

On **MS01**, logged in as the local Administrator:

```powershell
.\Member-1-JoinDomain.ps1 -Role MS01
```

On **MS02**:

```powershell
.\Member-1-JoinDomain.ps1 -Role MS02
```

Each script sets its static IP, points DNS at the DC and removes Defender. It then asks for domain admin credentials (`SBR\Administrator`), renames and joins the server, and **reboots**.

---

## 6. Configure the member servers

After the reboot, log in as the **local** Administrator, not the domain one. At the login screen choose *Other user* and type `.\Administrator`. The member scripts **refuse to run under a domain account**; see [Credential hygiene](#credential-hygiene) for why.

**MS01 (`SANDIEGO`):**

```powershell
cd C:\LabSetup; Set-ExecutionPolicy -Scope Process Bypass -Force
.\MS01-2-Configure.ps1
```
This deploys the IIS race site and configures autologon for `SBR\g.zeppeli`. After the reboot, Gyro logs on at the console automatically. That is expected, and it's part of the lab.

**MS02 (`MONUMENTVALLEY`):**

```powershell
cd C:\LabSetup; Set-ExecutionPolicy -Scope Process Bypass -Force
.\MS02-2-Configure.ps1
```
This creates the `CorpseTracker` service, grants WinRM access, creates `C:\RaceOps` and writes the flags.

**Automatic cleanup.** Each `*-2-Configure.ps1` script finishes by **deleting `C:\LabSetup`**, which holds every password, and then **rebooting**, which clears any setup-time credentials from memory. You don't need to delete anything by hand. If something has a file in the folder open, the deletion is scheduled to run as SYSTEM at the next boot instead.

| Switch | Use it when |
|--------|-------------|
| `-KeepSetupFiles` | You're still testing and want to re-run scripts. Run once more without it, or delete the folder as `.\Administrator`, before you play. |
| `-NoReboot` | You want to reboot yourself later. Do reboot before you snapshot. |
| `-AllowDomainAccount` | (MS01/MS02 only) Not recommended. It overrides the local-admin check. |

> All `*-2-Configure.ps1` scripts are **idempotent**: you can re-run them safely, if the files are still there. Each run regenerates the flags.

---

## 7. Verify from Kali

```bash
# Every host is up with the expected ports
nmap -Pn -p 53,80,88,135,389,445,3389,5985 192.168.56.10-12

# Website is live on MS01
curl -s http://192.168.56.11/ | grep -i "steel ball run"

# Domain is reachable
nxc smb 192.168.56.10-12
```

Expected:
- `.10` shows 53/88/389/445 (DC).
- `.11` shows 80/445/3389/5985.
- `.12` shows 445/3389/5985.
- `nxc` reports the domain `steelballrun.local` and the three hostnames.

**Kerberos clock sync.** Kerberos attacks fail with `KRB_AP_ERR_SKEW` if Kali's clock is more than 5 minutes off the DC:

```bash
sudo ntpdate -u 192.168.56.10      # or: sudo rdate -n 192.168.56.10
```

**Optional wordlist sanity check.** The intended crack relies on `rockyou.txt`:

```bash
grep -cx valkyrie /usr/share/wordlists/rockyou.txt   # should print 1 (or more)
```

---

## 8. Clean up & snapshot

1. Check that `C:\LabSetup` is gone on every Windows VM. The configure scripts delete it unless you used `-KeepSetupFiles`. If it's still there, delete it as **`.\Administrator`** on member servers. Never use a domain account for this; see below.
   ```powershell
   Remove-Item C:\LabSetup -Recurse -Force
   ```
2. **Don't log on to MS01/MS02 again** after their final reboot. MS01 shows Gyro's autologon desktop; leave it.
3. Shut the VMs down and take a snapshot named **`clean`** of each one.
4. Revert to `clean` whenever you want a fresh attempt. Reverting the DC and members **together** keeps machine-account passwords in sync.

### Credential hygiene

Players get SYSTEM on both member servers, and anything Windows remembers there is theirs. A domain admin logon or elevation on MS01/MS02 leaves two traces:

| What | Where | How long | What players get |
|------|-------|----------|------------------|
| NT hash (and Kerberos tickets) | LSASS memory | Until reboot | Instant Domain Admin through pass-the-hash, skipping MS02 and the ACL chain |
| Cached logon (DCC2 / mscache) | `HKLM\SECURITY\Cache` | **Permanent**, survives reboots | Offline cracking of the DA password, if it's weak |

Domain admin logons include all of these: logging on as `SBR\Administrator`, typing DA credentials into a **UAC prompt**, `runas`, RDP, or mapping a drive with DA credentials.

**Rules for building the lab:**
- On MS01/MS02, only ever log on as the **local** `.\Administrator`. The member configure scripts enforce this.
- The only place domain admin credentials touch a member is the `Get-Credential` prompt in `Member-1-JoinDomain.ps1`. That's a network authentication for the join, not a logon, and the server reboots right after.
- Give `SBR\Administrator` a **strong, unique password** that isn't in any wordlist, so a leaked cached hash can't be cracked.

**Already leaked a domain admin logon on a member?** Check from Kali once you have SYSTEM: `secretsdump` shows `Dumping cached domain logon information` with an `SBR/Administrator` entry. Then do either of these:
- **Easiest:** revert to a snapshot from before the logon, or rebuild that member.
- **In place:**
  1. Change the `SBR\Administrator` password on the DC to a strong new one, which makes the leaked hash and cached entry useless.
  2. Reboot the member to flush LSASS.
  3. Then take your `clean` snapshot.

> Evaluation editions run for 180 days. Running `slmgr /rearm` resets the timer a few times. Reverting snapshots also restores the clock-based activation state.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Found N active adapters` | Set `InterfaceAlias` in `LabConfig.psd1`. |
| Domain join: "domain could not be contacted" | Check that the member's DNS is `192.168.56.10` and that `Resolve-DnsName steelballrun.local` works. The DC firewall must allow DNS (it does by default). |
| `Cannot resolve SBR\svc_tusk` on MS02 | Run `DC01-2-Configure.ps1` on the DC first. |
| Website returns 500 / compilation error | Make sure `Web-Asp-Net45` installed: `Get-WindowsFeature Web-Asp-Net45`. |
| `KRB_AP_ERR_SKEW` from Kali | Sync the clock (see §7). |
| Kerberoast returns `$krb5tgs$18$` (AES) instead of `$23$` | Crack with `hashcat -m 19700`. It still cracks, just slower. Or re-run `DC01-2-Configure.ps1`, which forces RC4 on the legacy service accounts. |
| MS02 `local.txt` ended up in `C:\Users\Public\Desktop` | The script couldn't pre-create svc_tusk's profile. The lab still works, and the flag's ACL still restricts it to svc_tusk. |
