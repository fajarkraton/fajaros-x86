# Gemma 3 1B Upgrade Plan — FajarOS Kernel-Native LLM

> **Version:** 2.0 (2026-04-08)
> **Author:** Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id)
> **Model:** Claude Opus 4.6 exclusively
> **Goal:** Upgrade FajarOS from SmolLM-135M test model to real Gemma 3 1B inference
> **Status:** PLANNING
> **Previous:** v1.0 targeted Gemma 3 270M. Upgraded to 1B for IFEval 80.2% (vs 51.2%).

---

## Executive Summary

FajarOS Phase 1-8 pipeline is complete with a test model (d=16, 2 layers).
This plan upgrades to **Google Gemma 3 1B** — IFEval 80.2%, same architecture
as Gemma 3 270M but 3.7x more parameters for dramatically better quality.

**Why 1B over 270M:**
- IFEval: **80.2%** vs 51.2% (+57% improvement)
- Architecture: **100% identical** (same GQA, RoPE, sliding window, RMSNorm)
- Memory: 250 MB at 2-bit → fits in 1 GB QEMU (774 MB free)
- Extra effort: **+1-2 tasks only** (frame-alloc hidden state for d=1152)

**End state:** `nova> ask "What is 2+2?"` runs Gemma 3 1B entirely inside the kernel,
producing coherent English responses at IFEval 80% quality.

---

## Gemma 3 1B Architecture (exact from config.json)

```
hidden_size:          1152         # d_model
num_hidden_layers:    26           # transformer layers
num_attention_heads:  4            # query heads
num_key_value_heads:  1            # KV heads (GQA, 4:1 ratio)
head_dim:             256          # per-head dimension
intermediate_size:    6912         # FFN intermediate
vocab_size:           262144       # 256K tokens
max_position_embeddings: 32768    # 32K context
rms_norm_eps:         1e-06        # RMSNorm epsilon
rope_theta:           1000000.0    # RoPE base frequency
sliding_window:       512          # local attention window
sliding_window_pattern: 6         # every 6th layer is global
hidden_activation:    gelu_pytorch_tanh
attention_bias:       false
EOS token:            106
BOS token:            2
```

### Gemma 3 Family Comparison

| Parameter | 270M | **1B (target)** | Ratio |
|-----------|------|-----------------|-------|
| hidden_size | 640 | **1152** | 1.8x |
| num_layers | 18 | **26** | 1.4x |
| num_heads | 4Q:1KV | 4Q:1KV | same |
| head_dim | 256 | 256 | same |
| FFN dim | 2048 | **6912** | 3.4x |
| vocab | 262K | 262K | same |
| IFEval | 51.2% | **80.2%** | +57% |
| 2-bit size | ~105 MB | **~250 MB** | 2.4x |

### Key Differences from Current Code (SmolLM-135M test model)

| Feature | SmolLM-135M (test) | Gemma 3 1B | Code Impact |
|---------|-------------------|------------|-------------|
| d_model | 768 | **1152** | **Exceeds km_ slot max 1024 → frame-alloc ALL vectors** |
| Layers | 12 | **26** | +117% compute, zero code change |
| Attention | MHA (12 heads) | **GQA (4Q:1KV)** | New: broadcast KV across query groups |
| head_dim | 64 | **256** | 4x larger dot product per head |
| FFN | 2-matrix (3072) | **3-matrix gated (6912)** | New: gate*up→down, frame-alloc buffer |
| Norm | LayerNorm | **RMSNorm** | Simpler: no mean, no beta |
| Position | Learned | **RoPE** | New: rotary embedding with sin/cos |
| Attention type | Full | **Hybrid (sliding+global)** | New: 512-token window for local layers |
| Vocab | 49K | **262K** | Frame-alloc embed + logits + tokenizer |
| Activation | GELU (sigmoid) | **GELU (tanh)** | More accurate approximation |
| Context | 2048 | **32768** | 16x larger KV cache capacity |
| EOS | 2 | **106** | Config change |

### Memory Budget (2-bit quantization, 1 GB QEMU)

