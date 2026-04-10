#!/usr/bin/env python3
"""
export_fjm.py — Convert HuggingFace model to .fjm v3 (Fajar Model) binary format.

v3 changes (production quality):
  - Header extended to 160 bytes (was 96)
  - Embed codebook + LM-head codebook stored in header
  - Shared codebook per layer (all matrices use same centroids)
  - Final RMSNorm weights exported (model.norm before LM head)
  - O projection included in layer data

Usage:
    python export_fjm.py --test-model -o test.fjm
    python export_fjm.py --model unsloth/gemma-3-1b-it --bits 2 -o gemma3.fjm

Author: Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id)
"""

import argparse
import struct
import sys
import numpy as np
from pathlib import Path

FJM_MAGIC = 0x314D4A46  # "FJM1"
FJM_HEADER_V1_SIZE = 64
FJM_HEADER_V3_SIZE = 160  # v3: extended with embed_cb + lmhead_cb + final_norm_off
FJM_LAYER_HDR_SIZE = 16

MODEL_TYPES = {
    "test": 0,
    "HuggingFaceTB/SmolLM-135M": 1,
    "google/gemma-3-1b-it": 10,
    "google/gemma-3-270m-it": 11,
    "unsloth/gemma-3-1b-it": 10,
    "unsloth/gemma-3-270m-it": 11,
}


def lloyd_max_quantize(data, bits, max_iters=50):
    """Lloyd-Max quantization with L2 distance. Returns (indices, centroids)."""
    n_centroids = 2 ** bits
    flat = data.flatten().astype(np.float32)
    n = len(flat)

    # Use larger sample for centroid initialization (5M or full data)
    sample_size = min(5_000_000, n)
    sample = flat[np.random.choice(n, sample_size, replace=False)] if n > sample_size else flat

    percentiles = np.linspace(0, 100, n_centroids + 2)[1:-1]
    centroids = np.percentile(sample, percentiles).astype(np.float32)

    chunk_size = 2_000_000
    prev_centroids = centroids.copy()
    for iteration in range(max_iters):
        indices = np.empty(n, dtype=np.int32)
        for start in range(0, n, chunk_size):
            end = min(start + chunk_size, n)
            # L2 distance (squared) — minimizes MSE
            dists = (flat[start:end, None] - centroids[None, :]) ** 2
            indices[start:end] = np.argmin(dists, axis=1)
        for i in range(n_centroids):
            mask = indices == i
            if mask.any():
                centroids[i] = flat[mask].mean()
        # Early stopping if converged
        if np.allclose(centroids, prev_centroids, atol=1e-7):
            break
        prev_centroids = centroids.copy()

    # Final assignment with L2
    indices = np.empty(n, dtype=np.int32)
    for start in range(0, n, chunk_size):
        end = min(start + chunk_size, n)
        dists = (flat[start:end, None] - centroids[None, :]) ** 2
        indices[start:end] = np.argmin(dists, axis=1)

    return indices.astype(np.uint8), centroids


def quantize_with_codebook(data, centroids, bits):
    """Quantize data using pre-computed codebook centroids (L2 distance)."""
    flat = data.flatten().astype(np.float32)
    n = len(flat)
    indices = np.empty(n, dtype=np.int32)
    chunk_size = 2_000_000
    for start in range(0, n, chunk_size):
        end = min(start + chunk_size, n)
        dists = (flat[start:end, None] - centroids[None, :]) ** 2
        indices[start:end] = np.argmin(dists, axis=1)
    return indices.astype(np.uint8)


def pack_quantized(indices, bits):
    elems_per_byte = 8 // bits
    mask = (1 << bits) - 1
    n_bytes = (len(indices) + elems_per_byte - 1) // elems_per_byte
    result = bytearray(n_bytes)
    for i, idx in enumerate(indices):
        byte_idx = i // elems_per_byte
        bit_off = (i % elems_per_byte) * bits
        result[byte_idx] |= (int(idx) & mask) << bit_off
    return bytes(result)


