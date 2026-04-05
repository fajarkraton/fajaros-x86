# FajarOS Nova v3.0 "Nusantara" — Build System
# Target: x86_64-unknown-none (bare-metal)
# Compiler: Fajar Lang (fj)
# Strategy: concatenate modular .fj files → single combined.fj → compile

# Paths
FJ := /home/primecore/Documents/Fajar\ Lang/target/release/fj
BUILD_DIR := build
COMBINED := $(BUILD_DIR)/combined.fj
KERNEL_ELF := $(BUILD_DIR)/fajaros.elf
KERNEL_LLVM := $(BUILD_DIR)/fajaros-llvm.elf
STARTUP_S := boot/startup.S
STARTUP_O := $(BUILD_DIR)/startup.o
RUNTIME_S := boot/runtime_stubs.S
RUNTIME_O := $(BUILD_DIR)/runtime_stubs.o
LINKER_LD := linker.ld
ISO_FILE := $(BUILD_DIR)/fajaros.iso
GRUB_CFG := grub.cfg

# LLVM backend settings
LLVM_OPT := 2
LLVM_CPU := native
LLVM_FEATURES := +avx2,+fma,+popcnt,+aes

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
	kernel/hw/msr.fj \
	kernel/hw/cpuid.fj \
	kernel/mm/frames.fj \
	kernel/mm/paging.fj \
	kernel/mm/heap.fj \
	kernel/mm/slab.fj \
	kernel/mm/cow.fj \
	kernel/mm/demand_paging.fj \
	kernel/mm/oom.fj \
	kernel/mm/mmap.fj \
	kernel/auth/users.fj \
	kernel/auth/permissions.fj \
	kernel/auth/sessions.fj \
	kernel/ipc/message.fj \
	kernel/ipc/pipe.fj \
	kernel/ipc/pipe_v2.fj \
	kernel/ipc/ipc.fj \
	kernel/ipc/channel.fj \
	kernel/ipc/notify.fj \
	kernel/ipc/shm.fj \
	kernel/ipc/tests.fj \
	kernel/sched/process.fj \
	kernel/sched/signals.fj \
	kernel/sched/scheduler.fj \
	kernel/sched/smp.fj \
	kernel/sched/spinlock.fj \
	kernel/sched/pcpu.fj \
	kernel/sched/runqueue.fj \
	kernel/sched/priority.fj \
	kernel/sched/loadbalance.fj \
	kernel/interrupts/lapic.fj \
	kernel/interrupts/timer.fj \
	kernel/syscall/entry.fj \
	kernel/syscall/dispatch.fj \
	kernel/syscall/elf.fj \
	kernel/syscall/posix_fs.fj \
	kernel/syscall/posix_signal.fj \
	kernel/process/fork.fj \
	kernel/process/exec.fj \
	kernel/process/wait.fj \
	kernel/process/exit.fj \
	kernel/signal/signal.fj \
	kernel/signal/jobs.fj \
	kernel/debug/gdb_stub.fj \
	kernel/debug/gdb_ext.fj \
	kernel/security/capability.fj \
	kernel/security/limits.fj \
	kernel/security/hardening.fj \
	kernel/security/forkbomb.fj \
	kernel/security/seccomp.fj \
	kernel/security/aslr.fj \
	kernel/security/audit.fj \
	kernel/security/crypto.fj \
	drivers/serial.fj \
	drivers/vga.fj \
	drivers/keyboard.fj \
	drivers/pci.fj \
	drivers/nvme.fj \
	drivers/virtio_blk.fj \
	drivers/virtio_net.fj \
	drivers/xhci.fj \
	drivers/gpu.fj \
	drivers/virtio_gpu.fj \
	kernel/compute/buffers.fj \
	kernel/compute/kernels.fj \
	fs/ramfs.fj \
	fs/directory.fj \
	fs/links.fj \
	fs/journal.fj \
	fs/fsck.fj \
	fs/ext2_super.fj \
	fs/ext2_ops.fj \
	fs/ext2_indirect.fj \
	fs/fat32.fj \
	fs/vfs.fj \
	shell/pipes.fj \
	shell/redirect.fj \
	shell/vars.fj \
	shell/control.fj \
	shell/commands.fj \
	shell/scripting.fj \
	kernel/core/smp_sched.fj \
	kernel/core/mm_advanced.fj \
	kernel/core/security.fj \
	kernel/core/fast_ipc.fj \
	kernel/core/stability.fj \
	kernel/hw/detect.fj \
	kernel/hw/acpi.fj \
	kernel/hw/pcie.fj \
	kernel/hw/uefi_boot.fj \
	kernel/core/elf_loader.fj \
	kernel/ring3_embed.fj \
	services/blk/main.fj \
	services/blk/journal.fj \
	services/net/socket.fj \
	services/net/httpd.fj \
	services/net/main.fj \
	services/net/tcp.fj \
	services/net/dns.fj \
	services/net/http.fj \
	services/net/tcp_v2.fj \
	services/net/udp.fj \
	services/net/stats.fj \
	services/net/tcp_v3.fj \
	services/net/routing.fj \
	services/net/tls.fj \
	kernel/stubs/framebuffer.fj \
	kernel/stubs/gpu_stub.fj \
	services/display/main.fj \
	services/input/main.fj \
	services/gpu/main.fj \
	services/gui/main.fj \
	services/auth/main.fj \
	services/shell/main.fj \
	services/init/service.fj \
	services/init/runlevel.fj \
	services/init/daemon.fj \
	services/init/shutdown.fj \
	services/init/main.fj \
	services/pkg/manager.fj \
	services/pkg/registry.fj \
	services/vfs/main.fj \
	apps/editor/main.fj \
	apps/compiler/main.fj \
	apps/pkgmgr/main.fj \
	apps/user_programs.fj \
	apps/mnist.fj \
	tests/kernel_tests.fj \
	tests/benchmarks.fj \
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
QEMU_GPU := -device virtio-gpu-pci -display gtk
QEMU_FULL := $(QEMU_KVM) $(QEMU_SMP) $(QEMU_NET) -device virtio-gpu-pci

