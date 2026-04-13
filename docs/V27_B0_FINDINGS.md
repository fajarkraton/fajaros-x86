# V27 Phase B0 — Pre-Flight Audit Findings

**Date:** 2026-04-14
**Method:** grep + hands-on verification

## Results

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| B0.1 serial_send_str stub | TODO at line 79 | `drivers/serial.fj:79` confirmed | MATCH |
| B0.2 frame_alloc unchecked | 4 sites | `dispatch.fj:295,319` + `elf.fj:91,149` confirmed | MATCH |
| B0.3 kernel stack TODO | TODO at line 159 | `process.fj:159` confirmed | MATCH |
| B0.4 dead code | cmd_type + cmd_yes_arg | Lines 1980 + 2570 confirmed | MATCH |
| B0.5 SMAP coverage | 1 call site | Only `dispatch.fj:97` has smap_disable | MATCH |

## Surprises

None. All baselines match V26 re-audit findings exactly. B1-B4 unblocked.

## Gate

B0 complete. B1-B4 unblocked.