```
Component                              Size        Cumulative
─────────────────────────────────────  ─────       ──────────
Kernel ELF (.text+.data)               2 MB        2 MB
System (page tables, drivers, heap)    8 MB        10 MB

Embedding table (262K × 1152 × 2/8)   75 MB       85 MB
26 layers:
  Q proj  (1152 × 1024 × 2/8) × 26    7.4 MB
  K proj  (1152 × 256  × 2/8) × 26    1.9 MB
  V proj  (1152 × 256  × 2/8) × 26    1.9 MB
  O proj  (1024 × 1152 × 2/8) × 26    7.4 MB
  gate_proj (1152 × 6912 × 2/8) × 26  51.5 MB
  up_proj   (1152 × 6912 × 2/8) × 26  51.5 MB
  down_proj (6912 × 1152 × 2/8) × 26  51.5 MB
  RMSNorm gamma × 2 per layer         1.2 MB
  Codebook per layer                   0.1 MB
  Subtotal 26 layers                   174 MB      259 MB

LM head (1152 × 262K × 2/8)           75 MB       334 MB
KV cache (512 ctx × 26 layers × 256d) 3 MB        337 MB
Tokenizer table (262K × 16B)          4 MB        341 MB
Inference scratch                      2 MB        343 MB
─────────────────────────────────────  ─────       ──────────
TOTAL USED                             343 MB
FREE                                   681 MB
QEMU RAM                               1024 MB (1 GB)
```

**Comfortable fit.** 681 MB free headroom.

Note: Addresses above 128 MB (0x8000000) require extended identity mapping
in page tables. See Phase F1.

---

## Implementation Phases

### Phase A: Remaining Bug Fixes (from audit)

| Task | File | Description |
|------|------|-------------|
| A1 | fajarquant.fj | Fix PCA rotation overflow: clamp `r * v` intermediate to prevent i64 overflow |
| A2 | kmatrix.fj | Fix LayerNorm variance precision: accumulate `diff*diff` first, divide by dim at end |
| A3 | pipeline.fj | Fix noise `(seed % 100) - 50` for negative seed: use `((seed % 100) + 100) % 100 - 50` |
| A4 | model_loader.fj | Add header offset validation: `if embed_off > total_size { return -3 }` |
| A5 | tokenizer.fj | Add output buffer bounds check: `if n_tokens >= max_tokens { break }` in tok_encode |

**Gate:** All existing commands still work, no crashes. `model-load test` + `infer hello` pass.

---

### Phase B: RMSNorm + Gated FFN + Frame-Allocated Vectors

**Why first:** Every layer uses these. Must be correct before anything else.

| Task | Description | Verification |
|------|-------------|-------------|
| B1 | Add `km_rmsnorm(data_addr, dim, gamma_addr, eps)` to kmatrix.fj | RMSNorm(x) = x / sqrt(mean(x²) + eps) * gamma. No mean subtraction, no beta. Fixed-point: eps = 1 (= 1e-6 * 1e6 scaling). Test: known input → matches PyTorch within 1%. |
| B2 | Add `km_gelu_tanh(data_addr, dim)` to kmatrix.fj | GELU_tanh(x) = 0.5 * x * (1 + tanh(√(2/π) * (x + 0.044715 * x³))). Fixed-point tanh approximation. |
| B3 | Add frame-allocated vector API: `tfm_vec_alloc(dim)`, `tfm_vec_free(addr)`, `tfm_vec_get/set` | All hidden state vectors (d=1152) use frame_alloc_contiguous. Returns raw address. Manages up to 16 active vectors. |
| B4 | Add gated FFN: `tfm_ffn_gated(x_addr, layer, d_model, ffn_dim)` | `out = down_proj(gelu(gate_proj(x)) * up_proj(x))`. Three weight matrices per layer. gate+up both produce ffn_dim=6912 vectors (frame-allocated). Element-wise multiply before down_proj. |
| B5 | Update `tfm_layer` to use frame-alloc vectors + RMSNorm + gated FFN | Replace km_ slot usage with frame-allocated raw addresses for d>1024. Use km_rmsnorm instead of km_layernorm. Use tfm_ffn_gated instead of 2-matrix FFN. |

