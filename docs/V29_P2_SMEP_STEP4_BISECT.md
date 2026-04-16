# V29.P2.SMEP Step 4 — SMEP Shipped, SMAP+NX Deferred

**Date:** 2026-04-16
**Phase gate:** V29.P2.SMEP step 4 (partial closure; step 5 regression
test covers SMEP only)
**Outcome:** SMEP fully enabled and verified; SMAP + NX stay disabled
pending investigation of a secondary fault path the current walker
does not detect.

## Test Matrix

| Configuration | Boot reaches `nova>`? | PTE_LEAKS | Notes |
|---|---|---|---|
| strip_user + SMEP alone | ✅ YES | 0 | shell works, `version` responds |
| strip_user + SMEP + SMAP | ❌ No, EXC:8 → PANIC:8 | 0 | double fault immediately after write_cr4 |
| strip_user + SMAP alone | ❌ No, EXC:8 → PANIC:8 | 0 | same double fault; SMEP is not the trigger |
| strip_user + SMEP + SMAP + NX | ❌ No, EXC:8 → PANIC:8 | 0 | same failure, not NX-specific |

## Evidence

### Bisect run A — SMEP only (shipped state)

```bash
cd ~/Documents/fajaros-x86
make build-llvm && make iso-llvm
(sleep 5; printf 'version\r'; sleep 1) | timeout 12 \
    qemu-system-x86_64 -cdrom build/fajaros-llvm.iso \
    -chardev stdio,id=ch0,signal=off -serial chardev:ch0 \
    -display none -no-reboot -no-shutdown \
    -enable-kvm -cpu host -m 1G > /tmp/smep_only.log 2>&1

grep -E "PTE_LEAKS|nova>|EXC:|PANIC:" /tmp/smep_only.log
```

Result:
```
PTE_LEAKS=0000000000000000
nova> version
nova>
```

### Bisect run B — SMAP added (shipped-as-deferred state)

Same boot, SMAP uncommented in main.fj:
```
PTE_LEAKS=0000000000000000
101      (marker: post-SMEP)
EXC:8
PANIC:8
```

Fault occurs during or immediately after `write_cr4(cr4 | CR4_SMAP)`
at `kernel/core/security.fj:60`. The boot hangs before `println(102)`
(post-SMAP marker) is reached.

### Bisect run C — SMAP alone (SMEP commented)

Same outcome as run B:
```
PTE_LEAKS=0000000000000000
EXC:8
PANIC:8
```

Confirms SMAP is the independent trigger; SMEP is not part of the
failure.

## Interpretation

PTE_LEAKS=0 reliably, yet SMAP faults. The walker only reports leaks
where `vaddr < KERNEL_VIRT_BOUNDARY (0xC00000)`. Three possible
secondary sources:

1. **Kernel reads memory in the 12–128 MB range** (entries 6–63 kept
   USER bit for ASLR user processes). Any such read post-SMAP would
   #PF. Candidate regions: framebuffer at ~0xE0000000, MMIO ranges,
   process-table data if initialized before the SMAP-enable point.
2. **Walker's USER predicate is incomplete.** It checks only `PAGE_USER`
   at leaf entries. Intermediate PDPT/PML4 entries above kernel range
   might have USER bit set too (walker descends through them without
   checking). That's fine for SMEP (instruction fetch uses final
   translation) but MIGHT affect SMAP semantics on Intel micro-arches
   that check intermediate-level USER bits for data access.
3. **AC flag interaction.** SMAP bypasses require EFLAGS.AC=1. Fajar
   Lang doesn't yet expose a STAC/CLAC intrinsic (see kernel/core/
   security.fj:80-82 comment: "Ideally we'd use STAC/CLAC … but Fajar
   Lang doesn't expose RFLAGS intrinsics yet. CR4 toggle is the
   interim substitute."). It's possible the interim CR4-toggle path
   in `smap_disable`/`smap_enable` was never reached during boot
   because nothing called it yet — but the baseline AC=0 with SMAP=1
   means every USER-page access faults, and something in the boot
   sequence post-SMAP unexpectedly touches USER-flagged memory.

## Step 5 (Regression Test) Scope

Covers the SMEP claim only:

```bash
# Regression: on every build, verify:
#   PTE_LEAKS=0x0                    (strip + walker chain intact)
#   SMEP (CR4.20): ENABLED           (boot log contains this string
#                                     OR a CPU-unsupported warning)
#   nova> prompt reached             (kernel did not hang post-SMEP)
```

SMAP + NX land in a future sub-phase (V29.P2.SMAP or V29.P3) after
the secondary fault path is characterized. That phase's entry gate:

1. Extend PTE walker to also report intermediate PDPT/PML4 USER bits
2. Add a `smap_enable_with_bisect` helper that logs RIP on fault via
   the double-fault handler for attribution
3. Run with the extended walker; decide fix based on data
4. Land as `fix(v29-p3-smap.N)` commits following the same
   step-1-through-5 pattern

## Shipped State Recap

- **strip_user_from_kernel_identity** — permanent kernel boot helper;
  PTE_LEAKS=0x0 invariant for the kernel VM boundary (0–12 MB).
- **pte_walk_find_u_leaks + cmd_pte_audit** — walker permanent,
  runs at boot AND available via `pteaudit` shell command.
- **security_enable_smep** — WIRED at boot, verified active.
- **security_enable_smap / nx_enforce_data_pages** — DEFERRED, code
  intact for future activation; commented in main.fj.

## V28.1 Legacy Claim vs V29.P2 Reality

Memory note prior to V29: "SMEP disabled until U-bit leak found."
V29.P2 step 1–3 located and fixed the U-bit leak. Step 4 shows the
fix was NECESSARY but not SUFFICIENT for SMAP. SMEP re-enable is
the primary original ask; delivered. SMAP+NX become their own
follow-up scope.
