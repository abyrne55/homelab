# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# Install dependencies
RUN curl -LO https://github.com/abyrne55/systemd-age-creds/releases/download/v1.4.3/systemd-age-creds-1.4.3-1.aarch64.rpm && \
    dnf -y install age git ./systemd-age-creds-*.rpm && \
    dnf clean all && \
    rm -f /var/cache/dnf systemd-age-creds-*.rpm

# Create mount point for external data volume
RUN rm -rf /mnt && mkdir -p /mnt/media

# Create group for systemd-age-creds socket access
RUN groupadd -r systemd-age-creds-users

# Create test user for rootless quadlet testing
RUN useradd -r -u 1001 -m -d /var/home/testuser -s /sbin/nologin -c "Rootless quadlet test user" -G systemd-age-creds-users testuser

# Create required directories for rootless podman
RUN mkdir -p /var/home/testuser/.local/share/containers /var/home/testuser/.config/containers && \
    chown -R testuser:testuser /var/home/testuser

# Configure subuid/subgid ranges for rootless containers
RUN echo "testuser:100000:65536" >> /etc/subuid && \
    echo "testuser:100000:65536" >> /etc/subgid

# Enable lingering for testuser to allow user services to run without login
RUN mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/testuser

# Copy Caddy configuration
COPY caddy/Caddyfile /etc/caddy/Caddyfile

# Copy quadlets (container definitions)
COPY quadlets/ /usr/share/containers/systemd

# Copy rootless quadlets for testuser (UID 1001)
RUN mkdir -p /etc/containers/systemd/users/1001
COPY quadlets/rootless/ /etc/containers/systemd/users/1001/

# Copy systemd services
COPY systemd/ /etc/systemd/system

# Install SELinux policy for systemd-age-creds
COPY selinux/systemd_age_creds.cil /tmp/
RUN semodule -i /tmp/systemd_age_creds.cil && rm /tmp/systemd_age_creds.cil

# Enable services
RUN systemctl enable podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-data-disk.service mnt-media.mount demo-media.service github-known-hosts.service homelab-secrets-sync.service homelab-secrets-sync.timer systemd-age-creds.socket test-systemd-age-creds.service
