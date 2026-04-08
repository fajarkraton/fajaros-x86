#!/usr/bin/env python3
"""
export_fjm.py — Convert HuggingFace model to .fjm (Fajar Model) binary format.

Supports:
  v1: SmolLM-style (MHA, standard FFN, LayerNorm)
  v2: Gemma 3 style (GQA, gated FFN, RMSNorm, RoPE)

Usage:
    python export_fjm.py --test-model -o test.fjm
    python export_fjm.py --model google/gemma-3-1b-it --bits 2 -o gemma3.fjm
    python export_fjm.py --model google/gemma-3-1b-it --bits 2 -o gemma3.fjm --write-disk ../disk.img --lba 0

Author: Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id)
"""

import argparse
import struct
import sys
import numpy as np
from pathlib import Path

FJM_MAGIC = 0x314D4A46  # "FJM1"
FJM_HEADER_V1_SIZE = 64
FJM_HEADER_V2_SIZE = 96
FJM_LAYER_HDR_SIZE = 16

MODEL_TYPES = {
    "test": 0,
    "HuggingFaceTB/SmolLM-135M": 1,
    "google/gemma-3-1b-it": 10,
    "google/gemma-3-270m-it": 11,
}


def lloyd_max_quantize(data, bits, max_iters=20):
    """Lloyd-Max quantization with chunked distance computation to avoid OOM."""
    n_centroids = 2 ** bits
    flat = data.flatten().astype(np.float32)
    n = len(flat)

    # Use subset for centroid estimation if data is huge (>10M elements)
    if n > 10_000_000:
        sample = flat[np.random.choice(n, 2_000_000, replace=False)]
    else:
        sample = flat

    percentiles = np.linspace(0, 100, n_centroids + 2)[1:-1]
    centroids = np.percentile(sample, percentiles).astype(np.float32)

    for it in range(max_iters):
        # Assign in chunks to avoid huge distance matrix
        indices = np.empty(n, dtype=np.int32)
        chunk_size = 2_000_000
        for start in range(0, n, chunk_size):
            end = min(start + chunk_size, n)
            dists = np.abs(flat[start:end, None] - centroids[None, :])
            indices[start:end] = np.argmin(dists, axis=1)
        # Update centroids
        for i in range(n_centroids):
            mask = indices == i
            if mask.any():
                centroids[i] = flat[mask].mean()

    # Final assignment (chunked)
    indices = np.empty(n, dtype=np.int32)
    for start in range(0, n, chunk_size):
        end = min(start + chunk_size, n)
        dists = np.abs(flat[start:end, None] - centroids[None, :])
        indices[start:end] = np.argmin(dists, axis=1)

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


def build_v2_header(model_type, n_layers, d_model, n_heads, d_head, vocab_size,
                     bits, total_size, embed_off, layer0_off, lmhead_off,
                     n_kv_heads=0, ffn_type=0, norm_type=0, ffn_dim=0,
                     rope_theta=0, eos_token=2):
    # 19 fields × 4 bytes = 76 bytes + padding to 96
    header = struct.pack("<19I",
        FJM_MAGIC, 2,  # magic + version
        model_type, n_layers, d_model, n_heads, d_head,  # 5 fields
        vocab_size, bits, total_size, embed_off, layer0_off, lmhead_off,  # 6 fields
        n_kv_heads, ffn_type, norm_type, ffn_dim,  # 4 v2 fields
        rope_theta // 1000 if rope_theta > 0 else 0,  # stored as theta/1000
        eos_token,  # EOS token ID
    )
    header += b"\x00" * (FJM_HEADER_V2_SIZE - len(header))
    return header


