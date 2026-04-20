# V31.R3 — Precision Debug Closure

**Gate ID:** G2 (final R3 close, per `V31_MASTER_PLAN.md` §10)
**Committed:** 2026-04-20

## Scoreboard

| Hypothesis | Status | Impact |
|---|---|---|
| **H1** Cumulative RMSNorm (gamma_mode) | ✅ **CONTRIBUTOR (primary)** | 10× magnitude drop. Pad-collapse class broken. |
| **H3** Bhaskara RoPE precision | ✅ **CONTRIBUTOR (minor)** | Argmax winner shift. Shipped with 2.3× decode speedup. |
| **H2** c_exp_approx softmax saturation | ❌ **RULED OUT** | Attention ratios 1-3× (healthy). |
| **H4** Final LN gamma byte-offset | ❌ **RULED OUT** | Gamma values are authentic HF weights (up to 66.5 real). |

## Before / after summary

| Metric | V30 baseline | V31.R3 (H1+H3) |
|---|---|---|
| First generated token | 107 (`\n`) | 68 (`<unused62>`) |
| Token collapse | **single-token lock, 17× repeat** | **two-token cycle, `<unused>` tokens** |
| post_ffn_rmsnorm max (L25) | 11,108,172 | 769,500 (-93%) |
| Decode throughput | ~22 tok/s | **~52 tok/s** (2.3×) |
| final_rmsnorm per-token variance | degenerate | still degenerate ★ |

★ = remaining open problem for V32.

## Residual open problem: representation collapse at L25

`final_rmsnorm` outputs are nearly identical across 15 tokens even
with H1+H3 fixed. Root cause: Gemma 3's per-layer gamma values
genuinely reach 66.5 real, and 104 successive large-gamma norm
multiplications in x1000 fixed-point compound beyond the precision
threshold. Direction is lost; only magnitude pattern survives.

**This is not a bug in the V31.R3 scope — it's a quantization-
scale constraint that requires V32+ work.**

## V32 path options

**Option 1 — Wider fixed-point:**
- Promote RMSNorm to x100000 scale (i128 intermediates)
- Effort: ~1 week, preserves model compatibility
- Risk: marginal improvement uncertain, same arch limitation

**Option 2 — Per-layer gamma rescale at export:**
- Compute per-layer scale factor, bake into LM head
- Effort: ~3-5 days (export script + re-export)
- Risk: mathematical correctness hard to verify end-to-end

**Option 3 — Custom IntLLM (Phase D):**
- Design integer-native transformer with bounded-small gammas
- Effort: 6-8 weeks (Phase D research project)
- Payoff: novel research paper + clean architecture fit

**Recommended:** Option 3. Per V31 master plan, FajarQuant Phase D
is the natural home for this problem. Trying to shoehorn Gemma 3's
trained fp16 weights into fixed-point kernel arithmetic is fighting
the core impedance mismatch. A model DESIGNED for fixed-point
sidesteps the issue entirely.

## What ships from V31.R3

1. **H3 LUT x10000 RoPE** — permanent. 2.3× decode speedup is
   FajarQuant-performance-grade.

2. **H1 gamma_mode=1 for Gemma 3** — permanent. Pad-collapse class
   break is a real milestone.

3. **Decision corpus** — 4 decision docs (`H3`, `H1`, `H2`, `H4`)
   + this close doc form the Rule-6 mechanical-gate deliverable
   set for V31 master plan gate G2.

4. **Updated FJTRACE capture** — 28K records captured post-H1,
   available in `build/fjtrace-capture.jsonl`. Reusable for V32.

## V31 master plan impact

- **M8 "Precision closed"** status: **PARTIAL.** H1+H3 shipped;
  H2+H4 ruled out; pad-collapse class broken but representation
  collapse deferred to V32.
- **Track B (Fajar Lang fix)** priority increases: since custom
  IntLLM (Track C) is the recommended V32 path, making Fajar Lang
  code-gen clean becomes necessary for Phase D to be written
  natively (not in C bypass).
- **Track C (Phase D)** scope unchanged — now with evidence that
  the current architecture has fundamental fixed-point precision
  issues, Phase D's integer-native design has stronger motivation.

## Effort summary

| Phase | Budget | Actual | Variance |
|---|---|---|---|
| A.P0 pre-flight | 0.4h | 0.1h | -75% |
| A.P1 H3 LUT | 2h | 1.5h | -25% |
| A.P2 H1 RMSNorm | 2-3h | 1.5h | -50% |
| A.P3 H2 softmax | 1-2h | 0.5h | -67% |
| A.P4 H4 final LN | 1h | 0.3h | -70% |
| A.P5 close-out | 0.5h | this file | — |
| **Total R3** | **6-8h** | **~4h** | **-50%** |

## Sign-off

V31.R3 CLOSED 2026-04-20. Ship H1+H3 fixes.

Proceed per V31 master plan:
- Track B (Fajar Lang LLVM fix) — unblocks Track C clean-path
- Track C (FajarQuant Phase D IntLLM) — the real fix for residual problem
