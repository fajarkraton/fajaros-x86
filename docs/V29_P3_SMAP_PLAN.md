# V29.P3.SMAP — Characterize & Close SMAP Double-Fault (+ Re-enable NX)

**Phase:** V29.P3 "SMAP + NX Closure" (follow-up to V29.P2.SMEP)
**Parent:** V29 "Hardening" (FajarOS P2 + prerequisite compiler fixes)
**Status:** PLAN (2026-04-16) — execution pending user go-ahead per sub-phase
**Plan Hygiene:** satisfies Rules 1–8 (see §11 self-check at end)
**Signed by:** Muhamad Fajar Putranto
**Signed at:** 2026-04-16

---

## 1. Problem Statement

V29.P2.SMEP step 4 shipped SMEP enabled, PTE_LEAKS=0 invariant, walker
permanent. **SMAP and NX were deferred** because uncommenting
`security_enable_smap()` in `kernel/main.fj` triggers an immediate
double fault (EXC:8 → PANIC:8) the moment `write_cr4(cr4 | CR4_SMAP)`
executes at `kernel/core/security.fj:60`.

### 1.1 Established facts (V29.P2.SMEP step 4 bisect)

| Config | Boot `nova>`? | PTE_LEAKS | Notes |
|---|---|---|---|
| strip_user + SMEP alone | ✅ YES | 0x0 | shipped state |
| strip_user + SMEP + SMAP | ❌ EXC:8 | 0x0 | fault at `write_cr4 \| SMAP` |
| strip_user + SMAP alone | ❌ EXC:8 | 0x0 | SMAP is independent trigger |
| strip_user + SMEP + SMAP + NX | ❌ EXC:8 | 0x0 | not NX-specific |

Source: `docs/V29_P2_SMEP_STEP4_BISECT.md`

### 1.2 Three hypotheses (from bisect doc §Interpretation)

| # | Hypothesis | Why plausible | Test |
|---|---|---|---|
| H1 | Kernel reads USER-flagged memory in 12–128 MB range post-SMAP (framebuffer @ ~0xE0000000, MMIO, process-table) | Walker only reports leaks < 0xC00000. Anything ≥ that with USER=1 bypasses walker but triggers SMAP | Extend walker to full 4-level range; check framebuffer/MMIO PTEs |
| H2 | Walker's USER predicate only checks leaf PTE; intermediate PDPT/PML4 USER bits affect SMAP semantics on Intel micro-arches | Current `pte_walk_find_u_leaks` descends through non-leaf levels without checking their USER bits | Report USER bits at all 4 levels, not just leaf |
| H3 | EFLAGS.AC interaction: SMAP=1 + AC=0 means every USER-page access faults; boot sequence post-SMAP touches USER-flagged memory unexpectedly | Fajar Lang lacks STAC/CLAC intrinsic; CR4-toggle is interim — but AC=0 with SMAP=1 is the whole-kernel default | RIP-log the double fault; find which instruction faulted |

**Most likely:** H1 or H2 (architectural). H3 is a symptom of H1/H2, not a
root cause — if SMAP is working as intended, AC=0 is fine until the kernel
actually needs to cross a USER boundary.

### 1.3 Scope of closure

This plan characterizes the fault via instrumentation (walker +
double-fault RIP logger), identifies root cause, patches it, and
re-enables **both SMAP and NX** together (they share the same
pre-gate state per V29.P2 bisect table).

### 1.4 Prevention Layer Gap (Rule 3)

V29.P2 left SMAP+NX disabled with a comment in `main.fj`. There is no
CI gate that verifies SMAP is active after re-enable, no regression
test that would catch future regressions (e.g., future kernel code
re-introducing a USER-flagged read). This plan adds both.

---

## 2. Scope (Cross-Repo)

