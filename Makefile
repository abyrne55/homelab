# Container configuration
IMAGE_NAME ?= homelab
TAG ?= latest

# Build configuration
BUILD_DIR ?= ./build
SSH_KEY ?= $(BUILD_DIR)/id_ed25519
DATA_DISK_SIZE ?= 3G

# QEMU configuration
QEMU_BIOS ?= $(shell brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd
DETACH ?= true
SSH_PORT ?= 2222
HTTP_PORT ?= 8080
JELLYFIN_PORT ?= 8096
CADDY_PORT ?= 80

# Phony targets (convenience aliases and non-file targets)
.PHONY: build-container build-vm run-vm ssh-vm open-jellyfin stop-vm reboot-vm clean

# Default target
.DEFAULT_GOAL := build-container

#
# Convenience aliases
#
build-container: $(BUILD_DIR)/.image-built
build-vm: $(BUILD_DIR)/qcow2/disk.qcow2 $(BUILD_DIR)/data.qcow2 $(BUILD_DIR)/secrets.iso

#
# File-based targets with dependencies
#

# Build the container image (sentinel file tracks build state)
$(BUILD_DIR)/.image-built: Containerfile $(wildcard quadlets/*) $(wildcard systemd/*) $(wildcard caddy/*)
	mkdir -p $(BUILD_DIR)
	podman build -t $(IMAGE_NAME):$(TAG) -f Containerfile .
	@touch $@

# Generate SSH key
$(BUILD_DIR)/id_ed25519:
	mkdir -p $(BUILD_DIR)
	ssh-keygen -t ed25519 -f $@ -N "" -C "homelab-vm" -q

# Generate config.toml with SSH public key
$(BUILD_DIR)/config.toml: $(BUILD_DIR)/id_ed25519
	@echo '[[customizations.user]]' > $@
	@echo 'name = "core"' >> $@
	@echo 'key = "$(shell cat $(BUILD_DIR)/id_ed25519.pub)"' >> $@
	@echo 'groups = ["wheel"]' >> $@

# Build qcow2 image using bootc-image-builder
$(BUILD_DIR)/qcow2/disk.qcow2: $(BUILD_DIR)/.image-built $(BUILD_DIR)/config.toml
	podman run \
		--rm \
		-it \
		--privileged \
		--pull=newer \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR)/config.toml:/config.toml:ro \
		-v $(BUILD_DIR):/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		quay.io/centos-bootc/bootc-image-builder:latest \
		--type qcow2 \
		--use-librepo=True \
		localhost/$(IMAGE_NAME):$(TAG) \
		--rootfs btrfs

# Create data disk for media storage (formatted on first boot)
$(BUILD_DIR)/data.qcow2:
	mkdir -p $(BUILD_DIR)
	qemu-img create -f qcow2 $@ $(DATA_DISK_SIZE)

# Build secrets ISO if secrets exist (optional)
$(BUILD_DIR)/secrets.iso:
	@if [ -d secrets ] && [ -f secrets/age.key ] && [ -f secrets/ssh.key ]; then \
		echo "Creating secrets ISO..."; \
		mkdir -p $(BUILD_DIR)/secrets-temp; \
		cp secrets/age.key $(BUILD_DIR)/secrets-temp/; \
		cp secrets/age.key.pub $(BUILD_DIR)/secrets-temp/; \
		cp secrets/ssh.key $(BUILD_DIR)/secrets-temp/; \
		cp secrets/ssh.key.pub $(BUILD_DIR)/secrets-temp/; \
		xorrisofs -V SECRETS -J -R -o $@ $(BUILD_DIR)/secrets-temp; \
		rm -rf $(BUILD_DIR)/secrets-temp; \
		echo "Secrets ISO created successfully."; \
	else \
		echo "Secrets not found - skipping secrets ISO creation."; \
		echo "VM will use auto-generated keys from systemd services."; \
		touch $@; \
	fi

#
# Runtime targets
#

# Run the qcow2 image in QEMU (checks if already running)
run-vm: $(BUILD_DIR)/qcow2/disk.qcow2 $(BUILD_DIR)/data.qcow2 $(BUILD_DIR)/secrets.iso
	@if pgrep -f "qemu-system-aarch64.*$(BUILD_DIR)/qcow2/disk.qcow2" > /dev/null; then \
		echo "QEMU is already running"; \
	else \
		$(MAKE) _start-qemu; \
	fi

# Internal target to actually start QEMU
.PHONY: _start-qemu
_start-qemu:
ifeq ($(DETACH),true)
	qemu-system-aarch64 \
		-M accel=hvf \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios $(QEMU_BIOS) \
		-serial file:$(BUILD_DIR)/serial.log \
		-display none \
		-machine virt \
		-nic user,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(HTTP_PORT)-:8080,hostfwd=tcp::$(JELLYFIN_PORT)-:8096,hostfwd=tcp::$(CADDY_PORT)-:80 \
		-drive if=virtio,file=$(BUILD_DIR)/qcow2/disk.qcow2,snapshot=on \
		-drive if=virtio,file=$(BUILD_DIR)/data.qcow2 \
		$(shell [ -s $(BUILD_DIR)/secrets.iso ] && echo "-drive file=$(BUILD_DIR)/secrets.iso,format=raw,if=virtio,readonly=on,media=cdrom,id=secrets") &
	@echo "QEMU running in background. Serial output: $(BUILD_DIR)/serial.log"
else
	qemu-system-aarch64 \
		-M accel=hvf \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios $(QEMU_BIOS) \
		-serial stdio \
		-display none \
		-machine virt \
		-nic user,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(HTTP_PORT)-:8080,hostfwd=tcp::$(JELLYFIN_PORT)-:8096,hostfwd=tcp::$(CADDY_PORT)-:80 \
		-drive if=virtio,file=$(BUILD_DIR)/qcow2/disk.qcow2,snapshot=on \
		-drive if=virtio,file=$(BUILD_DIR)/data.qcow2 \
		$(shell [ -s $(BUILD_DIR)/secrets.iso ] && echo "-drive file=$(BUILD_DIR)/secrets.iso,format=raw,if=virtio,readonly=on,media=cdrom,id=secrets")
endif

# SSH options
SSH_OPTS := -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey

# SSH into the running VM (waits for SSH to become available)
ssh-vm: run-vm
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@localhost exit 2>/dev/null; do \
		sleep 1; \
	done
	ssh -i $(SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@localhost

# Open Jellyfin web UI in default browser
open-jellyfin: run-vm
	@if [ "$$(uname)" = "Darwin" ]; then \
		open "http://localhost:$(JELLYFIN_PORT)"; \
	else \
		xdg-open "http://localhost:$(JELLYFIN_PORT)"; \
	fi

#
# Cleanup
#

# Stop the VM
stop-vm:
	-pkill -f "qemu-system-aarch64.*$(BUILD_DIR)/qcow2/disk.qcow2"

# Reboot the VM
reboot-vm: stop-vm
	@echo "Rebooting VM..."
	@sleep 1
	$(MAKE) run-vm

# Clean up all build artifacts
clean: stop-vm
	rm -rf $(BUILD_DIR)
