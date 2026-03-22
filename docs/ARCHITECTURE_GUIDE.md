# FajarOS Nova v2.0 — Architecture Guide

> Microkernel OS written 100% in Fajar Lang with compiler-enforced safety.
> Target: Intel Core i9-14900HX | Verified: QEMU + Radxa Dragon Q6A

---

## 1. System Overview

```
 User Space (Ring 3)               Kernel (Ring 0)
 ==================                ================

 +-----------+  +-----------+
 | Editor    |  | AI App    |
 | @safe     |  | @device   |
 +-----+-----+  +-----+-----+
       |IPC            |IPC
       v               v
 +-----------+  +-----------+  +-----------+
 | Shell     |  | Net Svc   |  | Display   |
 | PID 5     |  | PID 4     |  | PID 6     |
 | @safe     |  | @device   |  | @safe     |
 +-----+-----+  +-----+-----+  +-----+-----+
       |IPC            |IPC            |IPC
       v               |               |
 +-----------+         |               |
 | VFS Svc   |<--------+               |
 | PID 3     |                         |
 | @safe     |                         |
 +-----+-----+                         |
       |IPC                            |
       v                               |
 +-----------+                         |
 | BLK Svc   |                         |
 | PID 2     |                         |
 | @device   |                         |
 +-----+-----+                         |
       |SYS_PORT_IO                    |
       v                               v
 ======+===============================+=======
 | Kernel (PID 0) — @kernel ONLY              |
 | Scheduler | IPC | MM | Syscall | IRQ       |
 | NVMe Stub | Net Stub | USB Stub            |
 +---------------------------------------------+
       |
 [ Hardware: i9-14900HX / LAPIC / NVMe / NIC ]
```

**Init (PID 1, @safe)** spawns all services in order: BLK -> VFS -> NET -> Shell.

---

## 2. Memory Map

```
Address Range          Size     Component
-------------------    ------   -------------------------------------------
0x000000 - 0x07FFFF    512K    Low memory (IVT, BDA, EBDA)
0x070000 - 0x073FFF     16K    Page tables (PML4, PDPT, PD)
0x0B8000 - 0x0B8FFF      4K    VGA text buffer (80x25, attr+char)
0x100000 - 0x120000    128K    Kernel .text (code, @kernel fns)
0x400000 - 0x580000   1536K    Heap (freelist allocator, kmalloc/kfree)
0x580000 - 0x581000      4K    Frame bitmap (32768 frames)
0x600000 - 0x700000   1024K    Process table (16 PIDs) + shell state
  0x600000                       Process table (256B per PID)
  0x6F800                        Command buffer (64 bytes)
  0x6FA00                        VGA cursor (row, col)
  0x6FBE0                        Keyboard state (shift, caps, ring buf)
  0x6FD00                        Command history (circular)
  0x6FE00                        Current PID
  0x6FF00                        Multiboot2 info pointer
0x700000 - 0x7E0000    896K    RamFS (file storage)
0x7F0000 - 0x800000     64K    Kernel stack (guard page at bottom)
0x8A0000 - 0x8AB800     46K    IPC subsystem
  0x8A0000                       Endpoint table (16 EPs x 576B = 9KB)
  0x8A2400                       Channel registry (16 channels)
  0x8A4000                       Notification bitmaps
  0x8A6000                       Shared memory regions (16 x 4KB)
0x8B0000 - 0x8B6000     24K    VFS service state (mounts, FDs, inodes)
0x8B8000 - 0x8B8400      1K    BLK device table (4 devices)
0x8C0000 - 0x900000    256K    Ramdisk (512 sectors x 512B)
0x8E0000 - 0x8E2200      9K    NET service (sockets, ARP cache, stats)
0x8F0000 - 0x8F4000     16K    Shell service (history, pipes, state)
0x8F4000 - 0x8F42C0      1K    SMP scheduler (per-CPU queues, affinity)
0x8F5000 - 0x8F7200      9K    Demand paging + CoW + memory stats
0x8F7800 - 0x8F7900    256B    Stack canaries (per-process)
0x8F8000 - 0x900000     32K    Journal + dirty bitmap (WAL, 32 entries)
0x8FA000 - 0x8FA460      1K    Fast IPC (16-entry register transfer)
0x900000 - 0x902000      8K    Test scratch area
0x910000 - 0x919000     36K    BLK cache (16 entries) + scratch
0x920000 - 0x928000     32K    Framebuffer + font + console
0x928000 - 0x92B000     12K    GUI widgets + theme engine
0x930000 - 0x93C000     48K    Text editor (gap buffer + line index)
0x940000 - 0x94F000     60K    Compiler (lexer + parser + interpreter)
0x950000 - 0x955000     20K    Package manager (32 packages)
0x960000 - 0x961000      4K    Hardware detection (CPUID + PCI scan)
0xB8000                         VGA text mode buffer (memory-mapped)
0xFEC00000                      IOAPIC MMIO
0xFEE00000                      LAPIC MMIO
0x2000000                       User program load address (Ring 3)
0x2F00000                       User stack (Ring 3)
```

---

## 3. IPC Flow: `cat /proc/version`

