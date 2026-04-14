# V28 Phase B0 — Pre-Flight Audit Findings

**Date:** 2026-04-14
**Method:** Hands-on verification of FajarOS baseline for V28 "Intelligence"

## Results

| # | Check | Expected | Actual | Status |
|---|-------|----------|--------|--------|
| V28.0.1 | FajarOS LOC | ~106K | **106,722** | MATCH |
| V28.0.2 | Kernel tests | 25 | **25** | MATCH |
| V28.0.3 | Current LLM model | SmolLM-135M | SmolLM 768-dim + Gemma 3 RMSNorm support already in kmatrix.fj | **BETTER THAN EXPECTED** |
| V28.0.4 | Transformer LOC | ~1,581 | **1,581** | MATCH |
| V28.0.5 | Framebuffer status | VGA text only | VGA_BASE=0xB8000; no VESA LFB yet | MATCH (V28.3 scope) |
| V28.0.6 | Compiler version | 27.5.0 | **27.5.0** | MATCH |
| V28.0.7 | Multi-repo sync | 0 unpushed | 0 across all 3 | MATCH |

## Key Surprises

1. **Gemma 3 RMSNorm already implemented** (`kmatrix.fj:500-547`): dual-mode norm supports both Gemma 3 "(1 + weight) scaling" at line 504 AND LLaMA/SmolLM "direct-scale gamma" at line 547. V28.1 Gemma 3 port is less work than expected — RMSNorm kernel primitive is ready.

2. **768-dim support already exists** in `kmatrix.fj:3`: "Extends the kernel compute stack with 768-dim support (SmolLM d_model)". Gemma 3 1B needs 1152-dim (head_dim=256 × 4 heads for KV). Extension needed but infrastructure present.

3. **Compiler V27.5 ready**: all V28 prerequisites (MAX_KERNEL_TENSOR_DIM=128, AI scheduler builtins, @interrupt wrappers, VESA fb_set_base/fb_scroll, @app/@host annotations, Cap<T>, refinement params) are in place.

## V28 Scope (8 weeks, 400h budget)

| Task | Description | Est |
|------|-------------|-----|
| V28.1 | Gemma 3 1B kernel integration (RMSNorm scaling mode, GQA, RoPE, sliding window, larger vocab) | ~160h |
| V28.2 | AI-powered shell (natural language → commands) | ~60h |
| V28.3 | GPU framebuffer compositor (VESA LFB, double buffering, font rendering) | ~100h |
| V28.4 | AI-aware scheduler (tensor workload detection, wire builtins) | ~40h |
| V28.5 | Prevention layers + CI gates | ~40h |

## Gate

V28.0 complete. V28.1-V28.5 unblocked.
