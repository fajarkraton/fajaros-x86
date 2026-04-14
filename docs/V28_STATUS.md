# V28 "Intelligence" — Status Report

**Date:** 2026-04-14
**Phase:** V28.0 complete, V28.1-V28.5 scoped

## Executive Summary

V27.5 compiler prep completed 96% of what V28 needs at the compiler layer. FajarOS already has substantial AI infrastructure (ml_scheduler.fj, transformer.fj, kmatrix.fj with Gemma 3 RMSNorm support, 2,047 LOC display service with framebuffer primitives).

**V28 is now a FajarOS-side integration effort**, not a compiler effort.

## Subphase Status

### V28.0 Pre-flight — DONE (`6507c4f`)

7 baselines verified:
- 106,722 LOC FajarOS | 25 kernel tests | 1,581 LOC transformer
- Gemma 3 RMSNorm already in kmatrix.fj:500-547 (dual-mode: Gemma 3 `(1+weight)` vs LLaMA direct-scale)
- 768-dim support present; 1152-dim extension needed for Gemma 3 1B
- Compiler V27.5 has all V28 prerequisites

### V28.1 Gemma 3 1B Integration — DEFERRED (Large)

**Why deferred:** ~160h work requires:
1. Model weight export from HuggingFace → binary format
2. Tensor pool extension 768 → 1152 dim
3. GQA (4Q:1KV) implementation
4. RoPE with dual theta values
5. Sliding window attention (512-token local + global layers)
6. 262K vocab table (vs current 32K)
7. 32K context (vs current 2K KV cache)
8. Numerical validation at each layer

**Recommendation:** Dedicated V28 sprint (4-week milestone).

### V28.2 AI-Powered Shell — DEFERRED (Medium)

Requires V28.1 (coherent LLM output).

### V28.3 GPU Framebuffer Compositor — EXISTING

FajarOS already has 2,047 LOC display service with:
- `fb_putpixel` / `fb_fill_rect` / `fb_draw_string` / `fb_draw_line_aa`
- `fb_draw_rounded_rect` with radius
- `fb_init_from_multiboot2` for VESA LFB detection
- Font rendering (1,076 LOC in font.fj)

New compiler builtins (`fb_set_base`, `fb_scroll`) available when
user-mode apps need direct framebuffer access outside the display
service. Kernel work is already done.

### V28.4 AI-Aware Scheduler — EXISTING

FajarOS already has `ml_scheduler.fj` with:
- Attention-based process scoring (512-byte pre-baked weights)
- `mlsched_score(pid)` per-process scoring
- `sched_pick_next_ml(current_pid)` ML-based selection
- `mlsched_set_mode` / `mlsched_get_mode` toggle

New compiler builtins (`tensor_workload_hint`, `schedule_ai_task`)
available from V27.5. Integration hook-point would be adding
automatic triggers on tensor operations (V29 codegen work).

### V28.5 Prevention Layers — V27.5 CI COVERS

V27.5 `v27_5_regression` CI job already validates:
- Compiler builtins (AI scheduler, framebuffer)
- `@interrupt` wrappers (ARM64 + x86_64)
- Refinement params + Cap<T>

## Revised V28 Plan

V28 scope is **narrower than originally planned** because most
infrastructure already exists. Remaining real work:

1. **V28.1 only** — Gemma 3 1B port (~4 weeks dedicated sprint)

V28.2-V28.5 are either deferred to post-V28.1 or already complete.

## Recommendation

**Next milestone: V28.1 Gemma 3 1B sprint.** 
- Week 1: Model weight export pipeline
- Week 2: Tensor pool + GQA implementation
- Week 3: RoPE + sliding window + large vocab
- Week 4: Numerical validation + quality benchmarks

Alternatively, **ship V27.5 as standalone compiler release** and
defer V28 to when a Gemma 3 model sprint can be committed.

## Current State

- Fajar Lang: v27.5.0 shipped
- FajarOS: v3.2.0 (last tag), V28.0 audit committed
- FajarQuant: v0.3.0 shipped
- All 3 repos synced, 0 unpushed commits
