# V30.DISK — ext2/FAT32 Write Test Disk Harness

**Date drafted:** 2026-04-16
**Entry doc:** `V29.P2.VFS_TESTS` commit message — "ext2/FAT32 tests need disk-backed mount which isn't set up at boot-test time"
**Track:** V30 Track 4 (per `Fajar Lang/docs/V30_NEXT_SESSION_AGENDA.md`)
**Goal:** build a test harness that creates pre-populated disk images, mounts them in QEMU, runs ext2/FAT32 write tests as part of the regression gate. Close the V29.P2.VFS_TESTS scope gap (RamFS covered, ext2+FAT32 not yet).

---

## 1. Problem Statement

### 1.1 Established facts

- V29.P2 (commit `d19262a`) added 3 VFS tests: `test_ramfs_roundtrip`,
  `test_vfs_create_read`, `test_vfs_list_entries`. All 3 pass.
- ext2 + FAT32 VFS drivers exist in kernel but **have no write-test
  coverage** because the test suite runs at `test-smep-regression`
  time with a default QEMU command that has no attached disk.
- Kernel has `run-nvme` target that attaches a `disk.img` — but the
  image is blank (created on-the-fly with `qemu-img create`), no
  filesystem, no pre-populated content.
- Makefile pins:
  - `QEMU_NVME := -boot order=d -drive file=disk.img,if=none,id=nvme0,format=raw -device nvme,serial=fajaros,drive=nvme0` (line 207)
  - `run-nvme: build` (line 317) — creates blank 64 MB image
  - `run-full-llvm` uses same disk.img (lines 355, 396)

### 1.2 Scope gap

`test-security-triple-regression` (V29.P3.P6.P4) covers SMEP+SMAP+NX
invariants with NO attached disk. ext2/FAT32 write paths untested →
regressions can slip in silently.

### 1.3 Three hypotheses (not applicable — this is construction, not investigation)

Track 4 is tooling work, not bug diagnosis. Instead of hypothesis
tree, the plan enumerates **design alternatives** with pros/cons
(§3).

### 1.4 Prevention Layer Gap (Rule 3)

Current prevention: none for ext2 / FAT32 write paths. After V30.DISK:
- Pre-populated test disk images built from manifest
- New `make test-fs-roundtrip` target (or extended
  `test-security-triple-regression`) boot-mounts the disk and greps
  for roundtrip markers
- Kernel tests `test_ext2_write_roundtrip` + `test_fat32_write_roundtrip` +
  `test_disk_mount_unmount`

---

## 2. Scope (Cross-Repo)

### 2.1 FajarOS x86 (primary — all work here)

| File | Anticipated change |
|------|---------|
| `scripts/build_test_disks.py` (NEW) | Python driver that emits ext2 + FAT32 + RamFS images with known content per manifest |
| `scripts/test_disks.manifest.yml` (NEW) | declarative spec: N files with content + expected-checksum per filesystem |
| `build/test-disks/` (NEW, gitignored) | output dir for generated images |
| `Makefile` | new `build-test-disks`, `test-fs-roundtrip`, optionally extend `test-security-triple-regression` |
| `kernel/fs/ext2.fj` (or equivalent) | may need bug fixes surfaced by roundtrip test (quarantined to P4) |
| `kernel/fs/fat32.fj` (or equivalent) | ditto |
| `tests/kernel_tests.fj` | add 3 new test cases: `test_ext2_write_roundtrip`, `test_fat32_write_roundtrip`, `test_disk_mount_unmount` |
| `.gitignore` | add `build/test-disks/` line |
| `docs/V30_DISK_HARNESS_FINDINGS.md` (NEW) | P0-P5 findings narrative |
| `CHANGELOG.md` | v3.6.0 or v3.5.1 narrative entry (TBD after P5 success) |

### 2.2 Fajar Lang

No changes expected. Pure FajarOS tooling.

### 2.3 FajarQuant

Not touched.

### 2.4 Documentation (memory/claude-context)

Rule 7 closure:
- `CLAUDE.md` §3 Version History row (V30.DISK)
- `MEMORY.md` FajarOS status line update (add "ext2+FAT32 roundtrip tested")
- Optional GitHub Release tag if the patch version warrants

---

## 3. Design Alternatives

Enumerate for Rule 6 decision gate before P1 implementation:

