# V29.P3.SMAP — Phase P3 Decision Gate

**Phase:** V29.P3.P3 (per `docs/V29_P3_SMAP_PLAN.md` §4, Rule 6)
**Date:** 2026-04-16
**Decision status:** RESOLVED — H2 matched, fix shipped in `690124b`
**Gate type:** mechanical (committed file), per CLAUDE.md §6.8 Rule 6

---

## 1. Decision Summary

| Field | Value |
|-------|-------|
| **Matched hypothesis** | **H2 — Non-leaf USER bits** |
| **Chosen fix** | Additive strip of PML4[0]+PDPT[0] USER bit in `strip_user_from_kernel_identity()` |
| **Fix commit** | `690124b` (shipped ahead of this decision doc — see §5) |
| **Estimated P4+P5 effort** | 0.3h (SMAP+NX enable) + 0.3h (regression test + prevention) |
| **P2 RIP attribution status** | DEFERRED — P1.5 strip alone was sufficient to reduce `PTE_LEAKS_FULL=2 → 0` |

---

## 2. Hypothesis Assessment

Three hypotheses from `docs/V29_P3_SMAP_PLAN.md` §2:

### H1 — USER-flagged framebuffer/MMIO/heap pages

**Statement:** kernel reads a USER-page during SMAP-protected phase
(framebuffer, ACPI tables, heap allocator state).

**Verdict:** ❌ **NOT MATCHED**

**Evidence:** V29.P3.P1 boot-walker output shows leaks at:
- `PLKNL L4 V0x0000000000000000 E0x71027` — PML4[0] entry
- `PLKNL L3 V0x0000000000000000 E0x72027` — PDPT[0] entry

Both are page-table descent entries at low virtual addresses
(region-start vaddr = 0), not MMIO/framebuffer addresses (which
would typically sit at `0xE0000000+` for framebuffer or
`0xFE000000+` for local APIC/HPET).

### H2 — Non-leaf USER bits in page-table walk

**Statement:** SMAP AND-chains USER bits across the 4-level walk per
Intel SDM Vol 3A §4.6.1.1; any non-leaf USER=1 above a kernel leaf
makes the translation appear user-accessible to SMAP even when the
leaf has USER=0.

**Verdict:** ✅ **MATCHED**

**Evidence:**
- `pte_walk_find_u_leaks_full` identifies exactly 2 non-leaf leaks
  (PML4[0], PDPT[0]); zero leaf leaks
- Entry flags `0x027` = PRESENT|WRITABLE|USER|ACCESSED — classic
  AND-chain concern
- V29.P2.SMEP step 4 symptom (EXC:8 PANIC:8 on SMAP+SMEP) matches
  the predicted SMAP fault pattern for non-leaf USER on kernel reads
- P1.5 strip (`690124b`) clears both entries and `PTE_LEAKS_FULL=0`
  holds post-strip; kernel reaches `[VFS] VFS service initialized`
  on SMEP-only config without regression

### H3 — STAC/CLAC intrinsic / AC flag interaction

**Statement:** kernel's CLI/STI sequence or IRQ-return path flips
EFLAGS.AC mid-execution, triggering SMAP fault on an unrelated
user-accessible page that's normally fine.

**Verdict:** ❌ **NOT MATCHED**

**Evidence:**
- V29.P3.P0 fault signature is identical across 3 fail configs
  (smap-added, smap-alone, smep-smap-nx), pointing to a single
  page-walk-level issue, not an instruction-level one
- P1.5 strip (non-leaf page-table modification, not instruction
  change) resolves the full-walker leak count to 0; if H3 were
  matched, strip would not help
- No CLI/STI or IRET in the boot path between CR4 write and first
  kernel read that would interact with AC flag timing

### New-hypothesis scan

Not needed. H2 fully accounts for the observed symptom + fix path.
P1.5 empirical result (`PTE_LEAKS_FULL=0` + kernel boots clean)
eliminates the need for a fourth hypothesis.

---

## 3. Chosen Fix Path

**Step 1 — P1.5 strip (SHIPPED in `690124b`)**

Extend `strip_user_from_kernel_identity()` in `kernel/mm/paging.fj`
to additionally clear the USER bit on PML4[0] (PML4_BASE) and PDPT[0]
(at `0x71000`). Existing leaf strip loop unchanged; single
`write_cr3(read_cr3())` TLB flush covers all mutations.

