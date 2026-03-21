# FajarOS x86_64 — Master Implementation Plan

> **Vision:** The world's first microkernel OS with compiler-enforced safety,
> written 100% in a single language that unifies kernel, drivers, AI, and userspace.
>
> **What makes it unique:** `@kernel/@device/@safe` — the COMPILER prevents
> privilege violations. No other OS in existence has this.
>
> **Date:** 2026-03-22
> **Author:** Fajar (PrimeCore.id) + Claude Opus 4.6
> **Baseline:** v1.0.0 "Genesis" — 10,291 LOC modular, 385 @kernel fns, monolithic
> **Target:** v3.0.0 "Sovereignty" — microkernel, self-hosting, GUI, real hardware

---

## Why This OS Can Be The Best

| Feature | Linux | seL4 | Redox | **FajarOS** |
|---------|-------|------|-------|-------------|
| Language | C (unsafe) | C (unsafe) | Rust (safe) | **Fajar Lang (compiler-enforced contexts)** |
| Architecture | Monolithic | Microkernel (formal) | Microkernel | **Microkernel (compiler-enforced)** |
| Driver isolation | No | Manual | Partial | **`@kernel` annotation — compiler rejects violations** |
| AI integration | Separate libs | None | None | **`@device` — tensor ops native in type system** |
| User safety | MMU only | Capability-based | MMU | **`@safe` — compiler prohibits hardware access** |
| Self-hosting | Yes (gcc) | No | Partial | **Target: compile Fajar Lang ON FajarOS** |

**The killer feature:** In FajarOS, if you write `@safe fn shell_cmd() { port_outb(0x3F8, 65) }`, the **compiler refuses to build it**. No other OS has this level of compile-time safety enforcement.

---

## Roadmap Overview: 3 Major Releases

```
v1.0 "Genesis" (CURRENT)     → Monolithic, 10K LOC, working
    │
    ▼
v2.0 "Sovereignty"           → MICROKERNEL refactor
    │                            @kernel/@device/@safe enforced
    │                            Drivers as user-space services
    │                            IPC message-passing core
    │
    ▼
v3.0 "Transcendence"         → SELF-HOSTING + GUI
                                 Compile Fajar Lang on FajarOS
                                 Framebuffer compositor
                                 Package manager
                                 Real hardware deployment
```

---

## Phase 1: Microkernel Core (v2.0-alpha)
**Goal:** Split monolithic kernel into micro-kernel + user-space services
**Effort:** ~40 hours | 8 sprints | 80 tasks

### Sprint 1.1: Define Microkernel Boundary (10 tasks)

What stays in Ring 0 (@kernel):

| Component | LOC | Why Ring 0 |
|-----------|-----|------------|
| Scheduler | ~200 | Timer ISR, context switch |
| Memory manager | ~500 | Page tables, frame alloc |
| IPC core | ~300 | Message passing, shared memory |
| Syscall dispatch | ~200 | Ring 3→0 transition |
| Interrupt handlers | ~100 | IDT, EOI, routing |
| **Total kernel** | **~1,300** | **Down from 10,291** |

What moves to Ring 3:

| Component | Current LOC | New Annotation | How It Runs |
|-----------|-------------|----------------|-------------|
| Shell | 3,394 | `@safe` | Process, syscalls for I/O |
| FAT32 | 752 | `@safe` | Service, IPC for block I/O |
| VFS | 325 | `@safe` | Service, routes to FS drivers |
| Network | 655 | `@device` | Service, IPC for NIC access |
| NVMe driver | 645 | `@kernel` → IPC wrapper | Minimal Ring 0 + user service |
| USB/XHCI | 552 | `@kernel` → IPC wrapper | Minimal Ring 0 + user service |
| RamFS | 115 | `@safe` | Service |
| MNIST/AI | 6+ | `@device` | Process |

