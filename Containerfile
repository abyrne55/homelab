# Bootc-based homelab system image
# Uses podman quadlets for container management
# See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

FROM quay.io/fedora/fedora-bootc:44

ARG TARGETARCH

# renovate: datasource=github-releases depName=sigstore/cosign extractVersion=^v(?<version>.*)$
ARG COSIGN_VERSION=3.1.4

# Install dependencies
RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64) RPM_ARCH="x86_64" ;; \
        arm64) RPM_ARCH="aarch64" ;; \
        *)     echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    SAC_VERSION="1.4.5"; \
    curl -fLO "https://github.com/abyrne55/systemd-age-creds/releases/download/v${SAC_VERSION}/systemd-age-creds-${SAC_VERSION}-1.${RPM_ARCH}.rpm" && \
    curl -fL "https://github.com/abyrne55/systemd-age-creds/releases/download/v${SAC_VERSION}/SHA256SUMS" | \
        grep "systemd-age-creds-${SAC_VERSION}-1.${RPM_ARCH}.rpm" | sha256sum -c && \
    curl -fLO --proto =https "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-${COSIGN_VERSION}-1.${RPM_ARCH}.rpm" && \
    curl -sfL --proto =https "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign_checksums.txt" | \
        grep "cosign-${COSIGN_VERSION}-1.${RPM_ARCH}.rpm" | sha256sum -c && \
    dnf -y --setopt=install_weak_deps=False install \
        jq age git firewalld sqlite nfs-utils wireguard-tools greenboot prometheus-podman-exporter qemu-guest-agent restic \
        ./systemd-age-creds-*.rpm ./cosign-*.rpm && \
    dnf clean all && \
    rm -rf /run/dnf /var/cache/*dnf* /var/cache/ldconfig/* /var/lib/dnf /var/log/dnf*.log \
        systemd-age-creds-*.rpm cosign-*.rpm

COPY etc/ /etc/
COPY usr/ /usr/

# Copy SELinux policy
COPY selinux/systemd_age_creds.cil selinux/container_tun.cil selinux/mealie_static_volume.cil /tmp/
# The trailing `semodule -N --refresh` mirrors what ostree runs on every deployment
# at finalize time (after the /etc merge). The first refresh rewrites the compiled
# policy produced by `semodule -i` into a different (but stable) binary, so without
# it the staged image's policy never matches the booted deployment's, and bootc
# refuses `--soft-reboot` on SELinux policy mismatch.
RUN semodule -i /tmp/systemd_age_creds.cil /tmp/container_tun.cil /tmp/mealie_static_volume.cil && \
    semodule -N --refresh && \
    rm /tmp/systemd_age_creds.cil /tmp/container_tun.cil /tmp/mealie_static_volume.cil

# Enable services and suppress upstream services that don't apply to our setup:
# - rpm-ostree-fix-shadow-mode.service: pre-create its stamp file so it knows the fix is
#   already applied; with transient /etc the stamp would otherwise be reset every boot
RUN systemctl enable firewalld podman-image-prune.timer bootc-fetch-apply-updates.timer secrets-inject.service ssh-generate-identity.service age-generate-identity.service init-content-dirs.service boot.mount boot-efi.mount var-mnt-data.mount var-mnt-backup.mount homelab-secrets-sync.service homelab-secrets-sync.timer homelab-config-sync.service homelab-config-sync.timer systemd-age-creds.socket wg-nas.service greenboot-healthcheck.service greenboot-set-rollback-trigger.service qemu-guest-agent.service restic-backup.timer && \
    touch /etc/.rpm-ostree-shadow-mode-fixed2.stamp && \
    ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Lint
RUN bootc container lint --fatal-warnings --no-truncate

# Enable transient /etc (reset on every boot, config comes from image)
# SOURCE_DATE_EPOCH must be exported so the systemd-sysusers run inside dracut
# doesn't stamp today's date into the initramfs /etc/shadow. Otherwise every
# day's build gets a unique initramfs, which changes the ostree bootcsum and
# makes `bootc upgrade --soft-reboot` refuse. Fedora's dracut-108 computes this
# value but doesn't export it (fixed upstream in dracut-ng); we mirror its logic.
RUN mkdir -p /usr/lib/ostree && \
    echo -e '[etc]\ntransient = true' >> /usr/lib/ostree/prepare-root.conf && \
    mkdir -p /var/roothome && \
    kver=$(cd /usr/lib/modules && echo *) && \
    SOURCE_DATE_EPOCH=$(stat -c %Y /usr/lib/dracut/dracut-functions.sh) \
    dracut -f /usr/lib/modules/$kver/initramfs.img $kver

LABEL containers.bootc=1 ostree.bootable=1

# It's recommended for bootc containers to set CMD /sbin/init
CMD ["/sbin/init"]