### 2.1 FajarOS x86 (primary)
| File | Change |
|------|--------|
| `kernel/core/mm_advanced.fj` (walker) | Extend `pte_walk_find_u_leaks` to report PDPT + PML4 USER bits in addition to leaf PTE. New leak counter: `PTE_LEAKS_INTERMEDIATE` |
| `kernel/core/irq.fj` (or double-fault handler site) | Add `record_double_fault_rip(rip: u64)` — capture faulting RIP into a well-known buffer, print at panic |
| `kernel/core/security.fj:51-66` | Add `security_enable_smap_with_bisect()` helper that logs `pre-write_cr4` marker + reads back CR4 + confirms set before proceeding |
| `kernel/main.fj` | Uncomment `security_enable_smap()` + `nx_enforce_data_pages()` after root-cause fix ships |
| `kernel/shell/commands.fj` (`cmd_pte_audit`) | Also surface intermediate-level leak count |
| `tests/kernel/test_smap_regression.fj` (new) | Boot-time assertion: CR4.SMAP=1, CR4.NX=1, boot reaches `nova>` |
| `Makefile` | New target `test-smap-regression` paralleling `test-smep-regression` |
| `scripts/git-hooks/pre-commit` (check 6/6) | Reject commits that disable SMAP/NX without a matching decision doc |
| `docs/V29_P3_SMAP_FINDINGS.md` (P0 output) | Pre-flight audit results: re-run V29.P2.SMEP step 4 bisect, confirm results still hold |
| `docs/V29_P3_SMAP_DECISION.md` (P3 gate) | Root cause + chosen fix path, committed before P4 |
| `docs/V29_P3_CLOSED.md` (P5 output) | Final rollup (SMAP+NX active, regression test green, walker extended) |
| `CHANGELOG.md` | v3.5.0 "Hardening" entry |

### 2.2 Fajar Lang
| File | Change |
|------|--------|
| — | **Conditional:** if root cause is H3 (AC flag interaction), add STAC/CLAC intrinsic (`__builtin_stac`, `__builtin_clac`) to lexer+codegen. Drop to Fajar Lang scope if needed; otherwise zero changes. |

### 2.3 FajarQuant
No direct changes. Kernel-port shim does not touch CR4.

### 2.4 Documentation (memory/claude-context)
| File | Change |
|------|--------|
| `~/.claude/projects/.../memory/MEMORY.md` | Update "SMEP enabled (P2 TODO, U-bit leak)" line → "SMEP+SMAP+NX enabled (V29.P3 closed)" |
| `memory/project_v26_phase_b_progress.md` | Same update on FajarOS status line |
| `Fajar Lang/CLAUDE.md` §3 Version History | Add V29.P3 row |

---

## 3. Skills & Knowledge Required

| Area | Depth | Reference |
|------|-------|-----------|
| **x86_64 paging semantics** | Deep — 4-level walk, USER bit at each level, SMAP enforcement rules | Intel SDM Vol 3A §4.6 (Access Rights) + §4.6.1.1 (SMAP) |
| **SMAP micro-arch behavior** | Medium — when SMAP checks leaf vs. intermediate USER bits; Linux's reference sequence | `arch/x86/kernel/cpu/common.c` in Linux (setup_smap path) |
| **Double-fault handler layout** | Medium — IDT entry 8, IST stack, error code format, RIP save location | Intel SDM Vol 3A §6.15 (Exception and Interrupt Reference) |
| **FajarOS PTE walker** | Medium — `kernel/core/mm_advanced.fj`, leaf vs intermediate descent | V29.P2 walker code |
| **Fajar Lang inline asm** | Medium — `asm!` block, register constraints, `volatile` | `src/parser/asm.rs`, prior uses in kernel |
| **CR4 bit semantics** | Light — CR4.20 (SMEP), CR4.21 (SMAP), EFER.NXE (not CR4) | Intel SDM Vol 3A §2.5 |
| **Intel CPU errata on i9-14900HX** | Light | Intel Core Ultra errata sheets (CPU-specific workarounds) |
| **QEMU -cpu host SMAP passthrough** | Light — KVM SMAP emulation vs native | QEMU docs + KVM kernel module |

**Skill gaps flagged:** SMAP micro-arch behavior on non-leaf USER bits is
under-documented. **Online research required** (per CLAUDE.md §6.9 Rule 2):
minimum 4 references from Intel SDM + Linux kernel + any published
blog/paper on SMAP debugging.

---

## 4. Phased Approach

