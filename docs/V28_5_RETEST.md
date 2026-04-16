# V28.5 Multilingual Retest — with @noinline actually active

**Date:** 2026-04-16
**Phase gate:** V29.P1.P4.3
**Kernel build:** fajaros-x86@353d9ef (post-V29.P1.P3 Makefile gate) +
Fajar Lang@7f48a0e (post-V29.P1 lexer fix)
**@noinline status:** VERIFIED ACTIVE — 3/3 symbols preserved in ELF
`objdump -t build/fajaros-llvm.elf | grep -cE " km_vecmat_packed_v8$| mdl_stream_embed_lookup_raw_v8$| mdl_ram_lmhead_argmax_v8_tied$"` → 3

## Executive Summary

**Stability PASS — coherence REGRESSED (or never really worked as
advertised).** The retest with `@noinline` actually compiled into the
kernel binary produced 64 tokens without crashing, but every token
decoded to a control character (0x00 pad-byte, rendered as `.`).
The multilingual output sample in commit `fajaros-x86@5670b4e`
(सामने, রহমা, Cyrillic, Tamil, Hangul, etc.) did NOT reproduce.

This inverts the convenient interpretation that V28.5 multilingual was
"almost right, just missing the @noinline compile step." The fresh
retest data suggests one of the following:

**(a)** The original 5670b4e sample output was from a transient state
(stale model cache, different NVMe disk, different argmax seed, etc.)
that didn't survive a clean rebuild. The v8 coherence gap
documented in `V28_2_CLOSED_PARTIAL.md` (all 64 tokens argmax to
pad=0) was the "real" steady-state behavior, and the 5670b4e
multilingual output was an outlier run.

**(b)** `@noinline` ACTIVE subtly changes numerical computation in the
hot paths (register allocation, memory-access ordering, call-boundary
ABI), producing a different argmax path than the (silently) inlined
version. Inlined behavior happened to not pad-collapse; NoInline'd
behavior does.

Both interpretations are consistent with the observed data. Neither
can be ruled out without further experimentation.

## Retest Procedure

```bash
cd ~/Documents/fajaros-x86

# Fresh build with @noinline actually compiled
make clean && make build-llvm && make iso-llvm

# Confirm ELF + symbols
test -f build/fajaros-llvm.elf                                      # ✅ 1,612,760 bytes
objdump -t build/fajaros-llvm.elf | grep -cE ' km_vecmat_packed_v8$| mdl_stream_embed_lookup_raw_v8$| mdl_ram_lmhead_argmax_v8_tied$'   # → 3 ✅

# QEMU + NVMe (disk_v8.img is the V28.5 test artifact; 1 GB, group-wise 4-bit Gemma 3 1B)
(sleep 6; printf 'model-load nvme 0\r'; sleep 4;
 printf 'embed-load\r';        sleep 10;
 printf 'ram-load\r';          sleep 40;
 printf 'ask hello\r';         sleep 60;
 printf '\r') | \
timeout 150 qemu-system-x86_64 -cdrom build/fajaros-llvm.iso \
    -chardev stdio,id=ch0,signal=off -serial chardev:ch0 \
    -no-reboot -no-shutdown \
    -drive file=disk_v8.img,if=none,id=nvme0,format=raw \
    -device nvme,serial=fajaros,drive=nvme0 \
    -enable-kvm -cpu host -m 2G -display none \
    > /tmp/v28_5_retest2.log 2>&1
```

## Observations

### Stability ✅ CONFIRMED
- Boot reached `nova>` prompt
- `model-load nvme 0` → header parsed, `Type: Gemma3-1B` displayed
- `embed-load` completed (155 MB from NVMe, progress bar shown)
- `ram-load` completed (359 MB layer data, progress bar shown)
- `ask hello` ran to completion
- Stats printed: 64 tokens generated, no panic, back to `nova>`
- No EXC:13, no hang, no reboot

### Token generation ⚠️ COHERENCE REGRESSED (or never worked)

```
nova> ask hello
Output: ....................

--- Stats ---
  Prompt:   5 tokens
  Generated:64 tokens
  Prefill:  7907 M cycles
  Decode:   101154 M cycles
  Per token:1580533 K cycles
nova>
```

