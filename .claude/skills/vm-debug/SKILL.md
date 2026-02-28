---
name: vm-debug
description: Diagnoses and debugs failures on the running homelab VM. Use this skill when a service isn't starting, a container is unhealthy, the VM behaves unexpectedly, or the user asks to investigate an error on the VM. Triggered via /vm-debug [service-name or symptom].
argument-hint: [service-name or symptom]
---

# VM Debug: $ARGUMENTS

Work through these steps in order. Stop when you've identified the root cause.

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

`machinectl` is not installed. Use `hl ps` to list containers, then `sudo su -` to run podman commands as the service user:

```bash
vsh hl ps -u $ARGUMENTS
vsh "sudo su - $ARGUMENTS -s /bin/sh -c 'XDG_RUNTIME_DIR=/run/user/\$(id -u) podman logs <container-name>'"
```

## 7. Check credentials (if service uses age-encrypted secrets)

```bash
vsh hl logs -s homelab-secrets-sync -n 30
vsh "ls /run/credentials/"
```

---

## Raw SSH fallback (if `vsh` is unavailable)

```bash
ssh -i ./secrets/core/id_ed25519 -p 2222 \
  -o LogLevel=QUIET \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  core@127.0.0.1 -- "<your command here>" || true
```

Append `|| true` when running parallel tool calls to prevent a non-zero exit from cancelling sibling calls.

## Common patterns

- **Service fails immediately at boot** → likely a missing config file or credential; check `ConditionPathExists` guards and secrets sync logs
- **Container unhealthy but running** → `HealthCmd` is failing; check the command manually inside the container
- **Unit not found** → quadlet may not have been picked up; check file is in `etc/containers/systemd/users/<uid>/` with `.container` extension
- **Port conflict** → check `hl ps` for duplicate port bindings; verify allocation table in CLAUDE.md
