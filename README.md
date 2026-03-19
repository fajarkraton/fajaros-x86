# FajarOS Nova — x86_64 Operating System in Fajar Lang

> The world's first OS written 100% in [Fajar Lang](https://github.com/fajarkraton/fajar-lang)
> that natively unifies kernel safety, hardware drivers, and AI inference —
> targeting Intel x86_64 processors.

**Codename:** "Nova" (Indonesian: bintang baru — a new star)

## Target Hardware

| Component | Specification |
|-----------|--------------|
| **CPU** | Intel Core i9-14900HX (24 cores / 32 threads, 5.8 GHz) |
| **RAM** | 32 GB DDR5 |
| **GPU** | NVIDIA RTX 4090 Laptop (Ada Lovelace) |
| **Storage** | 937 GB NVMe SSD (PCIe Gen4) |
| **Platform** | Lenovo Legion Pro |

## Features

- **100% Fajar Lang** — kernel, drivers, shell, and applications
- **Compiler-enforced safety** — `@kernel`, `@device`, `@safe` context annotations
- **x86_64 native** — 4-level paging, LAPIC/IOAPIC, SYSCALL/SYSRET
- **Preemptive multitasking** — round-robin scheduler with timer-driven context switch
- **SMP ready** — multi-core support for 24-core hybrid architecture
- **AI inference** — CPU tensor ops with AVX2, MNIST demo
- **Interactive shell** — `fjsh` with 50+ built-in commands

## Architecture

```
┌─────────────────────────────────────────────┐
│  Applications (@safe)         — Ring 3       │
│  Shell, demos, AI inference                  │
├─────────────────────────────────────────────┤
│  OS Services (@safe + @device)               │
│  VFS, ramfs, process manager                 │
├─────────────────────────────────────────────┤
│  HAL Drivers (@kernel)        — Ring 0       │
│  Serial, VGA, Keyboard, PCI, NVMe            │
├─────────────────────────────────────────────┤
│  Microkernel (@kernel)        — Ring 0       │
│  GDT/IDT, paging, LAPIC, scheduler, IPC      │
├─────────────────────────────────────────────┤
│  Hardware — Intel Core i9-14900HX             │
│  24-core, RTX 4090, 32GB DDR5, NVMe          │
└─────────────────────────────────────────────┘
```

## Context Safety Model

```fajar
@kernel fn irq_handler() {
    // CAN: asm!(), port I/O, page tables, MMIO
    // CANNOT: heap strings, tensor ops — compiler rejects!
    let status = port_inb(0x3F8 + 5)
    asm!("cli")
}

@device fn classify(image: Tensor) -> i64 {
    // CAN: tensor ops, AVX2, GPU dispatch
    // CANNOT: raw pointers, IRQ — compiler rejects!
    let output = tensor_matmul(weights, image)
    tensor_argmax(tensor_softmax(output))
}

@safe fn main() {
    // CAN: syscalls, strings, collections
    // CANNOT: raw pointers, IRQ, direct hardware — compiler rejects!
    let result = classify(load_image("/data/digit_5.raw"))
    println(f"Predicted: {result}")
}
```

**"If it compiles in Fajar Lang, it's safe to deploy."**

## Quick Start

### Prerequisites

- [Fajar Lang compiler](https://github.com/fajarkraton/fajar-lang) (`fj` binary)
- QEMU x86_64: `sudo apt install qemu-system-x86`
- GRUB2 tools: `sudo apt install grub-pc-bin grub-common xorriso mtools`

### Build & Run

```bash
# Build kernel
make build

# Run in QEMU (serial console)
make run

# Run with KVM acceleration
make run-kvm

# Run with VGA display
make run-vga

# Debug with GDB
make debug
```

### Expected Output

```
FajarOS Nova v0.1.0 — Intel Core i9-14900HX
====================================================
[BOOT] Serial console initialized (COM1: 115200 baud)
[BOOT] GDT loaded (5 entries, TSS at 0x28)
[BOOT] CPU: Intel Core i9-14900HX, 24 cores, AVX2
[BOOT] Memory: 32 GB total, 28 GB usable
[BOOT] Paging: 4-level (PML4), NX enabled
[BOOT] IDT loaded (256 vectors)
[BOOT] LAPIC timer: 100 Hz
[BOOT] Scheduler: 4 processes ready
[BOOT] Shell starting...

nova> _
```

## Project Structure

```
fajaros-x86/
├── kernel/                 Microkernel (100% Fajar Lang)
│   ├── main.fj             Entry point (@kernel _start)
│   ├── boot/               GDT, Multiboot2, early console
│   ├── mm/                 Paging, heap, physical allocator
│   ├── interrupts/         IDT, LAPIC, IOAPIC, exceptions
│   ├── sched/              Scheduler, context switch, processes
│   ├── syscall/            SYSCALL/SYSRET, dispatch, handlers
│   └── ipc/                Message passing, pipes
├── drivers/                Device drivers (100% Fajar Lang)
│   ├── serial.fj           16550 UART (COM1)
│   ├── vga.fj              VGA text mode (80x25)
│   ├── keyboard.fj         PS/2 keyboard
│   ├── pci.fj              PCI bus enumeration
│   └── nvme.fj             NVMe block device
├── fs/                     Filesystem
│   ├── vfs.fj              Virtual filesystem layer
│   └── ramfs.fj            In-memory filesystem
├── shell/                  User-space shell
│   ├── fjsh.fj             Shell main loop
│   └── commands.fj         50+ built-in commands
├── apps/                   Demo applications
│   ├── hello.fj            Hello World (Ring 3)
│   ├── mnist.fj            MNIST digit classifier
│   └── sysmon.fj           System monitor
├── tools/                  Build & test scripts
├── docs/                   Documentation
└── tests/                  Test infrastructure
```

## Related Projects

- [Fajar Lang](https://github.com/fajarkraton/fajar-lang) — The programming language
- [FajarOS Surya](https://github.com/fajarkraton/fajar-os) — ARM64 version (Radxa Dragon Q6A)

## Implementation Plan

See [FAJAROS_X86_PLAN.md](../fajar-lang/docs/FAJAROS_X86_PLAN.md) for the full 30-sprint, 300-task plan.

## License

MIT License — Copyright (c) 2026 Fajar (TaxPrime / PrimeCore.id)

---

*FajarOS "Nova" — A new star rises on x86_64*
*Built with Fajar Lang + Claude Opus 4.6*