| Option | Approach | Pros | Cons | Fit |
|--------|---------|------|------|-----|
| **A. Python mkfs driver** | `scripts/build_test_disks.py` uses `mkfs.ext2` / `mkfs.vfat` via subprocess + `mount`/`cp` via `sudo losetup` or `guestfish` | Standard tools, full FS feature coverage, deterministic | Needs `sudo` OR `libguestfs-tools`, CI complexity | ⭐⭐⭐ PRIMARY |
| **B. Pre-built images checked in** | Commit `build/test-disks/*.img` to repo | Zero build-time deps, reproducible, fast | Binary blobs in git (bad), hard to audit, manifest drift | ⭐ fallback |
| **C. Pure-Python FS writer (no mount)** | Use `pytsk3` / `pyfat32` / custom impl to write filesystem structures without kernel mount | No sudo, no external tools, pure Python | Limited FS feature coverage, may not exercise same code paths kernel takes | ⭐⭐ secondary |
| **D. Use kernel itself to populate** | Boot kernel with blank disk, have kernel write initial content, snapshot the image | Self-hosting, lowest trust boundary | Chicken-and-egg if ext2 writer is buggy; can't test the writer by using the writer | ❌ |

**Chosen primary:** Option A with Option C as fallback if `sudo`/`guestfish` not available on user's machine. Decision committed in P2 DECISION.md after P0 environment audit.

---

## 4. Skills & Knowledge Required

| Area | Depth | Reference |
|------|-------|-----------|
| **ext2 on-disk format** | Medium — superblock, group descriptor, inode table, directory entry | The ext2 filesystem manual (osdev wiki + Linux kernel `fs/ext2/`) |
| **FAT32 on-disk format** | Medium — BPB, FAT table, cluster chain, directory entry | Microsoft FAT32 specification |
| **QEMU NVMe attach** | Light — existing `$(QEMU_NVME)` pattern works | `Makefile:207` |
| **libguestfs / losetup for FS construction** | Medium (for Option A) | `guestfish` manpage |
| **Python subprocess with sudo** | Light | Standard Python patterns |
| **FajarOS VFS API** | Medium — `vfs_mount`, `vfs_open`, `vfs_write`, `vfs_close`, error codes | `kernel/fs/vfs.fj` + V29.P2 VFS test examples |

**Skill gaps flagged:** if user's machine lacks libguestfs-tools, P0 will detect and escalate to Option C (pure-Python FS writer). Plan handles both paths without replanning.

**Online research needed:** minimal — ext2/FAT32 formats are well-documented. 2-3 references sufficient:
1. OSDev wiki "Ext2" + "FAT32"
2. Linux kernel `fs/ext2/super.c` (reference for magic numbers, layout)
3. Microsoft FAT32 spec (authoritative)

---

## 5. Phased Approach

### Phase V30.DISK.P0 — Pre-Flight Audit

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P0.1 | Check user env for `mkfs.ext2`, `mkfs.vfat`, `sudo`, `guestfish` | shell commands succeed or clear escalation to Option C | 0.05h |
| P0.2 | Enumerate existing ext2/FAT32 driver code in kernel | `grep -l 'ext2\|fat32' kernel/fs/*.fj`; list output in findings | 0.05h |
| P0.3 | Read `run-nvme` + `$(QEMU_NVME)` integration | note pin in findings § | 0.05h |
| P0.4 | Run existing VFS tests to baseline | `make test-security-triple-regression` exit 0 | 0.1h |
| P0.5 | Multi-repo state check | `git status -sb` × 3 = clean | 0.02h |
| P0.6 | Commit `docs/V30_DISK_HARNESS_FINDINGS.md` P0 section | file committed | 0.1h |

**Phase P0 total: 0.37h** (+25% budget: 0.46h)
**Gate:** disk build environment known + existing tests passing + design option chosen (A vs C)

### Phase V30.DISK.P1 — Disk Image Builder

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P1.1 | Design manifest schema (`scripts/test_disks.manifest.yml`): filesystems, file paths, content, expected-checksum | schema documented; example manifest committed | 0.15h |
| P1.2 | Implement `scripts/build_test_disks.py` per chosen option (A or C) | script produces `build/test-disks/ext2.img` + `fat32.img` with manifest content; `file -s` identifies as ext2/fat32 | 0.7h |
| P1.3 | Add `build-test-disks` Makefile target | `make build-test-disks` emits 2 images; re-invocation is idempotent | 0.1h |
| P1.4 | Add `build/test-disks/` to `.gitignore` | `git status` clean after builder run | 0.02h |

