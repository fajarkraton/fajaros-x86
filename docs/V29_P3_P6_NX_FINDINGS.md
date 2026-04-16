# V29.P3.P6 — Phase P0 Pre-Flight Findings

**Phase:** V29.P3.P6.P0 (per `docs/V29_P3_P6_NX_PLAN.md`)
**Date:** 2026-04-16
**Plan reference:** P0.1–P0.6
**Outcome:** **H3 unambiguously matched from source inspection alone.**
Root cause identified without needing P1 NX walker. P1 can be skipped
(analog of P2 skip in V29.P3 main track).

---

## 1. P0.1 — Bisect Reproduction (SKIPPED with rationale)

Plan P0.1 calls for re-running the P4 bisect (SMEP+SMAP+NX) on
current HEAD. **Skipped** because:

- Between P4 bisect (commit `f2dd682`) and P6 start (HEAD `17a42b0`),
  the only diffs are:
  - `34426af` — adds `make test-smap-regression` target (Makefile only)
  - `c7e5c33` — CLAUDE.md §3 entry (fajar-lang, not kernel)
  - `17a42b0` — this plan doc (fajaros-x86, not kernel)
- Zero kernel source changes → bisect outcome mechanically identical
  to P4's recorded result: silent hang at `println(16)` before
  `frames_init()`, no EXC marker.
- Re-running would consume ~0.1h without new information.

If H3 fix fails boot-test in P3, P0.1 will be retroactively executed
as a sanity check. Current evidence trail is sufficient.

**Estimate savings:** 0.1h (P0.1 skip).

---

## 2. P0.2 — Kernel `.text` Range

Captured via `objdump -h build/fajaros-llvm.elf`:

```
  1 .text         00147297  0000000000101000  ...
  2 .rodata       00012228  0000000000249000  ...
  3 .data         00000008  000000000025c000  ...
  4 .bss          00001008  000000000025d000  ...
```

| Section | Start (virt) | End (virt) | PD entry (2MB huge) |
|---------|---|---|---|
| `.text` | `0x00101000` | `0x00248297` | **PD[0]** (0-2MB) **AND PD[1]** (2-4MB) |
| `.rodata` | `0x00249000` | `0x0025b227` | PD[1] (2-4MB) |
| `.data` | `0x0025c000` | `0x0025c007` | PD[1] |
| `.bss` | `0x0025d000` | `0x0025e007` | PD[1] |

**Critical implication:** kernel `.text` straddles the 2 MB boundary.
`.text` ends at `0x248297 = 2.285 MB`. Any NX-setting function that
starts at PD[1] without special-casing the 2-2.285 MB sub-range will
mark kernel code as non-executable.

Full kernel image fits within PD[0] + PD[1] (0-4 MB). PD[2] onwards
(4 MB+) contains no kernel `.text` / `.rodata` / `.data` / `.bss`.

---

## 3. P0.3 — `nx_enforce_data_pages()` Source

File: `kernel/core/security.fj:221-245`

```fj
@kernel fn nx_enforce_data_pages() {
    // Enable NX in EFER if not already set
    let efer = read_msr(0xC0000080)
    if (efer & (1 << 11)) == 0 {
        write_msr(0xC0000080, efer | (1 << 11))
    }
    // Walk PD entries for first 128MB (identity-mapped region)
    let pml4_entry = page_table_entry(PML4_BASE, 0)
    if (pml4_entry & PAGE_PRESENT) == 0 { return }
    let pdpt_addr = pml4_entry & 0xFFFFF000
    let pdpt_entry = page_table_entry(pdpt_addr, 0)
    if (pdpt_entry & PAGE_PRESENT) == 0 { return }
    let pd_addr = pdpt_entry & 0xFFFFF000
    // PD entries 1-63 (2MB-128MB): set NX on data regions
    // Skip PD[0] (first 2MB contains kernel .text — must stay executable)
    let mut pd_idx: i64 = 1   // ← BUG — should be 2
    while pd_idx < 64 {
        let entry = page_table_entry(pd_addr, pd_idx)
        if (entry & PAGE_PRESENT) != 0 {
            // Set NX bit (bit 63) via byte-level write
            nx_set_bit(pd_addr + pd_idx * 8)
        }
        pd_idx = pd_idx + 1
    }
}
```

**Bug line:** `let mut pd_idx: i64 = 1` (security.fj:236)

**Bug cause:** comment author assumed kernel `.text` fits in the first
2 MB (PD[0] only). At commit time that assumption held. Kernel has
since grown past 2 MB (`.text` now extends to 0x248297 = 2.285 MB,
spilling into PD[1] = 2-4 MB range).

**Effect:** on NX enable:
1. PD[1] is marked NX=1. It covers vaddr 2-4 MB.
2. Kernel `.text` section ending at 2.285 MB has instructions in
   PD[1]'s range.
3. First kernel-mode instruction fetch from the 2-2.285 MB range
   (any symbol beyond `.text + 0xFF000`) triggers #PF with NX reason.
