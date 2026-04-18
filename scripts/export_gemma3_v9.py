#!/usr/bin/env python3
"""
export_gemma3_v9.py — Export Gemma 3 1B to .fjm v8 format with 8-bit group-wise quantization.

Identical to v8 format (same 176-byte header) but with embed_bits=8, lmhead_bits=8.
Each weight element uses a full byte (no nibble packing), 256 quantization levels.

8-bit group-wise quantization (asymmetric):
    min_v, max_v = min(group), max(group)
    scale = (max_v - min_v) / 255.0
    zero = round(-min_v / scale)         # 0..255
    q[i] = clip(round(data[i] / scale + zero), 0, 255)
    dequant: x[i] = (q[i] - zero) * scale

Per-matrix layout:
    [raw 8-bit indices: n_elems bytes]
    [scales: 4 B × n_groups (INT32 LE, round(scale_real × 1_000_000))]
    [zero_points: 1 B × n_groups (u8, range 0..255)]
    n_groups = ceil(n_elems / group_size)

Size estimate for Gemma 3 1B at 8-bit: ~967 MB (vs ~514 MB at 4-bit).

Usage:
    python3 export_gemma3_v9.py -o build/gemma3_1b_v9.fjm
    python3 export_gemma3_v9.py -o build/gemma3_1b_v9.fjm --write-disk disk.img --lba 0
    python3 export_gemma3_v9.py --validate

Requires: unsloth/gemma-3-1b-it in HuggingFace hub cache.
"""

import argparse
import os
import struct
import sys

import numpy as np

FJM_MAGIC = 0x314D4A46
FJM_HEADER_SIZE = 176
FJM_VERSION = 8  # same format version — kernel dispatches on embed_bits

GROUP_SIZE = 128
QUANT_FORMAT_GROUPWISE = 1

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
SLIDING_PATTERN = 6
EOS_TOKEN = 106
MODEL_TYPE = 10  # Gemma3-1B

EMBED_BITS = 8
LMHEAD_BITS = 8

GEMMA3_SNAPSHOT_DIR = os.path.expanduser(
    "~/.cache/huggingface/hub/models--unsloth--gemma-3-1b-it/snapshots"
)


def resolve_safetensors_path() -> str:
    if not os.path.isdir(GEMMA3_SNAPSHOT_DIR):
        print(f"ERROR: Snapshot dir not found: {GEMMA3_SNAPSHOT_DIR}")
        sys.exit(1)
    snaps = sorted(os.listdir(GEMMA3_SNAPSHOT_DIR))
    if not snaps:
        print("ERROR: No snapshots found")
        sys.exit(1)
    candidate = os.path.join(GEMMA3_SNAPSHOT_DIR, snaps[-1], "model.safetensors")
    if not os.path.exists(candidate):
        candidate = os.path.realpath(candidate)
    if not os.path.exists(candidate):
        print(f"ERROR: model.safetensors missing in {snaps[-1]}")
        sys.exit(1)
    return candidate


# ═════════════��═══════════════════════���═════════════════════════════════
# Group-wise 8-bit quantization
# ═══════════════════════════════════════��═══════════════════════════════

SCALE_FIXED_POINT = 1_000_000


def groupwise_quantize_8bit(data: np.ndarray, group_size: int = GROUP_SIZE):
    """Asymmetric per-group 8-bit quantization.

    Returns:
        indices:    np.uint8, shape = (n,), values 0..255
        scales_int: np.int32, shape = (n_groups,), = round(scale × 1_000_000)
        zeros:      np.uint8, shape = (n_groups,), values 0..255
    """
    flat = data.astype(np.float32).flatten()
    n = len(flat)
    n_groups = (n + group_size - 1) // group_size

    scales_int = np.empty(n_groups, dtype=np.int32)
    zeros = np.empty(n_groups, dtype=np.uint8)
    indices = np.empty(n, dtype=np.uint8)

    for g in range(n_groups):
        s = g * group_size
        e = min(s + group_size, n)
        grp = flat[s:e]
        mn = float(grp.min())
        mx = float(grp.max())
        rng = mx - mn
        if rng < 1e-9:
            scale_real = 1.0
            zero = int(round(-mn))
            zero = max(0, min(255, zero))
            q = np.full(e - s, zero, dtype=np.uint8)
        else:
            scale_real = rng / 255.0
            zero_f = -mn / scale_real
            zero = int(round(zero_f))
            zero = max(0, min(255, zero))
            q = np.round(grp / scale_real + zero).astype(np.int32)
            q = np.clip(q, 0, 255).astype(np.uint8)
        indices[s:e] = q
        scales_int[g] = int(round(scale_real * SCALE_FIXED_POINT))
        zeros[g] = zero

    return indices, scales_int, zeros


