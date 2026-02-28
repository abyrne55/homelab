---
name: hardening
description: Provides hardening directives for quadlet containers and systemd system services in this homelab project. Load this skill automatically when writing, reviewing, or modifying any .container quadlet file or systemd unit in usr/lib/systemd/system/. Triggered via /hardening for a quick checklist.
---

# Hardening Directives

Always comment when intentionally omitting a hardening directive — future readers need to know it was a conscious choice, not an oversight.

## Quadlet containers

**Baseline — apply to every quadlet:**

```ini
NoNewPrivileges=true      # prevents privilege escalation inside the container
DropCapability=all        # drops all Linux capabilities
AutoUpdate=registry       # keep images up to date automatically

HealthCmd=<command>       # health check appropriate for the service
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

- `ConditionPathExists=` / `ConditionPathIsDirectory=` in `[Unit]` — guard against starting without required config (e.g., a missing Caddyfile or config directory)
- `ExecStartPre=/usr/bin/cosign verify ...` in `[Service]` — verify image provenance before starting (used by caddy and tinyproxy, which use custom images built via GitHub Actions)

**Known exceptions:**

- `DropCapability=all` must be omitted for images that need capabilities inside the container. Use `AddCapability=` to grant only what's needed and document why. Examples:
  - gluetun needs `NET_ADMIN`/`NET_RAW` for WireGuard
  - linuxserver s6-based images call `setgroups()` and need `CAP_SETGID`

## Systemd system services

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
PrivateNetwork=yes        # fully isolated network namespace (only for no-network services)
```

**Known exceptions:**

- All mount-namespace directives (`PrivateTmp`, `ProtectSystem`, `ProtectHome`, `ProtectKernel*`, `ProtectControlGroups`, `PrivateDevices`) must be omitted for services that run `mount`/`umount` across multiple `ExecStart=` lines — systemd clones a fresh mount namespace per step, making mounts from one step invisible to the next. See `init-data-disk.service`.

- `NoNewPrivileges=yes` and any directive implying it (`ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `RestrictRealtime`, `RestrictAddressFamilies`, `PrivateDevices`) must be omitted for services that invoke binaries with SELinux domain transitions — `NO_NEW_PRIVS` blocks all transitions to non-bounded domains. See `ssh-generate-identity.service`.
