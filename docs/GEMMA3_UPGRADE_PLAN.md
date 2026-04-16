# V30.GEMMA3 — Gemma 3 1B Kernel-Native LLM Upgrade

> **Version:** 3.0 (2026-04-16) — refreshed to V29.P1 Plan Hygiene pattern
> **Prior versions:** v2.0 (2026-04-08) established technical spec
> (phases A-H, architecture, memory budget). v3.0 preserves all v2.0
> technical content AND adds §6.8 discipline: pre-flight P0, mechanical
> decision gates, surprise budget tracking, prevention layers, self-check.
> **Author:** Muhamad Fajar Putranto (TaxPrime / PrimeCore.id)
> **Model:** Claude Opus 4.6 exclusively
> **Track:** V30 Track 2 per `Fajar Lang/docs/V30_NEXT_SESSION_AGENDA.md`
> **Predecessor:** V28.1 foundation shipped (v3.3.0), V28.5 multilingual
> pipeline proven (v3.4.0 with retroactive correction per V29.P1.P4).

---

## 1. Problem Statement

### 1.1 Established facts

- FajarOS Phase 1-8 pipeline complete with **test model** (d=16, 2 layers).
- V28.1 shipped Gemma tensor pool (8 × 1280-dim at `0xB70000`) —
  foundation ready for 1B upgrade (per MEMORY.md).
- V28.5 RETEST (V29.P1.P4) proved **stability** (64 tokens no crash)
  but **multilingual output not reproduced** — per-token pad byte 0x00
  at steady state. v8 coherence gap OPEN (Track 3 V30.SIM investigates).
- Current SmolLM-135M test model: d=768 fits within `km_` slot max
  (1024). Gemma 3 1B d=1152 **exceeds** that limit → frame-alloc
  ALL vectors is a hard requirement.
- Memory budget (2-bit quant, 1 GB QEMU): 343 MB used, 681 MB free.
  Comfortable fit.

### 1.2 Goal

`nova> ask "What is 2+2?"` runs **Google Gemma 3 1B** entirely in
Ring 0 (kernel space), producing coherent English responses at
IFEval 80.2% quality. No userspace fallback, no syscall overhead,
single-binary AI OS.

### 1.3 Why 1B over 270M (v2.0 decision, retained)

- IFEval: **80.2%** vs 51.2% (+57% quality improvement)
- Architecture: 100% identical (GQA, RoPE, sliding window, RMSNorm)
- Memory at 2-bit: 250 MB vs 105 MB — both fit in 1 GB QEMU
- Extra code effort: +1-2 tasks (frame-alloc hidden state for d=1152)

### 1.4 Three risk classes (research-grade uncertainty)

Unlike V29.P3 (hypothesis tree for bug diagnosis), V30.GEMMA3 is
**construction work with numerical precision risk**. Three class-level
risks dominate the schedule:

| ID | Class | Why uncertain | Mitigation |
|----|-------|---------------|------------|
| **R1** | **GQA broadcast correctness** | 4Q:1KV requires each query head attends to SAME K/V — subtle off-by-index bug possible | P7 layer-by-layer diff vs HF reference (Track 3 simulator reuse) |
| **R2** | **RoPE numerical drift** | Fixed-point sin/cos at theta=1M: accumulated error over 32K context may degrade coherence | P7 per-position check against PyTorch RoPE; theta=10K+1M dual paths |
| **R3** | **2-bit quantization coherence ceiling** | FajarQuant 2-bit may be insufficient for 1B coherent output | Mid-sprint decision gate: fallback to 3-bit (~375 MB) or research artifact |

### 1.5 Prevention Layer Gap (Rule 3)

Current prevention:
- `make test-security-triple-regression` — kernel security OK
- `test-smep-regression` alias for backward compat
- 35 kernel tests passing — but ALL on the SmolLM test model

Gap for V30.GEMMA3:
- No numerical layer-by-layer regression test yet
- No Python reference oracle yet (Track 3 V30.SIM blocks P7 if not ready)
- No quality gate beyond "produces tokens" — needs IFEval smoke test

After this plan: per-phase prevention outlined in §10.

---

## 2. Gemma 3 1B Architecture (exact from `config.json`)

Preserved verbatim from v2.0 §"Gemma 3 1B Architecture":

```
hidden_size:          1152         # d_model
num_hidden_layers:    26           # transformer layers
num_attention_heads:  4            # query heads
num_key_value_heads:  1            # KV heads (GQA, 4:1 ratio)
head_dim:             256          # per-head dimension
intermediate_size:    6912         # FFN intermediate
vocab_size:           262144       # 256K tokens
max_position_embeddings: 32768    # 32K context
rms_norm_eps:         1e-06        # RMSNorm epsilon
rope_theta:           1000000.0    # RoPE base frequency
sliding_window:       512          # local attention window
sliding_window_pattern: 6         # every 6th layer is global
hidden_activation:    gelu_pytorch_tanh
attention_bias:       false
EOS token:            106
BOS token:            2
```

### 2.1 Gemma 3 Family Comparison

