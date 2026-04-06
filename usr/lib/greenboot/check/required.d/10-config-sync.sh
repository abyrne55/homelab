#!/usr/bin/bash
set -euo pipefail
result=$(systemctl show homelab-config-sync.service -p Result --value)
if [ "$result" != "success" ]; then
    echo "FAIL: homelab-config-sync.service Result='${result}', expected 'success'"
    exit 1
fi
echo "OK: homelab-config-sync.service completed successfully"
