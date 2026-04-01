# homelab

GitOps-style homelab infrastructure using bootable containers (bootc).

## Overview

This repo builds a [bootc](https://containers.github.io/bootc/)-based system image. Bootc lets you define an OS as a container image, then convert it to a bootable VM disk. The system can update itself by pulling new container images, bringing container-native workflows to full operating systems.

**How it works:**

1. `Containerfile` defines the OS (based on Fedora bootc), including systemd units and quadlets
2. `podman build` creates a container image
3. `bootc-image-builder` converts the container image to a qcow2 VM disk
4. QEMU boots the resulting VM locally for testing

## Included Services

- **Caddy** - Reverse proxy and gateway for all HTTP/HTTPS services. Runs as a rootless Podman quadlet under a dedicated `caddy` user (UID 1051). Listens on internal ports 8080 (HTTP) and 8443 (HTTPS), published to host ports 20510 and 20511. Firewalld forwards external 80 → 20510 and 443 → 20511, so all web traffic enters through Caddy. Routes requests to backend services by hostname. Config (`Caddyfile`) lives in the private `homelab-config` repo.
- **Jellyfin** - Media server. Runs as a rootless Podman quadlet under a dedicated `jellyfin` user (UID 1052). Not directly exposed externally — accessed via Caddy by hostname. Service state lives in `/var/local/lib/jellyfin/`; media is served from the NFS content share at `/var/mnt/data`.
- **Tinyproxy** - Forward proxy (jellynet isolation). Allows Jellyfin to fetch metadata/artwork from approved external domains while keeping it off the main network. Config and domain allowlist live in the private `homelab-config` repo.
- **Jellarr** - Declarative Jellyfin configuration manager. Bootstraps an API key into Jellyfin's SQLite database on first boot, then applies `config.yml` (users, libraries, startup settings) via the Jellyfin API. Re-runs daily via a systemd timer. Config lives in the private `homelab-config` repo.
- **qBittorrent** - Torrent client. Runs as a rootless Podman quadlet under a dedicated `qbittorrent` user (UID 1053). Not directly exposed externally — accessed via Caddy by hostname. All traffic is routed through Gluetun. Service state lives in `/var/local/lib/qbittorrent/`; downloads go to the NFS content share at `/var/mnt/data/content/`.
  - **Gluetun** - Mullvad WireGuard VPN client. Runs alongside qBittorrent in a shared pod so that all torrent traffic is tunnelled through the VPN. WireGuard credentials are loaded at runtime from `homelab-secrets` via `systemd-age-creds`.
- **Radarr** - Movie collection manager. Runs as a rootless Podman quadlet under a dedicated `radarr` user (UID 1054). Not directly exposed externally — accessed via Caddy by hostname. Integrates with qBittorrent to automate movie downloads; hardlinks completed downloads into the media library. Service state lives in `/var/local/lib/radarr/`; media is on the NFS content share at `/var/mnt/data/content/`.
- **Sonarr** - TV series collection manager. Runs as a rootless Podman quadlet under a dedicated `sonarr` user (UID 1055). Not directly exposed externally — accessed via Caddy by hostname. Integrates with qBittorrent to automate TV show downloads; hardlinks completed downloads into the media library. Service state lives in `/var/local/lib/sonarr/`; media is on the NFS content share at `/var/mnt/data/content/`.
- **Configarr** - TRaSH-Guides sync. Runs as a rootless Podman quadlet under a dedicated `configarr` user (UID 1056). No web UI — runs on a timer to push quality profiles and custom formats from TRaSH-Guides into Radarr and Sonarr. Config lives in the private `homelab-config` repo.
- **Prowlarr** - Indexer manager. Runs as a rootless Podman quadlet under a dedicated `prowlarr` user (UID 1057). Not directly exposed externally — accessed via Caddy by hostname. Manages torrent indexers and syncs them to Radarr and Sonarr.
- **Home Assistant** - Home automation platform. Runs as a rootless Podman pod under a dedicated `home-assistant` user (UID 1058), alongside a **python-matter-server** sidecar for Matter/Thread device support. Not directly exposed externally — accessed via Caddy by hostname. Config is mounted read-only from the private `homelab-config` repo.

## Three-Repository Pattern

The system uses three repos to separate concerns:

| Repo | Visibility | Purpose |
|------|-----------|---------|
| `homelab` | Public | OS image structure, systemd units, quadlet definitions — no secrets or identity |
| `homelab-config` | Private | Identity-bearing application config (Caddyfile, tinyproxy.conf, jellarr config) |
| `homelab-secrets` | Private | `age`-encrypted credentials (API keys, passwords) |

`homelab-config` and `homelab-secrets` are cloned and kept up to date at runtime by systemd
services (`homelab-config-sync` and `homelab-secrets-sync`), which run on boot and every 15
minutes. Both use the SSH keypair at `/var/lib/git-ssh/id_ed25519` as a read-only deploy key.

## Disk Architecture

The VM uses a single root disk; content is served from a remote NAS over NFS:

- **Root disk** - Read-only system image (runs in snapshot mode, changes discarded on reboot). Default size is 15G to accommodate large container images (e.g., Home Assistant).
- **Service state** - Each service stores its config and cache in `/var/local/lib/<service>/` on the root disk's persistent `/var/` partition. Always available, independent of network.
- **Content share** - Media, downloads, and shared content live at `/var/mnt/data`, which is an NFSv4.1 share mounted over a WireGuard VPN tunnel to the NAS. `wg-nas.service` establishes the tunnel at boot; `var-mnt-data.mount` then mounts the NFS volume. Content directories are initialized on first mount by `init-content-dirs.service`.

## Secrets Management

Pre-generated secrets can be injected into the VM via an optional ISO image:

**Place secrets in `./secrets/`:**

- `age.key` and `age.key.pub` - Age encryption keys
- `ssh.key` and `ssh.key.pub` - SSH keypair for Git pull operations
- `core/id_ed25519` - SSH private key for the `core` login user (used by `make ssh-vm` and related targets; the matching public key is baked into the image)

**How it works:**

- If secrets exist, `make build-vm` creates a secrets ISO and attaches it to the VM
- The `secrets-inject.service` mounts the ISO and copies secrets to their target locations before boot completes
- If secrets don't exist, systemd services (`age-generate-identity.service` and `ssh-generate-identity.service`) auto-generate new keys on first boot
- The container image always remains secret-free—secrets are only injected at runtime

## Make Targets

| Target | Description |
|--------|-------------|
| `build-container` | Build the container image locally (default target) |
| `build-vm` | Build the qcow2 VM disk image from a local container build |
| `build-vm-from-ghcr` | Build the qcow2 VM disk image from GHCR (faster, recommended) |
| `run-vm` | Start the VM in QEMU (optionally with ./secrets/ injected; see above) |
| `run-vm-from-ghcr` | Build from GHCR and start the VM in QEMU |
| `ssh-vm` | Open an interactive SSH session into the running VM |
| `vm-switch` | Switch running VM to the container image for the current git branch |
| `await-ghcr` | Wait for GitHub Actions to finish building the current commit |
| `reboot-vm` | Reboot the running VM |
| `stop-vm` | Stop the running VM |
| `systemd-analyze-verify` | Verify all custom systemd unit files (pulls from GHCR) |
| `systemd-analyze-security` | Score all custom service units for hardening quality (pulls from GHCR) |
| `clean` | Stop VM and delete all build artifacts |

## Service Management

Once the VM is running, use the `hl` CLI (baked into the image at `/usr/local/bin/hl`) to manage services:

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
hl help                              # full usage
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_NAME` | `homelab` | Container image name |
| `TAG` | `latest` | Container image tag |
| `SSH_PORT` | `2222` | Host port forwarded to VM SSH |
| `ROOT_DISK_SIZE` | `15G` | Size of the root disk image |
| `DATA_DISK_SIZE` | `3G` | Size of the local data disk attached in QEMU (dev/test only) |
| `MONITOR_PORT` | `4444` | localhost TCP port for the QEMU monitor |

QEMU always forwards host ports 80 and 443 to the VM (which Caddy listens on via firewalld forwarding). These are not configurable.

## Dependencies

- [Podman](https://podman.io/) - container build and runtime
- [QEMU](https://www.qemu.org/) - VM emulation (`qemu-system-aarch64`)
- [socat](https://github.com/nicowillis/socat) - used to communicate with the QEMU monitor (`stop-vm`, `clean`)

On macOS with Homebrew:

```bash
brew install podman qemu socat
```
