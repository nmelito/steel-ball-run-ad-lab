# Hints

Open hints one at a time. Each one is a slightly bigger nudge than the last.

---

## SANDIEGO (MS01)

<details><summary>Hint 1: Foothold</summary>

The registration page wants a photo of your horse. How does it decide what counts as a "photo"?
</details>

<details><summary>Hint 2: Foothold</summary>

The extension check happens in your browser. Burp Suite sees the request after the browser does. What does the *server* look at?
</details>

<details><summary>Hint 3: Foothold</summary>

The server only checks the `Content-Type` header of the uploaded part, and it executes whatever lands in `/uploads/`. Kali ships ASPX web shells in `/usr/share/webshells/aspx/`.
</details>

<details><summary>Hint 4: Privilege escalation</summary>

Run `whoami /priv`. Web app pool accounts carry one very famous privilege.
</details>

<details><summary>Hint 5: Loot</summary>

Someone logs on to this server *automatically* every time it boots. Windows has to store that password somewhere it can read back.
</details>

---

## MONUMENTVALLEY (MS02)

<details><summary>Hint 6: Getting in</summary>

With domain creds in hand, ask the DC which accounts run services (have SPNs).
</details>

<details><summary>Hint 7: Getting in</summary>

One service account's password is in `rockyou.txt`. The other's isn't. BloodHound shows where the crackable one can log in.
</details>

<details><summary>Hint 8: Privilege escalation</summary>

The potato trick won't work here. Look at what's installed under `C:\Program Files\`, and read every README.
</details>

<details><summary>Hint 9: Privilege escalation</summary>

`sc.exe sdshow <service>`. Find your own SID with `whoami /user`. What rights does your SID have on the service? (`DC` = SERVICE_CHANGE_CONFIG.)
</details>

<details><summary>Hint 10: Loot</summary>

Administrators can see a folder at the root of `C:\` that you couldn't see before.
</details>

---

## PHILADELPHIA (DC01)

<details><summary>Hint 11: Path</summary>

Feed the new user into BloodHound and mark it as owned. Look at **Outbound Object Control**.
</details>

<details><summary>Hint 12: Path</summary>

GenericAll on a group means you can add yourself to it. What can *that group* do to the domain object?
</details>

<details><summary>Hint 13: Path</summary>

`WriteDacl` on the domain lets you grant yourself the two replication rights. Then ask the DC for every hash, nicely.
</details>