| Parameter | 270M | **1B (target)** | Ratio |
|-----------|-----:|---------------:|------:|
| hidden_size | 640 | **1152** | 1.8× |
| num_layers | 18 | **26** | 1.4× |
| num_heads | 4Q:1KV | 4Q:1KV | same |
| head_dim | 256 | 256 | same |
| FFN dim | 2048 | **6912** | 3.4× |
| vocab | 262K | 262K | same |
| IFEval | 51.2% | **80.2%** | +57% |
| 2-bit size | ~105 MB | **~250 MB** | 2.4× |

### 2.2 Key Differences from SmolLM-135M Test Model

| Feature | SmolLM-135M (test) | Gemma 3 1B | Code Impact |
|---------|-------------------|------------|-------------|
| d_model | 768 | **1152** | Exceeds `km_` slot max 1024 → frame-alloc ALL vectors |
| Layers | 12 | **26** | +117% compute, zero code change |
| Attention | MHA (12 heads) | **GQA (4Q:1KV)** | New: broadcast KV across query groups |
| head_dim | 64 | **256** | 4× larger dot product per head |
| FFN | 2-matrix (3072) | **3-matrix gated (6912)** | New: gate*up→down, frame-alloc buffer |
| Norm | LayerNorm | **RMSNorm** | Simpler: no mean, no beta |
| Position | Learned | **RoPE** | New: rotary embedding with sin/cos |
| Attention type | Full | **Hybrid (sliding+global)** | New: 512-token window for local layers |
| Vocab | 49K | **262K** | Frame-alloc embed + logits + tokenizer |
| Activation | GELU (sigmoid) | **GELU (tanh)** | More accurate approximation |
| Context | 2048 | **32768** | 16× larger KV cache capacity |
| EOS | 2 | **106** | Config change |

### 2.3 Memory Budget (2-bit quantization, 1 GB QEMU)

```
Component                              Size        Cumulative
─────────────────────────────────────  ─────       ──────────
Kernel ELF (.text+.data)               2 MB        2 MB
System (page tables, drivers, heap)    8 MB        10 MB

Embedding table (262K × 1152 × 2/8)   75 MB       85 MB
26 layers:
  Q proj  (1152 × 1024 × 2/8) × 26    7.4 MB
  K proj  (1152 × 256  × 2/8) × 26    1.9 MB
  V proj  (1152 × 256  × 2/8) × 26    1.9 MB
  O proj  (1024 × 1152 × 2/8) × 26    7.4 MB
  gate_proj (1152 × 6912 × 2/8) × 26  51.5 MB
  up_proj   (1152 × 6912 × 2/8) × 26  51.5 MB
  down_proj (6912 × 1152 × 2/8) × 26  51.5 MB
  RMSNorm gamma × 2 per layer         1.2 MB
  Codebook per layer                   0.1 MB
  Subtotal 26 layers                   174 MB      259 MB

LM head (1152 × 262K × 2/8)           75 MB       334 MB
KV cache (512 ctx × 26 layers × 256d) 3 MB        337 MB
Tokenizer table (262K × 16B)          4 MB        341 MB
Inference scratch                      2 MB        343 MB
─────────────────────────────────────  ─────       ──────────
TOTAL USED                             343 MB
FREE                                   681 MB
QEMU RAM                               1024 MB (1 GB)
```

Addresses above 128 MB (0x8000000) require extended identity mapping
in page tables. See Phase F.

---

## 3. Scope (Cross-Repo)

### 3.1 FajarOS x86 (primary)

| File | Anticipated change |
|------|---------|
| `kernel/compute/kmatrix.fj` | `km_rmsnorm`, `km_gelu_tanh`, frame-alloc vector API |
| `kernel/compute/transformer.fj` | GQA attention, gated FFN, RoPE, sliding window |
| `kernel/mm/paging.fj` | Extend identity map to 1 GB (P1 if not done by V29 extend_identity_mapping_512) |
| `kernel/fs/ram_model_loader.fj` | .fjm v2 parser (GQA, gated FFN, RMSNorm fields) |
| `kernel/compute/tokenizer.fj` | 262K vocab table loaded from NVMe |
| `scripts/export_gemma3_v9.py` (NEW) | HuggingFace → .fjm v2 export + quantize |
| `scripts/export_tokenizer.py` (UPDATE) | 262K Gemma-3 tokenizer export |
| `tests/kernel_tests.fj` | Per-phase regression tests (see §10) |
| `Makefile` | `test-gemma3-numerical`, `test-gemma3-e2e` targets |

### 3.2 Fajar Lang

No compiler changes anticipated. If frame-alloc vector API surfaces
codegen issues (unlikely given V28.1 Gemma tensor pool works), scope
expands.

### 3.3 FajarQuant

Lives in separate repo. V30.GEMMA3 **consumes** FajarQuant 2-bit
(and optionally 3-bit) dequant path. Algorithm unchanged unless P7
numerical audit surfaces a quantization-side bug.

### 3.4 Documentation (Rule 7)