def export_gemma3(model_name, bits):
    """Export Gemma 3 model to .fjm v2 format."""
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
    # Gemma 3 stores rope_theta in rope_scaling dict, not as top-level attr
    rope_theta = int(getattr(config, 'rope_theta', 0))
    if rope_theta == 0 and hasattr(config, 'rope_scaling'):
        rs = config.rope_scaling
        if isinstance(rs, dict) and 'full_attention' in rs:
            rope_theta = int(rs['full_attention'].get('rope_theta', 0))
    eos_token = getattr(config, 'eos_token_id', 2)
    if isinstance(eos_token, list):
        eos_token = eos_token[0]

    # Detect architecture
    is_gated = hasattr(model.model.layers[0].mlp, 'gate_proj')
    is_rmsnorm = True  # Gemma 3 always uses RMSNorm

    model_type = MODEL_TYPES.get(model_name, 99)
    print(f"Model: {n_layers}L d={d_model} {n_heads}Q:{n_kv_heads}KV d_head={d_head}")
    print(f"FFN: {'gated' if is_gated else 'standard'} dim={ffn_dim}")
    print(f"Norm: {'RMSNorm' if is_rmsnorm else 'LayerNorm'}, RoPE theta={rope_theta}")
    print(f"Quantizing to {bits}-bit...")

    # Embedding
    embed_w = model.model.embed_tokens.weight.detach().numpy()
    embed_idx, embed_cb = lloyd_max_quantize(embed_w, bits)
    embed_packed = pack_quantized(embed_idx, bits)
    print(f"  Embedding: {embed_w.shape} → {len(embed_packed)} bytes")

    # Layers
    layer_blocks = []
    for i in range(n_layers):
        layer = model.model.layers[i]

        # Q/K/V projections (separate for GQA)
        q_w = layer.self_attn.q_proj.weight.detach().numpy().T
        k_w = layer.self_attn.k_proj.weight.detach().numpy().T
        v_w = layer.self_attn.v_proj.weight.detach().numpy().T

        q_idx, q_cb = lloyd_max_quantize(q_w, bits)
        k_idx, _ = lloyd_max_quantize(k_w, bits)
        v_idx, _ = lloyd_max_quantize(v_w, bits)
        q_packed = pack_quantized(q_idx, bits)
        k_packed = pack_quantized(k_idx, bits)
        v_packed = pack_quantized(v_idx, bits)
        qkv_packed = q_packed + k_packed + v_packed

        # FFN (gated: gate + up + down)
        if is_gated:
            gate_w = layer.mlp.gate_proj.weight.detach().numpy().T
            up_w = layer.mlp.up_proj.weight.detach().numpy().T
            down_w = layer.mlp.down_proj.weight.detach().numpy().T
            gate_idx, _ = lloyd_max_quantize(gate_w, bits)
            up_idx, _ = lloyd_max_quantize(up_w, bits)
            down_idx, _ = lloyd_max_quantize(down_w, bits)
            ffn_packed = (pack_quantized(gate_idx, bits) +
                          pack_quantized(up_idx, bits) +
                          pack_quantized(down_idx, bits))
        else:
            ffn1_w = layer.mlp.gate_proj.weight.detach().numpy().T
            ffn2_w = layer.mlp.down_proj.weight.detach().numpy().T
            ffn1_idx, _ = lloyd_max_quantize(ffn1_w, bits)
            ffn2_idx, _ = lloyd_max_quantize(ffn2_w, bits)
            ffn_packed = (pack_quantized(ffn1_idx, bits) +
                          pack_quantized(ffn2_idx, bits))

        # RMSNorm gamma (no beta)
        ln1_gamma = layer.input_layernorm.weight.detach().numpy().astype(np.float64)
        ln2_gamma = layer.post_attention_layernorm.weight.detach().numpy().astype(np.float64)
        norm_data = b""
        for arr in [ln1_gamma, ln2_gamma]:
            for v in arr:
                norm_data += struct.pack("<q", int(v * 1000))

        # Codebook
        cb_data = b""
        for c in q_cb:
            cb_data += struct.pack("<q", int(c * 1000))

        weight_data = qkv_packed + ffn_packed + norm_data + cb_data
        layer_hdr = struct.pack("<iiii",
            i, FJM_LAYER_HDR_SIZE + len(weight_data),
            len(qkv_packed), len(ffn_packed))
        layer_blocks.append(layer_hdr + weight_data)
        print(f"  Layer {i}: Q={len(q_packed)} K={len(k_packed)} V={len(v_packed)} FFN={len(ffn_packed)}")

    # LM head
    lmhead_w = model.lm_head.weight.detach().numpy().T
    lmhead_idx, _ = lloyd_max_quantize(lmhead_w, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)
    print(f"  LM head: {len(lmhead_packed)} bytes")

    # Assemble
    embed_off = FJM_HEADER_V2_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    lmhead_off = layer0_off + layers_total
    total_size = lmhead_off + len(lmhead_packed)

    header = build_v2_header(
        model_type, n_layers, d_model, n_heads, d_head, vocab_size, bits,
        total_size, embed_off, layer0_off, lmhead_off,
        n_kv_heads=n_kv_heads, ffn_type=1 if is_gated else 0,
        norm_type=1 if is_rmsnorm else 0, ffn_dim=ffn_dim,
        rope_theta=rope_theta, eos_token=eos_token)

    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += lmhead_packed

    print(f"\nTotal: {total_size} bytes ({total_size/1024/1024:.1f} MB)")
    return fjm