**Phase P1 total: 0.97h** (+25% budget: 1.21h)
**Gate:** ext2 + FAT32 images built from manifest, contents readable by `mount -o loop` (Option A) or `pytsk3` extract (Option C)

### Phase V30.DISK.P2 — Design Decision + Kernel Test Stubs (Decision Gate)

Mechanical Rule 6 gate. Commit `docs/V30_DISK_HARNESS_DECISION.md`:
- Chose Option A or Option C (per P0 env detection)
- Kernel test mount semantics: one-disk-two-partitions OR two-disks-two-filesystems
- File layout convention (path + content) used by both builder and kernel tests

Then stub kernel test cases:

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P2.1 | Commit DECISION.md | file in git | 0.05h |
| P2.2 | Add `test_ext2_write_roundtrip` stub that mounts + reads known file + writes + unmounts + verifies | test runs (may fail first iteration) | 0.15h |
| P2.3 | Add `test_fat32_write_roundtrip` stub | test runs | 0.15h |
| P2.4 | Add `test_disk_mount_unmount` stub for mount+unmount correctness | test runs | 0.1h |

**Phase P2 total: 0.45h** (+25% budget: 0.56h)

### Phase V30.DISK.P3 — Kernel-side Mount Wiring

Current `test-security-triple-regression` runs QEMU without disk.
Options:
- Extend `test-security-triple-regression` with `QEMU_NVME` + `build-test-disks` prerequisite
- Create new `test-fs-roundtrip` target that stacks on top

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P3.1 | Decide target split (extend vs new target); document in DECISION update | commit | 0.05h |
| P3.2 | Implement chosen Makefile target; attach disk image | `make test-fs-roundtrip` boots kernel with disk; kernel test suite output captured | 0.3h |
| P3.3 | Wire kernel test execution via existing `test-all` shell command pattern (V29.P2 pattern) | test output visible in log with PASS/FAIL markers per test | 0.2h |
| P3.4 | First iteration: debug any ext2/FAT32 driver bugs surfaced by real roundtrip (quarantined — may spill to P4) | tests pass or known-failures documented | 0.5h (worst case) |

**Phase P3 total: 1.05h** (+30% high-uncertainty budget: 1.37h — driver bugs unpredictable)
**Gate:** `make test-fs-roundtrip` exits 0 with all 3 new tests PASS

### Phase V30.DISK.P4 — Regression + Prevention

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P4.1 | Rename `test-security-triple-regression` to cover FS or add coordinated `test-full-regression` target | new target runs all prior invariants + 3 new FS tests | 0.15h |
| P4.2 | Add `ALL TESTS PASSED` gate-style summary expected count bump (32 → 35 with 3 new tests) | gate assertion updated | 0.05h |
| P4.3 | CHANGELOG v3.5.1 or v3.6.0 entry | committed | 0.1h |
| P4.4 | Optional: CI workflow update (if wired elsewhere) | CI picks up new target | 0.1h |

**Phase P4 total: 0.4h** (+25% budget: 0.5h)

### Phase V30.DISK.P5 — Doc Sync (Rule 7)

| # | Task | Verification | Est |
|---|------|--------------|-----|
| P5.1 | CLAUDE.md §3 V30.DISK row | committed in fajar-lang | 0.1h |
| P5.2 | MEMORY.md FajarOS status line update | file edited | 0.05h |
| P5.3 | Optional GitHub Release tag | `gh release create` OR skip | 0.1h |

**Phase P5 total: 0.25h** (+25% budget: 0.31h)

---

## 6. Effort Summary

| Phase | Estimate | Budget |
|-------|---------:|-------:|
| P0 Pre-flight | 0.37h | 0.46h |
| P1 Disk builder | 0.97h | 1.21h |
| P2 Decision + stubs | 0.45h | 0.56h |
| P3 Kernel wiring | 1.05h | 1.37h |
| P4 Regression | 0.4h | 0.5h |
| P5 Doc sync | 0.25h | 0.31h |
| **Total** | **3.49h** | **4.41h** |

**Compare to agenda estimate:** 4-6h. Plan comes in at the lower
end if no driver bugs surface. If P3.4 uncovers real ext2/FAT32
bugs, +1-2h fix budget may be required.

---

## 7. Surprise Budget Tracking (Rule 5)

