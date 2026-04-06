#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M home-assistant@.host is-active --quiet home-assistant.service; then
    echo "FAIL: home-assistant.service (home-assistant) is not active"
    exit 1
fi
echo "OK: home-assistant.service (home-assistant) is active"
