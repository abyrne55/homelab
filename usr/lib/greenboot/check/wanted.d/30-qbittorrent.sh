#!/usr/bin/bash
set -euo pipefail
if ! systemctl --user -M qbittorrent@.host is-active --quiet qbittorrent.service; then
    echo "FAIL: qbittorrent.service (qbittorrent) is not active"
    exit 1
fi
echo "OK: qbittorrent.service (qbittorrent) is active"
