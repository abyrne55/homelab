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

- **Jellyfin** - Media server accessible at `http://localhost:8096`
- **Demo content** - Big Buck Bunny is downloaded on first boot to `/mnt/media/Movies`

## Disk Architecture

The VM uses two disks:

- **Root disk** - Read-only system image (runs in snapshot mode, changes discarded on reboot)
- **Data disk** - Persistent storage mounted at `/mnt/media` for media files and Jellyfin state

## Secrets Management

Pre-generated secrets can be injected into the VM via an optional ISO image:

**Place secrets in `./secrets/`:**

- `age.key` and `age.key.pub` - Age encryption keys
- `ssh.key` and `ssh.key.pub` - SSH keypair for Git pull operations

**How it works:**

- If secrets exist, `make build-vm` creates a secrets ISO and attaches it to the VM
- The `secrets-inject.service` mounts the ISO and copies secrets to their target locations before boot completes
- If secrets don't exist, systemd services (`age-generate-identity.service` and `ssh-generate-identity.service`) auto-generate new keys on first boot
- The container image always remains secret-free—secrets are only injected at runtime

## Make Targets

| Target | Description |
|--------|-------------|
| `build-container` | Build the container image (default target) |
| `build-vm` | Build the qcow2 VM disk image and data disk |
| `run-vm` | Start the VM in QEMU (optionally with ./secrets/ injected; see above) |
| `ssh-vm` | Build, run, and SSH into the VM |
| `open-jellyfin` | Start VM and open Jellyfin in browser |
| `stop-vm` | Stop the running VM |
| `clean` | Stop VM, remove container image, delete build artifacts |

Targets are composable: `make ssh-vm` will automatically run `build-container` and `build-vm` if needed.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_NAME` | `homelab` | Container image name |
| `TAG` | `latest` | Container image tag |
| `SSH_PORT` | `2222` | Host port forwarded to VM SSH |
| `HTTP_PORT` | `8080` | Host port forwarded to VM port 8080 |
| `JELLYFIN_PORT` | `8096` | Host port forwarded to Jellyfin web UI |
| `DATA_DISK_SIZE` | `3G` | Size of the persistent data disk |
| `DETACH` | `true` | Run QEMU in background (`false` for foreground) |

Example:

```bash
make run-vm HTTP_PORT=8081 DETACH=false
```

## Dependencies

- [Podman](https://podman.io/) - container build and runtime
- [QEMU](https://www.qemu.org/) - VM emulation (`qemu-system-aarch64`)

On macOS with Homebrew:

```bash
brew install podman qemu
```
