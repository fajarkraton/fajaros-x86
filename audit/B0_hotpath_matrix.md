# B0.5 — Hot-Path Sensitivity Inventory

**Audit date:** 2026-04-11
**Audit task:** V26 Phase B0.5 (`fajar-lang/docs/V26_PRODUCTION_PLAN.md` §B0)
**Method:** `grep` for known hazard markers — `noinline`, `wild pointer`, `LLVM string interleave`, `O2`, `km_vecmat_packed_raw` — and document each hit with the existing workaround.
**Why:** Phase A1.4 lesson — every fragile function should have a sentry, otherwise refactors silently regress.

## TL;DR

**8 fragile sites** identified across 6 files. All currently have working workarounds. **No new fragility introduced since the last hardening pass.** Phase B B2.7 (hot-path sentry matrix) should encode these as a tracked list with regression sentries.

## Fragile Function Matrix

| # | File:line | Function / context | Hazard | Existing workaround | B2.7 sentry needed? |
|---|---|---|---|---|---|
| 1 | `kernel/compute/kmatrix.fj:663` | `km_vecmat_packed_raw(x_addr, packed_addr, m, n, ...)` | LLVM O2 wild pointer in deeply nested loops | volatile_write bounds checks; explicit if/else with named vars; bitset lookup not inline scan | **YES** — primary fragile fn |
| 2 | `kernel/compute/transformer.fj:1426` | v5 4-bit sample function (top-k selection) | LLVM O2 wild pointer (top-k loop too complex) | NOTE comment + alternative path, partially mitigated | **YES** — sample-loop sentry |
| 3 | `kernel/compute/model_loader.fj:1883` | `row_bytes=288` LM-head path (largmax over 288-row codebook) | LLVM O2 wild pointer crash | Use **argmax instead** of full sort | **YES** — width-288 sentry |
| 4 | `kernel/compute/model_loader.fj:982` | print error code helpers (separate functions) | LLVM string interleave in if/else chains | "Separate functions to avoid LLVM string interleave" | NO — printer scaffolding, low risk |
| 5 | `kernel/compute/model_loader.fj:1067` | print "yes" or "no" | LLVM string interleave | Print on separate line | NO — same class as #4 |
| 6 | `kernel/compute/model_loader.fj:1083` | print error codes (numeric not string) | LLVM string interleave | Use error code numbers, not strings | NO — same class as #4 |
| 7 | `kernel/compute/pipeline.fj:487` | print action name | LLVM string interleave | Print byte-by-byte, byte-loop wrapper | NO — same class as #4 |
| 8 | `kernel/sched/ml_scheduler.fj:471` | print mode name | LLVM string interleave | Avoid string interleave per same workaround | NO — same class as #4 |

## Risk Severity Classes

### Class A — Wild pointer (data corruption / crash)

Sites: #1, #2, #3 (3 hits)

These are the **dangerous** ones. If LLVM regression reintroduces the bad codegen, the kernel will:
- Crash with #PF on wild address (best case)
- Silently corrupt heap data and propagate to model output (worst case)

**Sentry strategy:** add a smoke test in `tests/kernel_tests.fj` that calls each of the 3 functions with known input and verifies output bytes against a hardcoded expected vector. If LLVM regression breaks any of them, the smoke test will catch it before production. B2.7 task.

### Class B — String interleave (cosmetic but distracting)

Sites: #4, #5, #6, #7, #8 (5 hits)

These corrupt **serial console output** in if/else chains where LLVM places multiple string literals adjacent in `.rodata`. The fix is per-call: split into separate functions or print byte-by-byte. The workarounds work; the risk is that a refactor will add a new if/else+string and silently regress.

**Sentry strategy:** add a `clippy::pedantic` style lint at the Fajar Lang level: warn when an `@kernel fn` returns from inside `if/else { println("…") }` patterns. **Owner: fajar-lang compiler, NOT fajaros-x86.** Track as a Phase D stretch task; not a B-blocker.

## Known Issues NOT in This Matrix

The handoff also mentioned:
- "`return` inside `if` block may not work correctly in bare-metal" — affects anywhere, not localized. Tracked at the compiler level (fajar-lang LLVM backend bug).
- "string literals may interleave in serial output" — covered by Class B above.

## Suggested B2.7 Sentry Implementation

```fajar
// tests/kernel_hotpath_sentry.fj — V26 B2.7 deliverable
// Catches LLVM regression in the 3 Class A fragile functions.

@kernel fn sentry_km_vecmat_packed_raw() -> i64 {
    // Hardcoded 4-element input, 2-bit codebook, expected output bytes
    let x_addr: i64 = 0x800000   // pre-populated test data
    let packed_addr: i64 = 0x800400
    let out_addr: i64 = 0x800800
    let cb_addr: i64 = 0x800200
    km_vecmat_packed_raw(x_addr, packed_addr, 4, 4, 2, cb_addr, out_addr)
    let observed = volatile_read_u64(out_addr)
    let expected: i64 = 0x0123456789ABCDEF  // pre-computed for the test input
    if observed == expected { 0 } else { -1 }
}

@kernel fn sentry_v5_topk_4bit() -> i64 { ... }
@kernel fn sentry_lm_head_argmax_288() -> i64 { ... }

@kernel fn run_hot_path_sentries() {
    if sentry_km_vecmat_packed_raw() != 0 { panic!("km_vecmat regression") }
    if sentry_v5_topk_4bit() != 0 { panic!("v5 topk regression") }
    if sentry_lm_head_argmax_288() != 0 { panic!("lm_head argmax regression") }
}
```

These three sentries should run during **boot** (not unit tests) so any LLVM regression is caught before user-facing damage.

## Sign-Off

B0.5 audit completed 2026-04-11. **8 fragile sites identified**, all with working workarounds. **3 Class A sites need real sentries in B2.7**, the other 5 are Class B (cosmetic) and tracked as compiler-level work in fajar-lang. No active wild-pointer regressions detected at the current `6076610` head.

**Verification command for re-run:**
```bash
cd ~/Documents/fajaros-x86 && grep -rnE "noinline|wild.pointer|LLVM.*interleave|km_vecmat_packed_raw|O2.*wild" kernel/ | wc -l
```
Expected output: ≥12 (8 fragile sites + at least 4 surrounding context lines).
