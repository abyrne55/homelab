# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo contains GitOps-style homelab infrastructure-as-code based around a bootable container (bootc). The system is built as a fedora-bootc container image and either converted to a VM disk for dev-testing via QEMU or pushed to a container registry for deployment on a Raspberry Pi using `bootc switch`.

Note that none of the software referenced/defined in this repo is meant to be run directly on the local machine; it is meant to run on a Raspberry Pi or within an arm64 QEMU emulator. Do not assume that the local machine is even running Linux.

## Architecture

**Immutable OS Pattern:**

- Root filesystem read-only (bootc), mutable persistent state only in `/var/`
- Changes via container image updates, not manual system modifications
- `/etc` is image-owned and reset on every boot (transient `/etc`)

**Three-Repository Pattern:**

1. `homelab` (public) - OS structure, no secrets or identity
   - contains systemd jobs for auto-pulling the next two repos to the system at runtime
2. `homelab-config` (private) - Identity-bearing application config (synced at runtime by `homelab-config-sync.service`)
3. `homelab-secrets` (private) - `age`-encrypted credentials (synced at runtime by `homelab-secrets-sync.service`)

## Codebase Map

Quick file-level index — consult this before exploring the repo.

| File / Directory | What it controls |
|---|---|
| `Containerfile` | OS image definition: packages, file copies, SELinux policy, `systemctl enable` line |
| `Makefile` | All dev operations: build, QEMU run, SSH, vm-switch, await-ghcr |
| `etc/containers/systemd/users/<uid>/` | Rootless quadlet definitions, one directory per service user |
| `etc/firewalld/zones/public.xml` | Firewall rules — only Caddy's ports (20510, 20511) should be open |
| `usr/lib/systemd/system/` | System-level units (boot orchestration, secrets, git sync, NFS mount, WireGuard) |
| `usr/lib/systemd/user/` | User-level non-quadlet units (init-config, configure, bootstrap scripts) and `.target.wants/` enable symlinks |
| `usr/lib/sysusers.d/` | User/group definitions — one file per user, named `NN-username-user.conf` |
| `usr/lib/tmpfiles.d/quadlet-users-homedirs.conf` | Home + Podman directory trees for all quadlet users |
| `usr/lib/tmpfiles.d/quadlet-users-linger.conf` | Linger entries (one per quadlet user) |
| `usr/lib/tmpfiles.d/quadlet-users-subids.conf` | subUID/subGID ranges for rootless Podman |
| `usr/lib/tmpfiles.d/service-state-dirs.conf` | `/var/local/lib/<service>/` dirs for per-service state (config/cache) |
| `usr/lib/tmpfiles.d/core-homedir.conf` | Login user (core) home directory and SSH authorized_keys |
| `usr/lib/tmpfiles.d/prometheus-podman-exporter-configs.conf` | Per-user exporter environment configs (port assignments for X9 metrics endpoints) |
| `usr/lib/tmpfiles.d/` (other files) | NFS mount point, git known-hosts, homelab-config dir |
| `usr/local/bin/` | Scripts baked into the image (`hl`, `secrets-inject`, `wait-for-quadlets`, …) |
| `usr/lib/greenboot/check/required.d/` | Greenboot health checks that must pass or rollback is triggered (secrets-sync, config-sync, caddy) |
| `usr/lib/greenboot/check/wanted.d/` | Greenboot health checks that may fail without triggering rollback (other quadlets, wg-nas) |
| `usr/lib/systemd/system/greenboot-healthcheck.service.d/` | Drop-in: extends timeout, adds `After=` user sessions, runs `wait-for-quadlets` pre-flight |
| `etc/greenboot/greenboot.conf` | Greenboot config (`GREENBOOT_MAX_BOOT_ATTEMPTS=3`) |
| `selinux/` | Custom SELinux policy modules (`.cil` files) |

**Current service user allocations** (update this table when adding a new user):

| User | UID | Host port(s) | subUID range start | Next port index |
|---|---|---|---|---|
| caddy | 1051 | 20510, 20511, 20519 | 231072 | 20512 |
| jellyfin | 1052 | 20520, 20529 | 296608 | 20521 |
| qbittorrent | 1053 | 20530, 20539 | 362144 | 20531 |
| radarr | 1054 | 20540, 20549 | 427680 | 20541 |
| sonarr | 1055 | 20550, 20559 | 493216 | 20551 |
| configarr | 1056 | 20569 (exporter only) | 558752 | 20560 |
| prowlarr | 1057 | 20570, 20579 | 624288 | 20571 |
| home-assistant | 1058 | 20580, 20589 | 689824 | 20581 |
| **next slot** | **1059** | **20590** | **755360** | — |

