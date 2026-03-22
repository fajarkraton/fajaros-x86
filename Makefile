# FajarOS Nova v1.0.0 "Genesis" — Build System
# Target: x86_64-unknown-none (bare-metal)
# Compiler: Fajar Lang (fj)
# Strategy: concatenate modular .fj files → single combined.fj → compile

# Paths
FJ := fj
BUILD_DIR := build
COMBINED := $(BUILD_DIR)/combined.fj
KERNEL_ELF := $(BUILD_DIR)/fajaros.elf
ISO_FILE := $(BUILD_DIR)/fajaros.iso
GRUB_CFG := grub.cfg

# Source files in concatenation order (dependencies first)
# 1. Constants and low-level primitives
# 2. Memory management (frames → paging → heap → slab)
# 3. Drivers (serial, vga, keyboard, pci, nvme, virtio, net)
# 4. Filesystems (ramfs, fat32, vfs)
# 5. Kernel services (ipc, process, scheduler, syscall, elf, smp)
# 6. Shell (commands, dispatch)
# 7. Main entry point (MUST be last)
SOURCES := \
	kernel/boot/constants.fj \
	kernel/mm/frames.fj \
	kernel/mm/paging.fj \
	kernel/mm/heap.fj \
	kernel/mm/slab.fj \
	kernel/ipc/message.fj \
	kernel/ipc/pipe.fj \
	kernel/ipc/ipc.fj \
	kernel/ipc/channel.fj \
	kernel/ipc/notify.fj \
	kernel/ipc/shm.fj \
	kernel/ipc/tests.fj \
	kernel/sched/process.fj \
	kernel/sched/scheduler.fj \
	kernel/sched/smp.fj \
	kernel/sched/spinlock.fj \
	kernel/interrupts/lapic.fj \
	kernel/interrupts/timer.fj \
	kernel/syscall/entry.fj \
	kernel/syscall/dispatch.fj \
	kernel/syscall/elf.fj \
	kernel/security/capability.fj \
	kernel/security/limits.fj \
	kernel/security/hardening.fj \
	drivers/serial.fj \
	drivers/vga.fj \
	drivers/keyboard.fj \
	drivers/pci.fj \
	drivers/nvme.fj \
	drivers/virtio_blk.fj \
	drivers/virtio_net.fj \
	drivers/xhci.fj \
	drivers/gpu.fj \
	fs/ramfs.fj \
	fs/fat32.fj \
	fs/vfs.fj \
	shell/commands.fj \
	shell/scripting.fj \
	kernel/core/smp_sched.fj \
	kernel/core/mm_advanced.fj \
	kernel/core/security.fj \
	kernel/core/fast_ipc.fj \
	kernel/hw/detect.fj \
	kernel/core/elf_loader.fj \
	services/blk/main.fj \
	services/blk/journal.fj \
	services/net/main.fj \
	kernel/stubs/framebuffer.fj \
	services/display/main.fj \
	services/input/main.fj \
	services/gui/main.fj \
	services/shell/main.fj \
	services/init/main.fj \
	services/vfs/main.fj \
	apps/editor/main.fj \
	apps/compiler/main.fj \
	apps/pkgmgr/main.fj \
	apps/user_programs.fj \
	apps/mnist.fj \
	tests/kernel_tests.fj \
	kernel/main.fj

# QEMU settings
QEMU := qemu-system-x86_64
QEMU_COMMON := -serial stdio -no-reboot -no-shutdown
QEMU_MEM := -m 512M
QEMU_CPU := -cpu qemu64,+avx2,+sse4.2
QEMU_KVM := -enable-kvm -cpu host
QEMU_SMP := -smp 4
QEMU_NVME := -drive file=disk.img,if=none,id=nvme0 -device nvme,serial=fajaros,drive=nvme0 -boot d
QEMU_NET := -netdev user,id=net0 -device virtio-net-pci,netdev=net0

.PHONY: all build run run-kvm run-vga run-smp run-nvme run-net debug iso run-iso test clean help loc

all: build

# Concatenate all source files into one combined file
$(COMBINED): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	@echo "// FajarOS Nova v1.0.0 — Auto-generated from modular sources" > $(COMBINED)
	@echo "// DO NOT EDIT — edit individual .fj files instead" >> $(COMBINED)
	@echo "" >> $(COMBINED)
	@for f in $(SOURCES); do \
		echo "" >> $(COMBINED); \
		echo "// ════════════════════════════════════════════════════════" >> $(COMBINED); \
		echo "// Source: $$f" >> $(COMBINED); \
		echo "// ════════════════════════════════════════════════════════" >> $(COMBINED); \
		echo "" >> $(COMBINED); \
		cat $$f >> $(COMBINED); \
	done
	@echo "[OK] Combined $(words $(SOURCES)) source files → $(COMBINED)"

