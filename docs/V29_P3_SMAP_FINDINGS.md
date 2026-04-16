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
