---
name: fallback-cmd
description: Reveals the raw shell commands underlying preferred tools like 'ssh nook', 'vsh', and 'hl'. Use this skill ONLY if a preferred tool is unavailable or unable to complete a certain task.
argument-hint: [tool-name]
---

# Fallback Commands

Use these raw commands **only if** the preferred tool (`vsh`, `hl`) is unavailable or unable to complete a task.

**Key gotchas for rootless Podman commands:**

- Container names are `systemd-<service-name>` (e.g., `systemd-jellyfin`), not just the service name
- Must run in the service user's context with `XDG_RUNTIME_DIR=/run/user/$(id -u)` set
- List available containers first: `sudo su - <user> -s /bin/sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u) podman ps"`

---

## vsh (QEMU VM SSH wrapper)

**When:** `vsh` is unavailable or broken.

**Preferred:**

```bash
vsh 'echo $(hostname)-$(date +%s)'
```

**Fallback (raw SSH):**

```bash
ssh -i ./secrets/core/id_ed25519 -p 2222 \
  -o LogLevel=QUIET \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  core@127.0.0.1 -- "<your command here>"
```

**One-liner for easy copy:**

```bash
ssh -i ./secrets/core/id_ed25519 -p 2222 -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey core@127.0.0.1 -- "YOUR_COMMAND"
```

---

## ssh nook (production SSH)

**When:** running commands on the production nook hardware.

**Preferred:**

```bash
ssh nook -- "<your command here>"
```

No special flags needed — assumes `~/.ssh/config` has nook configured with user `core`.

**Note:** `ssh nook` is NOT sandbox-safe. Run with `dangerouslyDisableSandbox: true`, or disable the sandbox first.

---

## hl (homelab quadlet manager)

**When:** `hl` is unavailable or `hl help` doesn't show the flag you need.

### Status / Logs (User Quadlets)

**Preferred:**

```bash
hl status jellyfin
hl logs jellyfin -n 50
hl restart qbittorrent
```

**Fallback (systemctl/journalctl):**

```bash
# Status of a user unit
sudo systemctl --user -M jellyfin@.host status jellyfin.service

# Last 50 log lines for a user unit (use --no-pager in SSH)
sudo journalctl --user-unit jellyfin.service -n 50 -e --no-pager

# Restart a user unit
sudo systemctl --user -M jellyfin@.host restart jellyfin.service

# Watch logs in real-time
sudo journalctl --user-unit jellyfin.service -f
```

### Status / Logs (System Units)

**Preferred:**

```bash
hl status -s homelab-config-sync
hl logs -s homelab-secrets-sync -n 20
hl restart -s homelab-config-sync
```

**Fallback (systemctl/journalctl):**

```bash
# Status of a system unit
sudo systemctl status homelab-config-sync.service

# Last 20 log lines for a system unit (use --no-pager in SSH)
sudo journalctl -u homelab-config-sync.service -n 20 -e --no-pager

# Restart a system unit
sudo systemctl restart homelab-config-sync.service

# Watch logs in real-time
sudo journalctl -u homelab-config-sync.service -f
```

### List Failed Units

**Preferred:**

```bash
hl failed
```

**Fallback (systemctl):**

```bash
# System units
sudo systemctl list-units --failed

# User units (for a specific user, e.g., jellyfin)
sudo systemctl --user -M jellyfin@.host list-units --failed
```

### Running Containers

**Preferred:**

```bash
hl ps
```

**Fallback (podman):**

```bash
# List all running containers across all users
# User containers only visible when running in user context:
sudo su - jellyfin -s /bin/sh -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) podman ps"

# For system containers (if any):
sudo podman ps
```

### Run Command Inside Container

**Preferred:**

```bash
hl sudo jellyfin -- ls /
```

**Fallback (podman exec):**

```bash
# Quadlet containers are named systemd-<service-name>
# Run podman exec in the service user's context:
sudo su - jellyfin -s /bin/sh -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) podman exec systemd-jellyfin ls /"

# General pattern (replace jellyfin with service name):
sudo su - <service_user> -s /bin/sh -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) podman exec systemd-<service_name> <command>"
```

---

## Reference

For `systemctl` subcommands, flags, and exit codes not covered above, consult `.claude/references/systemd/systemctl.1.txt`.