def serialize_codebook(centroids):
    """Serialize codebook centroids as i64 values (x1000 fixed-point)."""
    data = b""
    for c in centroids:
        data += struct.pack("<q", int(c * 1000))
    return data


def build_v3_header(model_type, n_layers, d_model, n_heads, d_head, vocab_size,
                     bits, total_size, embed_off, layer0_off, lmhead_off,
                     n_kv_heads=0, ffn_type=0, norm_type=0, ffn_dim=0,
                     rope_theta=0, eos_token=2, final_norm_off=0,
                     embed_cb=None, lmhead_cb=None):
    """Build 160-byte v3/v4 header with embedded codebooks.
    v4: per-matrix codebooks (7 per layer instead of 1 shared)."""
    # Bytes 0-75: standard v2 fields (19 × u32 = 76 bytes)
    header = struct.pack("<19I",
        FJM_MAGIC, 4,  # magic + version=4 (per-matrix codebooks)
        model_type, n_layers, d_model, n_heads, d_head,
        vocab_size, bits, total_size, embed_off, layer0_off, lmhead_off,
        n_kv_heads, ffn_type, norm_type, ffn_dim,
        rope_theta // 1000 if rope_theta > 0 else 0,
        eos_token,
    )
    # Bytes 76-107: embed codebook (4 centroids × 8 bytes = 32 bytes for 2-bit)
    if embed_cb is not None:
        header += serialize_codebook(embed_cb)
    else:
        header += b"\x00" * 32
    # Bytes 108-139: lmhead codebook (32 bytes)
    if lmhead_cb is not None:
        header += serialize_codebook(lmhead_cb)
    else:
        header += b"\x00" * 32
    # Bytes 140-143: final_norm_off (u32)
    header += struct.pack("<I", final_norm_off)
    # Bytes 144-159: reserved
    header += b"\x00" * (FJM_HEADER_V3_SIZE - len(header))
    assert len(header) == FJM_HEADER_V3_SIZE, f"Header size mismatch: {len(header)} != {FJM_HEADER_V3_SIZE}"
    return header


