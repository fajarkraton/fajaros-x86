# Gemma 3 270M Upgrade Plan — FajarOS Kernel-Native LLM

> **Version:** 1.0 (2026-04-08)
> **Author:** Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id)
> **Model:** Claude Opus 4.6 exclusively
> **Goal:** Upgrade FajarOS from SmolLM-135M test model to real Gemma 3 270M inference
> **Status:** PLANNING

---

## Executive Summary

FajarOS Phase 1-8 pipeline is complete with a test model (d=16, 2 layers).
This plan upgrades to **Google Gemma 3 270M** — the best sub-500M model per April 2026.

**End state:** `nova> ask "What is 2+2?"` runs Gemma 3 270M entirely inside the kernel,
producing coherent English responses at ~1 token/sec in QEMU.

---

## Gemma 3 270M Architecture (exact from config.json)

```
hidden_size:          640          # d_model
num_hidden_layers:    18           # transformer layers
num_attention_heads:  4            # query heads
num_key_value_heads:  1            # KV heads (GQA, 4:1 ratio)
head_dim:             256          # per-head dimension
intermediate_size:    2048         # FFN intermediate
vocab_size:           262144       # 256K tokens
max_position_embeddings: 32768    # 32K context
rms_norm_eps:         1e-06        # RMSNorm epsilon
rope_theta:           1000000.0    # RoPE base frequency
sliding_window:       512          # local attention window
sliding_window_pattern: 6         # every 6th layer is global
hidden_activation:    gelu_pytorch_tanh
attention_bias:       false
EOS token:            1
BOS token:            2
```

### Key Differences from SmolLM-135M

| Feature | SmolLM-135M | Gemma 3 270M | Impact |
|---------|------------|--------------|--------|
| d_model | 768 | 640 | Smaller, fits km_ slots |
| Layers | 12 | 18 | +50% layers |
| Attention | MHA (12 heads) | **GQA (4Q:1KV)** | Major: shared KV heads |
| head_dim | 64 | **256** | 4x larger heads |
| FFN | 2-matrix (3072) | **3-matrix gated (2048)** | GeGLU: gate*up→down |
| Norm | LayerNorm | **RMSNorm** | Simpler (no mean/beta) |
| Position | Learned | **RoPE** | Rotary embeddings |
| Attention type | Full | **Hybrid sliding+global** | Window=512, global every 6th |
| Vocab | 49K | **262K** | 5x larger, needs frame-alloc |
| Activation | GELU | **gelu_pytorch_tanh** | Different approximation |
| Context | 2048 | 32768 | 16x larger |

### Memory Budget (2-bit quantization, 512MB QEMU)

```
Component                    Size        Cumulative
──────────────────────────   ─────       ──────────
Kernel ELF (.text+.data)     2 MB        2 MB
System (pages, drivers)      6 MB        8 MB
Embedding table (2-bit)      42 MB       50 MB
18 layers (2-bit each ~1.4M) 25 MB       75 MB
LM head (2-bit)              42 MB       117 MB
KV cache (512 ctx, 2-bit)    1 MB        118 MB
Tokenizer table              4 MB        122 MB
Free                         390 MB      512 MB
```

---

## Implementation Phases

### Phase A: Remaining Bug Fixes (from audit)

| Task | File | Description |
|------|------|-------------|
| A1 | fajarquant.fj | Fix PCA rotation overflow: clamp intermediate products |
| A2 | kmatrix.fj | Fix LayerNorm variance precision: accumulate then divide |
| A3 | pipeline.fj | Fix noise calculation for negative seed values |
| A4 | model_loader.fj | Add header offset validation (embed_off < total_size) |
| A5 | tokenizer.fj | Add output buffer bounds check in tok_encode |

**Gate:** All existing tests still pass, no new crashes.

---

### Phase B: RMSNorm + Gated FFN (Architecture Core)

**Why first:** These are used by every layer, must be correct before anything else.

| Task | Description | Verification |
|------|-------------|-------------|
| B1 | Add `km_rmsnorm(slot, dim, gamma_addr)` to kmatrix.fj | RMSNorm(x) = x * rsqrt(mean(x²)+eps) * gamma. No mean subtraction, no beta. Test: rmsnorm([1,2,3,4]) matches PyTorch. |
| B2 | Add `km_gelu_tanh(slot, dim)` to kmatrix.fj | GELU_tanh(x) = 0.5*x*(1+tanh(sqrt(2/pi)*(x+0.044715*x³))). More accurate than current sigmoid approx. |
| B3 | Add gated FFN to transformer.fj | `ffn = down_proj(gelu(gate_proj(x)) * up_proj(x))`. Three weight matrices instead of two. Gate and up are both 640→2048. |
| B4 | Frame-allocate FFN intermediate buffer | 2048 elements > km_ slot max 1024. Use `frame_alloc_contiguous()` for FFN scratch. Allocate once per inference session. |

