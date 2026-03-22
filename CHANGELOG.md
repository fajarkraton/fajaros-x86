# Changelog

All notable changes to FajarOS Nova are documented in this file.

## [2.0.0] "Sovereignty" -- 2026-03-22

FajarOS Nova v2.0 is a complete rewrite from monolithic to microkernel architecture.
22 sprints across 3 phases, 20,416 lines of Fajar Lang, 405 KB kernel image.
19 critical bugs found and fixed during development. 10/10 ARM64 tests pass on
Radxa Dragon Q6A.

### Phase 1: Microkernel Foundation (Sprint 1.1--1.8)

- **S1.1 Microkernel Spec**: Defined IPC protocol, capability model, syscall
  numbering, service registration, and endpoint lifecycle
- **S1.2 IPC Core**: Synchronous message passing with 576-byte endpoints,
  capability-based access control, blocking send/recv with scheduler integration
- **S1.3 Kernel Extraction**: Split monolithic kernel into minimal microkernel
  (scheduler, IPC, memory, syscall) with all drivers moved to userspace services
- **S1.4 VFS Service**: Virtual filesystem service over IPC -- open, read, write,
  close, stat, readdir operations with mount point management
- **S1.5 BLK Service**: Block device service wrapping NVMe and ramdisk drivers,
  sector-level read/write, partition table parsing
- **S1.6 NET Service**: Network stack service -- Ethernet, ARP, IPv4, ICMP, UDP,
  TCP, DHCP client, all communicating via IPC to the kernel
- **S1.7 Shell Service**: Interactive shell running as userspace service, 160+
  built-in commands, command parsing and pipeline support
- **S1.8 Compiler Enforcement**: `@kernel` annotation enforced at compile time --
  services cannot access hardware directly, must use IPC

### Phase 2: Hardening (Sprint 2.1--2.6)

- **S2.1 SMP Scheduler**: Multi-core symmetric multiprocessing with per-CPU run
  queues, load balancing, INIT-SIPI-SIPI AP bootstrap, per-CPU idle tasks
- **S2.2 Memory Management**: Per-process page tables with CR3 switching, page
  fault handler that kills faulting process, kernel heap with slab allocator
- **S2.3 Security Hardening**: Capability-based IPC access control, syscall
  argument validation, stack canaries, W^X enforcement on page tables
- **S2.4 Journaling Filesystem**: Write-ahead journal for FAT32, crash recovery
  on mount, transaction commit/abort, fsck shell command
- **S2.5 Fast IPC**: Optimized message path -- register-based fast path for small
  messages (<64 bytes), zero-copy shared memory for large transfers
- **S2.6 Test Suite**: 200+ kernel tests, IPC stress tests, scheduler fairness
  tests, memory leak detection, QEMU automated test runner

### Phase 3: Userspace & Release (Sprint 3.1--3.10)

- **S3.1 Framebuffer Display**: Linear framebuffer via VESA/GOP, 1024x768x32
  console with 8x16 font, scroll, ANSI color codes
- **S3.2 Mouse Input**: PS/2 mouse driver as userspace service, absolute
  positioning, click events delivered via IPC
- **S3.3 GUI Toolkit**: Minimal widget toolkit -- Window, Button, Label, TextBox,
  event loop, compositing over framebuffer
- **S3.4 Text Editor**: `edit` command -- modal editor (view/insert), syntax
  highlighting for `.fj` files, save to VFS
- **S3.5 Self-Hosting Compiler**: `fj` compiler runs inside FajarOS, can compile
  `.fj` sources to x86_64 ELF, bootstrap verified
- **S3.6 Package Manager**: `pkg install/remove/list` commands, dependency
  resolution, package index over HTTP via NET service
- **S3.7 Hardware Detection**: PCI enumeration, ACPI table parsing, CPU feature
  detection (SSE, AVX, x2APIC), device tree for drivers
- **S3.8 ARM64 Q6A Port**: Cross-compilation to aarch64, UEFI boot on Radxa
  Dragon Q6A, GPIO and NPU stubs, 10/10 hardware tests pass
- **S3.9 Documentation**: Architecture guide, syscall reference, IPC protocol
  spec, service development tutorial, shell command reference
- **S3.10 Release Engineering**: Version tagging, ISO generation, QEMU test
  automation, CONTRIBUTING.md, CHANGELOG.md, issue templates

### Statistics

| Metric               | Value                     |
|----------------------|---------------------------|
| Total LOC            | 20,416 lines of Fajar Lang |
| Kernel image size    | 405 KB                    |
| Sprints completed    | 22 / 22                   |
| Shell commands       | 160+                      |
| Syscalls             | 17                        |
| IPC endpoint size    | 576 bytes                 |
| Max processes        | 16 (PID table)            |
| Critical bugs fixed  | 19                        |
| ARM64 tests          | 10 / 10 pass              |
| QEMU targets         | x86_64, aarch64           |

### Breaking Changes

- **Syscall numbers differ from v1.0 spec**: The microkernel redesign
  renumbered all syscalls. `SYS_EXIT` is now 0 (was 1), `SYS_IPC_SEND` is 10
  (new), `SYS_IPC_RECV` is 11 (new). See `kernel/syscall/table.fj` for the
  complete mapping.
- **IPC endpoint buffer size**: Changed from 512 to 576 bytes to accommodate
  capability metadata (8-byte cap header + 56-byte cap table).
- **Driver model**: All drivers moved from kernel to userspace services. Code
  that previously called hardware functions directly must now use IPC to the
  appropriate service (BLK, NET, etc.).
- **Shell service**: The shell is no longer linked into the kernel binary. It
  runs as PID 2 and communicates via IPC. Shell extensions must be rewritten
  as IPC-aware services.

### Bug Fixes (Notable)

- Fixed double-free in IPC endpoint deallocation during process exit
- Fixed race condition in SMP scheduler when two cores dequeue same task
- Fixed page table corruption when forking process with shared memory mappings
- Fixed TCP RST not sent on connection abort through NET service
- Fixed journal replay applying committed transactions out of order
- Fixed framebuffer scroll leaving artifacts in last row
- Fixed PS/2 mouse byte synchronization loss after overflow

---

## [1.0.0] "Genesis" -- 2026-03-10

Initial release. Monolithic kernel with preemptive multitasking, DHCP+ping
networking, USB mass storage, NVMe, FAT32, VFS, ELF loader, Ring 3 user
programs, SMP bootstrap, 160+ shell commands. 11,615 LOC across 35 `.fj` files.
Verified on QEMU x86_64 with KVM.