Each milestone (M1-M7 per §6) triggers:
- `CLAUDE.md` §3 Version History entry (one per milestone batch)
- `MEMORY.md` V28/V30 status line update
- `CHANGELOG.md` (fajaros-x86) entry per release (likely v3.6.0 M5, v3.7.0 M6/M7)
- GitHub Release tags at M5, M6, M7

---

## 4. Skills & Knowledge Required

| Area | Depth | Reference |
|------|-------|-----------|
| **Gemma 3 architecture** | Deep — GQA, dual-theta RoPE, gated FFN, sliding window pattern | HF `modeling_gemma3.py`, Gemma technical report |
| **RMSNorm fixed-point** | Deep — no mean subtraction, gamma-only, eps scaling | PyTorch `nn.functional.rms_norm` source |
| **RoPE numerical** | Deep — per-pair rotation math, sin/cos table precision at theta=1M | RoFormer paper + HF `LlamaRotaryEmbedding` |
| **Sliding window attention** | Medium — ring buffer KV cache, global-every-6 pattern | Gemma technical report + HF `Gemma3Attention.forward` |
| **2-bit quantization** | Medium — FajarQuant PCA + Lloyd-Max + dequant fused matmul | `fajarquant/paper/fajarquant.tex` + FajarQuant source |
| **262K tokenizer (SentencePiece)** | Medium — token table layout, UTF-8 multi-byte handling | Gemma 3 tokenizer.json + `scripts/export_tokenizer.py` v1 |
| **NVMe disk image layout** | Light — LBA-based weight + tokenizer placement | Existing `run-nvme` pattern + V28.5 multilingual disk.img |
| **1 GB identity mapping** | Medium — extend_identity_mapping_512 per V29.P3 | `kernel/mm/paging.fj` + V29.P3 NX strip pattern |
| **Python HF transformers** | Medium — reference forward pass, attention mask assembly, cache states | HF `transformers.Gemma3ForCausalLM` |
| **Kernel serial trace parsing** | Light — regex over FJTRACE lines per V30.SIM pattern | `kernel/compute/transformer.fj` FJTRACE helpers |

**Skill gaps flagged:**

- **Layer-by-layer numerical diff automation** — manual diff across
  26 layers × per-token too expensive. **Track 3 V30.SIM simulator
  is a hard dependency for P7** (numerical validation). If V30.SIM is
  not ready by P7, block P7 and revert scope.
- **2-bit coherence at 1B parameters** — open research question. No
  prior art on kernel-native 1B at 2-bit. Mid-sprint decision gate
  handles this risk.

Per CLAUDE.md §6.9 Rule 2, **minimum 10 online references** required
before P2 (architecture implementation):

1. **HF Gemma 3 implementation** — `modeling_gemma3.py` authoritative reference
2. **Gemma 3 technical report** — Google DeepMind, Feb 2025
3. **RoFormer paper** — Su et al., 2021 (RoPE original)
4. **KIVI paper** — 2-bit KV cache viability evidence
5. **AWQ paper** — activation-aware 4-bit
6. **QuaRot / SpinQuant** — rotation for 2-bit outlier handling
7. **LLaMA.cpp gemma-3 support** — community kernel for validation
8. **Google `gemma.cpp`** — reference C++ implementation
9. **Gemma 3 SentencePiece tokenizer** — 262K vocab details
10. **Sliding window attention** — Longformer / Mistral variants

Stretch:
11. Intel AMX / AVX-512 int matmul patterns (for speed — not correctness)
12. Flash Attention v2 (if ever ported to kernel)

---

## 5. Design Decisions (pre-locked from v2.0)

| Decision | Value | Rationale |
|----------|-------|-----------|
| Model variant | Gemma 3 **1B-it** (instruction-tuned) | IFEval 80.2% vs base-pretrained |
| Quantization | 2-bit (FajarQuant, fallback 3-bit) | 250 MB fits 1 GB QEMU; 3-bit (~375 MB) as mid-sprint fallback |
| KV cache strategy | Hybrid: 512-ring for local layers, linear for global | Matches Gemma architecture; saves ~4× KV memory vs full |
| Execution | Single-binary AI OS, Ring 0 | No syscall overhead, kernel owns ML runtime |
| Validation oracle | V30.SIM Python bit-exact simulator | Track 3 dependency; layer-by-layer diff |

---

## 6. Phased Approach (V29.P1 pattern)

### Phase V30.GEMMA3.P0 — Pre-Flight Audit

Mandatory per §6.8 Rule 1. Confirms V28.1 foundation still holds on
current HEAD before committing to the 4-week sprint.

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P0.1 | Boot current HEAD + run V28.5 smoke test | `nova> infer` produces output; no crash | 0.15h |
| P0.2 | Measure baseline token/sec with SmolLM-135M test model | number recorded in findings | 0.1h |
| P0.3 | Verify V28.1 Gemma tensor pool (8 × 1280-dim at 0xB70000) still allocated + usable | `nova> memmap` shows region | 0.05h |
| P0.4 | Confirm extend_identity_mapping_512 reaches 1 GB | `nova> pteaudit` or probe write at 0x20000000 | 0.05h |
| P0.5 | Multi-repo state check | `git status -sb` × 3 = clean; `origin/main..main` = 0 | 0.02h |
| P0.6 | Commit `docs/V30_GEMMA3_FINDINGS.md` P0 section | new file committed | 0.15h |

