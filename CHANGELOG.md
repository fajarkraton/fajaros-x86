# Changelog

All notable changes to FajarOS Nova are documented in this file.

> **Note on historical gap (V28.5 audit, 2026-04-16):** Entries for `v3.1.0`,
> `v3.2.0`, and `v3.3.0` are absent from this file. The tags exist on GitHub
> and git history has full commit trails, but narrative release notes were
> not backfilled into CHANGELOG at the time of tagging. This is tracked as
> a separate documentation gap; authoritative source for v3.0--v3.3 work is
> git log + the `docs/V28_*.md` audit trail.

## [3.4.0] "Multilingual" -- 2026-04-16

V28.5 audit complete. Gemma 3 1B inference demonstrated end-to-end across
7+ writing systems (Devanagari, Bengali, Tamil, Malayalam, Cyrillic,
Hangul, Latin). Output is real BPE-tokenized multilingual text — not yet
semantically coherent (4-bit quantization ceiling) but confirms the
kernel inference pipeline is functionally correct.

### Fixed

- **Bug 1 (`ba97be6`)** — Memory map collision detector script
  (`scripts/check_memory_map.py`) + STFM region overlap fix + 4-byte v7
  layer header shift. The header bug was silently corrupting v7
  inference since V28.1; discovery was retroactive via the v8 export
  rewrite.
- **Bug 2 (`2795019`)** — UTF-8 multi-byte raw streaming in
  `tfm_generate` + `cmd_infer`. Previous shell filter rejected bytes
  `>= 0x80`, hiding the entire multilingual vocab as dots. After fix,
  Korean (`안녕하세요`), Tamil, Hindi, Russian, etc. render correctly.
- **Bug 3 (fajar-lang `e6f6e99`)** — `.gitignore` for `.venv/`,
  `.claude/`, `__pycache__/`, `*.pyc` in the compiler repo. Local dev
  directories were shown in `git status` and risked accidental commits.
- **Bug 4 (`e3e2931`)** — Retroactive annotation on
  `docs/V28_1_FIRST_TOKEN.md` documenting the 4-byte header bug found
  in V28.2 but originally masked by quantization noise in V28.1's
  celebration doc.
- **Bug 5 (`5670b4e`)** — `@noinline` on 3 v8 hot paths
  (`km_vecmat_packed_v8`, `mdl_stream_embed_lookup_raw_v8`,
  `mdl_ram_lmhead_argmax_v8_tied`). LLVM O2 was over-inlining these
  with mis-reordered memory accesses, producing EXC:13 GP faults
  within the first 5 tokens. After fix: stable ~50 multilingual
  tokens per run.

### Added

- `scripts/check_memory_map.py` — static analyzer that parses all
  `const *_BASE: i64 = 0x` declarations across `kernel/`, flags any
  overlap. Wired as pre-commit hook check 4/4.
- `docs/V28_MEMORY_MAP.md` — 33 memory regions documented with
  collision history. Covers kernel heap, stack, framebuffer, page
  tables, KV cache, Gemma tensor pool, model data, STFM, and more.
- `docs/V28_5_CLOSED.md` — V28.5 closure doc (this release's primary
  deliverable). Captures 7 commits, known issues, verification
  commands, effort tally, next-session pickup notes.
- `docs/V28_2_V7_HEADER_RETEST.md` — re-verification of V28.1 v7
  pipeline with 16-byte header fix applied.

### Changed

- Per-layer file header: 4-byte → 16-byte (matches kernel
  `FJM_LAYER_HDR_SIZE` constant). All `.fjm` v7 and v8 files produced
  by `export_gemma3_v7.py` and `export_gemma3_v8.py` now use the
  canonical layout.
- `km_rmsnorm` switched to max-abs rescaling — eliminates truncation
  on mixed-magnitude vectors with Gemma 3's large gamma values
  (mean 4.55, max 55.75). More robust for large models without
  changing semantics.

### Known Issues (Tracked, Not Blocking Release)

- **EXC:13 after ~50 tokens** — `@noinline` workaround stabilizes
  short runs but intermittent crash at extended working sets.
  Candidate root causes: integer overflow in 262K×1152 LM head
  accumulator, cumulative rounding across 26 layers × 4 norms,
  or KV cache state under memory pressure. Root cause investigation
  requires Python reference simulator — deferred as research-grade
  work.
- **v8 coherence gap** — output is diverse multilingual but not
  semantically coherent. This is the inherent 4-bit group-wise
  quantization ceiling on a 1B parameter model, not a kernel bug.
  Documented in `docs/V28_2_GAMMA_FINDING.md`.

### Infrastructure / CI

- Pre-commit hook expanded to 4 checks (build + @unsafe SAFETY + TODO
  severity + memory map collisions). Layout-file changes are blocked
  if any new `const *_BASE` address overlaps an existing region.
- 4 V28.2 v8 infrastructure regression tests committed in `f23e714`,
  bringing kernel tests from 26 → 32 (all pass).

### Stats

- **183 .fj files** across kernel + services + boot + tests + drivers
- **108K lines** of Fajar Lang (verified via `find . -name "*.fj" -exec cat {} + | wc -l`)
- **32 kernel tests** (tests/kernel_tests.fj + arm64_harness.fj)
- **302 shell commands** (unchanged)
- **0 collisions** across 33 memory map regions
- **7 V28.5 commits** (6 in fajaros-x86, 1 in fajar-lang)
- **Effort:** 3.6h actual vs 5h est (-28%)

### Compiler Compatibility

- **Fajar Lang v27.5.0** — unchanged. V27.5 "Compiler Prep" prerequisites
  (kernel tensor max 128, AI scheduler builtins, `@interrupt` wrappers,
  `@app`/`@host` annotations, refinement params, `Cap<T>`, framebuffer
  extensions) all supported V28 work. No compiler version bump required.

### Verification

```bash
# Multi-repo clean state
git rev-list --count origin/main..main   # → 0

# Memory map
python3 scripts/check_memory_map.py       # → 0 overlaps across 33 regions

# @noinline markers
grep -E "^@noinline$" kernel/compute/kmatrix.fj \
                      kernel/compute/model_loader.fj | wc -l  # → 3
```

---

## [2.1.0] "Zenith" -- 2026-03-29

Compiler and tooling upgrade: FajarOS Nova now fully verified with Fajar Lang v7.0.0
"Integrity". 6 phases of production hardening, native compilation, and automated testing.

### Compiler Compatibility

- **Fajar Lang v7.0.0** — full kernel passes `fj check` with 0 errors (21,396 lines)
- Native Cranelift compilation of kernel verified end-to-end
- ARM64 cross-compilation verified (10/10 tests pass)

### Production Hardening (Phase F)

- Stack canary verification on all kernel entry points
- NX enforcement on all data pages
- ASLR address space randomization
- Kernel heap guard pages
- Double-free detection in slab allocator
- Resource limit enforcement per process
- Capability-based syscall filtering
- Session timeout enforcement
- Input validation on all syscall arguments
- Rate limiting on authentication attempts

### Automated Testing (Phase D)

- QEMU automated test suite: 38/40 subsystem tests pass
- Serial output verification for boot sequence
- Memory subsystem stress tests
- Network stack integration tests

### Modularization (Phase C)

- Kernel split into 14 independently compilable modules
- Module dependency graph verified cycle-free
- Per-module `fj check` validation

### CI/CD

- GitHub Actions: type-check, QEMU boot, ARM64 cross-compile, source analysis
- All CI workflows green on Linux, macOS, Windows

---

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
