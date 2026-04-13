# FajarOS Nova — Physical Memory Map

> **V27 B2.2** — Unified address allocation document.
> Previous collisions: CANARY vs PROC_MEM_STATS, SHM vs IRQ_NOTIFY, FP_RECV vs slot 15.
> This document prevents future collisions by tracking all allocations.
> CI check: `scripts/check_memory_map.sh` verifies completeness.

## Identity-Mapped Region (0x0 — 0x20000000, 512 MB)

### Low Memory (0x0 — 0xFFFFF, first 1 MB)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x00000 | 0x00FFF | 4 KB | Real-mode IVT + BDA | (hardware) |
| 0x6F800 | 0x6FFFF | 2 KB | Shell command buffer | shell/commands.fj |
| 0x6FE00 | 0x6FE07 | 8 B | Current PID | kernel/syscall/dispatch.fj |
| 0x6FF00 | 0x6FF07 | 8 B | Multiboot2 info pointer | kernel/main.fj |
| 0x6FF10 | 0x6FF3F | 48 B | Multiboot2 parsed tags | kernel/main.fj |
| 0x70000 | 0x70FFF | 4 KB | PML4 page table root | kernel/mm/paging.fj |
| 0xB8000 | 0xB8FFF | 4 KB | VGA text-mode buffer | kernel/boot/constants.fj |

### Kernel Code + Data (0x100000 — 0x57FFFF, ~5 MB)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x100000 | 0x11FFFF | 128 KB | Kernel .text (executable) | linker.ld |
| 0x120000 | 0x3FFFFF | ~3 MB | Kernel .data + .bss + heap | linker.ld |
| 0x400000 | 0x57FFFF | ~1.5 MB | Dynamic heap (heap_init) | kernel/mm/heap.fj |

### Frame Allocator + Slab (0x580000 — 0x5FFFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x580000 | 0x58FFFF | 64 KB | Frame bitmap (32768 frames) | kernel/mm/frames.fj |
| 0x590000 | 0x5FFFFF | 448 KB | Slab allocator pools | kernel/mm/slab.fj |

### Kernel Services (0x600000 — 0x6FFFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x640000 | 0x64FFFF | 64 KB | IPC message buffers | kernel/ipc/message.fj |
| 0x650000 | 0x651FFF | 8 KB | Pipe metadata pool | kernel/ipc/pipe.fj |
| 0x652000 | 0x6523FF | 1 KB | Per-CPU state (16 CPUs) | kernel/sched/smp.fj |
| 0x6FBE4 | 0x6FBEF | 12 B | Ctrl+C/Z job control state | kernel/signal/jobs.fj |

### Filesystem (0x700000 — 0x7FFFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x700000 | 0x7000FF | 256 B | RamFS header (count + data ptr) | fs/ramfs.fj |
| 0x700100 | 0x70FFFF | ~64 KB | RamFS directory entries (64 × 128B) | fs/ramfs.fj |
| 0x710000 | 0x7DFFFF | 896 KB | RamFS data area | fs/ramfs.fj |
| 0x7EF000 | 0x7EFFFF | 4 KB | Syscall handler stack | kernel/syscall/entry.fj |

### FAT32 + VFS (0x800000 — 0x83FFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x805000 | 0x8050FF | 256 B | FAT32 mount state | fs/fat32.fj |
| 0x806000 | 0x8060FF | 256 B | VFS mount table | fs/vfs.fj |
| 0x820000 | 0x820FFF | 4 KB | FAT32 read buffer | fs/fat32.fj |
| 0x821000 | 0x821FFF | 4 KB | FAT32 directory buffer | fs/fat32.fj |
| 0x822000 | 0x822FFF | 4 KB | FAT32 name buffer | fs/fat32.fj |
| 0x830000 | 0x831FFF | 8 KB | ext2/FAT write scratch | fs/ext2_ops.fj |

### ELF + Syscall (0x880000 — 0x88FFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x880000 | 0x88FFFF | 64 KB | ELF read buffer | kernel/syscall/elf.fj |
| 0x884000 | 0x8840FF | 256 B | Syscall dispatch table | kernel/syscall/dispatch.fj |

### Process Table + FDs (0x890000 — 0x89FFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x890000 | 0x890FFF | 4 KB | Process table V2 (16 × 256B) | kernel/sched/process.fj |
| 0x894000 | 0x897FFF | 16 KB | FD table (16 procs × 16 FDs × 16B) | kernel/ipc/pipe.fj |
| 0x898000 | 0x89FFFF | 32 KB | Pipe pool (8 pipes × 4KB) | kernel/ipc/pipe.fj |

