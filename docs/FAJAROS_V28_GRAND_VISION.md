# FajarOS V28+ Grand Vision — Production Plan

**Version:** 1.0 (2026-04-13)
**Author:** Muhamad Fajar Putranto, SE., SH., MH. (TaxPrime / PrimeCore.id) + Claude Opus 4.6
**Baseline:** FajarOS v3.2.0 "Hardened" (V27) -- 106,722 LOC, 183 .fj files, 302 shell commands, 25 kernel tests, boots to `nova>` on QEMU
**Compiler:** Fajar Lang V27 "Hardened" -- 448K LOC Rust, 10,179 tests, 54 modules, 23 CLI subcommands, LLVM + Cranelift backends
**Plan Hygiene:** ALL 8 Rules from CLAUDE.md section 6.8 enforced (pre-flight audit, runnable verification, prevention layer, cross-check, surprise budget, mechanical gates, artifact sync, multi-repo check)

---

## PART 1: VISION STATEMENT

### Mission

**"The world's first AI-native, compiler-verified, single-language operating system."**

FajarOS is not a Linux clone. It is not a macOS replacement. It is a new class of operating system where the programming language IS the security model, where machine learning IS the scheduling policy, and where the entire system -- kernel, drivers, AI, GUI, applications -- is written in a single language with compile-time safety guarantees that no other OS in existence provides.

### Five Pillars Where FajarOS Beats macOS

**Pillar 1: Kernel Memory Safety via Compiler Enforcement**
macOS XNU is written in C/C++ with KASAN, KCOV, and runtime mitigations (SIP, SMEP, SMAP). Every CVE is a C bug that wasn't caught. FajarOS uses `@kernel`/`@device`/`@safe` annotations enforced at compile time. If a `@safe` function calls `port_outb`, the compiler rejects it with error SE020. The attack surface that generates CVEs does not exist.

Evidence: `kernel/security/hardening.fj` (57 LOC), `docs/SAFETY_MODEL.md`, 38 context enforcement tests in `tests/context_enforcement.fj`, and 8 error codes (KE001-KE006, SE020-SE021, DE001) already implemented in the Fajar Lang compiler.

**Pillar 2: AI-Native Kernel (Ring 0 Inference)**
macOS bolts on Core ML as a userspace framework with syscall overhead. FajarOS runs a 1B-parameter transformer (Gemma 3 1B target, currently SmolLM-135M) entirely in Ring 0. The ML scheduler (`kernel/sched/ml_scheduler.fj`, 493 LOC) uses transformer attention to pick the next process. Zero syscall overhead. No userspace round-trip.

Evidence: 7,612 LOC across 11 files in `kernel/compute/`, working inference pipeline with `ask`, `infer`, `tokenize`, `model-info` shell commands, FajarQuant 2-bit quantization.

**Pillar 3: Single-Language Vertical Stack**
macOS mixes C (XNU kernel), Objective-C (frameworks), Swift (applications), Python (ML), and Metal (GPU). Impedance mismatch at every boundary. FajarOS is 100% Fajar Lang -- 106,722 LOC, 183 files, zero FFI boundaries, zero language mismatches. The type system spans from page table entries to GUI widgets.

Evidence: Every `.fj` file in the repo. The Makefile concatenates 183 source files into a single `combined.fj` that compiles to one ELF.

**Pillar 4: Clean Microkernel Architecture**
macOS XNU is a "hybrid" (Mach microkernel + BSD monolithic) that gets neither the isolation of a microkernel nor the performance of a monolith. FajarOS is a clean microkernel: kernel core is 4,621 LOC across 12 files in `kernel/core/`, services (VFS, BLK, NET, display, shell, GUI) run as separate IPC-based processes. Measured at 22KB microkernel ELF vs 264KB monolithic (92% reduction).

Evidence: `build/micro_combined.fj` (2,641 LOC), `services/` directory with 13 service subdirectories, IPC protocol defined in `docs/MICROKERNEL_SPEC.md`.

**Pillar 5: Formal Verifiability Path**
macOS XNU is too large (~6M LOC of C) for formal verification. FajarOS's Ring 0 TCB (trusted computing base) is under 5,000 LOC of Fajar Lang. This is small enough for SMT-based verification of the syscall boundary, capability system, and memory isolation. SeL4 verified 10,000 LOC of C; FajarOS can verify half that with a safer source language.

Evidence: `docs/COMPILER_ENHANCEMENTS.md` E12 (formal verification hooks), capability system already in `kernel/security/capability.fj`, 18 syscalls defined with clear pre/post conditions.

### Non-Goals (What We Intentionally Do NOT Compete On)

1. **Hardware driver ecosystem.** macOS has thousands of drivers. FajarOS targets one hardware configuration (Lenovo Legion Pro: i9-14900HX + RTX 4090 + NVMe + Intel AX211). We do not aim for generic hardware support.

2. **Application ecosystem.** macOS has 1M+ apps. FajarOS will have under 20 native applications. We do not build an App Store.

3. **Backward compatibility.** macOS carries 40 years of POSIX, Carbon, Cocoa, and Mach legacy. FajarOS starts fresh with no backward compatibility burden.

4. **Consumer UX polish.** macOS has 40 years of Aqua refinement. FajarOS aims for functional, professional UI -- not consumer beauty. Tiling window manager, not Aqua animations.

5. **Multi-platform support.** FajarOS targets x86_64 (QEMU + bare metal Lenovo Legion Pro) and ARM64 (Radxa Q6A, verification only). We do not support arbitrary hardware.

---

## PART 2: ARCHITECTURE ROADMAP (6 Major Phases)

### Phase Timeline Overview

```
V28 "Intelligence"   Apr 2026 - Jun 2026   8 weeks   ~320h (+80h surprise = 400h)
V29 "Foundation"     Jun 2026 - Aug 2026   8 weeks   ~320h (+80h surprise = 400h)
V30 "Desktop"        Aug 2026 - Oct 2026   8 weeks   ~320h (+80h surprise = 400h)
V31 "Ecosystem"      Oct 2026 - Dec 2026   8 weeks   ~320h (+80h surprise = 400h)
V32 "Hardware"       Dec 2026 - Feb 2027   8 weeks   ~320h (+80h surprise = 400h)
V33 "Verified"       Feb 2027 - Apr 2027   8 weeks   ~320h (+80h surprise = 400h)
                                            ──────    ──────────────────────────────
                                            48 weeks  1,920h base + 480h surprise = 2,400h total
```

### Architecture Evolution Diagram

```
V27 "Hardened" (NOW)                V28 "Intelligence"
┌─────────────────────┐             ┌───────────────────────────┐
│ Monolithic ELF      │             │ Monolithic ELF            │
│ VGA text mode       │   ────►     │ GPU framebuffer           │
│ SmolLM-135M test    │             │ Gemma 3 1B real           │
│ ~300 shell commands │             │ AI-powered shell (NL→cmd) │
└─────────────────────┘             └───────────────────────────┘
                                                │
V29 "Foundation"                                │
┌───────────────────────────┐                   │
│ Multi-binary ELFs         │   ◄───────────────┘
│ kernel.elf + vfs.elf ...  │
│ Type-safe IPC (@message)  │
│ User-mode runtime         │
│ SMT verification proofs   │
└───────────────────────────┘
            │
V30 "Desktop"                      V31 "Ecosystem"
┌───────────────────────────┐      ┌───────────────────────────┐
│ GPU compositor (Wayland)  │      │ Self-hosting compiler     │
│ Tiling + floating WM      │ ──►  │ Package manager + deps    │
│ Widget toolkit + @app     │      │ Text editor + REPL        │
│ AI in every text field    │      │ Debugger + profiler       │
└───────────────────────────┘      └───────────────────────────┘
                                               │
V32 "Hardware"                                 │
┌───────────────────────────┐                  │
│ Bare-metal Lenovo Legion  │   ◄──────────────┘
│ NVMe + USB + HDMI + WiFi  │
│ RTX 4090 compute          │
│ Intel HDA audio           │
└───────────────────────────┘
            │
V33 "Verified"
┌───────────────────────────┐
│ SMT-verified syscall layer│
│ Cap<T> type system        │
│ Secure boot chain         │
│ Per-service sandboxing    │
│ Side-channel mitigations  │
└───────────────────────────┘
```

---

## PHASE V28: "Intelligence" (8 weeks, 320h base + 80h surprise = 400h)

**Focus:** AI-Native Desktop + LLM Upgrade
**Gate:** Gemma 3 1B generates coherent text; GPU framebuffer compositor renders pixels; AI shell converts natural language to commands; AI scheduler classifies workloads.
**Codename:** V28 "Intelligence"

### V28.0: Pre-Flight Audit (8h)

Before any V28 work begins, hands-on verify the V27 baseline. Produces `docs/V28_B0_FINDINGS.md`.

| Task | Description | Verification Command | Est |
|------|-------------|---------------------|-----|
| V28.0.1 | Verify boot to `nova>` on QEMU KVM | `make run-kvm-llvm` and type `version` -- expect "v3.2.0 Hardened" | 0.5h |
| V28.0.2 | Verify existing AI pipeline | `make run-kvm-llvm`, type `model-info`, `tokenize hello`, `tensor` -- all produce output without crash | 1h |
| V28.0.3 | Audit transformer.fj GQA readiness | Read `kernel/compute/transformer.fj:51-59` (tfm_get_n_kv_heads, tfm_kv_dim) -- confirm GQA scaffolding exists | 0.5h |
| V28.0.4 | Audit memory map for 1GB extension | Read `docs/MEMORY_MAP.md`, verify addresses above 0x8000000 are documented, identify collision risks with extended identity map | 1h |
| V28.0.5 | Audit frame allocator limits | Read `kernel/mm/frames.fj`, confirm TOTAL_FRAMES=32768, BITMAP_SIZE, identify what changes for 262144 frames | 0.5h |
| V28.0.6 | Audit display service capabilities | Read `services/display/main.fj` and `services/gui/compositor.fj` -- measure current pixel rendering, confirm 1024x768 target | 1h |
| V28.0.7 | Run all 25 kernel tests | `make run-kvm-llvm`, type `test-all` -- confirm 25/25 pass | 1h |
| V28.0.8 | Multi-repo state check (Rule 8) | `git -C ~/Documents/fajaros-x86 status -sb && git -C ~/Documents/fajaros-x86 rev-list --count origin/main..main && git -C ~/Documents/Fajar\ Lang status -sb && git -C ~/Documents/Fajar\ Lang rev-list --count origin/main..main` | 0.5h |
| V28.0.9 | Document findings | Write `docs/V28_B0_FINDINGS.md` with results | 1h |
| V28.0.10 | GATE: All 9 checks pass | All findings committed, no blocking issues | 1h |

