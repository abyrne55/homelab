#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/prowlarr/.local/share/containers/storage \
               --runroot /run/user/1057/containers \
               ps --filter name=prowlarr --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: prowlarr container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: prowlarr container is healthy"
