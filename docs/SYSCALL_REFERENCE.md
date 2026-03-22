# FajarOS Nova v2.0 — Syscall Reference

> 18 syscalls. Capability-guarded. SYSCALL/SYSRET entry via MSR 0xC0000082.

## Syscall Table

| # | Name | Args | Returns | Description |
|---|------|------|---------|-------------|
| 0 | SYS_EXIT | code:i64 | -- | Terminate calling process |
| 1 | SYS_WRITE | fd:i64, buf:ptr, len:i64 | bytes:i64 | Write to fd (1=stdout/serial) |
| 2 | SYS_READ | fd:i64, buf:ptr, len:i64 | bytes:i64 | Read from fd (0=stdin/keyboard) |
| 3 | SYS_GETPID | -- | pid:i64 | Get current process ID |
| 4 | SYS_YIELD | -- | 0 | Voluntary reschedule |
| 5 | SYS_SLEEP | ms:i64 | 0 | Sleep for N milliseconds |
| 6 | SYS_MMAP | size:i64 | addr:i64 | Map memory pages (heap at ELF+40MB) |
| 10 | SYS_SEND | dst:i64, msg:ptr | 0 or err | Send 64-byte IPC message (blocks) |
| 11 | SYS_RECV | from:i64, buf:ptr | sender:i64 | Receive IPC message (blocks, -1=any) |
| 12 | SYS_CALL | dst:i64, msg:ptr, reply:ptr | 0 or err | Send + wait reply (synchronous RPC) |
| 13 | SYS_REPLY | dst:i64, msg:ptr | 0 or err | Reply to a SYS_CALL sender |
| 14 | SYS_NOTIFY | dst:i64, bits:i64 | 0 or err | Async notification (bitmask) |
| 21 | SYS_MUNMAP | addr:i64, len:i64 | 0 or -1 | Unmap memory pages |
| 22 | SYS_SHARE | region:i64, pid:i64 | addr:i64 | Share memory region with process |
| 30 | SYS_IRQ_WAIT | irq:i64 | 0 | Block until IRQ fires (drivers only) |
| 31 | SYS_PORT_IO | port:i64, val:i64, dir:i64 | val:i64 | Port read (dir=0) / write (dir=1) |
| 32 | SYS_DMA_ALLOC | size:i64 | phys:i64 | Allocate DMA-safe physical memory |

Numbers 7 (SYS_BRK), 8 (SYS_SPAWN), 9 (SYS_KILL) are reserved.

## Invocation Convention

Syscalls use `SYSCALL`: RAX=number, RDI=arg0, RSI=arg1, RDX=arg2, RAX(out)=return. Kernel entry at `0x8200` does `swapgs`, switches to kernel stack, dispatches, returns via `SYSRETQ`.

## IPC Message Format (64 bytes)

```
Offset  Size   Field        Description
 +0     8      src_pid      Sender process ID (set by kernel)
 +8     4      msg_type     Message type code (see table below)
+12     4      msg_id       Unique message ID (request/reply matching)
+16    40      payload      Application-defined data
+56     8      reserved     Must be zero
```

### Message Types

| Type | Value | Direction | Description |
|------|-------|-----------|-------------|
| MSG_VFS_OPEN | 0x0100 | App -> VFS | Open file by path |
| MSG_VFS_READ | 0x0101 | App -> VFS | Read from fd |
| MSG_VFS_WRITE | 0x0102 | App -> VFS | Write to fd |
| MSG_VFS_CLOSE | 0x0103 | App -> VFS | Close fd |
| MSG_VFS_STAT | 0x0104 | App -> VFS | Get file info |
| MSG_VFS_LIST | 0x0105 | App -> VFS | List directory |
| MSG_VFS_REPLY | 0x01FF | VFS -> App | Reply with data/status |
| MSG_BLK_READ | 0x0200 | VFS -> BLK | Read sectors |
| MSG_BLK_WRITE | 0x0201 | VFS -> BLK | Write sectors |
| MSG_BLK_REPLY | 0x02FF | BLK -> VFS | Reply with data |
| MSG_NET_SEND | 0x0300 | App -> NET | Send packet |
| MSG_NET_RECV | 0x0301 | App -> NET | Receive packet |
| MSG_NET_CONNECT | 0x0302 | App -> NET | TCP connect |
| MSG_NET_REPLY | 0x03FF | NET -> App | Reply with data |
| MSG_DEV_REG | 0x0400 | Drv -> VFS | Register device node |
| MSG_IRQ_EVENT | 0x0500 | Kernel -> Drv | IRQ occurred |