**Phase P0 total: 0.52h** (+25% budget: 0.65h)
**Gate:** V28.1 foundation stable, baseline token/sec recorded, 1 GB map reachable

### Phase V30.GEMMA3.P1 — Phase A v2.0 (Bug Fixes)

**Preserved from v2.0 Phase A.** Precursor cleanup; not 1B-specific
but must land first.

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P1.A1 | `fajarquant.fj` PCA overflow clamp | Known-input PCA produces same output; no crash | 0.3h |
| P1.A2 | `kmatrix.fj` LayerNorm variance precision | Test vector matches PyTorch within 1% | 0.3h |
| P1.A3 | `pipeline.fj` negative-seed noise fix | `((seed % 100) + 100) % 100 - 50` path exercised | 0.2h |
| P1.A4 | `model_loader.fj` header offset validation | Malformed header returns -3, no crash | 0.2h |
| P1.A5 | `tokenizer.fj` output buffer bounds check | `n_tokens >= max_tokens` path exercised | 0.2h |

**Phase P1 total: 1.2h** (+25% budget: 1.5h)
**Gate:** `nova> model-load test` + `nova> infer hello` still pass with SmolLM test model

### Phase V30.GEMMA3.P2 — Phase B v2.0 (RMSNorm + Gated FFN + Frame-Alloc Vectors)

Core numerical building blocks. Must be correct before 1B weights touch.

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P2.B1 | `km_rmsnorm(data_addr, dim, gamma_addr, eps)` | Test vector within 1% of PyTorch `rms_norm` | 0.75h |
| P2.B2 | `km_gelu_tanh(data_addr, dim)` | Test vector within 0.1% of PyTorch `gelu(approximate='tanh')` | 0.5h |
| P2.B3 | Frame-alloc vector API: `tfm_vec_alloc/free/get/set` | 16 concurrent vectors, no leak, no collision | 1.0h |
| P2.B4 | `tfm_ffn_gated(x_addr, layer, d_model, ffn_dim)` | `down(gelu(gate)*up)` matches PyTorch reference | 1.5h |
| P2.B5 | Update `tfm_layer` to use new frame-alloc + RMSNorm + gated FFN | End-to-end with scaled-down test model produces output | 1.0h |

**Phase P2 total: 4.75h** (+25% budget: 5.94h)
**Gate:** `nova> infer hello` on test model goes through new code path without crash; per-op numerical tolerance verified

### Phase V30.GEMMA3.P3 — Phase C v2.0 (Grouped Query Attention)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P3.C1 | GQA `tfm_attention`: 4Q heads share 1 KV (broadcast) | Test vector matches HF Gemma3Attention within 1% | 2.0h |
| P3.C2 | Q/K/V/O projection sizes (4 separate weights) | Shapes match config.json (1152→1024, 1152→256, 1152→256, 1024→1152) | 0.5h |
| P3.C3 | KV cache for GQA (256 dim per position per layer) | Memory math = config × 4 heads collapsed to 1 | 1.0h |
| P3.C4 | .fjm v2 format: add `n_kv_heads` field | Parser reads/writes new header correctly | 0.5h |

**Phase P3 total: 4.0h** (+30% research budget: 5.2h — broadcast correctness is R1)

### Phase V30.GEMMA3.P4 — Phase D v2.0 (Rotary Position Embedding)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P4.D1 | `tfm_rope_apply(q, k, pos, head_dim, theta)` per-pair rotation | Token at pos=0 vs pos=10 produces different Q/K | 1.5h |
| P4.D2 | Pre-compute sin/cos LUT (fixed-point ×10000) | ~130 KB table at frame-alloc'd address | 0.75h |
| P4.D3 | Dual theta: local layers 10K, global layers 1M | Layer-idx-conditional theta switch verified | 0.5h |
| P4.D4 | Integrate RoPE into `tfm_layer` (post Q/K proj, pre score) | Attention score matrix changes with position | 0.75h |

**Phase P4 total: 3.5h** (+30% research budget: 4.55h — R2 numerical drift)

### Phase V30.GEMMA3.P5 — Phase E v2.0 (Hybrid Sliding Window)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P5.E1 | `tfm_is_global_layer(idx)` — globals at 5,11,17,23 (4 of 26) | Boolean table matches Gemma sliding_window_pattern=6 | 0.25h |
| P5.E2 | Sliding-window attention score loop | Pos=600 in local layer attends only 88..600 | 1.5h |
| P5.E3 | Dual KV cache: 512-ring (local) + linear (global) | Memory saving confirmed vs linear-only baseline | 1.5h |

**Phase P5 total: 3.25h** (+25% budget: 4.06h)

