#!/usr/bin/env python3
"""
export_gemma3_v7.py — Export Gemma 3 1B to .fjm v7 format.

V28.1 first concrete implementation. Based on export_smollm_v6.py.

Gemma 3 1B config (from unsloth/gemma-3-1b-it):
  - hidden_size (d_model):     1152
  - num_hidden_layers:         26
  - num_attention_heads:       4   (Q heads)
  - num_key_value_heads:       1   (GQA 4:1 ratio)
  - head_dim:                  256
  - intermediate_size (ffn):   6912
  - vocab_size:                262,144
  - max_position_embeddings:   32,768
  - rope_theta (global):       1,000,000
  - rope_local_base_freq:      10,000
  - sliding_window:            512
  - sliding_window_pattern:    6 (globals at layers 5, 11, 17, 23)
  - rms_norm_eps:              1e-6
  - q_norm/k_norm per head:    YES (new vs SmolLM)
  - norms per layer:           4 (pre/post attn + pre/post FFN)

v7 vs v6 header additions:
  +8 bytes rope_theta_global (offset 152)
  +4 bytes sliding_window    (offset 160)
  +4 bytes global_layer_pattern (offset 164)
  +4 bytes n_kv_heads        (offset 168)
  Total v7 header: 176 bytes (v6 was 160).

Expected output size at 4-bit:
  embed:  262K × 1152 × 0.5 = 151 MB
  layers: 26 × (Q+K+V+O + gate+up+down + 4 norms + 7 cbs + 2 head norms)
  lmhead: tied with embed (no separate section)
  TOTAL:  ~310 MB

Usage:
    python3 export_gemma3_v7.py -o build/gemma3_1b_v7.fjm
    python3 export_gemma3_v7.py -o build/gemma3_1b_v7.fjm --write-disk disk.img --lba 0

Requires: unsloth/gemma-3-1b-it already cached in HuggingFace hub.
"""

import argparse
import glob
import os
import struct
import sys

import numpy as np

FJM_MAGIC = 0x314D4A46
FJM_HEADER_SIZE = 176  # v7: 160 + 16 new bytes

# Gemma 3 1B config
N_LAYERS = 26
D_MODEL = 1152
N_HEADS = 4
N_KV_HEADS = 1
D_HEAD = 256
VOCAB_SIZE = 262144
FFN_DIM = 6912
ROPE_THETA_GLOBAL = 1_000_000
ROPE_THETA_LOCAL = 10_000
SLIDING_WINDOW = 512
SLIDING_PATTERN = 6  # globals at layers 5, 11, 17, 23 (0-indexed)
EOS_TOKEN = 106
MODEL_TYPE = 3  # Gemma 3 (SmolLM=1, Gemma v2=2, Gemma 3=3)

GEMMA3_SNAPSHOT_DIR = os.path.expanduser(
    "~/.cache/huggingface/hub/models--unsloth--gemma-3-1b-it/snapshots"
)


def resolve_safetensors_path() -> str:
    """Find the model.safetensors in the latest snapshot."""
    if not os.path.isdir(GEMMA3_SNAPSHOT_DIR):
        print(f"ERROR: Snapshot dir not found: {GEMMA3_SNAPSHOT_DIR}")
        sys.exit(1)
    snaps = sorted(os.listdir(GEMMA3_SNAPSHOT_DIR))
    if not snaps:
        print("ERROR: No snapshots found")
        sys.exit(1)
    candidate = os.path.join(GEMMA3_SNAPSHOT_DIR, snaps[-1], "model.safetensors")
    if not os.path.exists(candidate):
        # Follow symlink
        candidate = os.path.realpath(candidate)
    if not os.path.exists(candidate):
        print(f"ERROR: model.safetensors missing in {snaps[-1]}")
        sys.exit(1)
    return candidate


def lloyd_max_quantize(data, bits, max_iters=30):
    """Lloyd-Max quantization with L2 distance."""
    n_centroids = 2 ** bits
    flat = data.astype(np.float32).flatten()
    n = len(flat)
    sample_size = min(2_000_000, n)
    if n > sample_size:
        sample = flat[np.random.choice(n, sample_size, replace=False)]
    else:
        sample = flat
    percentiles = np.linspace(0, 100, n_centroids + 2)[1:-1]
    centroids = np.percentile(sample, percentiles).astype(np.float32)
    chunk_size = 1_000_000
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
    """Serialize centroids as i64 values (×1000 fixed-point)."""
    return b"".join(struct.pack("<q", int(c * 1000)) for c in centroids)


