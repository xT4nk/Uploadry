# TryHackMe community room — "Progress" (SnapShare)

Copy-paste material for the THM room editor. Theme: a host running an
**outdated, php2shell-vulnerable PHP** stack (CVE-2026-109618 /
CVE-2026-109619) that also serves a sloppily-built PHP app. The graded path
is a reliable web-exploitation chain; php2shell features as the scenario,
a version-fingerprinting objective, and theory. (An authentic php2shell
bonus flag is planned as phase 2.)

- **Difficulty:** Easy
- **Room type:** Challenge (VM)
- **Tags (≥4):** `php`, `web`, `file-upload`, `privilege-escalation`, `cve`, `linux`
- **Questions:** 10 (≤15 ✓)
- **Free-tier friendly:** VM tuned to boot in 0.5 GiB RAM (t2.nano)

---

## Task 1 — Deploy

**Description:**
> Welcome to **Progress**. The *SnapShare* photo host is running on an
> outdated PHP stack and a hastily-written uploader. Your goal: get a foothold
> through the web app, then escalate to root.
>
> Deploy the machine with the **Start Machine** button — give it ~2 minutes to
> boot. All activity stays on the TryHackMe network; use the AttackBox or your
> own VPN-connected box. Target: `MACHINE_IP`.

*No answer needed.*

---

## Task 2 — Recon & fingerprinting

**Description:**
> Start with service and version enumeration. Identify what's listening and,
> importantly, **which PHP version** the server runs — outdated PHP branches
> are exposed to the recently-disclosed **php2shell** flaws. Map the version to
> the public advisory.
>
> Hints: `nmap -sV -sC MACHINE_IP`, and inspect the HTTP response headers
> (`curl -I http://MACHINE_IP`). PHP leaks its version via `X-Powered-By`.

| # | Question | Answer | Hint |
|---|----------|--------|------|
| 1 | How many TCP ports are open? | `2` | SSH and HTTP |
| 2 | What major.minor PHP version does the web server report? | `8.1` | `X-Powered-By` header |
| 3 | php2shell is tracked under which two CVE IDs? (comma-separated, ascending) | `CVE-2026-109618,CVE-2026-109619` | Search "php2shell CVE" |

---

## Task 3 — Foothold

**Description:**
> SnapShare has an admin uploader. Enumerate the site, find your way into the
> panel, and turn the uploader into remote code execution.
>
> Hints: check `robots.txt`; look for leftover backup files in the admin
> folder; the uploader's extension filter is a **blacklist** — find an
> executable PHP extension it forgot.

| # | Question | Answer | Hint |
|---|----------|--------|------|
| 4 | Which path, disallowed in `robots.txt`, hosts the admin login? | `/admin` | `curl http://MACHINE_IP/robots.txt` |
| 5 | A leftover backup file in the admin folder leaks the admin password. What is it? | `Sup3rS3cr3t!2023` | `config.php.bak` is served as text |
| 6 | Which file extension bypasses the uploader's blacklist to get code execution? | `.phtml` | Apache still runs it as PHP |

---

## Task 4 — User

**Description:**
> With a webshell as `www-data`, hunt for credentials on disk. Developers love
> reusing passwords between the database and their own account.
>
> Hint: read the app's DB config under the web root.

| # | Question | Answer | Hint |
|---|----------|--------|------|
| 7 | Which system user's password is reused in a web config file? | `michael` | `config/db.php` |
| 8 | What is the contents of `user.txt`? | `THM{upl0ad_f1lt3r_bypass3d}` | `/home/michael/user.txt` |

---

## Task 5 — Privilege escalation

**Description:**
> Now that you're `michael`, look at what you're allowed to run as root.
> One misconfigured `sudo` entry is all it takes.
>
> Hint: `sudo -l`, then check GTFOBins for the allowed binary.

| # | Question | Answer | Hint |
|---|----------|--------|------|
| 9 | Which binary can `michael` run as root via `sudo`? | `find` | `sudo -l` |
| 10 | What is the contents of `root.txt`? | `THM{g7f0b1ns_f1nd_t0_r00t}` | `/root/root.txt` |

---

## Task 6 — Remediation (no answer)

**Description:**
> You chained info-disclosure, a weak upload filter, credential reuse and a
> `sudo` misconfiguration. How to fix each:
> - **Patch PHP** to a fixed release (8.1 is EOL — upgrade the branch) and set
>   `session.upload_progress.enabled = Off` to blunt php2shell.
> - Validate uploads by **content**, store them outside the web root or with
>   script execution disabled; never ship `.bak`/source backups.
> - Don't reuse the DB password for a login account; no plaintext creds on disk.
> - Scope `sudo` to specific, non-shell-spawning actions; audit against GTFOBins.

*No answer needed.*
