# FajarOS Nova v2.0 User Manual

> Written 100% in Fajar Lang. Compiler-enforced safety. Microkernel architecture.

## 1. Introduction

FajarOS Nova is a bare-metal x86_64 operating system written entirely in Fajar Lang (`.fj`). It is the world's first OS with **compiler-enforced privilege isolation**: `@kernel`, `@device`, and `@safe` annotations are checked at compile time, preventing entire classes of security bugs before the code ever runs.

| Annotation | Ring | Allowed | Prohibited |
|------------|------|---------|------------|
| `@kernel` | 0 | asm, port I/O, MMIO, IRQ | heap strings, tensors |
| `@device` | 3 | tensor/AVX2/GPU compute | raw pointers, IRQ |
| `@safe` | 3 | syscalls, strings, IPC | direct hardware access |

**Target audience:** OS researchers, embedded AI engineers, safety-critical systems developers.

## 2. Getting Started

**Requirements:** Fajar Lang compiler (`fj`) v4.1.0+, QEMU 8.0+, GNU Make. Optional: KVM, `grub-mkrescue`.

```bash
make build        # Concatenate 70+ .fj files + compile kernel ELF
make run          # Boot in QEMU (serial, no KVM)
make run-kvm      # Boot with KVM acceleration
make run-vga      # Boot with VGA text display
make run-smp      # Boot with 4 CPU cores
make run-nvme     # Boot with NVMe virtual disk (64MB)
make run-net      # Boot with virtio-net networking
make debug        # Boot with GDB server on :1234
make iso          # Create bootable GRUB2 ISO
make test         # Run kernel tests (auto-exit)
make micro        # Build microkernel core only (Ring 0, ~8 files)
make clean        # Remove build artifacts
```

The Makefile concatenates modular `.fj` files in dependency order into `build/combined.fj`, then compiles with `fj build --target x86_64-none`. Services build separately via `make services` (target `x86_64-user`).

## 3. Shell Commands

Type `help` at the `nova>` prompt. Commands grouped by category:

### System

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `help` | List all commands | `version` | Kernel version |
| `uname` | OS name/arch/version | `uptime` | Time since boot |
| `cpuinfo` | CPU features/cores | `meminfo` | Memory usage |
| `date` | Current date/time | `hostname` | System hostname |
| `whoami` | Current user | `arch` | Architecture |
| `nproc` | CPU core count | `sysinfo` | System overview |
| `neofetch` | Info + ASCII logo | `acpi` | Power info |

### Files

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `ls` | List directory | `cat <file>` | Print file |
| `touch <file>` | Create file | `rm <file>` | Remove file |
| `mkdir <dir>` | Create directory | `rmdir <dir>` | Remove directory |
| `write <f> <t>` | Write text to file | `append <f> <t>` | Append to file |
| `head <file>` | First lines | `tail <file>` | Last lines |
| `grep <p> <f>` | Search pattern | `wc <file>` | Word/line count |
| `stat <file>` | File metadata | `cp <s> <d>` | Copy file |
| `mv <s> <d>` | Move/rename | `pwd` | Working directory |

### Process

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `ps` | List processes | `kill <pid>` | Terminate process |
| `spawn <name>` | Start program | `wait <pid>` | Wait for exit |
| `top` | Process monitor | `nice <p> <n>` | Set priority |
| `demo` | Scheduler demo | | |

### Network

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `ifconfig` | Interface status | `ping` | ICMP echo |
| `arp` | ARP cache | `netinit` | Init network |

### IPC v2 & Microkernel

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `ipc2` | Endpoint status | `channels` | Named channels |
| `shm` | Shared memory | `ipc-test` | IPC test suite |
| `ipc-bench` | Latency bench | `caps` | Capabilities |
| `vfs-test` | VFS tests | `blk-test` | Block tests |
| `net-test` | Network tests | `shell-test` | Shell tests |
| `init-status` | Init status | | |

### Phase 2 (SMP, MM, Security)

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `smp-sched` | Per-CPU queue status | `mm-stats` | Per-process memory |
| `mm-cow` | Copy-on-write pages | `sec-status` | SMEP/SMAP/NX/canary |
| `journal` | WAL entries | `jsync` | Flush journal |
| `fsck` | FS integrity check | `perf` | Performance counters |
| `test-all` | All kernel tests | | |

### Phase 3 (GUI, Apps, Hardware)

| Command | Description | Command | Description |
|---------|-------------|---------|-------------|
| `fb-test` | Framebuffer test | `mouse-test` | Mouse input test |
| `gui-test` | Compositor test | `editor-test` | Text editor test |
| `fjc-test` | Compiler test | `pkg-list` | Package listing |
| `hw-detect` | Hardware report | | |

### Utilities

`echo`, `clear`/`cls`, `calc`, `hex`, `base`, `seq`, `fib`, `factor`, `prime`, `sort`, `uniq`, `tr`, `cut`, `nl`, `rev`, `md5`, `xxd`, `sleep`, `history`, `cowsay`, `fortune`, `dice`, `banner`, `reboot`, `shutdown`

## 4. Architecture

```
Ring 0 (kernel/core/)     ~2,500 LOC    Scheduler, MM, IPC, syscall, IRQ
Ring 3 (services/)        user-space    Init, VFS, BLK, NET, Shell, Display, Input, GUI
Ring 3 (apps/)            user-space    Editor, Compiler, Package Manager, MNIST
```

### Service PIDs

| PID | Service | Annotation | Role |
|-----|---------|------------|------|
| 0 | Kernel | `@kernel` | Scheduler, MM, IPC, syscall dispatch |
| 1 | Init | `@safe` | Spawn + monitor services, respawn on crash |
| 2 | BLK | `@device` | NVMe + USB block device access |
| 3 | VFS | `@safe` | Filesystem: RamFS, FAT32, /dev, /proc |
| 4 | NET | `@device` | Virtio-net, ARP, IPv4, ICMP, UDP, TCP |
| 5 | Shell | `@safe` | Interactive shell, 160+ commands |
| 6 | Display | `@device` | Framebuffer, VGA, GPU compositor |
| 7 | Input | `@device` | Keyboard + PS/2 mouse |
| 8 | GUI | `@safe` | Window manager, widgets |

### IPC Message Flow (`cat /mnt/nvme/hello.txt`)

```
Shell(5) --SYS_CALL--> VFS(3) --SYS_CALL--> BLK(2) --SYS_PORT_IO--> Kernel(0)
         <--reply----         <--reply----          <--IRQ wake----
```

4 hops, target <10us.

## 5. Building for Hardware

**QEMU:** `make run` (serial), `make run-kvm` (fast), `make run-net` (networking).

**Real x86_64:** `make iso` creates `build/fajaros.iso`. Write to USB with `dd`, boot via GRUB menu.

**Radxa Dragon Q6A (ARM64):** Cross-compile `fj` for aarch64, then build on Q6A:
```bash
cargo build --release --target aarch64-unknown-linux-gnu
scp target/aarch64-unknown-linux-gnu/release/fj radxa@192.168.50.94:~/
# On Q6A: ./fj build --target aarch64-none combined.fj -o fajaros.elf
```

---
*FajarOS Nova v2.0 "Sovereignty" -- compiler-enforced safety, microkernel IPC, 160+ commands*
