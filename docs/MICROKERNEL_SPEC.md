# FajarOS Microkernel Specification v2.0

> **Sprint 1.1 Output:** Complete microkernel boundary definition
> **Date:** 2026-03-22

---

## 1. Microkernel Boundary

### Ring 0 — Kernel Core (actual: ~2,500 LOC — IPC larger than original 300 LOC estimate)

```
kernel/
├── core/
│   ├── sched.fj        @kernel  ~200 LOC  Scheduler + context switch
│   ├── mm.fj           @kernel  ~500 LOC  Frame alloc + paging + heap
│   ├── ipc.fj          @kernel  ~300 LOC  Message passing core
│   ├── syscall.fj      @kernel  ~200 LOC  Syscall dispatch (20 calls)
│   ├── irq.fj          @kernel  ~100 LOC  IDT + ISR routing + EOI
│   └── boot.fj         @kernel  ~100 LOC  Entry + init + constants
├── stubs/
│   ├── console.fj      @kernel   ~50 LOC  VGA + serial (debug only)
│   ├── nvme_stub.fj    @kernel   ~50 LOC  NVMe IRQ + DMA mapping
│   ├── net_stub.fj     @kernel   ~50 LOC  Virtio IRQ + DMA mapping
│   └── usb_stub.fj     @kernel   ~50 LOC  XHCI IRQ + DMA mapping
└── TOTAL                        ~1,600 LOC
```

### Ring 3 — User Services

```
services/
├── vfs/                @safe    VFS + FAT32 + RamFS
│   ├── main.fj                  Service entry + IPC loop
│   ├── vfs.fj                   Mount table + path resolution
│   ├── fat32.fj                 FAT32 driver (via BLK IPC)
│   └── ramfs.fj                 RAM filesystem
├── blk/                @safe    Block device service
│   ├── main.fj                  Service entry
│   ├── nvme.fj                  NVMe protocol (via kernel DMA stub)
│   └── usb_storage.fj           XHCI+SCSI (via kernel DMA stub)
├── net/                @device  Network service
│   ├── main.fj                  Service entry
│   ├── eth.fj                   Ethernet frames
│   ├── arp.fj                   ARP protocol
│   ├── ip.fj                    IPv4 + ICMP
│   ├── udp.fj                   UDP + DHCP
│   └── tcp.fj                   TCP + HTTP
├── shell/              @safe    Interactive shell
│   ├── main.fj                  Shell loop (via SYS_READ/SYS_WRITE)
│   ├── commands.fj              Built-in commands
│   └── scripting.fj             Script execution
└── init/               @safe    Init process (PID 1)
    └── main.fj                  Spawn services + respawn on crash
```

---

## 2. Syscall API (18 calls — as implemented)

> **Note:** Numbering preserved from monolithic v1.0 for backward compatibility.
> Original spec had SYS_SPAWN=1, SYS_WAIT=2, SYS_KILL=3 — deferred to Phase 3.

### Console + Process (legacy numbers 0-7)

| # | Name | Args | Returns | Description |
|---|------|------|---------|-------------|
| 0 | SYS_EXIT | code:i64 | — | Terminate process |
| 1 | SYS_WRITE | fd:i64, buf:ptr, len:i64 | written:i64 | Write to stdout/serial |
| 2 | SYS_READ | fd:i64, buf:ptr, len:i64 | read:i64 | Read from stdin/keyboard |
| 3 | SYS_GETPID | — | pid:i64 | Get current PID |
| 4 | SYS_YIELD | — | 0 | Voluntary reschedule |
| 5 | SYS_SLEEP | ms:i64 | 0 | Sleep for N milliseconds |
| 6 | SYS_MMAP | size:i64 | addr:i64 | Map memory pages |
| 7 | SYS_BRK | — | — | (reserved) |

### IPC (numbers 10-14)

