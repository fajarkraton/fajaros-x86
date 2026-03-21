# FajarOS Nova v0.6 "Ascension" — Implementation Plan

> **Date:** 2026-03-21
> **Author:** Fajar (PrimeCore.id) + Claude Opus 4.6
> **Context:** Nova v0.5.0 shipped (9,637 LOC, 148 commands, Ring 3, SYSCALL/SYSRET, NVMe+FAT32, VFS, SMP, virtio-net virtqueues, XHCI init, const fn). All 6 fixes from NEXT_SESSION_PLAN complete.
> **Codename:** "Ascension" — the OS that ascends from prototype to production
> **Goal:** Test everything, release v3.5.0, complete USB, improve language, plan v0.6

---

## Current State

```
Fajar Lang:  v3.4.0 — const fn, 6,051 tests, ~152K LOC Rust
Nova:        v0.5.0 "Transcendence" — 9,637 LOC, 365 @kernel fns, 148 commands
Repos:       fajar-lang (monolithic kernel) + fajaros-x86 (35 modular .fj files)
Ring 3:      SYSCALL/SYSRET with "Hello Ring 3!" working
Storage:     NVMe + FAT32 + VFS + RamFS
Network:     Virtio-net virtqueues (TX/RX implemented, needs QEMU testing)
USB:         XHCI init + slot enable + address device (needs testing)
Compiler:    const fn with compile-time evaluation (fib(10)=55)
```

---

## Phase A: Test & Verify in QEMU (3 sprints, 30 tasks)

**Goal:** Verify all Nova features work in QEMU. Fix bugs found during testing.
**Effort:** ~6 hours
**Priority:** HIGHEST — untested code is broken code

### Sprint A1: Boot & Core Verification (10 tasks)

| # | Task | QEMU Command | Expected Result | Status |
|---|------|-------------|-----------------|--------|
| A1.1 | Basic boot (serial) | `make run` | Boot banner + "nova>" prompt | [ ] |
| A1.2 | Boot with KVM | `make run-kvm` | Same, faster boot | [ ] |
| A1.3 | Boot with VGA | `make run-vga` | VGA text mode, colored banner | [ ] |
| A1.4 | Shell commands: help | Type `help` | List 148 commands | [ ] |
| A1.5 | Shell commands: uname, uptime, cpuinfo | Type each | Correct output | [ ] |
| A1.6 | Shell commands: meminfo, frames, heap | Type each | Memory stats shown | [ ] |
| A1.7 | Shell commands: clear, echo hello | Type each | Screen clears, echo works | [ ] |
| A1.8 | Shell commands: ps, lspci | Type each | Process list, PCI devices | [ ] |
| A1.9 | Keyboard: shift, caps lock, arrows | Press keys | Uppercase, history navigation | [ ] |
| A1.10 | Verify serial output matches VGA | Compare serial + VGA | Consistent output | [ ] |

### Sprint A2: Storage & Filesystem Verification (10 tasks)

| # | Task | QEMU Command | Expected Result | Status |
|---|------|-------------|-----------------|--------|
| A2.1 | NVMe detection | `make run-nvme` + `nvme` | NVMe controller found | [ ] |
| A2.2 | NVMe read/write | `disk_read 0` / `disk_write 0` | Sector R/W works | [ ] |
| A2.3 | FAT32 mount | `fat32mount` | FAT32 filesystem mounted | [ ] |
| A2.4 | FAT32 list | `fat32ls` | Root directory listing | [ ] |
| A2.5 | FAT32 cat | `fat32cat <file>` | File contents shown | [ ] |
| A2.6 | FAT32 write | `fatwrite test.txt hello` | File created | [ ] |
| A2.7 | FAT32 delete | `fatrm test.txt` | File removed | [ ] |
| A2.8 | VFS mounts | `mounts` | /, /dev, /proc, /mnt listed | [ ] |
| A2.9 | /dev/random | `devread random` | Random bytes shown | [ ] |
| A2.10 | /proc/version | `procversion` | Kernel version string | [ ] |

### Sprint A3: Network & USB & Ring 3 Verification (10 tasks)