**Prevention layer:** V28.0 findings become the baseline for all subsequent V28 phases. Every V28 task cross-references V28.0 findings.

### V28.1: Gemma 3 1B Kernel Integration (10 sub-phases, 120h)

This follows the existing `docs/GEMMA3_UPGRADE_PLAN.md` phases A through H, with refinements.

#### V28.1.A: Bug Fixes from Audit (8h)

| Task | File:Line | Description | Verification | Est |
|------|-----------|-------------|--------------|-----|
| V28.1.A1 | kernel/compute/fajarquant.fj | Fix PCA rotation overflow: clamp `r * v` intermediate | `make run-kvm-llvm`, `infer hello` -- no overflow crash | 1.5h |
| V28.1.A2 | kernel/compute/kmatrix.fj | Fix LayerNorm variance precision: accumulate `diff*diff` first, divide by dim at end | `make run-kvm-llvm`, `tensor` -- variance test passes | 1.5h |
| V28.1.A3 | kernel/compute/pipeline.fj | Fix noise `(seed % 100) - 50` for negative seed: use `((seed % 100) + 100) % 100 - 50` | `make run-kvm-llvm`, `model-load test` + `infer hello` -- no crash with random seeds | 1h |
| V28.1.A4 | kernel/compute/model_loader.fj | Add header offset validation: `if embed_off > total_size { return -3 }` | `make run-kvm-llvm`, `model-load nvme 0` with corrupted header -- returns error, no crash | 1.5h |
| V28.1.A5 | kernel/compute/tokenizer.fj | Add output buffer bounds check: `if n_tokens >= max_tokens { break }` in tok_encode | `make run-kvm-llvm`, `tokenize <long string>` -- truncates cleanly, no buffer overrun | 1.5h |
| V28.1.A-GATE | -- | All existing commands still work, no crashes | `make test-commands` -- 0 crashes in 90-command batch | 1h |

#### V28.1.B: RMSNorm + Gated FFN + Frame-Allocated Vectors (18h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.B1 | kernel/compute/kmatrix.fj | Add `km_rmsnorm(data_addr, dim, gamma_addr, eps)` -- RMSNorm(x) = x / sqrt(mean(x^2) + eps) * gamma, no mean subtraction, no beta | `make run-kvm-llvm`, `km-test rmsnorm` -- known input matches PyTorch within 1% | 4h |
| V28.1.B2 | kernel/compute/kmatrix.fj | Add `km_gelu_tanh(data_addr, dim)` -- GELU_tanh(x) = 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3))) | `make run-kvm-llvm`, `km-test gelu` -- known input within 2% of reference | 3h |
| V28.1.B3 | kernel/compute/transformer.fj | Add frame-allocated vector API: `tfm_vec_alloc(dim)`, `tfm_vec_free(addr)`, `tfm_vec_get/set` -- all hidden state vectors (d=1152) use frame_alloc_contiguous, returns raw address, manages up to 16 active vectors | `make run-kvm-llvm`, `infer hello` with d=32 test model using new API | 4h |
| V28.1.B4 | kernel/compute/transformer.fj | Add gated FFN: `tfm_ffn_gated(x_addr, layer, d_model, ffn_dim)` -- `out = down_proj(gelu(gate_proj(x)) * up_proj(x))`, three weight matrices per layer, gate+up produce ffn_dim=6912, element-wise multiply before down_proj | `make run-kvm-llvm`, `infer hello` with v2 test model -- gated FFN path runs | 4h |
| V28.1.B5 | kernel/compute/transformer.fj | Update `tfm_layer` to use frame-alloc vectors + RMSNorm + gated FFN -- replace km_ slot usage with frame-allocated raw addresses for d>1024, use km_rmsnorm instead of km_layernorm, use tfm_ffn_gated instead of 2-matrix FFN | `make run-kvm-llvm`, `infer hello` with test model works through new code path -- tokens generated | 3h |

#### V28.1.C: Grouped Query Attention (12h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.C1 | kernel/compute/transformer.fj | Add GQA support to `tfm_attention` -- Q has 4 heads (4x256=1024 total), K/V have 1 head (1x256), broadcast KV across all query heads | `make run-kvm-llvm`, `infer hello` with GQA test model -- 4 heads attend to same KV | 4h |
| V28.1.C2 | kernel/compute/transformer.fj | Update QKV projection sizes -- Q: 1152->1024, K: 1152->256, V: 1152->256, O: 1024->1152, four separate weight matrices | `make run-kvm-llvm`, `model-info` shows separate Q/K/V/O sizes | 3h |
| V28.1.C3 | kernel/compute/transformer.fj | Update KV cache for GQA -- store only n_kv_heads * d_head = 256 dims per position per layer (not d_model=1152), reduces KV cache 4.5x | `make run-kvm-llvm`, `model-info` shows KV cache dim=256 | 3h |
| V28.1.C4 | kernel/compute/model_loader.fj | Update .fjm v2 format for GQA weights -- header adds `n_kv_heads`, per-layer separate Q/K/V/O sizes | `make run-kvm-llvm`, `model-info` after loading v2 format shows n_kv_heads=1 | 2h |

#### V28.1.D: Rotary Position Embedding (10h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.D1 | kernel/compute/transformer.fj | Implement `tfm_rope_apply(q_addr, k_addr, pos, head_dim, theta)` -- for each pair (x[2i], x[2i+1]): rotate by angle theta_i = pos / (theta^(2i/d)) | `make run-kvm-llvm`, `rope-test` -- token at pos=0 vs pos=10 produce different Q/K | 4h |
| V28.1.D2 | kernel/compute/transformer.fj | Pre-compute sin/cos lookup table -- fixed-point x10000 for positions 0..2048 and 128 frequency bins, ~130 KB frame-allocated, computed once at model-load | `make run-kvm-llvm`, `model-info` shows "RoPE table loaded: 130KB" | 3h |
| V28.1.D3 | kernel/compute/transformer.fj | Dual RoPE frequencies -- local layers: theta=10,000, global layers (5,11,17,23): theta=1,000,000. Select based on layer index | `make run-kvm-llvm`, `model-info` shows "22 local layers (theta=10K), 4 global (theta=1M)" | 1.5h |
| V28.1.D4 | kernel/compute/transformer.fj | Integrate RoPE into tfm_layer -- after Q/K projection, before attention score computation | `make run-kvm-llvm`, `infer hello` with RoPE-enabled test model -- different output at different positions | 1.5h |

#### V28.1.E: Hybrid Sliding Window + Global Attention (8h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.E1 | kernel/compute/transformer.fj | Add `tfm_is_global_layer(layer_idx)` -- every 6th layer is global. For 26 layers: globals at 5, 11, 17, 23 (4 global, 22 local) | `make run-kvm-llvm`, `model-info` shows "4 global attention layers" | 1h |
| V28.1.E2 | kernel/compute/transformer.fj | Modify attention score loop for sliding window -- local layers: attend to positions max(0, cur_pos - 512)..cur_pos only, global layers: attend to all positions 0..cur_pos | `make run-kvm-llvm`, `infer` with 20+ tokens -- local layer at pos=600 attends only to pos 88-600 | 4h |
| V28.1.E3 | kernel/compute/transformer.fj | Dual KV cache strategy -- local layers: ring buffer of 512 entries, global layers: full linear buffer | `make run-kvm-llvm`, `model-info` shows "KV cache: 22 local (512-ring) + 4 global (2048-linear)" | 3h |

#### V28.1.F: Large Vocabulary + Extended Memory Mapping (18h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.F1 | kernel/mm/paging.fj | Extend identity mapping to 1 GB -- add PDPT entries for 128 MB-1 GB, RW+NX (data, not code). Called during kernel_main init | `make run-kvm-llvm`, `meminfo` shows "Identity mapped: 1 GB" | 4h |
| V28.1.F2 | kernel/mm/frames.fj | Update frame allocator for 1 GB -- TOTAL_FRAMES: 32768->262144, BITMAP_SIZE: 4096->32768, relocate bitmap if needed | `make run-kvm-llvm`, `frames` shows "Total: 262144 frames (1 GB)" | 3h |
| V28.1.F3 | kernel/compute/model_loader.fj | Frame-allocate embedding table -- 75 MB loaded from NVMe into contiguous frames above 128 MB | `make run-nvme run-kvm-llvm`, `model-load nvme 0` -- "Embedding loaded: 75 MB at 0x8000000" | 3h |
| V28.1.F4 | kernel/compute/model_loader.fj | Frame-allocate LM head weights -- 75 MB at separate contiguous region | `make run-kvm-llvm`, `model-info` shows "LM head: 75 MB at 0xC000000" | 2h |
| V28.1.F5 | kernel/compute/transformer.fj | Implement `tfm_argmax_raw(addr, count)` -- argmax over 262K i64 values, hierarchical: max per 4096-element block, then max of 64 block winners | `make run-kvm-llvm`, `infer hello` with 262K vocab -- produces valid token ID in <50ms | 3h |
| V28.1.F6 | tools/export_tokenizer.py (host) | Export Gemma 3 tokenizer to .fjt -- 262K entries, written to disk.img at LBA 2000 | `python tools/export_tokenizer.py --model google/gemma-3-1b-it -o disk.img --lba 2000` -- file written | 2h |
| V28.1.F7 | kernel/compute/tokenizer.fj | NVMe-based tokenizer loading -- `tok_load_nvme(start_lba)` reads .fjt from NVMe into frame-allocated memory | `make run-kvm-llvm`, `tok-load nvme 2000` -- "Loaded 262K tokens (4 MB)" | 1h |

