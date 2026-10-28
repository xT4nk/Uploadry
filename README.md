# OSCP Lab — "Uploadry" target

A **deliberately vulnerable** Linux VM for practising the OSCP kill-chain:
web enumeration → file-upload RCE → credential reuse → `sudo` privilege
escalation to root.

The same target can be obtained in three ways: import the ready-made **x86 OVA**
(any hypervisor, no Mac needed), build that OVA yourself, or run it natively on
Apple Silicon with [Lima](https://lima-vm.io). Everything is provisioned from
the scripts in this repo, so the machine is fully reproducible.

> ⚠️ **Lab use only.** This machine is intentionally insecure. Keep it on a
> host-only / NAT network and never expose it to an untrusted network.

## Screenshots

| Public site | Admin login |
|:---:|:---:|
| ![SnapShare homepage](docs/webapp-home.png) | ![Admin login](docs/webapp-admin.png) |

The intentionally sloppy "SnapShare" photo app — the uploader behind the admin
login is the way in.

## Vulnerability class

Modelled on the *weakly-authenticated file-upload → webshell* pattern (same
class as the `php2shell` PoC referenced in the room). No external exploit code
is run; the target simply ships the insecure upload handler so you build the
exploit yourself — which is the point for OSCP.

---

## Getting the VM

### Option A — Import the prebuilt OVA (simplest, cross-platform)

Grab `uploadry.ova` from the **Releases** page (or build it, Option C) and
import it into **VirtualBox** or **VMware** on Windows, Linux or macOS
(Intel *or* Apple Silicon). It's an x86-64 Ubuntu 22.04 VM, ~800 MB.

- Import → set the network to **Host-Only** or **NAT**.
- Boot it, find its IP (`ip a` from the console, or your hypervisor's DHCP
  lease list), and attack it from your Kali box.

No Mac and no build toolchain required — this is also exactly what gets
uploaded to TryHackMe.

### Option B — Run locally on Apple Silicon with Lima (fastest to spin up)

Native arm64 VM, port-forwarded to your Mac. Good for quick iteration.

```bash
brew install lima
./lab.sh up        # build & boot the VM, provision the target (first run pulls Ubuntu)
./lab.sh status    # show VM state
./lab.sh reset     # destroy & rebuild clean (fresh flags)
./lab.sh reprovision   # re-run provisioning only, keep the VM
./lab.sh shell     # drop into the VM (admin/debug only — not "cheating")
./lab.sh down      # stop the VM
```

Target web app: **http://127.0.0.1:8080**

### Option C — Build a VM image from source (macOS + QEMU)

```bash
brew install qemu

# x86-64 OVA — import anywhere / upload to THM. Runs on any Mac
# (uses QEMU TCG emulation, so the one-time build is slow on Apple Silicon).
./build/build-x86-ova.sh            # → dist/uploadry.ova

# arm64 VMware Fusion VM — for an exam-like "Kali VM vs. target VM" setup on
# Apple Silicon (native HVF, fast). Requires VMware Fusion to run the output.
./build/build-arm64-fusion.sh       # → dist/Progress-Uploadry-arm64.vmwarevm
```

Both scripts re-use `provision/provision.sh` unchanged, so every image is
identical in behaviour.

> **Flags.** This public repo ships **redacted placeholder flags**. To bake real
> ones at build time, export them first:
> ```bash
> USER_FLAG='THM{...}' ROOT_FLAG='THM{...}' ./build/build-x86-ova.sh
> ```
> Without them the provisioner just writes the placeholders — fine for practice.

---

## Requirements

| What you want to do | What you need |
|---------------------|---------------|
| **Run the prebuilt OVA** (Option A) | VirtualBox or VMware — Windows, Linux, or macOS (Intel/Apple Silicon). No Mac required. |
| **Run via Lima** (Option B) | Apple Silicon Mac + `brew install lima` |
| **Build the x86 OVA** (Option C) | macOS + `brew install qemu` (builds on any Mac; slow under emulation on Apple Silicon) |
| **Build the arm64 Fusion VM** (Option C) | Apple Silicon Mac + `brew install qemu` + VMware Fusion |

---

## What you'll learn

- **Web enumeration** — `robots.txt`, directory discovery, and spotting a
  leftover source-backup file served as plain text.
- **File-upload exploitation** — defeating an extension **blacklist** plus a
  client-trusted **MIME type** (e.g. with Burp) to land a `.phtml` webshell and
  get RCE.
- **Post-exploitation as `www-data`** — looting on-disk configs and turning a
  cramped webshell into a stable one (dropping an SSH key).
- **Lateral movement** — credential reuse between a DB config and a system user.
- **Linux privilege escalation** — abusing a `sudo` + **GTFOBins** rule
  (`find`) to get root.
- **Fingerprinting to CVE** — mapping a leaked PHP version to a public advisory
  (php2shell, CVE-2026-109618 / CVE-2026-109619).
- **Remediation** — how each weakness should have been prevented.

## Objectives (no spoilers)

1. Enumerate the web app. Find the admin area and a way in.
2. Get code execution on the box (`www-data`) through the uploader.
3. Find credentials on disk and move laterally to a real user.
4. Escalate to **root**.
5. Collect both flags: `/home/michael/user.txt` and `/root/root.txt`.

## Attacking it realistically (Kali vs. target)

For an exam-like setup where the target has its own IP and you attack from a
**Kali VM**:

- **OVA (Option A):** put both the target and your Kali on the same Host-Only /
  NAT network and target the VM's DHCP address.
- **Lima (Option B):** the app is port-forwarded to `127.0.0.1:8080`, so you can
  run your tools (Burp, `ffuf`, `curl`, a webshell) straight from the Mac. For a
  dedicated IP, add a shared network to `lima/uploadry.yaml`:
  ```yaml
  networks:
    - lima: shared     # needs: brew install socket_vmnet  (+ sudoers entry, see lima docs)
  ```
- **arm64 Fusion VM (Option C):** boots in VMware Fusion with its own NAT IP —
  attack it from a Kali VM on the same Fusion network.

## Files

```
oscp-lab/
├── lab.sh                   # up / down / reset / shell helper (Lima)
├── lima/uploadry.yaml       # the Lima VM definition (arm64)
├── provision/provision.sh   # builds the target (shared by every build path)
├── webapp/                  # the vulnerable SnapShare app
└── build/
    ├── build-x86-ova.sh      # → dist/uploadry.ova  (cross-platform / THM)
    └── build-arm64-fusion.sh # → dist/…vmwarevm     (Apple Silicon local lab)
```
