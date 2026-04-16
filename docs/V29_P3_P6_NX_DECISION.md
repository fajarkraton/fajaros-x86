# V29.P3.P6 — Decision Gate (NX Silent Triple-Fault Root Cause)

**Phase:** V29.P3.P6.P2 (per `docs/V29_P3_P6_NX_PLAN.md` §4, Rule 6)
**Date:** 2026-04-16
**Decision status:** H3 MATCHED — P3 cleared to launch
**Gate type:** mechanical (committed file), per CLAUDE.md §6.8 Rule 6

---

## 1. Decision Summary

| Field | Value |
|-------|-------|
| **Matched hypothesis** | **H3 — `nx_enforce_data_pages()` mis-classifies PD[1] as data** |
| **Root cause** | `security.fj:236` loop starts at `pd_idx = 1`; kernel `.text` ends at 0x248297 (2.285 MB), spilling from PD[0] into PD[1] |
| **Chosen fix** | Single-line edit: `let mut pd_idx: i64 = 1` → `let mut pd_idx: i64 = 2` |
| **Fix complexity** | Trivial additive (bumps the loop start by 1 index) |
| **Estimated P3 effort** | 0.3h (edit + build + ISO + boot-test) |
| **Estimated P4+P5 effort** | 0.75h (regression target rename + doc sync) |
| **Total remaining effort** | 1.05h |

---

## 2. Hypothesis Assessment

Five hypotheses from `docs/V29_P3_P6_NX_PLAN.md` §1.2:

### H1 — Kernel `.text` page NX-marked

**Statement:** CPU faults on instruction fetch from NX-marked kernel page.

**Verdict:** ✅ **SECONDARY — symptom of H3**

**Evidence (from P0 FINDINGS §2, §3):**
- Kernel `.text` spans 0x101000–0x248297 (0-2.285 MB).
- H3's misclassification causes PD[1] (2-4 MB) to be NX-marked.
- Kernel instructions in the 2-2.285 MB range thus become NX, causing
  #PF on fetch.
- H1 *is* the observable effect, but not a distinct root cause — the
  effect disappears when H3's misclassification is fixed.

### H2 — `extend_identity_mapping_*` NX on wrong range

**Statement:** data-extend functions set NX on entries that cover kernel code.

**Verdict:** ❌ **NOT MATCHED**

**Evidence (from P0 FINDINGS §4):**
- `extend_identity_mapping()` touches PD[64..127] = 128-256 MB.
- `extend_identity_mapping_512()` touches PD[128..511] + PD2[0..511]
  = 256 MB - 2 GB.
- Both ranges are strictly ≥ 128 MB.
- Kernel `.text` ends at 2.285 MB.
- No overlap. NX-on-data in these functions is correct.

### H3 — `nx_enforce_data_pages()` mis-classifies

**Statement:** function's range assumption is stale; loop includes a
PD entry that actually contains kernel code.

**Verdict:** ✅ **PRIMARY MATCH**

**Evidence (from P0 FINDINGS §3):**
- `security.fj:236` loop: `let mut pd_idx: i64 = 1`.
- Comment (line 234-235) states: "Skip PD[0] (first 2MB contains
  kernel .text — must stay executable)".
- Comment assumption held at original commit time but is now stale:
  kernel `.text` has grown from < 2 MB to 2.285 MB, spilling into PD[1].
- Loop therefore marks PD[1] NX despite PD[1] containing 0x200000-0x248297
  of kernel code.
- On NX enable, first instruction fetch from 2-2.285 MB range triggers
  #PF → handler also on NX page → #DF handler also on NX page →
  triple-fault → silent halt (exactly the P4 bisect symptom).

### H4 — IDT/GDT/TSS descriptor page NX

**Statement:** descriptor tables (at 0x7EF000 per V29.P2 boot log) land
on NX-marked page, causing fault on any interrupt dispatch.

**Verdict:** ❌ **NOT PRIMARY — subsumed by H3**

**Evidence (from P0 FINDINGS §6):**
- TSS at 0x7EF000 = physical 7.93 MB = PD[3] (6-8 MB range).
- `nx_enforce_data_pages()` does mark PD[3] as NX.
- BUT: TSS is a DATA structure (CPU reads it, doesn't execute code
  from it). NX on TSS data page is CORRECT behavior — NX only blocks
  instruction fetch, not data read.
- IDT handler CODE, however, lives in `.text` (PD[0]+PD[1]). When
  H3 marks PD[1] NX, handler fetches from PD[1] sub-range fault. That's
  the actual failure path.
- H3 fix resolves both IDT handler fetch issues AND leaves TSS data
  NX-protected (desired).

### H5 — Residual (not in H1-H4)

**Verdict:** ❌ **NOT NEEDED**

**Reasoning:** H3 fully accounts for silent halt + post-nx_enforce
timing + absent EXC marker. No gap in explanation requires a new
hypothesis. P3 fix + boot-test will confirm.

---

## 3. Chosen Fix Path

### Step 1 — P3 fix (1-line change)

**File:** `kernel/core/security.fj`
**Line:** 236

**Before:**
```fj
    // PD entries 1-63 (2MB-128MB): set NX on data regions
    // Skip PD[0] (first 2MB contains kernel .text — must stay executable)
    let mut pd_idx: i64 = 1
```

**After:**
```fj
    // PD entries 2-63 (4MB-128MB): set NX on data regions. Kernel
    // image (.text + .rodata + .data + .bss) spans 0x101000-0x25e007,
    // which straddles PD[0] (0-2MB) AND PD[1] (2-4MB). Skip both to
    // keep kernel instructions executable. Verified via objdump -h
    // build/fajaros-llvm.elf against kernel .text end at 0x248297.
    //
    // TODO(V30+): replace hardcoded `2` with dynamic __kernel_end
    // symbol lookup so future kernel growth past 4 MB auto-handles.
    let mut pd_idx: i64 = 2
```