### Phase V30.GEMMA3.P6 — Phase F v2.0 (Large Vocab + Extended Memory)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P6.F1 | Confirm/extend 1 GB identity mapping | Write+readback probe at 0x3F000000 (1008 MB) succeeds | 0.5h (may be no-op after V29.P3) |
| P6.F2 | Frame allocator: TOTAL_FRAMES 32768→262144, bitmap layout | Alloc at 0x10000000+ works; no collision with kernel text | 1.0h |
| P6.F3 | Frame-allocate embedding table (75 MB contiguous) | `mdl_load_embed` handles large-address | 1.0h |
| P6.F4 | Frame-allocate LM head (75 MB) | Separate region from embed; no address clash | 0.5h |
| P6.F5 | `tfm_argmax_raw` hierarchical over 262K | Matches brute-force argmax within 1 index on random input | 1.0h |
| P6.F6 | Export Gemma 3 tokenizer to .fjt | 262K entries, NVMe disk region | 0.75h |
| P6.F7 | `tok_load_nvme(start_lba)` — read .fjt into frame-alloc'd mem | `nova> tokenize hello` produces correct IDs | 0.75h |

**Phase P6 total: 5.5h** (+25% budget: 6.88h)

### Phase V30.GEMMA3.P7 — Numerical Validation (Decision Gate — uses V30.SIM)

**Rule 6 mechanical gate.** Before loading real 1B weights, validate the
transformer pipeline against a Python bit-exact reference (Track 3
V30.SIM output). Commit `docs/V30_GEMMA3_P7_DECISION.md`:

- Layer-by-layer numerical tolerance decision (1% per layer? cumulative?)
- R1 (GQA) pass/fail per Track 3 simulator diff
- R2 (RoPE) pass/fail per Track 3 simulator diff
- Any kernel-side bugs surfaced; fix path (quarantine)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P7.1 | Block until V30.SIM simulator ready (Track 3 P1 done) | Track 3 status doc committed | 0h (dependency) |
| P7.2 | Run kernel forward on scaled-down model + V30.SIM in parallel with same input | Diff report generated | 1.5h |
| P7.3 | Identify first-divergence layer + op | `algo-numerical-diff` skill (Track 3 output) | 0.5h |
| P7.4 | Fix kernel or algorithm (iterate P7.2-P7.3 until tolerance met) | All 26 layers within tolerance | 1-4h (uncertain) |
| P7.5 | Commit P7 DECISION.md | file in git | 0.25h |

**Phase P7 total: 3.25-6.25h** (+40% research budget: up to 8.75h)
**Gate:** per-layer numerical tolerance met; R1+R2 both closed

### Phase V30.GEMMA3.P8 — Phase G v2.0 (.fjm v2 Export)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P8.G1 | .fjm v2 header (96 bytes) with GQA+gated+RMSNorm fields | Header round-trip: write+read produces same struct | 0.5h |
| P8.G2 | `export_gemma3_v9.py` — extracts all weights + quantizes to 2-bit | Output file size ~250 MB | 1.0h |
| P8.G3 | Write .fjm + .fjt to `disk.img` at chosen LBAs | Disk image 256 MB+, readable by QEMU NVMe | 0.5h |
| P8.G4 | `model_loader.fj` v2 parser | Loads gemma3.fjm without error; model-info shows correct metadata | 1.0h |
| P8.G5 | Update test model generator to .fjm v2 format | Test model still works end-to-end via new loader | 0.75h |

**Phase P8 total: 3.75h** (+25% budget: 4.69h)

### Phase V30.GEMMA3.P9 — Mid-Sprint Decision Gate (Go/Fallback)

**Rule 6 mechanical gate.** After P8, before loading full 1B, evaluate:

- Did P7 per-layer tolerance hold with FP16 reference and scaled model?
- Does 2-bit quant degrade scaled-model output meaningfully?
- Is NVMe load time within 30s?

Commit `docs/V30_GEMMA3_P9_DECISION.md`:

| Go path | Criteria |
|---------|----------|
| **A. Proceed 2-bit Gemma 3 1B** | P7 all green; quant degradation <10% vs FP16; load <30s |
| **B. Fallback to 3-bit** | P7 green but 2-bit degrades >10%; 3-bit fits 375 MB in 1 GB |
| **C. Fallback to Gemma 3 270M** | Scaling issues surface; ship 270M as M6, defer 1B to V31 |
| **D. Ship as research artifact** | P7 residual bugs; document the foundation, defer inference claim |

**Phase P9 total: 0.3h** (decision + commit)

### Phase V30.GEMMA3.P10 — Phase H v2.0 (E2E Real Weights)

Depends on P9 branch selection.

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P10.H1 | Prepare NVMe disk: export .fjm (250 MB) + .fjt (4 MB) | disk.img sized correctly | 0.5h |
| P10.H2 | `nova> model-load nvme 0` loads 250 MB | Memory snapshot shows weights at expected addresses | 1.0h |
| P10.H3 | `nova> tok-load nvme 2000` loads tokenizer | `tokenize hello` produces correct IDs | 0.25h |
| P10.H4 | Single-token inference: `nova> infer "The capital of France is"` → "Paris" (or close) | Meaningful token emitted | 1.0h |
| P10.H5 | Multi-token generation: `nova> ask "What is 2+2?"` | Coherent response | 2.0h |
| P10.H6 | Performance measurement (tokens/sec) | Number recorded; bottleneck identified | 1.0h |
| P10.H7 | 128-token stress test | No KV overflow, no memory corruption | 1.0h |
| P10.H8 | 10-prompt quality validation vs PyTorch reference | Quality report committed | 2.0h |