**Gate:** `nova> infer hello` with test model works through new code path.

---

### Phase C: Grouped Query Attention (GQA)

**Why:** Gemma 3 uses 4 query heads sharing 1 KV head. Current code assumes n_heads == n_kv_heads.

| Task | Description | Verification |
|------|-------------|-------------|
| C1 | Add GQA support to `tfm_attention` | Q has 4 heads (4×256=1024 total), K/V have 1 head (1×256). Each of the 4 query heads attends to the SAME K/V. Broadcast KV across all query heads. |
| C2 | Update QKV projection sizes | Q: d_model→n_heads×d_head (1152→1024). K: d_model→n_kv_heads×d_head (1152→256). V: d_model→n_kv_heads×d_head (1152→256). O: n_heads×d_head→d_model (1024→1152). Four separate weight matrices. |
| C3 | Update KV cache for GQA | Store only n_kv_heads × d_head = 1×256 = 256 dims per position per layer (not d_model=1152). Reduces KV cache 4.5x compared to storing full d_model. |
| C4 | Update .fjm v2 format for GQA weights | Header: add `n_kv_heads` field (was implicit == n_heads). Per-layer: separate sizes for Q, K, V, O projections. |

**Gate:** Attention with 4Q:1KV produces correct output — each Q head gets same context from shared KV.

---

### Phase D: Rotary Position Embedding (RoPE)

**Why:** Gemma 3 uses RoPE with theta=1,000,000 instead of learned position embeddings.

| Task | Description | Verification |
|------|-------------|-------------|
| D1 | Implement `tfm_rope_apply(q_addr, k_addr, pos, head_dim, theta)` | For each pair (x[2i], x[2i+1]): x' = x·cos(θᵢ) - y·sin(θᵢ), y' = x·sin(θᵢ) + y·cos(θᵢ). Where θᵢ = pos / (theta^(2i/d)). Apply to EACH head independently. |
| D2 | Pre-compute sin/cos lookup table | Fixed-point x10000 for positions 0..2048 (demo context) and 128 frequency bins. Table at dedicated memory (frame-allocated, ~130 KB). Compute once at model-load time. |
| D3 | Dual RoPE frequencies | Local layers (15 of 26): theta=10,000 (rope_local_base_freq). Global layers (layers at 5,11,17,23): theta=1,000,000. Select theta based on layer index. |
| D4 | Integrate RoPE into tfm_layer | After Q/K projection, before attention score computation: apply RoPE to Q and K per head. |

**Gate:** Token at pos=0 and pos=10 produce different attention patterns (position-aware).

---

### Phase E: Hybrid Sliding Window + Global Attention

**Why:** Gemma 3 alternates 512-token local sliding window with full global attention.

| Task | Description | Verification |
|------|-------------|-------------|
| E1 | Add `tfm_is_global_layer(layer_idx)` | Pattern: every 6th layer is global. For 26 layers: globals at 5, 11, 17, 23 (4 global, 22 local). |
| E2 | Modify attention score loop for sliding window | For local layers: attend to positions `max(0, cur_pos - 512)..cur_pos` only. For global layers: attend to all positions `0..cur_pos`. |
| E3 | Dual KV cache strategy | Local layers: ring buffer of 512 entries (reuse positions). Global layers: full linear buffer. Reduces total KV memory. |

**Gate:** Local layer at pos=600 attends only to pos 88-600. Global layer attends 0-600.

---

### Phase F: Large Vocabulary + Extended Memory Mapping

**Why:** 262K vocab embedding/LM-head + d=1152 vectors need addresses above 128 MB.

