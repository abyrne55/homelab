#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/home-assistant/.local/share/containers/storage \
               --runroot /run/user/1058/containers \
               ps --filter name=home-assistant --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: home-assistant container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: home-assistant container is healthy"
