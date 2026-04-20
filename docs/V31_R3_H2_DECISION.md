# V31.R3 — H2 `c_exp_approx` Softmax Saturation Decision

**Gate ID:** G3 (per `V31_MASTER_PLAN.md` §10)
**Committed:** 2026-04-20
**Upstream:** `V31_R3_FINDINGS.md` §A.P3

## Result

**H2 RULED OUT as a primary contributor.**

Softmax is NOT saturating. Attention is healthy.

## Evidence

After H1 fix (gamma_mode 1 for Gemma 3), FJTRACE shows:

| Layer | q_proj |M| | k_proj |M| | v_proj |M| | attn_out |M| | attn_out / v_proj |
|---|---|---|---|---|---|
| L0 | 26343 | 53268 | 37871 | 56816 | 1.50× |
| L5 | 2152 | 5184 | 4086 | 9544 | 2.34× |
| L10 | 4372 | 5344 | 4390 | 6655 | 1.52× |
| L15 | 7129 | 11492 | 9074 | 11840 | 1.30× |
| L20 | 9297 | 11704 | 10498 | 19497 | 1.86× |
| L25 | 10515 | 7365 | 2450 | 2806 | 1.15× |

**Healthy-softmax signature:** ratio `attn_out / v_proj` in [1.0×, 3.0×]
across ALL 26 layers. This means attention is distributing weight
across 2-4 effective positions per head, not collapsing to a single
position (which would give ratio ≈ 1.0× exactly) and not uniform
(which would give lower ratios).

For reference, `c_exp_approx` saturation threshold:
- Input > 5000 → clamped to 148413
- Input < -7000 → clamped to 0

For saturation to dominate, `max_score - other_scores` would need
to exceed 7000 consistently. With `attn_scale = 1000000 / sqrt(d_head
× 10^6) ≈ 62.5`, that requires dot products differing by > 7000 ×
1000 / 62.5 = 112,000. Our observed attention vectors (Q~10K, K~10K,
V~5K at x1000 scale) produce dot products ~1-10K, differing by
hundreds to low-thousands. Far below saturation threshold.

## Secondary finding: hidden-state collapse, NOT argmax-level

`final_rmsnorm` outputs per token (15 tokens captured):

| Token | min | max | mean |
|---|---|---|---|
| 0 | -34270 | 18066 | -207 |
| 1 | -39698 | 8373 | -184 |
| 7 | -33350 | 9792 | -223 |
| 14 | -31817 | 7070 | -221 |

**All 15 tokens produce nearly identical final_rmsnorm distributions**
(min range -30K to -40K, max 7K to 18K, mean -150 to -260).

This is the remaining pad-collapse signature: **representations
collapse to a fixed attractor by L25**, despite healthy per-layer
dynamics and in-range magnitudes at argmax.

## Interpretation

The degenerate output after H1 fix is NOT a precision issue at the
LM head. It's a **representation dynamics issue**: early layers
produce variation, but by L25 the forward pass has converged to a
fixed hidden-state point regardless of input position. Same input
distribution → same argmax → same token.

Remaining candidate causes:

- **H1.2 Gamma value scale** — if mode-1 gamma values are too small
  (<0.5 at x1000 stored as <500), successive norms actively ATTENUATE
  variation instead of preserving it. Would need dedicated gamma
  audit.
- **H4 Final LayerNorm gamma** — specifically the final norm's gamma
  may flatten distribution before LM head.
- **Quantization noise saturation** — at 4-bit × group-wise, each
  layer might add uniform quantization noise that washes out signal
  differences across positions.

Note this is NOT the same as "model broken" — kernel vs sim remained
bit-exact on 8/14 ops at Layer 0 per V30 Track 3. The issue emerges
through accumulation, not at any single op.

## Decision

**PROCEED to A.P4 (H4 final LayerNorm gamma byte-compare).**

H2 scope is closed as ruled-out. No kernel change from A.P3.

## Files changed in A.P3

None (diagnostic-only phase).
