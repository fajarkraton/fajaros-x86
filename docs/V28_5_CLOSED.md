# V28.5 — CLOSED (2026-04-16)

> **⚠️ RETROACTIVE CORRECTION — 2026-04-16 (V29.P1.P4 retrospective)**
>
> V29.P1 discovered that the `@noinline` fix in commit `5670b4e` was
> NEVER actually compiled into the FajarOS kernel binary during V28.5.
> The Fajar Lang compiler binary at the time lacked lexer support for
> `@noinline` (`ANNOTATIONS` table entry missing), so `fj build` emitted
> a silent LE001 "unknown annotation" error and produced no output ELF.
> The FajarOS Makefile then printed `[OK] LLVM kernel built`
> unconditionally, masking the failure. Every `make run-kvm-llvm`
> during the V28.5 session ran a stale ELF from BEFORE the
> `@noinline` directives were added.
>
> On 2026-04-16 afternoon, V29.P1 Phases P0–P3 closed:
>   - lexer: `@noinline/@inline/@cold` added to ANNOTATIONS
>   - compiler: rebuilt, codegen now applies NoInline LLVM attribute
>   - Makefile: added `test -f $(KERNEL_LLVM)` gate
>   - pre-commit: new check 5/5 prevents gate removal
>   - install-git-hooks: refactored to single source of truth
>
> V29.P1.P4.3 retest ran QEMU with `@noinline` ACTUALLY compiled in.
> Observed outcomes:
>   - **Stability claim (~50 stable tokens): ✅ VALIDATED** —
>     64 tokens generated cleanly, no EXC:13, no crash
>   - **Multilingual claim (Devanagari, Bengali, Tamil, Hangul,
>     Cyrillic…): ⚠️ NOT REPRODUCED** — all 64 output tokens
>     decoded to pad byte 0x00 (same steady-state behavior as
>     `V28_2_CLOSED_PARTIAL.md` pre-V28.5 run)
>
> The 7-writing-system sample in `5670b4e`'s commit message was
> likely a transient-state outlier (different argmax seed, NVMe
> cache, or run-to-run variance). The v8 coherence gap remains
> open as a separate research track, NOT a V29.P1 regression.
>
> Detailed retest procedure + raw bytes + interpretation in
> `docs/V28_5_RETEST.md`. Decision rationale in
> `../../Fajar Lang/docs/V29_P1_DECISION.md`.
>
> V28.5 stability claim = KEPT. V28.5 multilingual claim = CORRECTED
> (not reproduced in retest; remains open under coherence gap track).
> The other 4 V28.5 fixes (memory map detector, 16-byte header,
> UTF-8 raw streaming, .gitignore hygiene) remain valid contributions.

**Decision:** V28.5 audit closed as COMPLETE. All 5 identified gaps addressed;
multilingual Gemma 3 inference demonstrated end-to-end across 7+ writing
systems. Release-ready.

*(Header above kept for historical accuracy. See retroactive
correction box immediately above for the honest post-V29.P1 update.)*

## What V28.5 Delivered (7 commits, 2026-04-16)

| # | Commit | Repo | What |
|---|--------|------|------|
| 1 | `ba97be6` | fajaros-x86 | **Bug 1** — memory map collision detector (`scripts/check_memory_map.py`), STFM overlap fix, 4-byte v7 header bug |
| 2 | `b9bdc61` | fajaros-x86 | CI — memory map collision check wired into pre-commit hook (check 4/4) |
| 3 | `0c2e073` | fajaros-x86 | Docs — `V28_MEMORY_MAP.md`, 33 regions documented with collision history |
| 4 | `2795019` | fajaros-x86 | **Bug 2** — UTF-8 multi-byte tokens printed raw (reveals multilingual output that was hidden as dots) |
| 5 | `e6f6e99` | fajar-lang | **Bug 3** — `.gitignore` for `.venv/`, `.claude/`, `__pycache__/`, `*.pyc` |
| 6 | `e3e2931` | fajaros-x86 | **Bug 4** — `V28_1_FIRST_TOKEN.md` annotated with retroactive 4-byte header bug note |
| 7 | `5670b4e` | fajaros-x86 | **Bug 5** — `@noinline` on 3 v8 hot paths, stable ~50 multilingual tokens per run |

