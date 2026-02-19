# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo contains GitOps-style homelab infrastructure-as-code based around a bootable container (bootc). The system is built as a fedora-bootc container image and either converted to a VM disk for dev-testing via QEMU or pushed to a container registry for deployment on a Raspberry Pi using `bootc switch`.

Note that none of the software referenced/defined in this repo is meant to be run directly on the local machine; it is meant to run on a Raspberry Pi or within an arm64 QEMU emulator. Do not assume that the local machine is even running Linux.

## Architecture

**Immutable OS Pattern:**

- Root filesystem read-only (bootc), mutable state only in `/var/` and `/etc/`
- Changes via container image updates, not manual system modifications
- `/etc` persists across updates with 3-way merge

**Three-Repository Pattern (in progress):**

1. `homelab` (public) - OS structure, no secrets
   - contains systemd jobs for auto-pulling the next two repos to the system at runtime
2. `homelab-config` (private) - Identity-bearing config
3. `homelab-secrets` (private) - `age`-encrypted credentials

## Key Directories

- `etc/` - System configuration files (mirrors target `/etc` filesystem)
  - `etc/caddy/` - Caddy web server configuration
  - `etc/containers/systemd/users/<uid>/` - Rootless Podman quadlet definitions, organized by user UID
  - `etc/firewalld/` - Firewall configuration
- `usr/` - OS-image-owned configuration (mirrors target `/usr` filesystem)
  - `usr/lib/systemd/system/` - Service units for boot orchestration and secrets management
  - `usr/lib/sysusers.d/` - User/group definitions created at boot
  - `usr/lib/tmpfiles.d/` - Temporary file/directory creation rules
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
make open-jellyfin         # Open Jellyfin web UI
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

Once the VM is running, you can interact with it using the following command format:

```bash
ssh -i ./secrets/core/id_ed25519 -p 2222 -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey core@localhost -- "<your command here>" || true
```

(the `|| true` is to prevent exit statuses from interrupting sibling tool calls)

Use the following command to check on the status of rootless quadlets:

```bash
sudo systemctl --user -M $QUADLET_USERNAME@.host status $QUADLET_NAME.service
```

## Adding New Software

### Quadlets (preferred)

Create `./etc/containers/systemd/users/<uid>/<name>.container` in the Podman quadlet format, where `<uid>` is the numeric UID of the service user (defined in `usr/lib/sysusers.d/`). If the quadlet requires a secret to be loaded from the homelab-secrets repo (separate), add `LoadCredential=credential-name:%t/systemd-age-creds.sock` to the `[Service]` section

### Systemd Services

Create unit file(s) (e.g., `name.service`, `name.socket`, `name.path`) in `./usr/lib/systemd/system/` and update `./Containerfile` with any required dependencies or additions to the `RUN systemctl enable` line
