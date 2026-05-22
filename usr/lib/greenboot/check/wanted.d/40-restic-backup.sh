#!/usr/bin/bash
set -euo pipefail
result=$(systemctl show restic-backup.service -p Result --value)
case "$result" in
    success|"") echo "OK: restic-backup.service result='${result:-never run}'"; exit 0 ;;
    *) echo "WARN: restic-backup.service Result='${result}'"; exit 1 ;;
esac
