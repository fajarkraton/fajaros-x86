# V29.P3.SMAP — Phase P0 Pre-Flight Findings

**Phase:** V29.P3.P0 (per `docs/V29_P3_SMAP_PLAN.md`)
**Date:** 2026-04-16
**Plan reference:** P0.1–P0.6
**Outcome:** Baseline from V29.P2.SMEP step 4 reproduces exactly — safe to proceed to P1 (walker extension) when scheduled.

---

## 1. P0.1 — Bisect Matrix Re-Run

Executed via the new `fajaros-bisect` Claude Code skill
(`~/.claude/skills/fajaros-bisect/`). All 4 V29.P2.SMEP step 4
configurations re-run end-to-end on current kernel source (post-V29.P2
shipped state), with fresh build each time.

### 1.1 Results

| # | Config | Toggle | Verdict | Key log markers | Log file |
|---|--------|--------|---------|-----------------|----------|
| A | sanity-smep-only | none (current source: SMEP on, SMAP+NX commented) | ✅ **PASS** | `PTE_LEAKS=0`, `nova>` | `20260416_183903_sanity-smep-only.log` |
| B | smap-added | uncomment `security_enable_smap()` | ❌ **FAIL** | `PTE_LEAKS=0`, `EXC:8`, `PANIC:8` | `20260416_184150_smap-added.log` |
| C | smap-alone | uncomment SMAP + comment `security_enable_smep()` | ❌ **FAIL** | `PTE_LEAKS=0`, `EXC:8`, `PANIC:8` | `20260416_184625_smap-alone.log` |
| D | smep-smap-nx | uncomment SMAP + `nx_enforce_data_pages()` (SMEP stays on) | ❌ **FAIL** | `PTE_LEAKS=0`, `EXC:8`, `PANIC:8` | `20260416_184359_smep-smap-nx.log` |

### 1.2 Match against V29.P2.SMEP Step 4 table

| Config | V29.P2 expected | V29.P3.P0 observed | Match? |
|--------|----------------|---------------------|--------|
| strip_user + SMEP alone | `nova>` reached, PTE_LEAKS=0 | `nova>` reached, PTE_LEAKS=0 | ✅ |
| strip_user + SMEP + SMAP | EXC:8 → PANIC:8, PTE_LEAKS=0 | EXC:8 + PANIC:8, PTE_LEAKS=0 | ✅ |
| strip_user + SMAP alone | EXC:8 → PANIC:8, PTE_LEAKS=0 | EXC:8 + PANIC:8, PTE_LEAKS=0 | ✅ |
| strip_user + SMEP + SMAP + NX | EXC:8 → PANIC:8, PTE_LEAKS=0 | EXC:8 + PANIC:8, PTE_LEAKS=0 | ✅ |

**4/4 match.** Baseline fault signature is stable across a ~1 day
gap and across a different build host state. No drift.

### 1.3 Key log excerpts

**A (sanity):**
```
PTE_LEAKS=0000000000000000
nova> version
nova>
```

**B, C, D (all three fail configs):**
```
PTE_LEAKS=0000000000000000
EXC:8
PANIC:8
```

All three fault configs emit identical log content (3 lines of
markers, 223 bytes each). PTE_LEAKS=0 still holds across every
config — the walker reports no USER-flagged leaks in the
kernel VM boundary (<0xC00000), yet SMAP/SMAP+NX still faults.
This is the exact V29.P2.SMEP step 4 open question that V29.P3
is scoped to close.

---

## 2. P0.2 — Op Inventory (Walker Current Coverage)

### 2.1 Current walker scope

File: `kernel/core/mm_advanced.fj` — `pte_walk_find_u_leaks`
Reports: USER bit **at leaf PTE only** (checks `PAGE_USER` flag on
final translation entry). Descends through PML4 → PDPT → PD → PT
without examining USER bit at non-leaf levels.

### 2.2 Gap

Three levels above leaf (PML4, PDPT, PD) are **never audited**.
V29.P3 Plan Phase P1 extends walker to report all 4 levels.

### 2.3 Call site

Called from boot (auto-invoked, V29.P2.SMEP step 2) and from
`cmd_pte_audit` shell command (V29.P2.SMEP step 3). Both paths
will benefit from P1 extension automatically — no additional
wiring needed.

---

## 3. P0.3 — Repo State Check

