#!/usr/bin/env python3
"""
export_fjm.py — Convert HuggingFace model to .fjm (Fajar Model) binary format.

Usage:
    # Create tiny test model (fits in RamFS, ~3KB):
    python export_fjm.py --test-model -o test.fjm

    # Export SmolLM-135M at 2-bit quantization:
    python export_fjm.py --model HuggingFaceTB/SmolLM-135M --bits 2 -o smollm.fjm

    # Write test model to NVMe disk image at LBA 0:
    python export_fjm.py --test-model -o test.fjm --write-disk ../disk.img --lba 0

Author: Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id)
"""

import argparse
import struct
import sys
import numpy as np
from pathlib import Path

# .fjm format constants
FJM_MAGIC = 0x314D4A46  # "FJM1" in little-endian
FJM_VERSION = 1
FJM_HEADER_SIZE = 64
FJM_LAYER_HDR_SIZE = 16

# Model type IDs
MODEL_TYPES = {
    "test": 0,
    "HuggingFaceTB/SmolLM-135M": 1,
    "TinyLlama/TinyLlama-1.1B-Chat-v1.0": 2,
    "HuggingFaceTB/SmolLM-360M": 3,
}

def lloyd_max_quantize(data: np.ndarray, bits: int) -> tuple:
    """Lloyd-Max scalar quantization. Returns (indices, codebook)."""
    n_centroids = 2 ** bits
    # Initialize centroids with percentile-based spacing
    percentiles = np.linspace(0, 100, n_centroids + 2)[1:-1]
    centroids = np.percentile(data.flatten(), percentiles)

    for _ in range(50):  # Lloyd iterations
        # Assign to nearest centroid
        dists = np.abs(data.flatten()[:, None] - centroids[None, :])
        indices = np.argmin(dists, axis=1)
        # Update centroids
        for i in range(n_centroids):
            mask = indices == i
            if mask.any():
                centroids[i] = data.flatten()[mask].mean()

    # Final assignment
    dists = np.abs(data.flatten()[:, None] - centroids[None, :])
    indices = np.argmin(dists, axis=1)
    return indices.astype(np.uint8), centroids


def pack_quantized(indices: np.ndarray, bits: int) -> bytes:
    """Pack quantized indices into bytes. E.g., 2-bit: 4 indices per byte."""
    elems_per_byte = 8 // bits
    mask = (1 << bits) - 1
    n = len(indices)
    n_bytes = (n + elems_per_byte - 1) // elems_per_byte
    result = bytearray(n_bytes)

    for i, idx in enumerate(indices):
        byte_idx = i // elems_per_byte
        bit_off = (i % elems_per_byte) * bits
        result[byte_idx] |= (int(idx) & mask) << bit_off

    return bytes(result)