**Gate:** `nova> infer hello` with test model still works with new norm/FFN path.

---

### Phase C: Grouped Query Attention (GQA)

**Why:** Gemma 3 uses 4 query heads but only 1 KV head. Current code assumes n_heads == n_kv_heads.

| Task | Description | Verification |
|------|-------------|-------------|
| C1 | Add GQA support to `tfm_attention` | Q has 4 heads (4×256=1024 dims), K/V have 1 head (1×256=256 dims). Each Q head attends to the same K/V. Broadcast KV across query groups. |
| C2 | Update QKV projection sizes | Q projection: 640→1024 (4 heads×256). K projection: 640→256 (1 head×256). V projection: 640→256. O projection: 1024→640. |
| C3 | Update KV cache for GQA | Store only 1 KV head per layer per position (256 dims, not 640). Reduces KV cache 4x. |
| C4 | Update .fjm format for GQA weights | Header: add n_kv_heads field. Layer block: separate Q/K/V/O weight sizes. |

**Gate:** Attention with 4Q:1KV produces same result as broadcasting manually.

---

### Phase D: Rotary Position Embedding (RoPE)

**Why:** Gemma 3 uses RoPE instead of learned position embeddings.

| Task | Description | Verification |
|------|-------------|-------------|
| D1 | Implement `tfm_rope_apply(q_addr, k_addr, pos, d_head)` | Apply rotary embedding to Q and K vectors. For each pair (x[2i], x[2i+1]): x_rot = x*cos(θ) - y*sin(θ), y_rot = x*sin(θ) + y*cos(θ). θ = pos / (theta^(2i/d)). |
| D2 | Pre-compute sin/cos table | Fixed-point sin/cos for positions 0..512 and frequencies. Store at dedicated memory address. |
| D3 | Dual RoPE frequencies | Local layers: theta=10000. Global layers: theta=1000000. Select based on layer index. |
| D4 | Integrate into tfm_layer | Apply RoPE to Q and K after projection, before attention score computation. |

**Gate:** RoPE(pos=0) ≈ identity. RoPE(pos=N) produces position-dependent rotation.

---

### Phase E: Hybrid Sliding Window + Global Attention

**Why:** Gemma 3 alternates between 512-token sliding window (local) and full attention (global).

| Task | Description | Verification |
|------|-------------|-------------|
| E1 | Add `tfm_is_global_layer(layer)` | Returns 1 for layers 5, 11, 16 (pattern: every 6th layer). Returns 0 for local layers. |
| E2 | Modify attention to respect sliding window | For local layers: only attend to positions max(0, cur_pos-512)..cur_pos. For global layers: attend to all positions 0..cur_pos. |
| E3 | Optimize local KV cache | Local layers only need 512 positions in cache (ring buffer). Global layers need full context. |

**Gate:** Local layer at pos=600 only reads KV cache positions 88-600. Global layer reads 0-600.

---

### Phase F: Large Vocabulary Support (262K tokens)

**Why:** Embedding table and LM head are 262K entries — too large for km_ slots.

| Task | Description | Verification |
|------|-------------|-------------|
| F1 | Frame-allocate embedding table | `frame_alloc_contiguous(N)` for 42MB embedding. Load from NVMe on `model-load`. |
| F2 | Frame-allocate logits buffer | 262K×8 bytes = 2MB for logits output. Allocate once per inference. |
| F3 | Implement `tfm_embed_lookup_large(token_id)` | Direct memory read from frame-allocated embedding, dequantize into km_ slot. |
| F4 | Implement `tfm_lmhead_large(x_slot)` | Quantized matmul against frame-allocated LM head weights, write logits to frame-allocated buffer. |
| F5 | Implement `tfm_argmax_large(logits_addr, vocab_size)` | Argmax over 262K logits from raw memory address (not km_ slot). |
| F6 | Export Gemma 3 tokenizer to .fjt | Use `export_tokenizer.py --model google/gemma-3-270m-it`. 262K entries. Load via NVMe (too large for RamFS). |

