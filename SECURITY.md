# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| v1.4.0 "Zenith" | Yes |
| v1.3.0 | No |
| < v1.3.0 | No |

## Reporting a Vulnerability

If you discover a security vulnerability in FajarOS Nova, please report it responsibly:

**Email:** security@primecore.id

**Response Timeline:**
- **48 hours** — Acknowledgment of report
- **7 days** — Initial assessment and severity classification
- **30 days** — Fix developed and tested

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

**Do NOT** open a public GitHub issue for security vulnerabilities.

## Security Model

FajarOS Nova uses **compiler-enforced privilege isolation**:

| Context | What It Can Do | What the Compiler Rejects |
|---------|---------------|--------------------------|
| `@kernel` | asm!(), port I/O, page tables, MMIO | Heap allocation, tensor ops |
| `@device` | Tensor ops, GPU dispatch, SIMD | Raw pointers, IRQ |
| `@safe` | Syscalls, strings, collections | Raw pointers, hardware access |

This means entire classes of vulnerabilities (kernel memory access from userspace, unauthorized I/O from applications) are **compile-time errors**, not runtime bugs.

## Security Audit

A formal security audit was conducted on 2026-03-25 covering all 34 syscalls and kernel interfaces. Results:

- **7 HIGH** severity findings (buffer bounds, integer overflow)
- **5 MEDIUM** severity findings (permission checks, race conditions)
- **3 LOW** severity findings (truncation, unchecked indices)

All HIGH severity findings have been documented with specific fixes. See `docs/SECURITY_AUDIT_V09.md` in the [fajar-lang](https://github.com/fajarkraton/fajar-lang) repository.

## Hardening Features

- Ring 0/Ring 3 separation via SYSCALL/SYSRET
- NX bit on data pages
- Stack guard pages (unmapped page below stack)
- 12 capability bits for fine-grained access control
- Per-user process limits (fork bomb protection)
- File permissions (rwxrwxrwx model)