All 3 repos clean, 0 unpushed at start of P0 (2026-04-16 18:37):

| Repo | Branch | Unpushed | Status |
|------|--------|----------|--------|
| Fajar Lang | main | 0 | clean |
| fajaros-x86 | main | 0 | clean |
| fajarquant | main | 0 | clean |

Note: P0.1 bisect runs left `kernel/main.fj` modified during each
config, but the skill's `trap EXIT` restore preserved the clean
state across all 4 runs. Verified post-P0.1.

---

## 4. P0 Byproducts — Skill Maturation

Running the V29.P2 bisect matrix on real hardware surfaced two real
bugs in the newly-built `fajaros-bisect` skill + prompted one
feature extension. All three were fixed within P0 scope:

1. **Bug:** sed uncomment command used `|` as delimiter, conflicting
   with regex alternation in toggle patterns (e.g.,
   `(smap\(\)|nx\(\))`). Fix: switched to `#` delimiter.

2. **Bug:** sed comment command used empty-pattern `s//\1// \2/` with
   intent to re-match outer address groups, but sed's "last regex"
   was the inner not-commented guard `/^[[:space:]]*\/\//`, which has
   0 groups. Fix: explicit pattern in `s` + `\#...#` address
   delimiter for consistency.

3. **Feature:** added `--also-comment <regex>` flag for bidirectional
   toggles. Required for `smap-alone` config (comment SMEP +
   uncomment SMAP in one invocation). All 4 matrix configs now
   supported by a single skill invocation.

The skill is now battle-tested across 4 real configs. Git status
confirmed clean between every bisect run.

---

## 5. Typo in V29.P3 Plan Doc (Non-Blocking, to Fix)

`docs/V29_P3_SMAP_PLAN.md` §2.1 Scope row references:
> `kernel/core/main.fj` | Uncomment `security_enable_smap()`

The actual path is `kernel/main.fj` (no `core/` subdir). Related
references in §1.1 ("`kernel/core/security.fj:60`") are correct —
that file exists at `kernel/core/security.fj` for `write_cr4`.
Only the `main.fj` path is wrong.

Amend before P4. No blocker for P1–P3.

---

## 6. P0 Gate Decision

All P0.1–P0.3 pre-flight checks pass:

- ✅ Baseline bisect matrix reproduces V29.P2 exactly (4/4)
- ✅ PTE_LEAKS=0 invariant holds across every config (confirming
  V29.P2 leak-closure still active post-rebase)
- ✅ Op inventory done (walker = leaf-only, P1 extends)
- ✅ Repo state clean + restored across runs
- ✅ Skill matured + ready for P1+ automation

**Decision:** proceed to V29.P3.P1 (walker full 4-level coverage)
on next scheduled phase. No scope change needed; plan holds.

---

## 7. Effort Tally (Rule 5 Surprise Budget)

