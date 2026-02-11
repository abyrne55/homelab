# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# Install dependencies
RUN curl -LO https://github.com/abyrne55/systemd-age-creds/releases/download/v1.4.4/systemd-age-creds-1.4.4-1.aarch64.rpm && \
    curl -LO https://github.com/sigstore/cosign/releases/download/v3.0.4/cosign-3.0.4-1.aarch64.rpm && \
    dnf -y install jq age git firewalld ./systemd-age-creds-*.rpm ./cosign-*.rpm && \
    dnf clean all && \
    rm -f /var/cache/dnf systemd-age-creds-*.rpm cosign-*.rpm

# Create mount point for external data volume
RUN rm -rf /mnt && \
    mkdir -p /var/mnt/media

# Copy systemd-sysusers and tmpfiles.d configurations
# Users/groups created at boot by systemd-sysusers.service
# Home directories created at boot by systemd-tmpfiles-setup.service
COPY sysusers/*.conf /usr/lib/sysusers.d/
COPY tmpfiles/*.conf /usr/lib/tmpfiles.d/

# Pre-create Caddy configuration directory at build time
# (Needed because we COPY Caddyfile before users exist at boot)
RUN mkdir -p /var/home/caddy/caddy_etc

# Copy Caddy configuration and set ownership by numeric UID
# (User 'caddy' doesn't exist at build time, created at boot)
# (Permissions are set by tmpfiles.d/quadlet-users-homedirs.conf at boot)
COPY caddy/rootless-hello.Caddyfile /var/home/caddy/caddy_etc/Caddyfile
RUN chown -R 1051:1051 /var/home/caddy/caddy_etc

# Copy quadlets (container definitions) - exclude rootless directory
COPY quadlets/*.container /usr/share/containers/systemd/

# Create directories and copy rootless quadlets
RUN mkdir -p /etc/containers/systemd/users/1001 /etc/containers/systemd/users/1002 /etc/containers/systemd/users/1051 /etc/containers/systemd/users/1052
COPY quadlets/rootless/testuser/ /etc/containers/systemd/users/1001/
COPY quadlets/rootless/testuser2/ /etc/containers/systemd/users/1002/
COPY quadlets/rootless/caddy/caddy.container /etc/containers/systemd/users/1051/
COPY quadlets/rootless/jellyfin/ /etc/containers/systemd/users/1052/

# Copy systemd services and SELinux policy
COPY systemd/ /etc/systemd/system
COPY selinux/systemd_age_creds.cil /tmp/systemd_age_creds.cil
RUN semodule -i /tmp/systemd_age_creds.cil && rm /tmp/systemd_age_creds.cil

# Copy firewalld configuration files
COPY firewalld/firewalld.conf /etc/firewalld/firewalld.conf
COPY firewalld/zones/public.xml /etc/firewalld/zones/public.xml

# Enable services
RUN systemctl enable firewalld podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-data-disk.service var-mnt-media.mount demo-media.service github-known-hosts.service homelab-secrets-sync.service homelab-secrets-sync.timer systemd-age-creds.socket test-systemd-age-creds.service
