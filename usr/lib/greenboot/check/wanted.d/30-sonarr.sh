#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/sonarr/.local/share/containers/storage \
               --runroot /run/user/1055/containers \
               ps --filter name=sonarr --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: sonarr container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: sonarr container is healthy"
