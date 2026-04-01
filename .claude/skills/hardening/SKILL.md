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

- When an image needs specific capabilities, keep `DropCapability=all` and add `AddCapability=` for only what's needed — do **not** omit `DropCapability=all`. Examples:
  - gluetun: `DropCapability=all` + `AddCapability=NET_ADMIN NET_RAW` (WireGuard tunnel + ICMP healthchecks)
- `DropCapability=all` must be omitted entirely only for images where the required caps are unknown or broad. Document why. Example:
  - linuxserver s6-based images call `setgroups()` and need `CAP_SETGID` — but the full set of caps used by s6 internals is not enumerable, so `DropCapability=all` is omitted

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

- `NoNewPrivileges=yes` and any directive implying it (`ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `RestrictRealtime`, `RestrictAddressFamilies`, `PrivateDevices`) must be omitted for services that invoke binaries with SELinux domain transitions — `NO_NEW_PRIVS` blocks all transitions to non-bounded domains. See `ssh-generate-identity.service` (ssh-keygen: `ssh_keygen_exec_t → ssh_keygen_t`) and `wg-nas.service` (ip: `ifconfig_exec_t → ifconfig_t`). Symptom: `avc: denied { nnp_transition }` in the journal, exit code 203/EXEC.

- `ReadWritePaths=` under `ProtectSystem=strict` requires the target path to **already exist** when the service starts — systemd sets up the bind mount during namespace initialization, before `ExecStart=` runs. If the service's purpose is to *create* that path, use the nearest existing parent instead. See `init-content-dirs.service` (`ReadWritePaths=/var/mnt/data`, not `/var/mnt/data/content`).

## Validating hardening with systemd-analyze security

Run `make systemd-analyze-security-local` to score all custom `.service` files (builds image locally, used in CI). To score against a pushed branch image instead (e.g. on a branch without a PR), use `make systemd-analyze-security` — it pulls from GHCR so the branch must have been pushed and built first.

**Score bands:**

| Score | Rating |
|-------|--------|
| 0–1.9 | OK 🙂 |
| 2.0–3.9 | MEDIUM 😐 |
| 4.0–5.9 | EXPOSED 😨 |
| 6.0+ | UNSAFE 🤮 |

**CI enforcement:** The `systemd-analyze / correctness-and-security` check (`.github/workflows/systemd-analyze.yml`) runs on PRs, builds the image locally via `make systemd-analyze-local`, and fails if any service scores UNSAFE (≥ 6.0). EXPOSED units print their full analysis for visibility but do not fail the build.

**Expected scores for baseline-hardened services:** OK–MEDIUM (< 4.0). Services with intentional exceptions (e.g., SELinux transitions requiring omission of `NoNewPrivileges`) will score in the EXPOSED range — document the exception in a comment in the unit file.

## Additional References

If in doubt about a quadlet option, these docs may help:

- `.claude/references/podman/podman-systemd.unit.5.md` (lines 443–840) — detailed descriptions of the security-relevant container options used above: `AutoUpdate`, `DropCapability`, `HealthCmd`, `NoNewPrivileges`, `Notify`, `ReadOnly`, `ReadOnlyTmpfs`
