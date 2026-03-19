# FajarOS Nova — Build System
# Target: x86_64-unknown-none (bare-metal)
# Compiler: Fajar Lang (fj)

# Paths
FJ := fj
KERNEL_SRC := kernel/main.fj
BUILD_DIR := build
KERNEL_ELF := $(BUILD_DIR)/fajaros.elf
ISO_FILE := $(BUILD_DIR)/fajaros.iso
GRUB_CFG := grub.cfg

# QEMU settings
QEMU := qemu-system-x86_64
QEMU_COMMON := -serial stdio -no-reboot -no-shutdown
QEMU_MEM := -m 512M
QEMU_CPU := -cpu qemu64,+avx2,+sse4.2
QEMU_KVM := -enable-kvm -cpu host
QEMU_SMP := -smp 4
QEMU_NVME := -drive file=disk.img,if=none,id=nvme0 -device nvme,serial=fajaros,drive=nvme0

.PHONY: all build run run-kvm run-vga debug iso clean test

all: build

# Build kernel ELF from Fajar Lang source
build:
	@mkdir -p $(BUILD_DIR)
	$(FJ) build --target x86_64-none $(KERNEL_SRC) -o $(KERNEL_ELF)
	@echo "[OK] Kernel built: $(KERNEL_ELF)"

# Run in QEMU (serial only, no graphics)
run: build
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -nographic

# Run with KVM acceleration (near-native speed)
run-kvm: build
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) -nographic

# Run with VGA display
run-vga: build
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU)

# Run with SMP (4 cores)
run-smp: build
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) $(QEMU_SMP) -nographic

# Run with NVMe storage
run-nvme: build
	@test -f disk.img || qemu-img create -f raw disk.img 64M
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) $(QEMU_NVME) -nographic

# Debug with GDB (QEMU waits for GDB connection)
debug: build
	@echo "Starting QEMU with GDB server on :1234"
	@echo "Connect with: gdb -ex 'target remote :1234' -ex 'symbol-file $(KERNEL_ELF)'"
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -s -S -nographic

# Create bootable ISO with GRUB2
iso: build
	@mkdir -p $(BUILD_DIR)/iso/boot/grub
	cp $(KERNEL_ELF) $(BUILD_DIR)/iso/boot/fajaros.elf
	cp $(GRUB_CFG) $(BUILD_DIR)/iso/boot/grub/grub.cfg
	grub-mkrescue -o $(ISO_FILE) $(BUILD_DIR)/iso 2>/dev/null
	@echo "[OK] ISO created: $(ISO_FILE)"

# Run from ISO
run-iso: iso
	$(QEMU) -cdrom $(ISO_FILE) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU)

# Run tests in QEMU (auto-exit)
test: build
	@echo "Running FajarOS tests in QEMU..."
	timeout 10 $(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) \
		-nographic -device isa-debug-exit,iobase=0xf4,iosize=0x04 || true
	@echo "[OK] Tests complete"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f disk.img
	@echo "[OK] Cleaned"

# Show help
help:
	@echo "FajarOS Nova — Build Targets"
	@echo ""
	@echo "  make build     Build kernel ELF"
	@echo "  make run       Run in QEMU (serial, no KVM)"
	@echo "  make run-kvm   Run in QEMU with KVM acceleration"
	@echo "  make run-vga   Run in QEMU with VGA display"
	@echo "  make run-smp   Run in QEMU with 4 CPU cores"
	@echo "  make debug     Run in QEMU with GDB server"
	@echo "  make iso       Create bootable GRUB2 ISO"
	@echo "  make run-iso   Boot from ISO in QEMU"
	@echo "  make test      Run tests in QEMU"
	@echo "  make clean     Remove build artifacts"