#### V28.1.G: Updated Export Scripts + .fjm v2 Format (10h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.G1 | kernel/compute/model_loader.fj | Define .fjm v2 header (96 bytes) -- add n_kv_heads, ffn_type, norm_type, rope_theta, gate_proj_size, up_proj_size, o_proj_size, bump version=2 | `make run-kvm-llvm`, `model-load test` with v2 format -- header parsed correctly | 2h |
| V28.1.G2 | tools/export_fjm.py (host) | Update export for Gemma 3 1B -- extract q/k/v/o separately, gate/up/down (3 FFN matrices), RMSNorm gamma only, Lloyd-Max quantization per matrix | `python tools/export_fjm.py --model google/gemma-3-1b-it --bits 2 -o gemma3.fjm` -- ~250 MB file | 3h |
| V28.1.G3 | tools/export_fjm.py (host) | Write Gemma 3 1B weights to NVMe disk image -- 250 MB on disk | `python tools/export_fjm.py ... --write-disk disk.img --lba 0` -- written | 1h |
| V28.1.G4 | kernel/compute/model_loader.fj | Parse v2 header, load Q/K/V/O as separate blocks, load 3 FFN matrices, RMSNorm gamma only, model_type=10 for Gemma 3 1B | `make run-kvm-llvm`, `model-load nvme 0` + `model-info` -- shows Gemma 3 1B architecture | 2h |
| V28.1.G5 | kernel/compute/model_loader.fj | Update test model to .fjm v2 -- d=32, 4 layers, 4Q:1KV, head_dim=8, ffn_dim=128 gated, RMSNorm, ~8 KB for RamFS | `make run-kvm-llvm`, `model-load test` + `model-info` -- shows "GQA 4:1, gated FFN, RMSNorm" | 2h |

#### V28.1.H: End-to-End Integration + Real Weights (18h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.1.H1 | tools/ (host) | Prepare NVMe disk image with Gemma 3 1B data -- .fjm (250 MB) + .fjt (4 MB) | Host: `ls -la disk.img` shows ~256 MB of model data | 2h |
| V28.1.H2 | kernel/compute/model_loader.fj | Load Gemma 3 1B from NVMe -- `nova> model-load nvme 0` loads 250 MB across extended memory | `make run-nvme run-kvm-llvm`, `model-load nvme 0` -- "Loaded Gemma 3 1B: 250 MB, 26 layers" | 3h |
| V28.1.H3 | kernel/compute/tokenizer.fj | Load Gemma 3 tokenizer from NVMe -- `nova> tok-load nvme 2000` | `make run-kvm-llvm`, `tok-load nvme 2000` -- "Loaded 262K tokens" | 1h |
| V28.1.H4 | kernel/compute/pipeline.fj | Run single-token inference -- `nova> infer "The capital of France is"` | Output contains "Paris" or a reasonable token | 3h |
| V28.1.H5 | kernel/compute/pipeline.fj | Run multi-token generation -- `nova> ask "What is 2+2?"` | Coherent multi-word response with streaming output | 3h |
| V28.1.H6 | kernel/compute/pipeline.fj | Performance measurement -- measure tokens/sec, profile embedding/matmul/attention/FFN | `make run-kvm-llvm`, `ask-bench` -- reports tokens/sec for each stage | 2h |
| V28.1.H7 | kernel/compute/pipeline.fj | Stress test: 128-token generation continuously | `make run-kvm-llvm`, `ask "Tell me about Indonesia"` -- 128 tokens with no KV overflow, no memory corruption | 2h |
| V28.1.H8 | docs/ | Quality validation -- 10 diverse prompts, document output quality | `docs/V28_GEMMA3_QUALITY.md` committed with 10 prompt/response pairs | 2h |

**V28.1 Success Gate:** `nova> ask "What is 2+2?"` produces a coherent, correct answer from Gemma 3 1B running entirely in Ring 0.

### V28.2: AI-Powered Shell (32h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.2.1 | shell/ai_shell.fj (NEW) | `nova> ai ls all files in /dev` -- LLM converts natural language to shell command, shows proposed command, waits for confirm | `make run-kvm-llvm`, `ai ls all files` -- proposes `ls /dev`, user presses Enter, command runs | 6h |
| V28.2.2 | shell/ai_shell.fj | Error explanation mode: when a command fails, `nova> explain` passes error to LLM for human-readable explanation | `make run-kvm-llvm`, `cat nonexistent` then `explain` -- LLM explains "file not found" | 4h |
| V28.2.3 | shell/ai_shell.fj | Command suggestion: `nova> suggest` shows 3 commands relevant to recent shell history | `make run-kvm-llvm`, run 5 net commands then `suggest` -- suggests network-related commands | 4h |
| V28.2.4 | shell/ai_shell.fj | Prompt engineering: system prompt that constrains LLM output to valid FajarOS commands (302 known commands + arguments) | `make run-kvm-llvm`, `ai show my ip address` -- proposes `ifconfig`, not arbitrary Linux commands | 4h |
| V28.2.5 | shell/ai_shell.fj | Safety layer: refuse to execute dangerous commands (`rm -rf /`, `dd if=/dev/zero`) even if LLM suggests them | `make run-kvm-llvm`, `ai delete everything` -- refuses with warning | 2h |
| V28.2.6 | shell/ai_shell.fj | Multi-turn conversation: `ai` enters interactive mode where user can refine requests | `make run-kvm-llvm`, `ai mode` -- enters AI chat loop, `exit` returns to shell | 4h |
| V28.2.7 | shell/commands.fj | Wire 6 new AI shell commands: `ai`, `explain`, `suggest`, `chat`, `ai-help`, `ai-config` | `make run-kvm-llvm`, `help ai` -- shows 6 AI commands | 4h |
| V28.2.8 | tests/kernel_tests.fj | Add 5 AI shell tests: NL parse, safety filter, command map, error explain, suggest relevance | `make run-kvm-llvm`, `test-all` -- 30/30 pass (25 existing + 5 new) | 4h |

### V28.3: GPU-Native Framebuffer Compositor (48h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.3.1 | drivers/virtio_gpu.fj | VirtIO-GPU resource creation: 2D scanout, `resource_create_2d`, `resource_attach_backing`, `set_scanout` | `make run-gpu-llvm`, `fb-info` -- shows "VirtIO-GPU: 1024x768, scanout active" | 6h |
| V28.3.2 | drivers/virtio_gpu.fj | Transfer + flush pipeline: `transfer_to_host_2d`, `resource_flush` -- double-buffered: render to back buffer, flush to front | `make run-gpu-llvm`, `fb-test` -- colored rectangles visible on QEMU GTK window | 6h |
| V28.3.3 | services/display/main.fj | Replace VGA text mode with GPU framebuffer as primary display -- boot banner rendered via pixel font, not VGA 0xB8000 | `make run-gpu-llvm` -- see FajarOS boot banner as pixel-rendered text on GPU framebuffer | 8h |
| V28.3.4 | services/gui/compositor.fj | GPU-backed compositor: `comp_render_gpu()` -- composite all windows into back buffer, then GPU flush | `make run-gpu-llvm`, `gui-test` -- multiple windows rendered via GPU pipeline | 6h |
| V28.3.5 | services/display/main.fj | Hardware cursor: VirtIO-GPU `cursor_pos_update`, `cursor_resource` -- replace software XOR cursor | `make run-gpu-llvm`, move mouse -- hardware cursor tracks without flicker | 4h |
| V28.3.6 | services/display/main.fj | Mode setting: detect available resolutions from VirtIO-GPU, allow `resolution 1920 1080` shell command | `make run-gpu-llvm`, `resolution 1920 1080` -- display changes resolution | 4h |
| V28.3.7 | services/display/font.fj | Anti-aliased font rendering: 4-level grayscale subpixel hint for 8x16 font, alpha-blended onto background | `make run-gpu-llvm` -- text visibly smoother than current binary font | 6h |
| V28.3.8 | services/gui/animation.fj | GPU-accelerated window animations: fade-in on open (8 frames), slide on close, opacity transitions | `make run-gpu-llvm`, `gui-test` -- window open shows fade-in animation | 4h |
| V28.3.9 | tests/kernel_tests.fj | Add 3 GPU display tests: resource creation, double-buffer flush, compositor render | `make run-kvm-llvm`, `test-all` -- 33/33 pass | 4h |

### V28.4: AI-Aware Process Scheduler (24h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.4.1 | kernel/sched/ml_scheduler.fj | Upgrade ML scheduler from d=8 attention to Gemma 3-powered classification: LLM classifies process as CPU-bound/IO-bound/memory-bound | `make run-kvm-llvm`, `ml-sched status` -- shows "Mode: Gemma 3 classification" | 6h |
| V28.4.2 | kernel/sched/ml_scheduler.fj | Feature extraction: per-process counters (syscall rate, IO wait cycles, page faults, IPC frequency) fed as text prompt to Gemma 3 | `make run-kvm-llvm`, `ml-sched features` -- shows feature vector for each process | 4h |
| V28.4.3 | kernel/sched/ml_scheduler.fj | Adaptive time quantum: CPU-bound processes get longer quanta, IO-bound get shorter quanta with higher priority upon wake | `make run-kvm-llvm`, run `bench` (CPU-bound) + `ping` (IO-bound) simultaneously, `ml-sched stats` -- ping gets higher priority | 4h |
| V28.4.4 | kernel/sched/ml_scheduler.fj | Tensor workload detection: when a process does many `km_vecmat` calls, scheduler pins it to a performance core (P-core) and avoids preempting mid-matmul | `make run-kvm-llvm`, `infer hello` during benchmark -- inference latency stable, not interrupted | 4h |
| V28.4.5 | kernel/sched/ml_scheduler.fj | Fallback: if LLM inference takes >1ms, fall back to round-robin for that scheduling tick. ML scheduling is opportunistic, not blocking | `make run-kvm-llvm`, `ml-sched stats` -- shows "ML ticks: N, fallback ticks: M, avg ML latency: Xus" | 3h |
| V28.4.6 | tests/kernel_tests.fj | Add 3 ML scheduler tests: classification accuracy, fallback trigger, tensor workload detection | `make run-kvm-llvm`, `test-all` -- 36/36 pass | 3h |