| # | Name | Args | Returns | Description |
|---|------|------|---------|-------------|
| 10 | SYS_SEND | dst:i64, msg:ptr | 0/-1 | Send 64-byte message (blocks) |
| 11 | SYS_RECV | src:ptr, buf:ptr | sender:i64 | Receive message (blocks) |
| 12 | SYS_CALL | dst:i64, msg:ptr, reply:ptr | 0/-1 | Send + wait reply (RPC) |
| 13 | SYS_REPLY | dst:i64, msg:ptr | 0/-1 | Reply to received message |
| 14 | SYS_NOTIFY | dst:i64, bits:i64 | 0/-1 | Async notification |

### Memory (numbers 20-22)

| # | Name | Args | Returns | Description |
|---|------|------|---------|-------------|
| 21 | SYS_MUNMAP | addr:i64, len:i64 | 0/-1 | Unmap pages |
| 22 | SYS_SHARE | region:i64, pid:i64 | remote_addr:i64 | Share pages with process |

### I/O (numbers 30-32, kernel-mediated, capability required)

| # | Name | Args | Returns | Description |
|---|------|------|---------|-------------|
| 30 | SYS_IRQ_WAIT | irq:i64 | 0 | Wait for IRQ (driver only) |
| 31 | SYS_PORT_IO | port:i64, val:i64, dir:i64 | val:i64 | Port read/write (cap required) |
| 32 | SYS_DMA_ALLOC | size:i64 | phys:i64 | Allocate DMA-safe memory |

### Not Yet Implemented (deferred to Phase 3)

| # | Name | Description |
|---|------|-------------|
| 8 | SYS_SPAWN | Load ELF + create process |
| 9 | SYS_KILL | Signal/terminate process |

---

## 3. IPC Message Format

```
┌──────────────────────────────────────────────────────────────┐
│  IPC Message (64 bytes, fixed size)                           │
├──────────┬───────────┬───────────┬───────────────────────────┤
│ src_pid  │ msg_type  │ msg_id    │ payload (40 bytes)         │
│ 8 bytes  │ 4 bytes   │ 4 bytes   │ 40 bytes                  │
├──────────┴───────────┴───────────┴───────────────────────────┤
│ Total: 56 bytes used + 8 bytes reserved = 64 bytes            │
└──────────────────────────────────────────────────────────────┘
```

### Message Types (msg_type)

| Type | Value | Direction | Description |
|------|-------|-----------|-------------|
| MSG_VFS_OPEN | 0x0100 | App → VFS | Open file by path |
| MSG_VFS_READ | 0x0101 | App → VFS | Read from fd |
| MSG_VFS_WRITE | 0x0102 | App → VFS | Write to fd |
| MSG_VFS_CLOSE | 0x0103 | App → VFS | Close fd |
| MSG_VFS_STAT | 0x0104 | App → VFS | Get file info |
| MSG_VFS_LIST | 0x0105 | App → VFS | List directory |
| MSG_VFS_REPLY | 0x01FF | VFS → App | Reply with data/status |
| MSG_BLK_READ | 0x0200 | VFS → BLK | Read sectors |
| MSG_BLK_WRITE | 0x0201 | VFS → BLK | Write sectors |
| MSG_BLK_INFO | 0x0202 | VFS → BLK | Get device info |
| MSG_BLK_REPLY | 0x02FF | BLK → VFS | Reply with data |
| MSG_NET_SEND | 0x0300 | App → NET | Send packet |
| MSG_NET_RECV | 0x0301 | App → NET | Receive packet |
| MSG_NET_CONNECT | 0x0302 | App → NET | TCP connect |
| MSG_NET_REPLY | 0x03FF | NET → App | Reply with data |
| MSG_DEV_REG | 0x0400 | Drv → VFS | Register device |
| MSG_IRQ_EVENT | 0x0500 | Kernel → Drv | IRQ occurred |

### Large Data Transfer

