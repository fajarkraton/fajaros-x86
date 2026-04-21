#!/usr/bin/env python3
"""
build_intllm_tiny.py — generate a minimal Phase D .fjm v9 test model.

Used by `make test-intllm-kernel-path` to produce a <1 KB synthetic model
that exercises every V31 Phase D code path (mdl_v9_detect_format,
mdl_v9_init_after_header, tfm_mf_mlgru_block, tfm_mf_glu_block,
tfm_mf_forward, km_mf_*) without needing a real 46-370 MB trained IntLLM.

Architecture of the tiny model:
  - 1 transformer layer (L = 1)
  - d_model = 8
  - intermediate = (8 * d) / 3 = 21  (HGRN-Bit formula, matches kernel)
  - vocab = 16
  - 6 BitLinears/layer (i, f, g, o, gate, down) + 1 LM head = 7 BitLinears total
  - β = 1.0 for every matrix (so LUT/scale paths exercise without extremes)

File layout (matches python/phase_d/intllm/export.py::export_fjm_v9):
  [176 B header] [beta table] [gamma table (empty)] [layer block] [embed] [lm_head]

Size at d=8 / V=16:
  header         : 176 B
  beta table     :   8 + 7*4 =  36 B   (u32 size + u32 n + 7 × f32)
  gamma table    :   8 B              (empty: u32 size=0 + u32 n=0)
  layer block    :  24 + d²  + 3·d·int/4  + 4   (hdr + MLGRU + GLU + eps)
                 =  24 + 64  + 126           + 4 = 218 B
  embedding FP16 :  V·d·2 =  16·8·2 =  256 B
  LM head ternary:  V·d/4 =  16·8/4 =  32 B
  total           ≈ 726 B (well under the 1 KB budget in production plan §1.5).

Weight content: all weights set to +1 (encoding 10 = 2 in ternary).
Embedding: token t maps to a vector of (t/V, t/V, ...). Bias-free path.

This is NOT a trained model — do NOT expect coherent text. The purpose
is purely to exercise the kernel forward path end-to-end for regression.

Usage:
    python3 scripts/build_intllm_tiny.py -o tests/test-models/intllm-tiny.fjm
    python3 scripts/build_intllm_tiny.py --validate <path>   # read-back check
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

# v9 protocol constants (mirrors python/phase_d/intllm/export.py)
FJM_MAGIC = b"FJM1"  # NB: kernel reads little-endian u32 "FJM1" = 0x314D4A46
FJM_VERSION = 9
MODEL_TYPE_INTLLM = 11
QUANT_FORMAT_TERNARY = 2
HEADER_SIZE = 176
LAYER_HDR_SIZE = 24

# Tiny model dimensions
N_LAYERS = 1
D_MODEL = 8
VOCAB = 16
N_HEADS = 1
INTERMEDIATE = (8 * D_MODEL) // 3  # = 21


def _build_header(*, embed_off: int, layer0_off: int, lmhead_off: int, total_size: int) -> bytes:
    h = bytearray(HEADER_SIZE)
    # Per kernel/compute/model_loader.fj offset table (§FJM Binary Format Constants):
    # magic (u32 at 0), version (u32 at 4), model_type (u32 at 8), n_layers (u32 at 12)…
    # Each header field is a full u32 little-endian. The Phase D export.py's
    # `h[4] = FJM_VERSION` convention is BUGGY and would fail mdl_parse_header's
    # `version > 9` check (it leaves garbage in bytes 5-7 that gets OR'd into
    # the u32 version read). This generator uses the canonical exporter layout
    # from export_gemma3_v8.py which is proven against the kernel.
    struct.pack_into("<I", h, 0, 0x314D4A46)             # "FJM1" magic
    struct.pack_into("<I", h, 4, FJM_VERSION)            # version = 9
    struct.pack_into("<I", h, 8, MODEL_TYPE_INTLLM)      # model_type = 11
    # Per model_loader.fj: n_layers@12, d_model@16, n_heads@20, d_head@24,
    # vocab_size@28, quant_bits@32, total_size@36, embed_off@40, layer0_off@44, lmhead_off@48
    struct.pack_into("<I", h, 12, N_LAYERS)
    struct.pack_into("<I", h, 16, D_MODEL)
    struct.pack_into("<I", h, 20, N_HEADS)
    struct.pack_into("<I", h, 24, D_MODEL // N_HEADS)    # d_head
    struct.pack_into("<I", h, 28, VOCAB)
    struct.pack_into("<I", h, 32, 2)                     # quant_bits = 2 (ternary)
    struct.pack_into("<I", h, 36, total_size)
    struct.pack_into("<I", h, 40, embed_off)
    struct.pack_into("<I", h, 44, layer0_off)
    struct.pack_into("<I", h, 48, lmhead_off)
    # v2 fields
    struct.pack_into("<I", h, 52, N_HEADS)               # n_kv_heads
    struct.pack_into("<I", h, 56, 0)                     # ffn_type (unused by Phase D)
    struct.pack_into("<I", h, 60, 1)                     # norm_type = RMSNorm
    struct.pack_into("<I", h, 64, INTERMEDIATE)          # ffn_dim (informational)
    struct.pack_into("<I", h, 68, 0)                     # rope_theta = 0 (NoPE)
    struct.pack_into("<I", h, 72, 0)                     # eos_token (don't care)
    # v3 codebooks at 76..140 — zero (Phase D uses ternary, not KMeans codebooks)
    struct.pack_into("<I", h, 140, 0)                    # final_norm offset (0 — no learnable γ)
    struct.pack_into("<I", h, 144, 0)                    # embed_bits (0 = FP16)
    struct.pack_into("<I", h, 148, 2)                    # lmhead_bits = 2 (ternary)
    # v7 fields at 152..175 — mostly zero for HGRN-Bit NoPE
    struct.pack_into("<Q", h, 152, 0)                    # rope_global = 0
    struct.pack_into("<I", h, 160, 0)                    # sliding_window
    struct.pack_into("<I", h, 164, 0)                    # sliding_pattern
    struct.pack_into("<I", h, 168, N_HEADS)              # n_kv_heads_v7
    struct.pack_into("<H", h, 172, QUANT_FORMAT_TERNARY)
    struct.pack_into("<H", h, 174, 0)                    # group_size (per-matrix β)
    return bytes(h)


def _pack_ternary_all_ones(n_elems: int) -> bytes:
    """Pack n_elems ternary values all equal to +1 (encoded 10 = 2).

    4 entries per byte, 2 bits each, little-endian within byte:
      byte = (2<<0) | (2<<2) | (2<<4) | (2<<6) = 0xAA for any 4-aligned group.
    """
    n_bytes = (n_elems + 3) // 4
    out = bytearray(n_bytes)
    # Fill with 0xAA — this encodes +1, +1, +1, +1 for each 4-entry group.
    # Kernel's km_mf_bitlinear_packed will read each 2-bit field as `2`, which
    # maps to weight value +1 per matmulfree.fj:236 encoding table.
    for i in range(n_bytes):
        out[i] = 0xAA
    # Trailing entries beyond n_elems are also +1; benign since kernel only
    # reads in_features × out_features entries per matrix.
    return bytes(out)


def _build_layer_block(layer_id: int) -> bytes:
    # MLGRU weights (4 × (d, d) ternary)
    mlgru_per_mat = D_MODEL * D_MODEL  # entries per (d, d) matrix
    mlgru_bytes = 4 * (mlgru_per_mat // 4)  # 4 entries per byte
    mlgru_weights = _pack_ternary_all_ones(4 * mlgru_per_mat)

    # GLU weights: gate_proj (2·int, d) + down_proj (d, int)
    gate_elems = 2 * INTERMEDIATE * D_MODEL
    down_elems = D_MODEL * INTERMEDIATE
    glu_weights = _pack_ternary_all_ones(gate_elems + down_elems)
    glu_bytes = len(glu_weights)

    weight_bytes = bytes(mlgru_weights) + bytes(glu_weights)

    rmsnorm_offset = LAYER_HDR_SIZE + len(weight_bytes)
    total_size = LAYER_HDR_SIZE + len(weight_bytes) + 4  # +4 for FP32 eps

    hdr = bytearray(LAYER_HDR_SIZE)
    struct.pack_into("<I", hdr, 0, layer_id)
    struct.pack_into("<I", hdr, 4, total_size)
    struct.pack_into("<I", hdr, 8, mlgru_bytes)
    struct.pack_into("<I", hdr, 12, glu_bytes)
    struct.pack_into("<I", hdr, 16, rmsnorm_offset)
    struct.pack_into("<I", hdr, 20, 0)  # reserved

    return bytes(hdr) + weight_bytes + struct.pack("<f", 1e-6)


def _build_beta_table(n_betas: int) -> bytes:
    out = bytearray()
    out.extend(struct.pack("<I", 4 * n_betas))
    out.extend(struct.pack("<I", n_betas))
    for _ in range(n_betas):
        out.extend(struct.pack("<f", 1.0))
    return bytes(out)


def _build_empty_gamma_table() -> bytes:
    out = bytearray()
    out.extend(struct.pack("<I", 0))
    out.extend(struct.pack("<I", 0))
    return bytes(out)


def _build_embedding() -> bytes:
    """FP16 embedding table shape (V, d). Row t = (t/V, t/V, ...) — deterministic."""
    import numpy as np
    table = np.zeros((VOCAB, D_MODEL), dtype=np.float16)
    for t in range(VOCAB):
        table[t, :] = float(t) / float(VOCAB)
    return table.tobytes()


def build(out_path: Path) -> dict:
    n_betas = 6 * N_LAYERS + 1  # 6 per layer + 1 LM head
    beta_table = _build_beta_table(n_betas)
    gamma_table = _build_empty_gamma_table()
    layer_blocks = [_build_layer_block(i) for i in range(N_LAYERS)]
    embed_bytes = _build_embedding()
    # LM head: ternary (V, d), all +1
    lm_head_bytes = _pack_ternary_all_ones(VOCAB * D_MODEL)

    # Compute offsets: header comes first, then beta_table, then gamma, then layers, then embed, then lmhead
    header_size = HEADER_SIZE
    beta_off = header_size
    gamma_off = beta_off + len(beta_table)
    layer0_off = gamma_off + len(gamma_table)
    total_layer_bytes = sum(len(b) for b in layer_blocks)
    embed_off = layer0_off + total_layer_bytes
    lmhead_off = embed_off + len(embed_bytes)
    total_size = lmhead_off + len(lm_head_bytes)

    header = _build_header(
        embed_off=embed_off, layer0_off=layer0_off, lmhead_off=lmhead_off, total_size=total_size
    )

    parts = [header, beta_table, gamma_table, *layer_blocks, embed_bytes, lm_head_bytes]
    blob = b"".join(parts)
    assert len(blob) == total_size, f"size mismatch: {len(blob)} vs header-claimed {total_size}"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(blob)
    return {
        "path": str(out_path),
        "n_layers": N_LAYERS,
        "d_model": D_MODEL,
        "vocab_size": VOCAB,
        "intermediate": INTERMEDIATE,
        "n_betas": n_betas,
        "total_bytes": len(blob),
        "sections": [
            ("header", 0, header_size),
            ("beta_table", beta_off, len(beta_table)),
            ("gamma_table", gamma_off, len(gamma_table)),
            *[(f"layer_{i}", layer0_off + sum(len(b) for b in layer_blocks[:i]), len(layer_blocks[i]))
              for i in range(N_LAYERS)],
            ("embedding", embed_off, len(embed_bytes)),
            ("lm_head", lmhead_off, len(lm_head_bytes)),
        ],
    }


def validate(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"FJM1":
        raise SystemExit(f"bad magic: {data[:4]!r}")
    v = data[4]
    mt = data[5]
    if v != FJM_VERSION:
        raise SystemExit(f"bad version: {v} (expected {FJM_VERSION})")
    if mt != MODEL_TYPE_INTLLM:
        raise SystemExit(f"bad model_type: {mt} (expected {MODEL_TYPE_INTLLM})")
    qf, = struct.unpack_from("<H", data, 172)
    if qf != QUANT_FORMAT_TERNARY:
        raise SystemExit(f"bad quant_format: {qf} (expected {QUANT_FORMAT_TERNARY})")
    n_layers, = struct.unpack_from("<I", data, 12)
    d_model, = struct.unpack_from("<I", data, 16)
    vocab, = struct.unpack_from("<I", data, 28)
    return {
        "path": str(path),
        "version": v,
        "model_type": mt,
        "quant_format": qf,
        "n_layers": n_layers,
        "d_model": d_model,
        "vocab_size": vocab,
        "total_bytes": len(data),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("-o", "--output", type=Path, default=Path("tests/test-models/intllm-tiny.fjm"),
                    help="output .fjm v9 path")
    ap.add_argument("--validate", action="store_true",
                    help="validate an existing .fjm v9 file instead of building")
    args = ap.parse_args()

    if args.validate:
        info = validate(args.output)
        print(f"[OK] {info['path']}  v{info['version']}  model_type={info['model_type']}  "
              f"qf={info['quant_format']}  L={info['n_layers']}  d={info['d_model']}  V={info['vocab_size']}  "
              f"bytes={info['total_bytes']}")
        return 0

    info = build(args.output)
    print(f"[OK] built {info['path']}  {info['total_bytes']} B")
    for label, off, sz in info["sections"]:
        print(f"     {label:<12s}  off={off:5d}  size={sz:5d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