### V28.5: Prevention Layers + CI Gates (16h)

| Task | File | Description | Verification | Est |
|------|------|-------------|--------------|-----|
| V28.5.1 | .github/workflows/v28_gemma3_test.yml | CI: automated Gemma 3 smoke test -- boot QEMU, load test model, run `infer hello`, verify output | `gh run list --workflow v28_gemma3_test.yml` -- shows green | 3h |
| V28.5.2 | .github/workflows/v28_gpu_test.yml | CI: GPU compositor test -- boot QEMU with VirtIO-GPU, run `fb-test`, check for crash | `gh run list --workflow v28_gpu_test.yml` -- shows green | 3h |
| V28.5.3 | scripts/check_memory_map.sh | Prevention: memory map collision detector -- parses all `const *_BASE: i64 = 0x` declarations, flags overlaps | `bash scripts/check_memory_map.sh` -- "0 collisions" | 2h |
| V28.5.4 | docs/V28_MEMORY_MAP.md | Updated memory map with all V28 allocations (extended 1GB identity map, Gemma 3 weights, KV cache, framebuffers) | `diff docs/V28_MEMORY_MAP.md docs/MEMORY_MAP.md` -- shows all new allocations | 2h |
| V28.5.5 | tests/kernel_tests.fj | Regression test suite: all 36 tests from V28.4 pass on every commit | `make test-serial` -- all pass | 2h |
| V28.5.6 | docs/V28_RELEASE_NOTES.md | Release documentation: what changed, what broke, migration notes | Document committed | 2h |
| V28.5.7 | CHANGELOG.md | V28 changelog entry | Updated | 1h |
| V28.5.8 | GATE: V28 complete | Tag `v4.0.0` if all gates pass | `git tag v4.0.0 && git push --tags` | 1h |

### V28 Effort Summary

| Sub-phase | Base Est | Surprise +25% | Total Budget |
|-----------|----------|---------------|-------------|
| V28.0 Pre-Flight | 8h | 2h | 10h |
| V28.1 Gemma 3 1B (A-H) | 122h | 30h | 152h |
| V28.2 AI Shell | 32h | 8h | 40h |
| V28.3 GPU Compositor | 48h | 12h | 60h |
| V28.4 AI Scheduler | 24h | 6h | 30h |
| V28.5 CI/Prevention | 16h | 4h | 20h |
| **V28 TOTAL** | **250h** | **62h** | **312h** |

### V28 Success Criteria

1. `nova> ask "What is 2+2?"` -- Gemma 3 1B produces coherent English answer in kernel Ring 0
2. `nova> ai show my ip` -- natural language translated to `ifconfig`, confirmed, executed
3. `make run-gpu-llvm` -- GPU framebuffer renders boot banner, windows, and text at 1024x768
4. `nova> ml-sched status` -- AI scheduler classifies processes and adjusts time quanta
5. 36/36 kernel tests pass
6. 0 memory map collisions
7. CI green on all V28 workflows

---

## PHASE V29: "Foundation" (8 weeks, 320h base + 80h surprise = 400h)

**Focus:** Compiler Multi-Binary + Real Microkernel Separation
**Gate:** Services compile as separate ELFs, type-safe IPC messages, user-mode runtime works, SMT verification of syscall boundary.

### V29.0: Pre-Flight Audit (8h)
Verify V28 baseline. `docs/V29_B0_FINDINGS.md`.

### V29.1: Multi-Binary Build System (60h)

| Task | Description | Est |
|------|-------------|-----|
| V29.1.1 | Compiler: directory build mode -- `fj build dir/` compiles all .fj in directory as one unit | 8h |
| V29.1.2 | Service manifest in fj.toml -- `[[service]] name="vfs" entry="services/vfs/main.fj"` | 4h |
| V29.1.3 | `fj build --all-services` -- builds each service as x86_64-user ELF | 8h |
| V29.1.4 | User-mode linker script -- `.text` at 0x2000000 (user space), separate stacks | 6h |
| V29.1.5 | Initramfs packing: `fj pack` creates tar of all service ELFs embedded in kernel | 8h |
| V29.1.6 | Kernel unpacks initramfs at boot and spawns services from embedded ELFs | 8h |
| V29.1.7 | Verify: `make microkernel` builds kernel.elf (22KB) + vfs.elf + shell.elf + net.elf + blk.elf + display.elf | 6h |
| V29.1.8 | Makefile: `make services` target builds all service ELFs independently | 4h |
| V29.1.9 | Tests: 3 multi-binary build tests in CI | 4h |
| V29.1.10 | Prevention: CI job rejects PR if any service fails to build as separate ELF | 4h |

### V29.2: Type-Safe IPC (@message structs) (48h)

| Task | Description | Est |
|------|-------------|-----|
| V29.2.1 | Compiler: `@message` struct annotation in parser -- `@message struct VfsOpen { path: str, flags: i64 }` | 8h |
| V29.2.2 | Auto-generate serialize/deserialize -- struct -> 64-byte buffer pack/unpack, compile-time layout | 8h |
| V29.2.3 | Type-check ipc_send argument -- `ipc_send(dst, VfsOpen { ... })` checks struct type at compile time | 6h |
| V29.2.4 | Type-check ipc_recv result -- `let msg: VfsOpen = ipc_recv(src)` checks type match | 6h |
| V29.2.5 | Message ID auto-assignment -- each @message struct gets unique type ID based on struct hash | 4h |
| V29.2.6 | Cross-service type sharing -- `@shared mod ipc_types { ... }` compiled once, used by all services | 8h |
| V29.2.7 | Port existing IPC protocols to @message structs -- VFS, BLK, NET, display protocols | 4h |
| V29.2.8 | Tests: wrong message type -> compile error (6 negative tests) | 4h |

### V29.3: User-Mode Runtime (40h)

| Task | Description | Est |
|------|-------------|-----|
| V29.3.1 | Compiler: `libfj_user.a` with syscall wrappers -- `fj_user_println(s)` -> SYS_WRITE via SYSCALL instruction | 8h |
| V29.3.2 | `fj_user_exit(code)` -> SYS_EXIT, `fj_user_ipc_send/recv/call` -> SYS_SEND/RECV/CALL | 6h |
| V29.3.3 | Auto-link user runtime when `--target x86_64-user` | 4h |
| V29.3.4 | `@safe fn main() { println("hello") }` compiles to user ELF that uses SYSCALL for output | 6h |
| V29.3.5 | User-mode heap: `sbrk` syscall wrapper, bump allocator in user space | 6h |
| V29.3.6 | User-mode page fault handler: kernel delivers SIGSEGV to user process | 4h |
| V29.3.7 | Tests: 5 user-mode programs compile and run as separate ELFs on kernel | 6h |

### V29.4: Separate Service ELFs (40h)

| Task | Description | Est |
|------|-------------|-----|
| V29.4.1 | VFS as separate ELF -- receives IPC from shell, calls BLK service for disk access | 8h |
| V29.4.2 | NET as separate ELF -- owns socket table, delegates to kernel for NIC DMA | 8h |
| V29.4.3 | Display as separate ELF -- owns framebuffer, receives draw commands via IPC | 6h |
| V29.4.4 | Shell as separate ELF -- uses SYS_WRITE for output, SYS_READ for input, IPC for services | 6h |
| V29.4.5 | Init service: spawns all services in order, monitors health, auto-restarts on crash | 6h |
| V29.4.6 | Boot sequence: kernel -> init -> vfs -> blk -> net -> display -> shell (verified order) | 4h |
| V29.4.7 | Tests: kill VFS service -> init restarts it, other services resume | 2h |

### V29.5: Formal Verification of Syscall Boundary (48h)

| Task | Description | Est |
|------|-------------|-----|
| V29.5.1 | SMT model of syscall dispatch -- encode 18 syscalls as Z3 assertions | 10h |
| V29.5.2 | Property: no @safe code can execute @kernel operations without going through syscall | 8h |
| V29.5.3 | Property: capability checks are complete -- every privileged syscall requires capability | 8h |
| V29.5.4 | Property: memory isolation -- user process cannot read/write kernel memory | 8h |
| V29.5.5 | Generate verification report -- machine-checkable proof artifact | 6h |
| V29.5.6 | CI: re-verify on every syscall change | 4h |
| V29.5.7 | Documentation: `docs/FORMAL_VERIFICATION.md` with proof methodology and results | 4h |

### V29 Success Criteria
1. `make microkernel` produces kernel.elf (under 30KB) + 5 service ELFs
2. `@message struct VfsOpen { path: str }` compiles, wrong types rejected at compile time
3. `@safe fn main() { println("hello") }` compiles to user ELF, runs on kernel via SYSCALL
4. All services run as separate ELFs, communicate via IPC
5. Z3 proves: no privilege escalation through syscall interface

---

## PHASE V30: "Desktop" (8 weeks, 320h base + 80h surprise = 400h)

**Focus:** Full Desktop Environment
**Gate:** Desktop with 3+ windows, tiling WM, widget toolkit, AI-integrated text fields.

### V30.0: Pre-Flight Audit (8h)

### V30.1: GPU Compositor (Wayland-Style) (64h)