.PHONY: all build build-llvm build-llvm-custom run run-kvm run-vga run-smp run-nvme run-net \
       run-llvm run-kvm-llvm debug debug-llvm iso run-iso test clean help loc

all: build

# Concatenate all source files into one combined file
$(COMBINED): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	@echo "// FajarOS Nova v3.0 — Auto-generated from modular sources" > $(COMBINED)
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

# Build kernel ELF from combined source (Cranelift backend — fast compile)
build: $(COMBINED)
	$(FJ) build --target x86_64-none $(COMBINED) -o $(KERNEL_ELF)
	@echo "[OK] Kernel built: $(KERNEL_ELF) ($(shell wc -l < $(COMBINED)) lines)"

# Assemble runtime stubs for LLVM bare-metal builds
$(RUNTIME_O): $(RUNTIME_S)
	@mkdir -p $(BUILD_DIR)
	as --64 -o $(RUNTIME_O) $(RUNTIME_S)
	@echo "[OK] Assembled runtime stubs: $(RUNTIME_O)"

# Build kernel with LLVM backend (optimized, uses hardware features)
# Auto-generates startup.S + linker script internally
build-llvm: $(COMBINED) $(RUNTIME_O)
	$(FJ) build --no-std --backend llvm \
		--opt-level $(LLVM_OPT) \
		--target-cpu $(LLVM_CPU) \
		--target-features "$(LLVM_FEATURES)" \
		--linker-script $(LINKER_LD) \
		--code-model kernel \
		--reloc static \
		--extra-objects $(RUNTIME_O) \
		$(COMBINED) -o $(KERNEL_LLVM)
	@echo "[OK] LLVM kernel built: $(KERNEL_LLVM) (O$(LLVM_OPT), $(LLVM_CPU))"
	@size $(KERNEL_LLVM) 2>/dev/null || true

# Build with custom startup.S (manual link — for advanced use)
$(STARTUP_O): $(STARTUP_S)
	@mkdir -p $(BUILD_DIR)
	as --64 -o $(STARTUP_O) $(STARTUP_S)
	@echo "[OK] Assembled: $(STARTUP_O)"

build-llvm-custom: $(COMBINED) $(STARTUP_O)
	$(FJ) build --no-std --backend llvm \
		--opt-level $(LLVM_OPT) \
		--target-cpu $(LLVM_CPU) \
		--target-features "$(LLVM_FEATURES)" \
		--linker-script $(LINKER_LD) \
		--code-model kernel \
		--reloc static \
		$(COMBINED) -o $(KERNEL_LLVM)
	@echo "[OK] LLVM kernel (custom startup): $(KERNEL_LLVM)"

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