def dequantize_8bit_groupwise(indices: np.ndarray, scales_int: np.ndarray,
                               zeros: np.ndarray, group_size: int = GROUP_SIZE) -> np.ndarray:
    """Inverse of groupwise_quantize_8bit."""
    n = len(indices)
    out = np.empty(n, dtype=np.float32)
    n_groups = len(scales_int)
    for g in range(n_groups):
        s = g * group_size
        e = min(s + group_size, n)
        scale = float(scales_int[g]) / SCALE_FIXED_POINT
        zero = int(zeros[g])
        out[s:e] = (indices[s:e].astype(np.float32) - zero) * scale
    return out


def serialize_matrix_v9(indices: np.ndarray, scales_int: np.ndarray, zeros: np.ndarray) -> bytes:
    """8-bit per-matrix payload: [raw indices] [scales int32 ×1e6] [zeros u8].
    No nibble packing — each index is a full byte."""
    assert scales_int.dtype == np.int32
    return indices.tobytes() + scales_int.tobytes() + zeros.tobytes()


def serialize_norm(arr) -> bytes:
    """RMSNorm gamma as i64 ×1000 (unchanged from v7/v8)."""
    return b"".join(struct.pack("<q", int(float(v) * 1000)) for v in arr)


# ═══════════════════════════════════════════════════════════════════════
# Single-matrix round-trip validation
# ══════════���════════════════���═══════════════════════════���═══════════════

def validate_roundtrip():
    """Validate 8-bit group-wise quant on a realistic LLM weight matrix."""
    print("=== 8-bit Round-Trip Validation ===\n")

    st_path = resolve_safetensors_path()
    import torch
    from safetensors import safe_open
    f = safe_open(st_path, framework="pt")

    key = "model.layers.0.mlp.gate_proj.weight"
    w = f.get_tensor(key).to(torch.float32).numpy()
    orig = w.astype(np.float32).flatten()
    print(f"Matrix: {key}")
    print(f"  Shape: {w.shape} ({orig.size} elements)")
    print(f"  Range: [{orig.min():.4f}, {orig.max():.4f}]")
    print(f"  Mean:  {orig.mean():.4f}  Std: {orig.std():.4f}\n")

    print(f"Quantizing 8-bit with group_size={GROUP_SIZE}...")
    indices, scales, zeros = groupwise_quantize_8bit(w, GROUP_SIZE)
    n_groups = len(scales)
    print(f"  Groups: {n_groups}")
    print(f"  Scales range: [{scales.min()}, {scales.max()}]")
    print(f"  Zeros range:  [{zeros.min()}, {zeros.max()}]\n")

    print("Dequantizing...")
    recon = dequantize_8bit_groupwise(indices, scales, zeros, GROUP_SIZE)
    err = recon - orig
    max_abs = float(np.abs(err).max())
    mae = float(np.abs(err).mean())
    rmse = float(np.sqrt((err ** 2).mean()))
    rng = float(orig.max() - orig.min())
    print(f"  Max abs error:  {max_abs:.6f} ({max_abs/rng*100:.4f}% of weight range)")
    print(f"  Mean abs error: {mae:.6f} ({mae/rng*100:.4f}% of weight range)")
    print(f"  RMSE:           {rmse:.6f}")

    # Compare with 4-bit
    print("\n--- Comparison with 4-bit ---")
    from export_gemma3_v8 import groupwise_quantize_4bit, dequantize_4bit_groupwise
    idx4, sc4, z4 = groupwise_quantize_4bit(w, GROUP_SIZE)
    recon4 = dequantize_4bit_groupwise(idx4, sc4, z4, GROUP_SIZE)
    err4 = recon4 - orig
    max_abs4 = float(np.abs(err4).max())
    mae4 = float(np.abs(err4).mean())
    rmse4 = float(np.sqrt((err4 ** 2).mean()))
    print(f"  4-bit max abs:  {max_abs4:.6f} ({max_abs4/rng*100:.4f}%)")
    print(f"  4-bit MAE:      {mae4:.6f}")
    print(f"  4-bit RMSE:     {rmse4:.6f}")
    print(f"\n  8-bit improvement: {max_abs4/max_abs:.1f}x max, {mae4/mae:.1f}x MAE, {rmse4/rmse:.1f}x RMSE")

    gate_pct = max_abs / rng * 100
    if gate_pct < 1.0:
        print(f"\nGATE PASS: max error {gate_pct:.4f}% < 1% of weight range")
        return True
    else:
        print(f"\nGATE FAIL: max error {gate_pct:.4f}% >= 1%")
        return False


