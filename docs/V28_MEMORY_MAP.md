# FajarOS V28 Memory Map

**Generated:** 2026-04-16 from `scripts/check_memory_map.py --verbose`
**Status:** 0 overlaps across 33 regions (verified by pre-commit check 4/4)
**Identity mapping:** 0-1 GB via `extend_identity_mapping_512()` + PD2 for 1-2 GB

## Physical Memory Layout

```
Address            Size       Region                   Source
─────────────────────────────────────────────────────────────────────
0x0006F800         2 KB       Kernel flags/state       kernel/main.fj
0x00070000        16 KB       Page tables (PML4/PDP)   boot/runtime_stubs.S
0x005A0000         8 KB       Test scratch area        tests/kernel_tests.fj
0x00600000         4 KB       Process table v2         kernel/sched/process.fj
0x007EF000         4 KB       Kernel stack             boot/runtime_stubs.S
0x00A52000       104 B        TSS (Task State Seg)     boot/runtime_stubs.S

── Compute / ML Region ──────────────────────────────────────────────

0x00BE0000        32 KB       TFM scratch              kernel/compute/transformer.fj
  ├ 0x00BE7C00     512 B      └ RoPE freq (local)      (sub-allocation)
  ├ 0x00BE7E00     256 B      └ TFM FVEC registry      (sub-allocation)
  └ 0x00BE7F00     256 B      └ padding

0x00BE8000        72 B        TFM inference state      kernel/compute/transformer.fj
0x00BEC000         6 KB       Repetition penalty bits  kernel/compute/model_loader.fj
0x00BEE000       128 B        Embed codebook (v5 4b)   kernel/compute/model_loader.fj
0x00BEE080       128 B        LMhead codebook (v5 4b)  kernel/compute/model_loader.fj
0x00BEE100        72 B        Recent token history     kernel/compute/model_loader.fj
0x00BEF100       128 B        LM top-K sample buffer   kernel/compute/model_loader.fj
0x00BEF200        24 B        v7/v8 extra header       kernel/compute/model_loader.fj
0x00BEF800         1 KB       RoPE freq (global 1M)    kernel/compute/transformer.fj

── Model Header + State ─────────────────────────────────────────────

0x00C00000       160 B        Model header copy        kernel/compute/model_loader.fj
0x00C000A0        64 B        Model loader state       kernel/compute/model_loader.fj
0x00C000E0         1 KB       Per-layer codebooks      kernel/compute/model_loader.fj
0x00C004E0        32 B        Embed codebook (v3/v4)   kernel/compute/model_loader.fj
0x00C00500        32 B        LMhead codebook (v3/v4)  kernel/compute/model_loader.fj
0x00C00540        24 B        RAM-resident state       kernel/compute/model_loader.fj
0x00C00558         8 B        RMSNorm gamma mode       kernel/compute/model_loader.fj

── Large Regions (model-dependent) ──────────────────────────────────

0x04000000        64 MB       KV cache                 kernel/compute/transformer.fj
                              (n_layers × max_pos × 2 × kv_dim × 8 B)

0x08000000       ~155 MB      Streaming embedding      kernel/compute/model_loader.fj
                              (Gemma 3 1B v8: 163 MB worst-case)

0x12000000       ~180 KB      STFM working buffers     kernel/compute/transformer.fj
  ├ 0x12000000    12 KB       └ STFM_X (hidden state)
  ├ 0x12003000    12 KB       └ STFM_RES (residual)
  ├ 0x12006000    40 KB       └ STFM_FFN_OUT
  ├ 0x12010000    56 KB       └ STFM_FFN_GATE
  └ 0x12020000    56 KB       └ STFM_FFN_UP

                  ~32 MB gap  (288 → 320 MB, available for future use)

0x14000000       ~360 MB      RAM-resident layers      kernel/compute/model_loader.fj
                              (Gemma 3 1B v8: 380 MB worst-case)

── End of model data: ~700 MB ───────────────────────────────────────
── Identity mapping limit: 1 GB (0x40000000) ────────────────────────
── PD2 extends to 2 GB for LLVM spill + future expansion ───────────
```

## Key Constraints

| Constraint | Value | Reason |
|-----------|-------|--------|
| STREAM_EMBED end | ≤ 0x12000000 | Must not overlap STFM buffers |
| STFM buffers | 0x12000000..0x1202E000 | Between embed end and layers start |
| RAM_LAYERS start | ≥ 0x14000000 | After embed+STFM with 32 MB headroom |
| RAM_LAYERS end | ≤ 0x40000000 | Identity mapping limit (1 GB guard) |
| Total model RAM | ≤ ~700 MB | Combined embed + layers fit in 1 GB |

## V28.2 Bugs Found by This Map

1. **STFM ⊕ STREAM_EMBED overlap** (commit `ba97be6`): STFM_X was at
   0xD500000 (213 MB), inside Gemma 3 embedding (128-283 MB). Inference
   writes to hidden state corrupted tied LM head embeddings. Fixed by
   moving STFM to 0x12000000.

2. **RAM_LAYERS ⊕ STREAM_EMBED overlap** (commit `9bbcb31`): RAM_LAYERS
   was at 0x10000000 (256 MB), overlapping 144 MB embed end at 272 MB.
   Fixed to 0x14000000.

## Validation

```bash
python3 scripts/check_memory_map.py --verbose   # Full layout + collision check
# Exit 0: no overlaps. Exit 1: overlap detected.
# Also runs as pre-commit check [4/4] on model_loader/transformer/kmatrix edits.
```
