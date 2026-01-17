.PHONY: all ignition qcow2 start clean

BUILD_DIR := build
IGNITION_DIR := ignition

# Source files
BU_FILES := $(wildcard $(IGNITION_DIR)/*.bu)
IGN_FILES := $(patsubst $(IGNITION_DIR)/%.bu,$(BUILD_DIR)/%.ign,$(BU_FILES))

# VM artifacts
VM_NAME := homelab-staging
VM_DISK := $(BUILD_DIR)/$(VM_NAME).qcow2
START_SCRIPT := $(BUILD_DIR)/start-$(VM_NAME).sh

all: qcow2

# Compile butane files to ignition
ignition: $(IGN_FILES)

$(BUILD_DIR)/%.ign: $(IGNITION_DIR)/%.bu | $(BUILD_DIR)
	butane --pretty --strict $< > $@

# Create VM disk (depends on ignition config)
qcow2: $(VM_DISK)

$(VM_DISK): $(IGN_FILES) | $(BUILD_DIR)
	cd $(BUILD_DIR) && ../scripts/create-vm.sh

# Start the VM
start: $(VM_DISK)
	cd $(BUILD_DIR) && ./start-$(VM_NAME).sh

# Ensure build directory exists
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Clean build artifacts
clean:
	rm -f $(BUILD_DIR)/*.ign
	rm -f $(BUILD_DIR)/*.qcow2
	rm -f $(BUILD_DIR)/start-*.sh
	rm -f $(BUILD_DIR)/*.raw
	rm -f $(BUILD_DIR)/*.raw.xz
	rm -f $(BUILD_DIR)/*-CHECKSUM
	rm -f $(BUILD_DIR)/fedora.gpg

# SSH into the running VM
ssh:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 core@localhost