def serialize_norm(arr):
    """Serialize RMSNorm gamma as i64 ×1000."""
    data = b""
    for v in arr:
        data += struct.pack("<q", int(float(v) * 1000))
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--layer-bits", type=int, default=4)
    parser.add_argument("--embed-bits", type=int, default=4)
    parser.add_argument("--write-disk", type=str)
    parser.add_argument("--lba", type=int, default=0)
    args = parser.parse_args()

    st_path = resolve_safetensors_path()
    print(f"Loading Gemma 3 1B from: {st_path}")

    # bfloat16 requires torch framework; convert to float32 on access
    import torch
    from safetensors import safe_open
    _f_torch = safe_open(st_path, framework="pt")

    class _TorchWrapper:
        def get_tensor(self, key):
            return _f_torch.get_tensor(key).to(torch.float32).numpy()

    f = _TorchWrapper()

    layer_bits = args.layer_bits
    embed_bits = args.embed_bits
    print(f"  v7 Gemma 3 1B: embed={embed_bits}-bit, layers={layer_bits}-bit")
    print(f"  Note: LM head tied with embed_tokens (Gemma 3 default)")

    # === Embedding ===
    embed_w = f.get_tensor("model.embed_tokens.weight")
    print(f"  Embedding: {embed_w.shape} → {embed_bits}-bit ({2**embed_bits} centroids)")
    embed_idx, embed_cb = lloyd_max_quantize(embed_w, embed_bits)
    embed_packed = pack_quantized(embed_idx, embed_bits)
    embed_cb_data = serialize_codebook(embed_cb)
    embed_section = embed_packed + embed_cb_data
    print(f"    → packed={len(embed_packed)} bytes + cb={len(embed_cb_data)} bytes")

    # === Layers ===
    layer_blocks = []
    for li in range(N_LAYERS):
        prefix = f"model.layers.{li}"

        # Transpose to (d_in, d_out) row-major for our matmul
        q_w = f.get_tensor(f"{prefix}.self_attn.q_proj.weight").T  # [1152, 1024]
        k_w = f.get_tensor(f"{prefix}.self_attn.k_proj.weight").T  # [1152, 256]
        v_w = f.get_tensor(f"{prefix}.self_attn.v_proj.weight").T  # [1152, 256]
        o_w = f.get_tensor(f"{prefix}.self_attn.o_proj.weight").T  # [1024, 1152]
        gate_w = f.get_tensor(f"{prefix}.mlp.gate_proj.weight").T  # [1152, 6912]
        up_w = f.get_tensor(f"{prefix}.mlp.up_proj.weight").T      # [1152, 6912]
        down_w = f.get_tensor(f"{prefix}.mlp.down_proj.weight").T  # [6912, 1152]

        # Per-matrix Lloyd-Max
        q_idx, q_cb = lloyd_max_quantize(q_w, layer_bits)
        k_idx, k_cb = lloyd_max_quantize(k_w, layer_bits)
        v_idx, v_cb = lloyd_max_quantize(v_w, layer_bits)
        o_idx, o_cb = lloyd_max_quantize(o_w, layer_bits)
        gate_idx, gate_cb = lloyd_max_quantize(gate_w, layer_bits)
        up_idx, up_cb = lloyd_max_quantize(up_w, layer_bits)
        down_idx, down_cb = lloyd_max_quantize(down_w, layer_bits)

        qkv_packed = (pack_quantized(q_idx, layer_bits) + pack_quantized(k_idx, layer_bits) +
                      pack_quantized(v_idx, layer_bits) + pack_quantized(o_idx, layer_bits))
        ffn_packed = (pack_quantized(gate_idx, layer_bits) + pack_quantized(up_idx, layer_bits) +
                      pack_quantized(down_idx, layer_bits))

        # 4 RMSNorms per layer (Gemma 3: pre/post attn + pre/post FFN)
        input_ln = f.get_tensor(f"{prefix}.input_layernorm.weight").astype(np.float64)
        post_attn_ln = f.get_tensor(f"{prefix}.post_attention_layernorm.weight").astype(np.float64)
        pre_ffn_ln = f.get_tensor(f"{prefix}.pre_feedforward_layernorm.weight").astype(np.float64)
        post_ffn_ln = f.get_tensor(f"{prefix}.post_feedforward_layernorm.weight").astype(np.float64)
        # 2 head norms (new in Gemma 3)
        q_norm = f.get_tensor(f"{prefix}.self_attn.q_norm.weight").astype(np.float64)
        k_norm = f.get_tensor(f"{prefix}.self_attn.k_norm.weight").astype(np.float64)

        norm_data = (serialize_norm(input_ln) + serialize_norm(post_attn_ln) +
                     serialize_norm(pre_ffn_ln) + serialize_norm(post_ffn_ln) +
                     serialize_norm(q_norm) + serialize_norm(k_norm))

        # 7 per-matrix codebooks
        cb_data = (serialize_codebook(q_cb) + serialize_codebook(k_cb) +
                   serialize_codebook(v_cb) + serialize_codebook(o_cb) +
                   serialize_codebook(gate_cb) + serialize_codebook(up_cb) +
                   serialize_codebook(down_cb))

        weight_data = qkv_packed + ffn_packed + norm_data + cb_data
        # v7 layer header: index, block_size, qkv_size, ffn_size, norm_size (+4 for norm count)
        layer_hdr = struct.pack("<iiiii", li, 20 + len(weight_data),
                                len(qkv_packed), len(ffn_packed), len(norm_data))
        layer_blocks.append(layer_hdr + weight_data)
        if li == 0:
            print(f"  Layer 0: QKV={len(qkv_packed)} FFN={len(ffn_packed)} "
                  f"NORM={len(norm_data)} CB={len(cb_data)}")
            print(f"    Q_cb=[{q_cb[0]:.3f}..{q_cb[-1]:.3f}]")
        elif li == 1:
            print(f"  Layer 1..{N_LAYERS-1}: (same format)")

    # === Final RMSNorm ===
    final_norm = f.get_tensor("model.norm.weight").astype(np.float64)
    final_norm_data = serialize_norm(final_norm)

    # === LM head: tied with embed_tokens in Gemma 3 (no separate section) ===

    # === Assemble ===
    embed_off = FJM_HEADER_SIZE
    layer0_off = embed_off + len(embed_section)
    layers_total = sum(len(b) for b in layer_blocks)
    final_norm_off = layer0_off + layers_total
    # LM head points to embed section (tied weights)
    lmhead_off = embed_off  # tied
    total_size = final_norm_off + len(final_norm_data)

    # Build v7 header (176 bytes)
    header = struct.pack("<19I",
        FJM_MAGIC, 7,  # version=7
        MODEL_TYPE, N_LAYERS, D_MODEL, N_HEADS, D_HEAD,
        VOCAB_SIZE, layer_bits, total_size, embed_off, layer0_off, lmhead_off,
        N_KV_HEADS, 1, 1, FFN_DIM,  # ffn_type=gated, norm_type=RMSNorm(1+γ)
        ROPE_THETA_LOCAL // 1000, EOS_TOKEN,
    )
    header += b"\x00" * 32  # 76-107 reserved
    header += b"\x00" * 32  # 108-139 reserved
    header += struct.pack("<I", final_norm_off)  # 140-143
    header += struct.pack("<I", embed_bits)      # 144-147
    header += struct.pack("<I", layer_bits)      # 148-151 (was lmhead_bits)
    # v7 new fields:
    header += struct.pack("<Q", ROPE_THETA_GLOBAL)  # 152-159
    header += struct.pack("<I", SLIDING_WINDOW)     # 160-163
    header += struct.pack("<I", SLIDING_PATTERN)    # 164-167
    header += struct.pack("<I", N_KV_HEADS)         # 168-171 (duplicate, explicit)
    header += b"\x00" * (FJM_HEADER_SIZE - len(header))
    assert len(header) == FJM_HEADER_SIZE, f"header size {len(header)} != {FJM_HEADER_SIZE}"

    fjm = header + embed_section
    for block in layer_blocks:
        fjm += block
    fjm += final_norm_data

    assert len(fjm) == total_size, f"assembly size mismatch: {len(fjm)} != {total_size}"

    with open(args.output, "wb") as fout:
        fout.write(fjm)

    print(f"\nSaved: {args.output} ({total_size} bytes, {total_size/1024/1024:.1f} MB)")
    print(f"  v7 Gemma 3 1B: {N_LAYERS} layers × 1152-dim")
    print(f"  Architecture: GQA 4:1, sliding_window=512, dual rope (local=10K, global=1M)")
    print(f"  LM head: tied with embed_tokens")

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
