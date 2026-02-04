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

- `quadlets/` - Podman container definitions (e.g., jellyfin.container, caddy.container)
- `systemd/` - Service units for boot orchestration and secrets management
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
make clean            # Remove all build artifacts and stop VM
make build-container  # Build the container image (default target)
make build-vm         # Build qcow2 VM disk + data disk
make run-vm           # Start QEMU vm
make ssh-vm           # Build, run, and open an interactive SSH session into VM
make open-jellyfin    # Start VM and open Jellyfin web UI
make stop-vm          # Stop running QEMU instance
make reboot-vm        # Stop and restart VM
```

Note that `ssh-vm` and `open-jellyfin` both depend on `run-vm`, which depends on `build-vm`, which depends on `build-container`. So after most changes to the files in this repo, all you need to run is the following command in order to rebuild/boot a fresh VM with your changes in-effect.
```bash
make clean && make run-vm > ./build/log
# Do NOT background this command. Run it as a BLOCKING tool call with a 10 minute timeout
# It uses output redirection because the build process is quite verbose
```

The full build will take several minutes. To more-quickly test out small changes, you can try interacting with the already-running VM via SSH (see below) before rebuilding.

Once the VM is running, you can interact with it using the following command format:

```bash
ssh -i build/id_ed25519 -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey core@localhost -- "<your command here>" || true
```

(the `|| true` is to prevent exit statuses from interrupting sibling tool calls)

Use the following command to check on the status of rootless quadlets:

```bash
sudo systemctl --user -M $QUADLET_USERNAME@.host status $QUADLET_NAME.service
```

## Adding New Software

### Quadlets (preferred)

Simply create `./quadlets/<name>.container` in the Podman quadlet format. If the quadlet requires a secret to be loaded from the homelab-secrets repo (separate), add `LoadCredential=credential-name:%t/systemd-age-creds.sock` to the `[Service]` section

### Systemd Services

Create unit file(s) (e.g., `name.service`, `name.socket`, `name.path`) in `./systemd/` and update `./Containerfile` with any required dependencies or additions to the `RUN systemd enable` line
