# OSCP Lab — "Uploadry" target

A **deliberately vulnerable** Linux VM for practising the OSCP kill-chain:
web enumeration → file-upload RCE → credential reuse → `sudo` privilege
escalation to root. Built with [Lima](https://lima-vm.io) so it runs as a
real VM (kernel, systemd, SSH) natively on Apple Silicon.

> ⚠️ **Lab use only.** This machine is intentionally insecure. Keep it on the
> host loopback (default) and never expose it to an untrusted network.

## Vulnerability class

Modelled on the *unauthenticated/weakly-authenticated file-upload → webshell*
pattern (the same class as the `php2shell` PoC you referenced). No external
exploit code is run; the target simply ships the insecure upload handler so
you build the exploit yourself — which is the point for OSCP.

## Requirements

- Apple Silicon Mac (arm64)
- [Lima](https://lima-vm.io): `brew install lima`

## Quick start

```bash
./lab.sh up        # build & boot the VM, provision the target (first run pulls Ubuntu)
./lab.sh status    # show VM state
./lab.sh reset     # destroy & rebuild clean (fresh flags)
./lab.sh reprovision   # re-run provisioning only, keep the VM
./lab.sh shell     # drop into the VM (admin/debug only — not "cheating")
./lab.sh down      # stop the VM
```

Target web app: **http://127.0.0.1:8080**

## Objectives (no spoilers)

1. Enumerate the web app. Find the admin area and a way in.
2. Get code execution on the box (`www-data`) through the uploader.
3. Find credentials on disk and move laterally to a real user.
4. Escalate to **root**.
5. Collect both flags: `/home/michael/user.txt` and `/root/root.txt`.

A full walkthrough is in **[SOLUTION.md](SOLUTION.md)** — open it only when you
want to check yourself.

## Attacking it realistically

The web app is port-forwarded to `127.0.0.1:8080`, so you can run your tools
(Burp, `ffuf`, `curl`, a webshell) straight from the Mac. For a more exam-like
setup where the target has its own IP and you attack from a **Kali VM**:

- Give the VM a dedicated address by adding a shared network to
  `lima/uploadry.yaml`:
  ```yaml
  networks:
    - lima: shared     # needs: brew install socket_vmnet  (+ sudoers entry, see lima docs)
  ```
  then target the VM's `192.168.105.x` address instead of the port-forward.
- Or import the same target into **UTM** if you prefer a GUI VM you can snapshot.

## Files

```
oscp-lab/
├── lab.sh                 # up / down / reset / shell helper
├── lima/uploadry.yaml     # the VM definition
├── provision/provision.sh # builds the target inside the VM
├── webapp/                # the vulnerable SnapShare app
└── SOLUTION.md            # full walkthrough (spoilers)
```
