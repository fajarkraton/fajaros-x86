# V30.GEMMA3 Pre-Flight Findings

> **Phase:** P0 Pre-Flight Audit
> **Date:** 2026-04-18
> **Author:** Claude Opus 4.6
> **Plan:** `GEMMA3_UPGRADE_PLAN.md` v3.0
> **Commit:** (this file)

---

## P0.1 — Boot Smoke Test

**Status:** PASS

```
Boot sequence: steps 1-60 clean
Security triple: PTE_LEAKS=0x0, PTE_LEAKS_FULL=0x0, NX_ENFORCED=0x800
Shell prompt: nova> reached
Commands tested: version, frames, uname — all pass
NVMe: detected when disk attached (1024 MB capacity); ramdisk fallback when absent
```

**Verification command:**
```bash
make test-serial  # 3 invariants pass: shell prompt, version, frames
```

## P0.2 — Baseline Token/sec

**Status:** PASS (test model only; v8 model header-only load)

### Test model (d=16, 2 layers, vocab=64)

```
model-load test → OK (generates + loads in <1s)
infer hello → 5 input tokens, prefill instant, next_token=0 ("\x00")
```

Token/sec on test model: effectively instant (<100ms for 1 prefill token).
Pad-collapse (token_id=0) is a known model-level issue (V30.SIM Track 3 conclusion).

### v8 model (Gemma 3 1B from NVMe)

```
model-load nvme 0 → header loaded OK
Model Info:
  Type:       Gemma3-1B
  Layers:     26
  d_model:    1152
  Heads:      4 x d_head=256
  Vocab:      262144
  Quant:      4-bit group-wise (g=128)
  Embed:      4-bit
  LM head:    4-bit
  Total size: 514 MB
  KV heads:   1 (GQA 4:1)
  FFN:        gated dim=6912
  Norm:       RMSN
  RoPE:       10K
```

Full inference not timed this session (requires embed-load + ram-load + ask,
~3+ min per token from V30.SIM FJTRACE capture baseline: 25,322 records / 69 tokens
in ~3 min = ~23 tokens/min = ~0.38 tok/sec).

### CRITICAL: v8 disk is 4-bit, not 2-bit

The existing `disk_v8.img` uses **4-bit group-wise quantization** (g=128),
yielding **514 MB** total model size. The plan assumes 2-bit FajarQuant
quantization yielding ~250 MB. This is a known gap:

- P8.G2 (`export_gemma3_v9.py`) will re-export with 2-bit FajarQuant
- Current v8 disk serves as architecture validation (header format, GQA params)
- 4-bit model does NOT fit in 256 MB frame allocator (needs P6.F2 expansion)
- 2-bit model (250 MB) fits within current 256 MB frame allocator

**Impact on plan:** None — P8 explicitly creates the 2-bit export. The v8
disk confirms the model architecture is Gemma 3 1B with the exact parameters
the plan targets.

## P0.3 — V28.1 Gemma Tensor Pool

**Status:** PARTIAL (no direct probe)

No `memmap` shell command exists. Model infrastructure verified indirectly:
- `model-load nvme 0` successfully parses v8 .fjm header
- `model-load test` generates + loads test model into memory
- Frame allocator: 65536 frames (256 MB), 2072 used (8.3 MB) at boot
- After model header load: 2121 frames used (8.5 MB) — +200 KB for header

The tensor pool at 0xB70000 (V28.1) is a static allocation for the SmolLM
model. For Gemma 3 1B (d=1152 > slot max 1024), the plan requires
frame-allocated vectors (P2.B3). The old tensor pool is NOT sufficient for
Gemma 3 — this is expected and addressed by P2.B3.

**TODO (nice-to-have):** Add `memmap` or `memprobe <addr>` shell command
for diagnostic memory inspection.

## P0.4 — 1 GB Identity Mapping

**Status:** PASS (code-confirmed)

```
kernel/main.fj:219    extend_identity_mapping()      // 128-256 MB
kernel/main.fj:220    extend_identity_mapping_512()  // 256-1024 MB (1 GB)
```

`extend_identity_mapping_512()` adds PD entries 128-511 covering
physical 256 MB - 1 GB, using 2 MB huge pages. Also maps PD2 entries
0-511 for 1 GB - 2 GB range.

Boot banner says "128MB identity" but this is the INITIAL mapping —
extensions happen during boot steps 7-12 (before shell prompt).

`pteaudit` confirms clean page tables:
```
Leaf PAGE_USER leaks: 0 (SMEP-safe)
All-level PAGE_USER leaks: 0 (SMAP-clean)
```

**Note:** Identity mapping covers PAGE TABLE entries for 1 GB+.
Frame allocator bitmap covers 256 MB (65536 × 4KB frames). These are
different: page tables map the address space; frame allocator manages
dynamic allocation within it. P6.F2 expands the frame allocator
(TOTAL_FRAMES 32768→262144) to match the full mapped range.

## P0.5 — Multi-Repo State Check

**Status:** PASS

```
fajar-lang:   0 unpushed | M CLAUDE.md + 3 untracked examples (Track 3 artifacts)
fajaros-x86:  0 unpushed | ?? scripts/__pycache__/ (gitignore candidate)
fajarquant:   0 unpushed | ?? scripts/diag_gate_proj.py (Track 3 diagnostic)
```

All 3 repos synced with origin/main. Loose Track 3 artifacts noted;
non-blocking.

## Summary

| Check | Result | Notes |
|-------|--------|-------|
| Boot stable | PASS | Security triple, shell, commands |
| Test model inference | PASS | Pipeline works, pad-collapse (known) |
| v8 model header load | PASS | Gemma3-1B architecture confirmed |
| Tensor pool | PARTIAL | No direct probe; infrastructure works |
| 1 GB identity map | PASS | Code + pteaudit confirmed |
| Multi-repo state | PASS | All synced |

**P0 Gate: PASS — V28.1 foundation stable, architecture confirmed,
1 GB map reachable. Proceed to P1.**

### Baseline Numbers (for future regression comparison)

| Metric | Value |
|--------|-------|
| Boot steps | 60 (1-60) |
| Frame allocator at boot | 65536 frames (256 MB), 3% used |
| Security triple | PTE_LEAKS=0, PTE_LEAKS_FULL=0, NX=0x800 |
| Test model prefill | <100ms for 5 tokens |
| v8 model size | 514 MB (4-bit); plan targets 250 MB (2-bit) |
| v8 model architecture | Gemma3-1B, 26L, d=1152, 4Q:1KV, FFN=6912, vocab=262K |
| ELF size | 1,417,343 bytes text + 8 data + 69,640 bss |

### Risks Updated

| Risk | P0 Assessment |
|------|---------------|
| R1 (GQA broadcast) | v8 header confirms 4Q:1KV — architecture ready |
| R2 (RoPE drift) | Header shows RoPE:10K (not dual-theta) — may need header v2 update |
| R3 (2-bit coherence) | v8 is 4-bit; 2-bit re-export in P8 — 4-bit serves as architecture validation |
| Frame allocator capacity | 256 MB < 514 MB (4-bit); 256 MB > 250 MB (2-bit planned) — P6.F2 handles |
