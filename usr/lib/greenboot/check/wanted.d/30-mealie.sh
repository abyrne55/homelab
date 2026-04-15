#!/usr/bin/bash
set -euo pipefail
for _ in 1 2 3; do
    state=$(systemctl --user -M mealie@.host show mealie.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: mealie.service is not active (state='${state}')"
    exit 1
fi
echo "OK: mealie.service is active"