# ═══════��═══════════════════════���═══════════════════════════════════════
# Full export
# ═════════════════════════════════════════════════════════════���═════════

def full_export(output_path: str, disk_path: str | None, lba: int) -> None:
    """Produce a full .fjm file for Gemma 3 1B at 8-bit group-wise."""
    st_path = resolve_safetensors_path()
    print(f"Loading Gemma 3 1B from: {st_path}")

    import torch
    from safetensors import safe_open
    f_torch = safe_open(st_path, framework="pt")

    class _W:
        def get_tensor(self, key):
            return f_torch.get_tensor(key).to(torch.float32).numpy()
    f = _W()

    print(f"  8-bit group-wise (group={GROUP_SIZE}), Gemma 3 1B, {N_LAYERS} layers")

    # === Embedding ===
    embed_w = f.get_tensor("model.embed_tokens.weight")  # [vocab, d_model]
    print(f"  Embedding: {embed_w.shape}")
    embed_idx, embed_sc, embed_z = groupwise_quantize_8bit(embed_w, GROUP_SIZE)
    embed_bytes = serialize_matrix_v9(embed_idx, embed_sc, embed_z)
    print(f"    → {len(embed_bytes)} bytes ({len(embed_bytes)/1024/1024:.1f} MB)")

    # === Layers ===
    layer_blocks = []
    for li in range(N_LAYERS):
        prefix = f"model.layers.{li}"

        q_w = f.get_tensor(f"{prefix}.self_attn.q_proj.weight").T
        k_w = f.get_tensor(f"{prefix}.self_attn.k_proj.weight").T
        v_w = f.get_tensor(f"{prefix}.self_attn.v_proj.weight").T
        o_w = f.get_tensor(f"{prefix}.self_attn.o_proj.weight").T
        g_w = f.get_tensor(f"{prefix}.mlp.gate_proj.weight").T
        u_w = f.get_tensor(f"{prefix}.mlp.up_proj.weight").T
        d_w = f.get_tensor(f"{prefix}.mlp.down_proj.weight").T

        def qm(w):
            idx, sc, z = groupwise_quantize_8bit(w, GROUP_SIZE)
            return serialize_matrix_v9(idx, sc, z)

        q_b = qm(q_w)
        k_b = qm(k_w)
        v_b = qm(v_w)
        o_b = qm(o_w)
        g_b = qm(g_w)
        u_b = qm(u_w)
        d_b = qm(d_w)

        qkv_packed = q_b + k_b + v_b + o_b
        ffn_packed = g_b + u_b + d_b

        # 4 RMSNorms + 2 head norms
        norms = b""
        for k in ("input_layernorm", "post_attention_layernorm",
                  "pre_feedforward_layernorm", "post_feedforward_layernorm"):
            norms += serialize_norm(f.get_tensor(f"{prefix}.{k}.weight").astype(np.float64))
        norms += serialize_norm(f.get_tensor(f"{prefix}.self_attn.q_norm.weight").astype(np.float64))
        norms += serialize_norm(f.get_tensor(f"{prefix}.self_attn.k_norm.weight").astype(np.float64))

        weight_data = qkv_packed + ffn_packed + norms
        hdr = struct.pack("<iiii", li, 16 + len(weight_data),
                          len(qkv_packed), len(ffn_packed))
        layer_blocks.append(hdr + weight_data)
        if li == 0:
            print(f"  Layer 0: QKV={len(qkv_packed)} FFN={len(ffn_packed)} NORM={len(norms)} total={16+len(weight_data)}")
        elif li == 1:
            print(f"  Layer 1..{N_LAYERS-1}: (same structure)")

    # === Final RMSNorm ===
    final_norm = f.get_tensor("model.norm.weight").astype(np.float64)
    final_norm_data = serialize_norm(final_norm)

    # === Assemble ===
    embed_off = FJM_HEADER_SIZE
    layer0_off = embed_off + len(embed_bytes)
    layers_total = sum(len(b) for b in layer_blocks)
    final_norm_off = layer0_off + layers_total
    lmhead_off = embed_off  # tied
    total_size = final_norm_off + len(final_norm_data)

    header = struct.pack("<19I",
        FJM_MAGIC, FJM_VERSION,
        MODEL_TYPE, N_LAYERS, D_MODEL, N_HEADS, D_HEAD,
        VOCAB_SIZE, EMBED_BITS, total_size, embed_off, layer0_off, lmhead_off,
        N_KV_HEADS, 1, 1, FFN_DIM,
        ROPE_THETA_LOCAL // 1000, EOS_TOKEN,
    )
    header += b"\x00" * 32   # 76-107
    header += b"\x00" * 32   # 108-139
    header += struct.pack("<I", final_norm_off)  # 140-143
    header += struct.pack("<I", EMBED_BITS)      # 144-147 embed_bits
    header += struct.pack("<I", LMHEAD_BITS)     # 148-151 lmhead_bits
    header += struct.pack("<Q", ROPE_THETA_GLOBAL)  # 152-159
    header += struct.pack("<I", SLIDING_WINDOW)     # 160-163
    header += struct.pack("<I", SLIDING_PATTERN)    # 164-167
    header += struct.pack("<I", N_KV_HEADS)         # 168-171
    header += struct.pack("<HH", QUANT_FORMAT_GROUPWISE, GROUP_SIZE)  # 172-175
    assert len(header) == FJM_HEADER_SIZE

    fjm = header + embed_bytes
    for blk in layer_blocks:
        fjm += blk
    fjm += final_norm_data

    assert len(fjm) == total_size, f"{len(fjm)} vs {total_size}"

    with open(output_path, "wb") as out:
        out.write(fjm)

    print(f"\nSaved: {output_path} ({total_size} bytes, {total_size/1024/1024:.1f} MB)")
    print(f"  Header: {FJM_HEADER_SIZE} B")
    print(f"  Embedding: {len(embed_bytes)} B ({len(embed_bytes)/1024/1024:.1f} MB)")
    print(f"  Layers: {layers_total} B ({layers_total/1024/1024:.1f} MB)")
    print(f"  Final norm: {len(final_norm_data)} B")

    if disk_path:
        with open(disk_path, "r+b") as disk:
            disk.seek(lba * 512)
            disk.write(fjm)
            rem = len(fjm) % 512
            if rem:
                disk.write(b"\x00" * (512 - rem))
        sectors = (len(fjm) + 511) // 512
        print(f"Written to {disk_path} at LBA {lba} ({sectors} sectors)")
        print(f"Tokenizer should go at LBA {sectors + 10} (after model + gap)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", help="Output .fjm path")
    parser.add_argument("--write-disk", type=str)
    parser.add_argument("--lba", type=int, default=0)
    parser.add_argument("--validate", action="store_true",
                        help="Run 8-bit round-trip test and exit")
    args = parser.parse_args()

    if args.validate:
        ok = validate_roundtrip()
        sys.exit(0 if ok else 1)

    if not args.output:
        parser.error("-o required unless --validate")

    full_export(args.output, args.write_disk, args.lba)


if __name__ == "__main__":
    main()
