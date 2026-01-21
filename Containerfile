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

# Enable services
RUN systemctl enable podman-auto-update.timer \
    && systemctl enable init-data-disk.service \
    && systemctl enable mnt-media.mount \
    && systemctl enable demo-media.service
