#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/qbittorrent/.local/share/containers/storage \
               --runroot /run/user/1053/containers \
               ps --filter name=qbittorrent --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: qbittorrent container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: qbittorrent container is healthy"
