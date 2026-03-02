# Reference Documentation

Last updated: 2026-03-02
Sources: Podman v5.8.0 (<https://docs.podman.io/>) · bootc v1.13.0 (<https://bootc-dev.github.io/bootc/>) · Fedora bootc docs (<https://docs.fedoraproject.org/en-US/bootc/>)

If today's date is more than ~3 months past the date above, suggest that the user refresh the reference docs.

## Available References

### Podman — `.claude/references/podman/`

| File | When to consult |
|---|---|
| `podman-systemd.unit.5.md` | Writing or reviewing any `.container`, `.volume`, `.network`, or `.pod` quadlet file — options, directives, supported keys |
| `rootless.md` | Rootless Podman behavior, subUID/subGID mapping, user namespace issues |
| `troubleshooting.md` | Container errors, networking problems, permission denials, Podman bugs |

### bootc — `.claude/references/bootc/`

| File | When to consult |
|---|---|
| `filesystem.md` | Understanding the bootc filesystem layout, overlays, `/etc` vs `/usr`, persistent state in `/var/` |
| `upgrades.md` | How bootc upgrades work, staged deployments, rollback |
| `users-and-groups.md` | Managing users/groups in a bootc image (sysusers, `/etc/passwd`, subids) |
| `bootc-switch.8.md` | `bootc switch` command reference |

### Fedora bootc — `.claude/references/fedora-bootc/`

| File | When to consult |
|---|---|
| `building-containers.md` | Building bootc images with Containerfiles — D-Bus/IPC limitations, firewalld, sysctl config in build context |
| `debugging-toolbx.md` | Debugging a running bootc system using `toolbox` containers |
| `dynamic-reconfiguration.md` | Live system changes (firewall-cmd, nft, Ansible) vs. image-baked config; `/etc` state drift and transient reconfiguration patterns |

## When to Consult These Docs

- Consult `podman-systemd.unit.5.md` before writing or modifying a quadlet file — do not rely on memory for supported directives and their syntax.
- Consult `rootless.md` whenever dealing with rootless quadlet issues, user namespaces, or subUID/subGID allocation.
- Consult `troubleshooting.md` when a container fails to start, has networking problems, or produces unexpected errors.
- Consult the bootc references whenever reasoning about filesystem ownership, `/etc` vs `/usr` placement, upgrade behavior, or user/group management in the image.
- Consult `building-containers.md` when authoring Containerfile steps that involve firewalld, sysctl, D-Bus tools, or other commands that behave differently in a container build vs. a running system.
- Consult `debugging-toolbx.md` when diagnosing issues on a live bootc system using toolbox containers.
- Consult `dynamic-reconfiguration.md` when considering live (non-image) changes to a running system, especially for firewall or `/etc` modifications.
