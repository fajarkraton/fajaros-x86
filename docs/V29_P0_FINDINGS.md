# V29.P0 Pre-Flight Audit Findings — FajarOS P2 Hardening

**Date:** 2026-04-16
**Phase:** V29 "Hardening" Pre-Flight (Plan Hygiene Rule 1)
**Baseline commit:** `5fa6724` (before V28.5 CHANGELOG backfill) → current `de1c43d`
**Tests baseline:** 32 kernel tests in `tests/kernel_tests.fj` (+ 12 ARM64 harness)

## Purpose

Verify actual state of the 3 items flagged as "FajarOS P2 Hardening" in the
post-V28.5 re-audit (2026-04-16). Goal: pick the right first sub-phase to
start, scoped to a single session (~4-12h), backed by runnable verification
commands.

## Item 1: SMEP (Supervisor Mode Execution Prevention) — **REAL WORK**

**State:** DISABLED at `kernel/main.fj:105-113`. Comment block (lines 105-112)
explicitly documents:
- `write_cr4(cr4 | CR4_SMEP)` line that hangs the kernel after EFER NX set
- "P2 security" tag confirming this is the tracked P2 item
- Root cause: "kernel page with PAGE_USER bit set" (U-bit leak)
- SMAP + NX also skipped until SMEP resolves

**Supporting infrastructure present:**
- CPUID detection in `kernel/core/security.fj:24-49` (leaf 7 EBX bit 7)
- CR4 bit masks defined
- CR4_SMEP constant defined
- Test infrastructure ready (security.fj gates)

**Infrastructure MISSING:**
- No page-table audit tool (no `dump_pde`, `walk_pde`, or PTE scanner)
- 10+ PAGE_USER uses across fork/exec/shm — no systematic validator
- No way to locate the rogue U-bit before enabling SMEP

**Historical commits reachable (do NOT cherry-pick blindly):**
```
7937c93 feat(v26-b4.2): enable SMEP at boot — kernel execution prevention
700f887 feat(v26-b4.4): enable SMAP + syscall SMAP disable/enable wrapper
168ef29 feat(v26-b4.5): wire NX enforcement at boot + ASLR already implemented
```
All three hung at stage 12 when enabled together. They're preserved in git
so the SMEP/SMAP/NX enable logic isn't lost — only the U-bit leak fix is
needed before they can re-land.

**Real work needed for V29.P2.SMEP:**
1. Write a page-table walker that scans all PML4 → PDPT → PD → PT entries
   at boot, printing any kernel-range address (>0xC0000000) with PAGE_USER
   set. (~2h)
2. Run walker at boot, identify the leaking page. (~0.5h)
3. Fix the leak — likely a shared-page mapping that incorrectly sets U-bit,
   or a leftover from user-mode setup. (~1-3h, depends on root cause)
4. Cherry-pick `7937c93` + `700f887` + `168ef29` with verification that
   kernel reaches `nova>` and security tests pass. (~1h)
5. Add regression test that fails if U-bit ever leaks into kernel page
   again (static or dynamic check). (~1h)

**Estimated:** 5-7h session-sized. Surprise budget +25% = 6-9h.

## Item 2: VFS write (ext2/FAT32) — **CODE DONE, TESTS MISSING**

Pre-flight caught an **earlier audit error**: the prior re-audit said
"ext2/FAT32 scaffold untested". Cross-check shows both are actually
implemented end-to-end:

**ext2 write — SHIPPED (V26 Phase B per CHANGELOG v3.1.0):**
- `fs/ext2_super.fj:138` — `ext2_write_block()`
- `fs/ext2_ops.fj:80` — `ext2_create(dir_inode, name, name_len, mode)`
- `fs/ext2_ops.fj:132` — `ext2_write_file(inode_num, data, data_len)`
- `fs/ext2_ops.fj:246-255` — `cmd_ext2write` shell command (full integration)

**FAT32 write — SHIPPED (V26 Phase B per CHANGELOG v3.1.0):**
- `fs/fat32.fj:286` — `fat32_write_fat_entry()`
- `fs/fat32.fj:408` — `fat32_create_dir_entry()`
- `fs/fat32.fj:458` — `fat32_create_file(name, data, data_len)`
- `fs/fat32.fj:542` — `cmd_fatwrite` shell command
- `shell/commands.fj:3416` — dispatcher entry (`buf_eq4(102, 97, 116, 119)` = "fatw")

**RamFS write** — also shipped: `fs/ramfs.fj` has `ramfs_write_file()`.

**Real gap:** kernel_tests.fj has NO `test_ext2_write`, `test_fat32_write`,
or `test_ramfs_write` — all 3 write paths are userspace-tested via `ext2write`
/ `fatwrite` shell commands but have no automated kernel regression coverage.

**Real work needed for V29.P2.VFS_TESTS:**
1. Add `test_ext2_write_roundtrip()` to kernel_tests.fj — create, write,
   read, verify content. (~1h)