- Default +25% per phase
- P3 elevated to **+30%** (FS driver bugs surface risk)
- P1 elevated to **+25%** baseline (Option A vs C branch may need rework)
- Commit messages tag variance: `feat(v30-disk-pN): ... [actual Xh, est Yh, ±Z%]`

---

## 8. Prevention Layers (Rule 3)

| Phase | Prevention artifact |
|-------|---------------------|
| P1 | Disk manifest as single source of truth for expected content — any drift between builder and kernel test triggers mismatch |
| P2 | DECISION.md documents chosen option — any future env change (e.g., drop sudo) is mechanically detectable |
| P3 | `test-fs-roundtrip` Makefile target — blocks edits that regress ext2/FAT32 write paths |
| P4 | CHANGELOG narrative entry preserves rationale for future engineers |
| P5 | CLAUDE.md row + MEMORY.md update for session continuity |

---

## 9. Gates & Decisions (Rule 6)

| Gate | Blocks | Mechanism |
|------|--------|-----------|
| P0 gate | P1 launch | FINDINGS P0 section committed |
| P2 decision | P3 wiring | DECISION.md with Option A/C + target split |
| P3 success | P4 rename | `make test-fs-roundtrip` exit 0 |
| P4 regression | P5 doc sync | All 6+ invariants + 3 new tests PASS in one run |

---

## 10. Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| ext2/FAT32 driver bugs surface under real write load | MEDIUM | P3.4 quarantines fix effort; if >2h, escalate to separate plan |
| User's env lacks `sudo`/`guestfish` for Option A | MEDIUM | P0.1 detects; auto-escalates to Option C |
| Option C pure-Python FS writer has limited feature coverage | LOW | Plan limits test file set to what C can reliably generate |
| Disk image format changes across QEMU versions | LOW | Use `raw` format (already pinned in `$(QEMU_NVME)`) |
| Kernel test timeout under disk I/O latency | LOW | P3.3 adds explicit test timeout extension if needed |

---

## 11. Self-Check — Plan Hygiene Rule 6.8 (All 8)

| # | Rule | Status |
|---|------|--------|
| 1 | Pre-flight audit (P0) exists | ✅ §5 Phase P0 with 6 runnable tasks |
| 2 | Every task has runnable verification command | ✅ every row has explicit command or artifact check |
| 3 | Prevention mechanism added per phase | ✅ §8 table; manifest + target + CHANGELOG |
| 4 | Agent-produced numbers cross-checked with Bash | ✅ plan claims verified against actual Makefile lines via grep |
| 5 | Surprise budget tagged per commit | ✅ §7 convention + elevated P1/P3 rates |
| 6 | Decisions are committed files | ✅ §9 table with P2 DECISION.md explicit |
| 7 | Public-facing artifact sync | ✅ §2.4 + P5 phase covers CLAUDE.md + CHANGELOG + optional Release |
| 8 | Multi-repo state check before starting | ✅ P0.5 task explicit |

**8/8 YES.** Plan ready for execution when scheduled.

---

## 12. Online Research Triggers

Minimum 2-3 references (Rule 2 allows reduced count for well-documented formats):

1. **OSDev wiki "Ext2"** — on-disk structure reference
2. **OSDev wiki "FAT32"** — on-disk structure reference
3. **Microsoft FAT32 spec** — authoritative byte layout
4. Stretch: Linux `fs/ext2/super.c` for magic-number validation

---

## 13. Author Acknowledgement

Plan drafted 2026-04-16 by Claude Opus 4.6 following V29.P1/V29.P3
pattern. Compared to the bigger V29.P3 SMAP plan, V30.DISK is scoped
smaller (no multi-hypothesis investigation; this is construction
work). Effort envelope 3.49h–4.41h well within single-session budget.

Pattern borrows from V29.P3:
- Manifest + builder analog to walker + fix-target pattern
- Mechanical DECISION.md gate before kernel wiring
- Rename-then-extend target approach
- Prevention via Makefile target that future edits can't silently bypass

Skill candidate `disk-image-builder` (per agenda §Skills) can be
extracted from `scripts/build_test_disks.py` after P1 lands — if the
script turns out to be reusable beyond V30.DISK, promote to skill in
P5 scope.

---

*V30.DISK Plan — generated 2026-04-16 by Claude Opus 4.6.
Self-check 8/8 ✅. Ready for execution on next scheduled phase.*
