# FajarOS Nova -- x86_64 Operating System Written 100% in Fajar Lang

[![Version](https://img.shields.io/badge/version-v3.3.0_V28_Foundation-blue)](https://github.com/fajarkraton/fajaros-x86/releases/tag/v3.3.0)
[![Files](https://img.shields.io/badge/modules-163_.fj_files-green)](https://github.com/fajarkraton/fajaros-x86)
[![LOC](https://img.shields.io/badge/LOC-106K-orange)](https://github.com/fajarkraton/fajaros-x86)
[![Compiler](https://img.shields.io/badge/compiler-Fajar_Lang_v27.5.0-blueviolet)](https://github.com/fajarkraton/fajar-lang)
[![Shell](https://img.shields.io/badge/shell-302_commands-purple)](https://github.com/fajarkraton/fajaros-x86)
[![Kernel Tests](https://img.shields.io/badge/kernel_tests-26-brightgreen)](https://github.com/fajarkraton/fajaros-x86)
[![Security](https://img.shields.io/badge/security-SMEP%2BSMAP%2BNX%2BASLR-success)](https://github.com/fajarkraton/fajaros-x86)
[![LLM E2E](https://img.shields.io/badge/LLM_E2E-SmolLM--135M_v5%2Fv6_in_kernel-success)](https://github.com/fajarkraton/fajaros-x86)
[![Ring 3](https://img.shields.io/badge/Ring_3-user_mode_works-success)](https://github.com/fajarkraton/fajaros-x86)
[![FajarQuant](https://img.shields.io/badge/FajarQuant-Phase_1%2B2_kernel_native-orange)](https://github.com/fajarkraton/fajaros-x86)
[![License](https://img.shields.io/badge/license-MIT-brightgreen)](LICENSE)
[![Made in](https://img.shields.io/badge/made_in-Indonesia-red)](https://primecore.id)

> **The world's first operating system with compiler-enforced privilege isolation.**
> Written entirely in [Fajar Lang](https://github.com/fajarkraton/fajar-lang) --
> `@kernel`, `@device`, and `@safe` annotations prevent privilege violations at compile time.
> No C. No assembly files. No other OS has this.

**Made in Indonesia** by [Fajar](https://github.com/fajarkraton) (PrimeCore.id)

---

## Why FajarOS Nova?

Most hobby operating systems are written in C or Rust with inline assembly. FajarOS Nova
takes a fundamentally different approach: every line of code -- from the bootloader constants
to the TCP state machine -- is written in **Fajar Lang**, a statically-typed systems language
designed for embedded ML and OS integration.

The key innovation is **compiler-enforced context safety**:

```fajar
@kernel fn irq_handler() {
    // Compiler ALLOWS: asm!(), port I/O, page tables, MMIO
    // Compiler REJECTS: heap strings, tensor ops
    let status = port_inb(0x3F8 + 5)
    asm!("cli")
}

@device fn classify(image: Tensor) -> i64 {
    // Compiler ALLOWS: tensor ops, AVX2, GPU dispatch
    // Compiler REJECTS: raw pointers, IRQ manipulation
    let output = tensor_matmul(weights, image)
    tensor_argmax(tensor_softmax(output))
}

@safe fn main() {
    // Compiler ALLOWS: syscalls, strings, collections
    // Compiler REJECTS: raw pointers, IRQ, direct hardware
    let result = classify(load_image("/data/digit.raw"))
    println(f"Predicted: {result}")
}
```

**"If it compiles in Fajar Lang, it's safe to deploy on hardware."**

---

## Quick Start

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| [Fajar Lang](https://github.com/fajarkraton/fajar-lang) | v7.0.0+ | `cargo install fajar-lang` |
| QEMU | 8.0+ | `sudo apt install qemu-system-x86` |
| GRUB2 | 2.0+ | `sudo apt install grub-pc-bin grub-common xorriso mtools` |
| GNU Make | 4.0+ | `sudo apt install build-essential` |

### Build and Run

```bash
git clone https://github.com/fajarkraton/fajaros-x86.git
cd fajaros-x86

# Build the kernel (concatenates 163 .fj files, compiles to ELF)
make build

# Boot in QEMU with serial console
make run
```

### Expected Boot Output

```
[NOVA] FajarOS Nova v3.0.0 Nusantara booted (62 init stages)
[NOVA] 47821 LOC | 119 commands (incl. 14 LLM) | Preemptive | 100% Fajar Lang
[NOVA] Frame allocator: 32768 frames (128MB)
[NOVA] RamFS: 64 entries, 832KB data
[NOVA] Init system: 16 services registered
[NOVA] SMP: 4 cores online
============================================
  FajarOS Nova v3.0.0 -- x86_64 Shell
  Written 100% in Fajar Lang
============================================

Type 'help' for available commands.

nova> _
```

---

## Architecture

FajarOS Nova uses a five-layer architecture. Context annotations enforce strict
isolation between layers at compile time -- a `@safe` application cannot call
`port_write`, and a `@kernel` interrupt handler cannot allocate heap memory.

```
+---------------------------------------------------------------+
|  Layer 5: Applications (@safe)                      Ring 3    |
|  Shell, MNIST classifier, editor, compiler, login, pkgmgr    |
+---------------------------------------------------------------+
|  Layer 4: OS Services (@safe + @device)             Ring 3    |
|  Init, VFS, BLK, NET, display, input, GPU, auth, packages    |
+---------------------------------------------------------------+
|  Layer 3: Filesystems (@kernel)                     Ring 0    |
|  RamFS, FAT32, ext2, VFS mount table, journaling, fsck       |
+---------------------------------------------------------------+
|  Layer 2: HAL Drivers (@kernel)                     Ring 0    |
|  Serial, VGA, keyboard, PCI, NVMe, VirtIO, xHCI, GPU         |
+---------------------------------------------------------------+
|  Layer 1: Microkernel (@kernel + @unsafe)           Ring 0    |
|  Boot, GDT/IDT, paging, LAPIC, scheduler, syscall, SMP       |
+---------------------------------------------------------------+
|  Hardware: Intel Core i9-14900HX / QEMU x86_64               |
+---------------------------------------------------------------+
```

### Context Safety Model

| Annotation | Ring | What It Can Do | What the Compiler Rejects |
|------------|------|----------------|---------------------------|
| `@kernel` | 0 | `asm!()`, port I/O, page tables, MMIO, IRQ | Heap allocation, tensor ops, string concat |
| `@device` | 0/3 | Tensor ops, GPU dispatch, AVX2, SIMD | Raw pointers, IRQ manipulation |
| `@safe` | 3 | Syscalls, strings, collections, math | Raw pointers, IRQ, port I/O, direct hardware |
| `@unsafe` | 0 | Everything (boot, context switch only) | Nothing -- use sparingly |

---

## Features

### Memory Management
- Bitmap frame allocator (32,768 frames / 128 MB)
- 4-level page tables (PML4 / PDPT / PDT / PT) with NX bit
- Copy-on-Write fork with refcounted page tables and page fault handler
- Freelist heap allocator with split/merge (`kmalloc` / `kfree`)
- Slab allocator with power-of-2 size classes

### Process Management
- Preemptive multitasking with timer-driven context switch (round-robin)
- 16-entry process table (ready / running / blocked / zombie)
- `fork()` with CoW, `exec()` from FAT32/ramfs with `argv`
- `waitpid()`, signals, job control, session timeout
- Per-process file descriptor table (stdin / stdout / stderr)

### Syscalls
- 34 syscalls via table dispatch (`EXIT` through `GPU_DISPATCH`)
- `SYSCALL` / `SYSRET` mechanism (MSR-configured)
- 5 Ring 3 user programs (hello / goodbye / fajar / counter / fibonacci)

### Storage and Filesystems
- NVMe driver (PCI detection, admin queue, I/O queue, sector R/W)
- FAT32 (BPB parse, cluster chain, directory listing, file R/W/delete)
- ext2 (superblock, block groups, inode read, directory traversal)
- RamFS (64 entries, 832 KB data area)
- VFS with mount table, `/dev` (null/zero/random), `/proc` (version/uptime/cpuinfo)
- Hierarchical directories, symlinks, hardlinks
- Write-ahead journaling with `fsck` recovery
- USB mass storage (xHCI)

### Networking
- TCP state machine (RFC 793) with SYN/ACK/FIN/RST
- UDP send/receive
- HTTP server (GET/POST, static files, API endpoints)
- Socket API (bind / listen / accept / connect / send / recv)
- Echo server
- DNS resolver
- TLS handshake framework
- VirtIO-Net driver (PCI discovery, Ethernet frame send/receive)
- ARP request/reply with cache table
- IPv4 header construction with checksum
- ICMP echo request/reply (ping)

### GPU and Compute
- VirtIO-GPU driver (framebuffer 320x200, 2D drawing primitives)
- GPU compute dispatch (matmul, vecadd) via syscall
- 16-buffer compute pool (4 KB each)
- GPU detection (NVIDIA / Intel / AMD via PCI class)

### Security and Multi-User
- 16 user accounts with login / logout / passwd
- `chmod` / `chown` with `rwxrwxrwx` permission model
- 12 capability bits for fine-grained access control
- NX bit on data pages, stack guard (unmapped page below stack)
- Ring 3 userspace with SYSCALL/SYSRET
- ASLR-ready address space layout
- Resource limits per process

### SMP (Symmetric Multiprocessing)
- AP trampoline with INIT-SIPI-SIPI boot sequence
- Per-CPU scheduling
- Test-and-set spinlocks

### Shell
- 240+ built-in commands
- Pipes (`cmd1 | cmd2 | cmd3`)
- Redirection (`>`, `>>`, `<`)
- Environment variables (`$VAR`, `export`, `unset`)
- Shell scripting (`if` / `for` / `while`, `test -f` / `-d`)
- Job control (`bg`, `fg`, `jobs`)

### Init System and Services
- 16-service init system with runlevels
- `syslogd`, `crond`, auto-restart on crash
- Package manager (`pkg install` / `remove` / `list` / `search` / `update` / `upgrade`)
- 5 standard packages

### Debugging
- GDB remote stub (RSP protocol)
- Software breakpoints, watchpoints
- Thread query, memory map
- `make debug` starts QEMU with GDB server on port 1234

### ELF Loader
- ELF64 parser with `PT_LOAD` segment loader
- `exec` from FAT32 or ramfs with argument passing
- x86_64-user target for Ring 3 ELF compilation

---

## Module Structure

```
fajaros-x86/                          163 .fj files, 47,821 LOC
|
+-- kernel/                           Microkernel core
|   +-- main.fj                       Entry point (kernel_main + shell loop)
|   +-- boot/constants.fj             Global constants, magic numbers
|   +-- mm/                           Memory management
|   |   +-- frames.fj                 Bitmap frame allocator
|   |   +-- paging.fj                 4-level page tables (PML4)
|   |   +-- heap.fj                   Freelist heap (kmalloc/kfree)
|   |   +-- slab.fj                   Slab allocator (size classes)
|   |   +-- cow.fj                    Copy-on-Write page fault handler
|   +-- sched/                        Process management
|   |   +-- process.fj                Process table (16 PIDs)
|   |   +-- scheduler.fj              Round-robin scheduler
|   |   +-- smp.fj                    SMP boot (INIT-SIPI-SIPI)
|   |   +-- signals.fj                Signal delivery
|   |   +-- spinlock.fj               Test-and-set spinlock
|   +-- syscall/                      System call interface
|   |   +-- entry.fj                  SYSCALL stub, MSR config
|   |   +-- dispatch.fj               Syscall table (34 entries)
|   |   +-- elf.fj                    ELF64 parser + PT_LOAD loader
|   +-- ipc/                          Inter-process communication
|   |   +-- message.fj                Message queue
|   |   +-- pipe.fj, pipe_v2.fj       Circular pipe (4KB, refcounted)
|   |   +-- channel.fj                Typed channels
|   |   +-- notify.fj                 Event notifications
|   |   +-- shm.fj                    Shared memory regions
|   +-- process/                      Process lifecycle
|   |   +-- fork.fj                   fork() with CoW
|   |   +-- exec.fj                   exec() from filesystem
|   |   +-- wait.fj                   waitpid() + zombie reaping
|   |   +-- exit.fj                   Process termination
|   +-- signal/                       POSIX-style signals
|   |   +-- signal.fj                 Signal dispatch
|   |   +-- jobs.fj                   Job control (bg/fg)
|   +-- auth/                         Authentication
|   |   +-- users.fj                  User database (16 accounts)
|   |   +-- permissions.fj            rwxrwxrwx model
|   |   +-- sessions.fj               Login sessions + timeout
|   +-- security/                     Hardening
|   |   +-- capability.fj             12 capability bits
|   |   +-- limits.fj                 Resource limits
|   |   +-- hardening.fj              FPU init, Ring 3, RDRAND
|   +-- debug/                        Debugging
|   |   +-- gdb_stub.fj               GDB RSP server
|   |   +-- gdb_ext.fj                Extended GDB commands
|   +-- hw/                           Hardware detection
|   |   +-- detect.fj                 CPU/chipset identification
|   |   +-- acpi.fj                   ACPI table parsing
|   |   +-- pcie.fj                   PCIe enumeration
|   |   +-- uefi_boot.fj              UEFI boot protocol
|   +-- interrupts/                   Interrupt management
|   |   +-- lapic.fj                  Local APIC + IOAPIC
|   |   +-- timer.fj                  PIT / LAPIC timer
|   +-- compute/                      GPU compute
|   |   +-- buffers.fj                Compute buffer pool
|   |   +-- kernels.fj                matmul, vecadd dispatch
|   +-- core/                         Core subsystems
|   |   +-- boot.fj, mm.fj, irq.fj   Low-level primitives
|   |   +-- sched.fj, ipc.fj          Scheduling + IPC core
|   |   +-- syscall.fj                Syscall core
|   |   +-- smp_sched.fj              SMP-aware scheduling
|   |   +-- mm_advanced.fj            Advanced memory ops
|   |   +-- security.fj               Security policy engine
|   |   +-- fast_ipc.fj               Fast-path IPC
|   |   +-- stability.fj              Stability monitors
|   |   +-- elf_loader.fj             ELF loading core
|   +-- stubs/                        Stub interfaces
|   |   +-- console.fj                Console abstraction
|   |   +-- driver_stubs.fj           Driver interface stubs
|   |   +-- framebuffer.fj            Framebuffer stub
|   |   +-- gpu_stub.fj               GPU dispatch stub
|   +-- ring3_embed.fj                Embedded Ring 3 programs
|
+-- drivers/                          Hardware drivers
|   +-- serial.fj                     16550 UART (COM1, 115200 baud)
|   +-- vga.fj                        VGA text console (80x25, 16 colors)
|   +-- keyboard.fj                   PS/2 keyboard (shift, capslock, scancodes)
|   +-- pci.fj                        PCI bus enumeration + lspci
|   +-- nvme.fj                       NVMe block device (admin + I/O queues)
|   +-- virtio_blk.fj                 VirtIO block device
|   +-- virtio_net.fj                 VirtIO network (Ethernet/ARP/IPv4/ICMP/TCP/UDP)
|   +-- virtio_gpu.fj                 VirtIO-GPU (framebuffer 320x200)
|   +-- xhci.fj                       USB 3.0 xHCI host controller
|   +-- gpu.fj                        GPU detection (NVIDIA/Intel/AMD)
|
+-- fs/                               Filesystems
|   +-- ramfs.fj                      RAM filesystem (64 entries)
|   +-- fat32.fj                      FAT32 (BPB, cluster chain, R/W)
|   +-- ext2_super.fj                 ext2 superblock + block groups
|   +-- ext2_ops.fj                   ext2 inode + directory ops
|   +-- vfs.fj                        Virtual filesystem layer
|   +-- directory.fj                  Hierarchical directory support
|   +-- links.fj                      Symlinks + hardlinks
|   +-- journal.fj                    Write-ahead log journaling
|   +-- fsck.fj                       Filesystem check + recovery
|
+-- services/                         Userspace services (IPC-based)
|   +-- init/                         Init system (PID 1)
|   |   +-- main.fj, service.fj       Service registry (16 slots)
|   |   +-- runlevel.fj               Runlevel management
|   |   +-- daemon.fj                 Daemon lifecycle
|   |   +-- shutdown.fj               Graceful shutdown
|   +-- blk/main.fj, journal.fj       Block device service
|   +-- net/                          Network stack service
|   |   +-- main.fj, socket.fj        Socket API
|   |   +-- tcp.fj, tcp_v2.fj         TCP state machine (RFC 793)
|   |   +-- udp.fj                    UDP send/receive
|   |   +-- http.fj, httpd.fj         HTTP client + server
|   |   +-- dns.fj                    DNS resolver
|   |   +-- tls.fj                    TLS handshake
|   |   +-- stats.fj                  Network statistics
|   +-- vfs/main.fj                   VFS service
|   +-- display/main.fj               Display service
|   +-- input/main.fj                 Input service
|   +-- gpu/main.fj                   GPU compute service
|   +-- gui/main.fj                   GUI window manager
|   +-- auth/main.fj                  Authentication service
|   +-- shell/main.fj                 Shell service
|   +-- pkg/                          Package manager
|       +-- manager.fj                Install/remove/update
|       +-- registry.fj               Package registry
|
+-- shell/                            Shell implementation
|   +-- commands.fj                   240+ commands + dispatch
|   +-- pipes.fj                      Pipe operator (|)
|   +-- redirect.fj                   I/O redirection (> >> <)
|   +-- vars.fj                       Environment variables ($VAR)
|   +-- control.fj                    Control flow (if/for/while)
|   +-- scripting.fj                  Shell script execution
|
+-- apps/                             User applications
|   +-- user_programs.fj              Ring 3 programs (5 embedded)
|   +-- mnist.fj                      MNIST digit classifier
|   +-- editor/main.fj                Text editor
|   +-- compiler/main.fj              In-OS compiler
|   +-- pkgmgr/main.fj                Package manager UI
|   +-- ring3_hello.fj                Ring 3 hello world
|
+-- lib/user_syscall.fj               Userspace syscall wrappers
+-- arch/aarch64/                     ARM64 cross-platform stubs
+-- tests/                            Test harnesses
|   +-- kernel_tests.fj               Kernel unit tests
|   +-- benchmarks.fj                 Performance benchmarks
|   +-- context_enforcement.fj        @kernel/@safe violation tests
|   +-- arm64_harness.fj              ARM64 cross-testing
+-- tools/                            Build utilities
|   +-- make_iso.sh                   ISO generation script
|   +-- run_qemu.sh                   QEMU launch wrapper
+-- Makefile                          Build system (concatenation)
+-- fj.toml                           Project configuration
+-- grub.cfg                          GRUB2 bootloader config
```

---

## QEMU Targets

| Target | Command | Description |
|--------|---------|-------------|
| Serial console | `make run` | Boot with serial I/O, no graphics |
| KVM accelerated | `make run-kvm` | Native speed with KVM (requires `/dev/kvm`) |
| VGA display | `make run-vga` | Boot with graphical VGA console |
| SMP (4 cores) | `make run-smp` | Multi-core with AP trampoline |
| NVMe storage | `make run-nvme` | Attach 64 MB NVMe disk image |
| Networking | `make run-net` | VirtIO-Net with user-mode networking |
| GDB debug | `make debug` | GDB server on `localhost:1234` |
| ISO boot | `make run-iso` | Boot from GRUB2 ISO image |
| Tests | `make test` | Automated tests with 10s timeout |
| LOC count | `make loc` | Lines of code per module |
| Microkernel | `make micro` | Build Ring 0 core only |

---

## Build Process

FajarOS uses a **concatenation build model**: all 163 modular `.fj` source files are
concatenated in dependency order into a single `build/combined.fj`, which the Fajar Lang
compiler then compiles into a bare-metal ELF binary.

```
163 .fj files (dependency-ordered)
        |
        v
    make build
        |
  [concatenate in Makefile order]
        |
        v
  build/combined.fj (~47,821 lines)
        |
  [fj build --target x86_64-none]
        |
        v
  build/fajaros.elf (bare-metal kernel)
        |
  [QEMU -kernel]
        |
        v
  FajarOS Nova boots
```

The concatenation order matters: constants and memory management come first,
drivers and filesystems in the middle, services and applications next,
and `kernel/main.fj` must always be last.

---

## Comparison with Other Hobby OS Projects

| Feature | FajarOS Nova | [Redox](https://redox-os.org) | [SerenityOS](https://serenityos.org) | [xv6](https://pdos.csail.mit.edu/6.828/xv6) |
|---------|-------------|------|-----------|-----|
| **Language** | Fajar Lang (100%) | Rust + asm | C++ + asm | C + asm |
| **Compile-time safety** | `@kernel/@device/@safe` | Rust borrow checker | None | None |
| **Privilege enforcement** | Compiler-level | OS-level only | OS-level only | OS-level only |
| **GPU compute** | VirtIO-GPU + dispatch | Orbital display | LibGL | None |
| **TCP/IP** | Full stack (RFC 793) | smoltcp | Full stack | None |
| **ML inference** | MNIST classifier | None | None | None |
| **ELF loader** | ELF64 + exec | ELF64 | ELF64 | ELF32 |
| **SMP** | INIT-SIPI-SIPI | SMP | SMP | None (xv6-riscv has SMP) |
| **Package manager** | Built-in (pkg) | pkgutils | Ports | None |
| **GDB stub** | Built-in RSP | GDB support | GDB support | GDB support |
| **Init system** | 16 services, runlevels | init | SystemServer | None |
| **Lines of code** | 36K (single language) | ~400K (multi-language) | ~600K (multi-language) | ~6K |

FajarOS Nova is unique in that **the compiler itself prevents privilege violations**.
In every other OS, a bug in a driver could accidentally access kernel memory or perform
unauthorized I/O. In FajarOS, the `@kernel` annotation makes such bugs a compile error,
not a runtime crash.

---

## Sample Shell Session

```
nova> uname -a
FajarOS Nova v3.0.0 Nusantara x86_64 SMP(4) 512MB

nova> cat /proc/cpuinfo
cpu0: x86_64 @ 2.0 GHz (QEMU)
cpu1: x86_64 @ 2.0 GHz (AP)
cpu2: x86_64 @ 2.0 GHz (AP)
cpu3: x86_64 @ 2.0 GHz (AP)

nova> ls /
bin  dev  etc  home  mnt  proc  tmp

nova> lspci
00:00.0 Host bridge
00:01.0 VGA controller
00:02.0 Ethernet controller [VirtIO]
00:03.0 NVMe controller

nova> ps
PID  STATE   NAME
  1  running init
  2  ready   shell
  3  blocked syslogd
  4  blocked crond

nova> echo "Hello from FajarOS!" > /tmp/hello.txt
nova> cat /tmp/hello.txt
Hello from FajarOS!

nova> ping 10.0.2.2
PING 10.0.2.2: 64 bytes, seq=1 ttl=64 time=0.3ms

nova> help | head 5
FajarOS Nova Shell -- 240+ commands available
Type 'help <command>' for details.
  cat      -- display file contents
  cd       -- change directory
  chmod    -- change file permissions
```

---

## Related Projects

| Project | Description | Link |
|---------|-------------|------|
| **Fajar Lang** | The compiler (Rust + Cranelift backend) | [github.com/fajarkraton/fajar-lang](https://github.com/fajarkraton/fajar-lang) |
| **FajarOS Surya** | ARM64 version for Radxa Dragon Q6A | [github.com/fajarkraton/fajar-os](https://github.com/fajarkraton/fajar-os) |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines, module conventions,
and the build process.

## Security

See [SECURITY.md](SECURITY.md) for the security model, vulnerability reporting,
and audit results.

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). We follow the Contributor Covenant 2.1.

## License

MIT License -- Copyright (c) 2026 Fajar (TaxPrime / PrimeCore.id)

See [LICENSE](LICENSE) for details.

---

*FajarOS Nova v3.0.0 "Nusantara" -- 47,821 LOC | 163 modules | 119 commands (incl. 14 LLM) | 34 syscalls | LLM E2E (SmolLM-135M v5/v6 in kernel) | 100% Fajar Lang*
*Compiler-enforced safety: if it compiles, it's safe to deploy.*
*Built with [Fajar Lang](https://github.com/fajarkraton/fajar-lang) + Claude Opus 4.6*
