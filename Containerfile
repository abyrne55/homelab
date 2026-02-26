# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# Install dependencies
RUN curl -LO https://github.com/abyrne55/systemd-age-creds/releases/download/v1.4.4/systemd-age-creds-1.4.4-1.aarch64.rpm && \
    curl -LO https://github.com/sigstore/cosign/releases/download/v3.0.4/cosign-3.0.4-1.aarch64.rpm && \
    dnf -y install --nodocs --setopt=install_weak_deps=False jq age git firewalld sqlite ./systemd-age-creds-*.rpm ./cosign-*.rpm && \
    dnf clean all && \
    rm -rf /var/cache/*dnf* /var/cache/ldconfig/* /var/lib/dnf /var/log/dnf*.log systemd-age-creds-*.rpm cosign-*.rpm

COPY etc/ /etc/
COPY usr/ /usr/
COPY selinux/systemd_age_creds.cil selinux/container_tun.cil /tmp/

# Configure system: fix permissions, load SELinux policy, enable services, and rebuild initramfs
RUN chmod +x /usr/local/bin/qbittorrent-configure && \
    semodule -i /tmp/systemd_age_creds.cil /tmp/container_tun.cil && \
    rm /tmp/systemd_age_creds.cil /tmp/container_tun.cil && \
    systemctl enable firewalld podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-data-disk.service boot.mount boot-efi.mount var-mnt-data.mount demo-media.service homelab-secrets-sync.service homelab-secrets-sync.timer homelab-config-sync.service homelab-config-sync.timer systemd-age-creds.socket test-systemd-age-creds.service && \
    systemctl --global enable jellarr-bootstrap.service jellarr.timer && \
    systemctl mask bootloader-update.service && \
    touch /etc/.rpm-ostree-shadow-mode-fixed2.stamp && \
    mkdir -p /usr/lib/ostree && \
    echo -e '[etc]\ntransient = true' >> /usr/lib/ostree/prepare-root.conf && \
    kver=$(cd /usr/lib/modules && echo *) && \
    dracut -f /usr/lib/modules/$kver/initramfs.img $kver

# Lint (TODO: reenable --fatal-warnings)
RUN bootc container lint --no-truncate

# It's recommended for bootc containers to set CMD /sbin/init
CMD ["/sbin/init"]
