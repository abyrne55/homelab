# Reference Documentation

Last updated: 2026-03-03
Sources: Podman v5.8.0 (<https://docs.podman.io/>) · bootc v1.13.0 (<https://bootc-dev.github.io/bootc/>) · Fedora bootc docs (<https://docs.fedoraproject.org/en-US/bootc/>) · systemd (<https://systemd.io/>)

If today's date is more than ~3 months past the date above, suggest that the user refresh the reference docs.

**Notify the user whenever you consult one of these reference documents** — mention which file(s) you consulted and when it was last updated.

## Available References

### Podman — `.claude/references/podman/`

| File | When to consult |
|---|---|
| `podman-systemd.unit.5.md` | Writing or modifying any `.container`, `.volume`, `.network`, or `.pod` quadlet file — do not rely on memory for supported directives and syntax |
| `rootless.md` | Rootless quadlet issues, user namespaces, subUID/subGID allocation |
| `troubleshooting.md` | Container fails to start, networking problems, permission denials, Podman bugs |

### bootc — `.claude/references/bootc/`

| File | When to consult |
|---|---|
| `filesystem.md` | Filesystem ownership, `/etc` vs `/usr` placement, persistent state in `/var/` |
| `upgrades.md` | Upgrade behavior, staged deployments, rollback |
| `users-and-groups.md` | Managing users/groups in a bootc image (sysusers, `/etc/passwd`, subids) |
| `bootc-switch.8.md` | `bootc switch` command reference |

### Fedora bootc — `.claude/references/fedora-bootc/`

| File | When to consult |
|---|---|
| `building-containers.md` | Containerfile steps involving firewalld, sysctl, D-Bus, or other commands that behave differently in a build vs. a running system |
| `debugging-toolbx.md` | Diagnosing issues on a live bootc system using toolbox containers |
| `dynamic-reconfiguration.md` | Live (non-image) changes to a running system, especially firewall or `/etc` modifications |

### systemd — `.claude/references/systemd/`

| File | When to consult |
|---|---|
| `systemd.exec.5.md` | Writing or reviewing service units — do not rely on memory for execution directives, security options, resource controls, or credential handling |
| `systemd.unit.5.md` | Writing or reviewing unit files — dependencies, ordering, conditions, specifiers, drop-ins, [Unit]/[Install] options |