For data >40 bytes (e.g., reading a 4KB file):
1. Sender calls `SYS_SHARE` to map buffer into receiver
2. Message payload contains: shared_addr(8) + length(8) + offset(8)
3. Receiver reads directly from shared memory (zero-copy)
4. After reply, sender unmaps shared region

---

## 4. Service Protocols

### VFS Protocol

```
OPEN:   App → VFS:  MSG_VFS_OPEN  { path[40] }
        VFS → App:  MSG_VFS_REPLY { fd(8), size(8), status(8) }

READ:   App → VFS:  MSG_VFS_READ  { fd(8), offset(8), len(8), shared_buf(8) }
        VFS → App:  MSG_VFS_REPLY { bytes_read(8), status(8) }
                    (data written to shared_buf by VFS)

WRITE:  App → VFS:  MSG_VFS_WRITE { fd(8), len(8), shared_buf(8) }
        VFS → App:  MSG_VFS_REPLY { bytes_written(8), status(8) }

CLOSE:  App → VFS:  MSG_VFS_CLOSE { fd(8) }
        VFS → App:  MSG_VFS_REPLY { status(8) }

LIST:   App → VFS:  MSG_VFS_LIST  { path[40] }
        VFS → App:  MSG_VFS_REPLY { count(8), shared_buf(8) }
```

### Block Device Protocol

```
READ:   VFS → BLK:  MSG_BLK_READ  { dev(8), lba(8), count(8), dma_buf(8) }
        BLK → VFS:  MSG_BLK_REPLY { status(8), bytes(8) }

WRITE:  VFS → BLK:  MSG_BLK_WRITE { dev(8), lba(8), count(8), dma_buf(8) }
        BLK → VFS:  MSG_BLK_REPLY { status(8) }

INFO:   VFS → BLK:  MSG_BLK_INFO  { dev(8) }
        BLK → VFS:  MSG_BLK_REPLY { total_lba(8), sector_sz(8), type(8) }
```

### Network Protocol

```
CONNECT: App → NET: MSG_NET_CONNECT { ip(4), port(2), proto(2) }
         NET → App: MSG_NET_REPLY   { conn_id(8), status(8) }

SEND:    App → NET: MSG_NET_SEND    { conn_id(8), len(8), shared_buf(8) }
         NET → App: MSG_NET_REPLY   { sent(8), status(8) }

RECV:    App → NET: MSG_NET_RECV    { conn_id(8), max_len(8), shared_buf(8) }
         NET → App: MSG_NET_REPLY   { received(8), status(8) }
```

---

## 5. Capability System

Each process has a capability bitmap (64 bits):

```
Bit  0: CAP_IPC_SEND     — can send IPC messages
Bit  1: CAP_IPC_RECV     — can receive IPC messages
Bit  2: CAP_SPAWN        — can spawn child processes
Bit  3: CAP_KILL         — can kill other processes
Bit  4: CAP_PORT_IO      — can do port I/O (via SYS_PORT_IO)
Bit  5: CAP_IRQ          — can wait for IRQs (via SYS_IRQ_WAIT)
Bit  6: CAP_DMA          — can allocate DMA memory
Bit  7: CAP_MAP_PHYS     — can map physical addresses
Bit  8: CAP_NET          — can access network service
Bit  9: CAP_FS           — can access filesystem service
Bit 10: CAP_DEVICE       — can access device hardware (@device)
Bit 11: CAP_ADMIN        — can shutdown/reboot
```

### Default Capabilities by Annotation

| Annotation | Default Caps |
|------------|-------------|
| @kernel | ALL (0xFFFFFFFFFFFFFFFF) |
| @device | IPC_SEND + IPC_RECV + PORT_IO + IRQ + DMA + MAP_PHYS + DEVICE |
| @safe | IPC_SEND + IPC_RECV + SPAWN + FS + NET |

---

## 6. Namespace System