### IPC Infrastructure (0x8A0000 — 0x8BFFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x8A0000 | 0x8A1FFF | 8 KB | IPC endpoints (16 × 512B) | kernel/ipc/ipc.fj |
| 0x8A8000 | 0x8A87FF | 2 KB | Channel table (32 channels) | kernel/ipc/channel.fj |
| 0x8A9100 | 0x8A91FF | 256 B | IRQ notify table (256 IRQs) | kernel/core/ipc.fj |
| 0x8AB000 | 0x8AB7FF | 2 KB | SHM table (32 regions × 64B) | kernel/core/ipc.fj |

### Security (0x8F7000 — 0x8FFFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x8F7800 | 0x8F78FF | 256 B | Stack canary table (16 × 16B) | kernel/core/security.fj |
| 0x8FA000 | 0x8FA4FF | 1.3 KB | IPC fast-path state | kernel/core/fast_ipc.fj |

### Kernel Stacks (0x900000 — 0xBFFFFF)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x900000 | 0xBFFFFF | 3 MB | sys_fork kernel stacks (16 × 64KB, pre-reserved) | kernel/mm/frames.fj |

### ML Compute (0xB20000 — 0xBFFFFF, overlaps stacks in upper range)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0xB20000 | 0xB21FFF | 8 KB | Model metadata | kernel/compute/inference.fj |
| 0xB22A20 | 0xB3FFFF | ~116 KB | FajarQuant scratch | kernel/compute/fajarquant.fj |
| 0xB40000 | 0xB61FFF | 136 KB | KMatrix large buffer | kernel/compute/kmatrix.fj |
| 0xB62000 | 0xBDFFFF | ~504 KB | KMatrix scratch | kernel/compute/kmatrix.fj |
| 0xBE0000 | 0xBE7BFF | 31 KB | Transformer scratch | kernel/compute/transformer.fj |
| 0xBE7C00 | 0xBE7FFF | 1 KB | RoPE frequency table | kernel/compute/transformer.fj |
| 0xBE8000 | 0xBEBFFF | 16 KB | Transformer state | kernel/compute/transformer.fj |
| 0xBEC000 | 0xBEE0FF | 8.3 KB | Repetition penalty bitset | kernel/compute/model_loader.fj |
| 0xBEE100 | 0xBEE17F | 128 B | Recent token buffer + head | kernel/compute/model_loader.fj |
| 0xBEF100 | 0xBEF1FF | 128 B | LM head top-K buffer | kernel/compute/model_loader.fj |
| 0xBF9240 | 0xBF9FFF | 3.5 KB | ML scheduler scratch | kernel/sched/ml_scheduler.fj |
| 0xBFA000 | 0xBFAFFF | 4 KB | Inference pipeline state | kernel/compute/pipeline.fj |

### Model Data (0xC00000+)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0xC00000 | 0xC005FF | 1.5 KB | Model header + state + codebooks + LN | kernel/compute/model_loader.fj |
| 0xC30000 | 0x11FFFFF | ~15 MB | Embedding table | kernel/compute/model_loader.fj |
| 0x1200000 | 0x3FFFFFF | ~46 MB | Layer weights | kernel/compute/model_loader.fj |
| 0x4000000 | 0x7FFFFFF | 64 MB | KV cache | kernel/compute/transformer.fj |
| 0x8000000 | 0xBFFFFFF | 64 MB | Streaming embed buffer | kernel/compute/model_loader.fj |
| 0xCC00000 | 0xD3FFFFF | 8 MB | Streaming layer buffer | kernel/compute/model_loader.fj |
| 0xD400000 | 0xDBFFFFF | 8 MB | Streaming LM head buffer | kernel/compute/model_loader.fj |
| 0x10000000 | 0x1AFFFFFF | 176 MB | RAM-resident layers (full model) | kernel/compute/model_loader.fj |

### User Space (0x2000000 — 0x3000000)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0x2000000 | 0x27FFFFF | 8 MB | ELF load base | kernel/syscall/elf.fj |
| 0x2800000 | 0x2FFFFFF | 8 MB | User heap (sys_brk) | kernel/syscall/dispatch.fj |
| 0x3000000 | 0x3000000 | top | User stack (grows down) | kernel/syscall/elf.fj |

### MMIO (above physical RAM)

| Start | End | Size | Owner | File |
|-------|-----|------|-------|------|
| 0xFEC00000 | 0xFEC003FF | 1 KB | I/O APIC registers | kernel/interrupts/lapic.fj |
| 0xFEE00000 | 0xFEE003FF | 1 KB | Local APIC registers | kernel/interrupts/lapic.fj |

## Known Collision History

| Date | Region A | Region B | Resolution |
|------|----------|----------|------------|
| Pre-V26 | CANARY_TABLE 0x8F7000 | PROC_MEM_STATS | Moved canary to 0x8F7800 |
| Pre-V26 | SHM_TABLE 0x8AA000 | IRQ_NOTIFY_TABLE | Moved SHM to 0x8AB000 |
| Pre-V26 | FP_RECV_SCRATCH 0x8FA1F0 | Slot 15 overlap | Moved to 0x8FA200 |
