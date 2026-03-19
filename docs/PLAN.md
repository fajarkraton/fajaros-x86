# FajarOS x86_64 — "Nova" Implementation Plan

> **Vision:** FajarOS running natively on Intel x86_64 — the world's first OS written 100%
> in a single language that unifies kernel safety (@kernel), hardware drivers (@kernel),
> AI inference (@device), and userspace (@safe) — now on the world's most popular CPU architecture.
>
> **Codename:** "Nova" (Indonesian: bintang baru — a new star rises on x86_64)
> **Target Hardware:** Lenovo Legion Pro — Intel Core i9-14900HX (Raptor Lake)
> **Language:** 100% Fajar Lang (inline asm for privileged instructions only)
> **Repo:** `github.com/fajarkraton/fajaros-x86`
> **Date:** 2026-03-19

---

## Hardware Target: Intel Core i9-14900HX

| Component | Specification |
|-----------|--------------|
| **CPU** | Intel Core i9-14900HX (Raptor Lake-HX, 14th Gen) |
| **Cores** | 24 (8 Performance + 16 Efficiency), 32 threads |
| **Clock** | 800 MHz — 5.8 GHz (Turbo Boost Max 3.0) |
| **Cache** | 36 MB L3 (shared), 32 MB L2 (2MB/P-core, 4MB/4 E-cores) |
| **ISA** | x86_64, SSE4.2, AVX2, AVX-VNNI, SHA-NI, VMX (VT-x) |
| **RAM** | 32 GB DDR5 |
| **GPU** | NVIDIA RTX 4090 Laptop (Ada Lovelace, 16GB GDDR6) |
| **iGPU** | Intel UHD Graphics (Raptor Lake-S) |
| **Storage** | 937 GB NVMe SSD (PCIe Gen4) |
| **Network** | Intel AX211 WiFi 6E + Intel I219-LM GbE |
| **Firmware** | UEFI (Insyde H2O) |
| **Serial** | 16550-compatible UART (COM1: 0x3F8) via QEMU |
| **Platform** | Intel 700-series PCH (Raptor Lake) |

### x86_64 vs ARM64 Comparison

| Aspect | x86_64 (Nova) | ARM64 (Surya/Q6A) |
|--------|---------------|-------------------|
| Boot | Multiboot2 (GRUB) or UEFI | UEFI (QCS6490) |
| Privilege | Ring 0/3 (CPL in CS) | EL0/EL1 (exception levels) |
| Exceptions | IDT (256 vectors) | VBAR_EL1 (4 groups × 4) |
| Paging | CR3 → PML4 (4-level) | TTBR0/TTBR1 (4-level) |
| Syscalls | SYSCALL/SYSRET (MSRs) | SVC instruction |
| IRQ Controller | LAPIC + IOAPIC | GICv3 |
| Timer | LAPIC Timer / HPET / PIT | Architected Timer (CNTV) |
| Serial | 16550 UART (I/O ports) | PL011 UART (MMIO) |
| Display | VGA text (0xB8000) / GOP | Framebuffer (MIPI DSI) |
| Context Frame | ~200 bytes (16 GPR + SSE) | 272 bytes (31 GPR + SPSR) |
| SMP | APIC-based (MP table/ACPI) | PSCI (Power State Coord) |

---

## Architecture Overview

### System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 5: Applications (@safe)                     ~3,000 LOC   │
│  FajarOS Shell (fjsh), REPL, AI demo apps, package manager      │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: OS Services (@safe + @device)           ~10,000 LOC   │
│  Init daemon, VFS, RAM filesystem, process manager,             │
│  GPU compute service (RTX 4090), display compositor             │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: HAL Drivers (@kernel)                    ~8,000 LOC   │
│  16550 UART, PS/2 Keyboard, VGA Text, PCI enumeration,         │
│  NVMe block device, Intel I219 Ethernet, Framebuffer            │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Microkernel (@kernel)                    ~6,000 LOC   │
│  x86_64 boot, GDT/IDT, 4-level paging, LAPIC/IOAPIC,          │
│  scheduler, IPC, memory allocator, SYSCALL dispatch             │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Compiler Support                         ~3,000 LOC   │
│  x86_64-unknown-none target, bare-metal runtime, linker,        │
│  asm!() x86_64 constraints, port I/O intrinsics                 │
├─────────────────────────────────────────────────────────────────┤
│  Layer 0: Hardware — Intel Core i9-14900HX                      │
│  24-core hybrid (8P+16E), RTX 4090, 32GB DDR5, NVMe, WiFi 6E   │
└─────────────────────────────────────────────────────────────────┘
```

### Memory Map (x86_64 — QEMU + Real Hardware)

```
Physical Memory Layout:
0x0000_0000 — 0x0000_0FFF    Real Mode IVT + BDA (reserved)
0x0000_1000 — 0x0007_FFFF    Usable low memory (508 KB)
0x0008_0000 — 0x0009_FFFF    EBDA (Extended BIOS Data Area)
0x000A_0000 — 0x000B_FFFF    VGA memory (0xB8000 = text buffer)
0x000C_0000 — 0x000F_FFFF    ROM area (BIOS)
0x0010_0000 — 0x001F_FFFF    Kernel .text (1 MB)
0x0020_0000 — 0x002F_FFFF    Kernel .rodata (1 MB)
0x0030_0000 — 0x003F_FFFF    Kernel .data + .bss (1 MB)
0x0040_0000 — 0x007F_FFFF    Kernel heap (4 MB, expandable)
0x0080_0000 — 0x00BF_FFFF    Page tables (4 MB)
0x00C0_0000 — 0x00FF_FFFF    Kernel stacks (4 MB, 64KB per process)
0x0100_0000 — 0x01FF_FFFF    DMA / device buffers (16 MB)
0x0200_0000 — 0x0FFF_FFFF    User space processes (224 MB)
0x1000_0000 — ...             Extended memory (up to 32 GB)

I/O Port Space (x86-specific):
0x0020 — 0x0021    PIC Master (8259A)
0x0040 — 0x0043    PIT (Programmable Interval Timer)
0x0060 — 0x0064    PS/2 Keyboard/Mouse controller
0x0070 — 0x0071    CMOS/RTC
0x00A0 — 0x00A1    PIC Slave (8259A)
0x02F8 — 0x02FF    COM2 (Serial)
0x03F8 — 0x03FF    COM1 (Serial) ← primary debug output
0x0CF8 — 0x0CFF    PCI Configuration

MMIO Space:
0xB8000              VGA text buffer (80×25, 4000 bytes)
0xFEC0_0000          IOAPIC registers
0xFEE0_0000          LAPIC registers (per-CPU)
0xFED0_0000          HPET registers
```

### Boot Sequence

```
Power On (Intel i9-14900HX)
  │
  ▼
UEFI Firmware (Insyde H2O)
  ├── POST, DDR5 training, PCIe init
  ├── NVMe/USB device enumeration
  └── Load GRUB2 from EFI partition
  │
  ▼
GRUB2 Bootloader
  ├── Read grub.cfg
  ├── Load FajarOS kernel (Multiboot2 ELF)
  ├── Pass multiboot info struct to kernel
  └── Jump to kernel _start (already in long mode!)
  │
  ▼
FajarOS Kernel Entry (@kernel _start)         ← Fajar Lang code begins here
  ├── 1. Parse Multiboot2 info (memory map, framebuffer)
  ├── 2. Initialize serial console (COM1: 0x3F8, 115200 baud)
  ├── 3. Set up GDT (kernel + user segments, TSS)
  ├── 4. Set up IDT (256 vectors, exception + IRQ handlers)
  ├── 5. Initialize 4-level paging (identity + higher-half)
  ├── 6. Initialize LAPIC + IOAPIC
  ├── 7. Initialize kernel heap (bump → freelist allocator)
  ├── 8. Start LAPIC timer (preemptive scheduling)
  ├── 9. Initialize PCI bus (enumerate devices)
  ├── 10. Start scheduler, spawn init process
  │
  ▼
Init Process (@safe, Ring 3)
  ├── Mount RAM filesystem
  ├── Start device manager
  ├── Start shell (fjsh)
  └── Ready for user input
```

### Syscall Interface (x86_64 ABI)

```
Register Convention (SYSCALL instruction):
  RAX = syscall number
  RDI = arg0
  RSI = arg1
  RDX = arg2
  R10 = arg3 (note: NOT RCX — SYSCALL clobbers RCX)
  R8  = arg4
  R9  = arg5
  RAX = return value

Kernel entry (via IA32_LSTAR MSR):
  1. CPU saves RIP → RCX, RFLAGS → R11
  2. CPU loads CS/SS from IA32_STAR
  3. CPU masks RFLAGS with IA32_FMASK
  4. Jump to handler at IA32_LSTAR
  5. Handler switches to kernel stack (TSS.RSP0)