4. IDT page-fault handler code lives in `.text` → handler itself
   also on an NX page → second #PF during handler entry → #DF.
5. #DF handler ALSO on an NX page in `.text` → triple-fault.
6. CPU halts silently (`-no-reboot -no-shutdown`) → observed symptom.

This explains why no EXC:8 / PANIC:8 marker appears — the double-fault
handler itself cannot execute.

---

## 4. P0.4 — NX-Setting Call Sites Inventory

grep for `PAGE_NX | nx_set_bit` across kernel:

### 4.1 Active sites (present in kernel binary)

| Location | Scope | Touches kernel range? |
|----------|-------|---|
| `kernel/core/security.fj:241` (`nx_enforce_data_pages`) | PD[1..63] via `nx_set_bit` | **YES — BUG (H3)** |
| `kernel/mm/paging.fj:210` (`map_page_wx` data branch) | Per-call, passes `PAGE_NX` on new mappings | NO (only called for newly-allocated data frames, never for PD[0-1]) |
| `kernel/mm/paging.fj:247` (`extend_identity_mapping`) | PD[64..127] (128-256 MB data) | NO |
| `kernel/mm/paging.fj:324` (`extend_identity_mapping_512`) | PD[128..511] (256 MB - 1 GB data) | NO |
| `kernel/mm/paging.fj:341` (`extend_identity_mapping_512`) | PD2[0..511] (1-2 GB data) | NO |

### 4.2 Dead code (present but never called)

`protect_kernel_data()` at `kernel/mm/paging.fj:214-231`:
```fj
// .rodata and .data start at 0x108000 (after .text), stack at 0x7F0000
let mut addr: i64 = 0x108000
while addr < 0x200000 {
    ...
    page_table_set(pd_addr, pd_idx, entry | PAGE_NX)
    ...
}
```

Verified via `grep -rn protect_kernel_data kernel/` — only the
definition site appears; no call site. **Dead code, not the bug.**

**Secondary bug note** (non-blocking for V29.P3.P6): the comment
assumes `.rodata` starts at 0x108000, but objdump shows actual start
is 0x249000. First iteration would mark PD[0] as NX — even WORSE
than `nx_enforce_data_pages()`'s PD[1] mistake. Since the function
is dead code, immediate safety is not affected. Track as
`TODO(P3-hygiene, V30+): fix or delete protect_kernel_data()`.

### 4.3 Other mentions (non-NX-setting)

- `kernel/mm/paging.fj:16` — `const PAGE_NX` definition
- `kernel/mm/paging.fj:198-199` — `enable_nx()` / `msr_enable_nx()` (just EFER.NXE toggle, no page-table write)
- `kernel/core/security.fj:213` — `nx_set_bit()` helper (the byte-level writer)
- `kernel/main.fj:178` — V29.P3.P6 TODO comment

---

## 5. P0.5 — Multi-Repo State Check

Run at P6 start (Rule 8):

| Repo | Dirty | Ahead origin |
|------|:-:|:-:|
| Fajar Lang | 0 | 0 |
| fajaros-x86 | 0 | 0 |
| fajarquant | 0 | 0 |

All clean. Safe to proceed with P6 kernel source edits.

---

## 6. Hypothesis Assessment (Plan §1.2)

| ID | Hypothesis | Verdict | Evidence |
|----|-----------|---------|----------|
| **H1** | Kernel `.text` page NX-marked | ✅ **SECONDARY CAUSE** | `.text` in PD[1], which `nx_enforce_data_pages` marks NX. But H1 is a *symptom* of H3's mis-classification, not a distinct root cause. |
| **H2** | `extend_identity_mapping_*` mis-sets NX | ❌ NOT MATCHED | Functions only touch PD[64..511] + PD2[0..511] = all above 128 MB. Kernel `.text` ≤ 4 MB. No overlap. |
| **H3** | `nx_enforce_data_pages()` mis-classifies | ✅ **PRIMARY MATCH** | Loop `pd_idx = 1` includes PD[1] (2-4 MB). Kernel `.text` ends at 2.285 MB, spilling into PD[1]. Fix: loop starts `pd_idx = 2`. |
| **H4** | IDT/GDT/TSS descriptor page NX | ❌ NOT PRIMARY | TSS at 0x7EF000 (per V29.P2 boot log). That's in PD[3] (6-8 MB) — `nx_enforce_data_pages` marks it NX. If TSS or IDT code is fetched, fault. BUT H3 fix (skip PD[1] only) leaves PD[3] still NX-marked — that's correct for TSS as DATA (not executable). IDT handler code however lives in `.text` (PD[0]+PD[1]) — so H3 fix also saves the handler. H4 is thus subsumed by H3. |
| **H5** | Residual (non-listed) | ❌ NOT NEEDED | H3 explains all observed symptoms (silent halt, no EXC marker, post-nx_enforce timing). |

