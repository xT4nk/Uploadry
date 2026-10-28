# Changelog

All notable changes to the Uploadry lab are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] — 2026-10-28

### Added
- Deliberately vulnerable "SnapShare" PHP web app (`webapp/`): info-disclosure
  via a leftover `config.php.bak`, and an upload filter that blacklists
  extensions but misses `.phtml` (MIME-type trusted from the client).
- Full chain: web foothold → `www-data` → credential reuse to `michael` →
  `sudo /usr/bin/find` GTFOBins privesc to root.
- `provision/provision.sh` — reproducible target build (Apache/PHP, user,
  sudo rule, flags, SSH), shared by every build path.
- Three ways to get the VM:
  - `lab.sh` + `lima/uploadry.yaml` — native arm64 run on Apple Silicon (Lima).
  - `build/build-x86-ova.sh` — x86-64 OVA for VirtualBox/VMware/TryHackMe.
  - `build/build-arm64-fusion.sh` — arm64 VMware Fusion VM for a Kali-vs-target lab.
- `README.md` with usage, a per-scenario requirements table, screenshots and a
  "What you'll learn" section.
- MIT `LICENSE`.

### Security
- Intended for isolated lab use only. Never expose the target to an untrusted
  network.
