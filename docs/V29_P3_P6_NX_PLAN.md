# V29.P3.P6 — Characterize & Close NX Silent Triple-Fault

**Phase:** V29.P3.P6 (sub-phase of V29.P3, follow-up to P4/P5)
**Date drafted:** 2026-04-16
**Entry doc:** `docs/V29_P3_SMAP_FINDINGS.md` §10 + `kernel/main.fj:189`
**Predecessor:** V29.P3.P4 (`f2dd682`) shipped SMEP+SMAP; NX deferred
**Parent plan:** `docs/V29_P3_SMAP_PLAN.md`

---

## 1. Problem Statement

After V29.P3.P1.5 strip closed the SMAP non-leaf USER leak, isolation
bisect (P4 session, 2026-04-16) found:

| Config | Outcome |
|---|---|
| SMEP only | ✅ reaches `[VFS]`, `nova>` (V29.P2 baseline + strip) |
| SMEP + SMAP | ✅ reaches `[VFS]`, `nova>` (V29.P3.P4 ship) |
| **SMEP + SMAP + NX** | ❌ silent halt at `println(16)`, before `frames_init()` |

### 1.1 Established facts

- No `EXC:8` / `PANIC:8` markers in boot log → **not a double-fault**
  (double-fault handler would emit EXC:8). Symptom is CPU silently
  halting post-triple-fault with `-no-reboot -no-shutdown`.
- `PTE_LEAKS=0` AND `PTE_LEAKS_FULL=0` both hold before hang — USER-bit
  state is clean, so NX issue is independent of the SMAP non-leaf
  closure.
- Hang occurs AFTER `nx_enforce_data_pages()` writes EFER.NXE and
  BEFORE the next `println(17)` prints. Exact death location is
  within this window in `kernel/main.fj`.
- `nx_enforce_data_pages()` is at `kernel/core/security.fj:221`.

### 1.2 Hypothesis tree

| ID | Hypothesis | Likelihood | Evidence to gather |
|----|-----------|------------|---------------------|
| **H1** | Kernel `.text` page is marked NX=1. CPU faults on next instruction fetch → #PF → IDT handler page is also NX → triple-fault → CPU shutdown. | **HIGH** | NX walker: list all NX=1 pages + cross-reference with ELF `.text` range from `objdump -t` |
| **H2** | `extend_identity_mapping_*` sets `PAGE_NX` on entries that happen to cover kernel code (not just data). Current code passes `flags \| PAGE_NX` for entries 64-511 — if kernel text overflows 128 MB boundary, some text pages land NX. | **MEDIUM** | Verify kernel `.text` end address vs `extend_identity_mapping` start (128 MB). If text < 12 MB (inside PD[0..5]), no overlap. |
| **H3** | `nx_enforce_data_pages()` itself mis-classifies: walks page tables and marks some kernel code page as NX based on wrong heuristic. | **MEDIUM** | Read `security.fj:221-`, trace what it marks NX. Prime suspect if it touches PD[0..5] kernel range. |
| **H4** | IDT / GDT / TSS descriptor page is NX-marked. When CPU tries to fetch IDT handler code on any interrupt (timer, IPI, etc.) → triple-fault. | **MEDIUM-LOW** | Check IDT/GDT frame addresses (typically `0x7EF000`-ish per V29.P2 TSS note) vs NX state. |
| **H5** | SYSCALL entry or specific interrupt handler resides on NX-marked frame. Fault surfaces on first interrupt after NX enable. | **LOW** | If H1-H4 rule out, check interrupt vector handlers' physical addresses. |

### 1.3 Why silent halt (vs EXC:8)

Triple-fault = fault during double-fault handler. Double-fault
handler itself being on NX page turns what would be #PF → #DF →
observable `EXC:8` into #PF → #PF (handler fetch fails too) → #PF
(iret to faulting context fetches again) → CPU shuts down (Intel
defines triple-fault as "CPU halt" with `-no-reboot`, or reset
otherwise).

This implicates H1 specifically: if the fault handler's page is NX,
attribution via RIP capture (V29.P3.P2 deferred pattern) won't work
directly — the handler can't run. **Workaround:** write RIP+CR2 to
a dedicated non-NX scratch area during handler entry in asm, or
temporarily disable NX in-fault via EFER toggle.