| Task | Description | Verification |
|------|-------------|-------------|
| F1 | **Extend identity mapping to 1 GB** | Add PDPT entries for 128 MB-1 GB in paging.fj. Map as RW+NX (data, not code). Called during kernel_main init. |
| F2 | Update frame allocator for 1 GB | TOTAL_FRAMES: 32768→262144. BITMAP_SIZE: 4096→32768. Relocate bitmap if needed or use 2-level bitmap. |
| F3 | Frame-allocate embedding table | 75 MB embedding loaded from NVMe into contiguous frames above 128 MB. `mdl_load_embed()` updated for large-address support. |
| F4 | Frame-allocate LM head weights | 75 MB LM head at separate contiguous region. |
| F5 | Implement `tfm_argmax_raw(addr, count)` | Argmax over 262K i64 values at raw address (not km_ slot). Hierarchical: max per 4096-element block, then max of 64 block winners. |
| F6 | Export Gemma 3 tokenizer to .fjt | `export_tokenizer.py --model google/gemma-3-1b-it -o gemma3.fjt --write-disk disk.img --lba 2000`. 262K entries. Load from NVMe. |
| F7 | NVMe-based tokenizer loading | `tok_load_nvme(start_lba)` — read .fjt from NVMe into frame-allocated memory. |

**Gate:** `nova> tokenize hello` with Gemma 3 tokenizer produces correct token IDs.

---

### Phase G: Updated Export Scripts + .fjm v2 Format

**Why:** Gemma 3 1B has different weight layout (GQA, gated FFN, RMSNorm, RoPE).

| Task | Description | Verification |
|------|-------------|-------------|
| G1 | Define .fjm v2 header (96 bytes) | Add fields: `n_kv_heads` (4B), `ffn_type` (4B: 0=standard, 1=gated), `norm_type` (4B: 0=LN, 1=RMSNorm), `rope_theta` (8B), `gate_proj_size` (4B), `up_proj_size` (4B), `o_proj_size` (4B). Bump version to 2. |
| G2 | Update `export_fjm.py` for Gemma 3 1B | Extract: `q_proj`, `k_proj`, `v_proj`, `o_proj` separately. Extract `gate_proj`, `up_proj`, `down_proj` (3 FFN matrices). Extract RMSNorm `weight` (gamma only, no beta). Apply Lloyd-Max quantization per matrix. |
| G3 | Write Gemma 3 1B weights to NVMe disk image | `python export_fjm.py --model google/gemma-3-1b-it --bits 2 -o gemma3.fjm --write-disk disk.img --lba 0`. Total: ~250 MB on disk. |
| G4 | Update `model_loader.fj` for .fjm v2 | Parse v2 header. Load Q/K/V/O projections as separate weight blocks. Load 3 FFN matrices. Load RMSNorm gamma only (skip beta). Support model_type=10 for Gemma 3 1B. |
| G5 | Update test model to .fjm v2 format | `mdl_create_test_model()` generates v2 with: d=32, 4 layers, 4Q:1KV, head_dim=8, ffn_dim=128 gated, RMSNorm. Small enough for RamFS (~8 KB). |

**Gate:** `nova> model-load test` loads v2 format. `model-info` shows: GQA 4:1, gated FFN, RMSNorm.

---

### Phase H: End-to-End Integration + Real Weights

| Task | Description | Verification |
|------|-------------|-------------|
| H1 | Prepare NVMe disk image with Gemma 3 1B data | Host-side: export .fjm (250 MB) + .fjt (4 MB) to disk.img. |
| H2 | Load Gemma 3 1B from NVMe | `nova> model-load nvme 0` loads 250 MB of weights across extended memory. |
| H3 | Load Gemma 3 tokenizer from NVMe | `nova> tok-load nvme 2000` loads 262K token table into frame-allocated memory. |
| H4 | Run single-token inference | `nova> infer "The capital of France is"` → produces meaningful next token (e.g., "Paris"). |
| H5 | Run multi-token generation | `nova> ask "What is 2+2?"` → generates coherent multi-word response with streaming. |
| H6 | Performance measurement + optimization | Measure tokens/sec. Profile: embedding lookup, matmul, attention, FFN. Identify bottleneck. |
| H7 | Stress test: 128-token generation | Generate 128 tokens continuously. Verify: no KV overflow, no memory corruption, stable output. |
| H8 | Quality validation | Run 10 diverse prompts. Compare output quality against PyTorch reference. Document any quantization artifacts. |

