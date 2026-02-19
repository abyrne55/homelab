# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:43

# Install dependencies
RUN curl -LO https://github.com/abyrne55/systemd-age-creds/releases/download/v1.4.4/systemd-age-creds-1.4.4-1.aarch64.rpm && \
    curl -LO https://github.com/sigstore/cosign/releases/download/v3.0.4/cosign-3.0.4-1.aarch64.rpm && \
    dnf -y install jq age git firewalld sqlite ./systemd-age-creds-*.rpm ./cosign-*.rpm && \
    dnf clean all && \
    rm -rf /var/cache/*dnf* /var/cache/ldconfig/* /var/lib/dnf /var/log/dnf*.log systemd-age-creds-*.rpm cosign-*.rpm

COPY etc/ /etc/
COPY usr/ /usr/

# Copy SELinux policy
COPY selinux/systemd_age_creds.cil /tmp/systemd_age_creds.cil
RUN semodule -i /tmp/systemd_age_creds.cil && rm /tmp/systemd_age_creds.cil

# Enable services
RUN systemctl enable firewalld podman-auto-update.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-data-disk.service boot.mount boot-efi.mount var-mnt-media.mount demo-media.service homelab-secrets-sync.service homelab-secrets-sync.timer systemd-age-creds.socket test-systemd-age-creds.service

# Enable user-level units for the jellyfin user session
RUN systemctl --global enable jellarr-bootstrap.service jellarr.timer

# Suppress upstream services that don't apply to our setup:
# - bootloader-update.service: bootupd is not installed in our image so this always fails
# - rpm-ostree-fix-shadow-mode.service: pre-create its stamp file so it knows the fix is
#   already applied; with transient /etc the stamp would otherwise be reset every boot
RUN systemctl mask bootloader-update.service && \
    touch /etc/.rpm-ostree-shadow-mode-fixed2.stamp

# Lint (TODO: reenable --fatal-warnings)
RUN bootc container lint --no-truncate

# Enable transient /etc (reset on every boot, config comes from image)
RUN mkdir -p /usr/lib/ostree && \
    echo -e '[etc]\ntransient = true' >> /usr/lib/ostree/prepare-root.conf && \
    kver=$(cd /usr/lib/modules && echo *) && \
    dracut -vf /usr/lib/modules/$kver/initramfs.img $kver

# It's recommended for bootc containers to set CMD /sbin/init
CMD ["/sbin/init"]