| # | Task | QEMU Command | Expected Result | Status |
|---|------|-------------|-----------------|--------|
| A3.1 | Virtio-net detect | `make run-net` + `ifconfig` | Real MAC (not fake 52:54:00:12:34:56) | [ ] |
| A3.2 | Virtio-net BAR0 | `ifconfig` | BAR0 address shown, "active" | [ ] |
| A3.3 | Real ping TX | `ping` | "Packet sent via virtio-net TX" | [ ] |
| A3.4 | ICMP reply RX | `ping` | "Reply from 10.0.2.2: time=Xus" OR timeout | [ ] |
| A3.5 | ARP cache | `arp` | ARP entries shown after ping | [ ] |
| A3.6 | XHCI detect | `make run` with `-device qemu-xhci` + `lsusb` | XHCI controller listed | [ ] |
| A3.7 | XHCI init | `usbinit` | "Controller running, N device(s)" | [ ] |
| A3.8 | USB device enum | `-device usb-storage,drive=usbdisk` + `usbinit` | Slot enabled, device addressed | [ ] |
| A3.9 | Ring 3 hello | Boot with default config | "[RING3] IRETQ to user mode..." in serial | [ ] |
| A3.10 | SMP boot | `make run-smp` | Boot with 4 cores, no crash | [ ] |

### A-Phase Quality Gate
- [ ] All 30 verification tasks checked
- [ ] Bug list documented (if any)
- [ ] All critical bugs fixed before proceeding

---

## Phase B: Fajar Lang v3.5.0 Release (1 sprint, 10 tasks)

**Goal:** Ship v3.5.0 with const fn, virtio-net, XHCI, modular fajaros-x86
**Effort:** ~1 hour
**Depends on:** Phase A (testing complete)

### Sprint B1: Release Engineering (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| B1.1 | Version bump | Cargo.toml → 3.5.0 | [ ] |
| B1.2 | CHANGELOG update | Add v3.5.0 section with all new features | [ ] |
| B1.3 | Update CLAUDE.md | Current stats (9,637 LOC, 148 cmd, 6,061 tests) | [ ] |
| B1.4 | Update Nova banner | "v0.5.0" → "v0.6.0" in kernel_main() | [ ] |
| B1.5 | Update fajaros-x86 README | Accurate feature list, LOC count | [ ] |
| B1.6 | Clippy clean | `cargo clippy -- -D warnings` — zero warnings | [ ] |
| B1.7 | Fmt check | `cargo fmt -- --check` — clean | [ ] |
| B1.8 | Full test suite | `cargo test --features native` — all pass | [ ] |
| B1.9 | Git tag | `git tag v3.5.0` on fajar-lang | [ ] |
| B1.10 | GitHub release | Create release with binaries + notes | [ ] |

### B-Phase Quality Gate
- [ ] `cargo test --features native` — 0 failures
- [ ] `cargo clippy -- -D warnings` — 0 warnings
- [ ] `cargo fmt -- --check` — clean
- [ ] CHANGELOG.md updated
- [ ] Git tag created

---

## Phase C: USB Mass Storage Complete (3 sprints, 30 tasks)

**Goal:** Read files from a USB stick in FajarOS Nova via XHCI + SCSI + FAT32
**Effort:** ~8 hours
**Depends on:** Phase A (XHCI verified working in QEMU)

### Sprint C1: Control Transfers + GET_DESCRIPTOR (10 tasks)

**Prerequisite:** XHCI controller running, slot enabled, device addressed

| # | Task | Detail | Status |
|---|------|--------|--------|
| C1.1 | Transfer Ring per endpoint | Allocate 64-TRB ring for EP0 at XHCI_XFER_BUF | [ ] |
| C1.2 | Setup TRB | Build 8-byte USB SETUP packet as Setup TRB | [ ] |
| C1.3 | Data TRB | Build Data TRB pointing to receive buffer | [ ] |
| C1.4 | Status TRB | Build Status TRB (zero-length, direction toggle) | [ ] |
| C1.5 | Ring doorbell for EP0 | Doorbell(slot_id, EP0_target=1) | [ ] |
| C1.6 | Poll Transfer Event | Wait for Transfer Event TRB on event ring | [ ] |
| C1.7 | GET_DESCRIPTOR (device) | bRequest=6, wValue=0x0100, wLength=18 | [ ] |
| C1.8 | Parse device descriptor | Extract VID, PID, bDeviceClass, bNumConfigurations | [ ] |
| C1.9 | GET_DESCRIPTOR (config) | bRequest=6, wValue=0x0200, wLength=255 | [ ] |
| C1.10 | Parse config descriptor | Extract interfaces, endpoints, bInterfaceClass | [ ] |