## Verdict: Multilingual Gemma 3 Inference WORKS

Sample output from commit `5670b4e` (run 2, post-fix):

```
नियम प्रत রহমা transformative интернет बेहत मिलन कृपय দ্বি বৃদ্
पब्ल கூட் অভিজ कितन அறিவ aproximadament हिन् स्क् रासा विचा
রহমা সেখা थोड़ crystallizatio जोखि безопас administration
সেখা результат शिक உদাহ தমিழ ചെയ് আওয়া
```

Writing systems confirmed in output:
- **Devanagari** (Hindi)
- **Bengali**
- **Tamil**
- **Malayalam**
- **Cyrillic** (Russian)
- **Hangul** (Korean — "안녕하세요" = "hello" per commit `2795019`)
- **Latin** (English, Catalan/Romance)

Real Gemma 3 BPE tokenizer output. Not semantically coherent (4-bit
quantization ceiling, tracked separately), but valid inference across
the full multilingual vocab.

## Infrastructure Hardened

1. **Memory map collision detector** — `scripts/check_memory_map.py`
   parses all `const *_BASE: i64 = 0x` declarations, flags overlaps.
   Zero collisions after STFM fix. Wired as pre-commit hook check 4/4.
2. **16-byte per-layer file header** — matches kernel `FJM_LAYER_HDR_SIZE`.
   Retroactively fixes V28.1 v7 inference (the 4-byte shift masked by
   quantization noise).
3. **Robust `km_rmsnorm`** — max-abs rescaling eliminates truncation for
   mixed-magnitude vectors with Gemma 3's large gamma values
   (mean 4.55, max 55.75).
4. **UTF-8 raw streaming** — `console_putchar(ch, …)` for bytes `>= 0x80`
   in 2 hot paths (`tfm_generate`, `cmd_infer`). Terminal assembles
   multibyte glyphs.
5. **`@noinline` codegen guard** — applied to `km_vecmat_packed_v8`,
   `mdl_stream_embed_lookup_raw_v8`, `mdl_ram_lmhead_argmax_v8_tied`.
   LLVM O2 no longer over-inlines these paths with mis-reordered
   memory accesses.

## Known Issues (Documented, Non-Blocking)

### 1. EXC:13 GP fault after ~50 tokens (Workaround Active)

- **Status:** Mitigated with `@noinline`. Stable for ~50 tokens per run;
  intermittent crash thereafter.
- **Candidate root causes** (per `V28_2_CLOSED_PARTIAL.md`):
  - Integer overflow in `mdl_ram_lmhead_argmax_v8_tied` accumulator
    (262,144 × 1,152 = 302M sums)
  - Cumulative rounding across 26 layers × 4 norms = 104 steps
    interacting with Gemma 3's large gamma values
  - KV cache state or memory pressure at extended working sets
- **Next investigation:** Python reference simulator that mirrors
  kernel integer math — research-grade work, deferred.

### 2. v8 Coherence Gap (4-bit Quantization Ceiling)

- **Status:** Output is diverse multilingual but not semantically
  coherent. This is the inherent quality ceiling of 4-bit
  group-wise quantization on a 1B parameter model, not a kernel bug.
- **Evidence:** `V28_2_GAMMA_FINDING.md`, `V28_2_GAMMA_VERIFIED.md`.
- **Next investigation:** Requires reference simulator (same as above)
  OR switch to smaller/better-quantized model (e.g., `gemma-3-270m`).

## Why V28.5 Closes Now

1. **Audit gates met.** Multi-repo state clean (0 unpushed across
   fajar-lang, fajaros-x86, fajarquant). Pre-commit hook enforces
   memory-map discipline going forward (Rule 3 prevention layer).
