#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/caddy/.local/share/containers/storage \
               --runroot /run/user/1051/containers \
               ps --filter name=caddy --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: caddy container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: caddy container is healthy"
