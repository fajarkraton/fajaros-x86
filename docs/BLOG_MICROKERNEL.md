# Building a Microkernel OS in Fajar Lang

*By Fajar (PrimeCore.id) -- 2026-03-22*

---

## Why a New OS Language?

Every operating system has the same fundamental problem: **the kernel trusts itself too much**.

Linux, written in C, lets any kernel module call any function. A buggy NVMe driver can corrupt the scheduler. A network driver can overwrite page tables. The compiler does not care -- it will happily compile `memset(page_table, 0, 4096)` inside a USB driver.

I wanted to fix this at the compiler level. Not with runtime checks that slow things down, not with formal proofs that nobody writes in practice, but with a simple rule: **annotate every function with its privilege level, and the compiler enforces the boundary**.

In Fajar Lang, you write:

```fajar
@kernel fn handle_timer_irq() { ... }  // Can access hardware
@safe fn shell_prompt() { ... }         // Cannot. Period.
```

If `shell_prompt()` tries to call `port_outb(0x3F8, 65)`, the compiler refuses with error SE020: "hardware access not allowed in @safe context -- use syscall." This is not a warning. The binary is never produced.

Three annotations. Three worlds. Compiler-enforced at build time, capability-checked at runtime:
- **@kernel** -- Ring 0. Hardware, IRQ, DMA, page tables. No heap strings, no tensors.
- **@device** -- Drivers. Restricted hardware via capabilities. No raw pointers, no inline asm.
- **@safe** -- User processes. Syscalls only. No hardware access whatsoever.

No other OS has this.

---

## The 3-Phase Journey

What started as a 10,291-line monolithic kernel became a 20,416-line microkernel OS across 21 sprints and three phases.

**Phase 1 (8 sprints): Microkernel extraction.** I split the monolithic kernel into a 2,480-line Ring 0 core and five user-space services (VFS, BLK, NET, Shell, Init). The kernel shrank by 76%. Everything that does not absolutely require Ring 0 privilege -- filesystem parsing, network protocols, the shell -- moved to user space and communicates through IPC.

**Phase 2 (6 sprints): Production hardening.** SMP scheduling with per-CPU run queues, demand paging with copy-on-write, SMEP/SMAP/NX security, a write-ahead journal for crash recovery, fast-path IPC that transfers 16 bytes via registers without touching memory, and a 20-test verification suite.

**Phase 3 (7 sprints): Self-hosting and GUI.** A framebuffer display with an 8x16 bitmap font. PS/2 mouse with cursor rendering. A widget-based GUI toolkit. A text editor with gap buffer and syntax highlighting for `.fj` files. A Fajar Lang compiler that runs ON FajarOS (lexer, parser, interpreter -- 30 token types, 15 AST nodes). A package manager with dependency resolution. And hardware detection for real deployment.

---

## Key Design Decisions

**IPC-first architecture.** The kernel does exactly six things: schedule processes, manage memory, pass messages, dispatch syscalls, handle interrupts, and check capabilities. Everything else is a service. `cat /proc/version` triggers Shell->VFS->procfs->reply -- four IPC transitions in under 10 microseconds.

**Synchronous rendezvous IPC (L4/seL4 inspired).** Sender blocks until receiver is ready. No kernel-side message queues for the fast path. For large data, processes share pages via `SYS_SHARE` for zero-copy transfer. For small payloads under 16 bytes, the fast path transfers data entirely through register slots.

**12-bit capability model.** Each process has a bitmap: IPC_SEND, IPC_RECV, SPAWN, KILL, PORT_IO, IRQ, DMA, MAP_PHYS, NET, FS, DEVICE, ADMIN. The kernel checks the bitmap on every syscall. @kernel gets all bits. @device gets hardware bits. @safe gets IPC + FS + NET only.

**Monolithic-to-micro extraction, not rewrite.** I did not start from scratch. I extracted the working monolithic kernel piece by piece, converting functions from @kernel to @safe as they moved to user space. At every step, the OS kept booting and running.

