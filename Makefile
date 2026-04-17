# Container configuration
IMAGE_NAME ?= homelab
TAG ?= latest
REMOTE_IMAGE ?= ghcr.io/abyrne55/homelab:$(shell git branch --show-current)
LOCAL_IMAGE ?= homelab:ci

# Build configuration
BUILD_DIR ?= ./build
CORE_SSH_KEY ?= ./secrets/core/id_ed25519
DATA_DISK_SIZE ?= 3G
ROOT_DISK_SIZE ?= 25G

# Platform detection
HOST_ARCH := $(shell uname -m)
HOST_OS   := $(shell uname -s)

ifeq ($(HOST_OS),Darwin)
  QEMU_ACCEL ?= hvf
  ifeq ($(HOST_ARCH),arm64)
    QEMU_BIN     ?= qemu-system-aarch64
    QEMU_MACHINE ?= virt
    QEMU_BIOS    ?= $(shell brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd
  else ifeq ($(HOST_ARCH),x86_64)
    QEMU_BIN     ?= qemu-system-x86_64
    QEMU_MACHINE ?= q35
    QEMU_BIOS    ?= $(shell brew --prefix qemu)/share/qemu/edk2-x86_64-code.fd
  endif
else ifeq ($(HOST_OS),Linux)
  QEMU_ACCEL ?= kvm
  ifeq ($(HOST_ARCH),x86_64)
    QEMU_BIN     ?= qemu-system-x86_64
    QEMU_MACHINE ?= q35
    QEMU_BIOS    ?= /usr/share/edk2/ovmf/OVMF_CODE.fd
  else ifeq ($(HOST_ARCH),aarch64)
    QEMU_BIN     ?= qemu-system-aarch64
    QEMU_MACHINE ?= virt
    QEMU_BIOS    ?= /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
  endif
endif

# QEMU configuration
SSH_PORT ?= 2222
HTTP_PORT ?= 8080
HTTPS_PORT ?= 8443
MONITOR_PORT ?= 4444

# Set DEBUG=1 for unfiltered output from build commands
DEBUG ?=

# Phony targets (convenience aliases and non-file targets)
.PHONY: build-container build-vm build-vm-from-ghcr run-vm run-vm-from-ghcr ssh-vm vm-switch await-ghcr stop-vm reboot-vm clean systemd-analyze-verify systemd-analyze-security systemd-analyze-local _pull-remote-image _build-local-image _run-verify _run-security verify-quadlets

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

_pull-remote-image:
	@podman pull $(REMOTE_IMAGE) 2>&1 | grep -Ev 'Copying (blob|config) sha256'

_build-local-image:
	@echo "Building local image for analysis..."
	@podman build -t $(LOCAL_IMAGE) -f Containerfile . 2>&1 | grep -Ev 'STEP [0-9]'

# Internal: run verify against whatever image _ANALYZE_IMAGE is set to.
_run-verify:
	@echo "Verifying custom systemd unit files from this repo..."
	@podman run --rm \
		-v $(CURDIR)/usr/lib/systemd/system:/tmp/homelab-system:ro \
		-v $(CURDIR)/usr/lib/systemd/user:/tmp/homelab-user:ro \
		$(_ANALYZE_IMAGE) /bin/bash -c ' \
		EXIT_CODE=0; \
		verify_dir() { \
			local label=$$1 dir=$$2; shift 2; \
			echo "=== $$label ==="; \
			for unit in $$(find "$$dir" -maxdepth 1 -type f \( "$$@" \) 2>/dev/null | sort); do \
				echo "  $$(basename $$unit)"; \
				if ! systemd-analyze --man=no --recursive-errors=yes verify "$$unit" 2>&1; then \
					EXIT_CODE=1; \
				fi; \
			done; \
			echo ""; \
		}; \
		verify_dir "System units"  /tmp/homelab-system  -name "*.service" -o -name "*.socket" -o -name "*.timer" -o -name "*.mount" -o -name "*.path"; \
		verify_dir "User units"    /tmp/homelab-user    -name "*.service" -o -name "*.socket" -o -name "*.timer"; \
		echo ""; \
		echo "=== Drop-in configs ==="; \
		for conf in $$(find /tmp/homelab-system -type f -name "*.conf" 2>/dev/null | sort); do \
			echo "  $$(basename $$(dirname $$conf))/$$(basename $$conf)"; \
		done; \
		exit $$EXIT_CODE'
	@echo ""
	@echo "Systemd unit verification complete"
	@echo "Note: Use 'make verify-quadlets' to validate quadlet files (.container, .volume, .network)"
	@echo "Note: Drop-in configs (.conf) are listed but validated with their parent units at runtime"

# Internal: run security analysis against whatever image _ANALYZE_IMAGE is set to.
_run-security:
	@echo "Analyzing custom systemd service security..."
	@podman run --rm \
		-v $(CURDIR)/usr/lib/systemd/system:/tmp/homelab-system:ro \
		-v $(CURDIR)/usr/lib/systemd/user:/tmp/homelab-user:ro \
		$(_ANALYZE_IMAGE) /bin/bash -c ' \
		EXIT_CODE=0; \
		scan_units() { \
			local label=$$1; local dir=$$2; \
			echo "=== $$label security scores ==="; \
			echo ""; \
			for unit in $$(find "$$dir" -maxdepth 1 -name "*.service" 2>/dev/null | sort); do \
				name=$$(basename "$$unit"); \
				ANALYSIS=$$(systemd-analyze security --offline=true --no-pager "$$unit" 2>&1); \
				SCORE=$$(echo "$$ANALYSIS" | grep -i "Overall exposure level" | sed "s/.*: //"); \
				echo "  $$name: $$SCORE"; \
				if echo "$$ANALYSIS" | grep -qE "EXPOSED|UNSAFE|DANGEROUS"; then \
					echo "  FAIL: $$name scored EXPOSED or worse. Full analysis:"; \
					echo "$$ANALYSIS"; \
					echo ""; \
					EXIT_CODE=1; \
				fi; \
			done; \
			echo ""; \
		}; \
		scan_units "System service"  /tmp/homelab-system; \
		scan_units "User service"    /tmp/homelab-user; \
		if [ $$EXIT_CODE -eq 0 ]; then \
			echo "All units passed (no EXPOSED units, i.e., no badness scores ≥ 7.5)"; \
		else \
			echo "One or more units scored EXPOSED or worse. Review the analysis above."; \
		fi; \
		exit $$EXIT_CODE'
	@echo ""
	@echo "Systemd security analysis complete"

# Run systemd-analyze verify on all custom unit files inside the GHCR image.
systemd-analyze-verify: _pull-remote-image
	@$(MAKE) --no-print-directory _run-verify _ANALYZE_IMAGE=$(REMOTE_IMAGE)


# Run systemd-analyze security on all custom .service files inside the GHCR image.
# Fails if any unit scores EXPOSED or worse (badness ≥ 7.5).
systemd-analyze-security: _pull-remote-image
	@$(MAKE) --no-print-directory _run-security _ANALYZE_IMAGE=$(REMOTE_IMAGE)

# Run both verify and security using a locally-built image, building the image only once.
systemd-analyze-local: _build-local-image
	@$(MAKE) --no-print-directory _run-verify _ANALYZE_IMAGE=$(LOCAL_IMAGE)
	@$(MAKE) --no-print-directory _run-security _ANALYZE_IMAGE=$(LOCAL_IMAGE)

# Validate quadlet files by running podman-system-generator --dryrun against each user's quadlet directory.
# Uses the base image directly (no local build required) with quadlet files mounted from the working tree.
QUADLET_VALIDATOR_IMAGE ?= $(shell grep '^FROM' Containerfile | head -1 | awk '{print $$2}')
verify-quadlets:
	@echo "Verifying quadlet files using podman-system-generator ($(QUADLET_VALIDATOR_IMAGE))..."
	@podman run --rm \
		-v $(CURDIR)/etc/containers/systemd/users:/etc/containers/systemd/users:ro \
		$(QUADLET_VALIDATOR_IMAGE) /bin/bash -c ' \
		EXIT_CODE=0; \
		GENERATOR=/usr/lib/systemd/system-generators/podman-system-generator; \
		for uid_dir in $$(find /etc/containers/systemd/users -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort); do \
			uid=$$(basename "$$uid_dir"); \
			inputs=$$(find "$$uid_dir" -maxdepth 1 \( -name "*.container" -o -name "*.volume" -o -name "*.network" \) 2>/dev/null | sort); \
			[ -z "$$inputs" ] && continue; \
			input_count=$$(echo "$$inputs" | grep -c .); \
			echo ""; \
			echo "=== UID $$uid ==="; \
			for f in $$inputs; do echo "  input:  $$(basename $$f)"; done; \
			tmpdir=$$(mktemp -d); \
			GEN_STDERR=$$(QUADLET_UNIT_DIRS="$$uid_dir" "$$GENERATOR" --user "$$tmpdir" "$$tmpdir" "$$tmpdir" 2>&1 >/dev/null); \
			GEN_EXIT=$$?; \
			outputs=$$(find "$$tmpdir" -maxdepth 1 \( -name "*.service" -o -name "*.mount" -o -name "*.socket" \) 2>/dev/null | sort); \
			for f in $$outputs; do echo "  output: $$(basename $$f)"; done; \
			if [ -n "$$GEN_STDERR" ]; then echo "$$GEN_STDERR"; fi; \
			if [ $$GEN_EXIT -ne 0 ]; then \
				echo "  FAIL: generator exited $$GEN_EXIT"; \
				EXIT_CODE=1; \
			elif [ -z "$$outputs" ]; then \
				echo "  FAIL: no units generated from $$input_count input file(s)"; \
				EXIT_CODE=1; \
			fi; \
			rm -rf "$$tmpdir"; \
		done; \
		exit $$EXIT_CODE'
	@echo ""
	@echo "Quadlet verification complete"

#
# File-based targets with dependencies
#

# Build the container image (sentinel file tracks build state)
$(BUILD_DIR)/.image-built: Containerfile $(wildcard quadlets/*) $(wildcard systemd/*) $(wildcard caddy/*)
	mkdir -p $(BUILD_DIR)
	podman build -t $(IMAGE_NAME):$(TAG) -f Containerfile .
	@touch $@

# Build qcow2 image using bootc install to-disk
$(BUILD_DIR)/qcow2/disk.qcow2: $(BUILD_DIR)/.image-built
	mkdir -p $(BUILD_DIR)/qcow2
	truncate -s $(ROOT_DISK_SIZE) $(BUILD_DIR)/disk.raw
ifdef DEBUG
	podman run \
		--rm \
		-it \
		--privileged \
		--pid=host \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR):/output \
		-v /dev:/dev \
		localhost/$(IMAGE_NAME):$(TAG) \
		bootc install to-disk --generic-image --filesystem btrfs --via-loopback /output/disk.raw
else
	@echo "Building qcow2 image from localhost/$(IMAGE_NAME):$(TAG)..."
	@podman run \
		--rm \
		-i \
		--privileged \
		--pid=host \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR):/output \
		-v /dev:/dev \
		localhost/$(IMAGE_NAME):$(TAG) \
		bootc install to-disk --generic-image --filesystem btrfs --via-loopback /output/disk.raw 2>&1 \
	| grep -E 'Installing image:|Deploying|Bootloader:|Installation complete!|[Ee]rror|[Ff]ail'
endif
	qemu-img convert -f raw -O qcow2 $(BUILD_DIR)/disk.raw $@
	rm $(BUILD_DIR)/disk.raw

# Build qcow2 image from GHCR (skips local container build)
$(BUILD_DIR)/qcow2/disk-from-ghcr.qcow2:
	mkdir -p $(BUILD_DIR)/qcow2
	@podman pull $(REMOTE_IMAGE) 2>&1 | grep -Ev 'Copying (blob|config) sha256'
	truncate -s $(ROOT_DISK_SIZE) $(BUILD_DIR)/disk.raw
ifdef DEBUG
	podman run \
		--rm \
		-it \
		--privileged \
		--pid=host \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR):/output \
		-v /dev:/dev \
		$(REMOTE_IMAGE) \
		bootc install to-disk --generic-image --filesystem btrfs --via-loopback /output/disk.raw
else
	@echo "Building qcow2 disk image..."
	@podman run \
		--rm \
		-i \
		--privileged \
		--pid=host \
		--security-opt label=type:unconfined_t \
		-v $(BUILD_DIR):/output \
		-v /dev:/dev \
		$(REMOTE_IMAGE) \
		bootc install to-disk --generic-image --filesystem btrfs --via-loopback /output/disk.raw 2>&1 \
	| grep -E 'Installing image:|Deploying|Bootloader:|Installation complete!|[Ee]rror|[Ff]ail'
endif
	qemu-img convert -f raw -O qcow2 $(BUILD_DIR)/disk.raw $@
	rm $(BUILD_DIR)/disk.raw
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
		xorrisofs -V SECRETS -J -R -o $@ $(BUILD_DIR)/secrets-temp 2>/dev/null; \
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
	@if socat /dev/null TCP:127.0.0.1:$(MONITOR_PORT) 2>/dev/null; then \
		echo "QEMU is already running"; \
	else \
		$(MAKE) _start-qemu; \
	fi

# Run VM built from GHCR image (faster than local build)
run-vm-from-ghcr: $(BUILD_DIR)/qcow2/disk-from-ghcr.qcow2 $(BUILD_DIR)/data.qcow2 $(BUILD_DIR)/secrets.iso
	@if socat /dev/null TCP:127.0.0.1:$(MONITOR_PORT) 2>/dev/null; then \
		echo "QEMU is already running"; \
	else \
		$(MAKE) _start-qemu; \
	fi

# Internal target to actually start QEMU
.PHONY: _start-qemu
_start-qemu:
	$(QEMU_BIN) \
		-M accel=$(QEMU_ACCEL) \
		-cpu host \
		-smp 2 \
		-m 4096 \
		-bios $(QEMU_BIOS) \
		-serial file:$(BUILD_DIR)/serial.log \
		-display none \
		-machine $(QEMU_MACHINE) \
		-monitor tcp:127.0.0.1:$(MONITOR_PORT),server,nowait \
		-nic user,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(HTTP_PORT)-:80,hostfwd=tcp::$(HTTPS_PORT)-:443 \
		-drive if=virtio,file=$(BUILD_DIR)/qcow2/disk.qcow2,snapshot=on \
		-drive if=virtio,file=$(BUILD_DIR)/data.qcow2 \
		$(shell [ -s $(BUILD_DIR)/secrets.iso ] && echo "-drive file=$(BUILD_DIR)/secrets.iso,format=raw,if=virtio,readonly=on,media=cdrom,id=secrets") & disown
	@echo "QEMU running in background. Serial output: $(BUILD_DIR)/serial.log"

# SSH options
SSH_HOST := 127.0.0.1
SSH_OPTS := -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey

# Internal target to check if VM is running
.PHONY: _check-vm-running
_check-vm-running:
	@socat /dev/null TCP:127.0.0.1:$(MONITOR_PORT) 2>/dev/null || \
		{ echo "ERROR: VM is not running. Start it with 'make run-vm' or 'make run-vm-from-ghcr' first."; exit 1; }

# SSH into the running VM (waits for SSH to become available)
ssh-vm: _check-vm-running
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@$(SSH_HOST) exit 2>/dev/null; do \
		sleep 1; \
	done
	ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@$(SSH_HOST) || true

# Switch VM to container image for current git branch
vm-switch: _check-vm-running
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@$(SSH_HOST) exit 2>/dev/null; do \
		sleep 1; \
	done
	@echo "Switching to $(REMOTE_IMAGE)..."
	ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@$(SSH_HOST) -- "sudo bootc switch --apply $(REMOTE_IMAGE) && sudo bootc upgrade --apply" || true

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
	@COMMIT_SHA=$$(git rev-parse HEAD); \
	MAX_RETRIES=12; \
	RETRY_DELAY=5; \
	for i in $$(seq 1 $$MAX_RETRIES); do \
		RUN_ID=$$(gh run list --workflow container-build.yml --commit $$COMMIT_SHA --limit 1 --json databaseId --jq '.[] | .databaseId' 2>/dev/null); \
		if [ -n "$$RUN_ID" ]; then \
			echo "Found workflow run $$RUN_ID"; \
			gh run watch --compact --exit-status $$RUN_ID; \
			exit 0; \
		fi; \
		if [ $$i -lt $$MAX_RETRIES ]; then \
			echo "No workflow run found for commit $$COMMIT_SHA (attempt $$i/$$MAX_RETRIES), retrying in $$RETRY_DELAY seconds..."; \
			sleep $$RETRY_DELAY; \
		fi; \
	done; \
	echo "ERROR: No workflow run found for commit $$COMMIT_SHA after $$MAX_RETRIES attempts."; \
	echo "Check that GitHub Actions is enabled and the workflow was triggered."; \
	exit 1

#
# Cleanup
#

# Stop the VM
stop-vm:
	-echo quit | socat - TCP:127.0.0.1:$(MONITOR_PORT) 2>/dev/null

# Reboot the VM
reboot-vm: _check-vm-running
	@echo "Waiting for SSH to become available..."
	@until ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) -o ConnectTimeout=2 core@$(SSH_HOST) exit 2>/dev/null; do \
		sleep 1; \
	done
	ssh -i $(CORE_SSH_KEY) -p $(SSH_PORT) $(SSH_OPTS) core@$(SSH_HOST) -- "sudo reboot" || true

# Clean up all build artifacts
clean: stop-vm
	rm -rf $(BUILD_DIR)
