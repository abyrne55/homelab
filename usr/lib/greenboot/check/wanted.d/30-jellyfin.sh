#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/jellyfin/.local/share/containers/storage \
               --runroot /run/user/1052/containers \
               ps --filter name=jellyfin --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: jellyfin container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: jellyfin container is healthy"
