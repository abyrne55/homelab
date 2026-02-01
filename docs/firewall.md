# Firewall Configuration

## Overview

The homelab uses **firewalld** with a default-deny policy to secure all network access. Port forwarding enables rootless Caddy to serve HTTP on port 80 while running on unprivileged port 8080.

## Architecture

```
External client → Port 80 → firewalld forward → Port 8080 → Socket activation → Caddy container
```

- **Zone:** `public` with `DROP` target (default deny)
- **Allowed services:** SSH (22)
- **Allowed ports:** 8080/tcp (Caddy), 8096/tcp (Jellyfin)
- **Port forwarding:** 80 → 8080 (transparent redirect)

## Implementation

Firewall rules are defined at build-time in `firewalld/zones/public.xml` and copied during container build, following the bootc immutable OS pattern.

### Key Files

- `firewalld/firewalld.conf` - Main firewalld configuration
- `firewalld/zones/public.xml` - Zone definition with rules and port forwarding
- `Containerfile` - Installs firewalld, copies configs, enables service

### Rootless Caddy Integration

Caddy runs as unprivileged user `caddy` (UID 1051) with:
- Socket activation on port 8080 (`caddy.socket`)
- Container network isolation (`Network=none`)
- On-demand activation (container only runs when traffic arrives)

Port forwarding provides transparent external access on port 80.

## Security Benefits

- **Default deny:** Only explicitly allowed ports are accessible
- **No privileged ports:** Removed system-wide `net.ipv4.ip_unprivileged_port_start` sysctl
- **Rootless services:** All user-facing services run without root privileges
- **Defense-in-depth:** Network isolation + socket activation + firewall

## Port Forwarding Behavior

Firewalld's port forwarding (`forward-port`) only affects traffic received on network interfaces, not localhost-originated traffic.

**Working:**
- External clients → VM port 80 ✅
- Traffic through network interface (enp0s1) ✅

**Not working (expected):**
- Inside VM: `curl http://127.0.0.1:80` ❌
- Localhost traffic bypasses PREROUTING chain

This is normal firewalld behavior. Production deployments receive external traffic, so port forwarding works correctly for real-world use.

## Verification

```bash
# Check firewall status
sudo firewall-cmd --state
sudo firewall-cmd --list-all

# Test external access (from outside VM)
curl http://localhost:80

# Verify Caddy socket
sudo systemctl --user -M caddy@.host status caddy.socket

# Check listening ports
sudo ss -tlnp | grep -E ':(80|8080)'
```

## Adding New Services

To allow a new service through the firewall:

1. Edit `firewalld/zones/public.xml`:
   ```xml
   <port port="9999" protocol="tcp"/>
   ```

2. Rebuild container image:
   ```bash
   make clean && make run-vm
   ```

For port forwarding:
```xml
<forward-port port="443" protocol="tcp" to-port="8443"/>
```

**Note:** Omit `to-addr` when forwarding to the same machine.
