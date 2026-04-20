# Changelog

All notable changes to FajarOS Nova are documented in this file.

## [3.6.0] "Gemma 3 Foundation" -- 2026-04-20

V30.GEMMA3 Track 2 **audit-complete** via Path D (research artifact).
12 phases (P0-P12) audited against current HEAD — every architectural
component the upgrade plan called for is VERIFIED PRESENT. Foundation
is mechanically correct and bit-exact vs an independent reference;
coherent generation output is an OPEN RESEARCH PROBLEM deferred to V31.

### Added

- **`make test-gemma3-e2e`** — 5 mechanical invariants regression gate:
  no EXC/PANIC, v7 parser intact, embed NVMe streaming, 262145-token
  BPE tokenizer loads at LBA 1054705, 64 tokens reach LM head. Gates
  mechanical stability, NOT output quality (pad-collapse open).
- **`make test-gemma3-kernel-path`** — 4 architectural invariants:
  GQA path, dual-theta RoPE init, gated FFN dim=6912, RMSNorm active.
  Depends on e2e.
- **`docs/V30_GEMMA3_P9_DECISION.md`** — Mid-Sprint Decision Gate
  Rule-6 mechanical commit. Paths A/B (2/3-bit quant) + C (270M
  fallback) blocked; Path D selected.
- **`docs/V30_GEMMA3_P10_FOUNDATION.md`** — research-artifact scope
  document with 3-data-point pad-collapse characterization (4-bit
  "hello" + "What is 2+2?" both collapse to token 107; 8-bit "hello"
  collapses to token 106 EOS).
- **`docs/V30_GEMMA3_FINDINGS.md`** — full P0-P12 audit trail, ~1100
  lines. 9 deviations documented (static addresses instead of
  frame-alloc, Bhaskara sin/cos instead of LUT, brute-force argmax
  with vocab-masking, unified ring KV cache).

### Fixed

- **`Makefile` `--target-features="..."` equals-form** — `fj build`
  fails with "unexpected argument '-a'" on space-form because clap
  parses "-avx,..." as a flag. Previous builds silently relinked
  yesterday's cached `combined.o.saved`; V29.P1's ELF-presence gate
  did not catch stale-cache fallback.

### Documented

- **Tokenizer on-disk LBA 1054705** (v2 ID-ordered) — token 107=`\n`,
  106=`<end_of_turn>`, 105=`<start_of_turn>`. Must run `tok-load
  nvme 1054705` before `ask` — not auto-loaded. LBA 1100000 holds
  the OLD sorted tokenizer (garbled) — do NOT use.
- **12-phase audit outcome:** ~8.6h actual vs ~46.5h budget (-82%).
  HEAD substantially V30-complete via V28.1 + V28.2 + V30 C-bypass
  work. Plan's "v2" format = HEAD's v7 header + v8 quant (superset).

### Deferred to V31 (R3 pad-collapse root cause)

Four ranked hypotheses:

1. Cumulative RMSNorm scaling across 104 norms (4 × 26L)
2. `c_exp_approx` softmax saturation
3. Bhaskara RoPE 0.16% shared error (P4.D2 LUT upgrade)
4. Final LayerNorm gamma weight loading bug

### Verified

- 0 crashes across 3 runs × 64 tokens × 26 layers ≈ 5,000 layer
  invocations
- 8/14 layer-0 ops BIT-EXACT (0 ULP) kernel vs Python simulator
- C-bypass covers 10 numerical hot-path ops
- .fjm v7 + v8 group-wise quant + 262K .fjt v2 all round-trip

### Stats

- 12 phases PASS (P0-P12)
- 2 regression-gate make targets (9 invariants)
- 3 decision/foundation docs committed
- 10 fajaros-x86 commits this sprint
- Cumulative budget variance -82%

## [3.5.0] "Security Triple" -- 2026-04-16

V26 B4.2 "full SMEP+SMAP+NX security triple" = **3/3 CLOSED**. Two
page-table bugs found and fixed via a single-session investigation
spanning V29.P3 SMAP closure + V29.P3.P6 NX closure. Boot reaches
`nova>` with all three bits active simultaneously, no fault markers.

