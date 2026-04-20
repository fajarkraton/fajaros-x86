# V31.R3 — H1 Cumulative RMSNorm Decision

**Gate ID:** G2-partial (per `V31_MASTER_PLAN.md` §10)
**Committed:** 2026-04-20
**Upstream:** `V31_R3_FINDINGS.md` §A.P2

## Result

**MAJOR PROGRESS — H1 confirmed primary contributor. Collapse class broken.**

### Evidence chain

1. **FJTRACE captured with H3 LUT baseline** revealed per-layer magnitudes:
   - `pre_attn_rmsnorm`, `pre_ffn_rmsnorm`: reasonable (~10K-50K at x1000)
   - `post_attn_rmsnorm`: 40K-560K
   - **`post_ffn_rmsnorm`: 41K → 11.1M across 26 layers** (monotonic-ish drift)
   - Ratio `post_ffn / pre_ffn` = 500× to 6000× at deep layers

2. **Hypothesized:** `gamma_mode=0` formula `(normed * (1000 + g)) / 1000`
   double-counts a `+1` shift if the export already stored
   post-shifted gamma values. HF `GemmaRMSNorm` stores weight as
   zero-centered (`1+w` applied at forward); if `export_gemma3_v8.py`
   applied that shift at export time, mode 0 in kernel would amplify
   twice.

3. **Experiment:** changed `MDL_GAMMA_MODE` from 0 → 1 for Gemma 3
   model types (`model_loader.fj:286`).

4. **Outcome:**
   - **Pad-collapse BROKEN.** Output shifted from `107 × 17` repeat
     (token `\n`) to `68 <unused62> 68 <unused62>...` — two-token
     cycle instead of single-token lock.
   - Magnitudes dropped 10× across the board. post_ffn_rmsnorm
     max now ~1M (worst L24 at 4.6M) vs previous 11M.
   - `pre_ffn_rmsnorm` now stable at ~20-30K across ALL layers
     (vs previously drifting 1K-50K with no pattern).

### Diagnostic table (token 0, all 26 layers)

| Config | post_ffn L0 | post_ffn L25 | pre_ffn range | Output |
|---|---|---|---|---|
| Before (mode 0, Bhaskara) | 1.5M | 11.1M | 700-26K | `107 × 17` |
| Before (mode 0, LUT x10000) | 1.5M | 11.1M | 700-26K | EOS (106) immediate |
| **After (mode 1, LUT x10000)** | 1.37M | 769K | **20-30K stable** | `68 <unused62> ...` |

## Interpretation

**H1 is the primary root cause of pad-collapse**, but partial fix only.

- With mode 1, model escapes the single-token attractor → generates
  varied (if still degenerate) tokens.
- Magnitudes are 10× better but still 100-200× the expected post-
  RMSNorm range (gamma typical ~1-3 at x1000 → output should be
  ~3-30K, not 1M).
- The residual 10× gap likely lives in:
  - (a) **Gamma value scale** — may need to be divided by 10 somewhere
    in the export pipeline
  - (b) **`c_isqrt` precision** at small variance inputs
  - (c) **Combined with H2** (softmax saturation) — the attention
    output magnitudes (post_attn ~200K-1M) suggest scoring itself
    may be amplifying.

## Decision

**PROCEED with split scope:**

1. **KEEP mode 1 for Gemma 3** — pad-collapse break is real.
2. **Continue to A.P3 (H2 softmax saturation)** — investigate
   attention score distribution for secondary explosion site.
3. **Defer deeper H1 investigation** (gamma value audit, isqrt
   precision) to a post-H2 refinement pass, unless H2 alone closes
   the remaining gap.

## Files changed in A.P2

- `kernel/compute/model_loader.fj` (1 line: gamma_mode 0 → 1 for mt 10/11)

## Git commit planned

```
feat(v31-r3-h1): gamma_mode 0→1 for Gemma 3 — pad-collapse class broken,
                 post_ffn magnitudes 10× smaller
```

## Open question for V31 R3 closure

Does H2 (softmax saturation) + H4 (final LN gamma) close the remaining
10× gap? Or do we need a dedicated H1.2 gamma-value audit pass?

Working hypothesis: H1 (gamma_mode) + H2 (softmax) + H4 (final LN)
together close pad-collapse **AND** produce coherent output. Test in
sequence.