```
/                          Root (VFS service manages)
├── dev/                   Device files (from driver registrations)
│   ├── nvme0              NVMe block device (blk_service)
│   ├── usb0               USB mass storage (blk_service)
│   ├── net0               Network interface (net_service)
│   ├── null               Null device (VFS built-in)
│   ├── zero               Zero device (VFS built-in)
│   └── random             Random device (VFS built-in)
├── proc/                  Process info (kernel queries via IPC)
│   ├── version            Kernel version string
│   ├── uptime             System uptime
│   ├── cpuinfo            CPU features
│   └── meminfo            Memory usage
├── mnt/                   Mount points
│   ├── nvme/              FAT32 from NVMe
│   └── usb/               FAT32 from USB
├── srv/                   Service endpoints (for IPC routing)
│   ├── vfs                VFS service PID
│   ├── blk                Block device service PID
│   ├── net                Network service PID
│   └── display            Display service PID
└── home/                  User home directory
```

---

## 7. Boot Sequence

```
Phase 1: Hardware Init (kernel, ~50ms)
  _start → GDT/IDT → paging → heap → serial
  PIT timer (100Hz) → keyboard IRQ → LAPIC

Phase 2: Kernel Services (kernel, ~10ms)
  Frame allocator → page table cloner → IPC init
  Syscall MSRs → capability table init

Phase 3: Init Process (PID 1, @safe, ~100ms)
  Kernel spawns init as first Ring 3 process
  init has CAP_SPAWN + CAP_ADMIN

Phase 4: Service Startup (init spawns, ~500ms)
  init → spawn blk_service (PID 2, @device)
    blk_service → detect NVMe/USB → register /dev/nvme0
  init → spawn vfs_service (PID 3, @safe)
    vfs_service → mount / (ramfs) → mount /dev → mount /proc
    vfs_service → mount /mnt/nvme (FAT32 via blk IPC)
  init → spawn net_service (PID 4, @device)
    net_service → detect virtio-net → DHCP → register /dev/net0
  init → spawn shell (PID 5, @safe)
    shell → prompt → ready

Phase 5: Ready (~1 second total boot)
  nova> _
```

---

## 8. New File Structure (v2.0)

```
fajaros-x86/
├── kernel/                      Ring 0 ONLY (@kernel)
│   ├── core/
│   │   ├── sched.fj             Scheduler + context switch
│   │   ├── mm.fj                Frame alloc + paging + heap + slab
│   │   ├── ipc.fj               IPC message passing core
│   │   ├── syscall.fj           Syscall entry + dispatch (20 calls)
│   │   ├── irq.fj               IDT + timer + LAPIC + EOI
│   │   └── cap.fj               Capability checker
│   ├── stubs/
│   │   ├── console.fj           VGA + serial (kernel debug)
│   │   ├── nvme_stub.fj         NVMe IRQ handler + DMA
│   │   ├── net_stub.fj          Virtio IRQ handler + DMA
│   │   └── usb_stub.fj          XHCI IRQ handler + DMA
│   ├── boot/
│   │   └── entry.fj             kernel_main + constants
│   └── main.fj                  Boot sequence + init spawn
│
├── services/                    Ring 3 (@safe / @device)
│   ├── init/
│   │   └── main.fj              @safe — PID 1, spawns services
│   ├── vfs/
│   │   ├── main.fj              @safe — VFS service loop
│   │   ├── vfs.fj               @safe — mount table, path resolution
│   │   ├── fat32.fj             @safe — FAT32 (via BLK IPC)
│   │   └── ramfs.fj             @safe — RAM filesystem
│   ├── blk/
│   │   ├── main.fj              @device — block service loop
│   │   ├── nvme.fj              @device — NVMe protocol
│   │   └── usb_storage.fj       @device — XHCI+SCSI
│   ├── net/
│   │   ├── main.fj              @device — network service loop
│   │   ├── eth.fj               @device — Ethernet
│   │   ├── arp.fj               @device — ARP
│   │   ├── ip.fj                @device — IPv4 + ICMP
│   │   ├── udp.fj               @device — UDP + DHCP
│   │   └── tcp.fj               @device — TCP + HTTP
│   └── shell/
│       ├── main.fj              @safe — shell process
│       ├── commands.fj          @safe — built-in commands (via IPC)
│       └── scripting.fj         @safe — script execution
│
├── apps/                        Ring 3 (@safe)
│   ├── hello.fj                 @safe — "Hello Ring 3!"
│   ├── counter.fj               @safe — count 1-10
│   └── wget.fj                  @safe — HTTP download (via net IPC)
│
├── docs/
│   ├── MICROKERNEL_SPEC.md      This document
│   ├── FAJAROS_MASTER_PLAN.md   Full roadmap
│   └── PLAN.md                  Original 30-sprint plan
│
├── Makefile                     Build kernel + services + apps
├── fj.toml                     Project config
└── grub.cfg                    GRUB2 bootloader
```

