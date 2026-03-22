# FajarOS Safety Model — Compiler-Enforced Isolation

> **The Killer Feature:** If it compiles, it's safe to deploy.
> No other OS enforces driver isolation at the compiler level.

---

## Three Isolation Contexts

| Context | Who | Can Access | Cannot Access |
|---------|-----|-----------|---------------|
| `@kernel` | Kernel core (Ring 0) | Hardware, IRQ, DMA, page tables, port I/O | Heap strings, tensor ops, @device fns |
| `@device` | Driver services | Tensor/ML, restricted hardware (via caps) | asm!, raw pointers, IRQ, @kernel fns |
| `@safe` | User processes | Pure computation, IPC via syscalls | ALL hardware, @kernel fns, @device fns |

## How It Works

```fajar
// This COMPILES — @kernel can access hardware
@kernel fn read_sensor() -> i64 {
    port_inb(0x3F8)
}

// This FAILS at compile time — SE020
@safe fn hack() {
    port_outb(0x3F8, 65)  // ERROR: hardware access not allowed in @safe context
}

// This FAILS — KE003
@kernel fn misuse() {
    tensor_zeros(3, 3)  // ERROR: tensor operations not allowed in @kernel context
}
```

## Error Code Reference

| Code | Context | Violation | Message |
|------|---------|-----------|---------|
| KE001 | @kernel | Heap allocation | "heap allocation not allowed in @kernel context" |
| KE002 | @kernel | Tensor/ML ops | "tensor operations not allowed in @kernel context" |
| KE003 | @kernel | Call @device fn | "cannot call @device function from @kernel context" |
| KE005 | @safe | Inline assembly | "inline assembly not allowed in @safe context" |
| KE006 | @device | Inline assembly | "inline assembly not allowed in @device context" |
| DE001 | @device | Raw pointer ops | "raw pointer operations not allowed in @device context" |
| SE020 | @safe | Hardware builtin | "hardware access not allowed in @safe — use syscall" |
| SE021 | @safe | Call @kernel fn | "cannot call @kernel function from @safe — use syscall" |

## Capability-Based @device Restrictions

```fajar
// @device("net") — only network builtins allowed
@device("net") fn handle_packet() {
    net_send(sock, data, len)  // ✅ OK
    port_outb(0x3F8, 65)      // ❌ FAIL: not a net capability
}
```

Available capabilities: `net`, `blk`, `port_io`, `irq`, `dma`

## Cross-Context Call Rules

```
@safe  → @safe    ✅ direct call
@safe  → @kernel  ❌ compile error (use syscall)
@safe  → @device  ❌ compile error (use IPC)

@kernel → @kernel  ✅ direct call
@kernel → @device  ❌ compile error (KE003)
@kernel → @safe    ✅ direct call (safe is subset)

@device → @device  ✅ direct call
@device → @kernel  ❌ compile error
@device → @safe    ✅ direct call (safe is subset)
```

## IPC Safety Model

The IPC subsystem provides runtime safety on top of compile-time enforcement:

1. **Fixed-size messages** (64 bytes) — no buffer overflows
2. **Capability bitmap** — checked on every IPC send (CAP_IPC_SEND etc.)
3. **Named channels** — service discovery without PID guessing
4. **Shared memory** — explicit mapping with permissions
5. **Message type dispatch** — unknown types return EINVAL

## OS Service Architecture

```
Shell (@safe, PID 5)         ── IPC ──→  VFS (@safe, PID 3)
                                              │
                                          IPC │
                                              ▼
                                         BLK (@device, PID 2)
                                              │
                                         SYS_PORT_IO (syscall)
                                              │
                                              ▼
                                    Kernel (@kernel, PID 0)
                                         [IRQ stubs only]
```

**Key insight:** The block driver (@device) cannot corrupt the kernel because:
- The compiler rejects `asm!()` in @device (KE006)
- The compiler rejects raw pointer ops in @device (DE001)
- Port I/O goes through `SYS_PORT_IO` syscall with capability check
- DMA buffers are kernel-mapped (SYS_DMA_ALLOC)

## Comparison with Other OSes

| Feature | Linux | seL4 | Redox | **FajarOS** |
|---------|-------|------|-------|-------------|
| Driver isolation | None (all Ring 0) | Manual caps | Rust borrow | **Compiler-enforced @kernel/@device** |
| AI safety | N/A | N/A | N/A | **@device blocks raw HW from ML code** |
| User safety | MMU only | Capability | MMU + Rust | **@safe = zero hardware access** |
| Error timing | Runtime crash | Runtime trap | Compile + runtime | **Compile time** |

---

*FajarOS Safety Model v2.0 — Compiler-Enforced Isolation*
*8 error codes, 3 contexts, 5 capabilities*
*"If it compiles in Fajar Lang, it's safe to deploy on hardware."*
