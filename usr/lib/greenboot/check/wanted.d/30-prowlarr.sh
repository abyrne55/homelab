#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M prowlarr@.host is-active --quiet prowlarr.service; then
    echo "FAIL: prowlarr.service (prowlarr) is not active"
    exit 1
fi
echo "OK: prowlarr.service (prowlarr) is active"
