# homelab

GitOps-style homelab infrastructure using bootable containers (bootc).

## Overview

This repo builds a [bootc](https://containers.github.io/bootc/)-based system image. Bootc lets you define an OS as a container image, then convert it to a bootable VM disk. The system can update itself by pulling new container images, bringing container-native workflows to full operating systems.

**How it works:**
1. `Containerfile` defines the OS (based on Fedora bootc), including systemd units and quadlets
2. `podman build` creates a container image
3. `bootc-image-builder` converts the container image to a qcow2 VM disk
4. QEMU boots the resulting VM locally for testing

## Make Targets

| Target | Description |
|--------|-------------|
| `build-container` | Build the container image (default target) |
| `build-vm` | Build the qcow2 VM disk image |
| `run-vm` | Start the VM in QEMU (detached by default) |
| `ssh-vm` | Build, run, and SSH into the VM |
| `clean` | Kill QEMU, remove container image, delete build artifacts |

Targets are composable: `make ssh-vm` will automatically run `build-container` and `build-vm` if needed.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_NAME` | `homelab` | Container image name |
| `TAG` | `latest` | Container image tag |
| `SSH_PORT` | `2222` | Host port forwarded to VM SSH |
| `HTTP_PORT` | `8080` | Host port forwarded to VM port 8080 |
| `JELLYFIN_PORT` | `8096` | Host port forwarded to Jellyfin web UI |
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