Number  Name                Context    Description
──────  ──────────────────  ─────────  ──────────────────────────────
0x00    SYS_EXIT            @safe      Terminate process (exit code in RDI)
0x01    SYS_WRITE           @safe      Write(fd=RDI, buf=RSI, len=RDX) → count
0x02    SYS_READ            @safe      Read(fd=RDI, buf=RSI, len=RDX) → count
0x03    SYS_OPEN            @safe      Open(path=RDI, flags=RSI) → fd
0x04    SYS_CLOSE           @safe      Close(fd=RDI) → 0
0x05    SYS_MMAP            @safe      Map(addr=RDI, len=RSI, prot=RDX) → addr
0x06    SYS_MUNMAP          @safe      Unmap(addr=RDI, len=RSI) → 0
0x07    SYS_SPAWN           @safe      Spawn(entry=RDI, stack=RSI) → pid
0x08    SYS_WAIT            @safe      Wait(pid=RDI) → exit_code
0x09    SYS_GETPID          @safe      GetPid() → pid
0x0A    SYS_YIELD           @safe      Yield() → 0
0x0B    SYS_IPC_SEND        @safe      Send(dst_pid=RDI, msg=RSI) → 0
0x0C    SYS_IPC_RECV        @safe      Recv(buf=RDI) → sender_pid
0x0D    SYS_SLEEP           @safe      Sleep(ms=RDI) → 0
0x0E    SYS_TIME            @safe      Time() → ms_since_boot
0x0F    SYS_SBRK            @safe      Sbrk(increment=RDI) → old_break
```

---

## Repo Structure

```
fajaros-x86/
├── README.md                     ← Project overview, build instructions
├── CLAUDE.md                     ← Claude Code session reference
├── Makefile                      ← Build orchestration (fj build + link + QEMU)
├── fj.toml                       ← Fajar Lang project manifest
├── grub.cfg                      ← GRUB2 bootloader config
├── linker.ld                     ← Custom linker script (x86_64 layout)
│
├── kernel/                       ← Kernel source (100% Fajar Lang)
│   ├── main.fj                   ← @kernel fn _start() — entry point
│   ├── boot/
│   │   ├── multiboot2.fj         ← Multiboot2 header + info parsing
│   │   ├── gdt.fj                ← GDT setup (kernel/user segments, TSS)
│   │   └── early_console.fj      ← Serial + VGA init before full kernel
│   ├── mm/
│   │   ├── paging.fj             ← 4-level page tables (PML4)
│   │   ├── phys_alloc.fj         ← Physical frame allocator (bitmap)
│   │   ├── heap.fj               ← Kernel heap (bump → freelist)
│   │   └── vmm.fj                ← Virtual memory manager
│   ├── interrupts/
│   │   ├── idt.fj                ← IDT setup (256 vectors)
│   │   ├── exceptions.fj         ← CPU exception handlers (#PF, #GP, #DF, etc.)
│   │   ├── apic.fj               ← LAPIC + IOAPIC driver
│   │   └── pic.fj                ← Legacy 8259 PIC (fallback)
│   ├── sched/
│   │   ├── process.fj            ← Process struct, creation, destruction
│   │   ├── scheduler.fj          ← Round-robin + priority scheduler
│   │   ├── context.fj            ← x86_64 context switch (register save/restore)
│   │   └── timer.fj              ← LAPIC timer for preemption
│   ├── syscall/
│   │   ├── entry.fj              ← SYSCALL/SYSRET handler (MSR setup)
│   │   ├── dispatch.fj           ← Syscall number → handler routing
│   │   └── handlers.fj           ← Individual syscall implementations
│   ├── ipc/
│   │   ├── message.fj            ← Message queue per process
│   │   └── pipe.fj               ← Pipe implementation
│   └── panic.fj                  ← Kernel panic handler (serial + VGA dump)
│
├── drivers/                      ← Device drivers (100% Fajar Lang)
│   ├── serial.fj                 ← 16550 UART driver (COM1/COM2)
│   ├── vga.fj                    ← VGA text mode (80×25)
│   ├── keyboard.fj               ← PS/2 keyboard (scancode → ASCII)
│   ├── pit.fj                    ← PIT timer (fallback, 8254)
│   ├── pci.fj                    ← PCI bus enumeration
│   ├── nvme.fj                   ← NVMe block device driver
│   ├── framebuffer.fj            ← UEFI/Multiboot2 framebuffer
│   └── rtc.fj                    ← CMOS Real-Time Clock
│
├── fs/                           ← Filesystem (100% Fajar Lang)
│   ├── vfs.fj                    ← Virtual filesystem layer
│   ├── ramfs.fj                  ← In-memory filesystem
│   └── fat32.fj                  ← FAT32 for NVMe/USB
│
├── shell/                        ← User-space shell (100% Fajar Lang)
│   ├── fjsh.fj                   ← Shell main loop (prompt, parse, execute)
│   ├── commands.fj               ← Built-in commands (ls, cat, echo, ps, etc.)
│   └── sysinfo.fj                ← System info (CPU, memory, uptime, etc.)
│
├── apps/                         ← Demo applications
│   ├── hello.fj                  ← Hello World (Ring 3)
│   ├── fibonacci.fj              ← CPU benchmark (JIT vs native)
│   ├── sysmon.fj                 ← System monitor (CPU, mem, processes)
│   └── ai_demo.fj                ← ML inference demo
│
├── tests/                        ← Test infrastructure
│   ├── boot_test.fj              ← Boot sequence validation
│   ├── mm_test.fj                ← Memory management tests
│   ├── sched_test.fj             ← Scheduler tests
│   ├── syscall_test.fj           ← Syscall tests
│   └── driver_test.fj            ← Driver tests
│
├── tools/                        ← Build & test tools
│   ├── make_iso.sh               ← Create bootable ISO (GRUB2 + kernel)
│   ├── run_qemu.sh               ← Launch QEMU x86_64 with KVM
│   ├── debug_qemu.sh             ← QEMU + GDB server
│   └── test_all.sh               ← Run all tests in QEMU
│
└── docs/
    ├── ARCHITECTURE.md            ← System design & memory layout
    ├── BOOT_SEQUENCE.md           ← Detailed boot documentation
    ├── SYSCALLS.md                ← Syscall reference
    └── PORTING_FROM_ARM64.md      ← Differences from FajarOS Surya
```

---

## Implementation Plan

### Summary

| # | Phase | Sprints | Tasks | Focus |
|---|-------|---------|-------|-------|
| 1 | Foundation | S1-S3 | 30 | Boot, serial, GDT, hello world on QEMU |
| 2 | Memory | S4-S6 | 30 | Paging, heap, physical allocator |
| 3 | Interrupts | S7-S9 | 30 | IDT, exceptions, LAPIC, timer |
| 4 | Scheduler | S10-S12 | 30 | Processes, context switch, preemption |
| 5 | Syscalls & User Space | S13-S15 | 30 | Ring 3, SYSCALL/SYSRET, IPC |
| 6 | Drivers | S16-S18 | 30 | Keyboard, VGA, PCI, NVMe |
| 7 | Filesystem & Shell | S19-S21 | 30 | VFS, ramfs, fjsh, 50+ commands |
| 8 | SMP & Advanced | S22-S24 | 30 | Multi-core, ACPI, hardening |
| 9 | AI & GPU | S25-S27 | 30 | RTX 4090 compute, ML inference |
| 10 | Production | S28-S30 | 30 | Polish, docs, benchmarks, release |
| **Total** | **10 phases** | **30 sprints** | **300 tasks** | |

---

## Phase 1: Foundation (Sprints 1-3)

> **Goal:** Boot FajarOS on QEMU x86_64, print "Hello from FajarOS Nova" via serial + VGA.
> **Gate:** Multiboot2-compatible ELF boots in QEMU, serial and VGA output working.
> **Hardware needed:** None (QEMU only)

### Sprint 1: Repo Setup & Compiler x86_64 Bare-Metal Target

| # | Task | Detail | Status |
|---|------|--------|--------|
| 1.1 | **Create fajaros-x86 repo** | `gh repo create fajarkraton/fajaros-x86 --public`, README, CLAUDE.md, .gitignore | [x] |
| 1.2 | **Create fj.toml** | Project manifest with `target = "x86_64-unknown-none"`, kernel entry point | [x] |
| 1.3 | **Create Makefile** | Build targets: `make build`, `make run` (QEMU), `make debug` (QEMU+GDB), `make iso` | [x] |
| 1.4 | **Add x86_64 port I/O intrinsics** | `port_inb(port) -> u8`, `port_outb(port, val)` as compiler builtins for `in`/`out` instructions | [x] |
| 1.5 | **Update linker.rs for x86_64 bare-metal** | Correct memory layout: .text at 0x100000, .rodata, .data, .bss, .stack. Multiboot2 header section first. | [x] |
| 1.6 | **Update runtime_bare.rs UART for x86_64** | Detect x86_64 target → use 0x3F8 (port I/O) instead of 0x09000000 (MMIO). Use `out` instruction for serial. | [x] |
| 1.7 | **Create x86_64 _start wrapper** | Compiler generates: disable interrupts (cli), set stack, zero BSS, call kernel_main, halt (hlt loop) | [x] |
| 1.8 | **Create kernel/main.fj** | Minimal: `@kernel fn kernel_main() { println("Hello from FajarOS Nova!") }` | [x] |
| 1.9 | **Test: compile to x86_64 bare-metal ELF** | `fj build --target x86_64-none kernel/main.fj` → valid ELF64 x86_64 binary | [x] |
| 1.10 | **Test: boot in QEMU** | `qemu-system-x86_64 -kernel fajaros.elf -serial stdio -nographic` → "Hello" on serial | [x] |

### Sprint 2: Multiboot2 Boot Protocol

| # | Task | Detail | Status |
|---|------|--------|--------|
| 2.1 | **Generate Multiboot2 header in ELF** | Magic 0xE85250D6, architecture 0 (i386/x86), checksum. Embed in `.multiboot_header` section. | [ ] |
| 2.2 | **Parse Multiboot2 boot info** | Read memory map tag (type 6): base_addr, length, type for each region. Store in global. | [ ] |
| 2.3 | **Parse framebuffer info** | Multiboot2 tag type 8: framebuffer addr, pitch, width, height, bpp. Store for VGA/GOP. | [ ] |
| 2.4 | **Implement serial driver (16550 UART)** | `serial_init(port, baud)`, `serial_write_byte(port, byte)`, `serial_write_str(port, ptr, len)`. COM1=0x3F8. | [ ] |
| 2.5 | **Implement VGA text mode driver** | `vga_init()`, `vga_putchar(ch, color)`, `vga_write_str(ptr, len)`, `vga_clear()`. Buffer at 0xB8000. | [ ] |
| 2.6 | **Implement kernel panic handler** | `@kernel fn panic(msg: str)` → print to serial + VGA, register dump (rax-r15, rip, rsp, rflags), halt. | [ ] |
| 2.7 | **Create GRUB2 config** | `grub.cfg` with `multiboot2 /boot/fajaros.elf`. Support both serial and VGA console. | [ ] |
| 2.8 | **Create ISO builder script** | `tools/make_iso.sh`: create boot/grub directory, copy kernel, run `grub-mkrescue` → fajaros.iso. | [ ] |
| 2.9 | **Test: boot ISO in QEMU** | `qemu-system-x86_64 -cdrom fajaros.iso -serial stdio` → boot via GRUB → serial output | [ ] |
| 2.10 | **Test: VGA text output** | Boot → see "FajarOS Nova" banner on VGA screen (80×25 text mode, white on blue) | [ ] |

### Sprint 3: GDT & Basic CPU Setup

| # | Task | Detail | Status |
|---|------|--------|--------|
| 3.1 | **Implement GDT structure** | 5 entries: null, kernel code (CS=0x08), kernel data (SS=0x10), user code (CS=0x1B), user data (SS=0x23). Long mode descriptors (L=1). | [ ] |
| 3.2 | **Implement TSS structure** | Task State Segment: RSP0 (kernel stack), RSP1/2 (unused), IST[1-7] (interrupt stacks). 104 bytes. | [ ] |
| 3.3 | **Load GDT via asm!** | `asm!("lgdt [{gdt_ptr}]", ...)` → reload CS (far jump), reload DS/ES/FS/GS/SS. | [ ] |
| 3.4 | **Load TSS via asm!** | `asm!("ltr ax", in("ax") tss_selector)`. TSS selector = 0x28 (6th GDT entry). | [ ] |
| 3.5 | **Implement CPUID reader** | `cpuid(leaf) -> (eax, ebx, ecx, edx)` via asm!. Read CPU vendor, features, topology. | [ ] |
| 3.6 | **Detect CPU features** | Check: SSE, SSE2, AVX, AVX2, APIC, x2APIC, NX bit, SMEP, SMAP, FSGSBASE. Store in global. | [ ] |
| 3.7 | **Print CPU info at boot** | "Intel Core i9-14900HX, 24 cores, AVX2, 36MB L3 cache" on serial console. | [ ] |
| 3.8 | **Enable SSE/SSE2** | Set CR0.EM=0, CR0.MP=1, CR4.OSFXSR=1, CR4.OSXMMEXCPT=1. Required for Cranelift-generated code. | [ ] |
| 3.9 | **Test: GDT loaded correctly** | Read CS/DS/SS selectors → verify kernel mode (RPL=0). | [ ] |
| 3.10 | **Test: CPUID detects features** | Verify AVX2, APIC, NX reported correctly. | [ ] |

**Phase 1 Gate:**
- [ ] FajarOS boots in QEMU x86_64 via Multiboot2
- [ ] Serial output (COM1) and VGA text output working
- [ ] GDT + TSS loaded, long mode confirmed
- [ ] CPU features detected (APIC, SSE, AVX2, NX)
- [ ] All 30 tasks pass
- [ ] Panic handler shows register dump

---

## Phase 2: Memory Management (Sprints 4-6)

> **Goal:** Full virtual memory with 4-level paging, kernel heap, physical frame allocator.
> **Gate:** `kmalloc(size)` / `kfree(ptr)` work. Page fault handler catches bad access.
> **Hardware needed:** None (QEMU only)

### Sprint 4: Physical Memory Manager

| # | Task | Detail | Status |
|---|------|--------|--------|
| 4.1 | **Parse Multiboot2 memory map** | Iterate memory map tags → build list of usable physical regions. Skip reserved/ACPI/firmware. | [ ] |
| 4.2 | **Implement bitmap allocator** | 1 bit per 4KB frame. For 32GB RAM = 8M frames = 1MB bitmap. `frame_alloc() -> PhysAddr`, `frame_free(addr)`. | [ ] |
| 4.3 | **Mark kernel memory as used** | Frames from 0x100000 to kernel_end marked as allocated in bitmap. | [ ] |
| 4.4 | **Mark Multiboot2 info as used** | Bootloader info struct memory preserved until fully parsed. | [ ] |
| 4.5 | **Implement frame statistics** | `total_frames()`, `used_frames()`, `free_frames()` for monitoring. | [ ] |
| 4.6 | **Implement region allocator** | `alloc_contiguous(count) -> PhysAddr` for DMA buffers (must be physically contiguous). | [ ] |
| 4.7 | **Test: allocate and free 1000 frames** | Alloc 1000, free all, alloc 1000 again → no leak. | [ ] |
| 4.8 | **Test: OOM handling** | Allocate until exhausted → returns error (not panic). | [ ] |
| 4.9 | **Test: contiguous allocation** | Allocate 16 contiguous frames for DMA → verify physically adjacent. | [ ] |
| 4.10 | **Test: memory map parsing** | Verify correct region detection from Multiboot2 info. | [ ] |

### Sprint 5: 4-Level Paging

| # | Task | Detail | Status |
|---|------|--------|--------|
| 5.1 | **Implement page table structures** | PML4Entry, PDPTEntry, PDEntry, PTEntry — 512 entries each, 64-bit. Flags: P, RW, US, PWT, PCD, A, D, NX. | [ ] |
| 5.2 | **Implement identity mapping (0-4GB)** | Map physical 0x0-0xFFFF_FFFF → virtual 0x0-0xFFFF_FFFF using 2MB huge pages (PD level). For boot transition. | [ ] |
| 5.3 | **Implement kernel higher-half mapping** | Map kernel at virtual 0xFFFF_FFFF_8000_0000 → physical 0x100000. Standard higher-half kernel layout. | [ ] |
| 5.4 | **Load page tables into CR3** | `asm!("mov cr3, {pml4}", ...)`. Flush TLB automatically on CR3 write. | [ ] |
| 5.5 | **Implement `map_page(virt, phys, flags)`** | Walk PML4→PDPT→PD→PT, allocate intermediate tables as needed, set leaf entry. | [ ] |
| 5.6 | **Implement `unmap_page(virt)`** | Clear PT entry, `invlpg` to flush single TLB entry. | [ ] |
| 5.7 | **Enable NX bit** | Set EFER.NXE (IA32_EFER MSR bit 11). Mark .data/.bss/.stack as NX. | [ ] |
| 5.8 | **Implement INVLPG wrapper** | `tlb_flush_page(virt_addr)` via `asm!("invlpg [{addr}]")`. For single-page invalidation. | [ ] |
| 5.9 | **Test: map/unmap page** | Map 0x1000_0000 → frame, write data, read back. Unmap, verify page fault. | [ ] |
| 5.10 | **Test: NX enforcement** | Mark data page NX → attempt execute → #PF with NX violation flag. | [ ] |

### Sprint 6: Kernel Heap

| # | Task | Detail | Status |
|---|------|--------|--------|
| 6.1 | **Implement bump allocator** | Simple: `heap_ptr += size; return old_ptr`. Fast, no fragmentation handling. For early boot. | [ ] |
| 6.2 | **Implement freelist allocator** | Linked list of free blocks. `kmalloc(size)` finds best-fit. `kfree(ptr)` merges adjacent. | [ ] |
| 6.3 | **Implement slab allocator** | Pre-sized caches for 32, 64, 128, 256, 512, 1024, 2048, 4096 byte objects. Fast allocation. | [ ] |
| 6.4 | **Auto-grow heap** | When heap exhausted, map new pages via `map_page()`. Expand from 4MB to max 256MB. | [ ] |
| 6.5 | **Heap statistics** | `heap_used()`, `heap_free()`, `heap_total()`. Print in `sysinfo` command. | [ ] |
| 6.6 | **Double-free detection** | Magic number in freed blocks. Detect use-after-free and double-free (debug mode). | [ ] |
| 6.7 | **Alignment support** | `kmalloc_aligned(size, align)` for DMA buffers (page-aligned), SIMD data (32-byte aligned). | [ ] |
| 6.8 | **Test: 10000 alloc/free cycles** | Random sizes 1-4096 bytes, alloc and free in random order → no corruption. | [ ] |
| 6.9 | **Test: heap auto-grow** | Allocate 8MB from 4MB heap → triggers page mapping → succeeds. | [ ] |
| 6.10 | **Test: double-free panics** | Free same pointer twice → kernel panic with helpful message. | [ ] |

**Phase 2 Gate:**
- [ ] Physical frame allocator manages all RAM from Multiboot2 memory map
- [ ] 4-level paging with identity + higher-half mapping
- [ ] Kernel heap with slab allocator (kmalloc/kfree)
- [ ] NX bit enforcement on data/stack pages
- [ ] All 30 tasks pass

---

## Phase 3: Interrupts & Exceptions (Sprints 7-9)

> **Goal:** Full interrupt handling — CPU exceptions, hardware IRQs, LAPIC timer.
> **Gate:** Timer fires 100 times/second, page fault handler recovers, keyboard input works.
> **Hardware needed:** None (QEMU only)

### Sprint 7: IDT & CPU Exceptions

| # | Task | Detail | Status |
|---|------|--------|--------|
| 7.1 | **Implement IDT structure** | 256 entries × 16 bytes = 4096 bytes. Gate descriptor: offset[0:15], selector, IST, type_attr, offset[16:63]. | [ ] |
| 7.2 | **Generate exception stubs (asm!)** | 32 stubs for vectors 0-31. Push error code (or dummy 0), push vector number, jump to common handler. | [ ] |
| 7.3 | **Implement common exception handler** | Save all GPRs (rax-r15, rbp), pass `InterruptFrame` to Fajar Lang handler, restore GPRs, `iretq`. | [ ] |
| 7.4 | **Implement InterruptFrame struct** | `{ rip, cs, rflags, rsp, ss, error_code, vector, rax, rbx, ..., r15, rbp }` — full context. | [ ] |
| 7.5 | **Handle #DE (Divide by Zero, vec 0)** | Print "Division by zero at RIP=0x...", halt or kill process. | [ ] |
| 7.6 | **Handle #PF (Page Fault, vec 14)** | Read CR2 (faulting address), decode error code (P/W/U/I/PK), print info, halt or map page. | [ ] |
| 7.7 | **Handle #GP (General Protection, vec 13)** | Print "General Protection Fault at RIP=0x..., error=0x...", register dump, halt. | [ ] |
| 7.8 | **Handle #DF (Double Fault, vec 8)** | Use IST[1] (separate stack). Print "DOUBLE FAULT — KERNEL BUG", full dump, halt forever. | [ ] |
| 7.9 | **Load IDT via asm!** | `asm!("lidt [{idt_ptr}]")`. IDT descriptor: 10 bytes (2 limit + 8 base address). | [ ] |
| 7.10 | **Test: trigger and handle #PF** | Access unmapped address → #PF → handler prints info → kernel continues (or halts cleanly). | [ ] |

### Sprint 8: LAPIC & IOAPIC

| # | Task | Detail | Status |
|---|------|--------|--------|
| 8.1 | **Detect APIC via CPUID** | CPUID leaf 1, EDX bit 9 = APIC present. Read APIC base from IA32_APIC_BASE MSR. | [ ] |
| 8.2 | **Map LAPIC MMIO registers** | Default at 0xFEE0_0000 (physical). Map to same virtual address (identity mapped). | [ ] |
| 8.3 | **Initialize LAPIC** | Set spurious interrupt vector (0xFF), enable APIC (bit 8 of SVR). | [ ] |
| 8.4 | **Implement LAPIC EOI** | Write 0 to offset 0xB0 (End of Interrupt). Must be called at end of every IRQ handler. | [ ] |
| 8.5 | **Detect IOAPIC via ACPI MADT** | Parse ACPI RSDP → RSDT/XSDT → MADT table → find IOAPIC entry (base address, GSI base). | [ ] |
| 8.6 | **Initialize IOAPIC** | Map IOAPIC at 0xFEC0_0000. Configure redirection entries for IRQs 0-23. | [ ] |
| 8.7 | **Route keyboard IRQ** | IOAPIC redirection entry for IRQ 1 → LAPIC vector 33 (0x21). | [ ] |
| 8.8 | **Route timer IRQ** | IOAPIC redirection entry for IRQ 0 → LAPIC vector 32 (0x20). Or use LAPIC timer directly. | [ ] |
| 8.9 | **Disable legacy PIC (8259)** | Remap PIC to vectors 32-47, then mask all PIC IRQs (use APIC instead). | [ ] |
| 8.10 | **Test: LAPIC spurious interrupt** | Verify spurious vector 0xFF is handled without crash. | [ ] |

### Sprint 9: LAPIC Timer & Preemption Clock

| # | Task | Detail | Status |
|---|------|--------|--------|
| 9.1 | **Calibrate LAPIC timer** | Use PIT or TSC to measure LAPIC frequency. Set initial count for 10ms ticks (100 Hz). | [ ] |
| 9.2 | **Configure LAPIC timer** | Periodic mode, vector 32 (0x20), divide by 16. Write initial count = freq/100. | [ ] |
| 9.3 | **Implement timer IRQ handler** | Vector 32: increment tick counter, call `scheduler_tick()`, send EOI. | [ ] |
| 9.4 | **Implement uptime tracking** | `time_since_boot() -> u64` returns milliseconds. Based on tick counter × 10ms. | [ ] |
| 9.5 | **Implement sleep_ms()** | `sleep_ms(ms)` busy-waits on tick counter. Later: proper sleep queue. | [ ] |
| 9.6 | **Implement TSC reader** | `rdtsc() -> u64` via asm!. Monotonic, high-resolution (nanosecond). For benchmarking. | [ ] |
| 9.7 | **Implement delay_us()** | Microsecond delay using TSC. For driver timing requirements. | [ ] |
| 9.8 | **Print tick count on boot** | After 1 second: "Timer: 100 ticks in 1 second — OK". Calibration verification. | [ ] |
| 9.9 | **Test: timer fires 100 times/second** | Count ticks over 1 second (TSC calibrated) → expect 98-102 ticks. | [ ] |
| 9.10 | **Test: uptime accuracy** | After 5-second busy loop → `time_since_boot()` reports 5000 ± 100 ms. | [ ] |

**Phase 3 Gate:**
- [ ] IDT loaded, 32 exception vectors handled
- [ ] Page fault (#PF) shows faulting address + error decode
- [ ] LAPIC + IOAPIC initialized, legacy PIC disabled
- [ ] LAPIC timer fires 100 Hz (verified)
- [ ] All 30 tasks pass

---

## Phase 4: Scheduler & Processes (Sprints 10-12)

> **Goal:** Preemptive multitasking — multiple processes running concurrently.
> **Gate:** 4 processes running simultaneously, timer-driven context switch, round-robin scheduling.
> **Hardware needed:** None (QEMU only)

### Sprint 10: Process Structure

| # | Task | Detail | Status |
|---|------|--------|--------|
| 10.1 | **Define Process struct** | `{ pid, state, name, rsp, cr3, kernel_stack, user_stack, entry, priority, ticks }` | [ ] |
| 10.2 | **Define ProcessState enum** | `Ready, Running, Blocked, Sleeping(until_tick), Zombie, Dead` | [ ] |
| 10.3 | **Implement process table** | Fixed array of 64 processes (expandable later). `MAX_PROCS = 64`. | [ ] |
| 10.4 | **Implement PID allocator** | `alloc_pid() -> u16`, `free_pid(pid)`. Bitmap-based. PID 0 = kernel, PID 1 = init. | [ ] |
| 10.5 | **Implement process creation** | `create_process(name, entry_fn) -> pid`. Allocate kernel stack (64KB), set initial register context. | [ ] |
| 10.6 | **Set initial register context** | New process starts with: RIP=entry, RSP=stack_top, RFLAGS=0x202 (IF=1), CS=kernel_cs, SS=kernel_ss. | [ ] |
| 10.7 | **Implement process destruction** | `destroy_process(pid)`. Free stacks, page tables, mark Dead. | [ ] |
| 10.8 | **Implement idle process** | PID 0: `loop { asm!("hlt") }`. Runs when no other process is ready. | [ ] |
| 10.9 | **Test: create 4 processes** | Create 4 processes → verify PIDs 1-4 allocated, states = Ready. | [ ] |
| 10.10 | **Test: destroy process** | Create → destroy → PID recycled on next create. | [ ] |

### Sprint 11: Context Switch

| # | Task | Detail | Status |
|---|------|--------|--------|
| 11.1 | **Define x86_64 context frame** | Save: RAX, RBX, RCX, RDX, RSI, RDI, RBP, R8-R15, RIP, RFLAGS, RSP, CR3. 17 × 8 = 136 bytes. | [ ] |
| 11.2 | **Implement save_context (asm!)** | Push all GPRs to current kernel stack. Save RSP to process.rsp. | [ ] |
| 11.3 | **Implement restore_context (asm!)** | Load RSP from next process.rsp. Pop all GPRs. `ret` to resume at saved RIP. | [ ] |
| 11.4 | **Implement switch_to(next_pid)** | Save current → restore next. If different CR3, load new page tables. | [ ] |
| 11.5 | **Update TSS.RSP0 on switch** | TSS.RSP0 = next process's kernel stack top. Required for Ring 3→0 transitions. | [ ] |
| 11.6 | **Handle FPU/SSE state** | FXSAVE/FXRSTOR (512 bytes) for XMM0-XMM15, x87 state. Lazy save (CR0.TS bit). | [ ] |
| 11.7 | **Implement first process switch** | Kernel → Process 1: special case (no save, only restore). | [ ] |
| 11.8 | **Test: switch between 2 processes** | Process A prints "A", Process B prints "B" → see interleaved output. | [ ] |
| 11.9 | **Test: register preservation** | Process sets RAX=0xDEAD, context switch, resume → RAX still 0xDEAD. | [ ] |
| 11.10 | **Test: 100 context switches** | Rapid switching between 4 processes → no corruption, no crash. | [ ] |

### Sprint 12: Preemptive Scheduler

| # | Task | Detail | Status |
|---|------|--------|--------|
| 12.1 | **Implement round-robin scheduler** | `scheduler_tick()`: if current process used its quantum (10ms), switch to next Ready process. | [ ] |
| 12.2 | **Integrate with timer IRQ** | Timer handler (vector 32) calls `scheduler_tick()`. Context switch happens in IRQ return path. | [ ] |
| 12.3 | **Implement yield syscall** | `SYS_YIELD`: voluntarily give up remaining quantum → immediate reschedule. | [ ] |
| 12.4 | **Implement sleep syscall** | `SYS_SLEEP(ms)`: set state=Sleeping(current_tick + ms/10), reschedule. Wake when tick reached. | [ ] |
| 12.5 | **Implement wait syscall** | `SYS_WAIT(pid)`: set state=Blocked, record waited pid. Wake when child exits. | [ ] |
| 12.6 | **Implement process exit** | `SYS_EXIT(code)`: set state=Zombie, store exit code, wake parent if waiting. | [ ] |
| 12.7 | **Implement ps command data** | `get_process_list()` returns array of `(pid, name, state, ticks)` for each process. | [ ] |
| 12.8 | **Print scheduler stats** | On boot: "Scheduler: 4 processes, 100 Hz timer, round-robin". | [ ] |
| 12.9 | **Test: preemptive switching** | 2 infinite-loop processes → both get CPU time (verified by interleaved output). | [ ] |
| 12.10 | **Test: sleep accuracy** | Process sleeps 500ms → wakes at tick ~50 (±2). | [ ] |

**Phase 4 Gate:**
- [ ] 4 processes run concurrently with preemptive scheduling
- [ ] Context switch preserves all registers correctly
- [ ] yield, sleep, wait, exit syscalls working
- [ ] FPU/SSE state saved/restored across switches
- [ ] All 30 tasks pass

---

## Phase 5: Syscalls & User Space (Sprints 13-15)

> **Goal:** Ring 3 user processes with SYSCALL/SYSRET fast path + IPC.
> **Gate:** User process at Ring 3 communicates with kernel via syscalls and other processes via IPC.
> **Hardware needed:** None (QEMU only)

### Sprint 13: SYSCALL/SYSRET Mechanism

| # | Task | Detail | Status |
|---|------|--------|--------|
| 13.1 | **Configure SYSCALL MSRs** | IA32_STAR (selector bases), IA32_LSTAR (handler address), IA32_FMASK (RFLAGS mask). | [ ] |
| 13.2 | **Implement syscall entry (asm!)** | Save user RSP, load kernel RSP from TSS.RSP0, save RCX/R11, push context, call dispatch. | [ ] |
| 13.3 | **Implement syscall dispatch** | `syscall_dispatch(num, arg0..arg5) -> i64`. Match on syscall number, call handler. | [ ] |
| 13.4 | **Implement SYSRET return** | Restore user context, `sysretq` (loads RIP from RCX, RFLAGS from R11, switches to Ring 3). | [ ] |
| 13.5 | **Implement SYS_WRITE** | Write(fd, buf, len): fd=1 → serial output, fd=2 → serial error. Validate user buffer pointer. | [ ] |
| 13.6 | **Implement SYS_READ** | Read(fd, buf, len): fd=0 → keyboard input buffer. Block until data available. | [ ] |
| 13.7 | **Implement SYS_EXIT** | Exit(code): destroy process, free resources, wake parent. | [ ] |
| 13.8 | **Implement SYS_GETPID** | GetPid(): return current process PID. | [ ] |
| 13.9 | **Test: syscall from Ring 3** | User process calls `syscall(SYS_WRITE, 1, "hello", 5)` → "hello" on serial. | [ ] |
| 13.10 | **Test: SYSRET returns correctly** | After syscall, user process resumes at correct RIP with correct RFLAGS. | [ ] |

### Sprint 14: Ring 3 User Mode

| # | Task | Detail | Status |
|---|------|--------|--------|
| 14.1 | **Create user address space** | Per-process page tables: user code at 0x400000, user stack at 0x7FFF_FFFF_F000 (grows down). | [ ] |
| 14.2 | **Map user code pages** | Copy process .text to user pages. Mark as User (US=1), Read-Only + Execute. | [ ] |
| 14.3 | **Map user stack pages** | 8 pages (32KB) at top of user VA. Mark as User, Read-Write, NX. | [ ] |
| 14.4 | **Implement Ring 0→3 transition** | First entry to user: build iretq frame (user CS=0x1B, user SS=0x23, user RSP, user RIP, RFLAGS with IF=1). | [ ] |
| 14.5 | **Enable SMEP** | Set CR4.SMEP=1. Kernel cannot execute user-space code (prevents ret2usr attacks). | [ ] |
| 14.6 | **Enable SMAP** | Set CR4.SMAP=1. Kernel cannot access user data unless STAC/CLAC. Wrap copy_from_user/copy_to_user. | [ ] |
| 14.7 | **Implement copy_from_user()** | `asm!("stac") → memcpy → asm!("clac")`. Validate user pointer range before access. | [ ] |
| 14.8 | **Implement copy_to_user()** | Same pattern for kernel→user copies. Used by SYS_READ. | [ ] |
| 14.9 | **Test: user code runs at Ring 3** | User process reads CS → RPL=3 (Ring 3 confirmed). | [ ] |
| 14.10 | **Test: user cannot access kernel** | User process reads 0xFFFF_FFFF_8010_0000 → #PF → process killed (not kernel crash). | [ ] |

### Sprint 15: IPC (Inter-Process Communication)

| # | Task | Detail | Status |
|---|------|--------|--------|
| 15.1 | **Implement message queue** | Per-process: circular buffer of 16 messages. `Message { sender_pid, data: [u8; 64] }`. | [ ] |
| 15.2 | **Implement SYS_IPC_SEND** | Send(dst_pid, msg_ptr): copy message to dst's queue. Wake dst if blocked on recv. | [ ] |
| 15.3 | **Implement SYS_IPC_RECV** | Recv(buf_ptr): if queue empty → block (state=Blocked). When message arrives → wake, copy to buf. | [ ] |
| 15.4 | **Implement SYS_SPAWN** | Spawn(name, entry): create new user process, return child PID. | [ ] |
| 15.5 | **Implement SYS_WAIT** | Wait(pid): block until child exits, return exit code. | [ ] |
| 15.6 | **Implement SYS_KILL** | Kill(pid, signal): terminate target process (signal 9) or send signal. | [ ] |
| 15.7 | **Implement pipe** | `pipe() -> (read_fd, write_fd)`. 4KB internal buffer. Read blocks when empty, write blocks when full. | [ ] |
| 15.8 | **Implement SYS_MMAP** | Map(addr, len, prot): allocate physical frames, map into user space. For dynamic memory. | [ ] |
| 15.9 | **Test: IPC send/recv between 2 processes** | Process A sends "HELLO" to Process B → B receives, prints, confirms. | [ ] |
| 15.10 | **Test: pipe data transfer** | Writer sends 1000 bytes through pipe → reader receives all 1000 correctly. | [ ] |

**Phase 5 Gate:**
- [ ] SYSCALL/SYSRET fast path working (< 500 cycles overhead)
- [ ] User processes run at Ring 3 with separate address spaces
- [ ] SMEP + SMAP enabled (kernel/user isolation)
- [ ] IPC message passing between processes
- [ ] Pipes for streaming data
- [ ] All 30 tasks pass

---

## Phase 6: Drivers (Sprints 16-18)

> **Goal:** Keyboard input, VGA display, PCI device discovery.
> **Gate:** Interactive shell with keyboard input and VGA output.
> **Hardware needed:** None (QEMU only)

### Sprint 16: PS/2 Keyboard Driver

| # | Task | Detail | Status |
|---|------|--------|--------|
| 16.1 | **Implement PS/2 controller init** | Disable devices (port 0x64), flush output buffer, set config byte, enable port 1, reset keyboard. | [ ] |
| 16.2 | **Implement scancode set 1 decoder** | Map make codes (0x01-0x58) → ASCII characters. Handle shift/ctrl/alt modifiers. | [ ] |
| 16.3 | **Implement key event queue** | Ring buffer (256 entries): `KeyEvent { scancode, ascii, pressed, shift, ctrl, alt }`. | [ ] |
| 16.4 | **Wire keyboard IRQ (vector 33)** | IOAPIC routes IRQ1 → vector 33. Handler reads port 0x60, pushes to queue, sends EOI. | [ ] |
| 16.5 | **Implement blocking read** | `keyboard_read_char() -> char`. Block process if queue empty, wake on keypress. | [ ] |
| 16.6 | **Handle special keys** | Backspace (0x0E), Enter (0x1C), Escape (0x01), arrow keys (0xE0 prefix), F1-F12. | [ ] |
| 16.7 | **Implement line editing** | Backspace deletes last char, arrow keys move cursor (future), Ctrl+C sends interrupt. | [ ] |
| 16.8 | **Test: keyboard input echo** | Type characters → appear on serial/VGA output in real-time. | [ ] |
| 16.9 | **Test: special keys** | Enter creates newline, Backspace deletes, Ctrl+C prints "^C". | [ ] |
| 16.10 | **Test: shift/caps lock** | Shift+A = 'A', Caps Lock toggle working. | [ ] |

### Sprint 17: VGA Console & Framebuffer

| # | Task | Detail | Status |
|---|------|--------|--------|
| 17.1 | **Implement VGA text console** | 80×25 text mode, cursor tracking (row, col), auto-scroll when bottom reached. | [ ] |
| 17.2 | **Implement color support** | 16 FG + 16 BG colors. Default: light grey on black. Error: white on red. Header: white on blue. | [ ] |
| 17.3 | **Implement scrolling** | When row > 24: memmove all rows up by 1, clear last row. Smooth visual scrolling. | [ ] |
| 17.4 | **Implement cursor control** | Hardware cursor via VGA ports 0x3D4/0x3D5. Move cursor to (row, col). | [ ] |
| 17.5 | **Implement ANSI escape codes** | `\x1B[31m` (red), `\x1B[0m` (reset), `\x1B[2J` (clear), `\x1B[H` (home). Basic subset. | [ ] |
| 17.6 | **Implement Multiboot2 framebuffer** | If framebuffer tag present: linear framebuffer mode (32bpp). Pixel plotting, rect fill, font rendering. | [ ] |
| 17.7 | **Implement bitmap font (8×16)** | 256 ASCII glyphs, 16 bytes per glyph. Render to framebuffer for graphical mode. | [ ] |
| 17.8 | **Dual output** | All kernel output goes to both serial AND VGA/framebuffer simultaneously. | [ ] |
| 17.9 | **Test: VGA scrolling** | Print 30 lines → first 5 lines scroll off, last 25 visible. | [ ] |
| 17.10 | **Test: color output** | Print "ERROR" in red, "OK" in green, "INFO" in cyan on VGA. | [ ] |

### Sprint 18: PCI Bus & Device Discovery

| # | Task | Detail | Status |
|---|------|--------|--------|
| 18.1 | **Implement PCI config space access** | Read/write via I/O ports 0xCF8 (address) + 0xCFC (data). Config space: 256 bytes per device. | [ ] |
| 18.2 | **Implement PCI bus scan** | Brute-force: scan bus 0-255, device 0-31, function 0-7. Read vendor/device ID. | [ ] |
| 18.3 | **Implement PCI device struct** | `{ bus, device, function, vendor_id, device_id, class, subclass, bar[6], irq }` | [ ] |
| 18.4 | **Parse BAR (Base Address Registers)** | Detect MMIO vs I/O port, 32-bit vs 64-bit, size. Map MMIO BARs into kernel address space. | [ ] |
| 18.5 | **Print PCI device list** | On boot: list all detected PCI devices with vendor:device, class name. Like `lspci` output. | [ ] |
| 18.6 | **Detect NVMe controller** | Class 01h (storage), subclass 08h (NVMe). Read BARs for NVMe registers. | [ ] |
| 18.7 | **Detect network controller** | Class 02h (network). Detect Intel I219 or virtio-net. | [ ] |
| 18.8 | **Detect GPU** | Class 03h (display). Detect VGA controller or virtio-gpu. | [ ] |
| 18.9 | **Test: detect QEMU devices** | QEMU `-M q35` has: PIIX4/ICH9 chipset, virtio devices. Verify correct detection. | [ ] |
| 18.10 | **Test: BAR mapping** | Read NVMe BAR0 → map MMIO → read NVMe CAP register → verify valid capability. | [ ] |

**Phase 6 Gate:**
- [ ] Keyboard input working (interactive typing)
- [ ] VGA text console with colors and scrolling
- [ ] PCI bus enumeration detects all QEMU devices
- [ ] NVMe controller detected and BAR mapped
- [ ] All 30 tasks pass

---

## Phase 7: Filesystem & Shell (Sprints 19-21)

> **Goal:** Interactive shell with 50+ commands, RAM filesystem, basic file I/O.
> **Gate:** `fjsh` shell boots, runs commands, manages files in ramfs.
> **Hardware needed:** None (QEMU only)

### Sprint 19: VFS & RAM Filesystem

| # | Task | Detail | Status |
|---|------|--------|--------|
| 19.1 | **Implement VFS (Virtual File System)** | `vfs_open(path, flags) -> fd`, `vfs_read(fd, buf, len) -> count`, `vfs_write(fd, buf, len) -> count`, `vfs_close(fd)`. | [ ] |
| 19.2 | **Implement file descriptor table** | Per-process: 16 FDs. FD 0=stdin, 1=stdout, 2=stderr. `fd_table[fd] -> { inode, offset, flags }`. | [ ] |
| 19.3 | **Implement ramfs inode** | `Inode { name, type (file/dir), size, data_ptr, children[], parent }`. Max 256 inodes. | [ ] |
| 19.4 | **Implement ramfs directory ops** | `mkdir(path)`, `rmdir(path)`, `readdir(path) -> entries[]`. Path resolution: split by '/'. | [ ] |
| 19.5 | **Implement ramfs file ops** | `create(path)`, `read(inode, offset, buf, len)`, `write(inode, offset, buf, len)`, `truncate(inode, len)`. | [ ] |
| 19.6 | **Implement path resolution** | `/home/user/file.txt` → walk inode tree: root → home → user → file.txt. Handle `.` and `..`. | [ ] |
| 19.7 | **Implement stat()** | `stat(path) -> { size, type, created, modified }`. For `ls -l` style output. | [ ] |
| 19.8 | **Pre-populate /etc and /tmp** | On boot: create `/etc/hostname` ("fajaros-nova"), `/etc/motd`, `/tmp/`. | [ ] |
| 19.9 | **Test: create/read/write file** | Create `/tmp/test.txt`, write "hello", read back → "hello". | [ ] |
| 19.10 | **Test: directory operations** | mkdir → create files → readdir → ls output matches. | [ ] |

### Sprint 20: Shell (fjsh) — Core

| # | Task | Detail | Status |
|---|------|--------|--------|
| 20.1 | **Implement shell main loop** | Print prompt `nova> `, read line from keyboard, parse command + args, dispatch. | [ ] |
| 20.2 | **Implement line editor** | Character-by-character input. Backspace, Enter, Ctrl+C (cancel line), Ctrl+D (EOF). | [ ] |
| 20.3 | **Implement command parser** | Split by whitespace: `cmd arg1 arg2 "quoted arg"`. Handle quotes and escapes. | [ ] |
| 20.4 | **Implement built-in: echo** | `echo Hello World` → prints "Hello World". | [ ] |
| 20.5 | **Implement built-in: help** | `help` → list all available commands with one-line descriptions. | [ ] |
| 20.6 | **Implement built-in: clear** | `clear` → clear VGA screen, reset cursor to top-left. | [ ] |
| 20.7 | **Implement built-in: uname** | `uname -a` → "FajarOS Nova 0.1.0 x86_64 i9-14900HX". | [ ] |
| 20.8 | **Implement built-in: uptime** | `uptime` → "up 0 days, 0:05:23, 4 processes". | [ ] |
| 20.9 | **Test: shell boot and prompt** | Boot → see "nova> " prompt → type "echo test" → see "test". | [ ] |
| 20.10 | **Test: unknown command** | Type "foobar" → "foobar: command not found". | [ ] |

### Sprint 21: Shell Commands (50+ commands)

| # | Task | Detail | Status |
|---|------|--------|--------|
| 21.1 | **File commands** | `ls`, `cat`, `touch`, `rm`, `cp`, `mv`, `mkdir`, `rmdir`, `pwd`, `cd`, `wc`, `head`, `tail` (13 commands) | [ ] |
| 21.2 | **Process commands** | `ps`, `kill`, `spawn`, `wait`, `top`, `nice` (6 commands) | [ ] |
| 21.3 | **System commands** | `sysinfo`, `cpuinfo`, `meminfo`, `lspci`, `dmesg`, `shutdown`, `reboot` (7 commands) | [ ] |
| 21.4 | **Utility commands** | `date`, `cal`, `sleep`, `seq`, `true`, `false`, `yes`, `expr`, `base64` (9 commands) | [ ] |
| 21.5 | **Text commands** | `grep`, `sort`, `uniq`, `tr`, `rev`, `tac`, `cut`, `paste` (8 commands) | [ ] |
| 21.6 | **I/O commands** | `write` (to file), `append`, `hexdump`, `xxd` (4 commands) | [ ] |
| 21.7 | **Fun commands** | `cowsay`, `fortune`, `matrix`, `color` (4 commands) | [ ] |
| 21.8 | **Command history** | Up/Down arrows navigate history. Store last 32 commands. | [ ] |
| 21.9 | **Test: file operations** | `touch a.txt` → `echo hello > a.txt` → `cat a.txt` → "hello" → `rm a.txt` | [ ] |
| 21.10 | **Test: pipe simulation** | `ps` output shows all processes with correct PIDs and states. | [ ] |

**Phase 7 Gate:**
- [ ] RAM filesystem with directories and files
- [ ] 50+ shell commands working
- [ ] Interactive line editing (backspace, history)
- [ ] File I/O (create, read, write, delete)
- [ ] All 30 tasks pass

---

## Phase 8: SMP & Advanced (Sprints 22-24)

> **Goal:** Multi-core operation (8P + 16E cores), ACPI support, security hardening.
> **Gate:** 4 cores running processes, ACPI shutdown working.
> **Hardware needed:** None (QEMU with `-smp 4`)

### Sprint 22: ACPI & Power Management

| # | Task | Detail | Status |
|---|------|--------|--------|
| 22.1 | **Find ACPI RSDP** | Search EBDA (0x9FC00) and BIOS area (0xE0000-0xFFFFF) for "RSD PTR " signature. | [ ] |
| 22.2 | **Parse RSDT/XSDT** | Follow RSDP → XSDT (64-bit) or RSDT (32-bit). Enumerate table entries. | [ ] |
| 22.3 | **Parse MADT (APIC info)** | Find MADT table → list all LAPIC entries (one per CPU core), IOAPIC entries. | [ ] |
| 22.4 | **Parse FADT (power management)** | Find FADT → ACPI PM registers. SCI_INT, PM1a_EVT, PM1a_CNT. | [ ] |
| 22.5 | **Implement ACPI shutdown** | Write SLP_TYP|SLP_EN to PM1a_CNT. For QEMU: outw(0x604, 0x2000). | [ ] |
| 22.6 | **Implement ACPI reboot** | Use FADT RESET_REG: write RESET_VALUE to register. For QEMU: outb(0xCF9, 0x06). | [ ] |
| 22.7 | **Implement shutdown command** | `shutdown` → sync filesystems → ACPI poweroff. | [ ] |
| 22.8 | **Implement reboot command** | `reboot` → sync → ACPI reboot → fallback: keyboard controller reset (0xFE to 0x64). | [ ] |
| 22.9 | **Test: ACPI table parsing** | Detect all CPU cores from MADT → print "Found 4 CPUs". | [ ] |
| 22.10 | **Test: ACPI shutdown** | `shutdown` command → QEMU exits cleanly. | [ ] |

### Sprint 23: SMP (Symmetric Multi-Processing)

| # | Task | Detail | Status |
|---|------|--------|--------|
| 23.1 | **Parse MADT for AP (Application Processor) IDs** | BSP (bootstrap processor) is first LAPIC. APs are additional entries. | [ ] |
| 23.2 | **Write AP trampoline code** | 16-bit real mode code at 0x8000. AP starts in real mode → protected → long mode. | [ ] |
| 23.3 | **Send INIT-SIPI-SIPI to APs** | Via LAPIC ICR: INIT IPI, wait 10ms, SIPI (startup IPI) with vector to trampoline. | [ ] |
| 23.4 | **Per-CPU data structures** | Each CPU has: LAPIC ID, current process, kernel stack, GDT, TSS. Per-CPU variable access via GS segment. | [ ] |
| 23.5 | **Per-CPU IDT/GDT** | Each CPU loads own GDT (with per-CPU TSS) and shared IDT. | [ ] |
| 23.6 | **Spinlock implementation** | `spinlock_acquire()` / `spinlock_release()` via `lock cmpxchg`. Used for scheduler, allocator. | [ ] |
| 23.7 | **SMP-safe scheduler** | Per-CPU run queue. Work stealing: idle CPU pulls process from busy CPU's queue. | [ ] |
| 23.8 | **SMP-safe allocator** | Lock-free or per-CPU slab caches to reduce contention. | [ ] |
| 23.9 | **Test: boot 4 CPUs** | QEMU `-smp 4` → "CPU 0 online", "CPU 1 online", "CPU 2 online", "CPU 3 online". | [ ] |
| 23.10 | **Test: processes on different CPUs** | 4 processes → 4 CPUs → all running simultaneously (verified by tick counts). | [ ] |

### Sprint 24: Security Hardening

| # | Task | Detail | Status |
|---|------|--------|--------|
| 24.1 | **Implement KASLR (Kernel Address Space Layout Randomization)** | Randomize kernel base address using RDRAND instruction. | [ ] |
| 24.2 | **Implement stack canaries** | Place random value before return address. Check on function return → panic if corrupted. | [ ] |
| 24.3 | **Implement W^X enforcement** | No page is both Writable AND Executable. Enforce via page table flags. | [ ] |
| 24.4 | **Implement kernel stack guard pages** | Unmap page at bottom of each kernel stack. Stack overflow → #PF (not silent corruption). | [ ] |
| 24.5 | **Enable KPTI (Kernel Page Table Isolation)** | Separate kernel/user page tables. On syscall entry: switch to kernel tables. On sysret: switch to user tables. | [ ] |
| 24.6 | **Implement syscall argument validation** | All user pointers checked: in user VA range, mapped, correct permissions. | [ ] |
| 24.7 | **Implement resource limits** | Max open files, max memory, max processes per user. Prevent fork bomb. | [ ] |
| 24.8 | **Test: stack overflow detection** | Recurse until stack overflow → clean #PF → process killed (not kernel crash). | [ ] |
| 24.9 | **Test: W^X enforcement** | Attempt to write to code page → #PF. Attempt to execute data page → #PF. | [ ] |
| 24.10 | **Test: KPTI isolation** | User process reads kernel address → #PF (page not present in user tables). | [ ] |

**Phase 8 Gate:**
- [ ] ACPI shutdown/reboot working
- [ ] SMP: 4 cores booted and running processes
- [ ] Spinlocks for SMP safety
- [ ] Security: SMEP, SMAP, KPTI, W^X, stack canaries
- [ ] All 30 tasks pass

---

## Phase 9: AI & GPU (Sprints 25-27)

> **Goal:** ML inference on FajarOS using RTX 4090 (future) and CPU-based tensor ops.
> **Gate:** MNIST inference running as userspace process on FajarOS.
> **Hardware needed:** QEMU for CPU inference. Real hardware for GPU (future).

### Sprint 25: CPU-Based Tensor Operations

| # | Task | Detail | Status |
|---|------|--------|--------|
| 25.1 | **Implement tensor struct in kernel** | `Tensor { data: *mut f64, rows: i64, cols: i64 }`. Heap-allocated via kmalloc. | [ ] |
| 25.2 | **Implement tensor creation** | `tensor_zeros(rows, cols)`, `tensor_ones(rows, cols)`, `tensor_from_data(data, rows, cols)`. | [ ] |
| 25.3 | **Implement matrix multiply** | `tensor_matmul(a, b) -> c`. Naive O(n³) first. Use AVX2 intrinsics later. | [ ] |
| 25.4 | **Implement element-wise ops** | `tensor_add`, `tensor_sub`, `tensor_mul`, `tensor_relu`, `tensor_sigmoid`. | [ ] |
| 25.5 | **Implement softmax** | `tensor_softmax(t) -> t`. For classification output. Numerically stable (subtract max). | [ ] |
| 25.6 | **Implement model loading** | Load FJML model file from ramfs. Parse weights into tensors. | [ ] |
| 25.7 | **Implement forward pass** | `model_forward(input) -> output`. Sequential: Dense → ReLU → Dense → Softmax. | [ ] |
| 25.8 | **AVX2 matrix multiply** | Use AVX2 `_mm256_fmadd_pd` for 4× throughput. Detect via CPUID, fallback to scalar. | [ ] |
| 25.9 | **Test: matmul correctness** | 4×4 × 4×4 → verify against known result. | [ ] |
| 25.10 | **Test: MNIST forward pass** | Load pretrained weights → classify digit image → correct prediction. | [ ] |

### Sprint 26: MNIST Demo Application

| # | Task | Detail | Status |
|---|------|--------|--------|
| 26.1 | **Create MNIST weight file** | Export pretrained MLP weights (784→128→10) as FJML binary format. | [ ] |
| 26.2 | **Create test digit images** | 10 raw images (28×28 = 784 bytes each), digits 0-9. Store in ramfs /data/. | [ ] |
| 26.3 | **Implement digit classifier app** | `apps/mnist.fj`: load model, load image, forward pass, print predicted digit. | [ ] |
| 26.4 | **Implement batch inference** | Classify all 10 test images, print accuracy (expect 8/10+). | [ ] |
| 26.5 | **Benchmark inference time** | Time per inference using TSC. Print "Inference: 0.5ms per digit". | [ ] |
| 26.6 | **Display digit on VGA** | Render 28×28 digit image using ASCII art on VGA console. '#' for dark, '.' for light. | [ ] |
| 26.7 | **Interactive demo** | Shell command `mnist [0-9]` → load digit image → classify → display result. | [ ] |
| 26.8 | **Test: classification accuracy** | At least 8/10 test digits classified correctly. | [ ] |
| 26.9 | **Test: inference performance** | Single inference < 5ms on QEMU (no KVM). | [ ] |
| 26.10 | **Test: batch mode** | `mnist all` → classify 10 digits → print results table. | [ ] |

### Sprint 27: GPU Compute Foundation (Future — Real Hardware)

| # | Task | Detail | Status |
|---|------|--------|--------|
| 27.1 | **Detect NVIDIA GPU via PCI** | Class 03h, vendor 10DEh. Read BAR0 (MMIO), BAR1 (framebuffer). | [ ] |
| 27.2 | **Map GPU MMIO registers** | Map BAR0 into kernel VA. Read GPU identification register (PMC). | [ ] |
| 27.3 | **Initialize GPU (minimal)** | Enable PRAMIN (GPU memory access), read VBIOS, detect VRAM size. | [ ] |
| 27.4 | **Implement GPU memory allocation** | Allocate VRAM regions for compute buffers. Map into CPU address space for data transfer. | [ ] |
| 27.5 | **Design GPU compute dispatch** | Submit compute commands via GPU FIFO (pushbuffer). Wait for completion via interrupt or polling. | [ ] |
| 27.6 | **Port matrix multiply to GPU** | Upload tensors to VRAM → dispatch compute kernel → download result. | [ ] |
| 27.7 | **Benchmark GPU vs CPU inference** | Compare RTX 4090 vs i9-14900HX for MNIST inference. Expect 10-100× speedup. | [ ] |
| 27.8 | **Test: GPU detection on real hardware** | Boot on Legion Pro → detect "NVIDIA RTX 4090" via PCI. | [ ] |
| 27.9 | **Test: GPU memory allocation** | Allocate 16MB VRAM → write pattern → read back → verify. | [ ] |
| 27.10 | **Test: GPU compute** | Matrix multiply on GPU → correct result. | [ ] |

**Phase 9 Gate:**
- [ ] CPU tensor ops with AVX2 acceleration
- [ ] MNIST inference in FajarOS userspace
- [ ] GPU detected via PCI (on real hardware)
- [ ] All 30 tasks pass

---

## Phase 10: Production & Polish (Sprints 28-30)

> **Goal:** Release-quality OS with documentation, benchmarks, and demo showcase.
> **Gate:** FajarOS Nova boots on real Intel hardware, runs MNIST demo, 50+ shell commands.
> **Hardware needed:** Lenovo Legion Pro (real hardware boot)

### Sprint 28: NVMe Block Device Driver

| # | Task | Detail | Status |
|---|------|--------|--------|
| 28.1 | **Initialize NVMe controller** | Map BAR0, read capabilities (CAP), configure admin queue (ASQ/ACQ). | [ ] |
| 28.2 | **Implement admin queue** | Create admin submission + completion queues. Send Identify Controller command. | [ ] |
| 28.3 | **Identify namespace** | Send Identify Namespace → get LBA count, block size (512 or 4096). | [ ] |
| 28.4 | **Create I/O queues** | Create I/O submission + completion queue pair. Configure IRQ or polling. | [ ] |
| 28.5 | **Implement block read** | `nvme_read(lba, count, buffer)`: submit read command, wait completion, return data. | [ ] |
| 28.6 | **Implement block write** | `nvme_write(lba, count, buffer)`: submit write command, wait completion. | [ ] |
| 28.7 | **Implement FAT32 filesystem** | Read FAT32 boot sector, parse FAT, read directory entries, read file clusters. | [ ] |
| 28.8 | **Mount NVMe FAT32 at /mnt** | Auto-detect FAT32 on NVMe → mount at `/mnt` in VFS. | [ ] |
| 28.9 | **Test: read NVMe sector** | Read LBA 0 → verify MBR signature (0x55AA) or GPT header. | [ ] |
| 28.10 | **Test: ls /mnt** | List files on FAT32 formatted NVMe partition. | [ ] |

### Sprint 29: Real Hardware Boot

| # | Task | Detail | Status |
|---|------|--------|--------|
| 29.1 | **Create bootable USB** | Write fajaros.iso to USB flash drive. UEFI + legacy BIOS boot support. | [ ] |
| 29.2 | **Boot on Lenovo Legion Pro** | Enter BIOS → disable Secure Boot → boot from USB → FajarOS kernel loads. | [ ] |
| 29.3 | **Fix hardware-specific issues** | Serial may not work on real HW → use VGA/framebuffer only. Fix any real HW differences. | [ ] |
| 29.4 | **Detect real CPU** | CPUID → "Intel Core i9-14900HX", 24 cores (MADT), 5.8 GHz. | [ ] |
| 29.5 | **Detect real RAM** | Multiboot2/EFI memory map → 32 GB DDR5. | [ ] |
| 29.6 | **Detect NVMe SSD** | PCI scan → Samsung/SK Hynix NVMe (Gen4 x4). | [ ] |
| 29.7 | **Detect RTX 4090** | PCI scan → NVIDIA GN21-X11 (vendor 10DE, device 27A0). | [ ] |
| 29.8 | **Run MNIST demo on real HW** | CPU inference with AVX2 → measure real performance. | [ ] |
| 29.9 | **Performance benchmark** | Fibonacci, matrix multiply, syscall latency — compare QEMU vs real HW. | [ ] |
| 29.10 | **Boot photo/video** | Capture FajarOS running on Legion Pro for documentation. | [ ] |

### Sprint 30: Documentation & Release

| # | Task | Detail | Status |
|---|------|--------|--------|
| 30.1 | **Write comprehensive README** | Features, build instructions, screenshots, architecture diagram. | [ ] |
| 30.2 | **Write ARCHITECTURE.md** | Detailed system design, memory layout, component contracts. | [ ] |
| 30.3 | **Write BOOT_SEQUENCE.md** | Step-by-step boot documentation with register values at each stage. | [ ] |
| 30.4 | **Write SYSCALLS.md** | Complete syscall reference with examples. | [ ] |
| 30.5 | **Write PORTING_FROM_ARM64.md** | Differences between FajarOS Surya (ARM64) and Nova (x86_64). | [ ] |
| 30.6 | **Create demo video** | Screen recording: boot → shell → commands → MNIST demo. | [ ] |
| 30.7 | **Benchmarks report** | CPU inference speed, syscall latency, context switch time, boot time. | [ ] |
| 30.8 | **GitHub release: v0.1.0** | Tag, release notes, binary ISO download. | [ ] |
| 30.9 | **Blog post** | "FajarOS Nova: An OS written in Fajar Lang, running on Intel i9-14900HX". | [ ] |
| 30.10 | **CI/CD setup** | GitHub Actions: build + test in QEMU on every push. | [ ] |

**Phase 10 Gate:**
- [ ] FajarOS boots on real Lenovo Legion Pro hardware
- [ ] 50+ shell commands, filesystem, MNIST demo
- [ ] Documentation complete
- [ ] GitHub release published
- [ ] CI/CD green
- [ ] All 30 tasks pass

---

## Quality Gates (Per Sprint)

- [ ] All sprint tests pass in QEMU
- [ ] No kernel panics during normal operation
- [ ] Serial output shows correct debug messages
- [ ] Memory usage stable (no leaks over 1 minute uptime)
- [ ] Code compiles cleanly (`fj build` + `cargo clippy`)

## Quality Gates (Per Phase)

- [ ] Phase gate criteria met
- [ ] No regressions from previous phase
- [ ] All accumulated tasks marked [x]
- [ ] Documentation updated

---

## QEMU Test Commands

```bash
# Basic boot (serial only)
qemu-system-x86_64 -kernel fajaros.elf -nographic -serial stdio

# Boot from ISO (GRUB + VGA)
qemu-system-x86_64 -cdrom fajaros.iso -serial stdio

# With KVM acceleration (near-native speed)
qemu-system-x86_64 -enable-kvm -cpu host -kernel fajaros.elf -serial stdio

# SMP (4 cores)
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 512M -kernel fajaros.elf -serial stdio

# With NVMe storage
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 512M \
  -drive file=disk.img,if=none,id=nvme0 \
  -device nvme,serial=fajaros,drive=nvme0 \
  -kernel fajaros.elf -serial stdio

# Debug with GDB
qemu-system-x86_64 -s -S -kernel fajaros.elf -serial stdio
# In another terminal: gdb -ex "target remote :1234" -ex "symbol-file fajaros.elf"

# Full setup (KVM + 4 cores + 1GB + NVMe + network)
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 1G \
  -drive file=disk.img,if=none,id=nvme0 \
  -device nvme,serial=fajaros,drive=nvme0 \
  -netdev user,id=net0 -device virtio-net,netdev=net0 \
  -kernel fajaros.elf -serial stdio
```

---

## Compiler Changes Needed (in fajar-lang repo)

| # | Change | File(s) | Priority |
|---|--------|---------|----------|
| 1 | Port I/O intrinsics (`port_inb`/`port_outb`) | `runtime_bare.rs`, `mod.rs` | HIGH — Sprint 1 |
| 2 | x86_64 bare-metal linker script update | `linker.rs` | HIGH — Sprint 1 |
| 3 | x86_64 UART (0x3F8 port I/O) in runtime | `runtime_bare.rs` | HIGH — Sprint 1 |
| 4 | x86_64 _start wrapper (cli + stack + bss + call main) | `cranelift/mod.rs` | HIGH — Sprint 1 |
| 5 | Multiboot2 header generation | `linker.rs` or new file | HIGH — Sprint 2 |
| 6 | x86_64 context frame builtins | `runtime_bare.rs` | MEDIUM — Sprint 11 |
| 7 | SYSCALL/SYSRET MSR setup builtins | `runtime_bare.rs` | MEDIUM — Sprint 13 |
| 8 | AVX2 matrix multiply intrinsics | `runtime_bare.rs` | LOW — Sprint 25 |

---

## Timeline Estimate

```
Phase 1:  Foundation         [S1-S3]    Weeks 1-2     Boot + serial + VGA + GDT
Phase 2:  Memory             [S4-S6]    Weeks 3-4     Paging + heap + allocator
Phase 3:  Interrupts         [S7-S9]    Weeks 5-6     IDT + LAPIC + timer
Phase 4:  Scheduler          [S10-S12]  Weeks 7-8     Processes + context switch
Phase 5:  User Space         [S13-S15]  Weeks 9-10    Ring 3 + syscalls + IPC
Phase 6:  Drivers            [S16-S18]  Weeks 11-12   Keyboard + VGA + PCI
Phase 7:  Filesystem & Shell [S19-S21]  Weeks 13-14   VFS + ramfs + fjsh (50+ cmd)
Phase 8:  SMP & Security     [S22-S24]  Weeks 15-16   Multi-core + ACPI + hardening
Phase 9:  AI & GPU           [S25-S27]  Weeks 17-18   Tensor + MNIST + GPU detect
Phase 10: Production         [S28-S30]  Weeks 19-20   NVMe + real HW + release

Total: 30 sprints, 300 tasks, ~20 weeks
```

---

## Success Criteria

### MVP (Phase 1-5 complete)
- [ ] Boots on QEMU x86_64 with KVM
- [ ] Serial + VGA output
- [ ] 4-level paging with kernel heap
- [ ] Preemptive scheduler (4 processes)
- [ ] Ring 3 user space with SYSCALL/SYSRET
- [ ] IPC between processes

### Feature Complete (Phase 1-7)
- [ ] Interactive shell (fjsh) with 50+ commands
- [ ] RAM filesystem with file I/O
- [ ] Keyboard input
- [ ] VGA text console with colors

### Production (Phase 1-10)
- [ ] Boots on real Lenovo Legion Pro (i9-14900HX)
- [ ] SMP (multi-core operation)
- [ ] NVMe SSD access
- [ ] MNIST ML inference demo
- [ ] ACPI shutdown/reboot
- [ ] Security hardened (SMEP, SMAP, KPTI, W^X)
- [ ] GitHub release with CI/CD

---

## Key Innovation: @kernel/@device/@safe on x86_64

```
FajarOS Nova carries forward the unique Fajar Lang safety model:

@kernel context (Ring 0)
  ├── Allowed: asm!(), port I/O, MMIO, page tables, IRQ
  ├── Blocked: heap strings, tensor ops, network I/O
  ├── Enforced by: Fajar Lang compiler (not convention)
  └── Used by: kernel, drivers, interrupt handlers

@device context (Compute)
  ├── Allowed: tensor ops, GPU dispatch, AVX2 intrinsics
  ├── Blocked: raw pointers, IRQ, volatile I/O
  ├── Enforced by: Fajar Lang compiler
  └── Used by: ML inference, GPU compute

@safe context (Ring 3)
  ├── Allowed: standard operations, syscalls, strings, collections
  ├── Blocked: raw pointers, IRQ, volatile I/O, direct hardware
  ├── Enforced by: Fajar Lang compiler + hardware (Ring 3)
  └── Used by: shell, applications, services

The compiler prevents bugs BEFORE they reach the hardware.
"If it compiles in Fajar Lang, it's safe to deploy."
```

---

*FajarOS "Nova" — Implementation Plan v1.0*
*Created 2026-03-19 by Claude Opus 4.6*
*Target: 30 sprints, 300 tasks, ~20 weeks*
*Hardware: Intel Core i9-14900HX (Lenovo Legion Pro)*
