# V30 Track 4 — ext2 + FAT32 Disk Harness Plan

**Session:** V30 Track 4
**Status:** DRAFT (this document is the Rule-1 Pre-Flight deliverable)
**Owner:** Muhamad Fajar Putranto
**Entry doc:** `V29_P2` commit message scope-pin —
  *"ext2/FAT32 tests need disk-backed mount which isn't set up at
   boot-test time"*
**Goal:** Make ext2 + FAT32 write paths regressable via a
 QEMU-driven test harness. Build pre-populated disk images at build
 time, mount them at kernel-test time, run write-roundtrip tests
 from the shell, grep invariants on the serial log.

---

## 1. Context (from audit of current HEAD)

**Found present:**

- `fs/fat32.fj`: `fat32_mount`, `fat32_write_cluster`,
  `fat32_write_fat_entry`, `fat32_find_in_dir`, `fat32_read_file`,
  `cmd_fat32_mount` (shell command live). Used by scheduler
  + exec loader.
- `fs/ext2_ops.fj`: `ext2_write_file`, `ext2_write_block`,
  directory write-back path. Super-block + indirect-block support
  live in `fs/ext2_super.fj` + `fs/ext2_indirect.fj`.
- `fs/vfs.fj`: shared VFS layer.
- `services/vfs/main.fj`: userland side.
- `tests/kernel_tests.fj`: test runner exists (35 tests landed in
  V29.P2). No ext2/FAT32 tests yet (the V29.P2 scope-pin).

**Found missing:**

1. No disk-image builder script in `scripts/` (no `disk-builder.py`,
   no `mkfs` wrapper).
2. No Makefile target for building + mounting a test disk.
3. No `nvme0`-targeted ext2/FAT32 tests in `tests/kernel_tests.fj`.
4. No CI step for the ext2/FAT32 gate.

**Found working (pattern to reuse):**

- `test-security-triple-regression` Makefile target (6 grep
  invariants, proven pattern).
- `test-gemma3-e2e` + `test-gemma3-kernel-path` (9 grep invariants,
  NVMe-backed, shipped in V30 Track 2 P11).
- `test-fjtrace-capture` — shows how to attach NVMe + run shell
  commands + parse serial log.

---

## 2. Phased Approach (V29.P1 pattern)

### Phase P0 — Pre-Flight Audit (this doc)

Rule 1 deliverable. ✅ Done.

### Phase P1 — Disk-image builder

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P1.1 | `scripts/build_test_disk.py` — ext2 image with 3 test files (README.TXT, DATA.BIN, SUBDIR/NESTED.TXT) | `file build/test-disks/ext2.img` reports ext2 fs | 0.75h |
| P1.2 | `scripts/build_test_disk.py` — FAT32 image variant via `mkfs.fat -F32` path | `file build/test-disks/fat32.img` reports FAT (32 bit) | 0.5h |
| P1.3 | Manifest-driven content: each file's bytes specified in `tests/test-disks/manifest.json` | re-running the builder produces byte-identical images | 0.25h |
| P1.4 | Both images ≤ 16 MB (QEMU startup budget) | `ls -la build/test-disks/` | 0.1h |

**Phase P1 total: 1.6h** (+25% = 2.0h)
**Gate:** Both disk images build reproducibly from manifest.

### Phase P2 — Makefile target

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P2.1 | `build/test-disks/ext2.img` + `.../fat32.img` as Makefile targets | `make build/test-disks/ext2.img` produces the file | 0.2h |
| P2.2 | `test-fs-roundtrip` target — boots ISO, attaches **both** disks as `nvme0` + `nvme1`, runs shell script, greps log | First run passes (or fails with actionable diagnostic) | 0.5h |
| P2.3 | Auto-skip if mkfs.ext2 or mkfs.fat unavailable (CI-friendly) | `which mkfs.ext2 >/dev/null || skip` | 0.1h |

**Phase P2 total: 0.8h** (+25% = 1.0h)
**Gate:** `make test-fs-roundtrip` runs end-to-end on dev host.

### Phase P3 — Kernel shell tests

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P3.1 | Add `fs-mount-ext2` + `fs-mount-fat32` shell commands if not present (audit first) | `nova> fs-mount-ext2 nvme1` returns OK | 0.5h |
| P3.2 | `test_ext2_write_roundtrip`: read README.TXT, write DATA.OUT, unmount, remount, verify DATA.OUT present | Test function in `tests/kernel_tests.fj` passes | 0.75h |
| P3.3 | `test_fat32_write_roundtrip`: same pattern on FAT32 | Test passes | 0.75h |
| P3.4 | `test_disk_mount_unmount`: mount, unmount, remount stress (5 cycles) | No corruption, all 3 files still readable | 0.5h |

**Phase P3 total: 2.5h** (+25% = 3.1h)
**Gate:** 3 new kernel tests pass → total 38 tests.

### Phase P4 — Invariant gate

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P4.1 | Extend `test-fs-roundtrip` with 4 grep invariants: ext2 mount OK, FAT32 mount OK, roundtrip PASS per fs, no EXC/PANIC | All 4 PASS lines printed | 0.25h |
| P4.2 | Prevention rule addition to CLAUDE.md §6 or equivalent: filesystem writes must be covered by roundtrip test before [x] | Rule added, referenced in commit | 0.15h |

