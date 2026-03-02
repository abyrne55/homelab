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
| `usr/lib/systemd/system/` | System-level units (boot orchestration, secrets, git sync) |
| `usr/lib/sysusers.d/` | User/group definitions — one file per user, named `NN-username-user.conf` |
| `usr/lib/tmpfiles.d/quadlet-users-homedirs.conf` | Home + Podman directory trees for all quadlet users |
| `usr/lib/tmpfiles.d/quadlet-users-linger.conf` | Linger entries (one per quadlet user) |
| `usr/lib/tmpfiles.d/quadlet-users-subids.conf` | subUID/subGID ranges for rootless Podman |
| `usr/lib/tmpfiles.d/` (other files) | Data disk mount points, git known-hosts, homelab-config dir |
| `usr/local/bin/` | Scripts baked into the image (`hl`, `secrets-inject`, `qbittorrent-configure`, …) |
| `selinux/` | Custom SELinux policy modules (`.cil` files) |

**Current service user allocations** (update this table when adding a new user):

| User | UID | Host port(s) | subUID range start | Next port index |
|---|---|---|---|---|
| caddy | 1051 | 20510, 20511 | 231072 | 20512 |
| jellyfin | 1052 | 20520 | 296608 | 20521 |
| qbittorrent | 1053 | 20530 | 362144 | 20531 |
| radarr | 1054 | 20540 | 427680 | 20541 |
| **next slot** | **1055** | **20550** | **493216** | — |

**Containerfile `systemctl enable` line** — when adding a new *system* unit, append it here. Quadlets are auto-discovered by podman-quadlet and do not need to be listed.

## Key Directories

Two top-level directories mirror their target filesystem counterparts, with a deliberate split:

- **`etc/`** — OS-image-owned configuration (mirrors target `/etc/`). Both `etc/` and `usr/` are image-owned and reset on every boot (transient `/etc`). Application config files (Caddyfile, tinyproxy.conf, jellarr config) live in the private `homelab-config` repo, not here — they are synced at runtime to `/var/lib/homelab-config/`.
  - `etc/containers/systemd/users/<uid>/` - Rootless Podman quadlet definitions, organized by user UID
  - `etc/firewalld/` - Firewall configuration
  - `etc/jellarr/` - Jellarr bootstrap script (OS plumbing, not config — stays in image)
- **`usr/`** — OS-image-owned infrastructure (mirrors target `/usr/`). Use this for systemd units, sysusers, tmpfiles, and other OS-level plumbing that belongs to the system rather than any one application.
  - `usr/lib/systemd/system/` - Service units for boot orchestration and secrets management
  - `usr/lib/sysusers.d/` - User/group definitions created at boot
  - `usr/lib/tmpfiles.d/` - Temporary file/directory creation rules
  - `usr/local/bin/` - OS-level CLI tools baked into the image (e.g., `hl`, `qbittorrent-configure`)
- `selinux/` - Custom SELinux policy modules (`.cil` files) for container and systemd permissions
- `build/` - Generated artifacts (.gitignored and deleted upon `make clean`)
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
make ssh-vm                # Open an interactive SSH session into VM
make stop-vm               # Stop running QEMU instance
make reboot-vm             # Stop and restart VM
make await-ghcr            # Wait for GitHub Actions to build current commit
make vm-switch             # Switch running VM to current branch image from GHCR
```

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

Append `|| true` when running parallel tool calls to prevent a non-zero exit from cancelling siblings.

If `vsh` is unavailable, use the raw SSH command:

```bash
ssh -i ./secrets/core/id_ed25519 -p 2222 -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey core@127.0.0.1 -- "<your command here>" || true
```

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
hl users                             # list discovered service users
hl help                              # full usage
```

The underlying pattern (useful when `hl` is unavailable) is:

```bash
sudo systemctl --user -M $QUADLET_USERNAME@.host status $QUADLET_NAME.service
```

## Adding New Software

Use `/add-quadlet [service-name]` for the full step-by-step checklist. The short version: each service gets a dedicated system user (sysusers.d), home directory (tmpfiles homedirs), linger entry, subid range, a `.container` quadlet file under `etc/containers/systemd/users/<uid>/`, and a Caddy route in homelab-config. For hardening directives to apply to the quadlet, use `/hardening`.

**Port assignment scheme:** `2<last 3 digits of UID><index>` — e.g. UID 1051 → 20510, 20511, … All ports stay in 20000–29999 (below the ephemeral port floor of 32768). Tinyproxy is an exception — it is not published to the host and is only reachable via container-internal DNS.

| Service | UID | Host port(s) | Container port(s) | Externally accessible |
|---|---|---|---|---|
| caddy | 1051 | 20510, 20511 | 8080 (HTTP), 8443 (HTTPS) | Yes — firewalld forwards 80→20510, 443→20511 |
| jellyfin | 1052 | 20520 | 8096 | No — via Caddy only |
| qbittorrent | 1053 | 20530 | 20530 | No — via Caddy only |
| radarr | 1054 | 20540 | 7878 | No — via Caddy only |

New system units (not quadlets) must also be appended to the `RUN systemctl enable` line in `Containerfile`.

## Skills

| Command | Purpose |
|---|---|
| `/add-quadlet [name]` | Full checklist for adding a new rootless quadlet service |
| `/hardening` | Baseline hardening directives for quadlets and systemd units |
| `/vm-debug [service]` | Guided triage for diagnosing VM/service failures |
| `/selinux-policy` | Write, debug, and extend custom SELinux CIL policy modules |
