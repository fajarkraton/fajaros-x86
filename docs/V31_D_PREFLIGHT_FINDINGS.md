# V31 Track D Pre-flight — ext2 Write-Path Bug

> **Date:** 2026-04-21 | **Rule:** §6.8 R1 (pre-flight before fix) + §6.10 (FS roundtrip coverage gate from V30.T4) | **Surfaced by:** V30.T4 disk harness — `ext2_create` returns -1 on freshly-mkfs'd disk

## 0. Summary

Root cause located. `cmd_mkfs_ext2()` in `fs/ext2_super.fj:147-195`
initializes the root inode's `mode` + `links` fields but **never
allocates a data block for the root directory and never writes
`BLOCK0` into the root inode**. As a result, `ext2_create()` for the
first file in the root directory returns -1 at the dblock-zero guard
on `fs/ext2_ops.fj:99`.

This is the latent bug V30.T4 surfaced. Fix scope: ~10 lines added to
`cmd_mkfs_ext2` to allocate + zero + persist the root directory's
data block.

## 1. Failure path (line-by-line)

`ext2_create(dir_inode=EXT2_ROOT_INODE, ...)` calls (per
`fs/ext2_ops.fj:80-111`):

```
let new_inode = ext2_inode_alloc()        // ✓ succeeds (bitmap not exhausted)
let new_block = ext2_block_alloc()        // ✓ succeeds
let iaddr = ext2_read_inode(new_inode)    // ✓ succeeds
... (writes mode, size, links, block0 to new inode buffer)
blk_write(... isector ...)                // ✓ persists new inode

let diaddr = ext2_read_inode(dir_inode)   // ✓ reads root inode buffer
let dblock =                              //  ↳ ROOT INODE BLOCK0 = 0
    volatile_read_u8(diaddr + EXT2_INO_OFF_BLOCK0) +
    volatile_read_u8(diaddr + EXT2_INO_OFF_BLOCK0 + 1) * 256
if dblock == 0 { return -1 }              // ❌ returns -1 here
```

Why is root inode's BLOCK0 = 0? Because
`cmd_mkfs_ext2:172-178` only writes mode + links:

```fajar
// Create root inode (inode 2)
i = 0
while i < 512 { volatile_write_u8(EXT2_BUF + i, 0); i = i + 1 }
volatile_write_u8(EXT2_BUF + EXT2_INO_OFF_MODE, 0xED)        // ← mode set
volatile_write_u8(EXT2_BUF + EXT2_INO_OFF_MODE + 1, 0x41)
volatile_write_u8(EXT2_BUF + EXT2_INO_OFF_LINKS, 2)           // ← links=2
blk_write(blk_dev, EXT2_INODE_TABLE_SECTOR + 1, 1, EXT2_BUF) // ← persist (no BLOCK0)
```

No `BLOCK0` field is touched. The 512-byte memset on line 174 leaves
it at 0.

## 2. Required fix scope (~10 lines)

After the root inode write at line 178, `cmd_mkfs_ext2` must:

```fajar
// Allocate + zero a data block for root directory's dirents
let root_data_block = ext2_block_alloc()  // marks bitmap, returns block #
if root_data_block < 0 {
    cprintln("ext2 mkfs failed: block alloc for root dir", RED_ON_BLACK)
    return
}

// Zero the new block (no entries yet)
i = 0
while i < EXT2_BLOCK_SIZE { volatile_write_u8(EXT2_DIR_BUF + i, 0); i = i + 1 }
ext2_write_block(root_data_block, EXT2_DIR_BUF)

// Update root inode: write BLOCK0 (re-read inode 2, set BLOCK0, persist)
let root_iaddr = ext2_read_inode(EXT2_ROOT_INODE)
volatile_write_u8(root_iaddr + EXT2_INO_OFF_BLOCK0, root_data_block & 0xFF)
volatile_write_u8(root_iaddr + EXT2_INO_OFF_BLOCK0 + 1, (root_data_block >> 8) & 0xFF)
let root_isector = EXT2_INODE_TABLE_SECTOR + ((EXT2_ROOT_INODE - 1) * EXT2_INODE_SIZE) / 512
blk_write(volatile_read_u64(EXT2_STATE + 8), root_isector, 1, EXT2_BUF)
```

Total ~12 lines (paraphrased — exact LOC depends on whether helpers
exist for "set u16 little-endian"). Reuses existing `ext2_block_alloc`,
`ext2_write_block`, `ext2_read_inode` — no new APIs needed.

## 3. Verification gate (per §6.10 + V30.T4 harness)

Existing `make test-fs-roundtrip` already invokes `ext2-mkfs +
ext2-mount + ext2-ls`. After the fix, the harness should also:

1. Add `ext2-create README.TXT` (or programmatic equivalent) to the
   harness boot script
2. Add `ext2-ls` invariant: README.TXT appears in directory listing
3. Add invariant check: serial log does NOT contain `ext2 create
   failed (-1)` marker

These additions land in the same fix commit per §6.8 R3 (prevention
layer ships with the fix).

## 4. Effort estimate

- Fix: ~30 minutes (10 lines + alignment with existing patterns)
- Test harness extension: ~30 minutes (add ext2-create + 2 invariants)
- Manual verification with QEMU: ~15 minutes (boot, mkfs, create, ls)
- Documentation update: ~15 minutes (CHANGELOG entry + decision doc)

**Total: ~1.5h** (vs the original V30.T4 plan §D estimate of 4-6h —
under because root cause is now precisely localised).

## 5. Risk register

| Risk | Mitigation |
|---|---|
| `ext2_block_alloc` returns the same block as previously allocated | Track which block is allocated to root explicitly; first call after fresh mkfs always returns block 0 (which is reserved for the superblock area — this might mask bugs). Verify allocator skips reserved blocks. |
| Existing on-disk ext2 images written by older mkfs lose compatibility | None — the fix only changes how NEW mkfs operations format disks. Existing images keep working (they were already broken for ext2_create, no regression possible). |
| Block 0 of an in-progress write fails partway, leaving inconsistent state | Acceptable for a research OS; document in §6.10 update. |

## 6. Decision: defer to dedicated session

**Recommendation: do not bundle this fix with Phase D work.** Track D
is in `fajaros-x86`; touching kernel filesystem code mid-Phase-D risks
distracting from C.P4-C.P7 momentum. The fix is small (~1.5h) and
self-contained — schedule as its own short session after Phase D
Mini/Base gates close.

This findings doc commits the audit so that next session starts
with the root cause localised, not with re-deriving it.

## 7. Unblocks

- A future short session (≈1.5h budget) can implement + verify with
  near-zero re-discovery cost
- §6.10 self-check item: "Surface pre-existing bugs as NOTE not hidden"
  is already satisfied by V30.T4's harness — the bug WAS surfaced
  honestly; this doc closes the loop on root cause
