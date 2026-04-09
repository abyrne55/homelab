---
name: add-quadlet
description: Adds a new rootless quadlet service to the homelab stack. Use this skill whenever adding a new service, container, or quadlet to the homelab — even if the user just says "add X" or "set up X as a service". Covers the full checklist: sysusers, homedirs, linger, subids, quadlet file, Caddy routing, and allocation table update.
argument-hint: [service-name]
---

# Add Quadlet: $ARGUMENTS

Read the service user allocations table in CLAUDE.md to pick the next available UID/port/subUID slot before starting.

Copy this checklist and check off each step as you complete it:

```text
Add Quadlet: $ARGUMENTS
- [ ] 1. sysusers.d entry
- [ ] 2. homedirs tmpfiles entry
- [ ] 3. linger tmpfiles entry
- [ ] 4. subids tmpfiles entry
- [ ] 5. .container quadlet file
- [ ] 6. service-state-dirs.conf entry (for /var/local/lib/<service>/ state dir)
- [ ] 7. Caddy route in homelab-config
- [ ] 8. Greenboot wanted.d check script
- [ ] 9. Allocations table updated in CLAUDE.md
- [ ] 10. prometheus-podman-exporter wired up
```

## 1. `usr/lib/sysusers.d/<N>-<name>-user.conf`

Define the user with a fixed UID and home directory. Add to `systemd-age-creds-users` group if the service needs credentials:

```text
u $ARGUMENTS <UID> "<Display Name>" /var/home/$ARGUMENTS /sbin/nologin
m $ARGUMENTS systemd-age-creds-users
```

## 2. `usr/lib/tmpfiles.d/quadlet-users-homedirs.conf`

Append the home directory and Podman subdirectory tree that rootless Podman requires:

```text
d /var/home/$ARGUMENTS 0750 $ARGUMENTS $ARGUMENTS - -
d /var/home/$ARGUMENTS/.local 0755 $ARGUMENTS $ARGUMENTS - -
d /var/home/$ARGUMENTS/.local/share 0755 $ARGUMENTS $ARGUMENTS - -
d /var/home/$ARGUMENTS/.local/share/containers 0755 $ARGUMENTS $ARGUMENTS - -
d /var/home/$ARGUMENTS/.config 0755 $ARGUMENTS $ARGUMENTS - -
d /var/home/$ARGUMENTS/.config/containers 0755 $ARGUMENTS $ARGUMENTS - -
```

## 3. `usr/lib/tmpfiles.d/quadlet-users-linger.conf`

