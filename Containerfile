# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# renovate: datasource=github-releases depName=sigstore/cosign extractVersion=^v(?<version>.*)$
ARG COSIGN_VERSION=3.0.4

# Install dependencies
RUN curl -LO https://github.com/abyrne55/systemd-age-creds/releases/download/v1.4.4/systemd-age-creds-1.4.4-1.aarch64.rpm && \
    echo "55e1c7a8f2655ee489ac012c3c2b00ed3269910e5a0669417a0606e1658d5586  systemd-age-creds-1.4.4-1.aarch64.rpm" | sha256sum -c && \
    curl -fLO --proto =https https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-${COSIGN_VERSION}-1.aarch64.rpm && \
    curl -sfL --proto =https https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign_checksums.txt | grep "cosign-${COSIGN_VERSION}-1.aarch64.rpm" | sha256sum -c && \
    dnf -y --setopt=install_weak_deps=False install jq age git firewalld sqlite nfs-utils wireguard-tools greenboot prometheus-podman-exporter ./systemd-age-creds-*.rpm ./cosign-*.rpm && \
    dnf clean all && \
    rm -rf /var/cache/*dnf* /var/cache/ldconfig/* /var/lib/dnf /var/log/dnf*.log systemd-age-creds-*.rpm cosign-*.rpm

COPY etc/ /etc/
COPY usr/ /usr/

# Copy SELinux policy
COPY selinux/systemd_age_creds.cil selinux/container_tun.cil /tmp/
RUN semodule -i /tmp/systemd_age_creds.cil /tmp/container_tun.cil && rm /tmp/systemd_age_creds.cil /tmp/container_tun.cil

# Enable services and suppress upstream services that don't apply to our setup:
# - bootloader-update.service: bootupd is not installed in our image so this always fails
# - rpm-ostree-fix-shadow-mode.service: pre-create its stamp file so it knows the fix is
#   already applied; with transient /etc the stamp would otherwise be reset every boot
RUN systemctl enable firewalld podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-content-dirs.service boot.mount boot-efi.mount var-mnt-data.mount homelab-secrets-sync.service homelab-secrets-sync.timer homelab-config-sync.service homelab-config-sync.timer systemd-age-creds.socket wg-nas.service greenboot-healthcheck.service greenboot-set-rollback-trigger.service && \
    systemctl mask bootloader-update.service && \
    touch /etc/.rpm-ostree-shadow-mode-fixed2.stamp

# Lint (TODO: reenable --fatal-warnings)
RUN bootc container lint --no-truncate

# Enable transient /etc (reset on every boot, config comes from image)
RUN mkdir -p /usr/lib/ostree && \
    echo -e '[etc]\ntransient = true' >> /usr/lib/ostree/prepare-root.conf && \
    kver=$(cd /usr/lib/modules && echo *) && \
    dracut -f /usr/lib/modules/$kver/initramfs.img $kver

# It's recommended for bootc containers to set CMD /sbin/init
CMD ["/sbin/init"]