For data >40 bytes: sender calls `SYS_SHARE` to map buffer into receiver, payload carries `shared_addr(8)+length(8)+offset(8)`, receiver reads zero-copy.

## Detailed Reference

### Console + Process (0-6)

**SYS_EXIT(0):** Terminates process, returns to scheduler. **SYS_WRITE(1):** fd=1 writes to serial 0x3F8 + VGA. Returns bytes written or -1. **SYS_READ(2):** fd=0 reads keyboard buffer. **SYS_GETPID(3):** Returns PID. **SYS_YIELD(4):** Voluntary reschedule. **SYS_SLEEP(5):** PIT-based millisecond sleep. **SYS_MMAP(6):** Allocates pages with USER+WRITABLE flags, returns virtual address.

```fajar
@safe fn print(msg: str) { syscall(SYS_WRITE, 1, msg as ptr, str_len(msg)) }
let heap = syscall(SYS_MMAP, 4096, 0, 0)
```

### IPC (10-14)

**SYS_SEND(10):** Synchronous send (L4-style rendezvous). Blocks until receiver calls recv. **SYS_RECV(11):** Blocks until message arrives. `from=-1` accepts any sender, returns sender PID. **SYS_CALL(12):** Atomic RPC -- send + wait reply in one syscall. **SYS_REPLY(13):** Unblocks a SYS_CALL sender with response data. **SYS_NOTIFY(14):** Async -- sets bits in target's pending notification word without blocking.

```fajar
// Client RPC
@safe fn rpc(server: i64, req: ptr, reply: ptr) -> i64 {
    syscall(SYS_CALL, server, req, reply)
}
// Server loop
@safe fn serve(buf: ptr) {
    let sender = syscall(SYS_RECV, -1, buf, 0)
    // process request...
    syscall(SYS_REPLY, sender, buf, 0)
}
```

### Memory (21-22)

**SYS_MUNMAP(21):** Unmap pages at `addr` for `len` bytes. **SYS_SHARE(22):** Map shared memory region into another process. Returns guest virtual address. Used for zero-copy IPC.

```fajar
let region = syscall(SYS_DMA_ALLOC, 4096, 0, 0)
let guest_addr = syscall(SYS_SHARE, region, client_pid, 0)
```

### I/O (30-32)

**SYS_IRQ_WAIT(30):** Block until IRQ fires. Requires `CAP_IRQ`. **SYS_PORT_IO(31):** Port read (dir=0) or write (dir=1). Requires `CAP_PORT_IO`. **SYS_DMA_ALLOC(32):** Allocate physically contiguous DMA memory. Requires `CAP_DMA`.

```fajar
@device fn serial_write(b: i64) { syscall(SYS_PORT_IO, 0x3F8, b, 1) }
@device fn wait_nvme() { syscall(SYS_IRQ_WAIT, nvme_irq, 0, 0) }
```

## Error Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | IPC_OK | Success |
| -1 | IPC_ERR_INVALID_PID | Target PID out of range or not allocated |
| -2 | IPC_ERR_QUEUE_FULL | Message queue full (4 slots) |
| -3 | IPC_ERR_NO_MESSAGE | No message available |
| -4 | IPC_ERR_NOT_CALLING | Target not in CALL_BLOCKED state |
| -5 | IPC_ERR_NO_CAP | Missing required capability |
| -6 | IPC_ERR_DEAD_PROCESS | Target has exited |
| -7 | IPC_ERR_WOULD_BLOCK | Would block (non-blocking mode) |

## Capability Requirements

| Syscall | Required Capability | Syscall | Required Capability |
|---------|-------------------|---------|-------------------|
| SYS_SEND | CAP_IPC_SEND (bit 0) | SYS_IRQ_WAIT | CAP_IRQ (bit 5) |
| SYS_RECV | CAP_IPC_RECV (bit 1) | SYS_PORT_IO | CAP_PORT_IO (bit 4) |
| SYS_CALL | SEND + RECV | SYS_DMA_ALLOC | CAP_DMA (bit 6) |
| SYS_REPLY | CAP_IPC_SEND | SYS_NOTIFY | CAP_IPC_SEND |

Defaults: `@kernel`=ALL, `@device`=IPC+PORT_IO+IRQ+DMA+MAP_PHYS+DEVICE, `@safe`=IPC+SPAWN+FS+NET.

---
*FajarOS Nova v2.0 -- 18 syscalls, 64-byte IPC messages, capability-guarded*
