# V28.2 — Critical Finding: Gemma 3 Gamma Values Are NOT Zero-Centered

**Date:** 2026-04-16
**Impact:** Reframes the V28.2 coherence debugging. What we thought was
a bug in our integer RMSNorm math may actually be correct arithmetic
applied to unexpectedly-large gamma values that require different
numerical handling.

## The Finding

Direct inspection of Gemma 3 1B layer 0 norm weights (via safetensors):

| Norm | min | max | mean | std | (1+γ) range |
|------|----:|----:|-----:|----:|:------------|
| input_layernorm        | 2.47  | **55.75** | **4.55** | 2.77 | 3.47..56.75 |
| q_norm (per-head)      | -1.01 | 2.03  | 0.49 | 0.56 | -0.01..3.03 |
| k_norm (per-head)      | -1.97 | 4.41  | 0.46 | 0.67 | -0.97..5.41 |
| post_attention_ln      | -1.41 | **51.25** | -0.06 | 2.47 | -0.41..52.25 |
| pre_feedforward_ln     | -1.00 | **28.12** | **5.99** | 2.11 | 0.00..29.12 |
| post_feedforward_ln    | -1.00 | **66.50** | **1.89** | 5.52 | 0.00..67.50 |

**Most LLMs** (Llama, SmolLM, Mistral): γ is initialized to 1.0 and stays
near 1.0. RMSNorm output ≈ 1× normalized.

**Gemma 3:** γ is initialized to **0.0** with the formula `(1+γ)·x`, so γ
is the DEVIATION from 1.0. Training produces large positive γ for several
norm layers, giving amplification factors of **5×, 30×, even 50×** per
RMSNorm application.

Reference: `Gemma3RMSNorm` in transformers/models/gemma3/modeling_gemma3.py:
```python
class Gemma3RMSNorm(nn.Module):
    def __init__(self, dim, eps=1e-6):
        self.weight = nn.Parameter(torch.zeros(dim))  # init to 0
    def forward(self, x):
        output = self._norm(x.float())
        output = output * (1.0 + self.weight.float())   # (1 + γ)
```

## Why This Explains V28.2's Empty Output

Our integer-math flow per layer (Gemma 3, 4 norms):

1. input_layernorm amplifies ×5.55 typical (up to ×56)
2. attention (Q×K, softmax, ×V) ~preserves magnitude
3. post_attention_layernorm ×0.94 typical (γ mean -0.06)
4. residual add
5. pre_feedforward_layernorm ×6.99 typical
6. FFN — can amplify further
7. post_feedforward_layernorm ×2.89 typical
8. residual add

Per-layer magnitude multiplier (rough): **5.55 × 0.94 × 6.99 × 2.89 = 105×**.

In reference FP32, residual stream absorbs this — x_{l+1} = x_l + f(x_l)
where residual x_l is bounded and f(x_l) is normalized by rms. Training
ensures residual magnitude stays stable.

In our integer math with cumulative rounding errors, each RMSNorm
introduces small distortions that compound through the 26 layers and
can produce:
- Argmax → pad=0 (empty output) when hidden state collapses
- Argmax → specific outlier token (e.g., `"` or `*`) when one vocab row
  matches the distorted hidden state

## What This Means For Next Steps

### Option A: Verify exactly how HF processes Gemma 3

Trace through Python what hidden-state magnitudes actually are at each
layer boundary for the reference BF16 model. Compare to our integer
intermediates at equivalent layers. The discrepancy point IS the
specific integration bug.

### Option B: Switch to FP32 emulation for sensitive steps

Our RMSNorm could accept float inputs/outputs while the matmul stays
integer. A "hybrid precision" approach. Requires kernel-level float
support (likely using SSE2 which we already enable at boot).

### Option C: Reformulate RMSNorm to absorb gamma into scale

For large γ, we can fold it into the rescaling constant:
  output = x × K / (max_abs × rms_rs) × (1+γ)
becomes
  output = x × (1+γ) × K / (max_abs × rms_rs)
which lets us clamp (1+γ) into our integer range without intermediate
overflow.

### Option D: Accept V28.2 as partial + pivot

V28.2 shipped: format + algorithm + kernel infrastructure + 16-byte
header fix (retroactively helps V28.1 v7). Coherent output is a
separate research-level project given the integer-math precision
constraints. Document + move on to other work.

## Recommended Commit Status

Don't claim coherence. Ship the infrastructure gains. Next session picks
from Options A-D explicitly.
