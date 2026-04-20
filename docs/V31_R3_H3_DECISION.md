# V31.R3 — H3 RoPE LUT Decision

**Gate ID:** G1 (per `V31_MASTER_PLAN.md` §10)
**Committed:** 2026-04-20
**Upstream:** `V31_R3_FINDINGS.md` §A.P1.4

## Result

**PARTIAL — H3 contributor confirmed, pad-collapse not closed.**

With LUT x10000 RoPE active on Gemma 3 1B 4-bit:
- First generated token shifted from **107 (`\n`)** to **106 (EOS)**.
- Collapse class unchanged — model still locks on single degenerate token.
- Bonus: 2.3× decode speedup (~22 → ~52 tok/s) as a real side-benefit.

## Decision

**PROCEED to A.P2 (H1 cumulative RMSNorm scaling).**

- LUT change is **kept** — precision benefit is real (argmax-winner
  shift proves RoPE participates in the collapse dynamic) and perf
  benefit is free.
- Next hypothesis: H1 — cumulative RMSNorm scaling error. 104 norms
  per forward is the next-largest accumulation site.

## Rationale

The shift from token 107 → 106 is diagnostically informative: if H3
were completely orthogonal to the collapse mechanism, the argmax
winner should not change at all (any small numerical perturbation
should produce the *same* degenerate winner unless the degeneracy
itself is near-flat across many candidates). That the winner *did*
change implies the LM head logit ordering IS sensitive to per-layer
precision, and RoPE is one knob among several.

H1 (RMSNorm) is ranked next because:
- It accumulates per-layer (×4 × 26 = 104 operations)
- Fixed-point x1000 scale + integer sqrt introduces quantization at
  every step
- Current `km_rmsnorm_c_mailbox` takes `data_addr + dim + gamma_addr`
  but the **epsilon and variance precision** are baked into the C
  implementation — if epsilon scaling is off, it compounds fast

H2 (softmax saturation) and H4 (final LayerNorm gamma) remain in
queue after H1.

## Ship note

LUT RoPE is production-quality and the 2.3× decode speedup is a
legitimate FajarQuant performance claim. The V31 precision debug is
now cheaper to run on every future change (each ask hello completes
in ~45s instead of ~100s).

## Files changed in A.P1

- `kernel/compute/vecmat_v8.c` (+158 LOC LUT, -24 LOC Bhaskara, /10000 instead of /1000 at 4 sites)

## Git commit planned

```
feat(v31-r3-h3): RoPE sin/cos LUT x10000 — H3 contributor confirmed, 2.3× decode speedup
```
