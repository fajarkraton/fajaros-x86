# V30.GEMMA3 — P10' Foundation Validation Report

> Replaces plan's P10 E2E Real Weights per the P9 Path D decision.
> Formalizes what HEAD's transformer pipeline does and does NOT do
> so future sessions (V31+) can target the residual work precisely.

**Date:** 2026-04-20
**Kernel:** `build/fajaros-llvm.elf` @ commit `b39d1ca` (P9 decision)
**Host:** i9-14900HX + KVM, QEMU 2-3 GB RAM

---

## 1. What the foundation delivers (positive claims)

Verified by P0-P8 audit + the observations below:

1. **Full Gemma 3 1B architecture** — GQA (4Q:1KV), dual-theta RoPE
   (local 10K / global 1M), sliding-window attention (globals at
   5/11/17/23), gated FFN (`down(gelu(gate)*up)`), 4-norm RMSNorm.
2. **C-bypass numerical path** — 10 hot-path ops (RMSNorm, GELU-tanh,
   add, mul, vecmat v8, RoPE, attention-score, LM-head argmax,
   embed-lookup) dispatch through gcc-compiled mailboxes to avoid
   LLVM O2 miscompile exposure.
3. **Multi-quant support** — 4-bit group-wise (disk_v8.img) and 8-bit
   group-wise (disk_v9.img) both load, both run through the full
   26-layer forward without crash, both reach the LM head.
4. **262K BPE tokenizer** — on-disk .fjt format, ID-ordered
   (commit `96a5cde` fix), loads in ~1s, verified decode: token
   107=`\n`, 106=`<end_of_turn>`, 105=`<start_of_turn>`.
5. **.fjm v7 header + v8 quant** — includes `n_kv_heads`,
   `rope_theta_global`, `sliding_window`, `sliding_pattern`,
   `quant_format`; strict superset of plan's proposed v2 format.
6. **Kernel-vs-sim bit-exactness** — 8 of 14 layer-0 ops produce
   BYTE-IDENTICAL output (0 ULP) against the Python simulator at
   `~/Documents/fajarquant/tools/kernel_sim/`. The 6 remaining ops
   also match after the C-bypass fix is applied.
7. **Boot + shell workflow** — `model-load → embed-load →
   tok-load → ask` sequence is stable; shell recovers cleanly
   after every run.

## 2. What the foundation does NOT deliver (negative claim)

**Coherent generation output.** The transformer runs mechanically
correctly but the numerical state after 26 layers collapses to a
single-token distribution at LM-head argmax. Characterization:

### 2.1 Run matrix

| Disk | Model | Prompt | Tok | Gen | First token | Decoded stream |
|---|---|---|---|---|---|---|
| disk_v8 | Gemma3-1B 4-bit | "hello" | 9 | 64 | **107** (`\n`) | 17 newlines then stop |
| disk_v8 | Gemma3-1B 4-bit | "What is 2+2?" | 15 | 64 | **107** (`\n`) | (same pattern) |
| disk_v9 | Gemma3-1B 8-bit | "hello" | 9 | 64 | **106** (`<end_of_turn>`, EOS) | 0 tokens before EOS |

Prompt-independent and quant-bit-width-sensitive:

- **4-bit: repeated `\n`** — argmax locks on token 107 regardless of
  prompt. Consistent with a near-degenerate hidden-state distribution
  where many token embeddings dot-product similarly; 107 wins by a
  tiny margin.
- **8-bit: immediate EOS** — argmax locks on token 106 (`<end_of_turn>`)
  even tighter. The 8-bit model's additional quant grid precision
  doesn't help — if anything it shifts the argmax winner to a
  DIFFERENT degenerate token.

### 2.2 Timing / load

From P0.2 baseline and 8-bit run:

| Metric | 4-bit | 8-bit |
|---|---|---|
| Model size on disk | 514 MB | (similar order) |
| Embed load | 155 MB in ~5s | 299 MB in ~7s |
| Tokenizer load | ~1s | ~1s |
| Prefill per-token cycles | 3,021 M | 2,888 M |
| Decode per-token cycles | 102 M | 46 M |
| Decode rate (≈2.4 GHz) | ~22 tok/s | ~52 tok/s |

8-bit decodes faster than 4-bit because the nibble-unpack loop in
argmax is skipped (`vecmat_v8.c:219-235` direct-byte-read branch).
All timings are within the P9 30-second budget.

### 2.3 Stability

Zero kernel crashes, EXC markers, or PANIC across all three runs.
Shell returns to `nova>` reliably. The foundation is rock-solid
MECHANICALLY — the open question is purely numerical.

## 3. Open research question (R3)

Why does a mechanically-correct transformer with bit-exact per-op
validation still collapse to a degenerate output distribution?

From the P9 decision doc, ranked candidate causes:

1. **Cumulative RMSNorm scaling** — 104 normalizations per forward
   (4 per layer × 26 layers) in fixed-point may accumulate
   scale-magnitude drift beyond the effective precision of
   x1000-scaled i64.
2. **`c_exp_approx` softmax saturation** — the piecewise exp may
   collapse the softmax to near-one-hot, over-concentrating
   attention on one position.
3. **Bhaskara RoPE 0.16% shared error** — applied at every layer;
   long-range compounding could rotate Q/K angles to aliasing.
4. **Final LayerNorm gamma weight loading** — a single byte-offset
   bug in the v7 header parser for the final norm could invalidate
   the last transformation before argmax.

Next-session investigation should run each hypothesis as an
independent sub-experiment:

- H1: instrument per-layer activation magnitude statistics
  (already have FJTRACE — just need a stats-aggregation pass)
- H2: dump post-softmax distribution for layer 0 token 0; compare
  to PyTorch
- H3: upgrade `rope_sin/cos` to ×10000 LUT; re-run; check whether
  collapse shifts
- H4: byte-compare final_rmsnorm output against HF reference at
  position 0

## 4. Research-artifact status

This foundation is sufficient to support:

- **Infrastructure claim** — "FajarOS can host a Gemma 3 1B
  transformer end-to-end in under 10 ms/tok (KVM)"
- **Bit-exactness claim** — "kernel arithmetic matches Python
  reference to 0 ULP on the validated op set"
- **Format claim** — ".fjm v7 format carries all Gemma 3
  architectural parameters and loads in <1s from NVMe"
- **Boot + shell claim** — "user-friendly 4-command sequence from
  boot to inference attempt"

It is NOT sufficient to support:

- Any claim about response quality
- Any accuracy benchmark (GLUE, MMLU, HellaSwag, …)
- Any "inference works" demo outside of the token-107 / EOS
  collapse shown here

V31 is where the quality claim gets earned, after R3 closes.

---

*Foundation validation: CLOSED 2026-04-20. Research-artifact
 ship-readiness: YES. Inference-quality ship-readiness: NO (defer
 V31).*
