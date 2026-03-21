# FajarOS Nova v1.0.0 "Genesis" — x86_64 Operating System in Fajar Lang

> The world's first OS written 100% in [Fajar Lang](https://github.com/fajarkraton/fajar-lang)
> that natively unifies kernel safety, hardware drivers, and AI inference —
> targeting Intel x86_64 processors.

**Codename:** "Nova" (Indonesian: bintang baru — a new star)

## Highlights

| Metric | Value |
|--------|-------|
| **LOC** | 11,615 lines of Fajar Lang |
| **Commands** | 160+ shell commands |
| **Files** | 35 modular `.fj` source files |
| **Scheduler** | Preemptive multitasking (timer-driven context switch) |
| **Ring 3** | 3 user programs run + return to kernel via SYSCALL |
| **Memory** | Per-process page tables (CR3 switch), page fault handler |
| **Storage** | NVMe + USB Mass Storage (XHCI→SCSI) + FAT32 + VFS |
| **Network** | DHCP + ARP + IPv4 + ICMP (real ping!) + UDP + TCP + HTTP |
| **SMP** | AP trampoline, INIT-SIPI-SIPI, per-CPU |
| **AI** | MNIST classifier (784 -> 10, softmax) |
| **Process** | Init (PID 1), 16 PIDs, fork/exit/waitpid, pipes, FD table |
| **ELF** | ELF64 parser + PT_LOAD loader + exec from FAT32 |

## Target Hardware

| Component | Specification |
|-----------|--------------|
| **CPU** | Intel Core i9-14900HX (24 cores / 32 threads, 5.8 GHz) |
| **RAM** | 32 GB DDR5 |
| **GPU** | NVIDIA RTX 4090 Laptop (Ada Lovelace) |
| **Storage** | 937 GB NVMe SSD (PCIe Gen4) |
| **Platform** | Lenovo Legion Pro |

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
# Build kernel (concatenates 35 .fj files -> compile)
make build

# Run in QEMU (serial console)
make run

# Run with KVM acceleration
make run-kvm

# Run with VGA display
make run-vga

# Run with SMP (4 cores)
make run-smp

# Run with NVMe storage
make run-nvme

# Run with networking
make run-net

# Debug with GDB
make debug

# Count lines of code
make loc
```

### Expected Output

```
[NOVA] FajarOS Nova v1.0.0 Genesis booted
[NOVA] 11600+ LOC | 160 commands | Preemptive | 100% Fajar Lang
[NOVA] Frame allocator: 32768 frames (128MB)
[NOVA] RamFS: 64 entries, 832KB data
============================================
  FajarOS Nova v1.0.0 — x86_64 Shell
  Written 100% in Fajar Lang
============================================

Type 'help' for available commands.

