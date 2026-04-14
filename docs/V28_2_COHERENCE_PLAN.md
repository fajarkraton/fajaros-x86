# V28.2 — Gemma 3 Coherence Sub-Project

**Date:** 2026-04-14
**Scope:** Close the quality gap between V28.1's working pipeline
(generates real 262K-vocab tokens) and coherent text output.
**Gate reached:** V28.1 pipeline is complete and demonstrably correct
(no regression vs SmolLM-135M, same quantization ceiling).
**Goal:** `nova> ask "what is 2 plus 2"` → `"The answer is 4."` or equivalent.

## Root Cause (Confirmed)

4-bit uniform Lloyd-Max quantization with a single global codebook per
matrix loses enough signal that both SmolLM-135M and Gemma 3 1B drop
below coherence threshold. Evidence: commit `65ef00f` — same incoherent-
vocab pattern for both models with identical kernel.

## Option Matrix (Ranked by Effort / Expected Quality)

### Option A — Group-wise 4-bit quantization (RECOMMENDED)

**What:** Replace the single-codebook-per-matrix scheme with group-wise
scale+zero_point (GPTQ/AWQ-style). Group size 128 elements.

**Expected quality:** 80-90% of FP16 (vs ~40% for single codebook).
This is the standard for production 4-bit LLM inference.

**Cost:**
- Export script rewrite: 4h. Quantize per 128-elem group, output
  packed indices + per-group (scale f16, zero-point u8).
- Kernel hot path changes: 6h. Dequantize per group on the fly in
  `km_vecmat_packed_raw` and `mdl_ram_lmhead_argmax_v5_4bit`.
  Adds ~0.5% runtime overhead (per-group scale lookup in the inner loop).
- Memory overhead: ~1.5× the current weight size (7-8 bytes per group
  of 128 elements for scale + zero-point). 333 MB → ~500 MB layers.
  Still fits in 1 GB identity mapping.
- Re-quantization time: comparable to current Lloyd-Max (~10 min per
  Gemma 3 1B export). No 24h blocker.

**Total:** ~2 session-days. High success probability.

**Why it wins:** matches the algorithm used by every production 4-bit
LLM (llama.cpp, GPTQ, AWQ, bitsandbytes). The quality gap vs FP16 is
a known, well-characterized ~1-2 PPL point loss on WikiText-2.

### Option B — 8-bit uniform Lloyd-Max

**What:** Bump `--layer-bits` and `--embed-bits` in `export_gemma3_v7.py`
from 4 to 8. Keep single-codebook-per-matrix structure.

**Expected quality:** 90-95% of FP16. Coherent.

**Cost:**
- Export time: Lloyd-Max with 256 centroids × 302M elements is ~16×
  slower than 4-bit's 16 centroids. ~12-24 h CPU on laptop.
- Kernel changes: codebook memory layout — 2 KB slot needed for
  256-centroid codebooks, not the current 128 B. Scrounge layout
  (possible at 0xBEF220+ after `MDL_V7_EXTRA`).
- Disk: model grows 477 MB → ~810 MB. Needs 2 GB `disk.img`.
- No new hot paths: the generic `mdl_ram_lmhead_argmax` already
  handles any bit width.

**Total:** ~1 CPU-day for quantization + ~4h kernel layout.
**Why not first:** slow, and trades 2× RAM/disk for less quality improvement
than Option A.

### Option C — Smaller-but-stronger model

**What:** Port a model that is ≤ 800 MB at 4-bit AND trained stronger
than SmolLM-135M. Candidates:
  - Qwen 2.5 0.5B (BPE 151K vocab, different arch)
  - Llama 3.2 1B (128K vocab, similar arch to Gemma 3)
  - TinyLlama 1.1B (32K vocab, stubs exist in `model_loader.fj`)

**Expected quality:** Depends on model. Llama 3.2 1B at 4-bit GPTQ
typically produces coherent but brief responses.

**Cost:**
- New export script: 4-8h per model.
- Kernel: model_loader.fj MODEL_TYPE branch for gamma convention.
  Arch-specific handling (e.g., Llama's SwiGLU is already supported
  as "gated FFN" — compatible).
- No quantization algorithm improvement — still limited by 4-bit
  single-codebook.

**Total:** ~1 session-day per candidate. Doesn't solve the underlying
quantization problem, just trades model choice.

## Recommended Sequence

1. **Phase 1 (2 session-days):** Option A — group-wise 4-bit.
   - Day 1: rewrite quantization in export script, validate 1 matrix.
   - Day 2: update kernel hot paths, test full model, measure
     perplexity on WikiText-2.
   - Commit gate: `ask "what is 2 plus 2"` → coherent.

2. **Phase 2 (optional, 1 session-day):** Option B as fallback if
   Option A underperforms. 8-bit uniform is guaranteed to work.

3. **Phase 3 (optional):** Option C — ship Llama 3.2 1B as the
   default Gemma-family alternative. Broadens the supported-model
   matrix beyond Gemma 3 and SmolLM.

## Out-of-Scope (for V28.2)

- FajarQuant v3.1 integration — targets KV-cache not weights,
  separate research track.
- Training-time improvements (QAT, distillation) — no GPUs here.
- On-device calibration — requires loading a calibration dataset
  into FajarOS, separate infrastructure.

## Verification Criteria

V28.2 is complete when ALL true:
- `nova> ask "what is 2 plus 2"` → response contains "4" or "four"
  within the first 10 tokens, with at least one coherent English
  phrase.
- `nova> ask "hello"` → response begins with a greeting-like token
  (not a random word like "sunshine").
- WikiText-2 perplexity ≤ 20 for Gemma 3 1B at the chosen format
  (reference FP16 is ~10).
- Regression test: SmolLM-135M still passes its own smoke criteria
  (tokenizer load, forward pass, non-crashing output).

## Current State Snapshot

- 10 V28.1 commits (2026-04-14) on `main`.
- `build/gemma3_1b_v7.fjm` (478 MB, 4-bit Lloyd-Max).
- `build/gemma3_tokenizer.fjt` (4 MB, 262K BPE).
- `disk.img` at 1 GB (model @ LBA 0, tokenizer @ LBA 1_000_000).
- `build/smollm_v6.fjm` — SmolLM regression baseline.
- Kernel: ELF 1.4 MB, security (SMEP/SMAP/NX) disabled at boot (P2).

## Handoff Checklist

When picking up V28.2:
- [ ] Re-read `docs/V28_1_FIRST_TOKEN.md` for the delivered pipeline.
- [ ] Re-read `docs/V28_1_NO_REGRESSION.md` for proof the kernel is correct.
- [ ] Pick Option (A / B / C) — record decision in
  `docs/V28_2_DECISION.md` (mandatory per plan-hygiene rule §6.8.6).
- [ ] Start with export script changes; keep kernel changes for after
  the new .fjm format is frozen.