Append one line to enable linger (starts the user's services at boot without a login session):

```text
f /var/lib/systemd/linger/$ARGUMENTS 0644 root root - -
```

## 4. `usr/lib/tmpfiles.d/quadlet-users-subids.conf`

Append the new user's subUID/subGID range to **both** the `subuid` and `subgid` write directives. Each user gets 65536 IDs; start after the last allocated range end (see allocations table in CLAUDE.md).

## 5. Create `etc/containers/systemd/users/<uid>/<name>.container`

Podman quadlet format. Apply the baseline hardening directives from the `/hardening` skill.

For credential access, use the hardcoded `/run/` path — **not** `%t/`. In user units, `%t` expands to `/run/user/<uid>`, not `/run`, so the credentials socket path would be wrong:

```ini
[Service]
LoadCredential=credential-name:/run/systemd-age-creds.sock
```

## 6. Add service state directory to `service-state-dirs.conf`

**File:** `usr/lib/tmpfiles.d/service-state-dirs.conf`

Service state (config DB, cache, app data) lives in `/var/local/lib/<service>/` — local disk, always available. Add a `d` entry:

```text
d /var/local/lib/$ARGUMENTS 0750 <uid> <uid> - -
```

This is created at every boot by systemd-tmpfiles before any services start.

If the service also needs to write to the NFS content share (`/var/mnt/data/`), add its content directories to `init-content-dirs.service` instead. That service only runs after the NFS mount is up, and uses `chmod 0777` (NFS does UID passthrough so `chown` is not applicable):

```ini
ExecStart=/usr/bin/mkdir -p \
  /var/mnt/data/content/$ARGUMENTS
ExecStart=/usr/bin/chmod 0777 /var/mnt/data/content/$ARGUMENTS
```

> **Note:** For an existing test VM, manually create the state dir:
>
> ```bash
> sudo mkdir -p /var/local/lib/$ARGUMENTS && sudo chown -R <uid>:<uid> /var/local/lib/$ARGUMENTS
> ```

## 7. Add a Caddy route (in homelab-config)

In the private `homelab-config` repo, add a block to the `Caddyfile` using the `(proxy)` snippet:

```caddy
# $ARGUMENTS
$ARGUMENTS.yourdomain.example {
    import proxy <host-port>
}
```

Do **not** open the service port in `etc/firewalld/zones/public.xml` — all external HTTP/HTTPS flows through Caddy on ports 20510/20511 only.

## Additional References

If in doubt about a directive or behavior, these docs may help:

- `.claude/references/podman/podman-systemd.unit.5.md` (lines 291–1031) — complete [Container] directive listing with podman-run equivalents and detailed descriptions
- `.claude/references/podman/rootless.md` — rootless Podman behavior, user namespaces, subUID/subGID semantics
- `.claude/references/bootc/users-and-groups.md` — sysusers.d patterns, subid allocation, user/group management in a bootc image
- `.claude/references/bootc/filesystem.md` (lines 114–154) — `/var/` layout and persistent state patterns (home directories, data mounts)

## 8. Add a greenboot health check (`usr/lib/greenboot/check/wanted.d/30-<name>.sh`)

All quadlet services get a `wanted.d` check (non-fatal — failure warns but won't trigger rollback). Use `systemctl --user -M` with a retry loop to handle transient D-Bus errors at boot:

```bash
#!/usr/bin/bash
set -euo pipefail
for _ in 1 2 3; do
    state=$(systemctl --user -M $ARGUMENTS@.host show $ARGUMENTS.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: $ARGUMENTS.service is not active (state='${state}')"
    exit 1
fi
echo "OK: $ARGUMENTS.service is active"
```

Mark it executable (`chmod +x`) — git preserves the bit, no Containerfile step needed.

**Do NOT use `podman --root/--runroot` as root** to check container health — it conflicts with the user session's libpod runtime dir and will restart running containers.

**Do NOT add to `required.d`** unless the service is as critical as secrets-sync, config-sync, or caddy. Required checks trigger rollback on failure.

## 9. Update the allocations table in CLAUDE.md

Update the service user allocations table to reflect the new user and advance the "next slot" row (UID, port, subUID range start).

**Port assignment formula:** `2<last 3 digits of UID><index>` — e.g. UID 1054 → host ports 20540, 20541, … All ports stay in 20000–29999 (below the Linux ephemeral port floor of 32768).

**New system unit only:** If adding a system-level unit (not a quadlet), also append it to the `RUN systemctl enable` line in `Containerfile`. Quadlets are auto-discovered and do not need to be listed there.

## 10. Wire up prometheus-podman-exporter

Each service user gets a `prometheus-podman-exporter` sidecar that exposes Podman metrics on a localhost-only port. Three files need updating:

### `usr/lib/tmpfiles.d/prometheus-podman-exporter-configs.conf`

Append one line for the new user. The port is the X9 port (last in the user's 10-port block — see allocations table):

```text
f /var/home/$ARGUMENTS/.config/prometheus-podman-exporter  0600 $ARGUMENTS  $ARGUMENTS  - PODMAN_EXPORTER_OPTS=--collector.enable-all --web.listen-address=127.0.0.1:<UID_X9_PORT>
```

The `f` type creates the file only if it doesn't already exist, so it won't overwrite any manually edited config on a live system.

### `usr/lib/systemd/user/prometheus-podman-exporter.service.d/10-homelab.conf`

Add the new container service name(s) to the `After=` line so the exporter starts after the user's containers have initialized libpod's rootless pause process:

```ini
After=... $ARGUMENTS.service
```

### Netdata scrape config (in homelab-config)

Add the new exporter endpoint to the Netdata Prometheus scrape config in the private `homelab-config` repo so metrics are actually collected.