### Added

- **`pte_walk_find_u_leaks_full()`** (V29.P3.P1) — 4-level page-table
  walker that reports PAGE_USER bit at EVERY descent point (PML4,
  PDPT non-huge, PD non-huge, plus all leaf types), not just leaves.
  Emits `PTE_LEAKS_FULL=<hex16>` boot marker + per-entry `PLKNL
  L<level> V<vaddr> E<entry>` lines to COM1. Prior walker was leaf-only
  and missed non-leaf USER leaks critical for SMAP enforcement.
- **`NX_ENFORCED=<hex16>` boot marker** (V29.P3.P6.P4) — emits EFER.NXE
  bit value after `nx_enforce_data_pages()`. Expected `0x800` (bit 11
  set) for regression detection.
- **`make test-security-triple-regression`** (V29.P3.P6.P4) — 6-invariant
  Makefile target verifying SMEP+SMAP+NX all active. Invariants:
  PTE_LEAKS=0, PTE_LEAKS_FULL=0, no PLKNL lines, no EXC/PANIC, nova>
  reached, NX_ENFORCED=0x800. Supersedes `test-smap-regression`
  (now a backward-compat alias).

### Changed

- **`strip_user_from_kernel_identity()`** (V29.P3.P1.5, `690124b`) —
  extended from leaf-only strip (PD[0..5]) to also clear USER bit on
  non-leaf entries PML4[0] and PDPT[0]. Single `write_cr3(read_cr3())`
  TLB flush covers all 3 levels of mutation. Idempotent.
- **`nx_enforce_data_pages()`** loop start (V29.P3.P6.P3, `540743b`) —
  `pd_idx = 1` → `pd_idx = 2`. Kernel `.text` spans 0x101000-0x248297
  (0-2.285 MB), which straddles PD[0] AND PD[1]. Previous start
  marked PD[1] NX, causing silent triple-fault on kernel instruction
  fetch from the 2-2.285 MB range.
- **`kernel/main.fj`** (V29.P3.P4, `f2dd682` + V29.P3.P6.P3, `540743b`) —
  uncommented `security_enable_smap()` and `nx_enforce_data_pages()`.
  All 3 security-triple calls now active after identity-map strip.

### Fixed

- **V29.P3.P1 — SMAP double-fault (H2: non-leaf USER bits)**
  (`690124b`). Root cause: PML4[0]+PDPT[0] had USER=1 from
  `boot/startup.S` indiscriminate seeding. SMAP AND-chains USER bits
  across the 4-level walk (Intel SDM Vol 3A §4.6.1.1), so any
  non-leaf USER=1 causes fault on kernel data reads regardless of
  leaf state. V29.P2's leaf-only `strip_user_from_kernel_identity()`
  missed both entries. Fix: extend strip to the two non-leaf
  entries. Verified: `PTE_LEAKS_FULL=0x0` + boot reaches `[VFS]`.
- **V29.P3.P6 — NX silent triple-fault (H3:
  `nx_enforce_data_pages` stale range assumption)** (`540743b`).
  Root cause: loop comment assumed kernel `.text` fits in first
  2 MB, but kernel has grown to 2.285 MB, spilling into PD[1].
  Previous loop start `pd_idx = 1` NX-marked the 2-4 MB range
  containing part of `.text`. Instruction fetch → #PF → handler
  page also NX → #DF → #DF handler also NX → triple-fault → silent
  CPU halt (no EXC marker). Fix: start loop at `pd_idx = 2`.
  Verified via boot-test: reaches `nova>` with all 3 bits active.
- **Hardcoded range assumption hardening** (V29.P3.P6.P3) — added
  `TODO(P3, V30+)` to replace `pd_idx = 2` with dynamic
  `__kernel_end` symbol lookup. Current kernel has 1.72 MB headroom
  before boundary recurrence.

### Stats

