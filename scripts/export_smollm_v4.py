#!/usr/bin/env python3
"""
export_smollm_v4.py — Export SmolLM-135M to .fjm v4 with per-matrix codebooks.
Reads directly from safetensors cache (no torch/transformers needed).

Usage:
    python export_smollm_v4.py -o build/smollm_v4.fjm
    python export_smollm_v4.py -o build/smollm_v4.fjm --write-disk disk.img --lba 0
"""

import argparse
import struct
import sys
import os
import numpy as np

FJM_MAGIC = 0x314D4A46
FJM_HEADER_SIZE = 160

SMOLLM_PATH = os.path.expanduser(
    "~/.cache/huggingface/hub/models--HuggingFaceTB--SmolLM-135M/"
    "snapshots/1d461723eec654e65efdc40cf49301c89c0c92f4/model.safetensors"
)

# SmolLM-135M config
N_LAYERS = 30
D_MODEL = 576
N_HEADS = 9
N_KV_HEADS = 3
D_HEAD = 64
VOCAB_SIZE = 49152
FFN_DIM = 1536
ROPE_THETA = 10000
EOS_TOKEN = 0
MODEL_TYPE = 1  # SmolLM


def lloyd_max_quantize(data, bits, max_iters=50):
    """Lloyd-Max quantization with L2 distance."""
    n_centroids = 2 ** bits
    flat = data.flatten().astype(np.float32)
    n = len(flat)
    sample_size = min(5_000_000, n)
    sample = flat[np.random.choice(n, sample_size, replace=False)] if n > sample_size else flat
    percentiles = np.linspace(0, 100, n_centroids + 2)[1:-1]
    centroids = np.percentile(sample, percentiles).astype(np.float32)
    chunk_size = 2_000_000
    prev = centroids.copy()
    for _ in range(max_iters):
        indices = np.empty(n, dtype=np.int32)
        for s in range(0, n, chunk_size):
            e = min(s + chunk_size, n)
            dists = (flat[s:e, None] - centroids[None, :]) ** 2
            indices[s:e] = np.argmin(dists, axis=1)
        for i in range(n_centroids):
            mask = indices == i
            if mask.any():
                centroids[i] = flat[mask].mean()
        if np.allclose(centroids, prev, atol=1e-7):
            break
        prev = centroids.copy()
    indices = np.empty(n, dtype=np.int32)
    for s in range(0, n, chunk_size):
        e = min(s + chunk_size, n)
        dists = (flat[s:e, None] - centroids[None, :]) ** 2
        indices[s:e] = np.argmin(dists, axis=1)
    return indices.astype(np.uint8), centroids


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
    return b"".join(struct.pack("<q", int(c * 1000)) for c in centroids)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--bits", type=int, default=2)
    parser.add_argument("--write-disk", type=str)
    parser.add_argument("--lba", type=int, default=0)
    args = parser.parse_args()

    if not os.path.exists(SMOLLM_PATH):
        print(f"ERROR: SmolLM not found at {SMOLLM_PATH}")
        sys.exit(1)

    from safetensors import safe_open
    print(f"Loading SmolLM-135M from safetensors cache...")
    f = safe_open(SMOLLM_PATH, framework="numpy")
    bits = args.bits
    q_dim = N_HEADS * D_HEAD  # 576
    kv_d = N_KV_HEADS * D_HEAD  # 192

    # === Embedding ===
    embed_w = f.get_tensor("model.embed_tokens.weight")
    print(f"  Embedding: {embed_w.shape}")
    embed_idx, embed_cb = lloyd_max_quantize(embed_w, bits)
    embed_packed = pack_quantized(embed_idx, bits)
    print(f"    → {len(embed_packed)} bytes, cb: {[f'{c:.4f}' for c in embed_cb]}")

    # === Layers (per-matrix codebooks) ===
    layer_blocks = []
    for li in range(N_LAYERS):
        prefix = f"model.layers.{li}"
        q_w = f.get_tensor(f"{prefix}.self_attn.q_proj.weight").T
        k_w = f.get_tensor(f"{prefix}.self_attn.k_proj.weight").T
        v_w = f.get_tensor(f"{prefix}.self_attn.v_proj.weight").T
        o_w = f.get_tensor(f"{prefix}.self_attn.o_proj.weight").T
        gate_w = f.get_tensor(f"{prefix}.mlp.gate_proj.weight").T
        up_w = f.get_tensor(f"{prefix}.mlp.up_proj.weight").T
        down_w = f.get_tensor(f"{prefix}.mlp.down_proj.weight").T

        # Per-matrix Lloyd-Max
        q_idx, q_cb = lloyd_max_quantize(q_w, bits)
        k_idx, k_cb = lloyd_max_quantize(k_w, bits)
        v_idx, v_cb = lloyd_max_quantize(v_w, bits)
        o_idx, o_cb = lloyd_max_quantize(o_w, bits)
        gate_idx, gate_cb = lloyd_max_quantize(gate_w, bits)
        up_idx, up_cb = lloyd_max_quantize(up_w, bits)
        down_idx, down_cb = lloyd_max_quantize(down_w, bits)

        qkv_packed = (pack_quantized(q_idx, bits) + pack_quantized(k_idx, bits) +
                      pack_quantized(v_idx, bits) + pack_quantized(o_idx, bits))
        ffn_packed = (pack_quantized(gate_idx, bits) + pack_quantized(up_idx, bits) +
                      pack_quantized(down_idx, bits))

        # RMSNorm gamma (direct scale for Llama)
        ln1 = f.get_tensor(f"{prefix}.input_layernorm.weight").astype(np.float64)
        ln2 = f.get_tensor(f"{prefix}.post_attention_layernorm.weight").astype(np.float64)
        norm_data = b""
        for arr in [ln1, ln2]:
            for v in arr:
                norm_data += struct.pack("<q", int(float(v) * 1000))

        # 7 per-matrix codebooks
        cb_data = (serialize_codebook(q_cb) + serialize_codebook(k_cb) +
                   serialize_codebook(v_cb) + serialize_codebook(o_cb) +
                   serialize_codebook(gate_cb) + serialize_codebook(up_cb) +
                   serialize_codebook(down_cb))

        weight_data = qkv_packed + ffn_packed + norm_data + cb_data
        layer_hdr = struct.pack("<iiii", li, 16 + len(weight_data),
                                len(qkv_packed), len(ffn_packed))
        layer_blocks.append(layer_hdr + weight_data)
        print(f"  Layer {li}: QKV={len(qkv_packed)} FFN={len(ffn_packed)} "
              f"Q_cb=[{q_cb[0]:.3f}..{q_cb[-1]:.3f}] gate_cb=[{gate_cb[0]:.3f}..{gate_cb[-1]:.3f}]")

    # === Final RMSNorm ===
    final_norm = f.get_tensor("model.norm.weight").astype(np.float64)
    final_norm_data = b""
    for v in final_norm:
        final_norm_data += struct.pack("<q", int(float(v) * 1000))

    # === LM head (tied with embeddings for SmolLM) ===
    try:
        lmhead_w = f.get_tensor("lm_head.weight").T
    except Exception:
        # SmolLM ties lm_head to embed_tokens
        lmhead_w = f.get_tensor("model.embed_tokens.weight")  # already (vocab, d_model)
        print("  LM head: tied with embed_tokens")
    lmhead_idx, lmhead_cb = lloyd_max_quantize(lmhead_w, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)
    print(f"  LM head: {len(lmhead_packed)} bytes")

    # === Assemble ===
    embed_off = FJM_HEADER_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    final_norm_off = layer0_off + layers_total
    lmhead_off = final_norm_off + len(final_norm_data)
    total_size = lmhead_off + len(lmhead_packed)

    # Build v4 header
    header = struct.pack("<19I",
        FJM_MAGIC, 4,  # version=4
        MODEL_TYPE, N_LAYERS, D_MODEL, N_HEADS, D_HEAD,
        VOCAB_SIZE, bits, total_size, embed_off, layer0_off, lmhead_off,
        N_KV_HEADS, 1, 1, FFN_DIM,  # ffn_type=gated, norm_type=RMSNorm
        ROPE_THETA // 1000, EOS_TOKEN,
    )
    header += serialize_codebook(embed_cb)   # bytes 76-108
    header += serialize_codebook(lmhead_cb)  # bytes 108-140
    header += struct.pack("<I", final_norm_off)
    header += b"\x00" * (FJM_HEADER_SIZE - len(header))
    assert len(header) == FJM_HEADER_SIZE

    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += final_norm_data
    fjm += lmhead_packed

    with open(args.output, "wb") as fout:
        fout.write(fjm)
    print(f"\nSaved: {args.output} ({total_size} bytes, {total_size/1024/1024:.1f} MB)")
    print(f"  v4 per-matrix codebooks: 7 codebooks × {N_LAYERS} layers = {7*N_LAYERS} codebooks")

    if args.write_disk:
        offset = args.lba * 512
        with open(args.write_disk, "r+b") as disk:
            disk.seek(offset)
            disk.write(fjm)
            remainder = len(fjm) % 512
            if remainder:
                disk.write(b"\x00" * (512 - remainder))
        sectors = (len(fjm) + 511) // 512
        print(f"Written to {args.write_disk} at LBA {args.lba} ({sectors} sectors)")


if __name__ == "__main__":
    main()
