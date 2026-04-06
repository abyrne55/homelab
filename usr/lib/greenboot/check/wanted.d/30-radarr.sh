#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M radarr@.host is-active --quiet radarr.service; then
    echo "FAIL: radarr.service (radarr) is not active"
    exit 1
fi
echo "OK: radarr.service (radarr) is active"