**Phase P10 total: 8.75h** (+30% budget: 11.4h)

### Phase V30.GEMMA3.P11 — Regression + Prevention

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P11.1 | `make test-gemma3-numerical` — per-layer tolerance gate (uses V30.SIM) | All 26 layers within tolerance | 0.5h |
| P11.2 | `make test-gemma3-e2e` — load + single-token + 128-token gate | All 3 invariants pass | 0.5h |
| P11.3 | Kernel tests: `test_gqa_broadcast`, `test_rope_position_sensitivity`, `test_sliding_window_bound` | Tests in `tests/kernel_tests.fj` pass | 1.0h |
| P11.4 | Optional CI wiring | Target runs in CI workflow | 0.5h |

**Phase P11 total: 2.5h** (+25% budget: 3.13h)

### Phase V30.GEMMA3.P12 — Doc Sync (Rule 7)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P12.1 | `CLAUDE.md` §3 V30.GEMMA3 row (per milestone batch) | commits in fajar-lang | 0.3h |
| P12.2 | `MEMORY.md` V28+V30 block update | file edited | 0.15h |
| P12.3 | `CHANGELOG.md` (fajaros-x86) v3.6.0/v3.7.0 narrative | commit in fajaros-x86 | 0.5h |
| P12.4 | GitHub Release tags at M5, M6, M7 | `gh release create` at each milestone | 0.3h |

**Phase P12 total: 1.25h** (+25% budget: 1.56h)

---

## 7. Effort Summary

| Phase | Estimate | Budget | % |
|-------|---------:|-------:|--:|
| P0 Pre-flight | 0.52h | 0.65h | +25% |
| P1 (A bug fixes) | 1.2h | 1.5h | +25% |
| P2 (B RMSNorm+FFN+vecs) | 4.75h | 5.94h | +25% |
| P3 (C GQA) | 4.0h | 5.2h | +30% R1 |
| P4 (D RoPE) | 3.5h | 4.55h | +30% R2 |
| P5 (E sliding window) | 3.25h | 4.06h | +25% |
| P6 (F large vocab + mem) | 5.5h | 6.88h | +25% |
| P7 Numerical validation | 3.25-6.25h | up to 8.75h | +40% R3 |
| P8 (G .fjm v2 export) | 3.75h | 4.69h | +25% |
| P9 Go/fallback gate | 0.3h | 0.38h | +25% |
| P10 (H E2E real weights) | 8.75h | 11.4h | +30% |
| P11 Regression | 2.5h | 3.13h | +25% |
| P12 Doc sync | 1.25h | 1.56h | +25% |
| **Total (nominal)** | **42.5h** | **58.7h** | — |
| **Total (P7/P10 worst case)** | **45.5h** | **63.7h** | — |