### 1.4 Prevention Layer Gap (Rule 3)

Current prevention: `make test-smap-regression` asserts SMAP clean,
but does NOT check NX state (because NX is commented out). Once
shipped, need a 6th invariant in the gate:
- `NX (EFER.NXE): ENFORCED` marker check (requires
  `nx_enforce_data_pages()` to emit the marker, likely already does)

OR rename target to `test-security-triple-regression` to cover all
three bits together.

---

## 2. Scope (Cross-Repo)

### 2.1 FajarOS x86 (primary)

| File | Anticipated change |
|------|---------|
| `kernel/mm/pte_audit.fj` | Add `pte_walk_find_nx_code_pages()` — analog of `pte_walk_find_u_leaks_full`, reports NX=1 entries whose vaddr falls in kernel `.text` range |
| `kernel/main.fj` | (a) boot marker `NX_CODE_VIOLATIONS=<hex16>`; (b) uncomment `nx_enforce_data_pages()` after fix ships (per root-cause branch) |
| `kernel/core/security.fj` | Fix `nx_enforce_data_pages()` classification if H3 matched |
| `kernel/mm/paging.fj` | Fix `extend_identity_mapping_*` NX flag if H2 matched |
| `kernel/core/exceptions.fj` (or wherever IDT handlers live) | Ensure handler frames are NX=0 if H4 matched |
| `Makefile` | Extend `test-smap-regression` → `test-security-triple-regression` with NX invariant |
| `docs/V29_P3_P6_NX_FINDINGS.md` | New findings doc (mirror of FINDINGS.md pattern) |
| `docs/V29_P3_P6_NX_DECISION.md` | Decision gate file (per Rule 6) |
| `Fajar Lang/CLAUDE.md` §3 | V29.P3.P6 row added to Version History |
| `MEMORY.md` | V29.P3.P6 status block update |

### 2.2 Fajar Lang

No compiler changes expected. Pure FajarOS paging + security work.
`cargo build --release --features llvm,native` should remain unchanged.

### 2.3 FajarQuant

Not touched. Unrelated.

### 2.4 Documentation (memory/claude-context)

Per Rule 7, this plan's closure triggers:
- `CLAUDE.md` §3 Version History row (V29.P3.P6)
- `MEMORY.md` V29.P3 block update (remove NX-deferred note when shipped)
- `CHANGELOG.md` (fajaros-x86) narrative entry for next patch release

---

## 3. Skills & Knowledge Required

| Area | Depth | Reference |
|------|-------|-----------|
| **x86_64 NX bit semantics** | Deep — bit 63 on leaf PTEs; requires EFER.NXE=1 to take effect | Intel SDM Vol 3A §4.6 (Access Rights) + §4.6.2 (Execute Disable) |
| **EFER MSR** | Medium — NXE=bit 11; `wrmsr` sequence | Intel SDM Vol 3C §2.2.1 |
| **Triple-fault diagnosis** | Medium — how to instrument without the handler triggering the same fault | Intel SDM §6.7 (Task Management) + Linux `early_idt_handler` pattern |
| **FajarOS kernel memory layout** | Medium — `.text` range from linker script, IDT/GDT/TSS base addresses | `linker.ld`, `boot/startup.S` (TSS RSP0=0x7EF000), `kernel/core/security.fj` |
| **ELF symbol table parsing** | Light — `objdump -t build/fajaros-llvm.elf` for `.text` boundaries | GNU binutils |
| **Fajar Lang inline asm** | Medium | Prior V29.P3 usage + `src/parser/asm.rs` |

**Skill gaps flagged:**
- Triple-fault debugging without live handler is non-trivial.
  **Online research required** (per CLAUDE.md §6.9 Rule 2): minimum
  4 references on x86 triple-fault early-boot debugging patterns
  (Linux early boot, Xen, MINIX 3, any bare-metal OS dev wiki).

---

## 4. Phased Approach