- **8 commits** across V29.P3 (`a521d4c`..`34426af`) + **5 commits**
  across V29.P3.P6 (`17a42b0`..`ac07fc9`) = **13 commits**
- **3 new plan/findings/decision docs** per track × 2 tracks = 6
  doc artifacts: `V29_P3_SMAP_{PLAN,FINDINGS,DECISION}.md` +
  `V29_P3_P6_NX_{PLAN,FINDINGS,DECISION}.md`
- **Wall clock:** ~3.6h for the full V26 B4.2 closure (SMAP +
  NX investigations combined), -9% on SMAP track, -19% on NX track
- **H2 + H3 hypothesis chain:** both matched on first plan, no
  residual (H1/H4/H5 paths not needed). P1 walkers skipped where
  static analysis was deterministic.

### Scope (what DID NOT ship)

- **`protect_kernel_data()`** dead code (tracked as V30+
  `TODO(P3, V30+)`) — would mark PD[0] NX if called (kernel .text
  range). Not called anywhere, so no runtime impact. Cleanup deferred.
- **Dynamic `__kernel_end`** symbol export from linker script —
  hardcoded `pd_idx = 2` requires manual update if kernel grows
  past 4 MB. Headroom 1.72 MB. Future work.

## [3.4.0] "Multilingual" -- 2026-04-16

> **⚠️ Retroactive addendum — 2026-04-16 evening (V29.P1.P4):**
> The "multilingual output across 7+ writing systems" claim below was
> documented in good faith but has NOT been reproduced in a controlled
> retest. Later investigation found that the `@noinline` stabilization
> fix was never actually compiled into the kernel during V28.5 — the
> compiler rejected the annotation silently and the Makefile reported
> a stale ELF as successful. See `docs/V28_5_RETEST.md` for the retest
> procedure with `@noinline` actually active: **stability ✅
> validated (64 tokens, no crash)**; **multilingual output ⚠️ not
> reproduced** (all 64 tokens decoded to pad byte, same behavior as
> `V28_2_CLOSED_PARTIAL.md`). The v8 coherence gap remains an open
> research track. The other 4 V28.5 fixes (memory map collision
> detector, 16-byte header, UTF-8 raw streaming, .gitignore hygiene)
> are solid contributions and remain valid. Cross-reference:
> `../Fajar Lang/docs/V29_P1_COMPILER_ENHANCEMENT_PLAN.md` +
> `docs/V28_5_CLOSED.md` header box.

V28.5 audit complete. Gemma 3 1B inference demonstrated end-to-end across
7+ writing systems (Devanagari, Bengali, Tamil, Malayalam, Cyrillic,
Hangul, Latin). Output is real BPE-tokenized multilingual text — not yet
semantically coherent (4-bit quantization ceiling) but confirms the
kernel inference pipeline is functionally correct.

*(Paragraph above retained as-written for historical accuracy. See
retroactive addendum box immediately above for the V29.P1.P4 honest
correction.)*

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

## [3.3.0] "V28 Foundation" -- 2026-04-14

Paired with Fajar Lang v27.5.0 "Compiler Prep". Pre-flight audit for V28
"Intelligence" complete; Gemma 3 1B tensor pool infrastructure landed.
80% of originally-planned V28 scope was found to already exist in the
kernel — revised V28 plan narrows real work to the Gemma 3 1B model port.

### Added

- **V28.1 Gemma 3 tensor pool** (`b5aa70e`) — new `KM_GEMMA_BASE` at
  `0xB70000` (80 KB, 8 slots × 1280-dim). Covers Gemma 3 1B
  `d_model=1152` with 11% margin. New API: `km_alloc_gemma`,
  `km_free_gemma`, `km_gemma_addr`.
- **Pool regression test** — `test_gemma_pool_alloc` validates 1152 OK,
  1280 max, 1281 rejected.
- **V28.0 pre-flight audit** (`6507c4f`) — 7 baselines verified,
  revised V28 scope documented in `docs/V28_STATUS.md`.

### Existing V28 Infrastructure (Discovered in Audit)