### Phase V29.P3.P0 — Pre-Flight Audit

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P0.1 | Re-run V29.P2.SMEP step 4 bisect (SMEP only; +SMAP; SMAP alone; +NX) | 4 QEMU boot logs captured to `build/bisect-logs/` | 0.2h |
| P0.2 | Confirm PTE_LEAKS=0 still holds on every config | `grep 'PTE_LEAKS=' build/bisect-logs/*.log` → all `=0000000000000000` | 0.05h |
| P0.3 | Confirm fault signature matches prior: `EXC:8` + `PANIC:8` + no post-SMAP marker | `grep -E 'EXC:8\|PANIC:8\|post-SMAP' build/bisect-logs/+smap.log` → 2 matches, no post-marker | 0.05h |
| P0.4 | Verify walker current coverage (leaf only) | `grep -A10 'pte_walk_find_u_leaks' kernel/core/mm_advanced.fj \| grep -c 'PAGE_USER'` → 1 (single check at leaf level) | 0.05h |
| P0.5 | Multi-repo state check | `git status -sb` across 3 repos = all clean; `git rev-list origin/main..main` = 0 | 0.02h |
| P0.6 | Commit `docs/V29_P3_SMAP_FINDINGS.md` with P0 results | `git log --oneline -1 docs/V29_P3_SMAP_FINDINGS.md` exists | 0.1h |

**Phase P0 total: 0.5h**
**Deliverable:** This plan doc + findings commit confirming baseline
**Gate:** PTE_LEAKS=0 still holds; fault signature matches prior bisect

### Phase V29.P3.P1 — Walker Extension (Full 4-Level Coverage)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P1.1 | Add `pte_walk_find_u_leaks_full` that walks PML4→PDPT→PD→PT and reports USER bit per level | new fn exists; `cargo build --release` in Fajar Lang + `make build-llvm` in FajarOS succeed | 0.3h |
| P1.2 | Emit 4 separate leak counters: `PML4_U_LEAKS`, `PDPT_U_LEAKS`, `PD_U_LEAKS`, `PT_U_LEAKS` (leaf = existing) | boot log contains all 4 lines with hex values | 0.1h |
| P1.3 | Extend `cmd_pte_audit` shell command to print all 4 | `printf 'pteaudit\r' \| qemu ...` log contains all 4 counters | 0.1h |
| P1.4 | Run walker on shipped (SMEP-only) kernel: document which levels show leaks | `docs/V29_P3_SMAP_FINDINGS.md` updated with level-by-level leak table | 0.15h |
| P1.5 | If non-leaf USER leaks found → strip them (analogous to V29.P2.SMEP.3 strip) | `PML4/PDPT/PD_U_LEAKS` all 0x0 on boot | 0.25h |

**Phase P1 total: 0.9h** (+25% budget: 1.1h)
**Deliverable:** Walker reports USER bits at all 4 levels; any non-leaf leaks stripped
**Gate:** All 4 leak counters = 0x0 in shipped config (SMEP only, no SMAP yet)

### Phase V29.P3.P2 — Double-Fault RIP Attribution

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P2.1 | Extend double-fault handler (IDT entry 8) to capture faulting RIP from stack frame + CR2 + error code | `objdump -d build/fajaros-llvm.elf \| grep -A5 double_fault_handler \| grep -c 'mov.*rip'` ≥ 1 | 0.3h |
| P2.2 | Emit panic payload: `PANIC:8 RIP=0x<hex> CR2=0x<hex> ERR=0x<hex>` | boot with SMAP enabled → log shows annotated RIP | 0.15h |
| P2.3 | Re-run "+SMAP" bisect config with new handler | log captured to `build/bisect-logs/smap-rip.log` | 0.1h |
| P2.4 | Symbolize faulting RIP via `addr2line` against ELF | `addr2line -e build/fajaros-llvm.elf <rip>` → source:line | 0.1h |
| P2.5 | Document faulting instruction + surrounding context in findings doc | `docs/V29_P3_SMAP_FINDINGS.md` updated with RIP + symbolized location + 10-line context | 0.15h |

**Phase P2 total: 0.8h** (+25% budget: 1.0h)
**Deliverable:** Exact instruction that faults post-SMAP identified
**Gate:** RIP symbolized to a named kernel function + source line

### Phase V29.P3.P3 — Root Cause Analysis + Fix (Decision Gate)

**Decision gate (Rule 6):** before P3 patches, commit
`docs/V29_P3_SMAP_DECISION.md` recording:
- Which hypothesis (H1 / H2 / H3 / new) matched P2 evidence
- Chosen fix path + estimated effort
- Rejected alternatives with rationale

Fix branches by hypothesis:

**If H1 (kernel reads USER-flagged framebuffer/MMIO/etc):**
| Task | Verification | Est |
|---|---|---|
| Identify the USER-flagged region (framebuffer, process table, or other) | walker P1 output + RIP from P2 | 0.1h |
| Strip USER bit from that region's PTEs at boot | boot log: region's walker counter → 0x0 | 0.3h |

**If H2 (non-leaf USER bits matter for SMAP):**
| Task | Verification | Est |
|---|---|---|
| Strip USER from PDPT/PML4 entries 0–5 (kernel range) | P1.5 delivered this; verify | 0.0h (covered) |
| If P1.5 did not fix SMAP: dig into Intel SDM for micro-arch note on non-leaf behavior | written note in DECISION doc | 0.3h |

**If H3 (AC flag / STAC-CLAC):**
| Task | Verification | Est |
|---|---|---|
| Fajar Lang: add `__builtin_stac`, `__builtin_clac` intrinsics | `cargo test --lib codegen::intrinsic` pass | 1.5h |
| Replace CR4-toggle in `smap_disable/smap_enable` with STAC/CLAC | kernel rebuilds; boot test passes | 0.3h |
| **Surprise budget escalation:** if H3 is the answer, Phase P3 bumps +40% | — | — |

**Phase P3 base range: 0.3h (H2) → 2.0h (H3)** (+25%: 0.4h–2.5h)
**Deliverable:** Root cause fixed; `+SMAP` boot reaches `nova>`
**Gate:** DECISION file committed before any code change; SMAP boot green

### Phase V29.P3.P4 — Enable SMAP + NX, Regression Suite

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P4.1 | Uncomment `security_enable_smap()` in `kernel/main.fj` | diff shows uncommenting only | 0.02h |
| P4.2 | Uncomment `nx_enforce_data_pages()` | same | 0.02h |
| P4.3 | `make clean && make iso-llvm` | `ls -la build/fajaros-llvm.iso` — file exists | 0.1h |
| P4.4 | Boot test: reach `nova>`, run `version`, confirm no EXC | `grep -E 'nova>\|EXC:' /tmp/smap-enabled.log` → `nova>` matches ≥ 1, `EXC:` matches = 0 | 0.1h |
| P4.5 | Read back CR4 + EFER in shell: `pteaudit` or new `cpustate` command shows CR4.SMEP=1, CR4.SMAP=1, EFER.NXE=1 | shell output contains all 3 bits ENABLED | 0.2h |
| P4.6 | Run existing V29.P2 SMEP regression test — verify no regression | `make test-smep-regression` exit 0 | 0.1h |
| P4.7 | Run full kernel test suite (35 tests per V29.P2) | `make test-kernel` → 35/35 pass, +1 new test | 0.15h |

**Phase P4 total: 0.7h** (+25% budget: 0.9h)
**Deliverable:** SMAP + NX active; all prior tests still green
**Gate:** CR4.SMAP=1 and EFER.NXE=1 both verified at runtime

### Phase V29.P3.P5 — Regression Test + Prevention Layers

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P5.1 | Write `tests/kernel/test_smap_nx_regression.fj` — assert CR4.SMAP=1, EFER.NXE=1, walker leaks all 0x0, boot reaches `nova>` | test file exists; `@test` fn declared | 0.2h |
| P5.2 | Add Makefile target `test-smap-regression` paralleling `test-smep-regression` | `grep -c 'test-smap-regression' Makefile` ≥ 1; target runnable | 0.15h |
| P5.3 | Extend pre-commit check (now check 6/6) to reject SMAP/NX disable without matching decision doc | temp-disable SMAP → `git commit` → blocked at check 6 | 0.2h |
| P5.4 | Commit `docs/V29_P3_CLOSED.md` rollup | file committed; links V29.P2 + V29.P3 findings | 0.15h |
| P5.5 | Update MEMORY.md status line ("SMEP+SMAP+NX enabled V29.P3") | memory diff review | 0.05h |
| P5.6 | Update `Fajar Lang/CLAUDE.md` §3 Version History with V29.P3 entry | CLAUDE.md diff review | 0.1h |
| P5.7 | Update FajarOS CHANGELOG.md [3.5.0] section with V29.P3 narrative | CHANGELOG diff review | 0.1h |
| P5.8 | GitHub Release v3.5.0 "Hardening" | `gh release view v3.5.0` succeeds | 0.1h |