**Conclusion:** H3 unambiguously matched. P1 NX walker unnecessary —
root cause has been identified from static source + symbol-table
inspection alone, analogous to how V29.P3 main track skipped P2
(RIP attribution) when P1 walker output was definitive.

---

## 7. Fix Specification (Input to P2 Decision Gate)

**Single-line change:**

```fj
// kernel/core/security.fj:236
let mut pd_idx: i64 = 1   // BEFORE
let mut pd_idx: i64 = 2   // AFTER
```

**Also update comment on line 234-235:**

```fj
// BEFORE:
// PD entries 1-63 (2MB-128MB): set NX on data regions
// Skip PD[0] (first 2MB contains kernel .text — must stay executable)

// AFTER:
// PD entries 2-63 (4MB-128MB): set NX on data regions. Kernel
// image (.text + .rodata + .data + .bss) spans 0x101000-0x25e007,
// which straddles PD[0] (0-2MB) AND PD[1] (2-4MB). Skip both to
// keep kernel instructions executable. Verified via objdump -h
// build/fajaros-llvm.elf against kernel .text end at 0x248297.
```

**Regression concern:** if kernel `.text` grows past 4 MB (PD[2]
boundary) in the future, this hardcoded `= 2` start will silently
re-introduce the same class of bug. **Long-term fix (V30+):** compute
the first safe PD index dynamically from linker-exported symbols
(e.g., `__kernel_end`) at boot.

For V29.P3.P6 scope: hardcoded `= 2` is acceptable (adds ~1.72 MB
kernel growth room before recurrence). Add an assertion
`assert(kernel_text_end < 4 MB)` during boot that panics with a
clear message if violated. Track the assertion addition in P5 as a
prevention layer.

---

## 8. P0 Gate Decision

All P0.1–P0.5 pre-flight checks satisfied (P0.1 skip justified in §1):

- ✅ Symptom reproduction known (P4 bisect, still valid on HEAD)
- ✅ Kernel `.text` range documented
- ✅ `nx_enforce_data_pages()` bug located (security.fj:236)
- ✅ Other NX-setting sites verified non-culprit
- ✅ Dead code catalogued (`protect_kernel_data` — secondary bug, TODO)
- ✅ Multi-repo state clean

**P1 (NX walker) SKIPPED** — redundant given static analysis already
identified root cause. Walker would report `NX_CODE_VIOLATIONS=N` for
PD[1] post-enforce, which we already know.

**Decision:** proceed directly to P6.P2 (DECISION.md commit) then
P6.P3 (fix), per plan §4 branch B-H3.

---

## 9. Effort Tally (Rule 5)

| Task | Estimate | Actual | Variance |
|------|---------:|-------:|---------:|
| P0.1 bisect rerun | 0.1h | 0h (skipped with rationale) | -100% |
| P0.2 `.text` range | 0.05h | 0.02h | -60% |
| P0.3 `nx_enforce_data_pages` read | 0.05h | 0.03h | -40% |
| P0.4 NX-site inventory | 0.05h | 0.1h (extra: found `protect_kernel_data` dead code) | +100% |
| P0.5 repo check | 0.02h | 0.02h | 0% |
| P0.6 commit this findings doc | 0.1h | 0.1h (pending) | 0% |
| **Phase P0 total** | 0.37h | 0.27h | **-27%** |

Well within surprise budget. The +100% on P0.4 was an unplanned
discovery (dead-code secondary bug) that strengthens the findings —
not a scope creep.

---

## 10. Phase P1 Skip Justification

Plan §4 P1 estimated 0.55h (walker implementation + boot marker +
capture findings). Skip authorized because:

- Root cause is deterministic from source (not empirical from
  running walker)
- Expected walker output (`NX_CODE_VIOLATIONS=N` for PD[1]) is
  already known — running would merely confirm
- Same precedent as V29.P3 main track P2 skip when P1 walker output
  was already definitive
- P5 prevention layer (regression gate) still covers the "future
  NX-on-kernel-text regression" gap without needing boot-time walker

If P3 fix boot-test unexpectedly fails, P1 walker can be built
retroactively as a debug tool. Current confidence: very high.

**Estimate savings:** 0.55h.

---

## 11. Next Phase

**V29.P3.P6.P2 — Decision Gate**

Deliverable: `docs/V29_P3_P6_NX_DECISION.md` recording:
- Matched hypothesis: H3 (per §6 above)
- Chosen fix: single-line change at `security.fj:236` (`1 → 2`)
- Rejected alternatives: 4 (H2 missed, H4 subsumed by H3, H5 not needed, P1 walker redundant)
- Estimated P3 effort: 0.3h (file edit + build + boot-test)
- Estimated P4+P5 effort: 0.75h (regression target rename + doc sync)

---

*V29.P3.P6.P0 Pre-Flight Findings — generated 2026-04-16 by Claude
Opus 4.6. Static-analysis-only phase; no kernel builds or QEMU boots
executed in P0. All evidence derivable from objdump + grep + source
read.*