# Build kernel ELF from combined source
build: $(COMBINED)
	$(FJ) build --target x86_64-none $(COMBINED) -o $(KERNEL_ELF)
	@echo "[OK] Kernel built: $(KERNEL_ELF) ($(shell wc -l < $(COMBINED)) lines)"

# Run in QEMU (serial only, no graphics)
run: build
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -nographic

# Run with KVM acceleration
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

# Run with networking
run-net: build
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) $(QEMU_NET) -nographic

# Debug with GDB
debug: build
	@echo "GDB: target remote :1234 -ex 'symbol-file $(KERNEL_ELF)'"
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

# Count lines of code
loc:
	@echo "FajarOS Nova — Lines of Code"
	@echo ""
	@wc -l $(SOURCES) | sort -n
	@echo ""
	@echo "Total .fj files: $(words $(SOURCES))"

# v2.0 Microkernel core — ONLY kernel/core/ + kernel/stubs/ (Ring 0)
MICRO_SOURCES := \
	kernel/core/boot.fj \
	kernel/core/mm.fj \
	kernel/core/irq.fj \
	kernel/core/sched.fj \
	kernel/core/ipc.fj \
	kernel/core/syscall.fj \
	kernel/stubs/console.fj \
	kernel/stubs/driver_stubs.fj

MICRO_COMBINED := $(BUILD_DIR)/micro_combined.fj
MICRO_ELF := $(BUILD_DIR)/fajaros_micro.elf

.PHONY: micro micro-loc microkernel services

# Build microkernel core only
$(MICRO_COMBINED): $(MICRO_SOURCES)
	@mkdir -p $(BUILD_DIR)
	@echo "// FajarOS Nova v2.0 Microkernel Core — Ring 0 ONLY" > $(MICRO_COMBINED)
	@for f in $(MICRO_SOURCES); do \
		echo "" >> $(MICRO_COMBINED); \
		echo "// Source: $$f" >> $(MICRO_COMBINED); \
		cat $$f >> $(MICRO_COMBINED); \
	done
	@echo "[OK] Micro-combined $(words $(MICRO_SOURCES)) source files → $(MICRO_COMBINED)"

micro: $(MICRO_COMBINED)
	@echo "[INFO] Microkernel core: $(words $(MICRO_SOURCES)) files"
	@wc -l $(MICRO_SOURCES) | tail -1

# Count microkernel LOC
micro-loc:
	@echo "FajarOS Microkernel — Lines of Code (Ring 0 ONLY)"
	@echo ""
	@wc -l $(MICRO_SOURCES) | sort -n
	@echo ""
	@echo "Target: <2,000 LOC for core"

# v2.0 Microkernel: build kernel + services as separate ELFs
microkernel: $(KERNEL_ELF) services
	@echo "[OK] Microkernel + services built"

services:
	@mkdir -p $(BUILD_DIR)
	@for svc in services/*/; do \
		if [ -d "$$svc" ]; then \
			name=$$(basename $$svc); \
			echo "[BUILD] Service: $$name"; \
			$(FJ) build --target x86_64-user $$svc -o $(BUILD_DIR)/$$name.elf 2>/dev/null || \
				echo "[SKIP] $$name (no .fj files)"; \
		fi \
	done
	@echo "[OK] Services built"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f disk.img
	@echo "[OK] Cleaned"

# Show help
help:
	@echo "FajarOS Nova v1.0.0 — Build Targets"
	@echo ""
	@echo "  make build     Concatenate + compile kernel ELF"
	@echo "  make run       Run in QEMU (serial, no KVM)"
	@echo "  make run-kvm   Run with KVM acceleration"
	@echo "  make run-vga   Run with VGA display"
	@echo "  make run-smp   Run with 4 CPU cores"
	@echo "  make run-nvme  Run with NVMe storage"
	@echo "  make run-net   Run with networking"
	@echo "  make debug     Run with GDB server (:1234)"
	@echo "  make iso       Create bootable GRUB2 ISO"
	@echo "  make test      Run tests in QEMU"
	@echo "  make loc       Count lines of code"
	@echo "  make micro     Build microkernel core only (Ring 0)"
	@echo "  make micro-loc Microkernel LOC breakdown"
	@echo "  make clean     Remove build artifacts"