**Phase P5 total: 1.05h** (+25% budget: 1.3h)
**Deliverable:** Regression test + prevention layer + full artifact sync
**Gate:** All 8 Plan Hygiene rules still YES; release live

---

## 5. Effort Summary

| Phase | Tasks | Base | +25% buffer |
|-------|------:|-----:|-----------:|
| P0 Pre-flight | 6 | 0.5h | 0.6h |
| P1 Walker extension | 5 | 0.9h | 1.1h |
| P2 RIP attribution | 5 | 0.8h | 1.0h |
| P3 Root cause + fix (H2 branch) | 2 | 0.3h | 0.4h |
| P3 Root cause + fix (H3 branch) | 3 | 2.0h | 2.8h (+40%) |
| P4 Enable SMAP+NX | 7 | 0.7h | 0.9h |
| P5 Regression + prevention | 8 | 1.05h | 1.3h |
| **TOTAL (H2 branch)** | **33** | **4.25h** | **5.3h** |
| **TOTAL (H3 branch)** | **34** | **5.95h** | **7.7h** |

**High-variance phases:** P3 (hypothesis-dependent, range 0.3h–2.0h base).
P2 RIP work also carries risk if double-fault handler doesn't preserve
enough state (may need IST stack rework).

**Effort envelope:** 4-8h per V30 agenda estimate — matches this plan
(5.3h H2 / 7.7h H3).

---

## 6. Surprise Budget Tracking (Rule 5)

Per CLAUDE.md §6.8 Rule 5, every commit tags variance:

```
feat(v29-p3-p1.1): extend walker to all 4 paging levels
  [actual 0.4h, est 0.3h, +33%]

fix(v29-p3-p3.H3): STAC/CLAC intrinsic in Fajar Lang codegen
  [actual 2.2h, est 1.5h, +47%]
```

Surprise budget starts at +25%. **If P0 findings show the fault
signature changed from V29.P2**, auto-escalate to +40% for the entire
phase (indicates unstable substrate, not just a single-task surprise).

Phase P3 H3-branch defaults to +40% (Fajar Lang compiler touch is
inherently higher variance than kernel C-equivalent work).

---

## 7. Prevention Layers (Rule 3)

Each phase installs at least one durable prevention mechanism:

| Phase | Prevention mechanism |
|-------|----------------------|
| P1 | Walker covers all 4 paging levels permanently; future kernel code that creates intermediate USER bits will trip walker on next boot |
| P2 | Double-fault handler preserves RIP — every future kernel crash gives attribution data for free (not just for this plan) |
| P4 | CR4 readback in `cpustate` shell command — SMAP/SMEP/NX status always visible without kernel rebuild |
| P5 | `test-smap-regression` Makefile target + pre-commit check 6/6 — SMAP/NX cannot be silently disabled |
| P5 | `V29_P3_CLOSED.md` documents decision chain (hypothesis → evidence → fix) — future readers reproduce reasoning, not just outcome |

---

## 8. Gates & Decisions (Rule 6)

| Gate | Before Phase | File |
|------|--------------|------|
| Pre-flight findings confirmed | P1 | `docs/V29_P3_SMAP_FINDINGS.md` (P0.6) |
| Root cause identified | P3 patches | `docs/V29_P3_SMAP_DECISION.md` (P3 entry) |
| SMAP+NX active | P5 | P4.5 runtime readback logged |
| Phase closure | handoff | `docs/V29_P3_CLOSED.md` (P5.4) |

Pre-commit hook check 6/6 blocks any commit touching
`kernel/main.fj` that disables SMAP/NX without a matching
`V29_P*_DECISION.md` file in the same commit.

---

