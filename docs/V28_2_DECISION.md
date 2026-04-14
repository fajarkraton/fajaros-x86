# V28.2 Coherence Sub-Project — Decision

**Date:** 2026-04-14
**Decided by:** user ("lanjut sesuai dengan rekomendasi A")
**Choice:** **Option A — group-wise 4-bit quantization (GPTQ/AWQ-style)**

## Rationale

Matches industry standard for production 4-bit LLMs (llama.cpp, GPTQ,
AWQ, bitsandbytes). Best quality-per-byte at 4-bit.

## Parameters

- **Group size:** 128 elements
- **Scheme:** asymmetric per-group (scale + zero_point)
- **Indices:** 4-bit, packed 2/byte (unchanged from current format)
- **Scale:** f32 per group
- **Zero-point:** u8 per group (range 0-15)
- **Per-group storage:** 64 B packed + 4 B scale + 1 B zero = 69 B
  (vs 64 B packed + 128 B shared codebook for current 4-bit)
- **Memory overhead:** ~8% vs single-codebook 4-bit

## Scope Boundaries

Implements weight quantization for Gemma 3 1B .fjm v8 (new version).

**In scope:**
- `scripts/export_gemma3_v7.py` → `scripts/export_gemma3_v8.py`
  (group-wise algorithm, new binary format)
- Kernel: add v8 parse branch + new hot-path dequant math in
  `km_vecmat_packed_raw` and `mdl_ram_lmhead_argmax_v5_4bit`
- SmolLM-135M regression: keep v6 path intact (no changes)

**Out of scope:**
- QAT / calibration-based GPTQ (static RTN for this pass)
- Mixed-precision per-matrix (uniform group-wise for all)
- FajarQuant integration (separate research track)

## Verification Criteria (from V28_2_COHERENCE_PLAN.md §"Verification")

- `ask "what is 2 plus 2"` → response contains "4" or "four" within first 10 tokens
- `ask "hello"` → begins with a greeting-like token
- WikiText-2 PPL ≤ 20 on Gemma 3 1B (FP16 reference is ~10)
- SmolLM-135M v6 still runs, produces same baseline output as commit `65ef00f`

## Execution Sequence

**Day 1 (first-step target):**
1. Design v8 binary format (this doc + companion spec)
2. Rewrite export in `export_gemma3_v8.py` — group-wise quantize
3. Validate single-matrix round-trip (quantize → dequantize → check max
   absolute error < 1% of weight range)

**Day 2:**
4. Add v8 branch in `kernel/compute/model_loader.fj::mdl_parse_header`
5. Update hot paths for per-group dequant lookup
6. Full .fjm v8 export + disk-write + boot test

**Gate:** Day 1 ends when single-matrix round-trip test passes with
acceptable error. Day 2 ends when `ask "what is 2 plus 2"` is coherent.
