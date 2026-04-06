#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M sonarr@.host is-active --quiet sonarr.service; then
    echo "FAIL: sonarr.service (sonarr) is not active"
    exit 1
fi
echo "OK: sonarr.service (sonarr) is active"
