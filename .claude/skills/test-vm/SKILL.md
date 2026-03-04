---
name: test-vm
description: Tests changes using the running homelab VM. Use this skill when testing a new service or troubleshooting something (e.g., a service isn't starting, a container is unhealthy, the VM behaves unexpectedly, or the user asks to investigate an error on the VM). Triggered via /test-vm [service-name or symptom].
argument-hint: [service-name or symptom]
---

# Test VM: $ARGUMENTS

Work through these steps in order. Stop when you've confirmed the target service is working or if you've identified the root cause of any issues.

```text
Triage: $ARGUMENTS
- [ ] 1. Check for failed units
- [ ] 2. Check service status and recent logs
- [ ] 3. Check container health
- [ ] 4. Check systemd journal for boot-time errors
- [ ] 5. Check specific unit's full journal
- [ ] 6. Inspect container directly
- [ ] 7. Check credentials
```

## 1. Check for any failed units

```bash
vsh hl failed
```

This lists failed units across both system and all service users. If something is unexpectedly failed, start there.

## 2. Check service status and recent logs

```bash
vsh hl status $ARGUMENTS
vsh hl logs $ARGUMENTS -n 50
```

For system units (not quadlets):

```bash
vsh hl status -s $ARGUMENTS
vsh hl logs -s $ARGUMENTS -n 50
```

## 3. Check container health

```bash
vsh hl ps
```

Look for containers with non-`healthy` status. A container stuck in `starting` may have a failing `HealthCmd`.

## 4. Check the systemd journal for boot-time errors

```bash
vsh "sudo journalctl -b -p err --no-pager | tail -40"
```

## 5. Check a specific unit's full journal

`--user-unit` doesn't work on this system; `hl logs` uses journal field matching instead:

```bash
vsh hl logs $ARGUMENTS -n 200
```

For system units:

```bash
vsh hl logs -s $ARGUMENTS -n 200
```

## 6. Inspect a container directly

`machinectl` is not installed. Use `hl ps` to list containers, then `hl sudo` to exec into one:

```bash
vsh hl ps -u $ARGUMENTS
vsh "hl sudo $ARGUMENTS -- <cmd>"                          # exec into container
vsh "hl sudo -u $ARGUMENTS <container> -- <cmd>"           # exec (explicit user)
# For podman commands other than exec (e.g. logs, inspect):
vsh "sudo su - $ARGUMENTS -s /bin/sh -c 'XDG_RUNTIME_DIR=/run/user/\$(id -u) podman logs <container-name>'"
```

## 7. Check credentials (if service uses age-encrypted secrets)

Check that secrets were synced and the socket is decrypting correctly:

```bash
vsh hl logs -s homelab-secrets-sync -n 30
vsh hl logs -s systemd-age-creds -n 30
vsh "ls /run/credentials/"
```

The `systemd-age-creds` log shows each credential request (service name, UID, credential name) — use this to confirm whether the failing service ever successfully requested its credential, and whether decryption succeeded or failed.

---

## Raw SSH fallback (if `vsh` is unavailable)

```bash
ssh -i ./secrets/core/id_ed25519 -p 2222 \
  -o LogLevel=QUIET \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  core@127.0.0.1 -- "<your command here>"
```

## Common patterns

- **`statfs /var/mnt/data/.<service>/config: no such file or directory`** → data disk config dir not created; `init-data-disk.service` only runs on fresh disk init. Fix: `sudo mkdir -p /var/mnt/data/.<service>/config && sudo chown -R <uid>:<uid> /var/mnt/data/.<service>`, then `hl restart <service>`
- **Service fails immediately at boot** → likely a missing config file or credential; check `ConditionPathExists` guards and secrets sync logs
- **Container unhealthy but running** → `HealthCmd` is failing; check the command manually inside the container
- **Unit not found** → quadlet may not have been picked up; check file is in `etc/containers/systemd/users/<uid>/` with `.container` extension
- **Port conflict** → check `hl ps` for duplicate port bindings; verify allocation table in CLAUDE.md

## Additional References

If the above steps don't resolve the issue, these docs may help diagnose further:

- `.claude/references/podman/troubleshooting.md` — indexed list of common Podman errors with solutions: permission denials (§2, §7), rootless namespace issues (§9, §10, §19, §35), networking (§4, §30), UID/GID mapping (§34, §35)
- `.claude/references/fedora-bootc/debugging-toolbx.md` — how to use a `toolbox` container to access diagnostic tools not installed in the bootc image