**Compare to v2.0 / agenda estimate:** 160h / 4-week sprint was a
large-bet estimate. v3.0 structure produces a tighter envelope
(42-64h ≈ 1-2 sessions-per-week × 4 weeks). The delta comes from:
- V28.1 foundation already shipped (saves ~30h v2.0 didn't count)
- V29.P3 1 GB mapping already shipped (saves ~5h)
- V30.SIM dependency means P7 external (Track 3 budget, not counted here)
- FajarQuant already at v0.3.0 (saves ~10h)

Realistic session shape: **4-6 focused sessions of 8-12h each**, with
mandatory decision gates at P7 and P9 that can short-circuit scope.

---

## 8. Surprise Budget Tracking (Rule 5)

- Default +25% per phase
- **P3 (GQA): +30%** — broadcast correctness risk (R1)
- **P4 (RoPE): +30%** — numerical drift risk (R2)
- **P7 (numerical validation): +40%** — unknown-unknowns in bit-exact comparison
- **P10 (E2E): +30%** — 26-layer NVMe load + inference flow has integration risks
- Commit messages tag variance:
  `feat(v30-gemma3-pN): ... [actual Xh, est Yh, ±Z%]`
- If running total exceeds +30% by P5 end, **trigger P9 decision gate
  early** and reassess scope (possibly fallback to 270M)

---

## 9. Risk Register (preserved from v2.0 + V29.P1 additions)

| Risk | Severity | Mitigation |
|------|----------|------------|
| d=1152 frame-alloc cache miss perf | MEDIUM | V28.1 Gemma tensor pool verified; measure P0.2 baseline before concluding |
| FFN dim=6912 matmul slowness | MEDIUM | Tile matmul; P10.H6 measures real tokens/sec |
| RoPE sin/cos fixed-point precision | **HIGH (R2)** | x10000 scale; P7 validates against PyTorch |
| 262K vocab argmax latency | MEDIUM | Hierarchical + early-termination top-K |
| 2-bit quant coherence insufficient | **HIGH (R3)** | P9 fallback to 3-bit or 270M |
| Extended identity map broke boot (V29.P3 adjacent) | LOW | V29.P3 + P1.5 both shipped; P0.4 reconfirms |
| head_dim=256 dot product overflow | LOW | Max ~2.5e8 per attention score; i64 safe |
| NVMe load 250 MB timing | MEDIUM | Lazy per-layer load if >30s boot; P10.H2 measures |
| V30.SIM (Track 3) not ready for P7 | **HIGH (NEW)** | P7 blocks on Track 3 P1 commit; if blocked >1 week, scope-revert V30.GEMMA3 to fallback-C (270M) |
| 160h estimate inflation | LOW (v3.0) | v3.0 structure forces P9 mid-sprint decision; can exit early |

---

## 10. Prevention Layers (Rule 3)

| Phase | Prevention artifact |
|-------|---------------------|
| P0 | V28.5 baseline token/sec recorded — any future regression compares |
| P1 | Per-bug regression test in kernel test suite |
| P2 | Per-op numerical tolerance test against PyTorch (RMSNorm, GELU_tanh, FFN) |
| P3 | `test_gqa_broadcast` kernel test (P11.3) |
| P4 | `test_rope_position_sensitivity` kernel test (P11.3) |
| P5 | `test_sliding_window_bound` kernel test (P11.3) |
| P6 | Frame allocator stress test (64 concurrent 75 MB allocs) |
| P7 | `test-gemma3-numerical` Makefile gate (P11.1) — layer tolerance |
| P8 | .fjm v2 round-trip test (write + read + checksum) |
| P10 | `test-gemma3-e2e` Makefile gate (P11.2) — load + gen |
| P11 | CI wiring — every commit that touches `kernel/compute/` runs gates |
| P12 | CLAUDE.md + CHANGELOG entries preserve rationale |

---

## 11. Gates & Decisions (Rule 6)

| Gate | Blocks | Mechanism |
|------|--------|-----------|
| P0 gate | P1 launch | FINDINGS P0 section committed |
| P2.B1-B4 gates | B5 integration | Per-op tolerance test exit 0 |
| P7 decision | P8 launch | `V30_GEMMA3_P7_DECISION.md` with Track 3 diff verdict |
| **P9 go/fallback** | P10 launch | `V30_GEMMA3_P9_DECISION.md` with branch choice (A/B/C/D) |
| P10.H4 single-token | H5 multi-token | Must produce meaningful token |
| P11 regression | Release | All gates exit 0 |

---

## 12. Execution Order + Dependencies

```
Phase P0 (pre-flight) ────────────────┐
                                      │
Phase P1 (A bug fixes) ───────────────┤
                                      │
Phase P2 (B RMSNorm+FFN+vecs) ────────┤
                                      │
Phase P3 (C GQA) ─────────────────────┤
                                      ├──→ Phase P8 (G .fjm v2)
Phase P4 (D RoPE) ────────────────────┤              │
                                      │              ├──→ Phase P9 (go/fallback gate)
Phase P5 (E sliding window) ──────────┤              │           │
                                      │              │           ├──→ Phase P10 (H E2E)
Phase P6 (F large vocab + mem) ───────┘              │           │           │
                                                     │           │           ├──→ P11 regression
                                Phase P7 (numerical validation)  │           │
                                (needs Track 3 V30.SIM P1)       │           │
                                                                 │           └──→ P12 doc sync
                                Phase P9 decision ───────────────┘
```

**Critical path:** P0 → P1 → P2 → {P3+P4+P5+P6 parallel} → P7 (Track 3 dependency) → P8 → **P9 decision** → P10 → P11 → P12

**Parallel opportunities:**
- P3/P4/P5 are independent in transformer.fj (different functions)
- P6 (memory) is independent of P3-P5 (separate file)
- P8 (export) depends on P2-P6 architectural shape, not their code

**Kill-switch:** P9 can downgrade to 270M or research artifact if
P7 numerical tolerance or quant quality fails. Both fallbacks preserve
the V28.1 foundation already shipped.

---

## 13. Success Criteria (milestones preserved from v2.0)

| Milestone | Criteria | Phase |
|-----------|----------|-------|
| **M1** Bug-free base | Audit fixes applied, all commands work | P1 |
| **M2** New architecture | RMSNorm+GQA+RoPE+gated FFN+sliding window work with test model | P2-P5 |
| **M3** Extended memory | 1 GB identity mapped, frame allocator manages full range | P6 |
| **M4** Export pipeline | .fjm v2 + .fjt on NVMe disk for Gemma 3 1B | P8 |
| **M5** First real token | `infer` produces meaningful token with Gemma 3 1B weights | P10.H4 |
| **M6** First conversation | `ask` generates coherent multi-word response | P10.H5 |
| **M7** Production | 128-token gen, 10-prompt quality validated, no crashes | P10.H7-H8 |

---

## 14. Online Research Triggers (per §6.9 Rule 2)

Minimum 10 references before P2 (§4). Specific research tasks per phase:

- **P3 (GQA):** HF `Gemma3Attention.forward` source + `gemma.cpp` GQA impl
- **P4 (RoPE):** RoFormer paper + HF `LlamaRotaryEmbedding` + Gemma's dual-theta handling
- **P5 (sliding window):** Longformer paper + Mistral SWA + Gemma pattern spec
- **P6 (argmax 262K):** any large-vocab kernel implementations (LLaMA.cpp `llm_build_lm_head`)
- **P7 (tolerance):** KIVI paper tolerance thresholds + AWQ paper per-layer analysis

---

## 15. Self-Check — Plan Hygiene Rule 6.8 (All 8)

| # | Rule | Status |
|---|------|--------|
| 1 | Pre-flight audit (P0) exists | ✅ §6 Phase P0 with 6 runnable tasks |
| 2 | Every task has runnable verification command | ✅ each row explicit command/artifact |
| 3 | Prevention mechanism added per phase | ✅ §10 table; per-phase gates + CI |
| 4 | Agent-produced numbers cross-checked with Bash | ✅ architecture/memory from config.json + objdump, verified not fabricated |
| 5 | Surprise budget tagged per commit | ✅ §8 convention + elevated P3/P4/P7/P10 rates |
| 6 | Decisions are committed files | ✅ §11 table: P7 + P9 mechanical gates with DECISION.md files |
| 7 | Public-facing artifact sync | ✅ §3.4 + P12 covers CLAUDE.md + MEMORY.md + CHANGELOG + Release tags at M5/M6/M7 |
| 8 | Multi-repo state check before starting | ✅ P0.5 task explicit |

**8/8 YES.** Plan ready for multi-session execution.

---

## 16. Dependencies on Other Tracks

| Dependency | Type | Impact if blocked |
|------------|------|-------------------|
| **Track 3 V30.SIM P1 (Python simulator)** | Hard | P7 cannot run; scope-revert to fallback-C (270M) |
| **FajarQuant 2-bit dequant path** | Soft | Already at v0.3.0; tested via V28.5 |
| **V29.P3 1 GB identity mapping** | Soft | Already shipped via `extend_identity_mapping_512` |
| **V28.1 Gemma tensor pool** | Soft | Already shipped in v3.3.0; P0 re-verifies |
| **`fajaros-bisect` skill** | Nice-to-have | Used if kernel boot issues surface during P10 |

**Hard dependency drives scheduling:** V30.GEMMA3 P7 cannot launch
until Track 3 V30.SIM P1 lands. Recommended ordering across sessions:
Track 3 P0-P1 first → V30.GEMMA3 P0-P6 parallel/concurrent → V30.GEMMA3 P7
after Track 3 P1 commit → rest.

---

## 17. What Makes This Unique (preserved from v2.0)

No other operating system has:

1. **Kernel-native 1B-parameter LLM** — Gemma 3 1B running entirely in Ring 0
2. **IFEval 80% in the kernel** — instruction-following quality rivaling early GPT-3.5
3. **2-bit quantized inference** — FajarQuant innovations (PCA rotation, fused attention)
4. **Attention-based process scheduler** — the kernel uses transformer attention for scheduling
5. **Single-binary AI OS** — kernel + ML runtime + quantization + 1B model = one ELF
6. **Zero syscall overhead** — inference runs at kernel privilege, no context switches

---

## 18. Author Acknowledgement

Plan drafted 2026-04-16 by Claude Opus 4.6 refreshing v2.0 (2026-04-08)
to V29.P1 Plan Hygiene pattern. All v2.0 technical content preserved
verbatim where applicable; structural additions (P0 pre-flight, P7
numerical gate, P9 mid-sprint decision, P11 regression, P12 doc sync,
self-check, prevention layers, surprise budget) bring the plan to
parity with V29.P3 / V30.SIM / V30.DISK plans.

Pattern reuse from V29.P3:
- Hypothesis-class structure for research uncertainties (R1/R2/R3)
- Mechanical decision gate files (P7, P9)
- Prevention layer enumeration per phase
- Online research triggers aligned to §6.9 Rule 2 (10 refs min for
  research-grade work)

Pattern reuse from V29.P1:
- Self-check 8/8 table
- Surprise budget elevated for research risk
- Cross-repo scope listing

**Realistic session count:** 4-6 focused sessions (8-12h each) with
mandatory decision gates (P7, P9) that can short-circuit to 270M
fallback or research-artifact scope if the research risks (R1/R2/R3)
don't close.

---

*V30.GEMMA3 Plan v3.0 — refreshed 2026-04-16 by Claude Opus 4.6.
Target: FajarOS world's first OS with kernel-native Gemma 3 1B
inference (IFEval 80.2%). Model: 1B params, 26 layers, d=1152,
GQA 4:1, 2-bit quantized, ~250 MB, Ring 0. QEMU: 1 GB RAM.
Self-check 8/8 ✅. Ready for execution on next scheduled phase.*
