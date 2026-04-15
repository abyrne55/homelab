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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6  # tighten to AF_UNIX for network-free services
```

**Add these if the service allows it:**

```ini
PrivateNetwork=yes        # fully isolated network namespace — use for no-network services
PrivateDevices=yes        # no access to physical devices
IPAddressDeny=any         # pair with PrivateNetwork=yes for belt-and-suspenders network isolation
CapabilityBoundingSet=<caps>  # strip capabilities the service doesn't need; see CAP_DAC_OVERRIDE note below
```

**Known exceptions:**

- All mount-namespace directives (`PrivateTmp`, `ProtectSystem`, `ProtectHome`, `ProtectKernel*`, `ProtectControlGroups`, `PrivateDevices`) must be omitted for services that run `mount`/`umount` across multiple `ExecStart=` lines — systemd clones a fresh mount namespace per step, making mounts from one step invisible to the next. See `init-data-disk.service`.

- `NoNewPrivileges=yes` and **all directives implying it** must be omitted for services that invoke binaries with SELinux domain transitions — `NO_NEW_PRIVS` blocks all transitions to non-bounded domains (`avc: denied { nnp_transition }`).
  - The confirmed NNP-implying directives are: `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `RestrictRealtime`, `RestrictAddressFamilies`, `PrivateDevices`, **`ProtectClock`**, **`MemoryDenyWriteExecute`**, **`ProtectHostname`**, **`RestrictSUIDSGID`**, **`RestrictNamespaces`**, **`SystemCallArchitectures`**, **`ProtectProc`**, **`ProcSubset`**.
  - Affected services: `ssh-generate-identity.service` (ssh-keygen: `ssh_keygen_exec_t → ssh_keygen_t`), `wg-nas.service` (ip: `ifconfig_exec_t → ifconfig_t`).
  - Symptom: `avc: denied { nnp_transition }` in journal, exit code 203/EXEC.
  - `wg-nas.service` keeps the non-NNP subset: `PrivateTmp`, `ProtectControlGroups`, `LockPersonality`, `ProtectSystem=strict`, `ProtectHome`, `ProtectClock`, `MemoryDenyWriteExecute`, `ProtectHostname`, `RestrictSUIDSGID`, `RestrictNamespaces`, `SystemCallArchitectures`, `ProtectProc`, `ProcSubset`, `UMask`. (The first five were already confirmed safe; `ProtectClock` and the rest don't imply NNP for root services.)
  - `ssh-generate-identity.service` uses the same non-NNP subset plus `PrivateNetwork=yes`, `IPAddressDeny=any`, and `CapabilityBoundingSet=` (empty — ssh-keygen, install, chmod, chcon as root need no capabilities).

- `PrivateNetwork=yes` must not be set on `wg-nas.service` — it disconnects `AF_NETLINK`, which `ip(8)` and `wg(8)` require to configure interfaces via the kernel.

- `PrivateDevices=yes` must not be set on `secrets-inject.service` — it mounts `/dev/disk/by-label/SECRETS`.

- `UMask=0077` must not be set on services that write files other users need to read. `homelab-config-sync` clones a git repo to `/var/lib/homelab-config/` that container users (e.g. caddy UID 1051) must be able to read — `UMask=0077` makes git create dirs/files as `700/600` (owner root only), causing `ConditionPathExists` guards to silently fail and services to never start on a clean boot. Services writing public-readable files should use the default root umask (0022). Services writing private data only (`homelab-secrets-sync`, `age-generate-identity`) are fine with `UMask=0077`.

- `CapabilityBoundingSet=` caveat: stripping all capabilities except `CAP_SYS_ADMIN` also removes `CAP_DAC_OVERRIDE`. Without it in the bounding set, root can no longer bypass DAC permission checks on files not owned by UID 0 — this silently breaks `install`/`cp` from mounted ISOs or files created by a non-root host user. Always include `CAP_DAC_OVERRIDE` when the service reads files from external sources. Example: `secrets-inject.service` uses `CapabilityBoundingSet=CAP_SYS_ADMIN CAP_DAC_OVERRIDE`. Services that only operate on files they create (e.g. `ssh-generate-identity.service`) can use an empty `CapabilityBoundingSet=`.

- `ReadWritePaths=` under `ProtectSystem=strict` requires the target path to **already exist** when the service starts — systemd sets up the bind mount during namespace initialization, before `ExecStart=` runs. If the service's purpose is to *create* that path, use the nearest existing parent instead. See `init-content-dirs.service` (`ReadWritePaths=/var/mnt/data`, not `/var/mnt/data/content`).

## User-level service units (non-quadlet)

These are `*.service` files in `usr/lib/systemd/user/` that run scripts/tools (init-config, configure, bootstrap) rather than containers. They run under a service user's systemd instance.

**Baseline — apply to every user-level service unit:**

```ini
NoNewPrivileges=yes
PrivateTmp=yes
PrivateUsers=yes         # works fine in user services (unlike quadlet [Service] sections)

ProtectSystem=strict
ProtectControlGroups=yes
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectClock=yes
ProtectProc=invisible    # prefer invisible over noaccess in user context

LockPersonality=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
```

**Network isolation — always set both `PrivateNetwork=` and `RestrictAddressFamilies=`:**

`PrivateNetwork=yes` creates an isolated network namespace (loopback only). `RestrictAddressFamilies=` restricts which socket families the process can even open. Use the tightest combination the service actually needs:

| Service pattern | `PrivateNetwork=` | `RestrictAddressFamilies=` |
|---|---|---|
| No network (init-config, file writers) | `yes` | `none` |
| Loopback only (calls localhost API) | omit | `AF_UNIX AF_INET` |
| Internet HTTP calls (configure scripts) | omit | `AF_INET` |
| Calls `systemctl --user` via D-Bus | omit | `AF_UNIX` |
| **libpod-embedding (Podman CLI/library)** | **omit** — breaks libpod | `none` or tightest needed |

**Tailor `ProtectHome=` per service:**

| Service pattern | `ProtectHome=` |
|---|---|
| Writes config to `/var/local/lib/…` | `tmpfs` |
| Reads from home-adjacent paths | `readonly` |
| Calls `systemctl --user` | **omit** (see note below) |

**`ReadWritePaths=`** — required under `ProtectSystem=strict` for services that write to `/var/local/lib/<service>/config`. The path must already exist when the service starts.

**Known exceptions:**

- `ProtectHome=yes` **must be omitted** for services that call `systemctl --user` (e.g., `jellarr-bootstrap.service`). `ProtectHome` also hides `/run/user/<uid>/`, which is where the user D-Bus socket lives — without it, `systemctl --user` cannot communicate with the user manager.

- `PrivateUsers=yes` is safe in standalone user service units. It is **not** the same as the `[Service]` section of rootless quadlet files — these units don't invoke `newuidmap` and don't set up container user namespaces, so NNP is not an issue here.

- Services that **embed libpod directly** (e.g. `prometheus-podman-exporter`, which uses the Podman Go library rather than the socket API) can only use purely seccomp/prctl directives. At init, libpod calls `setns()` to join the rootless pause process's user and mount namespaces (by opening `/proc/<pause_pid>/ns/user`). Two classes of directives break this, confirmed via strace:

  1. **Any directive that causes systemd to create a user or network namespace**, even as a failed side effect of attempting mount namespace setup: `PrivateTmp`, `PrivateNetwork`, `PrivateUsers`, `ProtectClock`, `ProtectKernelLogs`, `ProtectKernelModules`, `ProtectSystem`, `ProtectHome`, `ProtectHostname`, `ProtectControlGroups`, `ProtectProc`. Systemd calls `unshare(CLONE_NEWUSER|CLONE_NEWNS)` for mount-namespace directives; even when the mount half fails with EPERM (expected for an unprivileged user service), the user namespace is already live. From inside it, the pause process's namespace file returns EACCES, and libpod crashes with a nil pointer panic. `PrivateNetwork=yes` triggers the same failure via network namespace setup. Symptom in all cases: `Error: fatal error, invalid internal status, unable to create a new pause process: cannot re-exec process to join the existing user namespace`, exit code 125.

  2. **`RestrictNamespaces=yes`** — blocks `setns()` directly via seccomp, preventing libpod from joining the pause process's namespaces at all. Same exit-code-125 symptom.

  3. **`CapabilityBoundingSet=`** — fails in user service context with exit code 218/CAPABILITIES (`Failed to drop capabilities: Operation not permitted`). Reducing the bounding set requires `CAP_SETPCAP`, which unprivileged user services don't have.

  Safe hardening for libpod-embedding services is limited to directives with no mount/namespace component and no capability manipulation:

  ```ini
  NoNewPrivileges=yes
  LockPersonality=yes
  RestrictRealtime=yes
  RestrictSUIDSGID=yes
  SystemCallArchitectures=native
  RestrictAddressFamilies=AF_INET AF_UNIX   # or =none if no network needed
  IPAddressDeny=any                          # safe to add when RestrictAddressFamilies=none
  UMask=0077
  # Syscall blocklists for groups Podman/Go never use — safe to add, each worth ~0.2 pts:
  SystemCallFilter=~@clock @cpu-emulation @debug @module @obsolete @raw-io @reboot @swap
  # Avoid @mount, @privileged, @resources — libpod or the Go runtime may use these
  ```

  Always document the omissions with a comment explaining the libpod constraint so future readers know it is intentional. See `usr/lib/systemd/user/prometheus-podman-exporter.service.d/10-homelab.conf` and `usr/lib/systemd/user/podman-image-prune.service` for examples.

## Validating hardening with systemd-analyze security

Run `make systemd-analyze-local` to build the image locally and run both verify and security (used in CI). To score against a pushed branch image instead (e.g. on a branch without a PR), use `make systemd-analyze-security` — it pulls from GHCR so the branch must have been pushed and built first.

**Score bands** (from systemd source; displayed score is internal 0–100 divided by 10):

| Displayed score | Label | CI behavior |
|---|---|---|
| 0.0 | PERFECT | pass |
| 0.1–0.9 | SAFE | pass |
| 1.0–4.9 | OK | pass |
| 5.0–7.4 | MEDIUM | pass |
| 7.5–8.9 | EXPOSED | **fail** |
| 9.0–9.9 | UNSAFE | **fail** |
| 10.0 | DANGEROUS | **fail** |

**CI enforcement:** The `systemd-analyze / correctness-and-security` check (`.github/workflows/systemd-analyze.yml`) runs on PRs, builds the image locally via `make systemd-analyze-local`, and fails if any unit scores EXPOSED or worse (badness ≥ 7.5).

**Expected scores for baseline-hardened services:** OK–MEDIUM (< 7.5). Services with intentional exceptions (e.g., SELinux transitions requiring omission of `NoNewPrivileges`) must still score below EXPOSED.

**Note on `ProtectProc=` for root services:** `systemd-analyze security` marks `ProtectProc=` as ✗ for services running as root without an active user namespace (i.e., without `PrivateUsers=yes` or `DynamicUser=yes`). The directive is still set and enforced by the kernel, but systemd-analyze doesn't credit it because the protection is reduced without namespace isolation. This is expected for root services like `wg-nas.service` that can't use `PrivateUsers` due to SELinux domain transitions.

## Additional References

If in doubt about a quadlet option or systemd-analyze behavior, these docs may help:

- `.claude/references/podman/podman-systemd.unit.5.md` (lines 443–840) — detailed descriptions of the security-relevant container options used above: `AutoUpdate`, `DropCapability`, `HealthCmd`, `NoNewPrivileges`, `Notify`, `ReadOnly`, `ReadOnlyTmpfs`
- `.claude/references/systemd/systemd-analyze.1.txt` — full reference for `systemd-analyze verify` (unit validation, line 481), `systemd-analyze security` (hardening scoring and per-directive breakdown, line 561), and other subcommands (`blame`, `critical-chain`, `condition`, `capability`, `syscall-filter`)