**Gate:** `nova> ask "What is 2+2?"` → coherent, correct answer from Gemma 3 1B in kernel Ring 0.

---

## Execution Order + Dependencies

```
Phase A (bug fixes) ──────────────────┐
                                      │
Phase B (RMSNorm + gated FFN          │
         + frame-alloc vectors) ──────┤
                                      │
Phase C (GQA attention) ──────────────┤
                                      ├──→ Phase G (export scripts v2)
Phase D (RoPE) ───────────────────────┤              │
                                      │              ├──→ Phase H (E2E real weights)
Phase E (sliding window) ─────────────┤              │
                                      │              │
Phase F (large vocab + extended       │              │
         memory mapping) ─────────────┘──────────────┘
```

**Critical path:** A → B → G5 (test model v2) → verify all phases → G2-G3 (export) → H (real weights)

**Parallel work:**
- C, D, E are independent of each other (all modify transformer.fj but different functions)
- F is independent of B-E (memory infrastructure)
- G1-G4 depend on B-F being architecturally defined

**Estimated sessions:** 4-5 sessions total (A+B: 1 session, C+D+E: 1-2 sessions, F+G: 1 session, H: 1 session)

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| d=1152 frame-alloc performance | Slower than km_ slot (cache miss) | Frame addresses are contiguous; modern CPUs prefetch well |
| FFN dim=6912 matmul too slow | >5s per token for 26 layers | Tile matmul, consider 4-bit quant (reduces multiply count 2x) |
| RoPE sin/cos fixed-point precision | Wrong position encoding | Use x10000 scale (not x1000) for trig; validate against PyTorch |
| 262K vocab argmax too slow | >500ms per token just for LM head | Hierarchical argmax + early termination (top-K tracking) |
| 2-bit quantization quality insufficient | Incoherent output | Fallback to 3-bit (~375 MB, still fits) or 4-bit (~500 MB, tight) |
| Extended identity mapping breaks boot | Triple fault | Map incrementally; test each 128 MB region separately |
| head_dim=256 dot product overflow | Accumulating 256 terms of (qi*ki)/1000 | Max per term: ~1e6. 256 terms: ~2.5e8. Safe for i64. |
| NVMe 250 MB load too slow | >30s boot time | Lazy load: load layers on-demand during first inference |

---

## Success Criteria

| Milestone | Criteria | Phase |
|-----------|---------|-------|
| **M1: Bug-free base** | Audit fixes applied, all commands work | A |
| **M2: New architecture** | RMSNorm + GQA + RoPE + gated FFN + sliding window work with test model | B-E |
| **M3: Extended memory** | 1 GB identity mapped, frame allocator manages full range | F |
| **M4: Export pipeline** | .fjm v2 + .fjt exported for Gemma 3 1B on NVMe disk | G |
| **M5: First real token** | `infer` produces meaningful token with Gemma 3 1B weights | H4 |
| **M6: First conversation** | `ask` generates coherent multi-word response | H5 |
| **M7: Production** | 128-token generation, 10 quality-validated prompts, no crashes | H7-H8 |

---

## What Makes This Unique

No other operating system has:

1. **Kernel-native 1B-parameter LLM** — Gemma 3 1B running entirely in Ring 0
2. **IFEval 80% in the kernel** — instruction-following quality rivaling early GPT-3.5
3. **2-bit quantized inference** — FajarQuant innovations (PCA rotation, fused attention)
4. **Attention-based process scheduler** — the kernel uses transformer attention for scheduling
5. **Single-binary AI OS** — kernel + ML runtime + quantization + 1B model = one ELF
6. **Zero syscall overhead** — inference runs at kernel privilege, no context switches

---

*Gemma 3 1B Upgrade Plan v2.0*
*Target: FajarOS — world's first OS with kernel-native Gemma 3 1B inference (IFEval 80.2%)*
*Model: 1B params, 26 layers, d=1152, GQA 4:1, 2-bit quantized, ~250 MB, Ring 0*
*QEMU: 1 GB RAM (host: 31 GB), KVM + Skylake*
*Updated: 2026-04-08*
