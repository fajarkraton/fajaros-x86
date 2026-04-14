# V28.1 Gemma 3 1B Port — Status

**Date:** 2026-04-14
**Status:** ✅ **HEADER PARSE END-TO-END WORKING** — Gemma 3 1B loads from NVMe
and `model-info` displays all 26-layer, d_model=1152, GQA 4:1 fields correctly.
Remaining: weight streaming, dual-theta RoPE, sliding-window attention, first
token generation.

## What Shipped Today (2026-04-14)

| # | Artifact | Commit | Evidence |
|---|----------|--------|----------|
| 1 | `scripts/export_gemma3_v7.py` (.fjm v7 exporter) | `34abe1d` | Produced `build/gemma3_1b_v7.fjm` = 500,974,136 B |
| 2 | MODEL_TYPE=10 fix in exporter | (this commit) | Kernel maps 10 → "Gemma3-1B" + zero-centered RMSNorm |
| 3 | .fjm v7 parser in kernel/compute/model_loader.fj | `e18c8ac` | LLVM kernel compiles clean, ELF ~1.4 MB |
| 4 | Tensor pool @ 0xB70000 for 1280-dim (KM_GEMMA) | `b5aa70e` | `test_gemma_pool_alloc` in kernel_tests.fj |
| 5 | Security disable (SMEP/SMAP/NX) in kernel/main.fj | (this commit) | Unblocks boot — see debug section below |

### Export (WORKING)

```bash
cd ~/Documents/fajaros-x86
~/Documents/Fajar\ Lang/.venv/bin/python scripts/export_gemma3_v7.py \
    -o build/gemma3_1b_v7.fjm
# → 500 MB .fjm v7, header: FJM1 v7 type=10 n_layers=26
```

Header at LBA 0:
```
00000000: 464a 4d31 0700 0000 0a00 0000 1a00 0000  FJM1............
            MAGIC     VERSION=7 TYPE=10   N_LAYERS=26
```

### Parser (WORKING, exercised E2E)

`mdl_parse_header` in `kernel/compute/model_loader.fj`:
- Accepts version 1..=7 (was 1..=6)
- v7 extras (16 bytes @ offset 160-175 of src) stored out-of-line at
  `MDL_V7_EXTRA = 0xBEF200` to avoid clobbering `MDL_STATE_BASE` at
  `MDL_HDR_BASE + 160 = 0xC000A0`
- New accessors (return 0 for version < 7):
  - `mdl_get_rope_global()` → 1,000,000 for Gemma 3
  - `mdl_get_sliding_window()` → 512
  - `mdl_get_sliding_pattern()` → 6

### End-to-End Verification (2026-04-14 12:15)

```
nova> model-load nvme 0
[NVMe] ... FFN: gated dim=6912   Norm: RMSN   RoPE: 10K
nova> model-info
Model Info (.fjm):
  Type:       Gemma3-1B     ← ✅ correct
  Layers:     26            ← ✅ Gemma 3 1B
  d_model:    1152          ← ✅
  Heads:      4 x d_head=256 ← ✅
  Vocab:      262144         ← ✅ 262K BPE
  Quant:      4-bit (layers)
  Embed:      4-bit
  LM head:    4-bit
  Total size: 477 MB
  Source:     NVMe
  KV heads:   1 (GQA 4:1)   ← ✅ 4:1 group-query
  FFN:        gated dim=6912 ← ✅ intermediate_size=6912
  Norm:       RMSN          ← ✅
  RoPE:       10K            ← local theta (global 1M in MDL_V7_EXTRA)
```

All 11 Gemma-3-1B header fields round-trip correctly through
Python exporter → .fjm → NVMe LBA 0 → kernel parser → shell display.

### Debug Findings (security hang at boot stage 12)

Bisect identified `security_enable_smep()` (kernel/core/security.fj:39) as the
hang source. Reproduces with pre-V27.5 fj (`4efe025`) and with pre-V28 kernel
(`6c5f43c`), so it's not a compiler regression — it is the known P2 SMEP issue
(see user memory "kernel/main.fj:107: SMEP disabled (P2 security)"). Commits
`7937c93` (SMEP) + `700f887` (SMAP) + `168ef29` (NX enforcement) enabled all
three in a 24-hour window; the underlying U-bit leak in kernel PTEs was never
found. Restoring the previous disabled-by-default state for V28.1.

**Follow-up (P2, not blocking V28.1):**
1. Dump PDE flags on boot to find which entry has U-bit set
2. Fix that entry's flags in `setup_page_tables` (boot/runtime_stubs.S)
3. Re-enable SMEP → SMAP → NX in the order they were originally added

## Disk Image Prep

```bash
qemu-img create -f raw disk.img 1G
dd if=build/gemma3_1b_v7.fjm of=disk.img conv=notrunc bs=1M
# verify: xxd -l 16 disk.img → FJM1 0700 0000 0a00 0000 1a00 0000
```

## Next Steps (Remaining for V28.1 completion)

| Step | Effort est | Evidence needed |
|------|-----------|-----------------|
| Embedding load from NVMe (`embed-load`) | 1h | `weight-status` shows embedding loaded |
| Layer streaming (`ram-load`) × 26 | 2h | All 26 layers parsed, QKV+FFN+norms |
| Dual-theta RoPE (local 10K + global 1M) | 3h | New `rope_apply(v, pos, theta)` that selects by layer |
| Sliding-window attention mask (512) | 2h | Mask applied on non-global layers (0,1,2,3,4,6,7,8,9,10,12,...) |
| First `ask "what is 2+2"` run | 1h | Coherent response |
| Perplexity smoke test (WikiText-2) | 2h | PPL < 50 @ seq_len=512 |
| **Total remaining** | **~11h** | — |

## V28.1 Effort Tally

| Task | Estimate | Actual | Variance |
|------|----------|--------|----------|
| Export script | 8h | 2h | -75% |
| v7 parser + accessors | 8h | 1.5h | -81% |
| MODEL_TYPE fix | — | 0.1h | (bug) |
| Disk image + wiring | 2h | 0.5h | -75% |
| SMEP hang bisect | — | 0.5h | (unplanned) |
| End-to-end header verify | 4h | 0.5h | -87% |
| **Total header path** | **22h** | **5.1h** | **-77%** |

Conforms to pattern in `docs/V27_5_V28_SESSION_RETROSPECTIVE.md`: plans
estimate by feature scope, not actual delta. Full weight streaming +
dual-RoPE + sliding attention + first token is the remaining ~11h, not
the 160h originally in V28.1 planning.