| Task | Description | Est |
|------|-------------|-----|
| V30.1.1 | Wayland-style protocol: surface create/destroy, buffer attach, damage, commit | 12h |
| V30.1.2 | Per-surface framebuffers -- each window owns a memory region, compositor reads via shared memory | 10h |
| V30.1.3 | Damage tracking -- only re-composite dirty rectangles, not full screen | 8h |
| V30.1.4 | VSync -- synchronize compositor output with display refresh (VirtIO-GPU flush timing) | 6h |
| V30.1.5 | Multi-output support -- VirtIO-GPU scanout 0 + scanout 1 for dual-display | 8h |
| V30.1.6 | Alpha compositing -- Porter-Duff over operator for translucent windows | 6h |
| V30.1.7 | GPU-accelerated blitting -- VirtIO-GPU 2D blit for fast window copy | 6h |
| V30.1.8 | Wallpaper rendering -- BMP decoder, full-screen background image | 4h |
| V30.1.9 | Tests: compositor benchmarks -- FPS, damage tracking accuracy, memory usage | 4h |

### V30.2: Window Management (48h)

| Task | Description | Est |
|------|-------------|-----|
| V30.2.1 | Tiling WM core: binary split layout (BSP tree), auto-arrange on window create/destroy | 10h |
| V30.2.2 | Floating mode: drag window title bar to move, drag edges to resize | 8h |
| V30.2.3 | Toggle tiling/floating per window -- keyboard shortcut (Super+T) | 4h |
| V30.2.4 | Virtual desktops (workspaces): 4 workspaces, Super+1-4 to switch | 6h |
| V30.2.5 | Window decorations: title bar, close/minimize/maximize buttons, window border | 8h |
| V30.2.6 | Keyboard shortcuts: Super+Enter=terminal, Super+Q=close, Super+Arrow=tile position | 4h |
| V30.2.7 | Alt-Tab window switcher: preview thumbnails, cycle through windows | 4h |
| V30.2.8 | Full-screen mode: F11 or Super+F, removes decorations and fills screen | 4h |

### V30.3: Widget Toolkit (64h)

| Task | Description | Est |
|------|-------------|-----|
| V30.3.1 | Widget base: `Widget` struct with position, size, children, event handler, render method | 8h |
| V30.3.2 | Button: click handler, hover state, focused state, keyboard activation (Enter) | 6h |
| V30.3.3 | Label: single-line text, alignment (left/center/right), color, font size | 4h |
| V30.3.4 | TextBox: single-line text input, cursor, selection, copy/paste via clipboard | 8h |
| V30.3.5 | TextArea: multi-line text input with scroll, line numbers | 8h |
| V30.3.6 | ListView: scrollable list of items, single/multi selection, keyboard navigation | 6h |
| V30.3.7 | ScrollView: vertical/horizontal scrollbar, content clipping, scroll wheel | 6h |
| V30.3.8 | Menu: popup menu, submenu support, keyboard navigation, accelerator keys | 6h |
| V30.3.9 | Dialog: modal dialog (OK/Cancel), message box, file picker (VFS-based) | 6h |
| V30.3.10 | Layout engine: vertical/horizontal box layout, padding, margins, flex grow | 6h |

### V30.4: Application Framework (@app annotation) (32h)

| Task | Description | Est |
|------|-------------|-----|
| V30.4.1 | Compiler: `@app` annotation -- `@app fn main() { ... }` auto-generates window creation + event loop | 8h |
| V30.4.2 | Application IPC: `App.send(widget_id, event)` for cross-widget communication | 6h |
| V30.4.3 | Menu bar integration: `@app` programs declare menu items, system renders global menu bar | 6h |
| V30.4.4 | 3 demo apps: Calculator, File Manager, System Monitor -- all using @app + widget toolkit | 8h |
| V30.4.5 | Tests: application lifecycle (create, focus, minimize, close, crash recovery) | 4h |

### V30.5: AI-Integrated UI (40h)

| Task | Description | Est |
|------|-------------|-----|
| V30.5.1 | AI text field: every TextBox has an "AI assist" button -- LLM autocompletes based on context | 10h |
| V30.5.2 | Command palette: Super+P opens AI-powered command search (like VS Code) | 8h |
| V30.5.3 | AI-powered file search: type natural language query, LLM translates to VFS search | 6h |
| V30.5.4 | Accessibility: AI reads screen content aloud (text-to-description via LLM) | 8h |
| V30.5.5 | Smart notifications: AI summarizes and prioritizes system notifications | 4h |
| V30.5.6 | Tests: AI UI integration (5 tests) | 4h |

### V30 Success Criteria
1. Desktop with 3+ windows visible simultaneously, tiling layout works
2. Widget toolkit renders buttons, text boxes, lists with keyboard navigation
3. `@app fn main()` compiles to windowed application with event loop
4. AI text field auto-completes text using Gemma 3 1B
5. 60+ FPS compositor refresh rate on VirtIO-GPU

---

## PHASE V31: "Ecosystem" (8 weeks, 320h base + 80h surprise = 400h)

**Focus:** Self-Hosting + Developer Tools
**Gate:** `fj build hello.fj` runs ON FajarOS, text editor edits and compiles code.

### V31.0: Pre-Flight Audit (8h)

### V31.1: Self-Hosting Compiler (80h)

| Task | Description | Est |
|------|-------------|-----|
| V31.1.1 | Port Fajar Lang lexer to run on FajarOS -- tokenize .fj source files using VFS file I/O | 12h |
| V31.1.2 | Port parser -- AST construction using kernel/user heap allocation | 12h |
| V31.1.3 | Port analyzer -- type checking, context enforcement (@kernel/@device/@safe) | 12h |
| V31.1.4 | Port Cranelift codegen -- emit x86_64 machine code in user space | 16h |
| V31.1.5 | ELF writer -- generate valid ELF64 binary from compiled code | 8h |
| V31.1.6 | `fj build hello.fj -o hello.elf` running ON FajarOS -- compile .fj to native ELF | 10h |
| V31.1.7 | Bootstrap test: compile and run `@safe fn main() { println("hello") }` on FajarOS | 6h |
| V31.1.8 | Tests: 10 compilation tests running on FajarOS (arithmetic, functions, if/else, loops, structs) | 4h |

### V31.2: Package Manager with Dependency Resolution (48h)

| Task | Description | Est |
|------|-------------|-----|
| V31.2.1 | Package format: `.fjp` archive (tar + metadata.toml) | 6h |
| V31.2.2 | Package registry: local directory-based registry at `/pkg/` | 6h |
| V31.2.3 | Dependency resolution: topological sort with version constraints (semver) | 10h |
| V31.2.4 | `pkg install <name>` -- download from registry, resolve deps, install | 8h |
| V31.2.5 | `pkg build` -- compile current directory into .fjp package | 6h |
| V31.2.6 | `pkg search <query>` -- search registry by name/description | 4h |
| V31.2.7 | Standard library packages: fj-core, fj-math, fj-net, fj-gui, fj-ai | 4h |
| V31.2.8 | Tests: dependency resolution with diamond deps, version conflicts | 4h |

### V31.3: Text Editor with Syntax Highlighting (48h)

| Task | Description | Est |
|------|-------------|-----|
| V31.3.1 | GUI text editor app using widget toolkit TextArea | 8h |
| V31.3.2 | Syntax highlighting engine: regex-based tokenizer for .fj files (keywords, strings, comments, numbers, annotations) | 10h |
| V31.3.3 | Line numbers, current line highlight, cursor blink | 6h |
| V31.3.4 | File open/save via VFS IPC | 6h |
| V31.3.5 | Search and replace (Ctrl+F, Ctrl+H) | 6h |
| V31.3.6 | Multiple file tabs | 6h |
| V31.3.7 | AI-powered code completion: LLM suggests next line based on context | 4h |
| V31.3.8 | Tests: open, edit, save, syntax highlight accuracy | 2h |

### V31.4: REPL Inside FajarOS (24h)

| Task | Description | Est |
|------|-------------|-----|
| V31.4.1 | Interactive REPL: read line -> parse -> evaluate -> print, using on-FajarOS compiler | 8h |
| V31.4.2 | Variable persistence across lines (REPL state) | 4h |
| V31.4.3 | Expression evaluation with immediate feedback | 4h |
| V31.4.4 | History (up/down arrows), tab completion for variables/functions | 4h |
| V31.4.5 | Tests: arithmetic, variable binding, function definition in REPL | 4h |

### V31.5: Developer Tools (48h)

| Task | Description | Est |
|------|-------------|-----|
| V31.5.1 | Debugger: breakpoint on function entry, step-over, step-into, inspect variables | 16h |
| V31.5.2 | Profiler: per-function call count and time, hotspot detection | 10h |
| V31.5.3 | Memory profiler: track allocations, detect leaks, show heap fragmentation | 10h |
| V31.5.4 | `fj check` running on FajarOS -- type-check without compiling | 6h |
| V31.5.5 | Tests: debugger breakpoint + step, profiler output format | 6h |

### V31 Success Criteria
1. `nova> fj build hello.fj -o hello.elf && ./hello.elf` -- compile and run ON FajarOS
2. `nova> pkg install fj-math` -- installs package with dependency resolution
3. GUI text editor opens .fj file with syntax highlighting, saves via VFS
4. REPL evaluates `let x = 42; x * 2` and prints `84`
5. Debugger sets breakpoint, shows variable state at break

---

## PHASE V32: "Hardware" (8 weeks, 320h base + 80h surprise = 400h)

**Focus:** Real Hardware Deployment on Lenovo Legion Pro
**Gate:** FajarOS boots on bare metal, HDMI output visible, NVMe/USB/WiFi work.

### V32.0: Pre-Flight Audit (8h)
Audit ACPI tables, PCIe topology, and USB device enumeration on real hardware.

### V32.1: Intel i9-14900HX Bare-Metal Boot (60h)