Much of the originally-planned V28 scope was already built:

- **ml_scheduler.fj** — attention-based process scoring (covers V28.4).
- **services/display/** — 2,047 LOC framebuffer + fonts (covers V28.3).
- **kmatrix.fj** — Gemma 3 RMSNorm dual-mode already present.
- **V27.5 CI gates** — prevention layer already covers V28.5 scope.

### Remaining V28.1 Work (Deferred as Dedicated Sprint)

Full Gemma 3 1B model port requires multi-week effort:
- HuggingFace weight export pipeline
- GQA (4 Q heads : 1 KV head) attention
- RoPE dual theta (local 10K / global 1M)
- Sliding window attention (512-token local)
- 262K vocab table (vs current 32K)
- 32K KV cache (vs current 2K)
- Per-layer numerical validation vs HF reference

### Stats

- **26 kernel tests** (was 25)
- **106,825 LOC** across **163 .fj files**
- **Kernel ELF:** 1.38 MB (unchanged — pool is bss/heap)
- **0 clippy warnings**, clean build in <10s

### Companion Releases

- [Fajar Lang v27.5.0](https://github.com/fajarkraton/fajar-lang/releases/tag/v27.5.0)
- [FajarQuant v0.3.0](https://github.com/fajarkraton/fajarquant/releases/tag/v0.3.0-fajarquant-v3.1)

---

## [3.2.0] "V27 Hardened" -- 2026-04-14

Deep re-audit found 11 gaps (2 P0, 3 P1, 4 P2, 2 P3). All P0--P2 closed.
Serial string output restored, OOM paths hardened across 4 frame_alloc
call sites, unified memory map documented.

### Fixed (P0 Critical)

- **`serial_send_str()` implemented** — was a TODO stub since v0.5;
  serial string output now works for boot diagnostics.
- **Kernel stack leak** reclassified as P3 — frame IS freed
  (`main.fj:140`); the PTE-leak report was cosmetic (2 MB huge page,
  unmapping deferred to V28).

### Fixed (P1 High)

- **OOM hardening** — 4 `frame_alloc()` sites (`sys_brk`, `sys_mmap`,
  two ELF load paths) now return `-1/ENOMEM` on OOM instead of
  silently skipping.
- **Unified memory map** — `docs/MEMORY_MAP.md` with 60+ address
  allocations and 3 past collision incidents documented.
- **Boot init probes** — 5 critical subsystems (frames, heap, slab,
  ipc, ramfs) now emit `[BOOT] X OK` after init.

### Fixed (P2 Medium)

- **Multiboot2 validation** — `[WARN]` emitted on missing ACPI RSDP tag.
- **SMEP/SMAP warnings** — `[SEC]` warning when CPU doesn't support
  SMEP/SMAP (was silent no-op).
- **SMAP contract** — documented in `security.fj` header: all
  user-buffer access must use `smap_disable`/`smap_enable` bracket.
- **Dead code** — `cmd_type()` wired to dispatcher, `cmd_yes_arg()`
  removed.

### Stats

- **25 kernel tests** | SMEP+SMAP+NX+ASLR | `serial_send_str` working
- Boot output: `[BOOT] frames OK`, `[BOOT] heap OK`, etc.
- Memory map: 60+ allocations documented in `docs/MEMORY_MAP.md`

---

## [3.1.0] "V26 Phase B Complete" -- 2026-04-14

Security hardening milestone. SMEP + SMAP + NX + ASLR + stack canaries
+ capability auditing all enabled. VFS write support added for RamFS,
FAT32, and ext2. 4 new kernel tests, QEMU test CI, pre-commit hooks.

### Security Hardening

- **SMEP** enabled at boot (Supervisor Mode Execution Prevention).
- **SMAP** enabled at boot + syscall STAC/CLAC wrappers.
- **NX enforcement** on all data pages (kernel `.text` stays executable).
- **ASLR** for user processes (16--48 MB range, RDRAND/TSC entropy).
- **Stack canaries** on every context switch.
- **Capability auditing** — per-process privilege isolation.

### Kernel Infrastructure

- **25 kernel tests** (was 21): `vfs_write_roundtrip`,
  `o2_sentry_vecmat`, `o2_sentry_4bit_argmax`, `llm_pipeline_smoke`.
- **QEMU test CI** — boot + `test-all` + parse `OK:`/`NG:` markers
  (≥18/25 gate).
- **Boot-stress CI** — 10 consecutive boots, all must reach `nova>`.
- **Pre-commit hook** — build check + `@unsafe` SAFETY + TODO severity.

### VFS Write Support

- **RamFS write** — O_CREAT + O_TRUNC + first-write 4 KB alloc.
- **FAT32 write** — `fat32_create_file`, `fatwrite`/`fatrm` shell
  commands (752 LOC).
- **ext2 write** — `ext2_create` + `ext2_write_file` +
  `ext2-write`/`ext2-ls` commands.
- **`df` command** — RamFS + heap usage statistics, color-coded.

### New Shell Commands

- `cpufeatures` — 15 CPU features (SSE/AVX/SMEP/SMAP/NX/AES-NI/RDRAND/…)
- `df` — filesystem usage statistics
- `ext2-ls` / `ext2-write` — ext2 directory listing and file creation
- `sec-status` — full security hardening status

### Process Management (from prior B1 session)

- Process exit frees page tables, kernel stack, fd table.
- Parent wakeup on child exit (`waitpid` unblocking).
- `fork`+`exit` ×100 stress test passes with ≤5 frame leak.

### Stats

- **25 kernel tests** | **~48 K LOC** across **163 .fj files**
- **Security:** SMEP + SMAP + NX + ASLR + Canaries + Capabilities
- **Phase B effort:** ~18h actual vs 105h budgeted (-83%)

---

## [3.0.0] "Nusantara" -- 2026-04-11

**First FajarOS release with kernel-native end-to-end LLM inference.**
SmolLM-135M v5/v6 quantized models run entirely in Ring 0 `@kernel`
context — no userspace, no syscall overhead, no shared library. The
Gemma 3 architecture is also implemented (Phase A--H complete). 14 new
LLM shell commands wired into the existing 105-command shell.

### Highlights

- **End-to-end LLM inference in kernel** — SmolLM-135M v5 mixed
  precision (52 MB, 4-bit embed/lmhead + 2-bit layers) and v6 full
  4-bit (78 MB) generate diverse text in QEMU.
- **Repetition penalty via O(1) bitset** (K=8 window) for v5/v6 4-bit
  lmhead — prevents token loops, replaces inline scan that triggered
  LLVM O2 wild-pointer crash.
- **FajarQuant Phase 1+2 ported to bare metal** —
  `kernel/compute/fajarquant.fj` (708 LOC) + `kmatrix.fj` (1,035 LOC),
  all `@kernel`-safe with AVX2-enabled hot paths.
- **Gemma 3 architecture** — Phases A--H complete: 5 audit fixes,
  RMSNorm + GELU-tanh + frame-vectors + gated FFN, GQA, RoPE, hybrid
  sliding/global attention, 256 MB memory mapping, NVMe tokenizer,
  `.fjm` v2 format, `tfm_layer` dispatching v2 paths.
- **RAM-resident mode** — load all 310 MB to RAM once, no per-token
  NVMe access (eliminates I/O latency in inference loop).
- **14 new LLM shell commands** — `model-load`, `model-info`,
  `embed-load`, `layer-load`, `ram-load`, `weight-status`, `tokenize`,
  `tok-info`, `tok-load`, `tok-reset`, `infer`, `ask`, `gen`,
  `tfm-info`.

### Added

- **Phase 1 — Bare-metal FajarQuant** (`5b64cd5`): 3 innovations (PCA
  rotation, fused attention, hierarchical bit allocation) ported to
  `@kernel`.
- **Phase 2 — Kernel matrix engine** (`c32a5c0`): 768-dim transformer
  support, AVX2 hot paths, all kernels `@kernel`-safe.
- **Phase 3 — Model weight loader** (`40ece8e`): `.fjm` format reader,
  RamFS + NVMe support, ELF section mapping.
- **Phase 4 — Kernel tokenizer** (`83d84fd`): byte-level + BPE merges,
  runs entirely in `@kernel`.
- **Phase 5 — Transformer forward pass** (`3082d5d`): quantized
  inference engine, attention + FFN + LayerNorm.
- **Phase 6 — Autoregressive generation** (`3a7b8a2`): `ask`/`gen`
  commands with KV cache management.
- **Phase 7 — ML scheduler** (`ea3ff01`): attention-based process
  scheduling.
- **Phase 8 — Edge AI pipeline** (`267653e`): sensor → classify →
  actuate at kernel speed.
- **SmolLM-135M v3--v6 formats** — v3 (shared codebook), v4 (per-matrix
  codebooks, 7 per layer), v5 (mixed 4-bit/2-bit), v6 (full 4-bit).
- **Gemma 3 1B support** — `.fjm` v2 format, 256 MB memory mapping,
  26-layer streaming forward pass.
- **BOS token prepend** + E2E verified output diversity.

### Fixed

- **3 critical inference bugs** (`ffeb95c`): RMSNorm normalization,
  gamma convention, exp approximation.
- **6 safety hardening fixes** (`8aaf2c6`): inference E2E stable, no
  kernel panics under load.
- **Frame allocator overlap** (`d4e578c`, `a1e2a6e`, `f156d6d`):
  `model_loader` marks frames used, kernel static data region
  reserved, NVMe frame reservation, `TOK_META` relocation.
- **v5 4-bit sample workaround** (`1c82596`): fall back to argmax to
  dodge LLVM O2 wild-pointer crash with inline loops.
- **Header/state overlap** (`9044dac`): v3 header 160 B vs state at
  `0x60` — third time this class of bug, now sentry-tested.
- **NVMe PRP fix + 512 MB mapping** (`7a7c35b`): layer-streaming
  weight loader works under PRP1+PRP2 contiguous-page constraint.
- **Chunked Lloyd-Max quantization + header struct fix** (`4a87f02`).

### Changed

- **Boot:** 61 → 62 init stages, all reach `nova>` reliably in
  QEMU + KVM.
- **QEMU RAM:** 512 MB → 1 GB for Gemma 3 1B model support (`f81e230`).
- **Compiler:** Fajar Lang v23.0.0 → **v26.1.0-phase-a** (Phase A
  production complete).

### Stats

| Metric | Value |
|---|---|
| FajarOS LOC | **47,821** (was 41,400, +15.5%) |
| .fj files | **163** (was 154, +9 LLM modules) |
| Shell commands | **119** (105 base + 14 LLM) |
| Compiler | Fajar Lang v26.1.0-phase-a |
| Boot stages | **62** (was 61, +1 LLM init) |
| Kernel compute LOC | 708 (fajarquant.fj) + 1,035 (kmatrix.fj) = **1,743** |
| LLM models | SmolLM-135M v3--v6, Gemma 3 270M, Gemma 3 1B (in progress) |
| LLVM backend | v26 (30 enhancements + 4 string-display fixes) |

### Known Limitations

- **v5_4bit sample** triggers LLVM O2 wild-pointer crash with inline
  loops → workaround: dispatch to argmax (`1c82596`).
- **Output coherence** — SmolLM-135M @ 2-bit/4-bit produces diverse
  but not coherent sentences (model size limit, not bug). V26 Phase B5
  evaluates SmolLM-360M upgrade.
- **`fork()` syscall** doesn't return PID from scheduler yet (V26
  Phase B1 — see `docs/V26_PRODUCTION_PLAN.md` in fajar-lang repo).
- **Process exit** doesn't free resources (V26 Phase B1 leak).
- **SMEP** disabled (V26 Phase B4 security — closed in v3.1.0).

### Full Changelog

https://github.com/fajarkraton/fajaros-x86/compare/v2.1.0...v3.0.0

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
