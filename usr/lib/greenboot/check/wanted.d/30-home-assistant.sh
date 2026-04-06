#!/usr/bin/bash
set -euo pipefail
for _ in 1 2 3; do
    state=$(systemctl --user -M home-assistant@.host show home-assistant.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: home-assistant.service is not active (state='${state}')"
    exit 1
fi
echo "OK: home-assistant.service is active"
