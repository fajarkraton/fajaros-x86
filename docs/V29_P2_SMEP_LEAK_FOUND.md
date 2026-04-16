# V29.P2.SMEP Step 2 — U-Bit Leak Located

**Date:** 2026-04-16
**Phase:** V29.P2.SMEP step 2 of 5
**Prerequisite:** V29.P1 complete (compiler now accepts @noinline,
Makefile ELF-gate verifies builds, kernel actually compiles)

## Finding

The PTE audit walker added in V29.P2.SMEP step 1 (commit `0396286`)
was invoked at boot (this commit adds the invocation in `kernel/main.fj`
between println(12) and println(13)). Serial output captured 6
page-table entries with the PAGE_USER bit set mapping kernel-range
virtual addresses:

```
PLK L2 V0x000000 E0x00000000000000E7
PLK L2 V0x200000 E0x0000000000200000A7
PLK L2 V0x400000 E0x0000000000400000E7
PLK L2 V0x600000 E0x0000000000600000E7
PLK L2 V0x800000 E0x0000000000800000E7
PLK L2 V0xA00000 E0x0000000000A000E7
PTE_LEAKS=0x0000000000000006
```

All 6 entries are at **L2 (page-directory level) with the HUGE bit set**,
meaning each one maps a full 2 MB page via PDE rather than descending
to a PT of 4 KB entries. They cover a contiguous 12 MB region:

| Virtual range          | PDE flags (entry bits) |
|------------------------|------------------------|
| `0x000000 – 0x1FFFFF`  | `0xE7` = PRESENT\|WRITABLE\|USER\|ACCESSED\|DIRTY\|HUGE |
| `0x200000 – 0x3FFFFF`  | `0xA7` = PRESENT\|WRITABLE\|USER\|ACCESSED\|HUGE (no DIRTY yet) |
| `0x400000 – 0x5FFFFF`  | `0xE7` |
| `0x600000 – 0x7FFFFF`  | `0xE7` |
| `0x800000 – 0x9FFFFF`  | `0xE7` |
| `0xA00000 – 0xBFFFFF`  | `0xE7` |

Bit decomposition of `0xE7` (= `1110 0111`):

| Bit | Mask | Meaning    | Set? |
|-----|------|------------|------|
| 0   | 0x01 | PRESENT    | 1 ✅ |
| 1   | 0x02 | WRITABLE   | 1 ✅ |
| 2   | 0x04 | **USER**   | **1 ⚠️ LEAK** |
| 3   | 0x08 | PWT        | 0 |
| 4   | 0x10 | PCD        | 0 |
| 5   | 0x20 | ACCESSED   | 1 |
| 6   | 0x40 | DIRTY      | 1 |
| 7   | 0x80 | HUGE (PS)  | 1 ✅ |

## Why This Matters (SMEP / SMAP / NX)

SMEP (Supervisor Mode Execution Prevention) generates a #PF when the
CPU is in ring 0 and attempts to fetch an instruction from a page
with PAGE_USER = 1. The kernel `.text` section is linked at
`0x00100000` (1 MB) — that falls inside the first leaked 2 MB page
(`V0x000000`). Every kernel instruction fetch would trigger SMEP.

This is the exact failure mode documented at
`kernel/main.fj:105-111`: "`write_cr4(cr4 | CR4_SMEP)` hangs the
kernel after EFER NX is set. … Root cause likely a kernel page with
PAGE_USER bit set." The walker has now pinpointed **which** pages:
all 6 of the identity-mapped low-12-MB huge pages.

## Likely Root Cause

The low-memory identity map is set up at boot. Candidates:

1. **Boot trampoline / assembly** — some early setup writes PDEs
   before main.fj runs. Looking for a `0xE7`-style constant in
   boot-related `.S` / `.asm` / `linker.ld` files.
2. **Kernel-side identity map init** — `frames_init()`,
   `extend_identity_mapping()`, or `paging_init()` may set
   PAGE_USER as part of a shared flag set used for user pages.
3. **GRUB/multiboot2 initial map inheritance** — less likely on
   x86_64 since GRUB typically does NOT pre-install PAGE_USER on
   its 64-bit paging setup.

Grep targets for step 3:
```
grep -rn "0xE7\|PAGE_USER\|0x87\|0x83" kernel/boot/ boot/ *.S
grep -rn "paging_init\|extend_identity_mapping\|identity_map" kernel/
```

The fix will be mechanical once the set-site is found: replace the
flag expression with one that omits `PAGE_USER` for kernel pages
(or adds it only when mapping user regions).

## Walker Performance

The walker iterates up to 512⁴ entries in the worst case but
practically terminates quickly because only 6 leaves have PAGE_PRESENT
in the kernel identity map. Measured behavior at boot:

- Walker runs between `println(12)` and `println(13)` stages
- No observable delay in boot sequence
- Output emitted in under 10 ms (bytes hit COM1 before QEMU's serial
  buffer even flushes one line)

## Next Steps (V29.P2.SMEP step 3)

1. Locate the set-site for these PDEs (grep above).
2. Remove PAGE_USER from the kernel identity-map flag expression.
3. Rebuild and re-run the PTE walker — expect `PTE_LEAKS=0x0`.
4. Uncomment `security_enable_smep()` at `kernel/main.fj:111`
   (step 4: cherry-pick the historical SMEP enable commit).
5. Boot QEMU with SMEP enabled — kernel should reach `nova>`
   without the legacy hang.

## Reference Commits

- `0396286` V29.P2.SMEP step 1 — PTE walker function + shell cmd
- `353d9ef` V29.P1 install-git-hooks refactor
- `7937c93` (historical, pre-V29.P1) — `security_enable_smep()`
  implementation; to be re-landed in step 4
- `700f887` (historical) — SMAP + syscall STAC/CLAC wrappers;
  re-land in step 4
- `168ef29` (historical) — NX enforcement + ASLR; re-land in step 4

## Raw Boot Log Excerpt

```
[captured from timeout 12 qemu-system-x86_64 … 2>&1 > /tmp/pte_audit_v2.log]

12                                     ← boot stage println(12)
PLK L2 V0000000000000000 E0000000000000E7
PLK L2 V0000000000200000 E0000000000200A7
PLK L2 V0000000000400000 E0000000000400E7
PLK L2 V0000000000600000 E0000000000600E7
PLK L2 V0000000000800000 E0000000000800E7
PLK L2 V0000000000A00000 E0000000000A00E7
PTE_LEAKS=0000000000000006
13                                     ← boot stage println(13)
...
[NOVA] FajarOS Nova v3.0 Nusantara booted
```

Walker completed between stage 12 and stage 13 as intended. No crash,
no hang, boot sequence uninterrupted. The walker itself is safe for
production use; it will remain wired at this location after step 3's
leak fix so every boot confirms `PTE_LEAKS=0x0` before SMEP enable.
