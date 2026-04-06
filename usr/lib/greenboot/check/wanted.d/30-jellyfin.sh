#!/usr/bin/bash
set -euo pipefail
for _ in 1 2 3; do
    state=$(systemctl --user -M jellyfin@.host show jellyfin.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: jellyfin.service is not active (state='${state}')"
    exit 1
fi
echo "OK: jellyfin.service is active"
