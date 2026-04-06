#!/usr/bin/bash
set -euo pipefail
result=$(systemctl show homelab-secrets-sync.service -p Result --value)
if [ "$result" != "success" ]; then
    echo "FAIL: homelab-secrets-sync.service Result='${result}', expected 'success'"
    exit 1
fi
echo "OK: homelab-secrets-sync.service completed successfully"