| # | Task | Detail |
|---|------|--------|
| 1.1.1 | Document microkernel API | Define 15 syscalls: send, recv, map, unmap, spawn, exit, wait, kill, yield, getpid, time, irq_register, irq_wait, port_access, dma_alloc |
| 1.1.2 | Define IPC message format | 64-byte messages: src_pid(8) + type(8) + payload(48) |
| 1.1.3 | Define service protocol | VFS protocol: OPEN, READ, WRITE, CLOSE, STAT, LIST |
| 1.1.4 | Define driver protocol | Block protocol: READ_SECTORS, WRITE_SECTORS, GET_INFO |
| 1.1.5 | Define net protocol | Net protocol: SEND_FRAME, RECV_FRAME, GET_MAC, SET_IP |
| 1.1.6 | Map current code to new modules | Assign @kernel/@device/@safe to every function |
| 1.1.7 | Design capability system | Per-process capability table: port I/O, IRQ, DMA, IPC |
| 1.1.8 | Design namespace system | Naming: /dev/nvme0, /dev/net0, /srv/vfs, /srv/shell |
| 1.1.9 | Design boot sequence | Kernel → init → vfs_srv → net_srv → shell |
| 1.1.10 | Write architecture document | Complete microkernel spec with diagrams |

### Sprint 1.2: IPC Message-Passing Core (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.2.1 | `ipc_send(dst, msg)` syscall | Synchronous send — blocks until receiver ready |
| 1.2.2 | `ipc_recv(src, buf)` syscall | Synchronous receive — blocks until message arrives |
| 1.2.3 | `ipc_call(dst, msg, reply)` | Send + wait for reply (RPC pattern) |
| 1.2.4 | `ipc_reply(src, msg)` | Reply to a received message |
| 1.2.5 | Channel abstraction | Named channels: create_channel("vfs") → handle |
| 1.2.6 | Async notification | Non-blocking signal: notify(pid, bits) |
| 1.2.7 | Shared memory regions | map_shared(pid_a, pid_b, size) → addr pair |
| 1.2.8 | Zero-copy transfer | Large data via shared page mapping, not copy |
| 1.2.9 | IPC performance test | Measure round-trip latency (target: <1μs) |
| 1.2.10 | IPC security | Capability check on every send (can A talk to B?) |

### Sprint 1.3: Minimal Kernel (@kernel only) (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.3.1 | Extract kernel core | New `kernel/core/` with ONLY: sched, mm, ipc, syscall |
| 1.3.2 | Remove drivers from kernel | Drivers → separate .fj files compiled as user services |
| 1.3.3 | Remove shell from kernel | Shell → `@safe` process, communicates via IPC |
| 1.3.4 | Remove FS from kernel | FAT32/VFS → `@safe` service processes |
| 1.3.5 | Kernel size target: <2,000 LOC | Measure and trim |
| 1.3.6 | Per-process page tables | Each service gets own address space |
| 1.3.7 | Capability table per process | Bitmap: port_io, irq, dma, ipc_targets |
| 1.3.8 | Kernel-only memory region | 0x0-0x1FFFFF reserved, user starts at 0x200000 |
| 1.3.9 | Exception routing | Page fault → kill or forward to pager service |
| 1.3.10 | Kernel panic handler | Clean dump to serial + halt all CPUs |

### Sprint 1.4: VFS Service (@safe, Ring 3) (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.4.1 | VFS as separate process | Spawn at boot, listen on IPC channel "vfs" |
| 1.4.2 | VFS protocol messages | MSG_OPEN, MSG_READ, MSG_WRITE, MSG_CLOSE, MSG_STAT |
| 1.4.3 | Mount table in VFS service | IPC to block device services for actual I/O |
| 1.4.4 | /dev registration | Device services register via IPC: register_dev("nvme0") |
| 1.4.5 | /proc generation | VFS generates proc entries from kernel IPC queries |
| 1.4.6 | FAT32 as sub-service | VFS delegates to fat32_srv for FAT32 mounts |
| 1.4.7 | RamFS as sub-service | VFS delegates to ramfs_srv for RAM mounts |
| 1.4.8 | Path resolution | "/mnt/usb/hello.txt" → find mount → route to FS service |
| 1.4.9 | File descriptor table | Per-process FD table, managed by VFS service |
| 1.4.10 | Test: cat /proc/version via IPC | Shell → VFS → procfs → kernel → reply |