```
Shell (PID 5, @safe)
  |
  |  SYS_CALL(dst=3, MSG_VFS_OPEN, "/proc/version")
  |---------------------------------------------------->
  |                                    VFS Service (PID 3, @safe)
  |                                      |
  |                                      | path_resolve("/proc/version")
  |                                      | -> mount: /proc (procfs)
  |                                      | -> procfs_read("version")
  |                                      | -> "FajarOS Nova v2.0"
  |                                      |
  |  <-------- SYS_REPLY(MSG_VFS_REPLY, fd=0, size=18) -|
  |
  |  SYS_CALL(dst=3, MSG_VFS_READ, {fd=0, len=18})
  |---------------------------------------------------->
  |                                      |
  |                                      | Copy data to shared buffer
  |                                      |
  |  <-------- SYS_REPLY(bytes_read=18) ----------------|
  |
  |  SYS_WRITE(fd=1, "FajarOS Nova v2.0", 18)
  |  -> console output via kernel
  |
  Total: 4 IPC transitions, <10us target latency
```

For large files (>40 bytes), the VFS uses shared memory (SYS_SHARE) for zero-copy transfer.

---

## 4. Boot Sequence

```
Phase 1: Hardware Init (~50ms)                      @kernel
  GRUB2 -> _start -> GDT (3 segments) -> IDT (256 vectors)
  -> 4-level paging (PML4/PDPT/PD/PT via CR3)
  -> Heap init (freelist at 0x400000)
  -> Serial 16550 UART (COM1: 0x3F8, 115200 baud)
  -> PIT timer (100Hz) -> Keyboard IRQ (PS/2)
  -> LAPIC + IOAPIC init

Phase 2: Kernel Services (~10ms)                    @kernel
  Frame allocator (bitmap at 0x580000, 32768 frames)
  -> IPC endpoint table (16 EPs at 0x8A0000)
  -> Channel registry + notification system
  -> SYSCALL/SYSRET MSRs (STAR, LSTAR, SFMASK)
  -> Capability table init (12-bit per process)
  -> SMP: AP trampoline (INIT-SIPI-SIPI for cores 1-3)

Phase 3: Init Process (~20ms)                       @safe
  Kernel spawns init (PID 1, CAP_SPAWN + CAP_ADMIN)
  init_svc_init() bridges kernel -> userspace

Phase 4: Service Startup (~500ms)                   mixed
  init -> BLK service  (PID 2, @device) -> NVMe/USB detect
  init -> VFS service  (PID 3, @safe)   -> mount /, /dev, /proc
  init -> NET service  (PID 4, @device) -> virtio-net, DHCP
  init -> Shell        (PID 5, @safe)   -> prompt ready

Phase 5: Ready (~600ms total)
  nova> _
```

---

## 5. Capability Model

Each process has a 12-bit capability bitmap checked on every syscall.

```
Bit  Name          @kernel  @device  @safe   Purpose
---  ----------    -------  -------  -----   ---------------------------
 0   CAP_IPC_SEND    Y        Y       Y     Send IPC messages
 1   CAP_IPC_RECV    Y        Y       Y     Receive IPC messages
 2   CAP_SPAWN       Y        -       Y     Spawn child processes
 3   CAP_KILL        Y        -       -     Kill other processes
 4   CAP_PORT_IO     Y        Y       -     Port I/O (SYS_PORT_IO)
 5   CAP_IRQ         Y        Y       -     Wait for IRQs
 6   CAP_DMA         Y        Y       -     Allocate DMA memory
 7   CAP_MAP_PHYS    Y        Y       -     Map physical addresses
 8   CAP_NET         Y        -       Y     Access network service
 9   CAP_FS          Y        -       Y     Access filesystem service
10   CAP_DEVICE      Y        Y       -     Access device hardware
11   CAP_ADMIN       Y        -       -     Shutdown / reboot
```

Default bitmaps: `@kernel = 0xFFF (all)`, `@device = 0x4F3`, `@safe = 0x307`.

The compiler enforces context at build time. The capability system enforces it at runtime. Together they provide defense-in-depth: even if a service is compromised, it cannot exceed its capability mask.

---

## 6. IPC Message Format

```
 0       8       12      16                      56      64
 +-------+-------+-------+-----------------------+-------+
 |src_pid|msg_type|msg_id |    payload (40 bytes) |reservd|
 | 8B    | 4B     | 4B    |    40B                | 8B    |
 +-------+-------+-------+-----------------------+-------+
                           Total: 64 bytes fixed
```

Message types: `0x01xx` = VFS, `0x02xx` = BLK, `0x03xx` = NET, `0x04xx` = DEV, `0x05xx` = IRQ.

---

## 7. Syscall Table (18 calls)

Console/Process: `EXIT(0)`, `WRITE(1)`, `READ(2)`, `GETPID(3)`, `YIELD(4)`, `SLEEP(5)`, `MMAP(6)`.
IPC: `SEND(10)`, `RECV(11)`, `CALL(12)`, `REPLY(13)`, `NOTIFY(14)`.
Memory: `MUNMAP(21)`, `SHARE(22)`.
I/O (cap required): `IRQ_WAIT(30)`, `PORT_IO(31)`, `DMA_ALLOC(32)`.

---

*FajarOS Nova v2.0 Architecture Guide | 20K LOC | 9 services | 18 syscalls*
*Built with Fajar Lang + Claude Opus 4.6*
