#!/bin/bash
set -euo pipefail

# Configuration
VM_NAME="homelab-staging"
VM_DISK="$VM_NAME.qcow2"
DISK_SIZE="20G"
RAM="4G"
CPUS="4"
SSH_PORT="2222"
FEDORA_IOT_VERSION="${FEDORA_IOT_VERSION:-43}"
IGNITION_FILE="${IGNITION_FILE:-base.ign}"

echo "=== Creating Fedora IoT VM ==="

# Prepare to download and verify Fedora IoT
FEDORA_XZ_DIR_URL="https://download.fedoraproject.org/pub/alt/iot/$FEDORA_IOT_VERSION/IoT/aarch64/images/"
FEDORA_XZ_NAME=$(curl -L --silent "$FEDORA_XZ_DIR_URL" | grep --only-matching -E 'Fedora-IoT-raw-'"${FEDORA_IOT_VERSION}"'-[0-9]+\.[0-9]+\.aarch64\.raw\.xz' | sort -r | head -1)
FEDORA_XZ_URL="$FEDORA_XZ_DIR_URL/$FEDORA_XZ_NAME"
CHECKSUM_NAME=$(echo "$FEDORA_XZ_NAME" | sed -E 's/Fedora-IoT-raw-([0-9]+)-([0-9]+\.[0-9]+)\.aarch64\.raw\.xz/Fedora-IoT-\1-aarch64-\2-CHECKSUM/')
CHECKSUM_URL="$FEDORA_XZ_DIR_URL/$CHECKSUM_NAME"

# Download the compressed image (if not already downloaded) and checksum file
echo "Downloading $FEDORA_XZ_NAME..."
curl -# -L -C - "$FEDORA_XZ_URL" -O
curl --no-progress-meter -L "$CHECKSUM_URL" -O

# Verify the compressed image against the checksum file and Fedora's GPG key
echo "Verifying downloaded file..."
curl --no-progress-meter -O "https://fedoraproject.org/fedora.gpg"
sha256sum -c --ignore-missing <(gpgv --keyring ./fedora.gpg --output - "$CHECKSUM_NAME") || exit 1

# Extract the file
echo "Extracting..."
unxz -fkv "$FEDORA_XZ_NAME"
FEDORA_RAW_IMG="${FEDORA_XZ_NAME%.xz}"

# Create VM disk from base image
echo "Creating VM disk..."
rm -f "$VM_DISK"
qemu-img create -f qcow2 -F raw -b "$FEDORA_RAW_IMG" "$VM_DISK" "$DISK_SIZE"

# Verify Ignition config exists
if [ ! -f "$IGNITION_FILE" ]; then
    echo "ERROR: Ignition config not found at $IGNITION_FILE"
    echo "Run: ./scripts/compile-ignition.sh"
    exit 1
fi

# Create startup script
cat > "start-$VM_NAME.sh" <<VMSCRIPT
#!/bin/bash
HTTP_PORT=8080

# Start HTTP server to serve Ignition config
echo "Starting HTTP server on port \$HTTP_PORT..."
python3 -m http.server \$HTTP_PORT >/dev/null 2>&1 &
HTTP_PID=\$!

# Clean up HTTP server on exit
cleanup() {
    echo "Stopping HTTP server..."
    kill \$HTTP_PID 2>/dev/null
}
trap cleanup EXIT INT TERM

# Give HTTP server a moment to start
sleep 1

echo "Starting VM (Ignition config: http://10.0.2.2:\$HTTP_PORT/$IGNITION_FILE)..."
qemu-system-aarch64 \\
    -machine virt,accel=hvf \\
    -cpu host \\
    -smp $CPUS \\
    -m $RAM \\
    -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \\
    -drive file=$VM_DISK,if=virtio,format=qcow2 \\
    -fw_cfg name=opt/com.coreos/config,string=http://10.0.2.2:\$HTTP_PORT/$IGNITION_FILE \\
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \\
    -device virtio-net-pci,netdev=net0 \\
    -nographic \\
    -serial mon:stdio
VMSCRIPT

chmod +x "start-$VM_NAME.sh"

echo ""
echo "✓ VM created successfully!"
echo ""
echo "To start VM:"
echo "  ./start-$VM_NAME.sh"
echo ""
echo "To connect via SSH:"
echo "  ssh -p $SSH_PORT core@localhost"
echo ""
echo "To stop VM:"
echo "  Press Ctrl-A then X in the QEMU console"
echo ""