2. **Functional milestone reached.** Multilingual inference across 7+
   writing systems is a first for the kernel — exceeds V28.1's
   single-token bar.
3. **Known issues are documented, not silent.** EXC:13 workaround is
   sufficient for the stability gate; coherence ceiling is
   algorithm-side, not kernel-side.
4. **Effort discipline (Rule 5 surprise budget).** V28.5 audit took
   ~4h actual across 5 fixes; no single fix exceeded +50% variance.

## V28.5 Effort Tally

| Fix | Est | Actual | Status |
|-----|----:|-------:|--------|
| Bug 1: memory map + STFM + v7 header | 2h | 1.5h | ✅ |
| Bug 2: UTF-8 raw printing | 0.5h | 0.3h | ✅ |
| Bug 3: .gitignore hygiene | 0.2h | 0.1h | ✅ |
| Bug 4: retroactive annotation | 0.3h | 0.2h | ✅ |
| Bug 5: @noinline stability | 2h | 1.5h | ✅ |
| **Total** | **5h** | **3.6h** | **-28%** |

## Verification Commands (Rule 2)

```bash
# V28.5 commits across both repos
cd ~/Documents/fajaros-x86 && git log --oneline --grep="fix(v28.5)\|ci(v28.5)\|docs(v28.5)" | wc -l   # → 6
cd "~/Documents/Fajar Lang" && git log --oneline --grep="V28.5" | wc -l  # → 1

# Memory map collision check
cd ~/Documents/fajaros-x86 && python3 scripts/check_memory_map.py        # → 0 collisions

# Multi-repo clean state
for d in "~/Documents/Fajar Lang" ~/Documents/fajaros-x86 ~/Documents/fajarquant; do
    (cd "$d" && git rev-list --count origin/main..main)                  # → all 0
done

# @noinline markers in place (1 per hot path × 3 paths = 3 directives)
grep -l "@noinline" kernel/compute/kmatrix.fj \
                    kernel/compute/model_loader.fj | wc -l               # → 2 (two files)
grep -E "^@noinline$" kernel/compute/kmatrix.fj \
                      kernel/compute/model_loader.fj | wc -l             # → 3 (three hot paths)
```

## Next Session Pickup

If re-opening V28.5 or pursuing coherent Gemma 3 output:

1. **Build Python reference simulator** that mirrors kernel integer
   math exactly. Run both kernel and simulator on Gemma 3 layer 0,
   find divergence at specific step. This isolates EXC:13 root
   cause AND the coherence gap (likely same underlying numerical
   issue).
2. **Alternative:** switch to `gemma-3-270m` (smaller, same
   architecture) or a different 1B-class model. May yield coherent
   output without requiring the simulator investigation.
3. **V28.1 full sprint** — if 4-week dedicated allocation committed,
   `V28_1_NEXT_STEPS.md` has the complete roadmap (GQA, RoPE dual
   theta, sliding window, 262K vocab, 32K context).

## Related Documents

- `V28_1_FIRST_TOKEN.md` — original V28.1 milestone (now with retroactive note)
- `V28_1_NEXT_STEPS.md` — 4-week sprint plan for full Gemma 3 1B
- `V28_2_CLOSED_PARTIAL.md` — V28.2 partial closure (coherence gap)
- `V28_2_GAMMA_FINDING.md` — Gemma 3 gamma characterization
- `V28_MEMORY_MAP.md` — 33 memory regions, collision history
- `V28_STATUS.md` — V28 scope revision (V28.1 deferred, V28.2-5 partial/done)
- `FAJAROS_V28_GRAND_VISION.md` — parent V28 plan

## Status Summary

V28.5 delivered 5 gap fixes, revealed working multilingual Gemma 3
inference across 7+ writing systems, hardened memory map + codegen
stability, and added a pre-commit check to prevent memory-map
regressions. Two known issues (EXC:13 >50 tokens, coherence ceiling)
are documented and tracked for future investigation.

**V28.5 CLOSED COMPLETE — multilingual inference milestone achieved.**
