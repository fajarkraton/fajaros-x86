# Gemma 3 1B Export Script — Design Notes

**Status:** Planning. To be implemented as `scripts/export_gemma3_v7.py`.
**Template:** `scripts/export_smollm_v6.py` (258 LOC, 4-bit per-matrix codebooks)

## Model Source

```bash
# Requires HF access token (Gemma license acceptance)
huggingface-cli login
huggingface-cli download google/gemma-3-1b-pt \
  --include "*.safetensors" "config.json" "tokenizer*" \
  --local-dir models/gemma3-1b
```

## Architecture Differences from SmolLM v6

| Parameter | SmolLM-135M | Gemma 3 1B | Kernel Impact |
|-----------|-------------|------------|---------------|
| Layers | 30 | **26** | Fewer iterations |
| d_model | 576 | **1152** | Use KM_GEMMA pool (v3.3.0) |
| d_head | 64 | **256** | 4x attention dot product |
| n_heads | 9 | **4** (Q) | GQA |
| n_kv_heads | 3 | **1** | GQA ratio 4:1 |
| ffn_dim | 1536 | **6912** | Gated FFN (already in transformer.fj) |
| vocab | 49,152 | **262,144** | Tokenizer supports up to 262,200 |
| rope_theta_local | 10,000 | **10,000** | Same |
| rope_theta_global | N/A | **1,000,000** | Existing dual-theta code |
| sliding_window | N/A | **512** tokens | Already in transformer.fj |
| global_pattern | N/A | **every 6 layers** | Already supported |
| max_context | 2,048 | **32,768** | KV cache expansion needed |
| norm_type | RMSNorm | **RMSNorm (1+γ)** | kmatrix.fj has dual-mode |

## .fjm v7 Format (Proposed)

Based on v6 structure, but v7 header adds:
- `rope_theta_global` (8 bytes at offset 152)
- `sliding_window` (4 bytes at offset 160)
- `global_layer_period` (4 bytes at offset 164)
- `n_kv_heads` (4 bytes at offset 168)

v7 header total: 176 bytes (v6 was 160).

## Export Pipeline

1. Load safetensors shards via `safetensors.torch.load_file`
2. Extract weights by layer: `model.layers.{i}.{type}.weight`
3. For each weight matrix:
   - Reshape to `(d_out, d_in)` row-major
   - K-means on rows → 16 centroids (4-bit)
   - Pack indices as 4-bit per element
4. Write v7 header with model dimensions
5. Write embed codebook + packed indices
6. For each layer: write 7 codebooks + packed weights
7. Write final norm + LM head

## Expected Output Size

- Embed: 262,144 × 1152 × 0.5 bytes = **151 MB**
- Layers: 26 × (~6 MB packed weights + 896B codebooks) = **~156 MB**
- LM head: 262,144 × 1152 × 0.5 bytes = **151 MB** (same as embed if tied)
- **Total: ~460 MB at 4-bit** (fits in 1 GB QEMU with 540 MB free for KV)

## Quality Testing

After export, validate:
1. First token prediction matches HF reference ± epsilon
2. Perplexity on WikiText-2 test < 20 (comparable to HF FP16)
3. IFEval sample passes at 4-bit (Gemma 3 baseline: 80.2%)

## Integration Points

- Model loader: add `fjm_version == 7` branch in `mdl_parse_header`
- Existing v6 codebook path works (inherited for v7)
- New fields accessed via `mdl_get_rope_theta_global()`, etc.

## Effort

~1 week dedicated (model download → export → .fjm generation → kernel test).
Prerequisites (all done): GQA, dual-theta RoPE, sliding window, 262K vocab cap,
1280-dim tensor pool, v6 template to clone.