### Sprint C2: USB Mass Storage Detection (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| C2.1 | Find mass storage interface | bInterfaceClass=0x08, bInterfaceSubClass=0x06, bInterfaceProtocol=0x50 | [ ] |
| C2.2 | Extract bulk endpoints | Find bulk IN + bulk OUT endpoint addresses | [ ] |
| C2.3 | SET_CONFIGURATION | bRequest=9, wValue=1 — activate first config | [ ] |
| C2.4 | Configure Endpoint command | XHCI Configure Endpoint with bulk IN/OUT rings | [ ] |
| C2.5 | Allocate bulk transfer rings | 64 TRBs each for bulk IN + bulk OUT | [ ] |
| C2.6 | SCSI INQUIRY | CBW opcode 0x12 → get device name + type | [ ] |
| C2.7 | Parse INQUIRY response | Extract vendor, product, revision strings | [ ] |
| C2.8 | SCSI TEST UNIT READY | CBW opcode 0x00 → check device ready | [ ] |
| C2.9 | SCSI READ CAPACITY | CBW opcode 0x25 → total sectors + sector size | [ ] |
| C2.10 | `lsusb` with details | Show VID:PID, class, speed, capacity | [ ] |

### Sprint C3: Bulk-Only Transport + FAT32 Mount (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| C3.1 | CBW build function | 31-byte Command Block Wrapper (signature 0x43425355) | [ ] |
| C3.2 | CSW parse function | 13-byte Command Status Wrapper verification | [ ] |
| C3.3 | SCSI READ(10) | CBW opcode 0x28: read N sectors from LBA | [ ] |
| C3.4 | SCSI WRITE(10) | CBW opcode 0x2A: write N sectors to LBA | [ ] |
| C3.5 | Bulk transfer wrapper | Send CBW → data phase → receive CSW | [ ] |
| C3.6 | Register as blk_dev 2 | USB mass storage in block device table | [ ] |
| C3.7 | `usbread <lba>` command | Read + hex dump single sector from USB | [ ] |
| C3.8 | Mount FAT32 from USB | `mount /dev/usb0 /usb` → FAT32 init on blk_dev 2 | [ ] |
| C3.9 | `usbls` / `usbcat` commands | List + read files from USB FAT32 | [ ] |
| C3.10 | QEMU test: read file from USB | `-drive file=usb.img,if=none,id=usbdisk -device usb-storage,drive=usbdisk` | [ ] |

### C-Phase Quality Gate
- [ ] `lsusb` shows VID:PID of USB storage device
- [ ] `usbinit` enables slot + addresses device + reads descriptor
- [ ] SCSI INQUIRY returns device name
- [ ] SCSI READ(10) reads sector data
- [ ] FAT32 file listing from USB stick in QEMU

---

## Phase D: New Language Features (2 sprints, 20 tasks)

**Goal:** Improve Fajar Lang with const arrays, const structs, better errors
**Effort:** ~4 hours
**Depends on:** Phase B (v3.5.0 released)

### Sprint D1: const Arrays & Structs (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| D1.1 | `const TABLE: [i64; 4] = [1, 2, 3, 4]` | Static array in const context | [ ] |
| D1.2 | `const TABLE = [0; 256]` | Repeat syntax `[expr; count]` in const | [ ] |
| D1.3 | Const array indexing | `const X = TABLE[2]` at compile time | [ ] |
| D1.4 | Const array in codegen | Emit as static data in .rodata | [ ] |
| D1.5 | `const fn` returning array | `const fn make_table() -> [i64; 4]` | [ ] |
| D1.6 | Const struct init | `const ORIGIN = Point { x: 0, y: 0 }` | [ ] |
| D1.7 | Const struct field access | `const X = ORIGIN.x` at compile time | [ ] |
| D1.8 | Const fn body validation | Error on heap alloc, I/O, mutable ref in const fn | [ ] |
| D1.9 | Tests: 10 const array/struct cases | Verify codegen + interpreter | [ ] |
| D1.10 | Document: FAJAR_LANG_SPEC.md | const fn + const arrays section | [ ] |

