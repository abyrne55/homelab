# Container configuration
IMAGE_NAME ?= homelab
TAG ?= latest
REMOTE_IMAGE ?= ghcr.io/abyrne55/homelab:$(shell git branch --show-current)

# Build configuration
BUILD_DIR ?= ./build
CORE_SSH_KEY ?= ./secrets/core/id_ed25519
DATA_DISK_SIZE ?= 3G

# QEMU configuration
QEMU_BIOS ?= $(shell brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd
DETACH ?= true
SSH_PORT ?= 2222
HTTP_PORT ?= 8080
JELLYFIN_PORT ?= 8096
CADDY_PORT ?= 80

# Phony targets (convenience aliases and non-file targets)
.PHONY: build-container build-vm build-vm-from-ghcr run-vm run-vm-from-ghcr ssh-vm open-jellyfin vm-switch await-ghcr stop-vm reboot-vm clean verify-systemd

# Default target
.DEFAULT_GOAL := build-container

#
# Convenience aliases
#
build-container: $(BUILD_DIR)/.image-built
build-vm: $(BUILD_DIR)/qcow2/disk.qcow2 $(BUILD_DIR)/data.qcow2 $(BUILD_DIR)/secrets.iso
build-vm-from-ghcr: $(BUILD_DIR)/qcow2/disk-from-ghcr.qcow2 $(BUILD_DIR)/data.qcow2 $(BUILD_DIR)/secrets.iso

#
# Verification targets
#

# Verify all systemd unit files using systemd-analyze inside the container
# Note: Quadlet files (.container) are not verified as they are converted to systemd units at runtime
verify-systemd: $(BUILD_DIR)/.image-built
	@echo "Verifying custom systemd unit files from this repo..."
	@podman run --rm $(IMAGE_NAME):$(TAG) /bin/bash -c ' \
		EXIT_CODE=0; \
		echo "=== System units (/etc/systemd/system) ==="; \
		for unit in $$(find /etc/systemd/system -maxdepth 1 -type f \( -name "*.service" -o -name "*.socket" -o -name "*.timer" -o -name "*.mount" -o -name "*.path" \) 2>/dev/null); do \
			echo "Verifying $$unit"; \
			OUTPUT=$$(systemd-analyze verify "$$unit" 2>&1); \
			VERIFY_EXIT=$$?; \
			if [ $$VERIFY_EXIT -ne 0 ]; then \
				FILTERED=$$(echo "$$OUTPUT" | grep -v "Command .man.*failed with code"); \
				if [ -n "$$FILTERED" ]; then \
					echo "$$FILTERED"; \
					EXIT_CODE=1; \
				fi; \
			fi; \
		done; \
		echo ""; \
		echo "=== User units (custom only) ==="; \
		if [ -f /usr/lib/systemd/user/caddy.socket ]; then \
			echo "Verifying /usr/lib/systemd/user/caddy.socket"; \
			OUTPUT=$$(systemd-analyze verify /usr/lib/systemd/user/caddy.socket 2>&1); \
			VERIFY_EXIT=$$?; \
			if [ $$VERIFY_EXIT -ne 0 ]; then \
				FILTERED=$$(echo "$$OUTPUT" | grep -v "Command .man.*failed with code" | grep -v "service caddy.service not loaded"); \
				if [ -n "$$FILTERED" ]; then \
					echo "$$FILTERED"; \
					EXIT_CODE=1; \
				fi; \
			fi; \
		fi; \
		echo ""; \
		echo "=== Drop-in configs ==="; \
		for conf in $$(find /etc/systemd/system -type f -name "*.conf" 2>/dev/null); do \
			echo "Found: $$conf"; \
		done; \
		exit $$EXIT_CODE'
	@echo ""
	@echo "Systemd unit verification complete"
	@echo "Note: Quadlet files (.container) are not verified - they are converted to systemd units at runtime by podman-systemd-generator"
	@echo "Note: Drop-in configs (.conf) are listed but validated with their parent units at runtime"

#
# File-based targets with dependencies
#

# Build the container image (sentinel file tracks build state)
$(BUILD_DIR)/.image-built: Containerfile $(wildcard quadlets/*) $(wildcard systemd/*) $(wildcard caddy/*)
	mkdir -p $(BUILD_DIR)
	podman build -t $(IMAGE_NAME):$(TAG) -f Containerfile .
	@touch $@

# Build qcow2 image using bootc-image-builder
$(BUILD_DIR)/qcow2/disk.qcow2: $(BUILD_DIR)/.image-built
	podman run \
		--rm \
		-it \
		--privileged \
		--pull=newer \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR):/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		quay.io/centos-bootc/bootc-image-builder:latest \
		--type qcow2 \
		--use-librepo=True \
		localhost/$(IMAGE_NAME):$(TAG) \
		--rootfs btrfs

# Build qcow2 image from GHCR (skips local container build)
$(BUILD_DIR)/qcow2/disk-from-ghcr.qcow2:
	mkdir -p $(BUILD_DIR)
	podman pull $(REMOTE_IMAGE)
	podman run \
		--rm \
		-it \
		--privileged \
		--pull=newer \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR):/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		quay.io/centos-bootc/bootc-image-builder:latest \
		--type qcow2 \
		--use-librepo=True \
		$(REMOTE_IMAGE) \
		--rootfs btrfs
	@# Rename the created disk to disk-from-ghcr.qcow2
	@mv $(BUILD_DIR)/qcow2/disk.qcow2 $(BUILD_DIR)/qcow2/disk-from-ghcr.qcow2
	@# Create a symlink so run-vm can use the same disk path
	@ln -sf disk-from-ghcr.qcow2 $(BUILD_DIR)/qcow2/disk.qcow2

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

# Run VM built from GHCR image (faster than local build)
run-vm-from-ghcr: $(BUILD_DIR)/qcow2/disk-from-ghcr.qcow2 $(BUILD_DIR)/data.qcow2 $(BUILD_DIR)/secrets.iso
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
		$(shell [ -s $(BUILD_DIR)/secrets.iso ] && echo "-drive file=$(BUILD_DIR)/secrets.iso,format=raw,if=virtio,readonly=on,media=cdrom,id=secrets") & disown
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
SSH_OPTS := -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey

# Internal target to check if VM is running
.PHONY: _check-vm-running
_check-vm-running:
	@if ! pgrep -f "qemu-system-aarch64.*$(BUILD_DIR)/qcow2/disk.qcow2" > /dev/null; then \
		echo "ERROR: VM is not running. Start it with 'make run-vm' or 'make run-vm-from-ghcr' first."; \
		exit 1; \
	fi

# SSH into the running VM (waits for SSH to become available)
ssh-vm: _check-vm-running
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@localhost exit 2>/dev/null; do \
		sleep 1; \
	done
	ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@localhost || true

# Open Jellyfin web UI in default browser
open-jellyfin: _check-vm-running
	@if [ "$$(uname)" = "Darwin" ]; then \
		open "http://localhost:$(JELLYFIN_PORT)"; \
	else \
		xdg-open "http://localhost:$(JELLYFIN_PORT)"; \
	fi

# Switch VM to container image for current git branch
vm-switch: _check-vm-running
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@localhost exit 2>/dev/null; do \
		sleep 1; \
	done
	@echo "Switching to $(REMOTE_IMAGE)..."
	ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@localhost -- "sudo bootc switch --apply $(REMOTE_IMAGE) && sudo bootc upgrade --apply" || true

# Wait for GitHub Actions to build container image for current commit
await-ghcr:
	@echo "Checking git status..."
	@# Fail if there are staged changes
	@if ! git diff --cached --quiet; then \
		echo "ERROR: There are staged changes. Commit or unstage them before running."; \
		exit 1; \
	fi
	@# Fail if there are unpushed commits
	@if [ -n "$$(git rev-list @{u}..HEAD 2>/dev/null)" ]; then \
		echo "ERROR: There are unpushed commits. Push to origin before running."; \
		exit 1; \
	fi
	@# Warn if there are unstaged or untracked files
	@if ! git diff --quiet 2>/dev/null; then \
		echo "WARNING: There are unstaged changes."; \
	fi
	@if [ -n "$$(git ls-files --others --exclude-standard)" ]; then \
		echo "WARNING: There are untracked files."; \
	fi
	@echo "Waiting for GitHub Actions build to complete..."
	@gh run watch --compact --exit-status $$(gh run list --commit $$(git rev-parse HEAD) --limit 1 --json databaseId --jq '.[] | .databaseId')

#
# Cleanup
#

# Stop the VM
stop-vm:
	-pkill -f "qemu-system-aarch64.*$(BUILD_DIR)/qcow2/disk.qcow2"

# Reboot the VM
reboot-vm: _check-vm-running
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@localhost exit 2>/dev/null; do \
		sleep 1; \
	done
	ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@localhost -- "sudo reboot" || true

# Clean up all build artifacts
clean: stop-vm
	rm -rf $(BUILD_DIR)
