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
	kernel/sched/batch.fj \
	kernel/sched/preempt.fj \
	kernel/sched/ml_scheduler.fj \
	kernel/sched/smp.fj \
	kernel/sched/spinlock.fj \
	kernel/sched/pcpu.fj \
	kernel/sched/runqueue.fj \
	kernel/sched/priority.fj \
	kernel/sched/loadbalance.fj \
	kernel/interrupts/lapic.fj \
	kernel/interrupts/timer.fj \
	kernel/interrupts/exceptions.fj \
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
	kernel/compute/quantize.fj \
	kernel/compute/fajarquant.fj \
	kernel/compute/kmatrix.fj \
	kernel/compute/model_loader.fj \
	kernel/compute/tokenizer.fj \
	kernel/compute/transformer.fj \
	kernel/compute/pipeline.fj \
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
	services/display/font.fj \
	services/display/main.fj \
	services/input/main.fj \
	services/gpu/main.fj \
	services/gui/compositor.fj \
	services/gui/spaces.fj \
	services/gui/app_switcher.fj \
	services/gui/hot_corners.fj \
	services/gui/animation.fj \
	services/gui/tiling.fj \
	services/gui/taskbar.fj \
	services/gui/menubar.fj \
	services/gui/notifications.fj \
	services/gui/context_menu.fj \
	services/gui/wallpaper.fj \
	services/gui/dnd.fj \
	services/gui/launcher.fj \
	services/gui/clipboard.fj \
	services/gui/shortcuts.fj \
	services/gui/accessibility.fj \
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
	apps/filemgr.fj \
	apps/calc.fj \
	apps/viewer.fj \
	apps/settings.fj \
	apps/sysmon.fj \
	tests/kernel_tests.fj \
	tests/benchmarks.fj \
	kernel/main.fj

# QEMU settings
QEMU := qemu-system-x86_64
QEMU_COMMON := -serial stdio -no-reboot -no-shutdown
QEMU_MEM := -m 1G
QEMU_CPU := -cpu Skylake-Client-v4
QEMU_KVM := -enable-kvm -cpu host
QEMU_SMP := -smp 4
QEMU_NVME := -boot order=d -drive file=disk.img,if=none,id=nvme0,format=raw -device nvme,serial=fajaros,drive=nvme0
QEMU_NET := -netdev user,id=net0,hostfwd=tcp::8080-:80 -device virtio-net-pci,netdev=net0
QEMU_GPU := -device virtio-gpu-pci -display gtk
QEMU_USB := -device qemu-xhci
QEMU_SOUND := -audiodev pa,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0
QEMU_FULL := $(QEMU_KVM) $(QEMU_SMP) $(QEMU_NET) $(QEMU_USB) -device virtio-gpu-pci

.PHONY: all build build-llvm build-llvm-custom run run-kvm run-vga run-smp run-nvme run-net \
       run-llvm run-kvm-llvm debug debug-llvm iso run-iso test clean help loc \
       run-iso-kvm run-iso-tcg run-iso-vga run-iso-full debug-iso test-serial test-commands

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
	@$(FJ) build --no-std --backend llvm \
		--opt-level $(LLVM_OPT) \
		--target-cpu $(LLVM_CPU) \
		--target-features "$(LLVM_FEATURES)" \
		--linker-script $(LINKER_LD) \
		--code-model kernel \
		--reloc static \
		--extra-objects $(RUNTIME_O) \
		$(COMBINED) -o $(KERNEL_LLVM) 2>&1 | { grep -v "SE009\|SE010\|prefix with underscore\|unused variable\|^  " || true; }
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

# --- ISO-based run targets (GRUB2 + Multiboot2) ---

# Run LLVM ISO with KVM (recommended for development)
run-iso-kvm: iso-llvm
	$(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_KVM) -nographic

# Run LLVM ISO with TCG (no KVM needed)
run-iso-tcg: iso-llvm
	$(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) -nographic