### Phase V29.P3.P6.P0 — Pre-Flight Audit

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P0.1 | Re-run P4 bisect (SMEP+SMAP+NX) on HEAD, capture fresh log | `build/bisect-logs/*_smap-smep-nx.log` exists, hang at `println(16)` reproduces | 0.1h |
| P0.2 | Dump kernel `.text` range via `objdump -t build/fajaros-llvm.elf \| grep -E ' [tT] ' \| head` | write lower + upper `.text` bound to findings doc | 0.05h |
| P0.3 | Read `nx_enforce_data_pages()` source (security.fj:221-) verbatim into findings doc | source inline in findings § | 0.05h |
| P0.4 | Read NX-setting call sites in `paging.fj` (`extend_identity_mapping`, `extend_identity_mapping_512`) | both functions inline in findings § | 0.05h |
| P0.5 | Multi-repo state check | `git status -sb` × 3 repos = all clean | 0.02h |
| P0.6 | Commit `docs/V29_P3_P6_NX_FINDINGS.md` P0 section | new file in git log | 0.1h |

**Phase P0 total: 0.37h** (+25% budget: 0.46h)
**Gate:** hang reproduces + kernel `.text` bounds known + NX code sites catalogued

### Phase V29.P3.P6.P1 — NX Walker (Code-Page Detection)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P1.1 | Add `pte_walk_find_nx_code()` to `pte_audit.fj`: walks 4 levels, reports leaf entries with `PAGE_NX` set AND vaddr in kernel `.text` range | new fn compiles; `make build-llvm` exit 0 | 0.3h |
| P1.2 | Emit `NX_CODE_VIOLATIONS=<hex16>` boot marker (analog of `PTE_LEAKS_FULL=`) in `main.fj` BEFORE `nx_enforce_data_pages()` call | boot log contains new marker | 0.1h |
| P1.3 | Run walker on current kernel; capture findings | `NX_CODE_VIOLATIONS=<N>` value + per-entry `NXC L<d>` lines recorded in findings | 0.15h |

**Phase P1 total: 0.55h** (+25% budget: 0.69h)
**Gate:** either `NX_CODE_VIOLATIONS>0` (H1/H2 confirmed, specific pages listed) OR `=0` (walker clean — escalate to H3/H4 path)

### Phase V29.P3.P6.P2 — Root Cause Identification (Decision Gate)

Mechanical decision file (Rule 6) before P3 patches. Commit
`docs/V29_P3_P6_NX_DECISION.md` recording:
- Which hypothesis matched (H1 / H2 / H3 / H4 / H5 / new)
- Evidence from P1 walker output
- Chosen fix path + estimated effort
- Rejected alternatives with rationale

**Branches:**

**B-H1/H2 (code page marked NX):**
- Locate set-site (walker output gives vaddr → cross-ref `objdump -t`)
- Fix: strip NX from kernel text range in whichever function set it

**B-H3 (nx_enforce_data_pages misclassifies):**
- Read misclassification logic; fix range check or flag handling
- Idempotence + TLB flush discipline

**B-H4 (IDT/GDT/TSS NX):**
- Check frame addresses (TSS at 0x7EF000 per V29.P2); walk page tables at those frames; strip NX if set

**B-H5 (residual, if H1-H4 all eliminate):**
- Implement non-NX scratch RIP-capture in double-fault handler
- Boot + capture RIP + symbolize via `addr2line`
- Re-scope based on what handler page fault on

**Phase P2 total: 0.3h decision + branch effort** (budget tracked per branch)
**Gate:** DECISION.md committed before any kernel paging/security edit

### Phase V29.P3.P6.P3 — Fix Implementation

Effort depends on P2 branch:

| Branch | Est | +25% budget |
|--------|----:|------------:|
| B-H1/H2 strip | 0.3h | 0.38h |
| B-H3 classification fix | 0.4h | 0.5h |
| B-H4 IDT/GDT/TSS strip | 0.3h | 0.38h |
| B-H5 handler instrumentation + investigation | 1.0h | 1.25h |

**Gate:** boot log shows `NX_CODE_VIOLATIONS=0` AND kernel reaches
`[VFS]` with SMEP+SMAP+NX all enabled AND no EXC markers.