### Sprint 1.5: Block Device Service (@kernel→IPC) (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.5.1 | NVMe user-space driver | Minimal @kernel stub for MMIO + DMA, rest in @safe |
| 1.5.2 | Block device IPC protocol | BLK_READ(lba, count) → data, BLK_WRITE(lba, data) |
| 1.5.3 | DMA buffer sharing | Kernel maps DMA pages into driver process |
| 1.5.4 | IRQ forwarding | Kernel catches NVMe IRQ, notifies driver via IPC |
| 1.5.5 | USB storage service | XHCI SCSI via IPC to block layer |
| 1.5.6 | Ramdisk service | Simple memory block device |
| 1.5.7 | Block cache | Read-ahead cache in VFS service |
| 1.5.8 | Write-back | Dirty sector tracking + periodic flush |
| 1.5.9 | Test: read file via IPC chain | Shell → VFS → FAT32 → BLK → NVMe → data |
| 1.5.10 | Benchmark: IPC vs direct I/O | Compare latency of microkernel vs monolithic path |

### Sprint 1.6: Network Service (@device, Ring 3) (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.6.1 | Net service process | @device, handles Ethernet/IP/TCP/UDP |
| 1.6.2 | Virtio-net kernel stub | Minimal @kernel: virtqueue setup, IRQ, DMA |
| 1.6.3 | Frame send/recv via IPC | net_srv ↔ kernel: SEND_FRAME, RECV_FRAME |
| 1.6.4 | Socket API via IPC | Applications → net_srv: CONNECT, SEND, RECV |
| 1.6.5 | DHCP in net service | Full DHCP state machine in @device process |
| 1.6.6 | ARP in net service | ARP cache managed by net_srv |
| 1.6.7 | TCP in net service | Connection tracking, retransmission |
| 1.6.8 | DNS resolver | Query QEMU DNS at 10.0.2.3 |
| 1.6.9 | ping command via IPC | Shell → net_srv → ICMP → reply |
| 1.6.10 | wget via IPC | Shell → net_srv → TCP → HTTP → VFS → file |

### Sprint 1.7: Shell as @safe Process (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.7.1 | Shell process | @safe, compiled with --target x86_64-user |
| 1.7.2 | Console I/O via syscall | SYS_READ(stdin), SYS_WRITE(stdout) |
| 1.7.3 | File commands via VFS IPC | ls, cat, cp, rm → MSG_OPEN/READ/WRITE |
| 1.7.4 | Process commands via kernel | ps, kill, spawn → direct syscalls |
| 1.7.5 | Network commands via IPC | ping, wget → MSG to net_srv |
| 1.7.6 | Command history | Local to shell process (no kernel involvement) |
| 1.7.7 | Tab completion | Query VFS for path completion |
| 1.7.8 | Pipe support | Shell creates pipe, connects two processes |
| 1.7.9 | Job control | Background processes (&), fg, bg |
| 1.7.10 | Shell crash → restart | Init process detects shell exit, respawns |

### Sprint 1.8: Compiler Enforcement (10 tasks)

| # | Task | Detail |
|---|------|--------|
| 1.8.1 | @safe enforcement | Compiler rejects: asm!(), port_outb, volatile_write in @safe |
| 1.8.2 | @device enforcement | Compiler rejects: IRQ, raw pointers in @device |
| 1.8.3 | @kernel enforcement | Compiler rejects: heap strings, tensor ops in @kernel |
| 1.8.4 | Cross-annotation calls | @safe can call @safe, @kernel via syscall only |
| 1.8.5 | IPC type safety | Message types checked at compile time |
| 1.8.6 | Capability types | Cap<PortIO>, Cap<IRQ>, Cap<DMA> — compile-time checked |
| 1.8.7 | Error: @safe calls port_outb | Clear message: "port I/O not allowed in @safe context" |
| 1.8.8 | Error: @device calls irq | Clear message: "IRQ access not allowed in @device context" |
| 1.8.9 | Integration test | Build full OS with enforcement — all annotations correct |
| 1.8.10 | Documentation | Fajar Lang Safety Model specification |

---

## Phase 2: Production Hardening (v2.0-beta)
**Goal:** Make the microkernel reliable, fast, and deployable
**Effort:** ~30 hours | 6 sprints | 60 tasks

### Sprint 2.1: SMP Scheduler (10 tasks)
- Per-CPU run queues
- Work stealing between cores
- CPU affinity for processes
- Load balancing
- Real-time priority levels (IDLE, NORMAL, HIGH, REALTIME)

### Sprint 2.2: Memory Management (10 tasks)
- Demand paging (lazy allocation)
- Copy-on-write fork
- Shared libraries (mapped read-only)
- Out-of-memory killer
- Memory statistics per process