nova> _
```

## Architecture

```
+---------------------------------------------+
|  Applications (@safe)         — Ring 3       |
|  Shell, MNIST, user programs, login          |
+---------------------------------------------+
|  OS Services (@safe + @device)               |
|  VFS, ramfs, FAT32, process manager, IPC     |
+---------------------------------------------+
|  HAL Drivers (@kernel)        — Ring 0       |
|  Serial, VGA, Keyboard, PCI, NVMe, Net, USB |
+---------------------------------------------+
|  Microkernel (@kernel)        — Ring 0       |
|  GDT/IDT, paging, LAPIC, scheduler, syscall  |
+---------------------------------------------+
|  Hardware — Intel Core i9-14900HX            |
|  24-core, RTX 4090, 32GB DDR5, NVMe         |
+---------------------------------------------+
```

## Project Structure

```
fajaros-x86/
+-- kernel/                    Microkernel (100% Fajar Lang)
|   +-- main.fj                Entry point (kernel_main + shell loop)
|   +-- boot/
|   |   +-- constants.fj       Global constants + security status
|   +-- mm/
|   |   +-- frames.fj          Bitmap frame allocator (32768 frames)
|   |   +-- paging.fj          4-level page tables (PML4)
|   |   +-- heap.fj            Freelist heap allocator
|   |   +-- slab.fj            Slab allocator (power-of-2 classes)
|   +-- interrupts/
|   |   +-- lapic.fj           LAPIC/IOAPIC constants
|   |   +-- timer.fj           sleep_ms, delay_us
|   +-- sched/
|   |   +-- process.fj         Process table v2 (16 PIDs, fork/exit/waitpid)
|   |   +-- scheduler.fj       Init process + shutdown
|   |   +-- smp.fj             SMP boot (INIT-SIPI-SIPI, AP trampoline)
|   |   +-- spinlock.fj        Test-and-set spinlock
|   +-- syscall/
|   |   +-- entry.fj           SYSCALL stub at 0x8200, MSR config
|   |   +-- dispatch.fj        Syscall table (8 syscalls)
|   |   +-- elf.fj             ELF64 parser + loader
|   +-- ipc/
|   |   +-- message.fj         IPC message queue
|   |   +-- pipe.fj            Pipe + file descriptor table
|   +-- security/
|       +-- limits.fj          Resource limits + LAPIC/IRQ commands
|       +-- hardening.fj       FPU, Ring 3, RDRAND
+-- drivers/                   Device drivers (100% Fajar Lang)
|   +-- serial.fj              16550 UART (COM1, 115200 baud)
|   +-- vga.fj                 VGA console engine (80x25, color)
|   +-- keyboard.fj            PS/2 keyboard + shift/caps lock
|   +-- pci.fj                 PCI bus enumeration + lspci
|   +-- nvme.fj                NVMe block device (read/write sectors)
|   +-- virtio_blk.fj          VirtIO block device
|   +-- virtio_net.fj          Network stack (Ethernet/ARP/IPv4/ICMP)
|   +-- xhci.fj                USB 3.0 XHCI detection
|   +-- gpu.fj                 GPU detection (NVIDIA/Intel/AMD)
+-- fs/                        Filesystem
|   +-- ramfs.fj               RAM filesystem (64 entries)
|   +-- fat32.fj               FAT32 driver (read/write/delete)
|   +-- vfs.fj                 VFS layer (/dev, /proc, mount table)
+-- shell/                     Interactive shell
|   +-- commands.fj            145 built-in commands + dispatch
|   +-- scripting.fj           Shell script execution
+-- apps/                      User applications
|   +-- user_programs.fj       Ring 3 programs + login shell
|   +-- mnist.fj               MNIST classifier (reserved)
+-- docs/                      Documentation
|   +-- PLAN.md                Full 30-sprint, 300-task plan
+-- Makefile                   Build system (concat + compile)
+-- fj.toml                    Project config
+-- grub.cfg                   GRUB2 bootloader config
+-- linker.ld                  Linker script
```

## Key Features

### Memory Management
- **Frame allocator:** Bitmap-based, 32768 frames (128MB), alloc/free/contiguous
- **4-level paging:** PML4 -> PDPT -> PDT -> PT, 2MB huge pages, NX bit
- **Heap allocator:** Freelist with split/merge, kmalloc/kfree
- **Slab allocator:** Power-of-2 size classes for fast small allocations

### Process Management
- **16 PIDs:** Process table with state tracking (ready/running/blocked/zombie)
- **Fork/exit/waitpid:** Full process lifecycle
- **File descriptors:** Per-process FD table, stdin/stdout/stderr
- **Pipes:** Inter-process data streaming

### Storage & Filesystems
- **NVMe:** Full PCI detection + admin queue + I/O queue + read/write
- **FAT32:** BPB parsing, cluster chain, directory listing, file R/W
- **VFS:** Mount table, /dev (null/zero/random), /proc (version/uptime)
- **RamFS:** In-memory filesystem (64 entries, 832KB data)

### Networking
- **Virtio-Net:** PCI discovery, frame send/receive
- **Ethernet:** Frame construction + parsing
- **ARP:** Request/reply + cache table
- **IPv4:** Header construction + checksum
- **ICMP:** Echo request/reply (ping)

### Security
- **NX bit:** Execute-disable for data pages
- **Stack guard:** Unmapped page below stack
- **Ring 3:** User mode with SYSCALL/SYSRET
- **Spinlocks:** SMP-safe synchronization

## Related Projects

- [Fajar Lang](https://github.com/fajarkraton/fajar-lang) — The programming language
- [FajarOS Surya](https://github.com/fajarkraton/fajar-os) — ARM64 version (Radxa Dragon Q6A)

## License

MIT License — Copyright (c) 2026 Fajar (TaxPrime / PrimeCore.id)

---

*FajarOS "Nova" v0.5.0 "Genesis" — A new star rises on x86_64*
*9,000+ LOC | 145 commands | 35 modular files | 100% Fajar Lang*
*Built with Fajar Lang + Claude Opus 4.6*