---

## 9. Build System (v2.0)

```makefile
# Kernel: concatenate kernel/ files → compile as bare-metal ELF
kernel: kernel/core/*.fj kernel/stubs/*.fj kernel/boot/*.fj kernel/main.fj
	fj build --target x86_64-none $(KERNEL_SOURCES) -o build/kernel.elf

# Services: each compiled as separate user-mode ELF
services/init:
	fj build --target x86_64-user services/init/main.fj -o build/init.elf

services/vfs:
	fj build --target x86_64-user services/vfs/*.fj -o build/vfs.elf

services/blk:
	fj build --target x86_64-user services/blk/*.fj -o build/blk.elf

services/net:
	fj build --target x86_64-user services/net/*.fj -o build/net.elf

services/shell:
	fj build --target x86_64-user services/shell/*.fj -o build/shell.elf

# Pack all into initramfs (embedded in kernel or loaded by GRUB)
initramfs: services/init services/vfs services/blk services/net services/shell
	tar cf build/initramfs.tar build/*.elf

# Boot: kernel loads initramfs → spawns init → init spawns services
boot: kernel initramfs
	grub-mkrescue ... → build/fajaros.iso
```

---

## 10. IPC Call Chain Example

### `cat /mnt/nvme/hello.txt`

```
Shell (@safe, PID 5)
  │
  ├─ SYS_CALL(vfs_pid, MSG_VFS_OPEN, "/mnt/nvme/hello.txt")
  │    │
  │    ▼
  │  VFS Service (@safe, PID 3)
  │    ├─ Resolve path: /mnt/nvme → FAT32 mount on blk_dev 0
  │    ├─ fat32_find_file("hello.txt")
  │    ├─ SYS_CALL(blk_pid, MSG_BLK_READ, {dev=0, lba=X, count=1})
  │    │    │
  │    │    ▼
  │    │  BLK Service (@device, PID 2)
  │    │    ├─ nvme_read_sectors(lba, 1, dma_buf)
  │    │    │    ├─ SYS_PORT_IO(nvme_bar + doorbell, ...)
  │    │    │    └─ SYS_IRQ_WAIT(nvme_irq)
  │    │    │         │
  │    │    │         ▼
  │    │    │       Kernel (@kernel)
  │    │    │         └─ Wake blk_service when NVMe IRQ fires
  │    │    │
  │    │    └─ SYS_REPLY(vfs_pid, {data in shared buffer})
  │    │
  │    ├─ Parse FAT32 cluster chain, read data
  │    └─ SYS_REPLY(shell_pid, {file contents in shared buffer})
  │
  └─ Print file contents to console via SYS_WRITE
```

**Total IPC hops:** 4 (shell→vfs→blk→kernel→blk→vfs→shell)
**Target latency:** <10μs for the full chain

---

*FajarOS Microkernel Spec v2.0 — compiler-enforced safety, IPC-based services*