## 9. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| H3 (STAC/CLAC needed) → Fajar Lang compiler touch | Low-Med | High | P3 decision doc forces explicit cost-benefit before code; +40% budget baked in |
| Walker extension breaks SMEP-only baseline | Low | High | P1.5 baseline test + P4.6 regression suite catch this; revert walker if regression |
| Double-fault handler needs IST stack (extra allocation) | Medium | Medium | P2.1 first validates current IDT entry 8 config; IST rework scoped as P2 sub-task if needed |
| RIP capture works but symbol unrelated (e.g., in LLVM compiler-generated code, not source) | Medium | Medium | P2.4 addr2line + P2.5 ±10 line context covers compiler-emitted ranges |
| KVM `-cpu host` passthrough has Intel Core Ultra errata affecting SMAP | Low | High | P0 online research (Intel errata sheets); fallback: `-cpu Haswell` reference CPU for testing |
| Fix reveals deeper second bug (H1 AND H2 true) | Low | Medium | P3 DECISION doc captures all evidence; loop back to P2 if first fix doesn't clear |
| P4 regression: SMEP regression test breaks after SMAP enable | Very Low | High | P4.6 is explicit regression gate; revert P4 if broken, fix forward in P3 |
| 35→36 test count drift from CLAUDE.md numbers | Very Low | Low | P5.1 updates kernel test count; CLAUDE.md §3 synced in P5.6 |

---

## 10. Online Research Triggers (per CLAUDE.md §6.9 Rule 2)

Research required at Phase P0.5 or early P2:

1. **Intel SDM Vol 3A §4.6 + §4.6.1.1** — SMAP exact semantics: does it
   check intermediate-level USER bits, or leaf only? Authoritative answer.
2. **Intel SDM Vol 3A §6.15** — Double-fault handler state layout; what's
   on the stack at IDT entry 8 handler entry (for P2).
3. **Linux kernel `arch/x86/kernel/cpu/common.c`** (setup_smap path) —
   reference SMAP enable sequence; order of operations around MSR writes,
   CR4 bit flip, AC flag management.
4. **Linux kernel `arch/x86/include/asm/smap.h`** — STAC/CLAC intrinsic
   definitions + usage constraints (for H3 branch only).
5. **Intel Core Ultra errata sheets** (i9-14900HX family) — any SMAP-related
   errata.
6. **QEMU + KVM SMAP emulation docs** — passthrough vs emulated behavior on
   `-cpu host`.
7. **Search: "SMAP double fault"** — any published blog posts or kernel
   discussions (LKML, Phoronix, etc.) describing this exact failure mode.
8. **Fajar Lang `src/codegen/llvm/intrinsic.rs`** (or equivalent) —
   precedent for adding `__builtin_*` intrinsics (needed only for H3).

Minimum 8 sources per Rule 2. Sources cited in
`docs/V29_P3_SMAP_FINDINGS.md` and `V29_P3_SMAP_DECISION.md`.

---

## 11. Self-Check — Plan Hygiene Rule 6.8 (All 8)

```
[x] 1. Pre-flight audit mandatory                    — Phase P0 satisfies this (6 tasks)
[x] 2. Verification commands runnable                — every task has literal shell command or file-exists check
[x] 3. Prevention layer per phase                    — P1 walker permanence, P2 handler attribution, P4 CR4 readback, P5 Makefile+hook
[x] 4. Multi-agent audit cross-check mandatory       — P0 re-runs bisect manually (not trusting prior agent claims); online research §10 cross-checks hypotheses
[x] 5. Surprise budget +25% minimum, tracked         — §6 tagged; auto-escalate to +40% on substrate drift; H3 defaults to +40%
[x] 6. Decision gates mechanical files               — §8 lists 4 gate files; pre-commit hook check 6/6 enforces
[x] 7. Public-facing artifact sync                   — P5.5–P5.8 covers MEMORY.md, CLAUDE.md, CHANGELOG, GitHub Release
[x] 8. Multi-repo state check                        — P0.5 runs 3-repo git status; §2 enumerates all affected repos
```

All 8 YES = plan ships.

---

## 12. Author Acknowledgement

Per CLAUDE.md §6.8 Rule 7 + user memory `feedback_honesty_upfront`:
this plan exists because V29.P2.SMEP shipped SMEP **only** after the bisect
(step 4) surfaced a secondary fault path the walker did not catch. The
prior claim space was honest — step 4 doc explicitly deferred SMAP+NX —
but the bug class (silent USER-flagged memory causing CR4 faults) remains
open until root cause is identified. This plan is the closure phase.

The most durable contribution is **Phase P2 (RIP attribution)** — once
double-fault handler captures RIP, every future kernel crash becomes
diagnosable without rebuilding. That capability outlasts this specific
SMAP investigation.

---

*V29.P3 SMAP+NX Closure Plan — drafted 2026-04-16 by Claude Opus 4.6
as the first deliverable of V30 next-session agenda Track 1, per Plan
Hygiene Rule 1.*