---

## 19 Critical Bugs Found During Review

The code review across Sprint 3.8 (real hardware testing on Radxa Dragon Q6A) and earlier sprints uncovered 19 bugs. Here are the most interesting:

1. **IPC endpoint overflow.** With 16 endpoints at 512 bytes each, the message queue (4 entries x 72 bytes = 288 bytes starting at offset +256) overflowed past 512 into the next endpoint. Fixed by expanding EP_SIZE to 576 bytes.

2. **NX bit not set.** Data pages (heap, stack) were executable. An attacker could inject shellcode into a buffer and jump to it. Fixed: EFER.NXE enabled, PTE bit 63 set on all non-code pages.

3. **Ramdisk address overlap.** The ramdisk at 0x8C0000 (256KB) extended to 0x900000, overlapping the NET service region at 0x8E0000. Fixed by adjusting the NET service base address and validating all region boundaries.

4. **CAP_DEVICE_DEFAULT was wrong.** The @device default capability was 1143 (binary: had CAP_SPAWN but missed CAP_MAP_PHYS). A device driver could spawn processes but could not map DMA buffers. Fixed to 1267.

5. **Fast IPC recv scratch overlap.** The fast-path receive scratch area at 0x8FA1F0 overlapped with slot 15 of the 16-entry transfer table. Moved to 0x8FA200.

Other finds included missing PIT EOI acknowledgment, keyboard IRQ race conditions, incorrect VFS path resolution for nested mounts, and a scheduler priority inversion where IDLE processes could starve NORMAL ones.

---

## Real Hardware Deployment

Sprint 3.8 ran 10 tests on the Radxa Dragon Q6A (Qualcomm QCS6490, Kryo 670, 7.4GB RAM):

- IPC message format: 64-byte layout verified
- Capability bitmap: all 12 bits correct (after the fix above)
- Gap buffer: editor insert/delete across 32KB
- Package dependency resolution: 7 standard packages
- Lexer: tokenizes `let x: i32 = 42` into 6 tokens
- VFS path resolution: `/proc/version` -> procfs mount
- BLK cache: LRU eviction after 16 entries
- Scheduler: 4 priority levels in correct order
- NX bit: data pages non-executable
- Syscall numbering: all 18 calls at correct offsets

All 10 passed. The JIT compiler benchmark showed fib(30) = 9ms (JIT) versus 5.9 seconds (interpreter) -- a 656x speedup on ARM64.

The compiler itself (4,903 tests on x86_64) stays green across all changes.

---

## What's Next

Phase 3 sprints 3.9 and 3.10 remain: documentation (architecture guide, API reference, mdBook manual) and community setup (GitHub organization, contributing guide, release ISO).

Beyond v3.0, the roadmap includes:
- **GPU compute service** -- RTX 4090 tensor acceleration via @device
- **Networking stack hardening** -- real TCP, TLS, HTTP client
- **Multi-user support** -- per-user capability sets, login service
- **Native hardware boot** -- bare-metal on the Legion Pro i9-14900HX

The long-term vision: an OS where kernel safety, driver isolation, and AI inference share the same compiler, the same type system, and the same safety guarantees.

---

## By the Numbers

```
Total LOC:         20,416 (Fajar Lang, 65+ .fj files)
Binary size:       ~405KB ELF (microkernel + all services)
Sprints:           21 complete (8 + 6 + 7)
Services:          9 (kernel, init, BLK, VFS, NET, shell, display, input, GUI)
Syscalls:          18 implemented
IPC message types: 17 (VFS, BLK, NET, DEV, IRQ)
Capabilities:      12 bits per process
Shell commands:    160+
Compiler tests:    4,903 passing
Hardware verified: QEMU x86_64 + Radxa Dragon Q6A (ARM64)
Kernel Ring 0:     2,480 LOC (down from 10,291 -- 76% reduction)
```

---

*FajarOS: where the compiler IS the security model.*

*Built with Fajar Lang v4.1.0 + Claude Opus 4.6*
