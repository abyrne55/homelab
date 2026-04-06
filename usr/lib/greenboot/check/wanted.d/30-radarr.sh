#!/usr/bin/bash
set -euo pipefail
status=$(podman --root /var/home/radarr/.local/share/containers/storage \
               --runroot /run/user/1054/containers \
               ps --filter name=radarr --format '{{.Status}}' 2>/dev/null)
if [[ "$status" != *"(healthy)"* ]]; then
    echo "FAIL: radarr container is not healthy (status: '${status}')"
    exit 1
fi
echo "OK: radarr container is healthy"
