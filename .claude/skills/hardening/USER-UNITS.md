# User-Level Service Units (Non-Quadlet)

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