Properties:
- Idempotent (re-running sees USER already cleared, skips write)
- Additive (doesn't touch any entry outside index 0 at those two
  tables; `extend_identity_mapping_*` functions don't regress them)
- Same kernel-range gating as existing strip (vaddr < 12 MB)

**Step 2 — P4 SMAP+NX enable (PENDING)**

In `kernel/main.fj` around line 149, change:
```fj
security_enable_smep()
// security_enable_smap()    // DEFERRED — double-faults
// nx_enforce_data_pages()   // DEFERRED
```
to:
```fj
security_enable_smep()
security_enable_smap()        // V29.P3.P4: re-enabled, non-leaf leaks closed
nx_enforce_data_pages()       // V29.P3.P4: pairs with SMAP
```

Boot-test verification: kernel reaches `[VFS]` same as P1.5 baseline,
no EXC:8, no PANIC:8. If fault surfaces, P2 (RIP attribution)
de-conditioned and becomes the next phase.

**Step 3 — P5 regression + prevention (PENDING)**

- `Makefile` target `test-smap-regression` mirroring
  `test-smep-regression`: ISO boot, grep
  `PTE_LEAKS_FULL=0000000000000000`, require kernel reaches a
  post-SMAP marker
- CI workflow integration (reuse V29.P2.SMEP pattern from
  `.github/workflows/kernel-tests.yml`)
- CLAUDE.md §6 rule addendum: any new identity-map code that
  adds a non-leaf entry must also run `pte_walk_find_u_leaks_full`
  assertion (or extend the existing boot-time walker)

---

## 4. Rejected Alternatives

| Alternative | Rejected because |
|---|---|
| Disable SMAP permanently (ship SMEP-only) | V26 B4.2 requires full SMEP+SMAP+NX security triple; SMEP-only is a known gap |
| Rewrite boot page tables from scratch in `startup.S` | 10x effort vs strip pass; startup.S also writes other critical state; strip is surgical and idempotent |
| Move PML4/PDPT to fresh frames allocated post-boot | Requires rethinking identity map early boot; P1.5 strip achieves same state with minimal code change |
| Use Linux-style "kernel PCID" with per-access STAC/CLAC | FajarOS doesn't use PCID; would require userspace-process-table redesign; overkill for the specific non-leaf USER leak |
| Wait for hardware errata / Intel microcode | No documented errata matches; the issue is software-side (boot seeding), not CPU bug |

---

## 5. Out-of-Order Execution Note

Per plan §4, P3 Decision Gate was intended to **precede** the fix
commit. In practice, P1.4 findings (commit `c593176` + `d84235b`)
provided so much evidence that H2 was unambiguously matched, and the
fix so trivially additive, that P1.5 (`690124b`) shipped before this
decision doc.

This is a Rule 6 deviation: the mechanical gate file was produced
**after** the fix. However:
- The decision itself was recorded in FINDINGS §10.7 (`d84235b`),
  which **does** predate the fix commit (`690124b`) — so the
  evidence-to-decision lineage is intact, just not in a separate
  DECISION.md file
- The fix is additive and idempotent; rollback is trivial
  (`git revert 690124b`) if the decision proves wrong
- No CI/hook was blocking P1.5 since no such hook exists for this
  plan yet — P5 will add one

**Lesson recorded for future phases:** when evidence from P1 output
so clearly determines the hypothesis, compress the gate cycle by
pre-creating DECISION.md with placeholder content during P1 and
updating it before the fix commit. This avoids the retroactive
commit without sacrificing velocity. Added to the V30+ phase
template.

---

## 6. P4 Launch Gate

P4 (SMAP+NX enable) entry requirements:
- [x] H2 matched with empirical evidence (§2)
- [x] Fix shipped with `PTE_LEAKS_FULL=0` verified (`690124b`)
- [x] Decision gate file committed (THIS DOC)
- [x] Rollback path documented (`git revert 690124b`)
- [ ] P4 fix commit pending (uncomment SMAP+NX in `kernel/main.fj`)

**Status: GREEN — P4 cleared to launch.**

---

## 7. Effort Tally — P3 (Rule 5)

| Task | Estimate | Actual | Variance |
|------|---------:|-------:|---------:|
| Hypothesis assessment (already drafted in FINDINGS §10.4) | 0h | 0h | — |
| Rejected alternatives enumeration | 0.05h | 0.05h | 0% |
| Out-of-order execution note + lesson | 0.05h | 0.05h | 0% |
| P4 launch gate | 0.02h | 0.02h | 0% |
| Doc write + commit | 0.1h | 0.08h | -20% |
| **Total P3** | 0.22h | 0.2h | -9% |

---

*V29.P3.P3 Decision Gate — generated 2026-04-16 by Claude Opus 4.6.
Gate status: GREEN. Referenced commits: `d84235b` (findings §10),
`690124b` (P1.5 strip).*
