#!/bin/bash
set -euo pipefail

DB="/var/mnt/data/.jellyfin/config/data/jellyfin.db"
API_KEY=$(tr -d '[:space:]' < "${CREDENTIALS_DIRECTORY}/jellarr-api-key")
API_KEY_NAME="jellarr"

echo "Waiting for Jellyfin database at ${DB}..."
until [ -e "$DB" ]; do
    sleep 2
done

# Also wait for the schema to be initialized — Jellyfin creates the file before
# running migrations, so ApiKeys may not exist yet even though the file does.
echo "Waiting for Jellyfin database schema..."
until sqlite3 "$DB" "SELECT COUNT(*) FROM ApiKeys;" 2>/dev/null; do
    sleep 2
done

EXISTING=$(sqlite3 "$DB" "SELECT COUNT(*) FROM ApiKeys WHERE Name='${API_KEY_NAME}'")
if [ "$EXISTING" != "0" ]; then
    echo "API key '${API_KEY_NAME}' already exists, skipping bootstrap"
    exit 0
fi

echo "Stopping Jellyfin to insert API key..."
systemctl --user stop jellyfin.service
# systemctl stop is synchronous — returns only after the unit is fully inactive

sqlite3 "$DB" <<SQL
BEGIN IMMEDIATE;
INSERT INTO ApiKeys (AccessToken, Name, DateCreated, DateLastActivity)
SELECT '${API_KEY}', '${API_KEY_NAME}', datetime('now'), datetime('now')
WHERE NOT EXISTS (SELECT 1 FROM ApiKeys WHERE Name='${API_KEY_NAME}');
COMMIT;
SQL

systemctl --user start jellyfin.service
echo "Bootstrap complete — API key '${API_KEY_NAME}' inserted"