### Sprint 2.3: Security Hardening (10 tasks)
- SMEP/SMAP enforcement
- Stack canaries (compiler-generated)
- ASLR for user processes
- NX enforcement on all data pages
- Capability revocation

### Sprint 2.4: Persistence & Journaling (10 tasks)
- Write-ahead logging for FAT32
- Transaction support (atomic multi-file ops)
- fsck on mount
- Dirty bitmap + sync command
- Boot-time consistency check

### Sprint 2.5: Performance Optimization (10 tasks)
- IPC fast path (register-only transfer for small messages)
- Zero-copy I/O (page flipping)
- Batch syscalls (submit multiple ops)
- Lock-free IPC queues
- Benchmark: context switch <5μs, IPC <1μs

### Sprint 2.6: Testing & CI (10 tasks)
- Unit tests for kernel core
- Integration tests for each service
- QEMU automated test suite (20 scenarios)
- Fault injection testing
- Performance regression tests

---

## Phase 3: Self-Hosting & GUI (v3.0)
**Goal:** FajarOS compiles Fajar Lang, has GUI, runs on real hardware
**Effort:** ~60 hours | 10 sprints | 100 tasks

### Sprint 3.1: Framebuffer Display (10 tasks)
- VESA/GOP framebuffer from Multiboot2
- Pixel drawing primitives
- Font rendering (8×16 bitmap font)
- Window compositor (non-overlapping tiles)
- Terminal emulator in GUI mode

### Sprint 3.2: Mouse/Touchpad Input (10 tasks)
- PS/2 mouse driver
- USB HID mouse (via XHCI)
- Cursor rendering
- Click/drag events via IPC

### Sprint 3.3: GUI Toolkit (@safe) (10 tasks)
- Widget library: Button, TextBox, Label, List
- Event loop (message-based)
- Layout engine (vertical/horizontal stacks)
- Theme system (colors, borders)
- Window manager service

### Sprint 3.4: Text Editor (@safe) (10 tasks)
- Buffer management (gap buffer or rope)
- Syntax highlighting for .fj files
- Save/load via VFS IPC
- Keyboard shortcuts (Ctrl+S, Ctrl+Q)
- Line numbers, status bar

### Sprint 3.5: Fajar Lang Compiler Port (10 tasks)
- Port lexer to Fajar Lang (already exists in stdlib/)
- Port parser to Fajar Lang
- Port analyzer to Fajar Lang
- Minimal codegen (interpreter mode)
- `fj build hello.fj` runs on FajarOS

### Sprint 3.6: Package Manager (10 tasks)
- Package format: .fjpkg (tar + metadata)
- Local package database
- `fj install <package>` from FAT32/USB
- Dependency resolution
- Build from source support

### Sprint 3.7: Real Hardware — Intel i9-14900HX (10 tasks)
- Boot from USB stick (GRUB2 ISO)
- Serial output via real COM port (or USB-serial)
- VGA/UEFI GOP display
- PS/2 or USB keyboard
- NVMe SSD (real Samsung/WD drive)
- Intel I219 Ethernet (real network)

### Sprint 3.8: Real Hardware — Radxa Dragon Q6A (10 tasks)
- Port microkernel to ARM64
- GICv3 interrupt controller
- UART PL011 serial
- QNN NPU integration (@device)
- Dual-target build (x86_64 + aarch64)

### Sprint 3.9: Documentation & Website (10 tasks)
- FajarOS manual (mdBook)
- API reference for all syscalls
- Architecture guide with diagrams
- Blog: "Building an OS in Fajar Lang"
- fajaros.dev website

### Sprint 3.10: Community & Release (10 tasks)
- GitHub organization setup
- Contributing guide
- Issue templates
- First external contributor onboarding
- Conference talk / paper submission
- v3.0.0 release with ISO + documentation

---

## Architecture: v2.0 Microkernel

