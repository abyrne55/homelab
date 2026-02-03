#!/bin/bash
# create-quadlet-user.sh
# Creates a user configured for running rootless podman quadlets
# Usage: create-quadlet-user.sh <username> <uid> <description>

set -euo pipefail

if [ $# -ne 3 ]; then
    echo "Usage: $0 <username> <uid> <description>" >&2
    exit 1
fi

USERNAME="$1"
USER_ID="$2"
DESCRIPTION="$3"

# Create user with systemd-age-creds group membership
# The -m flag copies /etc/skel to the new home directory
useradd -u "$USER_ID" -m -d "/var/home/$USERNAME" -s /sbin/nologin \
    -c "$DESCRIPTION" -G systemd-age-creds-users "$USERNAME"

# Set ownership (useradd should handle this, but being explicit)
chown -R "$USERNAME:$USERNAME" "/var/home/$USERNAME"

# Enable systemd linger
mkdir -p /var/lib/systemd/linger
touch "/var/lib/systemd/linger/$USERNAME"

echo "Created quadlet user: $USERNAME (UID $USER_ID)"
