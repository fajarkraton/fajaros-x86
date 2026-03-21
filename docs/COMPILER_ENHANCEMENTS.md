# Fajar Lang Compiler Enhancements for FajarOS Microkernel

> **Scope:** Maximum enhancements — everything the compiler COULD do
> to make FajarOS the safest OS in the world.
> **Total:** 12 enhancements, ~45 hours

---

## Enhancement Matrix

| # | Enhancement | Priority | Effort | Impact |
|---|-------------|----------|--------|--------|
| E1 | @safe hardware restriction | **CRITICAL** | 3 hrs | Blocks all isolation |
| E2 | @safe → @kernel call gate | **CRITICAL** | 2 hrs | Forces syscall path |
| E3 | Multi-binary build | **CRITICAL** | 4 hrs | Enables separate services |
| E4 | User-mode runtime library | **HIGH** | 3 hrs | @safe println/exit/ipc |
| E5 | IPC type-safe messages | **HIGH** | 4 hrs | Compile-time IPC safety |
| E6 | Capability type system | **HIGH** | 5 hrs | `Cap<PortIO>` types |
| E7 | @device hardware subset | **MEDIUM** | 3 hrs | Only allowed HW access |
| E8 | Cross-service type sharing | **MEDIUM** | 3 hrs | Shared types across ELFs |
| E9 | Async IPC (await ipc_recv) | **MEDIUM** | 4 hrs | Non-blocking services |
| E10 | Service declaration syntax | **LOW** | 3 hrs | `service vfs { }` blocks |
| E11 | Protocol definition syntax | **LOW** | 4 hrs | `protocol VfsProto { }` |
| E12 | Formal verification hooks | **FUTURE** | 8 hrs | seL4-style proof annotations |

---

## E1: @safe Hardware Restriction (CRITICAL — 3 hrs)

**Problem:** `@safe fn` can currently call `port_outb`, `volatile_write`, `cli`, `hlt` etc.
A @safe shell process could crash the kernel.

**Solution:** Add `safe_blocked_builtins` set in analyzer, reject 121 bare-metal builtins.

### Tasks (6)

| # | Task | File | Detail |
|---|------|------|--------|
| E1.1 | Define safe_blocked set | `type_check/mod.rs` | All 121 `fj_rt_bare_*` builtins |
| E1.2 | Check in @safe context | `type_check/check.rs` | `if in_safe && safe_blocked.contains(name) → error` |
| E1.3 | New error: SE020 | `type_check/mod.rs` | "hardware access not allowed in @safe context" |
| E1.4 | Allow @safe builtins | mod.rs | `println`, `len`, `type_of`, `assert` stay allowed |
| E1.5 | Test: @safe port_outb → error | tests/ | Verify compiler rejects |
| E1.6 | Test: @safe println → OK | tests/ | Verify safe builtins work |

**Allowed in @safe:** `println`, `len`, `type_of`, `assert`, `assert_eq`, `panic`,
`to_string`, `parse_int`, `parse_float`, string/array methods, math builtins

**Blocked in @safe:** ALL `port_*`, `volatile_*`, `asm!()`, `cli`, `sti`, `hlt`,
`invlpg`, `write_cr*`, `read_cr*`, `write_msr`, `read_msr`, `iretq_to_user`,
`fxsave`, `fxrstor`, `rdtsc`, `rdrand`, `cpuid_*`, `pci_*`, `dma_*`, `irq_*`,
`sched_*`, `set_current_pid`, `gpio_*`, `spi_*`, `i2c_*`, `uart_*`, `nvme_*`

---

## E2: @safe → @kernel Call Gate (CRITICAL — 2 hrs)

**Problem:** @safe function can currently call ANY @kernel function directly.
In microkernel, @safe should ONLY interact with kernel via syscalls.

**Solution:** Reject direct @kernel function calls from @safe context.

### Tasks (4)

| # | Task | File | Detail |
|---|------|------|--------|
| E2.1 | Track @kernel functions | `type_check/register.rs` | `kernel_fns: HashSet<String>` (already exists) |
| E2.2 | Check @safe → @kernel calls | `type_check/check.rs` | `if in_safe && kernel_fns.contains(name) → error` |
| E2.3 | New error: SE021 | mod.rs | "cannot call @kernel function from @safe context; use syscall" |
| E2.4 | Test: @safe calls @kernel → error | tests/ | Verify |

**Allowed:** @safe → @safe, @safe → syscall builtins
**Blocked:** @safe → @kernel fn, @safe → @device fn

---

## E3: Multi-Binary Build (CRITICAL — 4 hrs)

**Problem:** `fj build` produces 1 ELF. Microkernel needs 6+ separate ELFs.

**Solution:** `fj build --target x86_64-none kernel/` → kernel.elf,
`fj build --target x86_64-user services/vfs/` → vfs.elf, etc.

### Tasks (6)