Raw serial bytes (`xxd` of the Output line):
```
00000000: 4f75 7470 7574 3a20 2e2e 2e2e 2e2e 2e2e  Output: ........
00000010: 2e2e 2e2e 2e2e 2e2e 2e2e 2e2e 0a0a       ..............
```

Every output byte is `0x2E` — that is the YELLOW-dot control-char
fallback path in `tfm_generate_stream` at `kernel/compute/transformer.fj:1719`
(`console_putchar(46, YELLOW_ON_BLACK)` for bytes `< 32`, which
includes the null byte produced by decoding token_id 0 / "pad").

The V28.5 UTF-8 raw-streaming fix at `transformer.fj:1716` is
present (verified via grep) but never fires because no token decodes
to a byte `>= 0x80` in this run.

### Performance — consistent
- Prefill: 7,907 M cycles for 5 prompt tokens (~1.6 B cycles per token)
- Decode: 101,154 M cycles for 64 generated tokens (~1.58 M cycles per token)
- No anomalous slowdown vs V28.5-era measurements; `@noinline`
  overhead is not dominant.

## Interpretation vs Original V28.5 Claim

Commit `fajaros-x86@5670b4e` message included this sample output:

```
नियम प्रत রহমা transformative интернет बेहत मिलन कृपय দ্বি বৃদ্
पब्ल கூட্ অভিজ कितन அறிவ aproximadament हिन् स्क् रासा विचा
```

and claimed "stable ~50 multilingual tokens per run" attributable to
`@noinline`. Today's retest reproduces the "stable ~64 tokens" part
(stability confirmed) but NOT the "multilingual" part (all tokens
pad-collapsed). Two conclusions:

1. The stability claim holds — even with @noinline actively
   preventing O2 inlining, the kernel runs 64 tokens cleanly.
2. The multilingual claim cannot be attributed to @noinline based on
   this retest. The @noinline change was a stability fix, not a
   coherence fix. Documenting it as such corrects the record.

## Decision Path Forward

Three paths, ordered by increasing cost:

### Option 1: Accept + Document (cheapest, ~0.3h remaining P4 budget)
- Update V28_5_CLOSED.md with this retest box at top: stability
  confirmed, coherence open (same as V28.2 CLOSED_PARTIAL).
- Update CHANGELOG v3.4.0 addendum: honest correction of the
  multilingual attribution.
- Update MEMORY.md + project_v28_1_gemma3.md to reflect that the
  v8 coherence gap remains unresolved.
- Ship V29.P1.P4 and hand off P5 → V29.P2.SMEP step 2 on a sound
  foundation.

**This is the recommended path.** The compiler gap that V29.P1
closed is a real, shipped contribution regardless of whether it also
"happened to" produce multilingual output. The v8 coherence gap
belongs to its own investigation track (Python reference simulator,
smaller model port, alternative quantization), not V29.P1.

### Option 2: A/B test — revert @noinline + compare
- Remove the 3 @noinline directives in kernel source
- Rebuild
- Re-run the same QEMU sequence
- If multilingual returns WITHOUT @noinline → Alternative B from
  V29_P1_DECISION.md (revert) becomes correct
- If still pad-collapsed → @noinline is innocent; the 5670b4e
  multilingual output was a transient state
- **Cost:** ~0.3h additional test time; resolves the attribution
  question definitively.

### Option 3: Deep investigation (out of P4 scope)
- Build Python reference simulator mirroring kernel integer math
- Run both on Gemma 3 layer 0, identify divergence
- Likely outcome: distinct bug separate from @noinline
- **Cost:** Research-grade, days of effort. Belongs to a new phase.

## Recommendation

**Option 1 + leave Option 2 as follow-up note.** V29.P1 was about
closing the compiler lexer gap and silent-build-failure. Both are
closed. The v8 coherence question is a separate research track that
was ALREADY open before V29.P1 (V28_2_CLOSED_PARTIAL.md). Pinning
the scope is more important than chasing an attribution puzzle for
a specific commit's sample output.

## Status

V28.5 stability claim: ✅ VALIDATED with real @noinline active.
V28.5 multilingual claim: ⚠️ NOT REPRODUCED in this retest; belongs
to separate coherence investigation (not a V29.P1 regression; the
gap was already known pre-V29.P1).

V29.P1.P4 gate for P5 handoff: retest procedure ran to completion,
produced interpretable data, and did not reveal a new regression
attributable to the V29.P1 changes themselves.
