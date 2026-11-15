# Lab Setup Guide

This guide builds the `steelballrun.local` lab from scratch. Budget about **60–90 minutes**, most of it spent on Windows installs and reboots.

> [!NOTE]
> **This guide is spoiler-free.** You can build the lab and still play it blind. The setup scripts print only generic progress messages, and nothing here describes the vulnerabilities.

---

## 0. Honor system: what not to open

This lab is meant for self-training, so it runs on the honor system. If you plan to play it, **don't open these**:

| File / location | Why |
|-----------------|-----|
| `scripts/LabSecrets.psd1` | Every account password and what each account is for |
| `scripts/*.ps1` and `scripts/web/` source | The scripts configure the vulnerabilities, so reading them reveals the path |
| `C:\LabSetup` on any VM (only present if you used `-KeepSetupFiles`) | A copy of all of the above |
| [`docs/ANSWER-KEY.md`](ANSWER-KEY.md) | The full walkthrough |
| [`docs/HINTS.md`](HINTS.md) | Fine to open, one hint at a time, when you're stuck |

The **only** file you might need to edit is `scripts/LabConfig.psd1`, and only for network settings. It's spoiler-free.

If your enumeration in the lab ever turns up `C:\LabSetup` or a `LabSecrets.psd1`, it's leftover setup material and not part of the challenge. Ignore it. Cheating only cheats you out of the practice.

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
> Give each server's **local Administrator a different password**. If they share one, a single dumped hash unlocks every server and the lab plays very differently from what was designed.

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

**Different subnet?** Edit `scripts/LabConfig.psd1` (the `Nodes` IPs and `PrefixLength`) before running anything. This file is spoiler-free.

**More than one NIC on a Windows VM?** For example, a NAT adapter for updates plus the host-only one. Set `InterfaceAlias` in `LabConfig.psd1` to the host-only adapter's name (`Get-NetAdapter` shows it). Otherwise the scripts refuse to guess.

> [!TIP]
> Do Windows Updates **before** moving the VMs to the isolated network, if you want them. The setup scripts themselves need no internet access: every Windows feature they install comes from the Server image.

---

## 3. Get the scripts onto the VMs

On each Windows VM, copy the **whole** `scripts\` folder to **`C:\LabSetup`**. You can use a hypervisor shared folder, an ISO, or a USB/clipboard copy. Don't open the files on the way. Then, in an **elevated** PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\LabSetup
Get-ChildItem -Recurse | Unblock-File
```

> [!TIP]
> Running from a **hypervisor shared folder** or an attached ISO works too. Disconnect it before you snapshot, so nothing on the VM still holds the scripts.

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

This populates the domain and writes the DC's flag. It then **deletes `C:\LabSetup` and reboots**; see [Automatic cleanup](#automatic-cleanup).

> [!IMPORTANT]
> Give `SBR\Administrator` a **strong, unique password** that isn't in any wordlist. See [Credential hygiene](#credential-hygiene).

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

**MS02 (`MONUMENTVALLEY`):**

```powershell
cd C:\LabSetup; Set-ExecutionPolicy -Scope Process Bypass -Force
.\MS02-2-Configure.ps1
```

Each script sets up that server's part of the lab and writes its flags.

> **Expected behavior:** after its final reboot, **MS01's console signs in to a user session on its own**. That's part of the lab. Leave it alone; don't sign it out or log on over it.

### Automatic cleanup

Each `*-2-Configure.ps1` script finishes by:
1. **deleting `C:\LabSetup`**, because it holds the lab's solution. If something has a file in it open, the deletion is scheduled to run as SYSTEM at the next boot instead.
2. **rebooting**, which clears any setup-time credentials from memory.

You don't need to delete anything by hand. Optional switches:

| Switch | Use it when |
|--------|-------------|
| `-KeepSetupFiles` | You're still testing and want to re-run scripts. Run once more without it, or delete the folder as `.\Administrator`, before you play. Until then, the [honor system](#0-honor-system-what-not-to-open) applies. |
| `-NoReboot` | You want to reboot yourself later. Do reboot before you snapshot. |
| `-AllowDomainAccount` | (MS01/MS02 only) Not recommended. It overrides the local-admin check. |

> All `*-2-Configure.ps1` scripts are **idempotent**: you can re-run them safely, if the files are still there. Each run regenerates the flags.

