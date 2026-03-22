# Contributing to FajarOS Nova

Thank you for your interest in contributing to FajarOS Nova, an x86_64 microkernel
operating system written entirely in Fajar Lang.

## Prerequisites

- **Fajar Lang compiler** (`fj`) v4.1.0 or later
- **GNU Make** 4.0+
- **QEMU** 8.0+ with `qemu-system-x86_64`
- **GRUB** and `xorriso` for ISO generation
- Optional: Radxa Dragon Q6A board for ARM64 cross-testing

## Building

```bash
# Build the kernel + all services
make

# Build and run in QEMU
make run

# Build ISO image
make iso
```

## Code Structure

| Directory   | Purpose                                      |
|-------------|----------------------------------------------|
| `kernel/`   | Microkernel core (IPC, scheduler, memory, syscall, security) |
| `services/` | Userspace services (VFS, BLK, NET, shell)    |
| `apps/`     | Userspace applications                       |
| `drivers/`  | Hardware drivers (NVMe, USB, virtio, framebuffer) |
| `shell/`    | Shell implementation and built-in commands   |
| `fs/`       | Filesystem implementations (FAT32, ramfs, journaling) |
| `tests/`    | Test harnesses and test scripts              |
| `tools/`    | Build and utility scripts                    |
| `docs/`     | Architecture docs, sprint plans, specs       |

## Coding Style

All kernel code follows these rules:

- **All kernel functions use `@kernel` annotation** -- no heap allocation, no tensor ops
- **Hardware access via `volatile_read` / `volatile_write`** -- never raw pointer dereference
- **No `.unwrap()`** in any production code -- return errors explicitly
- **50 lines max per function** -- split into helpers if longer
- **`snake_case`** for functions and variables, **`SCREAMING_CASE`** for constants
- **Every `@unsafe` block must have a `// SAFETY:` comment** explaining why it is safe

## Context Annotations

FajarOS enforces strict context isolation at compile time:

| Annotation | Ring | Usage                              | Restrictions              |
|------------|------|------------------------------------|---------------------------|
| `@kernel`  | 0    | Kernel core, interrupt handlers    | No heap, no tensor        |
| `@device`  | 0/3  | Hardware drivers, device access    | No raw pointers, no IRQ   |
| `@safe`    | 3    | Userspace services and apps        | No hardware, no raw ptrs  |
| `@unsafe`  | 0    | Low-level boot, context switch     | Full access (use sparingly) |

The compiler rejects cross-context violations. A `@safe` function cannot call
`port_write` and a `@kernel` function cannot allocate heap memory.

## Testing

```bash
# Run QEMU-based kernel tests
make test

# Run the full test suite from the shell (inside QEMU)
test-all

# ARM64 cross-testing on Radxa Dragon Q6A
fj run tests/arm64_harness.fj
```

All pull requests must pass the test suite before merging. If you add a new
kernel function, add at least one corresponding test.

## Pull Request Process

1. **Branch from `main`** -- use `feat/description` or `fix/description` naming
2. **Write tests first** -- follow TDD (red, green, refactor)
3. **Run the full test suite** -- `make test` must pass
4. **Update documentation** -- if you change syscall numbers, IPC protocol, or shell commands
5. **One concern per PR** -- keep changes focused and reviewable
6. **Commit messages** -- use `type(scope): description` format
   (e.g., `feat(ipc): add endpoint capability checking`)

## Error Code Naming

| Prefix | Category         | Example               |
|--------|------------------|-----------------------|
| `KE`   | Kernel error     | KE001 HeapAllocInKernel |
| `SE`   | Semantic error   | SE004 TypeMismatch    |
| `DE`   | Device error     | DE001 RawPointerInDevice |
| `RE`   | Runtime error    | RE003 StackOverflow   |
| `ME`   | Memory error     | ME001 UseAfterMove    |
| `IE`   | IPC error        | IE001 EndpointFull    |

When adding new error codes, follow the existing numbering scheme and document
them in `docs/ERROR_CODES.md`.

## License

By contributing, you agree that your contributions will be licensed under the
same license as the project (see `LICENSE`).
