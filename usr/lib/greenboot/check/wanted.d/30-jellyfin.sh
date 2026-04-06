#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M jellyfin@.host is-active --quiet jellyfin.service; then
    echo "FAIL: jellyfin.service (jellyfin) is not active"
    exit 1
fi
echo "OK: jellyfin.service (jellyfin) is active"
