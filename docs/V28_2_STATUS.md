# V28.2 Group-wise 4-bit — Current Status (Session End 2026-04-16)

## Headline

**V28.2 inference pipeline is structurally correct but not yet producing
coherent output.** The big bug from V28.1 (4-byte layer-header mismatch
that corrupted every matrix/gamma read) is FIXED. But the final output
for Gemma 3 1B v8 is empty (all tokens argmax to pad=0).

## What's Shipped (7 commits today, 2026-04-15 / 16)

| # | Commit | What |
|---|--------|------|
| 1 | `785ad71` | Group-wise 4-bit quant prototype — Day 1 gate PASS (2.40% max error) |
| 2 | `6a68ca8` | Full v8 export script (515 MB .fjm) |
| 3 | `6102355` | Kernel accepts v8 format (`model-info` shows group-wise) |
| 4 | `86c1933` | v8 hot paths wired (`km_vecmat_packed_v8`, embed, lmhead argmax) |
| 5 | `cede320` | Gemma 3 4-norm layer (post_attn + post_ffn) |
| 6 | `695ede5` | **16-byte layer header fix + max-abs rmsnorm** ← big correctness |
| 7 | (pending) | Attempted + reverted q_norm/k_norm per-head |

## The Big Bug We Found

`FJM_LAYER_HDR_SIZE = 16` in kernel, but export was writing **20 bytes**
(5 fields including extra `norm_size`). Every downstream matrix pointer
off by +4 bytes, every gamma value read from wrong address. Specifically:

- `gamma[0]` for input_layernorm read as **17,579,469,374,986** (garbage,
  actually the `norm_size=40960` field value or neighboring data)
- RMSNorm formula `(1+γ) × normed` = `(1 + 10^10) × ~1000 ≈ 10^13`
- Hidden state exploded 10^10× in first layer, compounded through 26 layers

This bug also affected V28.1 v7 — the "first token" achievement produced
incoherent tokens BECAUSE of this header mismatch, not just quantization
noise as originally diagnosed.

Fix: export writes `struct.pack("<iiii", ...)` (4 fields, 16 bytes).

## Current Output

```
nova> ask what is 2 plus 2
Output:                          ← empty
  Prompt:   7 tokens
  Generated:64 tokens
  Prefill:  11,074 M cycles
  Decode:   101,154 M cycles     ← +16% vs v7, matches v8 overhead
```

Earlier during debug we saw `"*************` output once (post-fix),
but it hasn't reproduced in subsequent clean runs. Either a transient
LLVM O2 nondeterminism, stale state, or I misread the cycles field.
Not a reliable result.

## What Isn't Working

Tokens all argmax to 0/pad → empty decode. Three orthogonal suspects,
none yet diagnosed:

1. **Missing q_norm / k_norm per-head** (Gemma 3 applies RMSNorm to Q
   and K between projection and RoPE). Added them, observed K magnitudes
   collapsing to 20 fp×1000 (= 0.02 real), dominating softmax degenerately.
   Reverted. Root cause of the K collapse is unclear — possibly Gemma 3's
   trained k_norm gamma has γ ≈ -1 (so 1+γ ≈ 0), or our integer RMSNorm
   diverges for d_head=256 distributions.

2. **Residual + post-norm sequence**. Our code does:
   `x = RES + post_attn_norm(attn_out)`
   Gemma 3 reference:
   `x = residual + self.post_attention_layernorm(hidden_states)`
   where hidden_states is already the attention output. Should match.
   Needs verification pass.

3. **Cumulative integer-math error**. Max-abs rmsnorm fixed the truncation
   issue but we may still be losing precision across 26 layers in a way
   that matters for Gemma 3's specific weight distribution.

## Next Session Recommendations

### Option A: Deep debug q_norm/k_norm

Dump k_norm gamma[0..8] directly from the file (not kernel-read) and
verify they match HF Gemma 3 layer 0 `k_norm.weight`. If kernel values
match Python, the issue is in our application. If they differ, it's an
offset bug.

### Option B: Verify integer rmsnorm against float reference

Write a small test: apply our `km_rmsnorm` to a fixed vector of known
Gemma 3 hidden-state values, compare to PyTorch Gemma3RMSNorm. If
results diverge significantly, reformulate.

### Option C: Ship v8 as infrastructure and revisit coherence

V28.2's quantization algorithm and v8 format ARE correct and better than
v7. Package v8 support as shipped infrastructure and document the
coherence gap as a separate project. This is the honest option.

## Effort Accounting (HONEST)

| Milestone | Est | Actual | Status |
|-----------|----:|-------:|--------|
| V28.1 first token | 160 h | 7.7 h | ✅ ship |
| V28.2 Day 1 (algorithm) | 4 h | 1.0 h | ✅ gate pass |
| V28.2 Day 2 (kernel integration) | 6 h | **~8 h, coherence NOT achieved** | ⚠️ partial |
| V28.2 coherent output gate | — | still failing | ❌ |

V28.2 total session time ~9h. The 16-byte header fix alone was worth
shipping — it improves V28.1 correctness too — but the coherent-output
gate from `V28_2_COHERENCE_PLAN.md` is NOT met.

## Recommended Commit Message for This Session

Ship as "partial V28.2" — shipping infrastructure with a known-open
bug, not claiming coherence achieved. Subsequent session picks from
Option A/B/C above.