| # | Task | File | Detail |
|---|------|------|--------|
| E3.1 | Directory build mode | `main.rs` | `fj build dir/` compiles all .fj in directory |
| E3.2 | Service manifest | `fj.toml` | `[[service]] name="vfs" entry="services/vfs/main.fj"` |
| E3.3 | Build all services | `main.rs` | `fj build --all-services` builds each as x86_64-user ELF |
| E3.4 | Initramfs packing | `main.rs` | `fj pack` creates tar of all service ELFs |
| E3.5 | Kernel embeds initramfs | `linker.rs` | `.section .initramfs` with packed service ELFs |
| E3.6 | Test: build 3 ELFs | tests/ | kernel.elf + vfs.elf + shell.elf |

---

## E4: User-Mode Runtime Library (HIGH — 3 hrs)

**Problem:** @safe services need `println` → SYS_WRITE, `exit` → SYS_EXIT,
`ipc_send` → SYS_SEND. These don't exist for x86_64-user target.

**Solution:** Create `libfj_user.a` with syscall wrappers.

### Tasks (6)

| # | Task | File | Detail |
|---|------|------|--------|
| E4.1 | `fj_user_println(s)` | `runtime_user.rs` | `SYS_WRITE(1, buf, len)` via SYSCALL |
| E4.2 | `fj_user_exit(code)` | `runtime_user.rs` | `SYS_EXIT(code)` via SYSCALL |
| E4.3 | `fj_user_ipc_send(dst, msg)` | `runtime_user.rs` | `SYS_SEND(dst, msg)` via SYSCALL |
| E4.4 | `fj_user_ipc_recv(src, buf)` | `runtime_user.rs` | `SYS_RECV(src, buf)` via SYSCALL |
| E4.5 | `fj_user_ipc_call(dst, msg, reply)` | `runtime_user.rs` | `SYS_CALL(dst, msg, reply)` |
| E4.6 | Link user runtime for x86_64-user | `main.rs` | Auto-link when `--target x86_64-user` |

**After this:** `@safe fn main() { println("hello") }` compiles to user ELF
that uses SYSCALL for output.

---

## E5: IPC Type-Safe Messages (HIGH — 4 hrs)

**Problem:** IPC messages are raw 64-byte buffers. Type errors at runtime.

**Solution:** `ipc_msg!` macro or struct-based messages with compile-time type checking.

### Tasks (6)

| # | Task | File | Detail |
|---|------|------|--------|
| E5.1 | `@message` struct annotation | parser | `@message struct VfsOpen { path: str, flags: i64 }` |
| E5.2 | Auto-generate serialize/deserialize | codegen | Struct → 64-byte buffer pack/unpack |
| E5.3 | Type-check ipc_send argument | analyzer | `ipc_send(dst, VfsOpen { ... })` checks struct type |
| E5.4 | Type-check ipc_recv result | analyzer | `let msg: VfsOpen = ipc_recv(src)` checks type |
| E5.5 | Message ID auto-assignment | codegen | Each @message struct gets unique type ID |
| E5.6 | Test: wrong message type → error | tests/ | Send VfsOpen, recv as BlkRead → compile error |

---

## E6: Capability Type System (HIGH — 5 hrs)

**Problem:** Capabilities checked at runtime. Compiler could enforce at build time.

**Solution:** Phantom types: `Cap<PortIO>`, `Cap<IRQ>`, `Cap<DMA>`.

### Tasks (6)

| # | Task | File | Detail |
|---|------|------|--------|
| E6.1 | `Cap<T>` generic type | ast.rs | New built-in generic type |
| E6.2 | Function requires capability | parser | `fn driver(cap: Cap<PortIO>) { port_outb(...) }` |
| E6.3 | Kernel grants capabilities | runtime | `let cap = kernel_grant::<PortIO>()` |
| E6.4 | Check cap at call site | analyzer | `port_outb` requires `Cap<PortIO>` in scope |
| E6.5 | Revocation | runtime | `kernel_revoke(pid, Cap<PortIO>)` |
| E6.6 | Test: no cap → error | tests/ | Call port_outb without Cap<PortIO> → compile error |

---

## E7: @device Hardware Subset (MEDIUM — 3 hrs)

**Problem:** @device can access ANY hardware. Should only access declared devices.

**Solution:** `@device(net)` restricts to network-related builtins only.

### Tasks (4)

| # | Task | File | Detail |
|---|------|------|--------|
| E7.1 | Parameterized @device | parser | `@device(net)`, `@device(blk)`, `@device(gpu)` |
| E7.2 | Device builtin sets | analyzer | `net_builtins`, `blk_builtins`, `gpu_builtins` |
| E7.3 | Restrict by parameter | check.rs | `@device(net)` can't call `nvme_read` |
| E7.4 | Test: @device(net) calls nvme → error | tests/ | Verify cross-device restriction |

---

## E8: Cross-Service Type Sharing (MEDIUM — 3 hrs)