> **Note:** Port X9 (last in each user's 10-port block) is reserved for `prometheus-podman-exporter` — a localhost-only metrics endpoint scraped by Netdata. No firewalld changes needed for these ports.
>
> **Note:** Netdata is deployed as a privileged **system-level** Podman quadlet (`etc/containers/systemd/netdata.container`) and does not have a dedicated Linux user. It requires `--network=host`, `SYS_PTRACE`, `SYS_ADMIN`, and broad read access to host paths, making rootless operation impractical. No UID, sysusers.d, homedirs, linger, or subids entries are needed. State dirs live under `/var/local/lib/netdata/` (owned root:root).

**Containerfile `systemctl enable` line** — when adding a new *system* unit, append it here. Quadlets are auto-discovered by podman-quadlet and do not need to be listed. User-level units that need to be enabled globally should ship `.target.wants/` symlinks under `usr/lib/systemd/user/` rather than using `systemctl --global enable` in the Containerfile.

## Key Directories

Two top-level directories mirror their target filesystem counterparts, with a deliberate split:

- **`etc/`** — OS-image-owned configuration (mirrors target `/etc/`). Both `etc/` and `usr/` are image-owned and reset on every boot (transient `/etc`). Application config files (Caddyfile, tinyproxy.conf, jellarr config) live in the private `homelab-config` repo, not here — they are synced at runtime to `/var/lib/homelab-config/`.
  - `etc/containers/systemd/users/<uid>/` - Rootless Podman quadlet definitions, organized by user UID
  - `etc/firewalld/` - Firewall configuration
- **`usr/`** — OS-image-owned infrastructure (mirrors target `/usr/`). Use this for systemd units, sysusers, tmpfiles, and other OS-level plumbing that belongs to the system rather than any one application.
  - `usr/lib/systemd/system/` - Service units for boot orchestration and secrets management
  - `usr/lib/systemd/user/` - User-level non-quadlet units (init-config, configure, bootstrap) and `.target.wants/` enable symlinks
  - `usr/lib/sysusers.d/` - User/group definitions created at boot
  - `usr/lib/tmpfiles.d/` - Temporary file/directory creation rules
  - `usr/local/bin/` - OS-level CLI tools baked into the image (e.g., `hl`, `qbittorrent-configure`)
- `selinux/` - Custom SELinux policy modules (`.cil` files) for container and systemd permissions
- `build/` - Generated artifacts (.gitignored and deleted upon `make clean`)

**Persistent storage split:**

| Location | What lives there | Always available? |
|---|---|---|
| `/var/local/lib/<service>/` | Service state: config DB, cache, app data | Yes — local disk |
| `/var/mnt/data/` | Content: media files, downloads | Only when NFS/WireGuard is up |

`/var/local/lib/` dirs are created at boot by `usr/lib/tmpfiles.d/service-state-dirs.conf`. `/var/mnt/data` is an NFSv4.1 share mounted over a WireGuard VPN tunnel to the NAS — see `usr/lib/systemd/system/wg-nas.service` and `var-mnt-data.mount`.

- `secrets/` - Pre-generated keys for injection into QEMU VM (.gitignored)
  - These secrets are injected into the VM during development for convenience. On the Raspberry Pi, unique credentials will be generated on first boot

## Secrets Management

Secrets are encrypted with `age` and decrypted on-demand by `systemd` and `systemd-age-creds`:

- Place keys in `./secrets/` to inject via ISO at boot, or auto-generate on first boot
- Credentials available at `/run/credentials/service-name/credential-name`
- System units: `LoadCredential=name:%t/systemd-age-creds.sock` (`%t` = `/run` in system context)
- User units (quadlets): use hardcoded `/run/systemd-age-creds.sock` — `%t` expands to `/run/user/<uid>` in user context, not `/run`

## Important Commands

All operations go through the Makefile:

```bash
make clean                 # Remove all build artifacts and stop VM
make build-container       # Build the container image (default target)
make build-vm-from-ghcr    # Build qcow2 VM from GHCR (faster, recommended)
make build-vm              # Build qcow2 VM from local container
make run-vm-from-ghcr      # Start QEMU VM from GHCR image (faster, recommended)
make run-vm                # Start QEMU VM from local build
make stop-vm               # Stop running QEMU instance
make reboot-vm             # Stop and restart VM
make await-ghcr            # Wait for GitHub Actions to build current commit
make vm-switch             # Switch running VM to current branch image from GHCR
```

Note: there's also an `ssh-vm` target, but do not use it yourself; that target is for interactive/user use only. Use `vsh` instead (see below).

The Makefile allows you to build container images locally or via GitHub Actions — **prefer GitHub Actions (`from-ghcr` targets)**, as GitHub can build container images much more quickly than the user's machine can.

**Testing workflow:**

1. Commit your changes to a non-main branch and push to origin
2. Wait for the build to complete and then trigger a bootc upgrade inside the running VM

   ```bash
   make await-ghcr vm-switch
   ```

If the VM isn't running or if you're testing changes that affect persistent/mutable parts of the container's filesystem (e.g., /var/), rebuild from scratch instead of doing a bootc upgrade:

```bash
make await-ghcr clean run-vm-from-ghcr
```

To more-quickly test small changes, try interacting with the already-running VM via SSH (see below) before rebuilding.

Once the VM is running, use `vsh` (`~/.local/bin/vsh`) to run commands on it:

```bash
vsh hl failed
vsh "sudo dmesg | tail -20"          # quote when using pipes/redirects/subshells
vsh 'echo $(hostname)-$(date +%s)'   # single-quote to defer expansion to remote
```

Note: `vsh` is always safe to run in the sandbox. Do NOT run `vsh` with `dangerouslyDisableSandbox: true`.

Use `/test-vm [service-name]` whenever you're testing, debugging, or doing other complex/multi-step interactions with the VM.

Use `hl` (baked into the image at `/usr/local/bin/hl`) to manage rootless quadlets:

```bash
hl                                    # status summary for system + all service users
hl status jellyfin                    # detailed status for jellyfin.service
hl status -s homelab-config-sync      # status of a system unit
hl logs jellyfin -n 50               # last 50 log lines
hl logs -u jellyfin tinyproxy         # logs for a secondary service
hl logs -s homelab-secrets-sync -n 20 # logs for a system unit
hl restart qbittorrent               # restart a unit
hl restart -s homelab-config-sync    # restart a system unit
hl failed                            # list failed units across system and all users
hl ps                                # running containers across all users
hl sudo jellyfin -- ls /              # run a command inside a container
hl users                             # list discovered service users
hl help                              # full usage
```

**Always prefer to use `hl` instead of using `systemctl` or `journalctl` directly.** If `hl` is unable to complete a certain task, check `hl help` to ensure you're specifying the correct flags. If that fails, use the `/fallback-cmd` skill to access raw underlying commands.

## Adding New Software

Use `/add-quadlet [service-name]` for the full step-by-step checklist. The short version: each service gets a dedicated system user (sysusers.d), home directory (tmpfiles homedirs), linger entry, subid range, a `.container` quadlet file under `etc/containers/systemd/users/<uid>/`, and a Caddy route in homelab-config. Use `/test-vm [service-name]` for testing and troubleshooting. For hardening directives to apply to the quadlet, use `/hardening`.

**Port assignment scheme:** `2<last 3 digits of UID><index>` — e.g. UID 1051 → 20510, 20511, … All ports stay in 20000–29999 (below the ephemeral port floor of 32768). Tinyproxy is an exception — it is not published to the host and is only reachable via container-internal DNS.

| Service | UID | Host port(s) | Container port(s) | Externally accessible |
|---|---|---|---|---|
| caddy | 1051 | 20510, 20511 | 8080 (HTTP), 8443 (HTTPS) | Yes — firewalld forwards 80→20510, 443→20511 |
| caddy (exporter) | 1051 | 20519 (localhost only) | — | No — Netdata scrape only |
| jellyfin | 1052 | 20520 | 8096 | No — via Caddy only |
| jellyfin (exporter) | 1052 | 20529 (localhost only) | — | No — Netdata scrape only |
| qbittorrent | 1053 | 20530 | 20530 | No — via Caddy only |
| qbittorrent (exporter) | 1053 | 20539 (localhost only) | — | No — Netdata scrape only |
| radarr | 1054 | 20540 | 7878 | No — via Caddy only |
| radarr (exporter) | 1054 | 20549 (localhost only) | — | No — Netdata scrape only |
| sonarr | 1055 | 20550 | 8989 | No — via Caddy only |
| sonarr (exporter) | 1055 | 20559 (localhost only) | — | No — Netdata scrape only |
| configarr | 1056 | none (no UI) | — | No |
| configarr (exporter) | 1056 | 20569 (localhost only) | — | No — Netdata scrape only |
| prowlarr | 1057 | 20570 | 9696 | No — via Caddy only |
| prowlarr (exporter) | 1057 | 20579 (localhost only) | — | No — Netdata scrape only |
| home-assistant | 1058 | 20580 | 8123 | No — via Caddy only |
| matter-server | 1058 | none (pod-internal) | 5580 | No — sidecar in home-assistant pod |
| home-assistant (exporter) | 1058 | 20589 (localhost only) | — | No — Netdata scrape only |

New system units (not quadlets) must also be appended to the `RUN systemctl enable` line in `Containerfile`.

## Skills

| Command | Purpose |
|---|---|
| `/add-quadlet [name]` | Full checklist for adding a new rootless quadlet service |
| `/hardening` | Baseline hardening directives for quadlets and systemd units |
| `/test-vm [service]` | Guided testing/troubleshooting of new or problematic features/services |
| `/selinux-policy` | Write, debug, and extend custom SELinux CIL policy modules |
| `/fallback-cmd` | Raw shell commands when `hl`/`vsh` can't complete a task |
