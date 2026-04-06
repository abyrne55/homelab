#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M caddy@.host is-active --quiet caddy.service; then
    echo "FAIL: caddy.service (caddy) is not active"
    exit 1
fi
echo "OK: caddy.service (caddy) is active"