def create_test_model(bits: int = 2) -> bytes:
    """Create a tiny synthetic .fjm model for testing."""
    n_layers = 2
    d_model = 16
    n_heads = 2
    d_head = 8
    vocab_size = 64

    # Generate random weights
    rng = np.random.RandomState(42)

    # Embedding table
    embed_weights = rng.randn(vocab_size, d_model).astype(np.float32)
    embed_idx, embed_cb = lloyd_max_quantize(embed_weights, bits)
    embed_packed = pack_quantized(embed_idx, bits)

    # Per-layer data
    layer_blocks = []
    for layer_n in range(n_layers):
        # QKV weights
        qkv = rng.randn(d_model, 3 * d_model).astype(np.float32)
        qkv_idx, qkv_cb = lloyd_max_quantize(qkv, bits)
        qkv_packed = pack_quantized(qkv_idx, bits)

        # FFN W1
        ffn1 = rng.randn(d_model, 4 * d_model).astype(np.float32)
        ffn1_idx, _ = lloyd_max_quantize(ffn1, bits)
        ffn1_packed = pack_quantized(ffn1_idx, bits)

        # FFN W2
        ffn2 = rng.randn(4 * d_model, d_model).astype(np.float32)
        ffn2_idx, _ = lloyd_max_quantize(ffn2, bits)
        ffn2_packed = pack_quantized(ffn2_idx, bits)

        # LayerNorm params (full precision, stored as i64 x1000 fixed-point)
        ln1_gamma = np.ones(d_model, dtype=np.float64)
        ln1_beta = np.zeros(d_model, dtype=np.float64)
        ln2_gamma = np.ones(d_model, dtype=np.float64)
        ln2_beta = np.zeros(d_model, dtype=np.float64)
        ln_data = b""
        for arr in [ln1_gamma, ln1_beta, ln2_gamma, ln2_beta]:
            for v in arr:
                ln_data += struct.pack("<q", int(v * 1000))

        # Codebook (i64 x1000 fixed-point)
        cb_data = b""
        for c in qkv_cb:
            cb_data += struct.pack("<q", int(c * 1000))

        # Layer block
        weight_data = qkv_packed + ffn1_packed + ffn2_packed + ln_data + cb_data
        layer_hdr = struct.pack("<iiii",
            layer_n,
            FJM_LAYER_HDR_SIZE + len(weight_data),
            len(qkv_packed),
            len(ffn1_packed) + len(ffn2_packed),
        )
        layer_blocks.append(layer_hdr + weight_data)

    # LM head
    lmhead = rng.randn(d_model, vocab_size).astype(np.float32)
    lmhead_idx, _ = lloyd_max_quantize(lmhead, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)

    # Calculate offsets
    embed_off = FJM_HEADER_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    lmhead_off = layer0_off + layers_total
    total_size = lmhead_off + len(lmhead_packed)

    # Build header
    header = struct.pack("<IIiiiiiiiIIII",
        FJM_MAGIC,
        FJM_VERSION,
        0,  # model_type = test
        n_layers,
        d_model,
        n_heads,
        d_head,
        vocab_size,
        bits,
        total_size,
        embed_off,
        layer0_off,
        lmhead_off,
    )
    # Pad to 64 bytes
    header += b"\x00" * (FJM_HEADER_SIZE - len(header))

    # Assemble
    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += lmhead_packed

    assert len(fjm) == total_size, f"Size mismatch: {len(fjm)} != {total_size}"

    print(f"Test model: {n_layers} layers, d={d_model}, vocab={vocab_size}, {bits}-bit")
    print(f"Total size: {total_size} bytes ({total_size/1024:.1f} KB)")
    print(f"Embed: {len(embed_packed)} bytes at offset {embed_off}")
    print(f"Layers: {layers_total} bytes at offset {layer0_off}")
    print(f"LM head: {len(lmhead_packed)} bytes at offset {lmhead_off}")

    return fjm


