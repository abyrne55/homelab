---
name: hardening
description: Provides hardening directives for quadlet containers and systemd system services in this homelab project. Load this skill automatically when writing, reviewing, or modifying any .container quadlet file or systemd unit in usr/lib/systemd/system/. Triggered via /hardening for a quick checklist.
---

# Hardening Directives

Always comment when intentionally omitting a hardening directive — future readers need to know it was a conscious choice, not an oversight.

## Quadlet containers — `[Container]` section

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

## Quadlet containers — `[Service]` section

> **WARNING: Do NOT add any systemd hardening directives to `[Service]` sections of rootless quadlet files.**

Every standard hardening directive breaks rootless Podman. The mechanism:

Rootless Podman invokes `newuidmap` — a **setuid-root** binary — to write UID mappings to `/proc/<child>/uid_map` when setting up user namespaces. For any of the seccomp-based directives (e.g. `ProtectClock`, `SystemCallArchitectures`, `RestrictSUIDSGID`) or namespace-isolation directives (e.g. `ProtectHostname`) to work in an **unprivileged** user service, the user systemd instance must set `PR_SET_NO_NEW_PRIVS` first — it has no `CAP_SYS_ADMIN` and NNP is the only alternative. That flag inherits to the Podman process, causing the setuid bit on `newuidmap` to be silently ignored, and every container fails with:

```text
newuidmap: write to uid_map failed: Operation not permitted
Error: fatal error, unable to create a new pause process: cannot set up
namespace using "/usr/bin/newuidmap": exit status 1
```

This applies to **all** standard directives tested:

| Directive | Why it forces NNP |
|---|---|
| `ProtectClock=yes` | Installs seccomp filter (requires `CAP_SYS_ADMIN` or NNP) |
| `SystemCallArchitectures=native` | Installs seccomp filter |
| `RestrictSUIDSGID=yes` | Installs seccomp filter |
| `MemoryDenyWriteExecute=yes` | Installs seccomp filter |
| `ProtectHostname=yes` | Creates UTS namespace (requires `CAP_SYS_ADMIN` or NNP) |
| `RestrictNamespaces=yes` | Directly breaks Podman's user/net/mnt namespace creation |

The `[Service]` section of a quadlet should contain **only** runtime policy and credential loading:

```ini
[Service]
Restart=on-failure
RestartSec=5
LoadCredential=...        # age-encrypted credentials if needed
Type=oneshot              # if applicable
RuntimeDirectory=...      # if applicable
ExecStartPre=...          # pre-start checks or cosign verify
```

**Why this doesn't matter:** Container-level isolation (`NoNewPrivileges=true`, `DropCapability=all`, `ReadOnly=true`) in `[Container]` applies to the processes **inside** the container, not to the host-side Podman process. This is where all the meaningful hardening lives for quadlets.

**System services are unaffected** — they run under the root systemd instance which has `CAP_SYS_ADMIN` and installs seccomp filters without needing NNP.

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
ProtectClock=yes
MemoryDenyWriteExecute=yes
ProtectHostname=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
SystemCallArchitectures=native
ProtectProc=noaccess
ProcSubset=pid
UMask=0077
```

**Good to add if the service allows it:**

```ini
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6  # or just AF_UNIX for network-free services
PrivateDevices=yes        # no access to physical devices
PrivateNetwork=yes        # fully isolated network namespace (only for no-network services)
```

**Known exceptions:**

- All mount-namespace directives (`PrivateTmp`, `ProtectSystem`, `ProtectHome`, `ProtectKernel*`, `ProtectControlGroups`, `PrivateDevices`) must be omitted for services that run `mount`/`umount` across multiple `ExecStart=` lines — systemd clones a fresh mount namespace per step, making mounts from one step invisible to the next. See `init-data-disk.service`.

- `NoNewPrivileges=yes` and **all directives implying it** must be omitted for services that invoke binaries with SELinux domain transitions — `NO_NEW_PRIVS` blocks all transitions to non-bounded domains (`avc: denied { nnp_transition }`).
  - The confirmed NNP-implying directives are: `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `RestrictRealtime`, `RestrictAddressFamilies`, `PrivateDevices`, **`ProtectClock`**, **`MemoryDenyWriteExecute`**, **`ProtectHostname`**, **`RestrictSUIDSGID`**, **`RestrictNamespaces`**, **`SystemCallArchitectures`**, **`ProtectProc`**, **`ProcSubset`**.
  - Affected services: `ssh-generate-identity.service` (ssh-keygen: `ssh_keygen_exec_t → ssh_keygen_t`), `wg-nas.service` (ip: `ifconfig_exec_t → ifconfig_t`).
  - Symptom: `avc: denied { nnp_transition }` in journal, exit code 203/EXEC.
  - `wg-nas.service` keeps the non-NNP subset: `PrivateTmp`, `ProtectControlGroups`, `LockPersonality`, `ProtectSystem=strict`, `ProtectHome`, `ProtectClock`, `MemoryDenyWriteExecute`, `ProtectHostname`, `RestrictSUIDSGID`, `RestrictNamespaces`, `SystemCallArchitectures`, `ProtectProc`, `ProcSubset`, `UMask`. (The first five were already confirmed safe; `ProtectClock` and the rest don't imply NNP for root services.)

- `PrivateNetwork=yes` must not be set on `wg-nas.service` — it disconnects `AF_NETLINK`, which `ip(8)` and `wg(8)` require to configure interfaces via the kernel.

- `PrivateDevices=yes` must not be set on `secrets-inject.service` — it mounts `/dev/disk/by-label/SECRETS`.

- `ReadWritePaths=` under `ProtectSystem=strict` requires the target path to **already exist** when the service starts — systemd sets up the bind mount during namespace initialization, before `ExecStart=` runs. If the service's purpose is to *create* that path, use the nearest existing parent instead. See `init-content-dirs.service` (`ReadWritePaths=/var/mnt/data`, not `/var/mnt/data/content`).

## Validating hardening with systemd-analyze security

Run `make systemd-analyze-local` to build the image locally and run both verify and security (used in CI). To score against a pushed branch image instead (e.g. on a branch without a PR), use `make systemd-analyze-security` — it pulls from GHCR so the branch must have been pushed and built first.

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
