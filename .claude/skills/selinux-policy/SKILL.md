---
name: selinux-policy
description: >
  Write, debug, and extend custom SELinux CIL (Common Intermediate Language) policy modules for
  the homelab bootc project. Use this skill automatically whenever the user is editing any .cil
  file in the selinux/ directory, mentions an "AVC denial" or "avc: denied", asks why a service
  or container is being blocked, references audit2allow or semodule, or shares an audit log
  snippet. Also trigger for /selinux-policy. Don't wait for the user to explicitly ask — if
  SELinux is the likely cause of a permission problem, proactively apply this skill.
---

# SELinux Policy (CIL) — Homelab Guide

## Project Setup

Policy files live in `selinux/*.cil` and are installed via the Containerfile:

```text
COPY selinux/file1.cil selinux/file2.cil /tmp/
RUN semodule -i /tmp/file1.cil /tmp/file2.cil && rm /tmp/file1.cil /tmp/file2.cil
```

**When adding a new `.cil` file**, always update both the `COPY` line and the `semodule -i`
invocation in the Containerfile. Forgetting either means the policy doesn't get built into the
image.

## CIL Syntax

The fundamental rule form:

```text
(allow SOURCE_TYPE TARGET_TYPE (CLASS (PERMISSIONS...)))
```

Comments use `;`. Multiple permissions go space-separated inside the inner list.

**Common types in this project:**

| Type | What it represents |
|---|---|
| `init_t` | systemd / system services |
| `container_t` | Rootless Podman containers (quadlets) |
| `unconfined_service_t` | Unconfined services (e.g., systemd-age-creds socket) |
| `tun_tap_device_t` | `/dev/net/tun` |

**Common classes and their typical permissions:**

| Class | Common permissions |
|---|---|
| `unix_stream_socket` | `connectto`, `read`, `write` |
| `chr_file` | `getattr`, `open`, `read`, `write`, `ioctl` |
| `file` | `getattr`, `open`, `read`, `write`, `create`, `unlink` |
| `dir` | `getattr`, `open`, `read`, `search`, `write`, `add_name` |
| `process` | `transition`, `signal` |

## Existing Policies (Examples)

### `selinux/systemd_age_creds.cil`

```text
(allow init_t unconfined_service_t (unix_stream_socket (connectto)))
```

Allows systemd (`init_t`) to connect to the systemd-age-creds UNIX socket (`unconfined_service_t`).

### `selinux/container_tun.cil`

```text
; Allow containers (rootless Podman, container_t) to access /dev/net/tun (tun_tap_device_t).
; Required for Gluetun (WireGuard VPN) running as a rootless quadlet.
; Permissions captured from AVC denials:
;   avc: denied { read write }  tclass=chr_file (enforcing)
;   avc: denied { open getattr } tclass=chr_file (permissive run)
; ioctl is included for WireGuard TUNSETIFF/TUNSETFLAGS calls.
(allow container_t tun_tap_device_t (chr_file (getattr open read write ioctl)))
```

## Workflow: New Policy from AVC Denial

### 1. Collect AVC denials

Read from the VM's audit log:

```bash
vsh "sudo ausearch -m avc -ts recent 2>/dev/null || sudo journalctl -k --grep='avc:' -n 50"
```

Tip: if multiple rules will be needed, boot in permissive mode first (`enforcing=0` kernel arg)
to collect all denials in one pass, then write them all before switching back to enforcing.

### 2. Parse the denial

A typical AVC message:

```text
avc: denied { read write } for pid=1234 comm="process" name="device"
     scontext=system_u:system_r:init_t:s0
     tcontext=system_u:object_r:tun_tap_device_t:s0 tclass=chr_file permissive=0
```

Extract:

- **Source type** (`stype`): from `scontext=...:TYPE:...` → `init_t`
- **Target type** (`ttype`): from `tcontext=...:TYPE:...` → `tun_tap_device_t`
- **Class**: from `tclass=` → `chr_file`
- **Permissions**: from `{ ... }` → `read write`

### 3. Write the CIL file

Name it descriptively (e.g., `selinux/container_tun.cil`). Always include a comment block
explaining the why, not just the what — this makes future debugging much easier:

```text
; Allow SOURCE to ACCESS TARGET.
; Required for SERVICE because REASON.
; Permissions captured from AVC denials:
;   avc: denied { PERMS } tclass=CLASS
(allow SOURCE_T TARGET_T (CLASS (PERM1 PERM2 ...)))
```

### 4. Update the Containerfile

The `COPY` and `RUN semodule -i` lines must stay in sync:

```diff
-COPY selinux/existing.cil /tmp/
-RUN semodule -i /tmp/existing.cil && rm /tmp/existing.cil
+COPY selinux/existing.cil selinux/new_policy.cil /tmp/
+RUN semodule -i /tmp/existing.cil /tmp/new_policy.cil && rm /tmp/existing.cil /tmp/new_policy.cil
```

### 5. Build and verify

```bash
make await-ghcr vm-switch       # rolling upgrade if no /var/ changes
# or for a clean slate:
make await-ghcr clean run-vm-from-ghcr

# Check for remaining denials after the upgrade:
vsh "sudo ausearch -m avc -ts recent 2>/dev/null | grep denied | head -20"
```

## Tips

- **Minimal permissions**: only allow what the AVC denial actually asked for. Don't speculatively
  add extras — if they're needed, a new denial will tell you.
- **Group related rules**: multiple permissions for the same source/target/class belong in one
  `allow` rule with all permissions listed together.
- **Multiple rules per file**: a single `.cil` file can contain many rules. Group by service or
  domain (e.g., all `container_t` rules together in one file).
- **`audit2allow`** can translate denials to TE (Type Enforcement) syntax as a starting point,
  but you'll need to convert to CIL manually. The CIL form is usually simpler.
- **Unknown types**: if a type isn't recognized by `semodule`, it may not exist on the running
  system. Use `seinfo -t | grep partial_name` on the VM to look it up.