### Phase V29.P3.P6.P4 — Regression + Prevention Layer

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P4.1 | Extend `make test-smap-regression` to 6 invariants, rename `test-security-triple-regression` | `make test-security-triple-regression` runs, all 6 PASS | 0.2h |
| P4.2 | Add 6th invariant: `NX_CODE_VIOLATIONS=0000000000000000` grep | new PASS line in target output | 0.05h |
| P4.3 | Optionally keep `test-smap-regression` as alias for backward compat OR update CI refs | CI job (if wired) picks up new target | 0.1h |
| P4.4 | Commit + push | multi-repo sync = 0 ahead | 0.05h |

**Phase P4 total: 0.4h** (+25% budget: 0.5h)

### Phase V29.P3.P6.P5 — Doc Sync (Rule 7)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P5.1 | CLAUDE.md §3 add V29.P3.P6 Version History row | committed in fajar-lang | 0.1h |
| P5.2 | MEMORY.md update: remove NX-deferred note, mark V29.P3 fully closed | file edited (no git — personal) | 0.05h |
| P5.3 | fajaros-x86 CHANGELOG narrative entry (optional next release) | CHANGELOG.md updated | 0.1h |
| P5.4 | GitHub Release tag if patch-worthy | `gh release create v3.5.0` OR skip | 0.1h |

**Phase P5 total: 0.35h** (+25% budget: 0.44h)

---

## 5. Effort Summary

| Phase | Estimate | +25% / +30% budget |
|-------|---------:|-----:|
| P0 Pre-flight | 0.37h | 0.46h |
| P1 NX walker | 0.55h | 0.69h |
| P2 Decision gate | 0.3h | 0.38h |
| P3 Fix (branch-dependent) | 0.3h–1.0h | 0.38–1.25h |
| P4 Regression + prevention | 0.4h | 0.5h |
| P5 Doc sync | 0.35h | 0.44h |
| **Total (B-H1/H2 branch)** | **2.27h** | **2.85h** |
| **Total (B-H5 worst case)** | **2.97h** | **3.72h** |

**Compare to V29.P3 actual (2.56h for SMAP closure):** this P6 budget
is slightly above, reflecting H5 worst-case instrumentation risk. If
P1 walker immediately finds violations (H1/H2), closure ~2.3h.

---

## 6. Surprise Budget Tracking (Rule 5)

- Default +25% per phase
- P3 **+40%** (NX fix may surface secondary fault requiring re-bisect)
- Commit messages tag variance: `fix(v29-p3-p6-p3): ... [actual Xh, est Yh, ±Z%]`
- If running total exceeds +25% by P4 start, escalate to +40% for remainder

---

## 7. Prevention Layers (Rule 3 — every fix must spawn one)

Per Rule 3, each phase must produce at least one durable prevention:

| Phase | Prevention artifact |
|-------|---------------------|
| P1 walker | `pte_walk_find_nx_code()` runs every boot → any future edit that introduces NX on kernel text triggers `NX_CODE_VIOLATIONS>0` marker (regression signal) |
| P3 fix | Fix is additive to existing strip function; idempotent |
| P4 gate | `test-security-triple-regression` Makefile target — blocks future edits that regress any of 3 security bits |
| P5 CLAUDE.md | Version History row = permanent cross-repo state marker |

Additional prevention (if NX walker is effective):
- Add kernel test case `test_no_nx_on_text` in `tests/kernel_tests.fj`
  (analog of `pte_no_user_leaks` from V29.P2)

---

## 8. Gates & Decisions (Rule 6 — mechanical committed files)

| Gate | Blocks | Mechanism |
|------|--------|-----------|
| P0 gate | P1 launch | FINDINGS.md P0 section committed (+ fresh bisect log) |
| P2 decision | P3 patch | DECISION.md with matched hypothesis + branch choice |
| P3 fix success | P4 regression setup | boot log shows `NX_CODE_VIOLATIONS=0` + `[VFS]` reached + no EXC |
| P4 regression | P5 doc sync | `make test-security-triple-regression` exit 0 |

No CI hook required for this P6 (inherits fajaros-x86 pre-commit 5/5 which already covers build + @unsafe + TODO severity + memory map + ELF gate).

---