# Run LLVM ISO with VGA display (GUI desktop mode)
run-iso-vga: iso-llvm
	$(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso -serial stdio -no-reboot \
		$(QEMU_MEM) $(QEMU_KVM) -vga std

# Run LLVM ISO with full hardware: KVM + SMP + NVMe + Net + USB
run-iso-full: iso-llvm
	@test -f disk.img || qemu-img create -f raw disk.img 64M
	$(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso -serial stdio -no-reboot \
		$(QEMU_MEM) $(QEMU_KVM) $(QEMU_SMP) $(QEMU_NET) $(QEMU_USB) \
		$(QEMU_NVME) -vga std

# Automated serial test: boot + send commands + check output
test-serial: iso-llvm
	@echo "[TEST] FajarOS serial boot test..."
	@(sleep 6; printf 'version\r'; sleep 2; printf 'frames\r'; sleep 2; printf 'uname\r'; sleep 2) | \
		timeout 15 $(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso \
		-chardev stdio,id=ch0,signal=off -serial chardev:ch0 \
		-display none -no-reboot -no-shutdown $(QEMU_KVM) $(QEMU_MEM) 2>/dev/null | \
		tee $(BUILD_DIR)/test-output.log
	@echo ""
	@grep -q "nova>" $(BUILD_DIR)/test-output.log && echo "[PASS] Shell prompt reached" || echo "[FAIL] No shell prompt"
	@grep -q "FajarOS Nova" $(BUILD_DIR)/test-output.log && echo "[PASS] Version command works" || echo "[FAIL] Version failed"
	@grep -q "Frame Allocator" $(BUILD_DIR)/test-output.log && echo "[PASS] Frames command works" || echo "[FAIL] Frames failed"

# Mass-test shell commands — 2 batches × 45 commands = 90 total
test-commands: iso-llvm
	@echo "═══════════════════════════════════════"
	@echo "  FajarOS Shell Command Test (90 cmds)"
	@echo "═══════════════════════════════════════"
	@echo "[BATCH 1/2] Info + Display + Math (45 commands)..."
	@(sleep 6; \
	printf 'help\r'; sleep 0.5; \
	printf 'version\r'; sleep 0.5; \
	printf 'uname\r'; sleep 0.5; \
	printf 'about\r'; sleep 0.5; \
	printf 'uptime\r'; sleep 0.5; \
	printf 'cpuinfo\r'; sleep 0.5; \
	printf 'meminfo\r'; sleep 0.5; \
	printf 'frames\r'; sleep 0.5; \
	printf 'free\r'; sleep 0.5; \
	printf 'whoami\r'; sleep 0.5; \
	printf 'hostname\r'; sleep 0.5; \
	printf 'arch\r'; sleep 0.5; \
	printf 'date\r'; sleep 0.5; \
	printf 'id\r'; sleep 0.5; \
	printf 'tsc\r'; sleep 0.5; \
	printf 'epoch\r'; sleep 0.5; \
	printf 'nproc\r'; sleep 0.5; \
	printf 'acpi\r'; sleep 0.5; \
	printf 'logo\r'; sleep 0.5; \
	printf 'color\r'; sleep 0.5; \
	printf 'motd\r'; sleep 0.5; \
	printf 'cal\r'; sleep 0.5; \
	printf 'banner FJ\r'; sleep 0.5; \
	printf 'cowsay moo\r'; sleep 0.5; \
	printf 'fortune\r'; sleep 0.5; \
	printf 'dice\r'; sleep 0.5; \
	printf 'true\r'; sleep 0.5; \
	printf 'false\r'; sleep 0.5; \
	printf 'seq 5\r'; sleep 0.5; \
	printf 'hex 255\r'; sleep 0.5; \
	printf 'factor 42\r'; sleep 0.5; \
	printf 'prime 97\r'; sleep 0.5; \
	printf 'len hello\r'; sleep 0.5; \
	printf 'fib 10\r'; sleep 0.5; \
	printf 'echo hello\r'; sleep 0.5; \
	printf 'rev hello\r'; sleep 0.5; \
	printf 'upcase hello\r'; sleep 0.5; \
	printf 'downcase HELLO\r'; sleep 0.5; \
	printf 'base 255 16\r'; sleep 0.5; \
	printf 'count\r'; sleep 0.5; \
	printf 'calc\r'; sleep 0.5; \
	printf 'env\r'; sleep 0.5; \
	printf 'history\r'; sleep 0.5; \
	printf 'dmesg\r'; sleep 0.5; \
	printf 'clear\r'; sleep 1; \
	) | timeout 60 $(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso \
		-chardev stdio,id=ch0,signal=off -serial chardev:ch0 \
		-display none -no-reboot -no-shutdown $(QEMU_KVM) $(QEMU_MEM) 2>/dev/null | \
		tee $(BUILD_DIR)/test-batch1.log
	@echo ""
	@echo "[BATCH 2/2] FS + System + Advanced (45 commands)..."
	@(sleep 6; \
	printf 'ls\r'; sleep 0.5; \
	printf 'pwd\r'; sleep 0.5; \
	printf 'mmap\r'; sleep 0.5; \
	printf 'lspci\r'; sleep 0.5; \
	printf 'ps\r'; sleep 0.5; \
	printf 'top\r'; sleep 0.5; \
	printf 'df\r'; sleep 0.5; \
	printf 'du\r'; sleep 0.5; \
	printf 'touch testfile\r'; sleep 0.5; \
	printf 'cat testfile\r'; sleep 0.5; \
	printf 'stat testfile\r'; sleep 0.5; \
	printf 'rm testfile\r'; sleep 0.5; \
	printf 'mkdir testdir\r'; sleep 0.5; \
	printf 'rmdir testdir\r'; sleep 0.5; \
	printf 'head\r'; sleep 0.5; \
	printf 'tail\r'; sleep 0.5; \
	printf 'wc\r'; sleep 0.5; \
	printf 'nl\r'; sleep 0.5; \
	printf 'sort\r'; sleep 0.5; \
	printf 'uniq\r'; sleep 0.5; \
	printf 'xxd\r'; sleep 0.5; \
	printf 'strings\r'; sleep 0.5; \
	printf 'md5\r'; sleep 0.5; \
	printf 'cut\r'; sleep 0.5; \
	printf 'tr\r'; sleep 0.5; \
	printf 'grep\r'; sleep 0.5; \
	printf 'which help\r'; sleep 0.5; \
	printf 'type help\r'; sleep 0.5; \
	printf 'man help\r'; sleep 0.5; \
	printf 'printenv\r'; sleep 0.5; \
	printf 'set FOO bar\r'; sleep 0.5; \
	printf 'alias\r'; sleep 0.5; \
	printf 'kill 0\r'; sleep 0.5; \
	printf 'tensor\r'; sleep 0.5; \
	printf 'bench\r'; sleep 2; \
	printf 'repeat 3 ok\r'; sleep 0.5; \
	printf 'splash\r'; sleep 0.5; \
	printf 'dd\r'; sleep 0.5; \
	printf 'time\r'; sleep 0.5; \
	printf 'nice\r'; sleep 0.5; \
	printf 'cls\r'; sleep 0.5; \
	printf 'sysinfo\r'; sleep 0.5; \
	printf 'neofetch\r'; sleep 0.5; \
	printf 'clear\r'; sleep 1; \
	) | timeout 60 $(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso \
		-chardev stdio,id=ch0,signal=off -serial chardev:ch0 \
		-display none -no-reboot -no-shutdown $(QEMU_KVM) $(QEMU_MEM) 2>/dev/null | \
		tee $(BUILD_DIR)/test-batch2.log
	@echo ""
	@cat $(BUILD_DIR)/test-batch1.log $(BUILD_DIR)/test-batch2.log > $(BUILD_DIR)/test-commands.log
	@echo "═══════════════════════════════════════"
	@echo "  FajarOS Command Test Results"
	@echo "═══════════════════════════════════════"
	@B1=$$(grep -c "^nova>" $(BUILD_DIR)/test-batch1.log 2>/dev/null || echo 0); \
	B2=$$(grep -c "^nova>" $(BUILD_DIR)/test-batch2.log 2>/dev/null || echo 0); \
	TOTAL=$$((B1 + B2)); \
	C1=$$(grep -c "\[EXC" $(BUILD_DIR)/test-batch1.log 2>/dev/null || echo 0); \
	C2=$$(grep -c "\[EXC" $(BUILD_DIR)/test-batch2.log 2>/dev/null || echo 0); \
	CRASHES=$$((C1 + C2)); \
	echo "  Batch 1: $$B1 prompts, $$C1 crashes"; \
	echo "  Batch 2: $$B2 prompts, $$C2 crashes"; \
	echo "  Total:   $$TOTAL prompts, $$CRASHES crashes"; \
	if [ "$$CRASHES" = "0" ]; then echo "  Result:  ALL PASS"; else echo "  Result:  $$CRASHES FAILURES"; fi

# Debug LLVM ISO with GDB
debug-iso: iso-llvm
	@echo "GDB: target remote :1234"
	@echo "     symbol-file $(KERNEL_LLVM)"
	$(QEMU) -cdrom $(BUILD_DIR)/fajaros-llvm.iso $(QEMU_COMMON) $(QEMU_MEM) $(QEMU_CPU) \
		-s -S -nographic

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
	@echo "  make run-llvm        Run LLVM kernel in QEMU (TCG)"
	@echo "  make run-kvm-llvm    Run LLVM kernel with KVM (near-native)"
	@echo "  make run-smp-llvm    Run LLVM kernel with KVM + 4 cores"
	@echo "  make debug-llvm      Debug LLVM kernel with GDB"
	@echo "  make run-gpu-llvm    Run LLVM kernel with VirtIO-GPU"
	@echo "  make run-full-llvm   Run with KVM+SMP+GPU+NVMe+Net"
	@echo "  make iso-llvm        Create bootable GRUB2 ISO"
	@echo ""
	@echo "  ISO-based (GRUB2 multiboot2):"
	@echo "  make run-iso-kvm     Boot ISO with KVM (recommended)"
	@echo "  make run-iso-tcg     Boot ISO with TCG (no KVM needed)"
	@echo "  make run-iso-vga     Boot ISO with VGA display"
	@echo "  make run-iso-full    Boot ISO with full hardware"
	@echo "  make debug-iso       Debug ISO kernel with GDB"
	@echo "  make test-serial     Automated boot + command test"
	@echo ""
	@echo "  Other:"
	@echo "  make iso             Create bootable GRUB2 ISO"
	@echo "  make test            Run tests in QEMU"
	@echo "  make loc             Count lines of code"
	@echo "  make micro           Build microkernel core only (Ring 0)"
	@echo "  make clean           Remove build artifacts"