**Problem:** VFS and shell both need `struct FileInfo`. Currently can't share types between separate ELFs.

**Solution:** Shared type definitions compiled into a common header.

### Tasks (4)

| # | Task | File | Detail |
|---|------|------|--------|
| E8.1 | `@shared` module annotation | parser | `@shared mod ipc_types { struct FileInfo { ... } }` |
| E8.2 | Compile shared types once | codegen | Output type definitions to shared header |
| E8.3 | Import in services | parser | `use ipc_types::FileInfo` across ELFs |
| E8.4 | Test: shared struct across 2 ELFs | tests/ | Same layout guaranteed |

---

## E9: Async IPC (MEDIUM — 4 hrs)

**Problem:** `ipc_recv` blocks the entire service. Can't handle multiple clients.

**Solution:** `async fn handle() { let msg = await ipc_recv() }`

### Tasks (4)

| # | Task | File | Detail |
|---|------|------|--------|
| E9.1 | Async IPC recv | runtime | `await ipc_recv()` yields to event loop |
| E9.2 | Service event loop | runtime | `select! { msg = ipc_recv(), timer = sleep(100) }` |
| E9.3 | Multi-client handling | runtime | Service handles N clients concurrently |
| E9.4 | Test: async VFS serves 2 clients | tests/ | Concurrent file reads |

---

## E10: Service Declaration Syntax (LOW — 3 hrs)

**Problem:** Services are just regular programs. No language support for service patterns.

**Solution:** `service` keyword with built-in IPC loop.

```fajar
@safe service vfs {
    on VfsOpen(msg) -> VfsReply {
        let fd = open_file(msg.path)
        VfsReply { fd, status: 0 }
    }
    on VfsRead(msg) -> VfsReply {
        let data = read_file(msg.fd, msg.len)
        VfsReply { data, status: 0 }
    }
}
```

### Tasks (4)

| # | Task | File | Detail |
|---|------|------|--------|
| E10.1 | `service` keyword | lexer/parser | New top-level declaration |
| E10.2 | `on` message handler | parser | Pattern-matched IPC dispatch |
| E10.3 | Auto-generate IPC loop | codegen | Main loop: recv → match → handler → reply |
| E10.4 | Test: service compiles | tests/ | VFS service declaration |

---

## E11: Protocol Definition Syntax (LOW — 4 hrs)

**Problem:** IPC protocols defined in documentation, not in code. Can drift.

**Solution:** `protocol` keyword defines the contract.

```fajar
protocol VfsProtocol {
    fn open(path: str) -> (fd: i64, status: i64)
    fn read(fd: i64, len: i64) -> (data: [u8], status: i64)
    fn write(fd: i64, data: [u8]) -> (written: i64, status: i64)
    fn close(fd: i64) -> (status: i64)
}

@safe service vfs implements VfsProtocol { ... }
```

### Tasks (6)

| # | Task | File | Detail |
|---|------|------|--------|
| E11.1 | `protocol` keyword | lexer/parser | Interface definition |
| E11.2 | `implements` clause | parser | Service declares which protocol |
| E11.3 | Completeness check | analyzer | All protocol methods must be implemented |
| E11.4 | Client type check | analyzer | Client calls match protocol signature |
| E11.5 | Auto-generate client stub | codegen | `VfsClient::open(path)` → IPC call |
| E11.6 | Test: missing method → error | tests/ | Service missing read() → compile error |

---

## E12: Formal Verification Hooks (FUTURE — 8 hrs)

**Problem:** Safety depends on correct implementation. Formal proofs would guarantee it.

**Solution:** `@invariant`, `@requires`, `@ensures` annotations.

```fajar
@kernel fn frame_alloc() -> i64 {
    @requires(frame_count > 0)
    @ensures(result >= 0 || result == -1)
    @invariant(bitmap_consistent())
    // ...
}
```

---

## Implementation Order

### Minimum Viable (unblocks microkernel): 3 enhancements, ~9 hrs
```
E1 (@safe restriction)  →  E2 (call gate)  →  E3 (multi-binary)
```

### Recommended (safe + usable): 6 enhancements, ~19 hrs
```
E1 → E2 → E3 → E4 (user runtime) → E5 (typed IPC) → E7 (@device subset)
```

### Maximum (world-class): ALL 12, ~45 hrs
```
E1 → E2 → E3 → E4 → E5 → E6 → E7 → E8 → E9 → E10 → E11 → E12
```

---

## Impact Comparison

| Level | Enhancements | What It Enables |
|-------|-------------|-----------------|
| **Minimum** (E1-E3) | @safe can't access HW, separate ELFs | Basic microkernel works |
| **Recommended** (E1-E7) | Typed IPC, user runtime, capability types | Production microkernel |
| **Maximum** (E1-E12) | Service syntax, protocols, async, formal proofs | **World's safest OS** |

---

*Fajar Lang: where the compiler IS the security model.*