def export_huggingface(model_name: str, bits: int) -> bytes:
    """Export a HuggingFace model to .fjm format."""
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
    d_head = d_model // n_heads
    vocab_size = config.vocab_size

    model_type = MODEL_TYPES.get(model_name, 99)

    print(f"Model: {n_layers} layers, d={d_model}, {n_heads} heads, vocab={vocab_size}")
    print(f"Quantizing to {bits}-bit...")

    # Extract and quantize embedding
    embed_w = model.model.embed_tokens.weight.detach().numpy()
    embed_idx, embed_cb = lloyd_max_quantize(embed_w, bits)
    embed_packed = pack_quantized(embed_idx, bits)
    print(f"  Embedding: {embed_w.shape} -> {len(embed_packed)} bytes")

    # Extract and quantize layers
    layer_blocks = []
    for i in range(n_layers):
        layer = model.model.layers[i]

        # QKV projection (concatenated)
        q_w = layer.self_attn.q_proj.weight.detach().numpy()
        k_w = layer.self_attn.k_proj.weight.detach().numpy()
        v_w = layer.self_attn.v_proj.weight.detach().numpy()
        qkv_w = np.concatenate([q_w, k_w, v_w], axis=0).T  # [d_model, 3*d_model]
        qkv_idx, qkv_cb = lloyd_max_quantize(qkv_w, bits)
        qkv_packed = pack_quantized(qkv_idx, bits)

        # FFN
        ffn1_w = layer.mlp.gate_proj.weight.detach().numpy().T
        ffn1_idx, _ = lloyd_max_quantize(ffn1_w, bits)
        ffn1_packed = pack_quantized(ffn1_idx, bits)

        ffn2_w = layer.mlp.down_proj.weight.detach().numpy().T
        ffn2_idx, _ = lloyd_max_quantize(ffn2_w, bits)
        ffn2_packed = pack_quantized(ffn2_idx, bits)

        # LayerNorm (RMSNorm for LLaMA-style)
        ln1_gamma = layer.input_layernorm.weight.detach().numpy().astype(np.float64)
        ln2_gamma = layer.post_attention_layernorm.weight.detach().numpy().astype(np.float64)
        ln1_beta = np.zeros_like(ln1_gamma)  # RMSNorm has no beta
        ln2_beta = np.zeros_like(ln2_gamma)

        ln_data = b""
        for arr in [ln1_gamma, ln1_beta, ln2_gamma, ln2_beta]:
            for v in arr:
                ln_data += struct.pack("<q", int(v * 1000))

        # Codebook
        cb_data = b""
        for c in qkv_cb:
            cb_data += struct.pack("<q", int(c * 1000))

        weight_data = qkv_packed + ffn1_packed + ffn2_packed + ln_data + cb_data
        layer_hdr = struct.pack("<iiii",
            i,
            FJM_LAYER_HDR_SIZE + len(weight_data),
            len(qkv_packed),
            len(ffn1_packed) + len(ffn2_packed),
        )
        layer_blocks.append(layer_hdr + weight_data)
        print(f"  Layer {i}: {len(weight_data)} bytes")

    # LM head
    lmhead_w = model.lm_head.weight.detach().numpy().T  # [d_model, vocab_size]
    lmhead_idx, _ = lloyd_max_quantize(lmhead_w, bits)
    lmhead_packed = pack_quantized(lmhead_idx, bits)
    print(f"  LM head: {len(lmhead_packed)} bytes")

    # Calculate offsets
    embed_off = FJM_HEADER_SIZE
    layer0_off = embed_off + len(embed_packed)
    layers_total = sum(len(b) for b in layer_blocks)
    lmhead_off = layer0_off + layers_total
    total_size = lmhead_off + len(lmhead_packed)

    # Build header
    header = struct.pack("<IIiiiiiiiIIII",
        FJM_MAGIC, FJM_VERSION, model_type,
        n_layers, d_model, n_heads, d_head, vocab_size, bits,
        total_size, embed_off, layer0_off, lmhead_off,
    )
    header += b"\x00" * (FJM_HEADER_SIZE - len(header))

    # Assemble
    fjm = header + embed_packed
    for block in layer_blocks:
        fjm += block
    fjm += lmhead_packed

    assert len(fjm) == total_size
    print(f"\nTotal: {total_size} bytes ({total_size/1024/1024:.1f} MB)")

    return fjm


def write_to_disk(fjm_data: bytes, disk_path: str, lba: int):
    """Write .fjm data to raw disk image at given LBA (sector 512B)."""
    offset = lba * 512
    disk = Path(disk_path)
    if not disk.exists():
        print(f"Creating disk image: {disk_path} (64MB)")
        with open(disk_path, "wb") as f:
            f.write(b"\x00" * 64 * 1024 * 1024)

    with open(disk_path, "r+b") as f:
        f.seek(offset)
        f.write(fjm_data)
        # Pad to sector boundary
        remainder = len(fjm_data) % 512
        if remainder:
            f.write(b"\x00" * (512 - remainder))

    sectors = (len(fjm_data) + 511) // 512
    print(f"Written {len(fjm_data)} bytes to {disk_path} at LBA {lba} ({sectors} sectors)")


def main():
    parser = argparse.ArgumentParser(description="Export model to .fjm format")
    parser.add_argument("--model", type=str, help="HuggingFace model name")
    parser.add_argument("--bits", type=int, default=2, help="Quantization bits (default: 2)")
    parser.add_argument("--test-model", action="store_true", help="Create tiny test model")
    parser.add_argument("-o", "--output", type=str, required=True, help="Output .fjm file")
    parser.add_argument("--write-disk", type=str, help="Write to raw disk image")
    parser.add_argument("--lba", type=int, default=0, help="Start LBA for disk write")
    args = parser.parse_args()

    if args.test_model:
        fjm = create_test_model(args.bits)
    elif args.model:
        fjm = export_huggingface(args.model, args.bits)
    else:
        parser.error("Specify --model or --test-model")

    with open(args.output, "wb") as f:
        f.write(fjm)
    print(f"Saved: {args.output}")

    if args.write_disk:
        write_to_disk(fjm, args.write_disk, args.lba)


if __name__ == "__main__":
    main()