---

## 7. Verify from Kali

```bash
# Every host is up
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

**Clock sync.** Kerberos fails with `KRB_AP_ERR_SKEW` if Kali's clock is more than 5 minutes off the DC:

```bash
sudo ntpdate -u 192.168.56.10      # or: sudo rdate -n 192.168.56.10
```

**Wordlists.** Make sure Kali's standard wordlists are unpacked:

```bash
sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null; ls -lh /usr/share/wordlists/rockyou.txt
```

---

## 8. Clean up & snapshot

1. Check that `C:\LabSetup` is gone on every Windows VM. The configure scripts delete it unless you used `-KeepSetupFiles`. If it's still there, delete it as **`.\Administrator`** on member servers. **Never** elevate with a domain account to do this; see below.
   ```powershell
   Remove-Item C:\LabSetup -Recurse -Force
   ```
2. Disconnect any shared folder or ISO you used to copy the scripts.
3. **Don't log on to MS01/MS02 again** after their final reboot. MS01's console session is expected; leave it.
4. Shut the VMs down and take a snapshot named **`clean`** of each one.
5. Revert to `clean` whenever you want a fresh attempt. Reverting the DC and members **together** keeps machine-account passwords in sync.

### Credential hygiene

Assume players will eventually have full control of the member servers, and that anything Windows remembers there is theirs. A **domain admin** logon or elevation on MS01/MS02 leaves two traces behind:

| What | Where | How long | Effect on the lab |
|------|-------|----------|-------------------|
| NT hash (and Kerberos tickets) | LSASS memory | Until reboot | Instant Domain Admin through pass-the-hash, skipping most of the lab |
| Cached logon (DCC2 / mscache) | `HKLM\SECURITY\Cache` | **Permanent**, survives reboots | Offline cracking of the DA password, if it's weak |

Domain admin logons include all of these: logging on as `SBR\Administrator`, typing DA credentials into a **UAC prompt**, `runas`, RDP, or mapping a drive with DA credentials.

**Rules for building the lab:**
- On MS01/MS02, only ever log on as the **local** `.\Administrator`. The member configure scripts enforce this.
- The only place domain admin credentials touch a member is the `Get-Credential` prompt in `Member-1-JoinDomain.ps1`. That's a network authentication for the join, not a logon, and the server reboots right after.
- Give `SBR\Administrator` a **strong, unique password** that isn't in any wordlist, so a leaked cached hash can't be cracked.

**Already used a domain admin account on a member?** Do either of these:
- **Easiest:** revert that member to a snapshot from before the logon, or rebuild it.
- **In place:**
  1. Change the `SBR\Administrator` password on the DC to a strong new one, which makes any leaked hash or cached entry useless.
  2. Reboot the member to flush memory.
  3. Then take your `clean` snapshot.

> Evaluation editions run for 180 days. Running `slmgr /rearm` resets the timer a few times. Reverting snapshots also restores the clock-based activation state.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Found N active adapters` | Set `InterfaceAlias` in `LabConfig.psd1`. |
| `LabConfig.psd1` / `LabSecrets.psd1 not found` | Copy the **whole** `scripts\` folder, not individual files. |
| Domain join: "domain could not be contacted" | Check that the member's DNS is `192.168.56.10` and that `Resolve-DnsName steelballrun.local` works. The DC firewall must allow DNS (it does by default). |
| `A required domain account was not found` on MS02 | Run `DC01-2-Configure.ps1` on the DC first. |
| `You are running as a DOMAIN account` | Sign out, log on as `.\Administrator` (local) and run the script again. |
| `Password for '...' rejected by domain policy` | Only happens if `LabSecrets.psd1` was edited. Restore it from the repo. |
| Website returns 500 / compilation error | Make sure the ASP.NET feature installed: `Get-WindowsFeature Web-Asp-Net45`. |
| `KRB_AP_ERR_SKEW` from Kali | Sync the clock (see §7). |
| Warning: `local.txt was written to the fallback location` | The lab still works. That flag is in `C:\Users\Public\Desktop\` instead of the user's own Desktop, and its permissions are unchanged. |
| Something in the attack path doesn't behave as expected | See *Troubleshooting the intended path* at the end of [ANSWER-KEY.md](ANSWER-KEY.md) (spoilers). |