### Sprint D2: Error Recovery & Diagnostics (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| D2.1 | Error: non-const op in const fn | Clear error message: "heap allocation not allowed in const fn" | [ ] |
| D2.2 | Error: mutable binding in const fn | "mutable variables not allowed in const fn" | [ ] |
| D2.3 | Error: non-const fn call in const fn | "function 'X' is not const" | [ ] |
| D2.4 | Error: const fn recursion limit | "const fn recursion limit exceeded (128 levels)" | [ ] |
| D2.5 | Error: const fn overflow | "arithmetic overflow in const fn evaluation" | [ ] |
| D2.6 | Const fn suggestion | When calling non-const fn in const context, suggest adding `const` | [ ] |
| D2.7 | Better type mismatch errors | Show expected vs actual type with source location | [ ] |
| D2.8 | Unused const warning | Warn when const defined but never used | [ ] |
| D2.9 | Tests: 10 error message cases | Verify error output quality | [ ] |
| D2.10 | Error codes: CE011-CE015 | New error codes for const fn violations | [ ] |

### D-Phase Quality Gate
- [ ] `const TABLE: [i64; 4] = [1, 2, 3, 4]` works in codegen
- [ ] `const ORIGIN = Point { x: 0, y: 0 }` works
- [ ] Non-const operations in const fn produce clear error messages
- [ ] All tests pass (6,061+ lib tests)
- [ ] FAJAR_LANG_SPEC.md updated

---

## Phase E: FajarOS Nova v0.6 Architecture (3 sprints, 30 tasks)

**Goal:** Transform Nova from interactive shell to real multitasking OS
**Effort:** ~12 hours
**Depends on:** Phase A (verified), Phase C (USB working)

### Sprint E1: Real Preemptive Scheduler (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| E1.1 | Timer IRQ context switch | LAPIC/PIT fires → save regs → pick next → restore | [ ] |
| E1.2 | Per-process kernel stack | Each PID gets 4KB kernel stack at alloc time | [ ] |
| E1.3 | Context frame struct | Define register save area (RAX-R15, RIP, RSP, RFLAGS, CR3) | [ ] |
| E1.4 | save_context(pid) | Push all GPRs + RSP + RIP to process table | [ ] |
| E1.5 | restore_context(pid) | Pop all GPRs + RSP + RIP, IRETQ to process | [ ] |
| E1.6 | Round-robin pick_next() | Cycle through READY PIDs, skip current | [ ] |
| E1.7 | Timer ISR calls scheduler | IRQ0 handler: EOI → save → pick → restore → IRET | [ ] |
| E1.8 | `spawn` command | Fork process, set entry point, add to ready queue | [ ] |
| E1.9 | Multiple processes running | `spawn counter` + `spawn hello` → both produce output | [ ] |
| E1.10 | Test: preemption works | Process A runs, timer fires, process B runs, etc. | [ ] |

### Sprint E2: Multiple Ring 3 Programs (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| E2.1 | User program registry | Table: name → {code_addr, code_size, entry_point} | [ ] |
| E2.2 | `install` builtin | Install user binary to registry from raw bytes | [ ] |
| E2.3 | `run <name>` command | Look up program, create Ring 3 process, switch to it | [ ] |
| E2.4 | SYS_WRITE from Ring 3 | User writes to stdout → kernel prints to VGA/serial | [ ] |
| E2.5 | SYS_EXIT from Ring 3 | User exits → kernel marks zombie, returns to shell | [ ] |
| E2.6 | SYS_GETPID from Ring 3 | User queries PID → kernel returns current PID | [ ] |
| E2.7 | hello.elf user program | "Hello from Ring 3!\n" via SYSCALL | [ ] |
| E2.8 | counter.elf user program | Print numbers 1-10, each via SYS_WRITE | [ ] |
| E2.9 | fibonacci.elf user program | Compute fib(20), print result via SYS_WRITE | [ ] |
| E2.10 | Test: 3 programs sequential | run hello → run counter → run fib → all succeed | [ ] |

