#!/usr/bin/bash
set -euo pipefail
if ! systemctl is-active --quiet wg-nas.service; then
    echo "FAIL: wg-nas.service is not active"
    exit 1
fi
echo "OK: wg-nas.service is active"
