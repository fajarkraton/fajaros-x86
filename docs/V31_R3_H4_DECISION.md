# V31.R3 — H4 Final LayerNorm Gamma Decision

**Gate ID:** G4 (per `V31_MASTER_PLAN.md` §10)
**Committed:** 2026-04-20
**Upstream:** `V31_R3_FINDINGS.md` §A.P4

## Result

**H4 RULED OUT as a byte-offset / load-path bug.**

Final LN gamma is loaded correctly. The large per-layer gamma values
(up to 66.5 real) are authentic HF Gemma 3 1B weights, not an export
bug. The kernel reads the right bytes from the right offset.

## Evidence

Read directly from `disk_v8.img` (Gemma 3 1B 4-bit export) via Python:

**final_rmsnorm gamma (1152 values at offset 0x202FA850):**
- min: -1.015 (real)
- max: **46.000** (real)
- mean |g|: 7.04
- pattern: many values clustered around 0.5-5.0 with sparse outliers
  at 16-46 range. `round(x1000)` matches expected export path.

**Layer 0 per-layer gamma (from end of layer 0 block):**

| Norm | min | max | mean | mean \|g\| |
|---|---|---|---|---|
| input_layernorm | 2.468 | **55.75** | 4.55 | 4.55 |
| post_attn_ln | -1.414 | 51.25 | -0.064 | 1.19 |
| pre_ffn_ln | -1.000 | 28.13 | 5.99 | 5.99 |
| **post_ffn_ln** | -1.000 | **66.50** | 1.89 | 2.06 |
| q_norm | -1.007 | 2.031 | 0.489 | 0.66 |
| k_norm | -1.968 | 4.406 | 0.457 | 0.67 |

- `q_norm` / `k_norm` are "normal" (~1-4 range) — these are
  per-head norms standard in Gemma 3.
- The 4 main norms have outlier gammas reaching 28-66 real value.
- Values are round-clean (e.g. 55.750, 51.250, 66.500) — not
  quantization artifacts; these are the HF-trained values × 1000.

## Why gamma_mode=1 was the right fix anyway

Mode 1 formula: `out = (normed * g) / 1000` where g is stored raw.

For HF weight=5.156 → stored g=5156 → multiplier=5.156 (= 1 + 4.156 in
HF's `(1+w)` convention). This ALREADY includes the `+1` implicitly
in the stored value.

Mode 0 formula: `out = (normed * (1000 + g)) / 1000` = multiplier
`1 + g/1000`. For g=5156, multiplier=6.156 — **adds `+1` AGAIN** on
top of HF's already-shifted weight.

The **4 layers × 26 × ~1.17 compound factor** = 4.4× extra
amplification per forward, explains the 10× magnitude drop we saw
from mode 0 → mode 1.

## Why pad-collapse CLASS broke but not representation collapse

With mode 1 fix, per-op magnitudes are now dimensionally correct. But
Gemma 3's gammas are genuinely large (max 66.5 real). Fixed-point
arithmetic at x1000 scale compounds rounding error when multipliers
reach 60+, and the 4-norm × 26-layer structure amplifies further.

The symptom: early layers produce input-dependent variation, but
successive large-gamma norms attenuate it (the `rms`-division
collapses variance, then `(1+w)` with large `w` amplifies toward a
fixed direction set by gamma's shape, not the input's direction).

This is an intrinsic tension: the kernel's fixed-point scale is not
high enough to preserve direction through 104 large-gamma
multiplications. Float-math HF version preserves it; fixed-point
x1000 loses it.

## Decision

**H4 byte-offset RULED OUT.** Closing V31.R3 with status:
**pad-collapse CLASS broken** (single-token → two-token cycle) but
**representation collapse persists** (hidden states converge to
fixed attractor by L25).

## Future work (V32 candidates)

1. **Wider fixed-point scale** — promote RMSNorm to x100000
   (i.e., 10^5 scaling). Requires updating accumulators to i128
   intermediates, gamma storage to wider int type, and all
   downstream multipliers.

2. **Learned post-hoc gamma re-scaling** — at export time, compute a
   per-layer global scale factor and bake it into the LM head's
   inverse. Preserves architecture but accepts perturbed training.

3. **Move to custom IntLLM (Track C)** — design Phase D arch with
   integer-native gammas bounded to small values, avoiding the
   large-gamma problem entirely.

Option 3 is the research-grade path. Options 1-2 are stopgaps.

## Files changed in A.P4

None (diagnostic-only phase, analysis from disk image).
