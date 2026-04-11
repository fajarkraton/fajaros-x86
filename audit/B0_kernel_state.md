# B0.2 — fork() / exit() / SMEP Actual Code Paths

**Audit date:** 2026-04-11
**Audit task:** V26 Phase B0.2 (`fajar-lang/docs/V26_PRODUCTION_PLAN.md` §B0)
**Repo HEAD:** `6076610` (in sync with origin)
**Method:** Read each cited line in the actual source file, quote verbatim.

## TL;DR — Plan Hygiene Rule 4 Catch

The handoff (`memory/project_v26_handoff.md`) listed three FajarOS V26 critical TODOs:

1. ❌ **WRONG**: "kernel/core/syscall.fj: fork() doesn't return PID (P0)" — the cited line is for **SYS_GETPID**, not SYS_FORK. The actual `sys_fork()` is fully implemented in `kernel/process/fork.fj` and returns the child PID correctly.
2. ✅ **CORRECT**: "kernel/sched/process.fj: process exit doesn't free resources (P1 leak)" — confirmed at `proc_v2_exit()`.
3. ✅ **CORRECT**: "kernel/main.fj:107: SMEP disabled (P2 security)" — confirmed with detailed reason comment.

**Net effect:** the B1 Phase task "fork() PID return [actual 3h, est 2h, +50%]" can be **deleted entirely** — the work is already done. Phase B effort budget shrinks accordingly.

---

## 1. sys_fork() — REAL, COMPLETE (handoff was wrong)

**File:** `kernel/process/fork.fj`
**Function:** `@kernel fn sys_fork() -> i64`
**Lines:** 1-76
**Status:** **Fully implemented**, returns child PID

### Verbatim implementation summary

```fajar
@kernel fn sys_fork() -> i64 {
    let parent_pid = volatile_read_u64(0x6FE00)
    let parent_base = PROC_TABLE + parent_pid * PROC_ENTRY_SIZE

    // Find free PID
    let mut child_pid: i64 = -1
    let mut i: i64 = 1
    while i < PROC_MAX && child_pid == -1 {
        if volatile_read(PROC_TABLE + i * PROC_ENTRY_SIZE + PROC_OFF_STATE) == PROC_STATE_FREE {
            child_pid = i
        }
        i = i + 1
    }
    if child_pid == -1 { return -1 }

    // Clone page tables
    let parent_cr3 = volatile_read(parent_base + PROC_OFF_CR3)
    let child_pml4 = fork_clone_page_tables(parent_cr3)
    if child_pml4 == -1 { return -1 }

    // Copy FD table
    fork_copy_fd_table(parent_pid, child_pid)

    // Copy proc fields, build child kernel stack, copy parent context frame
    // ... (lines 32-73)

    // Set child RAX=0 so child sees fork() returning 0 (parent gets PID)
    volatile_write_u64(child_sp + CTX_OFF_RAX, 0)

    // ... (state setup)

    child_pid    // ← LINE 75: returns child PID to parent
}
```

**Key correctness facts:**
1. **Parent return value:** the function literally returns `child_pid` on the last line (line 75)
2. **Child return value:** child's saved RAX is set to 0 (line 57: `volatile_write_u64(child_sp + CTX_OFF_RAX, 0)`)
3. **Error path:** returns `-1` if no free PID slot OR page table clone fails
4. **Page table copy:** delegates to `fork_clone_page_tables()` (line 78+) which uses `clone_kernel_pml4()` and recursive `fork_copy_page_level()` — true deep copy, not shallow alias
5. **FD table copy:** delegates to `fork_copy_fd_table()` (line 131+) — preserves open file descriptors across fork
6. **PPID set:** line 66 — `volatile_write(child_base + PROC_OFF_PPID, parent_pid)`

### Where the syscall dispatch routes

**File:** `kernel/syscall/dispatch.fj`
**Constant:** `const SYS_FORK: i64 = 20      // fork() -> pid/0` (line 37)
**Dispatch:** `if num == SYS_FORK { return sys_fork() }` (line 117)

The dispatcher returns `sys_fork()`'s result directly, so userland gets the real PID.

### What the handoff ACTUALLY saw

The handoff cited `kernel/core/syscall.fj:249` as "fork() doesn't return PID". The actual content of that line is:
```fajar
if num == SYS_GETPID {
    return 0 // TODO: return actual PID from scheduler  ← line 249
}
```

This is **`SYS_GETPID`** (constant `SYS_GETPID = 39` or similar), **not** SYS_FORK. The handoff confused two different syscalls. `SYS_GETPID` returning 0 is a **separate, smaller bug** (always returns "PID 0") that does need fixing — but it is NOT the same scope as a missing fork() implementation.

**Action:** Remove the "fork() PID return" item from B1. Add a much smaller item "fix SYS_GETPID hardcoded 0" if desired (15 min, single-line change).

---

## 2. proc_v2_exit() — Real, Has Real TODO (handoff correct)

**File:** `kernel/sched/process.fj`
**Function:** `@kernel fn proc_v2_exit(pid: i64, code: i64)`
**Lines:** 93-97
**Status:** **Half-implemented**, real P1 resource leak

### Verbatim quote

```fajar
@kernel fn proc_v2_exit(pid: i64, code: i64) {
    proc_v2_set(pid, 0, PROC_STATE_ZOMBIE)
    proc_v2_set(pid, 56, code)
    // TODO: signal parent, free resources
}
```

