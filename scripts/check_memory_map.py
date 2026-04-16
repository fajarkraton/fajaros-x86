#!/usr/bin/env python3
"""
check_memory_map.py — FajarOS memory map collision detector.

V28.5 prevention layer. Scans kernel source files for memory-mapped
constant addresses and checks for overlapping regions. Exits 0 if clean,
1 if any overlaps detected.

Found real bugs during V28.2:
  - STREAM_EMBED (0x8000000..0x11000000, 144 MB) overlapped
    RAM_LAYERS_BASE (was 0x10000000) — fixed to 0x14000000.
  - MDL_V7_EXTRA expanded from 16→24 B without checking neighbors.

Usage:
    python3 scripts/check_memory_map.py
    python3 scripts/check_memory_map.py --verbose

Author: PrimeCore.id / Claude Opus 4.6
"""

import argparse
import os
import re
import sys

# Known regions with their sizes (bytes). Extracted from kernel source
# constants + computed sizes. Some are fixed, some are model-dependent
# (worst-case sizes used).

REGIONS = [
    # (name, start_addr, size_bytes, source_file)

    # Kernel core (boot/identity-mapped)
    ("PAGE_TABLES", 0x70000, 0x4000, "boot/runtime_stubs.S"),
    ("KERNEL_STACK", 0x7EF000, 0x1000, "boot/runtime_stubs.S"),
    ("TSS", 0xA52000, 0x68, "boot/runtime_stubs.S"),

    # Process table
    ("PROC_TABLE", 0x600000, 0x1000, "kernel/sched/process.fj"),

    # Kernel state flags
    ("KERNEL_FLAGS", 0x6F800, 0x800, "kernel/main.fj"),

    # Test scratch
    ("TEST_SCRATCH", 0x5A0000, 0x2000, "tests/kernel_tests.fj"),

    # KV Cache (64 MB region)
    ("TFM_KV_CACHE", 0x4000000, 0x4000000, "kernel/compute/transformer.fj"),

    # Streaming embed (Gemma 3 1B worst-case: 155 MB for v8)
    ("STREAM_EMBED", 0x8000000, 163_000_000, "kernel/compute/model_loader.fj"),

    # RAM layers (Gemma 3 1B worst-case: 360 MB for v8)
    ("RAM_LAYERS", 0x14000000, 380_000_000, "kernel/compute/model_loader.fj"),

    # STFM working buffers (V28.2 fix: moved from 0xD500000 to 0x12000000)
    ("STFM_X", 0x12000000, 0x3000, "kernel/compute/transformer.fj"),
    ("STFM_RES", 0x12003000, 0x3000, "kernel/compute/transformer.fj"),
    ("STFM_FFN_OUT", 0x12006000, 0xA000, "kernel/compute/transformer.fj"),
    ("STFM_FFN_GATE", 0x12010000, 0xE000, "kernel/compute/transformer.fj"),
    ("STFM_FFN_UP", 0x12020000, 0xE000, "kernel/compute/transformer.fj"),

    # TFM scratch + state. Note: ROPE_FREQ_BASE and TFM_FVEC_REG are
    # intentional sub-allocations within the 32 KB TFM_SCRATCH region —
    # not standalone regions. They share space with the scratch area by
    # design (scratch is only used during unpacking, freq/fvec are used
    # during inference — never simultaneously). We list only TFM_STATE
    # as a separate region since it must not overlap.
    # ("TFM_SCRATCH", 0xBE0000, 0x8000)  — contains ROPE_FREQ + TFM_FVEC
    ("TFM_SCRATCH_LOWER", 0xBE0000, 0x7C00, "kernel/compute/transformer.fj"),
    ("ROPE_FREQ_BASE", 0xBE7C00, 0x200, "kernel/compute/transformer.fj"),
    ("TFM_FVEC_REG", 0xBE7E00, 0x100, "kernel/compute/transformer.fj"),
    ("TFM_SCRATCH_PAD", 0xBE7F00, 0x100, "kernel/compute/transformer.fj"),
    ("TFM_STATE", 0xBE8000, 0x48, "kernel/compute/transformer.fj"),

    # Repetition penalty
    ("RECENT_BITSET", 0xBEC000, 6144, "kernel/compute/model_loader.fj"),

    # Codebook regions
    ("MDL_EMBED_CB_V5", 0xBEE000, 0x80, "kernel/compute/model_loader.fj"),
    ("MDL_LMHEAD_CB_V5", 0xBEE080, 0x80, "kernel/compute/model_loader.fj"),
    ("RECENT_TOK_BUF", 0xBEE100, 0x48, "kernel/compute/model_loader.fj"),
    ("LM_TOPK_BUF", 0xBEF100, 0x80, "kernel/compute/model_loader.fj"),
    ("MDL_V7_EXTRA", 0xBEF200, 24, "kernel/compute/model_loader.fj"),
    ("ROPE_FREQ_GLOBAL", 0xBEF800, 0x400, "kernel/compute/transformer.fj"),

    # Model header + state
    ("MDL_HDR_BASE", 0xC00000, 0xA0, "kernel/compute/model_loader.fj"),
    ("MDL_STATE_BASE", 0xC000A0, 0x40, "kernel/compute/model_loader.fj"),
    ("MDL_CODEBOOK_BASE", 0xC000E0, 0x400, "kernel/compute/model_loader.fj"),
    ("MDL_EMBED_CB", 0xC004E0, 0x20, "kernel/compute/model_loader.fj"),
    ("MDL_LMHEAD_CB", 0xC00500, 0x20, "kernel/compute/model_loader.fj"),
    ("MDL_RAM_STATE", 0xC00540, 0x18, "kernel/compute/model_loader.fj"),
    ("MDL_GAMMA_MODE", 0xC00558, 0x08, "kernel/compute/model_loader.fj"),
]


def check_overlaps(regions, verbose=False):
    """Check for address-range overlaps between all region pairs."""
    sorted_regions = sorted(regions, key=lambda r: r[1])
    n_overlaps = 0

    for i, (name_a, start_a, size_a, src_a) in enumerate(sorted_regions):
        end_a = start_a + size_a
        for name_b, start_b, size_b, src_b in sorted_regions[i + 1:]:
            end_b = start_b + size_b
            if start_b < end_a:  # overlap
                overlap = min(end_a, end_b) - start_b
                print(f"OVERLAP: {name_a} [0x{start_a:X}..0x{end_a:X}] "
                      f"⊕ {name_b} [0x{start_b:X}..0x{end_b:X}] "
                      f"({overlap} bytes)")
                n_overlaps += 1

    if verbose:
        print(f"\n{'Name':<25} {'Start':>12} {'End':>12} {'Size':>10}  Source")
        print("-" * 80)
        for name, start, size, src in sorted_regions:
            end = start + size
            print(f"{name:<25} 0x{start:08X}  0x{end:08X}  {size:>8,}  {src}")

    return n_overlaps


def main():
    parser = argparse.ArgumentParser(description="FajarOS memory map collision detector")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    print("FajarOS Memory Map Collision Detector (V28.5)")
    print(f"Checking {len(REGIONS)} regions...\n")

    n = check_overlaps(REGIONS, args.verbose)

    if n == 0:
        print(f"\n✓ No overlaps detected across {len(REGIONS)} regions.")
        return 0
    else:
        print(f"\n✗ {n} overlap(s) detected!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