def export_gemma3(model_name, bits):
    """Export Gemma 3 model to .fjm v3 format with production-quality codebooks."""
    try:
        from transformers import AutoModelForCausalLM, AutoConfig
        import torch
    except ImportError:
        print("ERROR: pip install transformers torch")
        sys.exit(1)

    print(f"Loading {model_name}...")
    config = AutoConfig.from_pretrained(model_name)
    model = AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float32)
    model.eval()

    n_layers = config.num_hidden_layers
    d_model = config.hidden_size
    n_heads = config.num_attention_heads
    n_kv_heads = getattr(config, 'num_key_value_heads', n_heads)
    d_head = getattr(config, 'head_dim', d_model // n_heads)
    vocab_size = config.vocab_size
    ffn_dim = config.intermediate_size
    rope_theta = int(getattr(config, 'rope_theta', 0))
    if rope_theta == 0 and hasattr(config, 'rope_scaling'):
        rs = config.rope_scaling
        if isinstance(rs, dict):
            if 'full_attention' in rs:
                rope_theta = int(rs['full_attention'].get('rope_theta', 0))
            elif 'rope_theta' in rs:
                rope_theta = int(rs['rope_theta'])
    eos_token = getattr(config, 'eos_token_id', 2)
    if isinstance(eos_token, list):
        eos_token = eos_token[0]

    is_gated = hasattr(model.model.layers[0].mlp, 'gate_proj')
    model_type = MODEL_TYPES.get(model_name, 99)

    print(f"Model: {n_layers}L d={d_model} {n_heads}Q:{n_kv_heads}KV d_head={d_head}")
    print(f"FFN: {'gated' if is_gated else 'standard'} dim={ffn_dim}")
    print(f"Norm: RMSNorm, RoPE theta={rope_theta}")
    print(f"Quantizing to {bits}-bit (shared codebook per layer)...")

    # === Embedding (own codebook) ===
    embed_w = model.model.embed_tokens.weight.detach().numpy()
    embed_idx, embed_cb = lloyd_max_quantize(embed_w, bits)
    embed_packed = pack_quantized(embed_idx, bits)
    print(f"  Embedding: {embed_w.shape} → {len(embed_packed)} bytes (own codebook)")

    # RMSNorm gamma convention: stored as int(weight × 1000), no conversion.
    # Kernel detects model_type at load time and applies:
    #   Gemma (type 10/11):     (1 + g/1000) × x  — gamma is zero-centered (~0)
    #   Llama/SmolLM (type 1):  g/1000 × x        — gamma is direct scale (~0.03-1.4)
    is_gemma_norm = 'Gemma' in type(model.model.layers[0].input_layernorm).__name__
    print(f"  Norm convention: {'Gemma (zero-centered)' if is_gemma_norm else 'Llama (direct scale)'}")

    # === Layers (shared codebook per layer) ===
    layer_blocks = []
    for i in range(n_layers):
        layer = model.model.layers[i]

        q_w = layer.self_attn.q_proj.weight.detach().numpy().T
        k_w = layer.self_attn.k_proj.weight.detach().numpy().T
        v_w = layer.self_attn.v_proj.weight.detach().numpy().T
        o_w = layer.self_attn.o_proj.weight.detach().numpy().T

        if is_gated:
            gate_w = layer.mlp.gate_proj.weight.detach().numpy().T
            up_w = layer.mlp.up_proj.weight.detach().numpy().T
            down_w = layer.mlp.down_proj.weight.detach().numpy().T
        else:
            gate_w = layer.mlp.gate_proj.weight.detach().numpy().T
            down_w = layer.mlp.down_proj.weight.detach().numpy().T
            up_w = None

        # Per-matrix codebooks (v4): each matrix gets its own Lloyd-Max codebook
        # Order: Q=0, K=1, V=2, O=3, gate=4, up=5, down=6
        q_idx, q_cb = lloyd_max_quantize(q_w, bits)
        k_idx, k_cb = lloyd_max_quantize(k_w, bits)
        v_idx, v_cb = lloyd_max_quantize(v_w, bits)
        o_idx, o_cb = lloyd_max_quantize(o_w, bits)
        q_packed = pack_quantized(q_idx, bits)
        k_packed = pack_quantized(k_idx, bits)
        v_packed = pack_quantized(v_idx, bits)
        o_packed = pack_quantized(o_idx, bits)
        qkv_packed = q_packed + k_packed + v_packed + o_packed

        if is_gated:
            gate_idx, gate_cb = lloyd_max_quantize(gate_w, bits)
            up_idx, up_cb = lloyd_max_quantize(up_w, bits)
            down_idx, down_cb = lloyd_max_quantize(down_w, bits)
            ffn_packed = (pack_quantized(gate_idx, bits) +
                          pack_quantized(up_idx, bits) +
                          pack_quantized(down_idx, bits))
        else:
            gate_idx, gate_cb = lloyd_max_quantize(gate_w, bits)
            down_idx, down_cb = lloyd_max_quantize(down_w, bits)
            up_cb = gate_cb  # placeholder — not used
            ffn_packed = (pack_quantized(gate_idx, bits) +
                          pack_quantized(down_idx, bits))

        # RMSNorm gamma — store raw weight × 1000 (kernel handles convention)
        ln1_gamma = layer.input_layernorm.weight.detach().numpy().astype(np.float64)
        ln2_gamma = layer.post_attention_layernorm.weight.detach().numpy().astype(np.float64)
        norm_data = b""
        for arr in [ln1_gamma, ln2_gamma]:
            for v in arr:
                norm_data += struct.pack("<q", int(v * 1000))

        # Per-matrix codebooks: Q, K, V, O, gate, up, down (7 × 32B = 224B)
        cb_data = (serialize_codebook(q_cb) + serialize_codebook(k_cb) +
                   serialize_codebook(v_cb) + serialize_codebook(o_cb) +
                   serialize_codebook(gate_cb) + serialize_codebook(up_cb) +
                   serialize_codebook(down_cb))

        weight_data = qkv_packed + ffn_packed + norm_data + cb_data
        layer_hdr = struct.pack("<iiii",
            i, FJM_LAYER_HDR_SIZE + len(weight_data),
            len(qkv_packed), len(ffn_packed))
        layer_blocks.append(layer_hdr + weight_data)
        print(f"  Layer {i}: Q={len(q_packed)} K={len(k_packed)} V={len(v_packed)} O={len(o_packed)} FFN={len(ffn_packed)} cb=per-matrix(7)")

    # === Final RMSNorm (model.norm — applied AFTER last layer, BEFORE lm_head) ===
    final_norm_w = model.model.norm.weight.detach().numpy().astype(np.float64)
    final_norm_data = b""
    for v in final_norm_w:
        final_norm_data += struct.pack("<q", int(v * 1000))
    print(f"  Final norm: {len(final_norm_data)} bytes ({d_model} dims)")

    # === LM head (own codebook) ===
    lmhead_w = model.lm_head.weight.detach().numpy().T
    lmhead_idx, lmhead_cb = lloyd_max_quantize(lmhead_w, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)
    print(f"  LM head: {len(lmhead_packed)} bytes (own codebook)")

    # === Assemble ===
    embed_off = FJM_HEADER_V3_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    final_norm_off = layer0_off + layers_total
    lmhead_off = final_norm_off + len(final_norm_data)
    total_size = lmhead_off + len(lmhead_packed)

    header = build_v3_header(
        model_type, n_layers, d_model, n_heads, d_head, vocab_size, bits,
        total_size, embed_off, layer0_off, lmhead_off,
        n_kv_heads=n_kv_heads, ffn_type=1 if is_gated else 0,
        norm_type=1, ffn_dim=ffn_dim,
        rope_theta=rope_theta, eos_token=eos_token,
        final_norm_off=final_norm_off,
        embed_cb=embed_cb, lmhead_cb=lmhead_cb)

    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += final_norm_data
    fjm += lmhead_packed

    print(f"\nTotal: {total_size} bytes ({total_size/1024/1024:.1f} MB)")
    print(f"Header: {FJM_HEADER_V3_SIZE}B | Embed: {len(embed_packed)}B | Layers: {layers_total}B | FinalNorm: {len(final_norm_data)}B | LMHead: {len(lmhead_packed)}B")
    return fjm


def create_test_model(bits=2):
    """Create a tiny v3 test model with O projection + final norm."""
    n_layers, d_model, n_heads, n_kv_heads = 2, 16, 4, 1
    d_head, vocab_size, ffn_dim = 4, 64, 32
    q_dim, kv_d = n_heads * d_head, n_kv_heads * d_head
    rng = np.random.RandomState(42)

    # Embedding with own codebook
    embed_w = rng.randn(vocab_size, d_model).astype(np.float32)
    embed_idx, embed_cb = lloyd_max_quantize(embed_w, bits)
    embed_packed = pack_quantized(embed_idx, bits)

    layer_blocks = []
    for li in range(n_layers):
        # All layer weights
        q_w = rng.randn(d_model, q_dim).astype(np.float32)
        k_w = rng.randn(d_model, kv_d).astype(np.float32)
        v_w = rng.randn(d_model, kv_d).astype(np.float32)
        o_w = rng.randn(q_dim, d_model).astype(np.float32)
        gate_w = rng.randn(d_model, ffn_dim).astype(np.float32)
        up_w = rng.randn(d_model, ffn_dim).astype(np.float32)
        down_w = rng.randn(ffn_dim, d_model).astype(np.float32)

        # Per-matrix codebooks (v4)
        q_idx, q_cb = lloyd_max_quantize(q_w, bits)
        k_idx, k_cb = lloyd_max_quantize(k_w, bits)
        v_idx, v_cb = lloyd_max_quantize(v_w, bits)
        o_idx, o_cb = lloyd_max_quantize(o_w, bits)
        qkv_packed = (pack_quantized(q_idx, bits) + pack_quantized(k_idx, bits) +
                      pack_quantized(v_idx, bits) + pack_quantized(o_idx, bits))

        gate_idx, gate_cb = lloyd_max_quantize(gate_w, bits)
        up_idx, up_cb = lloyd_max_quantize(up_w, bits)
        down_idx, down_cb = lloyd_max_quantize(down_w, bits)
        ffn_packed = (pack_quantized(gate_idx, bits) + pack_quantized(up_idx, bits) +
                      pack_quantized(down_idx, bits))

        norm_data = b""
        for _ in range(2 * d_model):
            norm_data += struct.pack("<q", 0)  # gamma=0 → identity (1+0=1)
        cb_data = (serialize_codebook(q_cb) + serialize_codebook(k_cb) +
                   serialize_codebook(v_cb) + serialize_codebook(o_cb) +
                   serialize_codebook(gate_cb) + serialize_codebook(up_cb) +
                   serialize_codebook(down_cb))

        weight_data = qkv_packed + ffn_packed + norm_data + cb_data
        layer_hdr = struct.pack("<iiii",
            li, FJM_LAYER_HDR_SIZE + len(weight_data),
            len(qkv_packed), len(ffn_packed))
        layer_blocks.append(layer_hdr + weight_data)

    # Final norm (identity for test: gamma=0 → (1+0)=1)
    final_norm_data = b""
    for _ in range(d_model):
        final_norm_data += struct.pack("<q", 0)

    # LM head with own codebook
    lmhead_w = rng.randn(d_model, vocab_size).astype(np.float32)
    lmhead_idx, lmhead_cb = lloyd_max_quantize(lmhead_w, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)

    embed_off = FJM_HEADER_V3_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    final_norm_off = layer0_off + layers_total
    lmhead_off = final_norm_off + len(final_norm_data)
    total_size = lmhead_off + len(lmhead_packed)

    header = build_v3_header(
        0, n_layers, d_model, n_heads, d_head, vocab_size, bits,
        total_size, embed_off, layer0_off, lmhead_off,
        n_kv_heads=n_kv_heads, ffn_type=1, norm_type=1, ffn_dim=ffn_dim,
        rope_theta=1000000, eos_token=106, final_norm_off=final_norm_off,
        embed_cb=embed_cb, lmhead_cb=lmhead_cb)

    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += final_norm_data
    fjm += lmhead_packed

    print(f"Test v3: {n_layers}L d={d_model} {n_heads}Q:{n_kv_heads}KV gated={ffn_dim}")
    print(f"Total: {total_size} bytes ({total_size/1024:.1f} KB)")
    return fjm


def write_to_disk(data, disk_path, lba):
    offset = lba * 512
    disk = Path(disk_path)
    if not disk.exists():
        with open(disk_path, "wb") as f:
            f.write(b"\x00" * 64 * 1024 * 1024)
    with open(disk_path, "r+b") as f:
        f.seek(offset)
        f.write(data)
        remainder = len(data) % 512
        if remainder:
            f.write(b"\x00" * (512 - remainder))
    sectors = (len(data) + 511) // 512
    print(f"Written {len(data)} bytes to {disk_path} at LBA {lba} ({sectors} sectors)")


def main():
    parser = argparse.ArgumentParser(description="Export model to .fjm v3 format")
    parser.add_argument("--model", type=str, help="HuggingFace model name")
    parser.add_argument("--bits", type=int, default=2)
    parser.add_argument("--test-model", action="store_true")
    parser.add_argument("-o", "--output", type=str, required=True)
    parser.add_argument("--write-disk", type=str)
    parser.add_argument("--lba", type=int, default=0)
    args = parser.parse_args()

    if args.test_model:
        fjm = create_test_model(args.bits)
    elif args.model:
        fjm = export_gemma3(args.model, args.bits)
    else:
        parser.error("Specify --model or --test-model")

    with open(args.output, "wb") as f:
        f.write(fjm)
    print(f"Saved: {args.output}")

    if args.write_disk:
        write_to_disk(fjm, args.write_disk, args.lba)


if __name__ == "__main__":
    main()