| Task | Description | Est |
|------|-------------|-----|
| V32.1.1 | UEFI boot: replace Multiboot2 with UEFI direct boot -- EFI stub, memory map from UEFI | 16h |
| V32.1.2 | ACPI parsing: RSDP -> XSDT -> MADT (APIC info), MCFG (PCIe config), FADT (power management) | 12h |
| V32.1.3 | SMP on real i9: 8 P-cores + 16 E-cores (24 total), INIT-SIPI-SIPI for each AP | 10h |
| V32.1.4 | Hybrid core scheduler: detect P-core vs E-core via CPUID, assign tensor workloads to P-cores | 8h |
| V32.1.5 | Boot diagnostics: POST-style checks on serial, EFI framebuffer fallback if GPU fails | 6h |
| V32.1.6 | Interrupt routing: IOAPIC + MSI-X for NVMe + USB + Network | 8h |

### V32.2: NVMe on Real Hardware (32h)

| Task | Description | Est |
|------|-------------|-----|
| V32.2.1 | PCIe NVMe BAR detection via MCFG (not legacy PCI config space) | 8h |
| V32.2.2 | NVMe admin queue on real hardware -- identify controller, namespace | 8h |
| V32.2.3 | IO queue creation -- completion/submission queue pairs, MSI-X interrupt | 8h |
| V32.2.4 | Read/write sectors on real 937GB NVMe SSD | 4h |
| V32.2.5 | FAT32 mount on real NVMe partition | 4h |

### V32.3: USB Keyboard/Mouse (XHCI) (40h)

| Task | Description | Est |
|------|-------------|-----|
| V32.3.1 | XHCI on real hardware: BAR mapping, register access, capability parsing | 10h |
| V32.3.2 | Device enumeration: port status, slot enable, address device | 8h |
| V32.3.3 | USB HID keyboard: interrupt transfers, HID report descriptor parsing | 10h |
| V32.3.4 | USB HID mouse: interrupt transfers, relative/absolute coordinate conversion | 8h |
| V32.3.5 | Hotplug detection: port status change events | 4h |

### V32.4: HDMI/DisplayPort Output (48h)

| Task | Description | Est |
|------|-------------|-----|
| V32.4.1 | Intel UHD Graphics detection via PCI + MMIO BAR | 8h |
| V32.4.2 | Display pipe setup: plane -> pipe -> encoder -> connector chain | 12h |
| V32.4.3 | Mode setting: EDID parsing from connected monitor, choose optimal resolution | 10h |
| V32.4.4 | Framebuffer: allocate GTT memory, configure display surface, flip | 10h |
| V32.4.5 | Cursor plane: hardware cursor via Intel iGPU | 4h |
| V32.4.6 | HDMI audio (optional): Intel HDA + HDMI audio output | 4h |

### V32.5: WiFi Driver (Intel AX211) (48h)

| Task | Description | Est |
|------|-------------|-----|
| V32.5.1 | Intel AX211 PCIe detection and firmware loading | 10h |
| V32.5.2 | WiFi management frames: probe, auth, association | 10h |
| V32.5.3 | WPA3-SAE authentication | 12h |
| V32.5.4 | Data frames: TX/RX via DMA ring buffers | 8h |
| V32.5.5 | `wifi scan`, `wifi connect SSID` shell commands | 4h |
| V32.5.6 | TCP/IP over WiFi: `ping 8.8.8.8`, `wget http://example.com` via WiFi | 4h |

### V32.6: Audio Driver (Intel HDA) (24h)

| Task | Description | Est |
|------|-------------|-----|
| V32.6.1 | Intel HDA controller detection and codec enumeration | 6h |
| V32.6.2 | Output widget path: DAC -> mixer -> pin (headphone/speaker) | 8h |
| V32.6.3 | PCM playback: 16-bit 44.1KHz stereo via DMA ring buffer | 6h |
| V32.6.4 | `play <file>` shell command: WAV file playback from VFS | 4h |

### V32.7: RTX 4090 Compute (48h)

| Task | Description | Est |
|------|-------------|-----|
| V32.7.1 | NVIDIA RTX 4090 PCIe BAR detection and MMIO mapping | 8h |
| V32.7.2 | GPU memory allocation: device memory management for tensor buffers | 10h |
| V32.7.3 | Compute shader dispatch: minimal CUDA-like kernel launch via MMIO command buffer | 12h |
| V32.7.4 | Matrix multiply on GPU: offload km_vecmat to RTX 4090 for Gemma 3 inference | 10h |
| V32.7.5 | Benchmark: GPU vs CPU tokens/sec for Gemma 3 1B inference | 4h |
| V32.7.6 | Fallback: if GPU not available, seamlessly fall back to CPU inference | 4h |

### V32 Success Criteria
1. FajarOS boots on real Lenovo Legion Pro -- `nova>` prompt on HDMI-connected monitor
2. NVMe SSD accessible, FAT32 partition mounted
3. USB keyboard types commands, USB mouse controls cursor
4. WiFi connects to WPA3 network, `ping 8.8.8.8` works
5. Audio plays WAV file through speakers
6. RTX 4090 accelerates Gemma 3 inference (measurable speedup over CPU)

---

## PHASE V33: "Verified" (8 weeks, 320h base + 80h surprise = 400h)

**Focus:** Formal Verification + Production Security
**Gate:** SMT-verified syscall boundary, capability type system, secure boot chain.

### V33.0: Pre-Flight Audit (8h)

### V33.1: SMT Verification of Syscall Boundary (80h)

| Task | Description | Est |
|------|-------------|-----|
| V33.1.1 | Formalize syscall dispatch in Z3: model each of 18 syscalls as state transitions | 16h |
| V33.1.2 | Property: capability completeness -- every privileged operation requires a capability | 12h |
| V33.1.3 | Property: memory isolation -- user pages never overlap kernel pages | 12h |
| V33.1.4 | Property: no privilege escalation -- @safe -> @kernel transition only via SYSCALL instruction | 12h |
| V33.1.5 | Property: IPC safety -- typed messages cannot be forged by sender | 8h |
| V33.1.6 | Property: resource limits -- no process can exhaust kernel memory | 8h |
| V33.1.7 | Proof artifact: machine-checkable Z3 script, runs in CI | 8h |
| V33.1.8 | Documentation: `docs/VERIFICATION_REPORT.md` | 4h |

### V33.2: Capability Type System (Cap<T>) (64h)

| Task | Description | Est |
|------|-------------|-----|
| V33.2.1 | Compiler: `Cap<T>` phantom type -- `Cap<PortIO>`, `Cap<IRQ>`, `Cap<DMA>`, `Cap<Memory>` | 12h |
| V33.2.2 | Function requires capability: `fn driver(cap: Cap<PortIO>) { port_outb(...) }` | 10h |
| V33.2.3 | Kernel grants capabilities at process creation: `let cap = kernel_grant::<PortIO>()` | 8h |
| V33.2.4 | Capability delegation: process A shares `Cap<PortIO>` with process B via IPC | 8h |
| V33.2.5 | Capability revocation: kernel revokes cap, all holders lose access | 8h |
| V33.2.6 | No cap -> compile error: call port_outb without Cap<PortIO> -> compile-time rejection | 8h |
| V33.2.7 | Port all drivers to use Cap<T> instead of raw builtins | 6h |
| V33.2.8 | Tests: 10 capability enforcement tests (6 positive, 4 negative) | 4h |

### V33.3: Secure Boot Chain (48h)

| Task | Description | Est |
|------|-------------|-----|
| V33.3.1 | UEFI Secure Boot integration: sign kernel ELF with custom key | 10h |
| V33.3.2 | Kernel image hash verification: SHA-256 of kernel checked against stored hash | 8h |
| V33.3.3 | Service image verification: each service ELF signed, kernel verifies before spawn | 8h |
| V33.3.4 | Measured boot: extend TPM PCR with each loaded component hash | 10h |
| V33.3.5 | Anti-rollback: monotonic counter prevents loading older, vulnerable kernel versions | 6h |
| V33.3.6 | Documentation: secure boot chain specification | 6h |

### V33.4: Per-Service Sandboxing (64h)

| Task | Description | Est |
|------|-------------|-----|
| V33.4.1 | Seccomp-like syscall filtering: per-service allowlist of permitted syscalls | 10h |
| V33.4.2 | Memory sandbox: each service has isolated address space, no access to other services | 10h |
| V33.4.3 | IPC sandbox: services can only send messages to declared endpoints | 8h |
| V33.4.4 | Resource limits: CPU time, memory, IPC message rate per service | 8h |
| V33.4.5 | Fault isolation: service crash does not affect kernel or other services (proven via SMT) | 10h |
| V33.4.6 | Audit logging: all cross-service IPC and syscalls logged for forensic analysis | 8h |
| V33.4.7 | Penetration test suite: 20 attack scenarios (privilege escalation, memory corruption, IPC spoofing) | 6h |
| V33.4.8 | Tests: crash VFS service -> other services continue, restart VFS -> full recovery | 4h |

### V33.5: Side-Channel Mitigations (32h)

| Task | Description | Est |
|------|-------------|-----|
| V33.5.1 | Spectre v1 mitigation: lfence after bounds checks in syscall path | 6h |
| V33.5.2 | Spectre v2 mitigation: retpoline for indirect calls, IBRS/IBPB on context switch | 8h |
| V33.5.3 | Meltdown mitigation: KPTI (kernel page table isolation) -- separate page tables for user/kernel | 8h |
| V33.5.4 | L1TF mitigation: flush L1 cache on VM exit and context switch | 4h |
| V33.5.5 | MDS mitigation: VERW on kernel exit to clear microarchitectural buffers | 2h |
| V33.5.6 | Tests: timing-based Spectre PoC fails to extract kernel data | 4h |

### V33 Success Criteria
1. Z3 proves: no privilege escalation path through syscall interface (machine-checkable proof)
2. `Cap<PortIO>` enforced at compile time -- missing capability is a compile error
3. Secure boot chain: unsigned kernel refuses to boot
4. Service crash does not propagate -- kill VFS, NET continues, restart VFS works
5. Spectre PoC unable to extract kernel memory from user process

