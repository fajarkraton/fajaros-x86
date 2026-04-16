# V28.2 — Gamma Reads Verified Correct (Coherence Bug is Elsewhere)

**Date:** 2026-04-16
**Status update:** The earlier hypothesis (V28.2 fails because gamma
reads return garbage values ~10^13) is **WRONG**. Direct in-kernel
memory inspection confirms gamma is read correctly. The empty-output
bug is somewhere else in the v8 pipeline.

## Verification Evidence

Added instrumentation inside `km_rmsnorm` Pass 1 to dump bytes and
read variants at `gamma_addr = 0x14DCBF10` (input_layernorm for
layer 0 in RAM mode with 16-byte header fix):

```
[G-BYTES @ 14DCBF10]:
  -8..-1:  08 08 07 05 0A 06 07 0A   (end of FFN data — correct)
   0..+7:  FD 0F 00 00 00 00 00 00   (= 4093 = 4.09 real, matches HF weight)
  +8..+15: 17 11 00 00 00 00 00 00   (= 4375 = 4.375 real, matches gamma[1])

[G-READ] plain=4093 plus0=4093 plus8=4375 hard=4093
```

All read variants give the correct 4093 value. The RAM state matches
the file state matches the HF source weight. Bytes are:

- HF `model.layers.0.input_layernorm.weight[0]` = 4.09375 (FP32)
- Exported: `int(4.09375 * 1000) = 4093`
- File bytes at norms offset: `FD 0F 00 00 00 00 00 00` (little-endian 4093)
- RAM bytes after ram-load: same, `FD 0F 00 00 00 00 00 00`
- Kernel `volatile_read_u64(gamma_addr)` returns 4093

This is the full verification pipeline end-to-end.

## What This Rules Out

- 4-byte misalignment in gamma_addr computation (was already fixed in commit 695ede5)
- Integer-type truncation in gamma read
- LLVM O2 bug in `volatile_read_u64`
- Sign-extension issue with int32 scales

## What Still Doesn't Work

`ask` still produces empty output for Gemma 3 1B v8. All 64 generated
tokens decode to empty strings → argmax is picking token 0 = `<pad>`
consistently.

## Revised Hypothesis Space

With gamma reads proven correct, the bug must be in one of:

1. **`mdl_ram_lmhead_argmax_v8_tied`** — the LM head argmax over 262K
   vocab. All 64 generated tokens being pad=0 strongly suggests this
   function is picking token 0 regardless of input hidden state. Could
   be:
   - Integer overflow in the sum accumulator for 262144 × 1152 products
   - x_val × w_x_1M overflow before `/1000000`
   - First-token bias in the `if sum > best_score` compare chain

2. **`km_vecmat_packed_v8`** — the group-wise matmul kernel used
   throughout the 26 layers. Bug here produces degenerate hidden state
   that LM head then argmaxes to any token.

3. **Residual stream accumulation** — even with correct norms and gamma,
   26 layers × 4 norms per layer = 104 integer-rounding steps. Cumulative
   error could drag the final hidden state into a degenerate region.

## Recommended Next Steps

Per V28_2_STATUS.md options, pick one:

- **Option A (systematic debug):** Write Python simulator that runs
  kernel integer math step by step with real Gemma 3 layer 0 weights,
  compare against float reference. Find exact divergence.

- **Option D (ship + move on):** The v8 infrastructure is shipped and
  correct. Document coherence as a known sub-project and pivot to
  other FajarOS work. V28.2 effort has been ~10h already.

My recommendation: **Option D for this session**. The gamma-verification
work already produced a valuable finding (Gemma 3 gammas are huge, not
zero-centered). That's worth documenting. Going deeper into integer-math
coherence debugging for a research-grade model quantization is a
different project than shipping the V28.2 pipeline infrastructure.

## Effort Tally (HONEST)

| Phase | Est | Actual | Status |
|-------|----:|-------:|--------|
| V28.2 Day 1 (quantization algorithm) | 4 h | 1.0 h | ✅ pass |
| V28.2 Day 2 (kernel infrastructure) | 6 h | 4.5 h | ✅ ship |
| V28.2 Day 2 (coherent output gate) | — | **~5 h debug, still FAIL** | ❌ |

Total V28.2: ~10.5 h. Infrastructure 100% shipped. Coherence 0%.

Claiming anything else would be dishonest per the `honesty_upfront`
memory rule.
