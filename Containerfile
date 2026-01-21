# In this example, a simple "podman-systemd" unit which runs
# an application container via https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
# that is also configured for automatic updates via
# https://docs.podman.io/en/latest/markdown/podman-auto-update.1.html

FROM quay.io/fedora/fedora-bootc:43
COPY httpd.container /usr/share/containers/systemd
# Enable the simple "automatic update containers" timer, in the same way
# that there is a simplistic bootc upgrade timer.  However, you can
# obviously also customize this as you like; for example, using
# other tooling like Watchtower or explicit out-of-band control over container
# updates via e.g. Ansible or other custom logic.
RUN systemctl enable podman-auto-update.timer
