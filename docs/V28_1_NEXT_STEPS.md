# V28.1 Gemma 3 1B Port — Next Steps Checklist

**Status:** Foundation done (v3.3.0). Remaining work = dedicated sprint.
**Prerequisites:** All met. Tensor pool, compiler builtins, kernel infrastructure ready.
**Estimated:** 4 weeks (~160h) with dedicated focus.

## Prerequisites (ALL DONE ✅)

- [x] Fajar Lang v27.5.0 shipped with MAX_KERNEL_TENSOR_DIM=128
- [x] AI scheduler builtins (`tensor_workload_hint`, `schedule_ai_task`)
- [x] @interrupt wrappers (ARM64 + x86_64)
- [x] fb_set_base, fb_scroll for framebuffer
- [x] @app, @host annotations
- [x] Refinement type params + Cap<T>
- [x] FajarOS v3.3.0 Gemma tensor pool (80 KB, 8 × 1280-dim)
- [x] kmatrix.fj RMSNorm dual-mode (Gemma 3 `(1+weight)` + LLaMA direct-scale)

## Sprint Week 1: Model Weight Export

- [ ] Install HuggingFace CLI, accept Gemma 3 license
- [ ] `huggingface-cli download google/gemma-3-1b-pt --local-dir model/gemma3-1b`
- [ ] Write `scripts/export_gemma3.py` — converts HF safetensors → .fjm format
- [ ] Quantize to 2-bit using existing FajarQuant pipeline
- [ ] Expected output size: ~250 MB at 2-bit (fits 1 GB QEMU)
- [ ] Verify embed + lm_head dimensions match expected (262,144 × 1152)

## Sprint Week 2: Attention Primitives

- [ ] Implement GQA in `transformer.fj`: 4 Q heads, 1 KV head (broadcasted)
  - Reuse existing multi-head attention scaffold
  - Add `broadcast_kv` helper that replicates single KV across 4 Q heads
- [ ] Implement RoPE dual theta:
  - Local layers: theta = 10000
  - Global layers: theta = 1000000
  - Existing RoPE in transformer.fj uses single theta (line ~200)
- [ ] Add 3 kernel tests:
  - `test_gqa_broadcast` — verify Q.len() == KV.len() * 4
  - `test_rope_local_theta` — verify rotation angle uses 10000
  - `test_rope_global_theta` — verify rotation angle uses 1000000

## Sprint Week 3: Sliding Window + Context

- [ ] Implement sliding window attention (512-token local)
  - Modify attention mask generation to zero beyond window
  - Preserve full attention for global layers
- [ ] Extend KV cache from 2K to 32K tokens
  - Current KV at 0x4000000, 64 MB
  - Gemma 3 needs: 32K × (1152 × 4 KV heads × 2 bytes × 26 layers) = ~30 MB per layer × fp16
  - At 2-bit quant: 32K × 1152 × 4 × 0.25 × 26 = ~96 MB per cache
  - Budget: move KV start to avoid model data (currently 0x10000000+)
- [ ] Add 262K vocab support:
  - Current RECENT_BITSET = 6KB (49K tokens)
  - Extend to 32KB (262K tokens) — fits at 0xBEC000 + 32KB
  - Test: repetition penalty works with larger vocab

## Sprint Week 4: Integration + Validation

- [ ] Wire model loader to accept Gemma 3 .fjm format
- [ ] Add shell command `model-load-gemma3 nvme 0` 
- [ ] First token generation test: `ask "2+2="` expect coherent continuation
- [ ] Numerical validation per layer (compare first 3 layers vs HF reference)
- [ ] Perplexity benchmark: WikiText-2 test set vs FP16 baseline
- [ ] Performance: measure tokens/sec on QEMU, compare vs SmolLM-135M

## Gate for V28.1 Complete

- [ ] `nova> ask "what is 2+2"` produces recognizable answer
- [ ] Output is more coherent than current SmolLM-135M
- [ ] Memory usage fits in 1 GB QEMU
- [ ] No panic paths, no OOM in normal generation
- [ ] Kernel tests: 26 → 30+ (5+ new tests for GQA/RoPE/sliding window)

## Decision Gates (Per §6.8 Rule 6)

- [ ] Before Week 1: commit `V28_1_SPRINT_DECISION.md` confirming 4-week allocation
- [ ] After Week 2: Go/No-Go on sliding window (may defer to V28.2)
- [ ] After Week 4: `V28_1_RESULTS.md` with benchmark data

## Fallback Plan

If full Gemma 3 1B proves too ambitious in 4 weeks:
- **Fallback A:** Port Gemma 3 270M (smaller, same architecture) — ~2 weeks
- **Fallback B:** Upgrade SmolLM-135M → SmolLM-360M (simpler port, no GQA) — 1 week
- **Fallback C:** Stay on SmolLM-135M, focus V28 on AI shell + desktop instead

## Related

- Parent plan: `docs/FAJAROS_V28_GRAND_VISION.md`
- Pre-flight audit: `docs/V28_B0_FINDINGS.md`
- V28 scope revision: `docs/V28_STATUS.md`
- Compiler prep: `~/Documents/Fajar Lang/docs/V27_5_COMPILER_PREP_PLAN.md`
