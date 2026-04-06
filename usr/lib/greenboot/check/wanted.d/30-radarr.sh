#!/usr/bin/bash
set -euo pipefail
for _ in 1 2 3; do
    state=$(systemctl --user -M radarr@.host show radarr.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: radarr.service is not active (state='${state}')"
    exit 1
fi
echo "OK: radarr.service is active"