---

## PART 3: V28 DETAILED TASK TABLE (First Phase)

### V28 Pre-Flight Checklist

| Check | Command | Expected | Actual |
|-------|---------|----------|--------|
| Boot to nova> | `make run-kvm-llvm` | Prompt within 3 seconds | TBD in V28.0 |
| Version | Type `version` | "v3.2.0 Hardened" | TBD |
| AI pipeline | Type `model-info` | Model parameters displayed | TBD |
| Test suite | Type `test-all` | 25/25 pass | TBD |
| LOC count | `make loc \| tail -1` | ~106K total | TBD |
| File count | `find . -name "*.fj" \| wc -l` | ~183 files | TBD |
| No unpushed commits | `git rev-list --count origin/main..main` | 0 | TBD |
| Compiler tests | `cd ~/Documents/Fajar\ Lang && cargo test --lib 2>&1 \| tail -1` | "test result: ok" | TBD |

### V28 File-Level Impact Map

| Sub-phase | Files Modified | Files Created | LOC Change |
|-----------|---------------|---------------|------------|
| V28.1.A Bug fixes | 5 existing compute/*.fj | 0 | +30 |
| V28.1.B RMSNorm/FFN | kmatrix.fj, transformer.fj | 0 | +400 |
| V28.1.C GQA | transformer.fj, model_loader.fj | 0 | +300 |
| V28.1.D RoPE | transformer.fj | 0 | +250 |
| V28.1.E Sliding window | transformer.fj | 0 | +200 |
| V28.1.F Extended mem | paging.fj, frames.fj, model_loader.fj, tokenizer.fj | export_tokenizer.py | +500 |
| V28.1.G .fjm v2 | model_loader.fj | export_fjm.py (updated) | +200 |
| V28.1.H E2E | pipeline.fj | V28_GEMMA3_QUALITY.md | +100 |
| V28.2 AI shell | commands.fj | shell/ai_shell.fj | +600 |
| V28.3 GPU compositor | virtio_gpu.fj, display/main.fj, gui/compositor.fj, display/font.fj, gui/animation.fj | 0 | +800 |
| V28.4 AI scheduler | ml_scheduler.fj | 0 | +300 |
| V28.5 CI/prevention | 0 | 3 CI workflows, 2 docs | +200 |
| **TOTAL** | ~15 modified | ~5 created | **+3,880 LOC** |

### V28 Estimated Final State

| Metric | V27 (Now) | V28 (Target) | Delta |
|--------|-----------|-------------|-------|
| Total LOC | 106,722 | ~110,600 | +3,878 |
| .fj files | 183 | ~188 | +5 |
| Shell commands | 302 | ~314 | +12 |
| Kernel tests | 25 | 36 | +11 |
| AI model | SmolLM-135M (test, d=16) | Gemma 3 1B (real, d=1152) | 7.5x params |
| Display | VGA text + basic framebuffer | GPU framebuffer + compositor | Major upgrade |
| Scheduler | Attention d=8 | Gemma 3 classification | LLM-powered |

---

## PART 4: DEPENDENCIES AND CRITICAL PATH

### Dependency Graph

```
V28.0 Pre-flight ──┐
                    ├──► V28.1.A Bug fixes
                    │         │
                    │         ▼
                    │    V28.1.B RMSNorm+FFN ──────────────────┐
                    │         │                                 │
                    │    V28.1.C GQA ────┐                     │
                    │         │          │                      │
                    │    V28.1.D RoPE ───┤                     │
                    │         │          ├──► V28.1.G Export ──┤
                    │    V28.1.E Sliding ─┘        │           │
                    │         │                    ▼           │
                    │    V28.1.F Memory ──────► V28.1.H E2E ◄─┘
                    │
                    ├──► V28.2 AI Shell (needs V28.1.H for Gemma 3)
                    │
                    ├──► V28.3 GPU Compositor (INDEPENDENT of V28.1)
                    │
                    ├──► V28.4 AI Scheduler (needs V28.1.H for Gemma 3)
                    │
                    └──► V28.5 CI Gates (after V28.1-V28.4)
```

### Cross-Phase Dependencies

```
V28 "Intelligence" ──► V29 "Foundation"
  Gemma 3 works         Multi-binary build
  GPU compositor         Type-safe IPC
  AI shell               User runtime
                         SMT verification
         │
         ▼
V29 ──────────────────► V30 "Desktop"
  Separate service ELFs    GPU compositor (from V28)
  @message IPC             + window manager
  User-mode runtime        + widget toolkit
                           + @app framework
         │
         ▼
V30 ──────────────────► V31 "Ecosystem"
  Desktop environment      Self-hosting compiler
  Widget toolkit           Package manager
  @app framework           Text editor (GUI)
                           REPL + debugger
         │
         ▼
V31 ──────────────────► V32 "Hardware"
  Self-hosting compiler    UEFI boot
  Package manager          Real NVMe/USB/WiFi/HDMI
  Dev tools                RTX 4090 compute
         │
         ▼
V32 ──────────────────► V33 "Verified"
  Real hardware            SMT verification
  All drivers working      Cap<T> type system
  Production OS            Secure boot
                           Sandboxing
```

### Parallel vs Sequential

**Within V28 (parallelizable):**
- V28.1.C (GQA), V28.1.D (RoPE), V28.1.E (Sliding) are independent of each other
- V28.1.F (Memory) is independent of V28.1.B-E
- V28.3 (GPU compositor) is completely independent of V28.1 (Gemma 3)

**Across phases (strictly sequential):**
- V29 REQUIRES V28 complete (Gemma 3 + GPU are the "Intelligence" foundation)
- V30 REQUIRES V29 complete (multi-binary + type-safe IPC enable real desktop)
- V31 REQUIRES V30 complete (desktop environment provides the surface for dev tools)
- V32 can BEGIN after V31.1 (self-hosting compiler) -- hardware drivers do not require ecosystem
- V33 can BEGIN after V32.1 (bare-metal boot) -- verification runs on real hardware

### Decision Gates

| Gate | Location | Decision File | Blocks |
|------|----------|--------------|--------|
| V28.1.H-GATE | After Gemma 3 E2E | `docs/V28_GEMMA3_DECISION.md` | V28.2, V28.4 |
| V29.1-GATE | After multi-binary | `docs/V29_BUILD_DECISION.md` | V29.4 (service ELFs) |
| V30.2-GATE | After WM works | `docs/V30_DESKTOP_DECISION.md` | V30.4 (@app framework) |
| V31.1-GATE | After self-hosting | `docs/V31_COMPILER_DECISION.md` | V31.2-V31.5 |
| V32.1-GATE | After bare metal boot | `docs/V32_HARDWARE_DECISION.md` | V32.2-V32.7 |
| V33.1-GATE | After SMT proofs | `docs/V33_VERIFICATION_DECISION.md` | V33.2-V33.5 |

Each gate must be a committed file (Rule 6) with: chosen option, justification, rollback plan, timestamp, and author signature.

---

## PART 5: RISK REGISTER

### Technical Risks

| ID | Risk | Probability | Impact | Mitigation |
|----|------|------------|--------|-----------|
| T1 | Gemma 3 1B 2-bit quantization produces incoherent output | Medium | High | Fallback to 3-bit (375 MB, still fits in 1GB). Have SmolLM-135M as known-working baseline. |
| T2 | Extended 1GB identity mapping breaks boot (triple fault) | Low | Critical | Map incrementally, test each 128MB region separately. Keep V27 boot as rollback. |
| T3 | Frame-allocated d=1152 vectors cause cache thrashing, >5s per token | Medium | Medium | Profile with `perf` counters. Tile matmul to improve cache locality. Consider SIMD (AVX2). |
| T4 | VirtIO-GPU 2D is too slow for 60 FPS compositing | Medium | Medium | Implement damage tracking (only re-render changed regions). Consider software fallback. |
| T5 | Multi-binary build breaks Fajar Lang's single-binary assumption | High | High | Incremental: first support directory mode, then service manifest. Keep concatenation as fallback. |
| T6 | Type-safe IPC (@message) adds significant compile time | Low | Low | Generate serialize/deserialize as simple memcpy for fixed-size structs. Benchmark compile time. |
| T7 | Self-hosting compiler port is too large (Cranelift alone is 400K LOC of Rust) | High | Critical | Port subset: interpreter-based execution ON FajarOS (not Cranelift). Generate ELF via simple codegen. |
| T8 | WiFi (Intel AX211) firmware loading requires huge firmware blob | High | Medium | Start with Ethernet (Intel I219-LM, simpler). WiFi is stretch goal for V32. |
| T9 | RTX 4090 NVIDIA GPU programming requires undocumented MMIO | High | High | Use nouveau open-source docs. Limit to basic compute dispatch. Full CUDA not realistic. |
| T10 | SMT verification of 18 syscalls takes too long to solve | Medium | Medium | Verify subset (6 critical syscalls) first. Scale to full set incrementally. |

### Schedule Risks

| ID | Risk | Probability | Impact | Mitigation |
|----|------|------------|--------|-----------|
| S1 | V28.1 Gemma 3 integration takes longer than 120h (60% overrun) | Medium | Medium | Surprise budget +25% (152h total). Can drop V28.4 (AI scheduler) to stay on schedule. |
| S2 | V29 multi-binary build requires major compiler refactoring | High | High | Start V29.1 compiler work early (in parallel with V28 OS work). 60h dedicated budget. |
| S3 | V32 hardware drivers are harder than QEMU emulation suggests | High | High | Each driver has independent 2-week budget. Can defer WiFi + Audio + GPU to V33. |
| S4 | External dependency: Google may change Gemma 3 format/weights | Low | Medium | Export and freeze weights in .fjm v2 format at V28 start. Independent of upstream. |
| S5 | Disk failure loses local work | Low | Critical | Rule 8 multi-repo check. Push to GitHub within 24h of any session. |

### Risk Priority Matrix

```
              Low Impact     Medium Impact   High Impact    Critical Impact
High Prob  │              │ T8 WiFi FW     │ T5 Multi-bin  │ T7 Self-host
           │              │ S3 HW drivers  │ T9 RTX 4090   │
Medium Prob│              │ T3 Cache       │               │ T2 Boot break
           │ T6 Compile   │ T4 GPU FPS     │               │
           │              │ T1 Quant qual  │               │
           │              │ T10 SMT time   │               │
Low Prob   │              │ S4 Gemma fmt   │               │ S5 Disk fail
```

---

## PART 6: SUCCESS METRICS

### Per-Phase Measurable Gates

| Phase | Metric | Measurement Command | Pass Criteria |
|-------|--------|-------------------|---------------|
| **V28** | Gemma 3 1B inference | `make run-kvm-llvm`, `ask "What is 2+2?"` | Coherent English answer in <30 seconds |
| **V28** | GPU compositor | `make run-gpu-llvm`, `fb-test` | Colored rectangles on QEMU GTK window |
| **V28** | AI shell | `make run-kvm-llvm`, `ai show my ip` | Proposes `ifconfig`, executes on confirm |
| **V28** | Test suite | `make run-kvm-llvm`, `test-all` | 36/36 pass |
| **V29** | Separate ELFs | `make microkernel && ls build/*.elf` | kernel.elf + 5 service ELFs |
| **V29** | Type-safe IPC | Compile `@message struct Bad { x: str }; ipc_send(0, VfsOpen { ... })` | Wrong type -> compile error |
| **V29** | User-mode | Compile `@safe fn main() { println("hello") }` as user ELF | Runs via SYSCALL, prints on serial |
| **V29** | SMT proof | `z3 proofs/syscall_safety.z3` | "sat" for all safety properties |
| **V30** | 3+ windows | `make run-gpu-llvm`, open calculator + editor + terminal | All 3 visible, tiling layout |
| **V30** | AI text field | Type in TextBox, press AI assist | LLM suggests completion |
| **V30** | FPS | `make run-gpu-llvm`, `comp-bench` | >30 FPS with 3 windows |
| **V31** | Self-hosting | `fj build hello.fj -o hello.elf` on FajarOS | hello.elf runs, prints "hello" |
| **V31** | Package install | `pkg install fj-math` on FajarOS | Package installed, `pkg list` shows it |
| **V31** | GUI editor | Open .fj file in editor, syntax highlighting visible | Keywords colored, saves to VFS |
| **V32** | Bare metal boot | Power on Lenovo Legion Pro | `nova>` prompt on HDMI monitor |
| **V32** | NVMe real HW | `ls /mnt` on bare metal | Files from NVMe SSD listed |
| **V32** | WiFi connect | `wifi connect MyNetwork` on bare metal | `ping 8.8.8.8` gets reply |
| **V32** | GPU compute | `ask-bench` on bare metal with RTX 4090 | Tokens/sec measurably faster than CPU |
| **V33** | SMT proof | `z3 proofs/full_verification.z3` | All properties proved (unsat for negation) |
| **V33** | Cap<T> enforced | Compile `@safe fn hack() { port_outb(0, 0) }` without Cap<PortIO> | Compile-time error |
| **V33** | Secure boot | Attempt to boot unsigned kernel on Lenovo | Boot refused |
| **V33** | Isolation proof | Kill VFS service while NET is active | NET continues working, VFS restarts |

### Longitudinal Metrics (Tracked Across All Phases)

| Metric | V27 (Now) | V28 | V29 | V30 | V31 | V32 | V33 |
|--------|-----------|-----|-----|-----|-----|-----|-----|
| Total LOC | 106,722 | ~111K | ~120K | ~140K | ~160K | ~180K | ~195K |
| .fj files | 183 | 188 | 210 | 250 | 280 | 310 | 330 |
| Shell commands | 302 | 314 | 320 | 340 | 360 | 380 | 390 |
| Kernel tests | 25 | 36 | 50 | 65 | 80 | 100 | 120 |
| Ring 0 TCB LOC | ~5,000 | ~5,500 | ~3,000* | ~3,000 | ~3,000 | ~3,200 | ~3,200 |
| Service ELFs | 0 | 0 | 6 | 8 | 10 | 12 | 12 |
| GUI apps | 0 | 0 | 0 | 4 | 8 | 10 | 10 |
| Hardware platforms | QEMU only | QEMU | QEMU | QEMU | QEMU | Real + QEMU | Real + QEMU |
| Formal properties proved | 0 | 0 | 4 | 4 | 4 | 4 | 20+ |
| AI model | SmolLM-135M | Gemma 3 1B | Gemma 3 1B | Gemma 3 1B | Gemma 3 1B | Gemma 3 1B | Gemma 3 1B |

*V29 Ring 0 TCB drops because services move to separate ELFs.

---

## PART 7: PLAN HYGIENE COMPLIANCE CHECKLIST

Every phase in this plan was designed to comply with all 8 Plan Hygiene Rules:

| Rule | How This Plan Complies |
|------|----------------------|
| 1. Pre-flight audit mandatory | V28.0 through V33.0 -- every phase starts with a dedicated pre-flight subphase producing `docs/V<N>_B0_FINDINGS.md` |
| 2. Runnable verification commands | Every task table has a "Verification" or "Verification Command" column with literal `make run-kvm-llvm` + shell commands |
| 3. Prevention layer per phase | V28.5 adds 3 CI workflows + memory collision detector. Each subsequent phase adds at least 1 prevention mechanism |
| 4. Multi-agent cross-check | V28.0.8 multi-repo state check. All LOC/test counts derived from `wc -l` and `make loc`, not estimated |
| 5. Surprise budget +25% | Every phase: 320h base + 80h surprise = 400h. Commit messages will tag actual variance |
| 6. Decision gates are mechanical files | 6 gate files defined (V28_GEMMA3_DECISION.md through V33_VERIFICATION_DECISION.md) |
| 7. Public-facing artifact sync | V28.5.7 CHANGELOG update, V28.5.8 git tag, README update included in every release phase |
| 8. Multi-repo state check | V28.0.8 explicitly checks fajaros-x86, Fajar Lang, and fajarquant repos |

### Self-Check Before Each Phase

```
[ ] Does this Phase have a B0/C0/D0 pre-flight audit?                (Rule 1)
[ ] Does every task have a runnable verification command?            (Rule 2)
[ ] Does this Phase add at least one prevention mechanism?           (Rule 3)
[ ] If I cite numbers, did I cross-check with Bash commands?         (Rule 4)
[ ] Did I include +25% surprise budget in effort table?              (Rule 5)
[ ] If this Phase has decisions, are they committed files?           (Rule 6)
[ ] If I touched internal docs, did I check public-facing drift?     (Rule 7)
[ ] Did I run multi-repo state check before starting?                (Rule 8)
```

---

## PART 8: GLOSSARY AND REFERENCES

### Key Terms
- **TCB (Trusted Computing Base):** The subset of code that must be correct for security to hold. In FajarOS, this is the Ring 0 kernel core.
- **GQA (Grouped Query Attention):** Attention variant where multiple query heads share one key-value head. Gemma 3 uses 4:1 ratio.
- **RoPE (Rotary Position Embedding):** Position encoding that rotates query/key vectors by position-dependent angles.
- **FajarQuant:** Adaptive vector quantization algorithm for LLM weight compression (2-bit). Published as separate repo.
- **.fjm:** FajarOS model format for quantized neural network weights.
- **.fjt:** FajarOS tokenizer format for vocabulary tables.

### Reference Documents
- `/home/primecore/Documents/fajaros-x86/CLAUDE.md` -- FajarOS project identity and build system
- `/home/primecore/Documents/fajaros-x86/docs/FAJAROS_MASTER_PLAN.md` -- V1-V3 completed plan (240 tasks)
- `/home/primecore/Documents/fajaros-x86/docs/GEMMA3_UPGRADE_PLAN.md` -- Gemma 3 1B phases A-H (basis for V28.1)
- `/home/primecore/Documents/fajaros-x86/docs/COMPILER_ENHANCEMENTS.md` -- 12 compiler enhancements (basis for V29)
- `/home/primecore/Documents/fajaros-x86/docs/COMPARISON_VS_MACOS.md` -- honest macOS comparison
- `/home/primecore/Documents/fajaros-x86/docs/SAFETY_MODEL.md` -- compile-time safety enforcement
- `/home/primecore/Documents/fajaros-x86/docs/MICROKERNEL_SPEC.md` -- syscall API and service protocols
- `/home/primecore/Documents/fajaros-x86/docs/MEMORY_MAP.md` -- unified address allocation
- `/home/primecore/Documents/Fajar Lang/CLAUDE.md` -- compiler identity and capabilities
- `/home/primecore/Documents/Fajar Lang/docs/V26_PRODUCTION_PLAN.md` -- V26 plan with hygiene rules (69KB reference)

---

### Critical Files for Implementation
- `/home/primecore/Documents/fajaros-x86/kernel/compute/transformer.fj` -- 1,581 LOC, the core file for V28.1 Gemma 3 integration (GQA, RoPE, sliding window, gated FFN all modify this file)
- `/home/primecore/Documents/fajaros-x86/kernel/mm/paging.fj` -- 118 LOC, must be extended for 1GB identity mapping in V28.1.F1 (critical for Gemma 3 memory layout)
- `/home/primecore/Documents/fajaros-x86/drivers/virtio_gpu.fj` -- 263 LOC (currently from `drivers/virtio_gpu.fj`), the GPU driver that V28.3 GPU compositor depends on
- `/home/primecore/Documents/fajaros-x86/kernel/compute/model_loader.fj` -- 2,183 LOC, must be updated for .fjm v2 format in V28.1.G (GQA weights, RMSNorm, gated FFN layout)
- `/home/primecore/Documents/Fajar Lang/CLAUDE.md` -- compiler CLAUDE.md that defines the plan hygiene rules (section 6.8) governing all phases of this plan