2. Add `test_fat32_write_roundtrip()` — same pattern. (~1h)
3. Add `test_ramfs_write_trunc()` — test O_TRUNC + append semantics. (~0.5h)
4. Add `test_vfs_mount_switching()` — cover the mount-table path. (~1h)
5. Update `TEST_TOTAL` constant + verify tests pass via `make test-serial`.
   (~0.5h)

**Estimated:** 3-4h session-sized. Surprise budget +25% = 4-5h.

## Item 3: CPUID Runtime Detection — **ALREADY DONE**

Pre-flight caught a **second audit error**: this item was tagged as "P2 TODO"
but actually both detection and reporting are production.

**Shipped state:**
- `kernel/hw/cpuid.fj:1-100` — full CPUID implementation (leaf 1, 7, 0x80000001)
- Feature store at `0xA30000` — all 15+ features detected at boot
- Detected: RDRAND, AES-NI, AVX2, POPCNT, SSE4.2, FMA, NX, RDTSCP, BMI2, AVX-512
- Shell command `cmd_cpufeatures()` reports all features (per V26 Phase B)
- SMEP/SMAP already properly CPUID-gated in security.fj
- NX is MSR-gated (EFER.NXE), which is correct

**What remains (P3, not P2):**
- **Hot-path fallbacks for non-AVX2 CPUs.** Kernel assumes AVX2/AES available
  on compute paths (`km_vecmat_packed_v8`, `kmatrix.fj` AVX2 kernels). No
  scalar fallback exists. This is a **portability** concern, not a security
  hardening concern. Relevant only if FajarOS targets pre-Haswell / Zen-1
  hardware — not a current deployment goal.

**No V29 work needed for CPUID.** Re-classify from "P2" to "P3 deferred".

## Summary — Real V29.P2 Phase Scope

| Item | Previous Claim | Actual State | Real V29 Work | Est |
|------|---------------|--------------|----------------|-----|
| SMEP | "P2, ~16h, Low risk" | **BLOCKER** — U-bit leak, no PTE audit tool | PTE walker + leak fix + regression test | **5-7h** |
| VFS write | "P2, ~12h, Low risk" | **DONE** (ext2 + FAT32 + RamFS shipped V26 B) | Tests only — 4 kernel regression tests | **3-4h** |
| CPUID | "P3, ~6h, Medium risk" | **DONE** (leaf 1/7, all features detected) | Hot-path fallbacks (P3, deferred) | N/A |

**Revised V29.P2 total:** 8-11h across 2 sub-phases (was 34h across 3).
**Phase delivers:** Full SMEP+SMAP+NX security triple re-enabled, VFS write
tests locked in regression suite.

## Recommendation

**Start with V29.P2.SMEP** (sub-phase 1 of 2):

1. Highest user-visible impact — unblocks SMEP+SMAP+NX security triple.
2. Session-sized — 5-7h discovery + fix + cherry-pick + test.
3. Has a real blocker to solve (U-bit leak) — not documentation churn.
4. Prevention layer natural: PTE walker becomes permanent kernel tool,
   regression test prevents re-introduction (Plan Hygiene Rule 3).

After SMEP: V29.P2.VFS_TESTS (sub-phase 2 of 2, 3-4h) as the closure.

## Verification Commands (Rule 2)

```bash
# Verify this audit's claims hold at time of V29.P2 start
cd ~/Documents/fajaros-x86

# SMEP disabled state
grep -n "DISABLED.*SMEP\|CR4_SMEP.*hangs" kernel/main.fj               # → 2 lines @ 105-106

# VFS write code shipped (not stubs)
grep -c "ext2_create\|ext2_write_file\|fat32_create_file" fs/*.fj      # → 5+ matches

# VFS write tests absent
grep -cE "test_ext2_write|test_fat32_write|test_vfs_write" tests/*.fj  # → 0

# CPUID shipped
grep -c "cpuid_leaf\|cpu_feature" kernel/hw/cpuid.fj                   # → 20+ matches
grep -l "cmd_cpufeatures" services/shell/*.fj shell/*.fj kernel/*.fj   # → 1 file

# Three historical SMEP-hang commits reachable
git log -1 --format=%s 7937c93 700f887 168ef29                         # → 3 lines

# Kernel test count baseline
grep -c "^@kernel fn test_\|^fn test_\|^pub fn test_" tests/kernel_tests.fj  # → 32
```

## Audit Errors Caught by This Pre-Flight

Two prior audits (the V28.5 post-mortem re-audit and the first sub-agent
pass) reported bugs that weren't actually bugs:

1. **FAT32 write "read-only"** — actually shipped in V26 Phase B
   (commit history + `fs/fat32.fj:458` + `cmd_fatwrite` wired in shell).
2. **CPUID "no runtime detection"** — actually shipped
   (`kernel/hw/cpuid.fj` full implementation, boot-time detection).

Both errors would have inflated V29.P2 scope by ~12h (VFS write impl +
CPUID impl) if accepted without verification. Per Plan Hygiene Rule 4
(multi-agent cross-check mandatory), cross-checking against Bash before
committing saved this scope from drift.

This validates the Rule 4 pattern: agent audits are inputs, not
conclusions.