**Gate:** `nova> tokenize hello` produces correct Gemma 3 token IDs.

---

### Phase G: Updated Export Scripts + .fjm v2 Format

**Why:** Gemma 3 has different weight layout (GQA, gated FFN, RMSNorm gamma only).

| Task | Description | Verification |
|------|-------------|-------------|
| G1 | Update .fjm header to v2 | Add: n_kv_heads, ffn_type (0=standard, 1=gated), norm_type (0=LN, 1=RMSNorm), rope_theta. Bump version to 2. |
| G2 | Update `export_fjm.py` for Gemma 3 | Extract Q/K/V/O projections separately (not concatenated QKV). Extract gate_proj/up_proj/down_proj. Extract RMSNorm gamma (no beta). |
| G3 | Write Gemma 3 weights to NVMe disk image | `python export_fjm.py --model google/gemma-3-270m-it --bits 2 -o gemma3.fjm --write-disk disk.img --lba 0` |
| G4 | Update `model_loader.fj` for .fjm v2 | Parse new header fields. Load GQA weights. Load gated FFN (3 matrices). Load RMSNorm gamma (no beta). |
| G5 | Create test model v2 | Update `mdl_create_test_model()` to generate .fjm v2 format with GQA + gated FFN. Small: d=16, 2 layers, 4Q:1KV, gated FFN. |

**Gate:** `nova> model-load test` with v2 format loads correctly, `model-info` shows GQA heads.

---

### Phase H: End-to-End Integration + Real Weights

| Task | Description | Verification |
|------|-------------|-------------|
| H1 | Load Gemma 3 270M from NVMe | `nova> model-load nvme 0` loads 105MB of weights. |
| H2 | Load Gemma 3 tokenizer from NVMe | `nova> tok-load nvme 1000` loads 262K token table. |
| H3 | Run inference with real weights | `nova> infer "The capital of France is"` → produces meaningful next token. |
| H4 | Run generation with real weights | `nova> ask "What is 2+2?"` → generates coherent multi-token response. |
| H5 | Performance measurement | Measure tokens/sec. Target: ≥0.5 tok/s in QEMU KVM. |
| H6 | Stress test: 128-token context | Generate 128 tokens, verify no KV cache overflow, no crash. |

**Gate:** `nova> ask "What is 2+2?"` → coherent answer with real Gemma 3 270M weights.

---

## Execution Order + Dependencies

```
Phase A (bug fixes) ─────────────┐
                                 │
Phase B (RMSNorm + gated FFN) ───┤
                                 ├──→ Phase G (export scripts)
Phase C (GQA attention) ─────────┤         │
                                 ├──→ Phase H (real weights E2E)
Phase D (RoPE) ──────────────────┤
                                 │
Phase E (sliding window) ────────┤
                                 │
Phase F (large vocab) ───────────┘
```

Phases A-F are independent and can be done in any order.
Phase G depends on B-F (export must match new architecture).
Phase H depends on all phases (end-to-end test).

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Fixed-point precision insufficient for RoPE sin/cos | Wrong position encoding | Use scaled i64 (x10000) for sin/cos, or pre-compute table |
| 262K vocab argmax too slow | >1s per token just for argmax | Hierarchical argmax: find max per 1024-element block, then max of maxes |
| 2-bit Gemma 3 quality too low | Incoherent output | Try 3-bit (158MB, still fits) or 4-bit (210MB) |
| head_dim=256 causes overflow in dot product | Wrong attention scores | Accumulate in chunks of 64, divide early |
| QEMU KVM too slow for 18-layer inference | >10s per token | Optimize matmul, consider AVX2 via LLVM intrinsics |
| 42MB embedding load from NVMe too slow | Long boot time | Lazy load: only load on first `ask` command |

---

## Success Criteria

| Milestone | Criteria |
|-----------|---------|
| **M1: Architecture ready** | Phases A-F done, test model works with new architecture |
| **M2: Export ready** | Phase G done, .fjm v2 + .fjt exported for Gemma 3 |
| **M3: First real token** | Phase H3, `infer` produces meaningful token with real weights |
| **M4: First conversation** | Phase H4, `ask` generates coherent multi-word response |
| **M5: Production** | 128-token generation, no crashes, ≥0.5 tok/s |

---

*Gemma 3 270M Upgrade Plan v1.0*
*Target: FajarOS becomes the world's first OS with kernel-native Gemma 3 inference*
*Model: 270M params, 2-bit quantized, ~105 MB total, fully in Ring 0*