### What's missing

1. **Signal parent**: parent waiting in `waitpid()` is not woken up. Parent must busy-poll on the zombie's state field (`proc_v2_waitpid()` returns `-1` if not ready, line 107).
2. **Free resources**: page tables are NOT freed when a process exits. The `cr3` field still points to live frames; `frame_alloc()` won't reclaim them. Long-running shells that fork+exit will eventually OOM.
3. **FD table not closed**: open files at fork time are not closed on exit; `fork_copy_fd_table()` semantics leak.
4. **Kernel stack not freed**: `KSTACK_BASE + child_pid * KSTACK_SIZE` page mapping remains.

### Companion: `proc_v2_waitpid()` (already correct)

Line 99-108 — reads zombie state, returns exit code, sets state to FREE. This is the **reaping** half. The exit half just doesn't notify it.

### Suggested B1 task

| Subtask | What | Estimated effort |
|---|---|---|
| B1.1.1 | Free child page tables in `proc_v2_exit()` (walk PML4 → free frames) | 1 h |
| B1.1.2 | Free child kernel stack mapping | 0.5 h |
| B1.1.3 | Walk fd table, close all open files | 0.5 h |
| B1.1.4 | Wake parent if blocked in `waitpid()` (set ready flag) | 1 h |
| B1.1.5 | Stress test: fork 100 children, exit 100 children, verify frame counter returns to baseline | 1 h |

**Total for B1.1:** ~4 h. **Risk:** medium — frame leak in cleanup path can corrupt heap if walk is wrong; needs careful test before SMP.

---

## 3. SMEP — Disabled With Detailed Reason (handoff correct)

**File:** `kernel/main.fj`
**Lines:** 101-107
**Status:** **Intentionally disabled** with code comments explaining why

### Verbatim quote

```fajar
// Note: SMEP (CR4 bit 20) NOT enabled — our identity-mapped 2MB pages
// use P|RW|PS flags without explicit Supervisor-only marking.
// On real CPUs with SMEP, the U/S bit in page tables must be 0 for
// kernel pages. Our 32-bit trampoline sets PD entries with just P|RW|PS
// (no User bit), so SMEP *should* work, but some QEMU -cpu host configs
// expose SMEP before we can verify page table correctness.
// TODO: Enable SMEP after verifying all kernel pages have U/S=0.
```

### What this means for B1

The TODO is real but the comment is honest about the risk. The fix is two-step:
1. **Audit** every page table mutation site (`map_page`, `extend_identity_mapping`, etc.) and assert U/S=0 for kernel addresses
2. **Enable SMEP** by setting CR4 bit 20

If the audit catches even one U/S=1 mapping, enabling SMEP will trip a #PF on the next kernel fetch from that page, hard-locking the kernel.

### Suggested B1 task

| Subtask | What | Estimated effort |
|---|---|---|
| B4.1.1 | Audit `kernel/mm/paging.fj` `map_page()` for U bit | 1 h |
| B4.1.2 | Audit `extend_identity_mapping()` and 32-bit trampoline `boot/startup.S` | 1 h |
| B4.1.3 | Add compile-time `assert!(flags & PAGE_USER == 0)` for kernel addresses | 1 h |
| B4.2.1 | Set CR4 bit 20 in `kernel/main.fj` after audit passes | 15 min |
| B4.2.2 | Boot test under QEMU `-cpu host` to verify no faults | 30 min |
| B4.2.3 | Run shell + LLM workload, verify no SMEP faults | 1 h |

**Total for B4 SMEP work:** ~5 h. **Risk:** HIGH — exhaustive audit is mandatory; staged rollout per V26 plan §6 risk register.

---

## 4. NEW Finding — Dual Scheduler Implementations (B0.4 territory)

Two separate files implement `proc_v2_*()` functions with the **same TODO at line 96**:

| File | LOC | Used in | Same TODO? |
|---|---|---|---|
| `kernel/sched/process.fj` | 147 | Main `make build-llvm` (Makefile line 56) | Yes (line 96) |
| `kernel/core/sched.fj` | 143 | `make micro` microkernel variant (Makefile line 544 in `MICRO_SOURCES`) | Yes (line 96) |

**Diff is small** (~4 lines difference, both define the same proc_v2 functions). The microkernel variant is a separate build path used for the experimental µkernel mode. Both are real, both are active in their respective build targets.

**Implication for B1:** when fixing the exit() leak, the fix must be applied to **both files** (or refactored to a single shared file), otherwise the µkernel variant remains broken. Add B1.1.6 = "apply same exit() fix to `kernel/core/sched.fj`" (15 min once main fix is in).

---

## 5. Sign-Off

B0.2 audit completed 2026-04-11. Three TODOs from the handoff verified against actual source. Major correction: **fork() PID return is not a problem and never was**; the handoff confused SYS_GETPID with SYS_FORK. **Two real TODOs** (exit leak, SMEP) confirmed and broken into actionable B1 subtasks. **One new finding** (dual scheduler) requires B1 work to be replicated across both build variants.

**Net effect on B1 scope:** −2 to −3 hours (no fork() work) + ~4 hours (proper exit() cleanup) + ~5 hours (proper SMEP audit + enable) + 15 min (microkernel duplication). **Approximate B1 baseline before surprise budget: ~9.5 hours**, vs handoff's implicit "3 critical TODOs" framing that suggested ~10-15 hours.