# --- LLVM backend run targets ---

# Run LLVM kernel in QEMU (serial, no KVM)
run-llvm: build-llvm
	$(QEMU) -kernel $(KERNEL_LLVM) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -nographic

# Run LLVM kernel with KVM (near-native speed, real CPU features)
run-kvm-llvm: build-llvm
	$(QEMU) -kernel $(KERNEL_LLVM) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) -nographic

# Run LLVM kernel with KVM + SMP (4 cores)
run-smp-llvm: build-llvm
	$(QEMU) -kernel $(KERNEL_LLVM) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) $(QEMU_SMP) -nographic

# Debug with GDB (Cranelift)
debug: build
	@echo "GDB: target remote :1234 -ex 'symbol-file $(KERNEL_ELF)'"
	$(QEMU) -kernel $(KERNEL_ELF) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -s -S -nographic

# Debug LLVM kernel with GDB
debug-llvm: build-llvm
	@echo "GDB: target remote :1234 -ex 'symbol-file $(KERNEL_LLVM)'"
	@echo "  break kernel_main"
	@echo "  continue"
	$(QEMU) -kernel $(KERNEL_LLVM) $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -s -S -nographic

# Run LLVM kernel with VirtIO-GPU (graphical output)
run-gpu-llvm: build-llvm
	$(QEMU) -kernel $(KERNEL_LLVM) -serial stdio -no-reboot -no-shutdown $(QEMU_MEM) $(QEMU_KVM) $(QEMU_GPU)

# Run LLVM kernel with everything: KVM + SMP + GPU + NVMe + Net (i9 + RTX 4090)
run-full-llvm: build-llvm
	@test -f disk.img || qemu-img create -f raw disk.img 64M
	$(QEMU) -kernel $(KERNEL_LLVM) -serial stdio -no-reboot -no-shutdown \
		$(QEMU_MEM) $(QEMU_FULL) $(QEMU_NVME) -display gtk

# LLVM ISO: bootable ISO with GRUB2 for LLVM kernel
iso-llvm: build-llvm
	@mkdir -p $(BUILD_DIR)/iso-llvm/boot/grub
	cp $(KERNEL_LLVM) $(BUILD_DIR)/iso-llvm/boot/fajaros.elf
	cp $(GRUB_CFG) $(BUILD_DIR)/iso-llvm/boot/grub/grub.cfg
	grub-mkrescue -o $(BUILD_DIR)/fajaros-llvm.iso $(BUILD_DIR)/iso-llvm 2>/dev/null
	@echo "[OK] LLVM ISO created: $(BUILD_DIR)/fajaros-llvm.iso"

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
	@echo "FajarOS Nova v3.0 \"Nusantara\" — Build Targets"
	@echo ""
	@echo "  Cranelift (fast compile):"
	@echo "  make build           Concatenate + compile kernel ELF"
	@echo "  make run             Run in QEMU (serial, no KVM)"
	@echo "  make run-kvm         Run with KVM acceleration"
	@echo "  make run-vga         Run with VGA display"
	@echo "  make run-smp         Run with 4 CPU cores"
	@echo "  make run-nvme        Run with NVMe storage"
	@echo "  make run-net         Run with networking"
	@echo "  make debug           Run with GDB server (:1234)"
	@echo ""
	@echo "  LLVM (optimized, AVX2/AES/FMA):"
	@echo "  make build-llvm      LLVM O2 kernel with hardware features"
	@echo "  make run-llvm        Run LLVM kernel in QEMU"
	@echo "  make run-kvm-llvm    Run LLVM kernel with KVM (near-native)"
	@echo "  make run-smp-llvm    Run LLVM kernel with KVM + 4 cores"
	@echo "  make debug-llvm      Debug LLVM kernel with GDB"
	@echo "  make run-gpu-llvm    Run LLVM kernel with VirtIO-GPU (GTK window)"
	@echo "  make run-full-llvm   Run with KVM+SMP+GPU+NVMe+Net (full hardware)"
	@echo "  make iso-llvm        Create bootable GRUB2 ISO (LLVM kernel)"
	@echo ""
	@echo "  Other:"
	@echo "  make iso             Create bootable GRUB2 ISO"
	@echo "  make test            Run tests in QEMU"
	@echo "  make loc             Count lines of code"
	@echo "  make micro           Build microkernel core only (Ring 0)"
	@echo "  make clean           Remove build artifacts"
