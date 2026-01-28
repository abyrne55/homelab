# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# Create mount point for external data volume
RUN rm -rf /mnt && mkdir -p /mnt/media

# Copy quadlets (container definitions)
COPY quadlets/ /usr/share/containers/systemd

# Copy systemd services
COPY systemd/ /etc/systemd/system

# Copy Caddy configuration
COPY caddy/Caddyfile /etc/caddy/Caddyfile

# Install dependencies
RUN dnf -y install age git

# Enable services
RUN systemctl enable podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-data-disk.service mnt-media.mount demo-media.service systemd-age-creds.socket github-known-hosts.service homelab-secrets-sync.service homelab-secrets-sync.timer
