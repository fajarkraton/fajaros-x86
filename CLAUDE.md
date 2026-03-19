# CLAUDE.md — FajarOS Nova (x86_64)

> Auto-loaded by Claude Code. Single source of truth for this repo.

## Project Identity

- **Project:** FajarOS Nova — x86_64 operating system written 100% in Fajar Lang
- **Codename:** "Nova" (Indonesian: bintang baru)
- **Target:** Intel Core i9-14900HX (Lenovo Legion Pro)
- **Language:** 100% Fajar Lang (`.fj` files)
- **Compiler:** [Fajar Lang](https://github.com/fajarkraton/fajar-lang) (`fj` binary)
- **Author:** Fajar (TaxPrime / PrimeCore.id)
- **Model:** Claude Opus 4.6 exclusively

## Architecture

- **Boot:** Multiboot2 (GRUB2 compatible)
- **Privilege:** Ring 0 (kernel) / Ring 3 (user)
- **Paging:** 4-level (PML4 → PDPT → PD → PT), 48-bit VA
- **Interrupts:** LAPIC + IOAPIC, IDT (256 vectors)
- **Syscalls:** SYSCALL/SYSRET fast path
- **Timer:** LAPIC timer, 100 Hz
- **Serial:** 16550 UART (COM1: 0x3F8)
- **Display:** VGA text mode (80×25) + Multiboot2 framebuffer

## Context Annotations

```
@kernel  → Ring 0, asm!/port I/O/MMIO allowed, no heap strings, no tensor
@device  → Compute, tensor/AVX2/GPU allowed, no raw pointers, no IRQ
@safe    → Ring 3, syscalls/strings/collections, no direct hardware
```

## Build Commands

```bash
make build          # Compile kernel (.fj → .elf)
make run            # Run in QEMU x86_64 (serial)
make run-kvm        # Run with KVM acceleration
make run-vga        # Run with VGA display
make debug          # QEMU + GDB server (port 1234)
make iso            # Create bootable ISO (GRUB2)
make clean          # Remove build artifacts
make test           # Run tests in QEMU
```

## Implementation Plan

Full plan: `docs/PLAN.md` (copied from fajar-lang/docs/FAJAROS_X86_PLAN.md)

```
Phase 1:  Foundation      [S1-S3]    Boot + serial + VGA + GDT
Phase 2:  Memory          [S4-S6]    Paging + heap + allocator
Phase 3:  Interrupts      [S7-S9]    IDT + LAPIC + timer
Phase 4:  Scheduler       [S10-S12]  Processes + context switch
Phase 5:  User Space      [S13-S15]  Ring 3 + syscalls + IPC
Phase 6:  Drivers         [S16-S18]  Keyboard + VGA + PCI
Phase 7:  FS & Shell      [S19-S21]  VFS + ramfs + fjsh (50+ cmd)
Phase 8:  SMP & Security  [S22-S24]  Multi-core + ACPI + hardening
Phase 9:  AI & GPU        [S25-S27]  Tensor + MNIST + GPU detect
Phase 10: Production      [S28-S30]  NVMe + real HW + release

Total: 30 sprints, 300 tasks
```

## Related

- **Compiler repo:** `/home/primecore/Documents/Fajar Lang`
- **ARM64 FajarOS:** `/home/primecore/Documents/FajarOS`
- **Hardware:** Lenovo Legion Pro (i9-14900HX, RTX 4090, 32GB DDR5)
- **QEMU test:** `qemu-system-x86_64 -enable-kvm -cpu host -serial stdio`

## Key Differences from FajarOS Surya (ARM64)

| Aspect | Nova (x86_64) | Surya (ARM64) |
|--------|---------------|---------------|
| Boot | Multiboot2 / GRUB | UEFI (QCS6490) |
| Privilege | Ring 0/3 | EL0/EL1 |
| Paging | CR3 → PML4 | TTBR0/TTBR1 |
| Interrupts | IDT + LAPIC | VBAR_EL1 + GICv3 |
| Syscalls | SYSCALL/SYSRET | SVC |
| Timer | LAPIC timer | Architected timer |
| Serial | 16550 I/O port | PL011 MMIO |

## Session Protocol

1. Read this CLAUDE.md (auto-loaded)
2. Read `docs/PLAN.md` for current sprint
3. Build: `make build`
4. Test: `make run`
5. Verify: `make test`
