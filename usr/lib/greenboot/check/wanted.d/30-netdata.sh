#!/usr/bin/bash
set -euo pipefail
for _ in 1 2 3; do
    state=$(systemctl show netdata.service -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: netdata.service is not active (state='${state}')"
    exit 1
fi
echo "OK: netdata.service is active"
