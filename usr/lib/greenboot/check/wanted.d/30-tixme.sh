#!/usr/bin/bash
set -euo pipefail
# Upstream image is amd64-only; tixme.service is skipped on other architectures.
if [ "$(uname -m)" != "x86_64" ]; then
    echo "SKIP: tixme.service is x86_64-only"
    exit 0
fi
for _ in 1 2 3; do
    state=$(systemctl --user -M tixme@.host show tixme.service \
            -p ActiveState --value 2>/dev/null) && break || state=""
    sleep 5
done
if [ "$state" != "active" ]; then
    echo "FAIL: tixme.service is not active (state='${state}')"
    exit 1
fi
echo "OK: tixme.service is active"
