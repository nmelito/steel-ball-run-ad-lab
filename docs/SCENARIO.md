# Engagement Brief: Operation "Saint's Corpse"

## Background

**North America, 1890.** The **Steel Ball Run**, a horse race from San Diego to New York, is about to begin. Its prize of **$50,000,000** has drawn riders from every corner of the world.

Race organizer **Steven Steel** runs the event's operations from a small Windows domain, `steelballrun.local`. The race is also bankrolled by the **Office of the President**, and Steel has started to suspect the sponsor of quietly using the race's infrastructure for its own ends: tracking *something* along the route. He doesn't trust the IT staff the sponsor provided.

Steel has hired you for a **black-box penetration test**. You get no credentials, no documentation and no help, only a network cable plugged into the race office. He wants to know whether an outsider could walk from the public registration website all the way to the heart of the domain, where the President's people hold the keys.

> *"I don't care how you get to New York. I just need to know if somebody else can."*
> — Steven Steel

## Scope

| Target | Hostname | IP |
|--------|----------|----|
| Race Office web server | SANDIEGO | 192.168.56.11 |
| Telemetry server | MONUMENTVALLEY | 192.168.56.12 |
| Domain Controller | PHILADELPHIA | 192.168.56.10 |

- **In scope:** the three hosts above and everything that runs on them.
- **Out of scope:** the hypervisor, your host machine, any other network, and denial of service.
- **Starting position:** Kali Linux on `192.168.56.0/24`. **No credentials are provided.**

## Objectives

Capture the flags. Each one is a 32-character hex string.

| Host | Flag | Location | Points |
|------|------|----------|--------|
| SANDIEGO | `local.txt` | Low-privileged foothold. Find it. | 5 |
| SANDIEGO | `proof.txt` | `C:\Users\Administrator\Desktop\` | 5 |
| MONUMENTVALLEY | `local.txt` | The low-privileged user's Desktop | 5 |
| MONUMENTVALLEY | `proof.txt` | `C:\Users\Administrator\Desktop\` | 5 |
| PHILADELPHIA | `proof.txt` | `C:\Users\Administrator\Desktop\` | 20 |
| | | **Total** | **40** |

The scoring is OSCP-inspired: compromising the whole domain is worth as much as all the member servers combined. A flag only counts if you can show it in an interactive shell together with `whoami` and `ipconfig` (or `hostname`).

## Rules of Engagement (exam mode)

To practice for the real thing, hold yourself to OSCP-style restrictions:

1. **Time box:** 6 hours for this set.
2. **No automated exploitation frameworks** (Metasploit, sqlmap's `--os-shell`, etc.), except Metasploit on **one** machine if you choose. `msfvenom` and `multi/handler` are fine.
3. **No AI assistants or walkthroughs** while the clock runs. [HINTS.md](HINTS.md) costs you 2 points per hint opened, if you're scoring yourself.
4. **Do not modify the setup scripts or VMs from the hypervisor side.**
5. Document as you go. A real engagement ends in a report.

## Deliverable

Write a short pentest report covering:
- an executive summary written for Steven Steel (non-technical);
- each finding with severity, evidence (screenshots), reproduction steps and remediation;
- the full attack narrative from Kali to Domain Admin.

## Tips Before You Start

- Every machine is reachable from Kali, but that doesn't mean you can do anything with them yet.
- The race office loves to publish names. Names make usernames.
- BloodHound is your friend once you have *any* domain credentials.
- Not everything that looks crackable will crack. If rockyou doesn't finish it in a few minutes, move on.
- Kerberos hates clock skew. Sync your clock with the DC.

Good luck, rider. *Arrivederci.*