| Task | Estimate | Actual | Variance |
|------|---------:|-------:|---------:|
| P0.1 bisect matrix (4 configs) | 0.2h | 0.25h | +25% |
| P0.2 walker inventory | 0.3h | 0.1h | -67% (already grep'd in §4.2 of plan) |
| P0.3 repo state | 0.05h | 0.02h | -60% |
| P0.4 walker coverage check | 0.05h | 0.02h | -60% |
| P0.5 multi-repo sanity | 0.02h | 0.02h | 0% |
| P0.6 commit findings + plan | 0.1h | 0.1h | 0% (pending) |
| **Skill bug fix + feature (unplanned)** | 0.0h | 0.25h | +∞ (surfaced during P0.1) |
| **Total** | 0.72h | 0.76h | +6% |

Within +25% surprise budget; no escalation needed. The +0.25h for
skill work was unplanned but immediately productive — future P1
and V29.P3 phases reuse the matured skill without rediscovering the
same bugs.

---

## 8. Phase P0 Deliverables Checklist

```
[x] P0.1 Re-run bisect matrix (4 configs, logs captured)
[x] P0.2 Walker coverage inventory documented
[x] P0.3 Multi-repo state check
[x] P0.4 Walker leaf-only confirmation
[x] P0.5 Baseline fault signature match confirmed (§1.2)
[ ] P0.6 This findings doc committed (pending at time of write)
```

P0 deliverable: this document. Upon commit, P0 gate is fully
closed. P1 ready to launch.

---

## 9. Next Phase Entry Gate

V29.P3.P1 entry requirements (per plan §4 Phase P1):

- [x] P0.1 findings match V29.P2 baseline — satisfied above
- [x] P0 findings doc committed — pending this commit
- [ ] P1 planning prerequisites (nothing blocking)

Green for P1 launch when next scheduled.

---

*V29.P3.P0 Pre-Flight Findings — generated 2026-04-16 by
Claude Opus 4.6 via the `fajaros-bisect` skill. All 4 bisect logs
live at `build/bisect-logs/20260416_*` for future cross-referencing.*

---

## 10. V29.P3.P1 — Walker Extension + Non-Leaf Leak Discovery

**Phase:** V29.P3.P1 (per `docs/V29_P3_SMAP_PLAN.md` §4)
**Date:** 2026-04-16 (same session as P0)
**Commits:** `a521d4c` (P1.1 walker), `c593176` (P1.3 wire + boot invoke)
**Outcome:** **Hypothesis H2 confirmed.** Two non-leaf PAGE_USER leaks
identified with presisi — PML4[0] and PDPT[0] both have USER=1.
Leaf-only walker was blind to both; `strip_user_from_kernel_identity()`
in V29.P2 only touches 2MB huge leaves at PD[0..5].

### 10.1 Walker implementation (P1.1 → commit `a521d4c`)

Added to `kernel/mm/pte_audit.fj`:
- `pte_report_leak_nonleaf(vaddr, entry, level)` — emits `PLKNL L<d> V<hex16> E<hex16>`
  with distinct prefix from leaf `PLK` so bisect-log grep can separate.
- `pte_check_nonleaf(vaddr, entry, level) -> i64` — same kernel-range
  gating as `pte_check_leaf` (report only when region-start < 12 MB).
- `pte_walk_find_u_leaks_full() -> i64` — full 4-level walk, calls
  nonleaf checker at PML4, PDPT-non-huge, PD-non-huge descent points
  plus leaf checker at all terminals. Returns combined count.

Level coding:
| Marker | Prefix | Level | What |
|--------|--------|------:|------|
| `PLKNL L4` | non-leaf | 4 | PML4 entry with USER=1 covering kernel |
| `PLKNL L3` | non-leaf | 3 | PDPT non-huge entry with USER=1 |
| `PLKNL L2` | non-leaf | 2 | PD non-huge entry with USER=1 |
| `PLK L1`   | leaf     | 1 | PT 4KB leaf with USER=1 |
| `PLK L2`   | leaf     | 2 | PD 2MB-huge leaf with USER=1 |
| `PLK L3`   | leaf     | 3 | PDPT 1GB-huge leaf with USER=1 |

### 10.2 Boot-marker wiring (P1.3 → commit `c593176`)

Added in `kernel/main.fj` right after existing `PTE_LEAKS=` block:
- Call `pte_walk_find_u_leaks_full()` on every boot
- Emit `PTE_LEAKS_FULL=<hex16>\n` byte-by-byte to COM1 (same hex16 helper)

Also extended `cmd_pte_audit` shell command with "All-level PAGE_USER
leaks (4-level walk)" line alongside the leaf count.

### 10.3 Empirical result

Boot on `qemu-system-x86_64 -cdrom build/fajaros-llvm.iso -cpu Skylake-Client-v4`:

```
PTE_LEAKS=0000000000000000                    ← Leaf walk clean (V29.P2 baseline intact)
PTE_LEAKS_FULL=0000000000000002               ← Full walk: 2 non-leaf leaks
PLKNL L4 V0000000000000000 E0000000000071027  ← PML4[0]
PLKNL L3 V0000000000000000 E0000000000072027  ← PDPT[0]
```

**Entry flag decode** (`E=0x027`):
- Bit 0 (PRESENT) = 1
- Bit 1 (WRITABLE) = 1
- **Bit 2 (USER) = 1** ← the leak
- Bit 5 (ACCESSED) = 1
- Upper bits = page-table base address (PDPT@`0x71000`, PD@`0x72000`)

### 10.4 Hypothesis assessment (Decision Gate input)

| Hypothesis | V29.P3 Plan §2 statement | Verdict | Evidence |
|---|---|---|---|
| **H1** — USER-flagged framebuffer/MMIO/heap pages | Kernel reads USER-page during SMAP-protected phase | ❌ NOT MATCHED | Leaks at PML4[0]/PDPT[0] are page-table descent entries, not MMIO address range |
| **H2** — Non-leaf USER bits in page-table walk | SMAP AND-chains USER across walk; any non-leaf USER=1 causes fault | ✅ **MATCHED** | Two intermediate leaks identified with exact virt+flag bytes |
| **H3** — STAC/CLAC intrinsic / AC flag interaction | Kernel CLI/STI or IRQ return flips AC mid-execution | ❌ NOT MATCHED | No instruction-level fault pattern; page-walk level issue |

**Why H2 fits the V29.P2 step 4 symptom:**
- SMEP-only config PASSES — SMEP check is leaf-only for ring-0 instruction fetch (Intel SDM Vol 3A §4.6.2)
- SMAP-enabled configs FAIL — SMAP check AND-chains USER bits across the entire page-table walk (Intel SDM §4.6.1.1)
- `PML4[0].U=1 ∧ PDPT[0].U=1` means the walk below them is "user-accessible" for SMAP purposes regardless of whether the leaf PTEs have USER=0
- First kernel access after SMAP enable → double-fault on supervisor data read of user-walkable mapping → EXC:8 PANIC:8 (exactly what V29.P2 step 4 bisect recorded)

### 10.5 P1.5 fix target (precise)

Extend `strip_user_from_kernel_identity()` in `kernel/mm/paging.fj` to
additionally clear the USER bit (bit 2) on:
- `PML4[0]` entry at PML4_BASE+0 (currently `0x71027` → `0x71023`)
- `PDPT[0]` entry at `0x71000+0` (currently `0x72027` → `0x72023`)

Success gate: next boot reports `PTE_LEAKS_FULL=0000000000000000`.
Regression safety: V29.P2.SMEP PTE_LEAKS=0 must still hold (leaf strip
pass unchanged, additive non-leaf strip only).

### 10.6 Effort tally (Phase P1 addendum to §7)

| Task | Estimate | Actual | Variance | Commit |
|------|---------:|-------:|---------:|--------|
| P1.1 Walker function (full 4-level) | 0.3h | 0.25h | -17% | `a521d4c` |
| P1.2 4 separate counters | 0.1h | 0h (DEFERRED) | — | — |
| P1.3 Wire shell + boot invoke | 0.1h | 0.2h (bundles de-facto P1.4) | +100% (de-facto P1.4 inline) | `c593176` |
| P1.4 Level-by-level leak table | 0.15h | 0h (closed inline by P1.3 output) | — | `c593176` §10.3–10.4 |
| P1.5 Strip non-leaf USER | 0.25h | ⏳ PENDING | — | — |
| P1 findings doc update | — | 0.15h | unplanned | THIS UPDATE |
| **P1 running total** | 0.9h | 0.6h so far | -33% | — |

Within +25% surprise budget. P1.2 intentionally deferred — the
aggregate `PTE_LEAKS_FULL` counter plus raw `PLKNL` per-entry lines
proved sufficient for H2 confirmation without separate per-level
aggregates. If P1.5 strip reveals counting complexity, P1.2 can be
revived.

### 10.7 P3 Decision Gate preview

Per plan §4 Phase V29.P3.P3, the Decision Gate committed file
`docs/V29_P3_SMAP_DECISION.md` will record (after P2 RIP attribution):
- Matched hypothesis: **H2**
- Chosen fix: P1.5 strip of PML4[0]+PDPT[0] USER bit (additive to existing `strip_user_from_kernel_identity`)
- Rejected: H1 (no MMIO evidence), H3 (no instruction-level fault), new-hypothesis scan (unnecessary)
- Estimated effort for P3 fix + validation: 0.5h

**P2 (RIP attribution) may no longer be strictly necessary** if P1.5
strip is sufficient to clear the fault — the leak discovery already
gives the fix target without needing double-fault RIP symbolization.
P2 becomes a confirmation path: if P1.5 boot with SMAP enabled still
faults, then P2 attribution identifies the *second* leak source.
Keep P2 in plan but flag as conditional-on-P1.5-residual-fail.

---

*V29.P3.P1 addendum — generated 2026-04-16 by Claude Opus 4.6.
Non-leaf walker commits: `a521d4c`, `c593176`.*
