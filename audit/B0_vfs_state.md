# B0.4 — VFS Scaffold Reality Audit

**Audit date:** 2026-04-11
**Audit task:** V26 Phase B0.4 (`fajar-lang/docs/V26_PRODUCTION_PLAN.md` §B0)
**Method:** Count `@kernel fn` declarations in `fs/*.fj`, sample function bodies to distinguish real implementation from scaffold/stub.

## TL;DR

The fajaros-x86 filesystem layer is **substantially real, not a scaffold**:

- **10 files** in `fs/`, **2,114 LOC**, **95 `@kernel fn` definitions**
- ext2 (read + write + lookup + create + unlink + stat) — real
- FAT32 — 752 LOC, 32 functions — real (the largest single FS implementation)
- ramfs — real fixed-address file table, init creates `/`, `/etc`, `/tmp`, `motd`, `hostname`
- vfs.fj — real mount table (8 entries × 64 bytes), path hash, mount registration

**No mass stub gap.** B0.4 baseline assumption ("VFS is mostly scaffold") is **wrong**. There may be specific missing features (e.g., ext2 journal recovery, FAT32 long filenames) but those are scoped enhancements, not "scaffold reality" gaps.

## Per-File Inventory

| File | LOC | `@kernel fn` count | Reality assessment |
|---|---|---|---|
| `fs/directory.fj` | 139 | 6 | Real — directory entry helpers |
| `fs/ext2_indirect.fj` | 49 | 4 | Real — ext2 indirect block helpers (small but complete) |
| `fs/ext2_ops.fj` | 211 | 10 | Real — lookup, create, read_file, write_file, unlink, stat, cmd_ext2ls |
| `fs/ext2_super.fj` | 208 | 8 | Real — superblock + inode + bitmap helpers |
| `fs/fat32.fj` | 752 | 32 | Real — by far the largest, FAT32 read/write/cluster chain |
| `fs/fsck.fj` | 63 | 2 | Real but minimal — `fsck_check_ramfs` + `cmd_fsck` |
| `fs/journal.fj` | 102 | 10 | Real — write-ahead journal primitives |
| `fs/links.fj` | 67 | 2 | Real but minimal — `cmd_ln`, hard-link helper |
| `fs/ramfs.fj` | 223 | 12 | Real — fixed-address file table, init creates default files |
| `fs/vfs.fj` | 300 | 9 | Real — mount table, path hash, dispatch |
| **Total** | **2,114** | **95** | **Real implementation, not scaffold** |

## Spot-Check Samples (Non-Stub Evidence)

### `fs/ramfs.fj` — `ramfs_init()`

Creates `/`, `/etc`, `/tmp`, writes `motd` ("Welcome to FajarOS Nova!"), `hostname` ("fajaros-nova"). Not a stub — has real default content baked in:

```fajar
@kernel fn ramfs_init() {
    volatile_write(FS_BASE, 0)          // file_count = 0
    volatile_write(FS_BASE + 8, FS_DATA) // next_data = 0x710000
    ramfs_create_entry("/", 2)
    ramfs_create_entry("/etc", 2)
    ramfs_create_entry("/tmp", 2)
    ramfs_write_file("motd", "Welcome to FajarOS Nova!", 24)
    ramfs_write_file("hostname", "fajaros-nova", 12)
}
```

### `fs/vfs.fj` — `vfs_path_hash()`

Real djb2 hash function (not a stub returning 0):

```fajar
@kernel fn vfs_path_hash(path_addr: i64) -> i64 {
    let mut hash: i64 = 5381
    let mut i: i64 = 0
    while i < 32 {
        let ch = volatile_read_u8(path_addr + i)
        if ch == 0 { i = 32 }
        else {
            hash = hash * 33 + ch
            i = i + 1
        }
    }
    hash
}
```

### `fs/ext2_ops.fj` — function list

`ext2_dirent_inode`, `ext2_dirent_name_len`, `ext2_dirent_set`, `ext2_lookup`, `ext2_create`, `ext2_read_file`, `ext2_write_file`, `ext2_unlink`, `ext2_vfs_stat`, `cmd_ext2ls`

10 functions covering the standard POSIX-ish ops. The "scaffold reality" suspicion would have predicted maybe 2-3 stub functions returning 0; reality is 10 real ones.

## What Might Still Be Missing (For B3 Scoping)

These are **enhancements**, not scaffold gaps. They are scoped follow-up work, not B0 surprises.

| Possible gap | Impact | Owner |
|---|---|---|
| ext2 journal recovery on dirty unmount | Crash → fsck loops | B3.1 |
| FAT32 long filenames (LFN entries) | Limited to 8.3 names | B3.2 |
| `vfs_unlink` cross-filesystem semantics | Hard links across FS types | B3.3 |
| `proc` and `sysfs` virtual filesystems | No `/proc/cpuinfo` | B3.4 (deferred to V27) |
| Concurrent FS access locking | Race conditions under SMP | B3.5 (depends on B4 SMEP audit) |

These should be characterized in `docs/V26_PRODUCTION_PLAN.md` §B3 but **none of them are blockers** for B1+B2.

## Sign-Off

B0.4 audit completed 2026-04-11. **Filesystem layer is real, not scaffold.** 95 functions across 10 files, 2,114 LOC, with concrete spot-checked evidence (ramfs init, vfs hash, ext2 ops list). **B3 effort estimate stands** (was 14 h base + 25% surprise budget = 17.5 h); no upward revision needed.

**Verification command for re-run:**
```bash
cd ~/Documents/fajaros-x86 && wc -l fs/*.fj && grep -c "@kernel fn" fs/*.fj
```
