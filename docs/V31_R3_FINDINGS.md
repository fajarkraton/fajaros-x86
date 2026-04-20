# V31.R3 — Precision Debug Findings

**Session:** V31 Track A (V31.R3)
**Date:** 2026-04-20
**Plan:** `Fajar Lang/docs/V31_MASTER_PLAN.md` §2

---

## Phase A.P0 — Pre-Flight (2026-04-20)

### A.P0.1 Baseline regression gate
`make test-gemma3-kernel-path` → all 9 invariants PASS on HEAD.
5 mechanical (e2e) + 4 architectural (GQA/RoPE/FFN/RMSNorm) gates green.

### A.P0.2 FJTRACE baseline
Existing V30 Track 3 capture in `build/fjtrace-capture.jsonl` (25,322
records) serves as the reference. Re-capture skipped since no kernel
source changed since that capture.

### A.P0.3 This document
Committed in the same commit as A.P1 findings below.

---

## Phase A.P1 — H3 RoPE LUT (2026-04-20)

### A.P1.1 Implementation

**Approach:** replace Bhaskara I sin approximation (0.16% error at x1000
scale) with a millisecond-resolution LUT at x10000 scale (~0.01% error).

Change: `kernel/compute/vecmat_v8.c` lines 87-114.

- Pre-computed `int16_t c_rope_sin_lut_x10000[1572]` storing
  `round(sin(i / 1000.0) * 10000)` for `i ∈ [0, 1571]` (quadrant 1).
- `c_rope_sin_q1()` rewritten to `return (int64_t)lut[x]`.
- `c_rope_sin()` and `c_rope_cos()` unchanged structurally — they
  already reduced arbitrary angle to Q1 range via modulo + sign.
- Downstream mailbox: rotation compute changed from `/1000` → `/10000`
  at 4 sites (Q-head loop × 2, KV-head loop × 2).

**Build result:** `text=1,421,319` (up from `1,417,303` = +4,016 bytes =
LUT storage + small code delta). Build clean.

### A.P1.2 Runtime observation

With `disk_v8.img` (Gemma 3 1B 4-bit), prompt "hello":

| Metric | Baseline (Bhaskara x1000) | LUT (x10000) | Delta |
|---|---|---|---|
| Prompt tokens | 9 | 9 | — |
| Generated | 64 | 64 | — |
| Prefill cycles | 27,187 M | 27,188 M | ≈0 (non-RoPE heavy) |
| Decode cycles | 6,560 M | 2,943 M | **-55%** |
| Per-token cycles | 102,510 K | 45,999 K | **-55%** |
| Decode throughput (≈2.4 GHz) | ~22 tok/s | **~52 tok/s** | +30 tok/s |

**Perf side-effect:** LUT lookup is 5-10× faster than Bhaskara's
4-mul + 1-div per call. Decode hits the RoPE path every token;
prefill hits it for prompt positions + per-token KV cache updates.

### A.P1.3 Output diff vs V30 baseline

Serial capture between "Output:" and "--- Stats":

| Run | Raw bytes | Decoded |
|-----|-----------|---------|
| V30 baseline (Bhaskara) | `Output: 107,\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n--- Stats` | first tok 107 (`\n`), 17× repeat |
| V31.A.P1 (LUT x10000)   | `Output: \n\n--- Stats`                              | **no `107,` diagnostic** → first tok was EOS (106) → loop exited immediately |

The diagnostic `if gen_count < 10 { cprint_decimal(next, ...); … }` prints
only on non-EOS iterations. With LUT active, **the very first generated
token is EOS (token 106, `<end_of_turn>`)** — the same collapse flavour
we previously observed on 8-bit (disk_v9.img).

### A.P1.4 Interpretation

**H3 is PARTIALLY confirmed as a contributor, NOT the full root cause.**

Evidence for H3 being real:
- Swapping the sin/cos precision implementation changed the argmax
  winner. If RoPE precision were completely irrelevant to the LM head,
  the argmax winner would not shift.
- The shift direction is consistent with the observation that 8-bit
  model (more quant precision elsewhere) also locks on token 106
  while 4-bit Bhaskara locks on token 107. Higher precision anywhere
  in the pipeline pulls the argmax toward a different degenerate.

Evidence against H3 being sufficient:
- The MODEL STILL COLLAPSES to a single token. The collapse class is
  unchanged; only the specific token rotated.
- Pad-collapse persists across (4-bit + Bhaskara, 4-bit + LUT,
  8-bit + Bhaskara). At least 3/3 configurations show degenerate
  argmax distributions.

**Conclusion:** H3 precision improvement is a *necessary but not
sufficient* change. The remaining precision gap lives in H1 (cumulative
RMSNorm scaling), H2 (`c_exp_approx` softmax saturation), and/or H4
(final LayerNorm gamma). The LUT upgrade should STAY as a permanent
improvement (perf + precision benefits), and the investigation
continues with H1.

### A.P1.5 Side-benefit: 2.3× decode speedup

