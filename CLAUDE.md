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
| **next slot** | **1054** | **20540** | **427680** | — |

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
- `selinux/` - SELinux policy for systemd-age-creds socket access
- `build/` - Generated artifacts (.gitignored and deleted upon `make clean`)
- `secrets/` - Pre-generated keys for injection into QEMU VM (.gitignored)
  - These secrets are injected into the VM during development for convenience. On the Raspberry Pi, unique credentials will be generated on first boot

## Secrets Management

Secrets are encrypted with `age` and decrypted on-demand by `systemd` and `systemd-age-creds`:

- Place keys in `./secrets/` to inject via ISO at boot, or auto-generate on first boot
- Credentials available at `/run/credentials/service-name/credential-name`
- Use `LoadCredential=name:%t/systemd-age-creds.sock` in systemd units

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

### Quadlets (preferred)

Each rootless quadlet runs under a dedicated system user. Adding a new one requires updates to four files before creating the quadlet itself:

1. **`usr/lib/sysusers.d/<N>-<name>-user.conf`** — define the user with a fixed UID and home directory. Add it to the `systemd-age-creds-users` group if the service needs credentials:

   ```text
   u myservice 1054 "My service" /var/home/myservice /sbin/nologin
   m myservice systemd-age-creds-users
   ```

2. **`usr/lib/tmpfiles.d/quadlet-users-homedirs.conf`** — create the home directory and the Podman subdirectory tree that rootless Podman requires:

   ```text
   d /var/home/myservice 0750 myservice myservice - -
   d /var/home/myservice/.local 0755 myservice myservice - -
   d /var/home/myservice/.local/share 0755 myservice myservice - -
   d /var/home/myservice/.local/share/containers 0755 myservice myservice - -
   d /var/home/myservice/.config 0755 myservice myservice - -
   d /var/home/myservice/.config/containers 0755 myservice myservice - -
   ```

3. **`usr/lib/tmpfiles.d/quadlet-users-linger.conf`** — enable linger so systemd starts the user's services at boot without a login:

   ```text
   f /var/lib/systemd/linger/myservice 0644 root root - -
   ```

4. **`usr/lib/tmpfiles.d/quadlet-users-subids.conf`** — append the new user's subUID/subGID range (each user gets 65536 IDs; start after the last allocated range) to both the `subuid` and `subgid` write directives.

Then create `./etc/containers/systemd/users/<uid>/<name>.container` in the Podman quadlet format. If the quadlet requires a secret, add `LoadCredential=credential-name:/run/systemd-age-creds.sock` to the `[Service]` section (use the hardcoded `/run/` path, not `%t/` — in user units `%t` expands to `/run/user/<uid>`, not `/run`)

**Port assignment scheme:** Host-published ports use the formula `2<last 3 digits of UID><index>`, e.g. UID 1051 → 20510, 20511, …; UID 1052 → 20520, 20521, …. This encodes the owning user into the port number and keeps all ports in the 20000–29999 range (below the Linux ephemeral port floor of 32768). Tinyproxy is an exception — it is not published to the host and is only reachable via container-internal DNS.

| Service | UID | Host port(s) | Container port(s) | Externally accessible |
|---|---|---|---|---|
| caddy | 1051 | 20510, 20511 | 8080 (HTTP), 8443 (HTTPS) | Yes — firewalld forwards 80→20510, 443→20511 |
| jellyfin | 1052 | 20520 | 8096 | No — via Caddy only |
| qbittorrent | 1053 | 20530 | 20530 | No — via Caddy only |

**Adding a new service to the stack:**

1. Create the quadlet (see above) with the service's assigned host port.
2. Add a hostname-based route to the `Caddyfile` in the private `homelab-config` repo, pointing the new hostname to `host.containers.internal:<host-port>`.
3. Do **not** open the service port in `firewalld` — all external HTTP/HTTPS access flows through Caddy (ports 20510/20511), not directly to service ports.

## Hardening

Always comment when intentionally omitting a hardening directive so future readers know it was a conscious choice, not an oversight.

### Quadlet containers

**Baseline — apply to every quadlet:**

```ini
NoNewPrivileges=true      # prevents privilege escalation inside the container
DropCapability=all        # drops all Linux capabilities
AutoUpdate=registry       # keep images up to date automatically

HealthCmd=<command>       # health check command appropriate for the service
HealthStartPeriod=30s
HealthInterval=30s
```

**Good to add if the image supports it:**

```ini
ReadOnly=true             # container root filesystem is read-only
ReadOnlyTmpfs=true        # /tmp is also read-only
Notify=healthy            # systemd waits for healthy state, not just process start
```

**Also consider:**

- `ConditionPathExists=` / `ConditionPathIsDirectory=` in `[Unit]` — guard against starting without required config (e.g., a missing Caddyfile)
- `ExecStartPre=/usr/bin/cosign verify ...` in `[Service]` — verify image provenance before starting (used by caddy and tinyproxy, which use custom images built via GitHub Actions)

**Known exceptions:**

- `DropCapability=all` must be omitted for images that need capabilities inside the container (e.g., gluetun needs `NET_ADMIN`/`NET_RAW` for WireGuard; linuxserver s6-based images call `setgroups()` and need `CAP_SETGID`). Use `AddCapability=` to grant only what's needed and document why.

### Systemd system services

**Baseline — apply to every system service:**

```ini
NoNewPrivileges=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
LockPersonality=yes
RestrictRealtime=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/...   # explicit allowlist of paths the service actually writes to
```

**Good to add if the service allows it:**

```ini
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6  # or just AF_UNIX for network-free services
PrivateDevices=yes        # no access to physical devices
PrivateNetwork=yes        # fully isolated network namespace (only for services with no network needs)
```

**Known exceptions:**

- All mount-namespace-creating directives (`PrivateTmp`, `ProtectSystem`, `ProtectHome`, `ProtectKernel*`, `ProtectControlGroups`, `PrivateDevices`) must be omitted for services that run `mount`/`umount` across multiple `ExecStart=` lines — systemd clones a fresh mount namespace for each step, so mounts from one step are invisible to the next (see `init-data-disk.service`).
- `NoNewPrivileges=yes` (and any directive that implies it: `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `RestrictRealtime`, `RestrictAddressFamilies`, `PrivateDevices`) must be omitted for services that invoke binaries with SELinux domain transitions — `NO_NEW_PRIVS` blocks all transitions to non-bounded domains (see `ssh-generate-identity.service`).

### Systemd Services

Create unit file(s) (e.g., `name.service`, `name.socket`, `name.path`) in `./usr/lib/systemd/system/` and update `./Containerfile` with any required dependencies or additions to the `RUN systemctl enable` line
