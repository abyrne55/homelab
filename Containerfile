# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# Install dependencies
RUN curl -LO https://github.com/abyrne55/systemd-age-creds/releases/download/v1.4.4/systemd-age-creds-1.4.4-1.aarch64.rpm && \
    dnf -y install age git firewalld ./systemd-age-creds-*.rpm && \
    dnf clean all && \
    rm -f /var/cache/dnf systemd-age-creds-*.rpm

# Create mount point for external data volume and systemd-age-creds group
RUN rm -rf /mnt && \
    mkdir -p /mnt/media && \
    groupadd -r systemd-age-creds-users

# Create test users and configure for rootless podman
RUN useradd -u 1001 -m -d /var/home/testuser -s /sbin/nologin -c "Rootless quadlet test user" -G systemd-age-creds-users testuser && \
    useradd -u 1002 -m -d /var/home/testuser2 -s /sbin/nologin -c "Second rootless quadlet test user" -G systemd-age-creds-users testuser2 && \
    useradd -u 1051 -m -d /var/home/caddy -s /sbin/nologin -c "Caddy web server" -G systemd-age-creds-users caddy && \
    mkdir -p /var/home/testuser/.local/share/containers /var/home/testuser/.config/containers && \
    mkdir -p /var/home/testuser2/.local/share/containers /var/home/testuser2/.config/containers && \
    mkdir -p /var/home/caddy/.local/share/containers /var/home/caddy/.config/containers /var/home/caddy/caddy_etc && \
    chown -R testuser:testuser /var/home/testuser && \
    chown -R testuser2:testuser2 /var/home/testuser2 && \
    chown -R caddy:caddy /var/home/caddy && \
    mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/testuser /var/lib/systemd/linger/testuser2 /var/lib/systemd/linger/caddy

# Copy Caddy configuration
COPY caddy/Caddyfile /etc/caddy/Caddyfile
COPY caddy/rootless-hello.Caddyfile /var/home/caddy/caddy_etc/Caddyfile
RUN chown caddy:caddy /var/home/caddy/caddy_etc/Caddyfile

# Copy quadlets (container definitions)
COPY quadlets/ /usr/share/containers/systemd

# Create directories and copy rootless quadlets
RUN mkdir -p /etc/containers/systemd/users/1001 /etc/containers/systemd/users/1002 /etc/containers/systemd/users/1051
COPY quadlets/rootless/testuser/ /etc/containers/systemd/users/1001/
COPY quadlets/rootless/testuser2/ /etc/containers/systemd/users/1002/
COPY quadlets/rootless/caddy/caddy.container /etc/containers/systemd/users/1051/
COPY quadlets/rootless/caddy/caddy.socket /usr/lib/systemd/user/

# Copy systemd services and SELinux policy
COPY systemd/ /etc/systemd/system
COPY selinux/systemd_age_creds.cil /tmp/systemd_age_creds.cil
RUN semodule -i /tmp/systemd_age_creds.cil && rm /tmp/systemd_age_creds.cil

# Copy firewalld configuration files
COPY firewalld/firewalld.conf /etc/firewalld/firewalld.conf
COPY firewalld/zones/public.xml /etc/firewalld/zones/public.xml

# Enable services
RUN systemctl enable firewalld podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-data-disk.service mnt-media.mount demo-media.service github-known-hosts.service homelab-secrets-sync.service homelab-secrets-sync.timer systemd-age-creds.socket test-systemd-age-creds.service && \
    systemctl --global enable caddy.socket