### Sprint E3: Persistent Storage + Real Network (10 tasks)

| # | Task | Detail | Status |
|---|------|--------|--------|
| E3.1 | NVMe write-back | `sync` command flushes dirty FAT32 sectors | [ ] |
| E3.2 | Persistent file test | Write file, reboot, verify file still exists | [ ] |
| E3.3 | FAT32 from NVMe at boot | Auto-mount /mnt/nvme0 if NVMe has FAT32 | [ ] |
| E3.4 | DHCP client (minimal) | Discover → Offer → Request → Ack for IP assignment | [ ] |
| E3.5 | TCP connect (SYN handshake) | 3-way handshake to remote server | [ ] |
| E3.6 | TCP data send/recv | Send HTTP GET, receive response | [ ] |
| E3.7 | `wget` command | Fetch URL via TCP/HTTP → save to FAT32 | [ ] |
| E3.8 | DNS resolver (minimal) | Query 10.0.2.3 (QEMU DNS) for hostname → IP | [ ] |
| E3.9 | `nslookup` command | `nslookup example.com` → IP address | [ ] |
| E3.10 | Network demo | `wget http://10.0.2.2:8080/hello.txt` → save → cat | [ ] |

### E-Phase Quality Gate
- [ ] Timer-driven preemptive scheduling works (2+ processes)
- [ ] 3 Ring 3 user programs run successfully
- [ ] File persistence across reboot (NVMe + FAT32)
- [ ] At least DHCP + ICMP ping with real IP from QEMU
- [ ] All serial + VGA output correct

---

## Dependency Graph

```
Phase A: Test & Verify (6 hrs)
    |
    +---> Phase B: v3.5.0 Release (1 hr)
    |         |
    |         +---> Phase D: Language Features (4 hrs)
    |
    +---> Phase C: USB Mass Storage (8 hrs)
    |
    +---> Phase E: Nova v0.6 Architecture (12 hrs)
              |
              +---> E1: Preemptive Scheduler
              +---> E2: Multiple Ring 3 Programs
              +---> E3: Persistent Storage + Network
```

## Timeline

```
Session 1:  Phase A (Sprint A1-A3)    — Test everything in QEMU
            Phase B (Sprint B1)        — Ship v3.5.0
Session 2:  Phase C (Sprint C1-C2)    — USB control transfers + detection
Session 3:  Phase C (Sprint C3)       — Mass storage BOT + mount
            Phase D (Sprint D1)        — const arrays + structs
Session 4:  Phase D (Sprint D2)        — Error diagnostics
            Phase E (Sprint E1)        — Preemptive scheduler
Session 5:  Phase E (Sprint E2-E3)    — Ring 3 programs + network
```

## Target Metrics

| Metric | Current (v0.5) | Target (v0.6) |
|--------|---------------|---------------|
| Nova LOC | 9,637 | ~13,000 |
| Nova commands | 148 | 165+ |
| Shell commands verified | 0 (untested) | 148 (all tested) |
| User programs in Ring 3 | 1 (hello) | 3+ (hello, counter, fib) |
| Network | Virtqueue impl (untested) | Real ICMP ping verified |
| USB | XHCI init (untested) | Mass storage read/write |
| Preemptive scheduling | None (cooperative) | Timer-driven round-robin |
| Fajar Lang version | v3.4.0 | v3.5.0 |
| Fajar Lang tests | 6,051 | 6,100+ |
| const fn features | Basic (int only) | Arrays + structs + errors |
| Persistent storage | RAM only | NVMe write-back |

## Summary

```
Phase A:  Test & Verify         3 sprints   30 tasks    ~6 hrs    HIGHEST priority
Phase B:  v3.5.0 Release        1 sprint    10 tasks    ~1 hr     After A
Phase C:  USB Mass Storage      3 sprints   30 tasks    ~8 hrs    After A
Phase D:  Language Features     2 sprints   20 tasks    ~4 hrs    After B
Phase E:  Nova v0.6 Arch        3 sprints   30 tasks    ~12 hrs   After A+C

Total:    12 sprints, 120 tasks, ~31 hours
```

---

*Nova v0.6 "Ascension" — from prototype to production*
*Built with Fajar Lang + Claude Opus 4.6*