```
┌─────────────────────────────────────────────────────────────┐
│  User Space (Ring 3)                                         │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │  Shell   │ │  Editor  │ │  wget    │ │  AI App  │       │
│  │  @safe   │ │  @safe   │ │  @safe   │ │  @device │       │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘       │
│       │IPC         │IPC         │IPC         │IPC           │
│  ┌────┴─────┐ ┌────┴─────┐ ┌────┴─────┐                    │
│  │  VFS     │ │  Net     │ │  Display │                    │
│  │  Service │ │  Service │ │  Service │                    │
│  │  @safe   │ │  @device │ │  @safe   │                    │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘                    │
│       │IPC         │IPC         │IPC                        │
├───────┼────────────┼────────────┼────────────────────────────┤
│  Kernel (Ring 0) — @kernel ONLY — <2,000 LOC                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Scheduler │ IPC Core │ Memory Mgr │ Syscall Dispatch│   │
│  │  (200 LOC) │ (300 LOC)│ (500 LOC)  │ (200 LOC)      │   │
│  └─────────────────────────────────────────────────────┘    │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐                 │
│  │ NVMe Stub │ │ Net Stub  │ │ USB Stub  │                 │
│  │ (IRQ+DMA) │ │ (IRQ+DMA) │ │ (IRQ+DMA) │                 │
│  │ @kernel   │ │ @kernel   │ │ @kernel   │                 │
│  │ (50 LOC)  │ │ (50 LOC)  │ │ (50 LOC)  │                 │
│  └───────────┘ └───────────┘ └───────────┘                 │
│                                                              │
│  Total Ring 0: ~1,500 LOC (down from 10,291)                │
└─────────────────────────────────────────────────────────────┘
│                                                              │
│  Hardware — Intel i9-14900HX / Radxa Dragon Q6A              │
└─────────────────────────────────────────────────────────────┘
```

---

## Compiler Safety Enforcement (Unique Feature)

```fajar
// THIS COMPILES ✓
@kernel fn handle_irq() {
    let status = port_inb(0x3F8)      // OK: @kernel can do port I/O
    pic_eoi(0)                         // OK: @kernel can send EOI
}

// THIS COMPILES ✓
@device fn classify(img: Tensor) -> i64 {
    let output = tensor_matmul(weights, img)  // OK: @device can use tensors
    tensor_argmax(output)                      // OK: @device can compute
}

// THIS COMPILES ✓
@safe fn shell_command(cmd: str) {
    let result = syscall(SYS_WRITE, 1, cmd, len(cmd))  // OK: @safe uses syscalls
    println(result)                                      // OK: @safe can print
}

// THIS DOES NOT COMPILE ✗
@safe fn hack() {
    port_outb(0x3F8, 65)   // ERROR: port I/O not allowed in @safe context
    volatile_write(0xB8000, 0)  // ERROR: MMIO not allowed in @safe
}

// THIS DOES NOT COMPILE ✗
@device fn bad_driver() {
    irq_register(14, handler)  // ERROR: IRQ not allowed in @device context
    asm!("cli")                // ERROR: asm not allowed in @device
}

// THIS DOES NOT COMPILE ✗
@kernel fn bloated_kernel() {
    let s = "hello"        // ERROR: heap strings not allowed in @kernel
    let t = tensor_zeros(3,3)  // ERROR: tensor ops not allowed in @kernel
}
```

---

## Timeline

```
v2.0-alpha (Phase 1):  Sprint 1.1-1.8    80 tasks    ~40 hrs    Microkernel
v2.0-beta  (Phase 2):  Sprint 2.1-2.6    60 tasks    ~30 hrs    Hardening
v3.0       (Phase 3):  Sprint 3.1-3.10   100 tasks   ~60 hrs    Self-hosting + GUI

Total: 24 sprints, 240 tasks, ~130 hours
```

## Success Metrics

| Metric | v1.0 (Now) | v2.0 Target | v3.0 Target |
|--------|-----------|-------------|-------------|
| Kernel LOC (Ring 0) | 10,291 | **<2,000** | <2,000 |
| User services | 0 | **5+** | 10+ |
| @safe functions | 0 | **100+** | 200+ |
| @device functions | 0 | **30+** | 50+ |
| IPC latency | N/A | **<1μs** | <500ns |
| Context switch | ~10ms | **<5μs** | <2μs |
| Crash isolation | None | **Per-service** | Per-service |
| Self-hosting | No | No | **Yes** |
| GUI | No | No | **Yes** |
| Real hardware | QEMU only | QEMU + basic HW | **Full HW** |
| Shell mode | Kernel (Ring 0) | **User (Ring 3)** | User + GUI |
| AI inference | Simulated | @device service | **NPU + GPU** |

---

*FajarOS: where the compiler IS the security model.*
*240 tasks across 24 sprints — from monolithic to microkernel to self-hosting.*
*Built with Fajar Lang + Claude Opus 4.6*