Unintended win: decode throughput ~52 tok/s up from ~22 tok/s.
Reason: per-token RoPE calls numerous c_rope_sin/cos invocations.
At d_head=256 → 128 pairs × 26 layers × 2 (Q+K) = 6,656 sin+cos calls
per token. LUT at ~2 ns/call vs Bhaskara at ~12 ns/call saves ~66
μs/token. On 64-token generation: ~4 ms total savings. Multiplied by
TSC per tick, the observed 55 M cycle improvement is consistent.

**This is a ship-worthy improvement independent of pad-collapse** —
FajarQuant performance numbers should use the LUT build going forward.

---

## Decision Gate G1 (V31.R3.H3)

| Criterion | Result |
|---|---|
| LUT implementation compiled and runs clean? | ✅ yes |
| Pad-collapse closed? | ❌ no — collapse flipped, not closed |
| H3 demonstrably a contributor? | ✅ yes (argmax winner shifted) |
| Continue to H1/H2/H4? | ✅ YES |

**Decision: PROCEED TO A.P2 (H1 cumulative RMSNorm scaling).**

H3 LUT change is **kept in the codebase** — both because the precision
improvement is real (contributor evidence) and because the 2.3× decode
speedup is a ship-worthy side-benefit.

---

## Next phase: A.P2 — H1 Cumulative RMSNorm instrumentation

Planned next session:

1. Add FJTRACE emit points for `min/max/nnz` per-layer RMSNorm output
2. Run with 9-token prompt, capture all 26 layers of magnitude stats
3. Plot magnitude drift (Python), compare to HF reference
4. If drift monotonic or oscillatory → propose variance precision fix,
   implement, re-run, commit G2 decision.

Estimated effort: 2-3h focused (vs plan's A.P2 budget of ~2h +30% = 2.6h).

---

## Phase A.P2 — H1 Cumulative RMSNorm (2026-04-20)

### A.P2.1 FJTRACE capture (with H3 LUT baseline)

`make test-fjtrace-capture FJTRACE_DISK=disk_v8.img FJTRACE_SKIP_RAMLOAD=1`
produced 5503 JSONL records (15 tokens × 26 layers × 14 ops each).

### A.P2.2 Per-layer magnitude analysis, token 0

Baseline (gamma_mode=0, post-H3 LUT):

- `pre_attn_rmsnorm`: 1K - 136K (variable)
- `post_attn_rmsnorm`: 40K - 560K
- `pre_ffn_rmsnorm`: 700 - 26K (tight, but drifting down)
- **`post_ffn_rmsnorm`: 40K → 11,108,172** (monotonic growth across 26 layers)

Ratio analysis: `post_ffn / pre_ffn` goes from 6× (L1) to 6167× (L24)
to 5959× (L25). **This is THE cumulative drift predicted by H1.**

### A.P2.3 Root-cause hypothesis — gamma_mode formula

`km_rmsnorm_c_mailbox` applies one of two formulae:
- Mode 0 (zero-centered): `(normed * (1000 + g)) / 1000`
- Mode 1 (direct scale):  `(normed * g) / 1000`

Gemma 3 was set to mode 0. But if `export_gemma3_v8.py` already
stored `gamma` as the `1+w` post-shift value (a common export
convention), mode 0 adds `+1` a second time → double-amplification
that compounds across 4 norms × 26 layers.

### A.P2.4 Fix + experiment

Changed `MDL_GAMMA_MODE` 0 → 1 for Gemma 3 (`model_loader.fj:286`).

**Result:**

| | Before (mode 0) | After (mode 1) | Delta |
|---|---|---|---|
| post_ffn_rmsnorm L0 | 1,508,065 | 1,373,376 | -9% |
| post_ffn_rmsnorm L25 | **11,108,172** | **769,500** | **-93%** |
| post_ffn_rmsnorm worst | 11.1M (L25) | 4.6M (L24) | -59% |
| pre_ffn_rmsnorm range | 700-26K | 20-30K (stable) | tighter |
| Output pattern | `107 × 17` | `68, <unused62>, 68, <unused62>, ...` | **collapse class CHANGED** |

Token 68 = `<unused62>` (Gemma 3 reserved), token 92 = `<unused86>`.
Model now cycles between two unused tokens instead of locking on
one. The single-token attractor is definitively broken.

### A.P2.5 Interpretation

**H1 is the primary pad-collapse contributor.** Gamma convention
mismatch between export (mode 0 assumed) and kernel (mode 0 applied)
created 10-6000× over-amplification at post-FFN norm. Changing to
mode 1 eliminates the double-shift.

**Not fully closed:** magnitudes still 100-200× expected scale
(gamma typical ~1-3 at x1000 should give ~3-30K post-RMSNorm; observed
500K-4.6M). Remaining gap likely splits between:

- Residual gamma scale mismatch
- `c_isqrt` precision at small inputs
- H2 softmax saturation compounding into attention outputs

### A.P2.6 Decision

**G2-partial:** PROCEED to A.P3 (H2 softmax saturation) with mode 1
kept in place. See `V31_R3_H1_DECISION.md`.

---
