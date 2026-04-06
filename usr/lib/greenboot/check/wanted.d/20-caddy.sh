#!/usr/bin/bash
set -euo pipefail
# Retry up to 3 times to handle transient D-Bus connection errors at boot.
for _ in 1 2 3; do
    state=$(systemctl --user -M caddy@.host show caddy.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: caddy.service is not active (state='${state}')"
    exit 1
fi
echo "OK: caddy.service is active"
