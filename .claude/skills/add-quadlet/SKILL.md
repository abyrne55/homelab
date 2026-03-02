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
- [ ] 6. Caddy route in homelab-config
- [ ] 7. Allocations table updated in CLAUDE.md
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

## 6. Add a Caddy route (in homelab-config)

In the private `homelab-config` repo, add a hostname-based reverse-proxy block to the `Caddyfile`:

```caddy
$ARGUMENTS.yourdomain.example {
    reverse_proxy host.containers.internal:<host-port>
}
```

Do **not** open the service port in `etc/firewalld/zones/public.xml` — all external HTTP/HTTPS flows through Caddy on ports 20510/20511 only.

## Additional References

If in doubt about a directive or behavior, these docs may help:

- `.claude/references/podman/podman-systemd.unit.5.md` (lines 291–1031) — complete [Container] directive listing with podman-run equivalents and detailed descriptions
- `.claude/references/podman/rootless.md` — rootless Podman behavior, user namespaces, subUID/subGID semantics
- `.claude/references/bootc/users-and-groups.md` — sysusers.d patterns, subid allocation, user/group management in a bootc image
- `.claude/references/bootc/filesystem.md` (lines 114–154) — `/var/` layout and persistent state patterns (home directories, data mounts)

## 7. Update the allocations table in CLAUDE.md

Update the service user allocations table to reflect the new user and advance the "next slot" row (UID, port, subUID range start).

**Port assignment formula:** `2<last 3 digits of UID><index>` — e.g. UID 1054 → host ports 20540, 20541, … All ports stay in 20000–29999 (below the Linux ephemeral port floor of 32768).

**New system unit only:** If adding a system-level unit (not a quadlet), also append it to the `RUN systemctl enable` line in `Containerfile`. Quadlets are auto-discovered and do not need to be listed there.