**Phase P4 total: 0.4h** (+25% = 0.5h)
**Gate:** Regression target is the deliverable.

### Phase P5 — Doc Sync (Rule 7)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P5.1 | `CHANGELOG.md` v3.7.0 "FS Roundtrip" entry | commit | 0.2h |
| P5.2 | `CLAUDE.md` §3 V30.TRACK4 row | commit | 0.15h |
| P5.3 | MEMORY.md update | edit | 0.1h |
| P5.4 | GitHub Release v3.7.0 tag | `gh release create` | 0.15h |

**Phase P5 total: 0.6h** (+25% = 0.75h)

---

## 3. Effort Summary

| Phase | Estimate | Budget |
|-------|---------:|-------:|
| P0 Pre-Flight (this doc) | 0.3h | 0.4h |
| P1 Disk-image builder | 1.6h | 2.0h |
| P2 Makefile target | 0.8h | 1.0h |
| P3 Kernel shell tests | 2.5h | 3.1h |
| P4 Invariant gate | 0.4h | 0.5h |
| P5 Doc Sync | 0.6h | 0.75h |
| **TOTAL** | **6.2h** | **7.75h** |

Matches agenda's 4-6h range (slight over at +0.2h on P0 doc + Rule-7 sync).

---

## 4. Surprise Budget Tracking (Rule 5)

**Default +25%** per subphase (standard confidence).

Higher-risk subphase: **P3.1** — adding new shell commands if not
present. If they're already there the phase collapses to 0.1h; if
the command-dispatch byte-matching pattern needs new `buf_eq4` work,
it's closer to 1.0h. Budgeting +40% on P3.1 alone.

---

## 5. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|------------|--------|------------|
| 1 | mkfs.ext2 / mkfs.fat not on dev host | LOW | MEDIUM | Auto-skip; print install hint |
| 2 | QEMU can't attach 3 NVMe devices (model + test disks) | LOW | MEDIUM | Use `ide` or `virtio` for test disks |
| 3 | Existing ext2_write has unknown bug | MEDIUM | HIGH | P3.2 is the test that surfaces it; quarantine + V31 fix |
| 4 | Disk-image byte-order / endian mismatch with kernel parser | LOW | HIGH | P1.3 manifest + byte-identity check catches it early |
| 5 | `tests/kernel_tests.fj` runner has hardcoded count that breaks with +3 tests | LOW | LOW | 1-line fix, not a blocker |

---

## 6. Prevention Layer (Rule 3)

**New Makefile target** `test-fs-roundtrip` becomes the prevention
mechanism. Every future FS change must keep this green. Add to:

- README's quick-test section (if exists)
- CLAUDE.md §6 rule: "FS writes require roundtrip test"
- (optional) CI workflow (P4 decision gate)

---

## 7. Decision Gates (Rule 6)

**After P3.2/P3.3 complete**, commit
`docs/V30_TRACK4_P3_DECISION.md` with:

- Does ext2 roundtrip work on first try? (Y/N)
- Does FAT32 roundtrip work on first try? (Y/N)
- If N: which invariant failed + proposed fix path
- Continue to P4 / quarantine / defer

This is the mechanical file that blocks P4 from merging before
P3 is actually green. Analogous to V29.P3.P6 decision file.

---

## 8. Multi-repo state check (Rule 8) — pre-execution

Before starting P1:

```
git -C "~/Documents/Fajar Lang"   status -sb  # expect clean
git -C "~/Documents/fajaros-x86"  status -sb  # expect clean
git -C "~/Documents/fajarquant"   status -sb  # expect clean
git -C "~/Documents/fajaros-x86"  rev-list --count origin/main..main  # expect 0
```

---

## 9. Self-check (§6.8 Plan Hygiene 8/8)

- [x] Pre-flight audit (P0) exists for the Phase? — this doc IS P0
- [x] Every task has a runnable verification command?
- [x] At least one prevention mechanism added? — `test-fs-roundtrip`
- [x] Agent-produced numbers cross-checked with Bash? — grep for
      fs files already run
- [x] Effort variance tagged in commit message convention? — planned
- [x] Decisions are committed files, not prose paragraphs? —
      P3 decision file specified in §7
- [x] Internal doc fixes audited for public-artifact drift? —
      CHANGELOG + GitHub Release scheduled in P5
- [x] Multi-repo state check run before starting work? — scripted
      in §8

**8/8 = ship.**

---

## 10. Execution Order + Dependencies

```
P0 (this doc, commit) → P1 → P2 → P3 → P4 → P5
                               ↓
                          P3_DECISION.md
                               ↓ (gate)
                               P4
```

No parallelism within subphases. P1+P2 could arguably run together
(image-building + Makefile target are closely coupled) but splitting
keeps commits reviewable.

---

## 11. Success Criteria

- `make test-fs-roundtrip` runs end-to-end in <5 min on KVM dev host
- Exit 0 with 4 PASS lines on clean HEAD
- Exit non-0 with actionable message if ext2/FAT32 write regressed
- 3 new kernel tests pass → total kernel_tests.fj count goes 35→38
- CHANGELOG v3.7.0 published, GitHub Release tag live
- MEMORY.md + CLAUDE.md §3 updated

---

*Plan status: DRAFT, ready for execution. Next phase (P1) is the
 first implementation step — awaiting authorization.*