def create_test_model(bits=2):
    """Create a tiny v2 test model."""
    n_layers, d_model, n_heads, n_kv_heads = 2, 16, 4, 1
    d_head, vocab_size, ffn_dim = 4, 64, 32
    q_dim, kv_d = n_heads * d_head, n_kv_heads * d_head
    rng = np.random.RandomState(42)

    embed_w = rng.randn(vocab_size, d_model).astype(np.float32)
    embed_idx, _ = lloyd_max_quantize(embed_w, bits)
    embed_packed = pack_quantized(embed_idx, bits)

    layer_blocks = []
    for li in range(n_layers):
        q_w = rng.randn(d_model, q_dim).astype(np.float32)
        k_w = rng.randn(d_model, kv_d).astype(np.float32)
        v_w = rng.randn(d_model, kv_d).astype(np.float32)
        q_idx, q_cb = lloyd_max_quantize(q_w, bits)
        k_idx, _ = lloyd_max_quantize(k_w, bits)
        v_idx, _ = lloyd_max_quantize(v_w, bits)
        qkv_packed = (pack_quantized(q_idx, bits) +
                      pack_quantized(k_idx, bits) +
                      pack_quantized(v_idx, bits))

        gate_w = rng.randn(d_model, ffn_dim).astype(np.float32)
        up_w = rng.randn(d_model, ffn_dim).astype(np.float32)
        down_w = rng.randn(ffn_dim, d_model).astype(np.float32)
        gate_idx, _ = lloyd_max_quantize(gate_w, bits)
        up_idx, _ = lloyd_max_quantize(up_w, bits)
        down_idx, _ = lloyd_max_quantize(down_w, bits)
        ffn_packed = (pack_quantized(gate_idx, bits) +
                      pack_quantized(up_idx, bits) +
                      pack_quantized(down_idx, bits))

        norm_data = b""
        for _ in range(2 * d_model):
            norm_data += struct.pack("<q", 0)  # gamma=0 → identity (1+0=1)
        cb_data = b""
        for c in q_cb:
            cb_data += struct.pack("<q", int(c * 1000))

        weight_data = qkv_packed + ffn_packed + norm_data + cb_data
        layer_hdr = struct.pack("<iiii",
            li, FJM_LAYER_HDR_SIZE + len(weight_data),
            len(qkv_packed), len(ffn_packed))
        layer_blocks.append(layer_hdr + weight_data)

    lmhead_w = rng.randn(d_model, vocab_size).astype(np.float32)
    lmhead_idx, _ = lloyd_max_quantize(lmhead_w, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)

    embed_off = FJM_HEADER_V2_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    lmhead_off = layer0_off + layers_total
    total_size = lmhead_off + len(lmhead_packed)

    header = build_v2_header(
        0, n_layers, d_model, n_heads, d_head, vocab_size, bits,
        total_size, embed_off, layer0_off, lmhead_off,
        n_kv_heads=n_kv_heads, ffn_type=1, norm_type=1, ffn_dim=ffn_dim,
        rope_theta=1000000, eos_token=106)

    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += lmhead_packed

    print(f"Test v2: {n_layers}L d={d_model} {n_heads}Q:{n_kv_heads}KV gated={ffn_dim}")
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
    parser = argparse.ArgumentParser(description="Export model to .fjm format")
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