## 9. Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| H5 (residual hypothesis) — none of H1-H4 matches | MEDIUM | P2 decision branch explicitly scopes H5 with handler instrumentation path; +40% P3 budget absorbs investigation |
| Double-fault handler itself NX-marked → cannot use RIP capture | LOW | Handler instrumentation writes to dedicated non-NX scratch page pre-nx-enable; verified by NX walker before enable |
| Fix strips NX from page that SHOULD be NX (kernel data) | LOW | Walker explicitly scopes kernel `.text` range; data pages untouched; regression gate catches re-enable of bad strip |
| Stale page-table state in memory map detector (V28.5 pattern) | LOW | TLB flush discipline per V29.P1.5 pattern |
| QEMU `-cpu host` NX handling diverges from Skylake-Client-v4 | LOW | P0 bisect runs without KVM (pure TCG) to match V29.P3 reproducer |

---

## 10. Online Research Triggers (per CLAUDE.md §6.9 Rule 2)

Required searches before P1 implementation (minimum 4 sources):

1. **Intel SDM Vol 3A §4.6.2** — Execute Disable bit semantics on leaf vs intermediate PTEs (**official authority**)
2. **Linux kernel `arch/x86/kernel/head64.c`** — early boot NX enable sequence; when does Linux enable EFER.NXE vs populate page tables with NX bits
3. **OSDev wiki "Triple Fault"** — canonical debugging patterns when no double-fault handler available
4. **GRUB2 Multiboot2 NX handling** — whether the loader pre-sets any NX bits in the initial page tables that survive our hand-off

Stretch:
5. MINIX 3 / Xen hypervisor early NX enable
6. Any published Intel i9 / Raptor Lake NX-related erratum

---

## 11. Self-Check — Plan Hygiene Rule 6.8 (All 8)

| # | Rule | Status |
|---|------|--------|
| 1 | Pre-flight audit (P0) exists | ✅ §4 Phase P0 with 6 runnable tasks |
| 2 | Every task has runnable verification command | ✅ each P0-P5 row has explicit command or artifact check |
| 3 | Prevention mechanism added per phase | ✅ §7 table; walker + regression gate + kernel test |
| 4 | Agent-produced numbers cross-checked with Bash | ✅ plan has no agent-produced numbers; all claims cite file:line from this session |
| 5 | Surprise budget tagged per commit | ✅ §6 tagging convention + +25%/+40% branches |
| 6 | Decisions are committed files | ✅ §8 gate table with P2 DECISION.md explicit |
| 7 | Public-facing artifact sync | ✅ §2.4 + P5 phase covers CLAUDE.md + CHANGELOG + optional Release tag |
| 8 | Multi-repo state check before starting | ✅ P0.5 task explicit |

**8/8 YES.** Plan ready.

---

## 12. Pre-execution Reminder

1. Load `CLAUDE.md` + `MEMORY.md` (auto)
2. Confirm V29.P3.P0–P5 commits still HEAD: `git log --oneline | grep -E 'v29-p3' | head`
3. Confirm 3-repo clean: `git status -sb` × 3 dirs
4. Run P0.1 bisect FIRST — must reproduce hang before P1

---

## 13. Author Acknowledgement

Plan drafted 2026-04-16 by Claude Opus 4.6 at the end of V29.P3 main
session. Predicated on V29.P3.P1's empirical success pattern: a
targeted 4-level walker reveals the leak, strip fix is additive, and
regression gate prevents regression. If NX follows the same playbook,
P6 closes in ~2.3h; if H5 is required, ~3h with +40% contingency.

Pattern reuse from V29.P3:
- Walker function naming (`pte_walk_find_nx_code` ≈ `pte_walk_find_u_leaks_full`)
- Boot marker format (`NX_CODE_VIOLATIONS=<hex16>` ≈ `PTE_LEAKS_FULL=<hex16>`)
- Decision gate file mechanism
- Regression test target rename (`test-smap-regression` → `test-security-triple-regression`)

---

*V29.P3.P6 Plan — generated 2026-04-16 by Claude Opus 4.6.
Parent: V29.P3.SMAP (commits `019bcf8`..`34426af` + `c7e5c33`).
Self-check 8/8 ✅. Ready for execution on next scheduled phase.*