**Step 2 — P3 boot-test (success gate):**

Uncomment `nx_enforce_data_pages()` at `kernel/main.fj:189`, rebuild:
```
$ make build-llvm && make iso-llvm
$ timeout 15 qemu-system-x86_64 -cdrom build/fajaros-llvm.iso \
    -chardev stdio,id=ch0,signal=off -serial chardev:ch0 \
    -display none -no-reboot -no-shutdown \
    -m 1G -cpu Skylake-Client-v4
```

Expected markers:
- `PTE_LEAKS=0000000000000000`
- `PTE_LEAKS_FULL=0000000000000000`
- `[VFS] VFS service initialized`
- `nova>` shell reachable
- NO `EXC:` / `PANIC:` markers

### Step 3 — P4 regression + prevention

Rename `make test-smap-regression` → `make test-security-triple-regression`.
Add 6th invariant check:
- `grep -vE 'EXC:|PANIC:'` (already covered as FAIL pattern)
- Optional: assert kernel test suite includes `test_nx_enforced` (add in
  `tests/kernel_tests.fj`)

### Step 4 — P5 doc sync

- `CLAUDE.md` §3 row for V29.P3.P6
- `MEMORY.md` V29.P3 block: remove "NX deferred" note, mark fully closed
- `CHANGELOG.md` (fajaros-x86): optional v3.5.0 entry

---

## 4. Rejected Alternatives

| Alternative | Rejected because |
|---|---|
| **Run P1 NX walker to empirically verify** | Source inspection already deterministic. Walker would merely confirm the PD[1] mis-classification already evident from static analysis. Saves 0.55h. Precedent: V29.P3 main track skipped P2 for same reason. |
| **Ship without NX (keep V29.P3.P4 SMEP+SMAP scope)** | V26 B4.2 requires full security triple. H3 fix is single-line + trivial. Cost of fix far below cost of permanent NX gap. |
| **Dynamic `__kernel_end` lookup now** | Would require linker-script symbol export + Fajar Lang extern mechanism. Over-engineered for current kernel size. Track as V30+ hardening. |
| **Fix by extending kernel `.text` into higher virtual address** | Invasive — touches linker.ld + boot.S. Reserves scalability headroom but not needed: kernel is 2.285 MB / 4 MB available = 57% utilization. Plenty of headroom. |
| **Replace huge 2MB PD entries with 4KB PT entries for finer-grained NX** | Adds 1-2 kB page-table bloat + a 512-entry strip pass per PD. Performance impact negligible but complexity too high for a 1-line fix. Archive for if kernel ever needs sub-2MB NX granularity. |
| **Also fix `protect_kernel_data()` dead code now** | Function is never called — not a live bug. Bundle into separate V30+ cleanup. |

---

## 5. Scope Revision Log

Plan originally budgeted P0+P1+P2+P3+P4+P5 = 2.27h (B-H1/H2 branch).
Actual revision after P0:

| Phase | Original | Revised | Savings |
|-------|---------:|--------:|--------:|
| P0 | 0.37h | 0.27h (done) | -0.10h |
| P1 walker | 0.55h | 0h (SKIPPED) | -0.55h |
| P2 decision | 0.3h | 0.1h (this doc) | -0.2h |
| P3 fix | 0.3h | 0.3h | 0 |
| P4 regression | 0.4h | 0.4h | 0 |
| P5 doc sync | 0.35h | 0.35h | 0 |
| **Total revised** | **2.27h** | **1.42h** | **-37%** |

---

## 6. P3 Launch Gate

P3 entry requirements:
- [x] H3 matched with deterministic source evidence (§2)
- [x] Fix specification complete (§3 Step 1)
- [x] Decision gate file committed (THIS DOC)
- [x] Rollback path documented (revert `security.fj:236` line change)
- [ ] P3 fix commit pending

**Status: GREEN — P3 cleared to launch.**

---

## 7. P6 Effort Tally (Rule 5)

| Task | Estimate | Actual | Variance |
|------|---------:|-------:|---------:|
| Hypothesis assessment (already drafted in FINDINGS §6) | 0h | 0h | — |
| Rejected alternatives enumeration | 0.04h | 0.04h | 0% |
| Scope revision log | 0.02h | 0.02h | 0% |
| P3 launch gate | 0.02h | 0.02h | 0% |
| Doc write + commit | 0.08h | 0.08h | 0% |
| **Total P2** | 0.16h | 0.16h | 0% |

Well under the 0.3h plan budget (revised to 0.1h after P0 pre-drafting).
Minor overshoot at 0.16h vs 0.1h revised = +60% over revised, but
still -47% vs original.

---

## 8. Prevention Layer Preview (for P5)

P4/P5 will add these prevention mechanisms:

1. **Regression target rename:** `test-smap-regression` → `test-security-triple-regression` with 6th invariant (NX state verification).
2. **Source-level guard comment** at `security.fj:232-235`: explicit warning that the hardcoded `2` requires re-verification if kernel `.text` grows past 4 MB.
3. **Optional kernel test case** `test_nx_enforced` in `tests/kernel_tests.fj` (analog of `test_smep_enabled`) that verifies EFER.NXE=1 after boot.
4. **CLAUDE.md §3 row** documents the class of bug and the hardcoded-index anti-pattern.

---

*V29.P3.P6.P2 Decision Gate — generated 2026-04-16 by Claude Opus 4.6.
Gate status: GREEN. Referenced: `b3c20b8` (P0 findings), `17a42b0` (plan).*
