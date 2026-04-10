/* FajarOS Nova v3.0 — Bare-Metal Runtime Stubs for LLVM Backend
   These symbols are referenced by compiled .fj code via fj_rt_bare_* calls.
   Linked with the kernel .o to produce the final ELF.

   Build: as --64 -o runtime_stubs.o boot/runtime_stubs.S
   Link:  ld -T linker.ld startup.o combined.o runtime_stubs.o -o kernel.elf
*/

.intel_syntax noprefix

/* ═══════════════════════════════════════════════════════════════════
   Console Output — VGA text buffer at 0xB8000 (80x25, 16-bit cells)
   Each cell: [char:8][attr:8], attr = fg | (bg << 4)
   ═══════════════════════════════════════════════════════════════════ */

.section .data
.align 8
vga_cursor_pos:
    .quad 0                     /* Current cursor position (0-1999) */

.section .text

/* fj_rt_bare_console_putchar(char: rdi) -> void
   Write one character to VGA text buffer with white-on-black attribute.
   Handles newline by advancing to next row. */
.global fj_rt_bare_console_putchar
.type fj_rt_bare_console_putchar, @function
fj_rt_bare_console_putchar:
    push    rbx
    mov     rbx, QWORD PTR [rip + vga_cursor_pos]

    /* Handle newline */
    cmp     dil, 0x0A
    jne     .Lputc_normal
    /* Advance to start of next line: pos = ((pos / 80) + 1) * 80 */
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 80
    div     rcx                 /* rax = row */
    inc     rax
    imul    rax, 80
    mov     rbx, rax
    jmp     .Lputc_scroll

.Lputc_normal:
    /* Write char + attribute at VGA address */
    mov     rax, 0xB8000
    lea     rdx, [rax + rbx * 2]
    mov     BYTE PTR [rdx], dil     /* character */
    mov     BYTE PTR [rdx + 1], 0x0F   /* white on black */
    inc     rbx

.Lputc_scroll:
    /* Scroll if past bottom (pos >= 2000) */
    cmp     rbx, 2000
    jl      .Lputc_done
    /* Simple scroll: reset to line 24 start */
    mov     rbx, 1920              /* row 24, col 0 */

.Lputc_done:
    mov     QWORD PTR [rip + vga_cursor_pos], rbx
    pop     rbx
    ret
.size fj_rt_bare_console_putchar, . - fj_rt_bare_console_putchar

/* ═══════════════════════════════════════════════════════════════════
   String Operations — operate on null-terminated C strings (ptr as i64)
   ═══════════════════════════════════════════════════════════════════ */

/* fj_rt_bare_str_len(ptr: rdi) -> rax = length */
.global fj_rt_bare_str_len
.type fj_rt_bare_str_len, @function
fj_rt_bare_str_len:
    xor     rax, rax
    test    rdi, rdi
    jz      .Lslen_done
.Lslen_loop:
    cmp     BYTE PTR [rdi + rax], 0
    je      .Lslen_done
    inc     rax
    cmp     rax, 65536          /* safety limit */
    jl      .Lslen_loop
.Lslen_done:
    ret
.size fj_rt_bare_str_len, . - fj_rt_bare_str_len

/* fj_rt_bare_str_byte_at(ptr: rdi, idx: rsi) -> rax = byte */
.global fj_rt_bare_str_byte_at
.type fj_rt_bare_str_byte_at, @function
fj_rt_bare_str_byte_at:
    xor     rax, rax
    test    rdi, rdi
    jz      .Lsbat_done
    movzx   eax, BYTE PTR [rdi + rsi]
.Lsbat_done:
    ret
.size fj_rt_bare_str_byte_at, . - fj_rt_bare_str_byte_at

/* ═══════════════════════════════════════════════════════════════════
   Buffer Read/Write — Little-Endian and Big-Endian Memory Access
   All take address in rdi, value (for write) in rsi
   ═══════════════════════════════════════════════════════════════════ */

/* --- Little-Endian Reads (native on x86) --- */

/* fj_rt_bare_buffer_read_u16_le(addr: rdi) -> rax */
.global fj_rt_bare_buffer_read_u16_le
.type fj_rt_bare_buffer_read_u16_le, @function
fj_rt_bare_buffer_read_u16_le:
    xor     rax, rax
    mov     ax, WORD PTR [rdi]
    ret
.size fj_rt_bare_buffer_read_u16_le, . - fj_rt_bare_buffer_read_u16_le

/* fj_rt_bare_buffer_read_u32_le(addr: rdi) -> rax */
.global fj_rt_bare_buffer_read_u32_le
.type fj_rt_bare_buffer_read_u32_le, @function
fj_rt_bare_buffer_read_u32_le:
    xor     rax, rax
    mov     eax, DWORD PTR [rdi]
    ret
.size fj_rt_bare_buffer_read_u32_le, . - fj_rt_bare_buffer_read_u32_le

/* fj_rt_bare_buffer_read_u64_le(addr: rdi) -> rax */
.global fj_rt_bare_buffer_read_u64_le
.type fj_rt_bare_buffer_read_u64_le, @function
fj_rt_bare_buffer_read_u64_le:
    mov     rax, QWORD PTR [rdi]
    ret
.size fj_rt_bare_buffer_read_u64_le, . - fj_rt_bare_buffer_read_u64_le

/* --- Big-Endian Reads (byte-swap on x86) --- */

/* fj_rt_bare_buffer_read_u16_be(addr: rdi) -> rax */
.global fj_rt_bare_buffer_read_u16_be
.type fj_rt_bare_buffer_read_u16_be, @function
fj_rt_bare_buffer_read_u16_be:
    xor     rax, rax
    mov     ax, WORD PTR [rdi]
    xchg    al, ah              /* byte swap 16-bit */
    ret
.size fj_rt_bare_buffer_read_u16_be, . - fj_rt_bare_buffer_read_u16_be

/* fj_rt_bare_buffer_read_u32_be(addr: rdi) -> rax */
.global fj_rt_bare_buffer_read_u32_be
.type fj_rt_bare_buffer_read_u32_be, @function
fj_rt_bare_buffer_read_u32_be:
    xor     rax, rax
    mov     eax, DWORD PTR [rdi]
    bswap   eax                 /* byte swap 32-bit */
    ret
.size fj_rt_bare_buffer_read_u32_be, . - fj_rt_bare_buffer_read_u32_be

/* --- Little-Endian Writes (native on x86) --- */

/* fj_rt_bare_buffer_write_u16_le(addr: rdi, val: rsi) -> rax=0 */
.global fj_rt_bare_buffer_write_u16_le
.type fj_rt_bare_buffer_write_u16_le, @function
fj_rt_bare_buffer_write_u16_le:
    mov     WORD PTR [rdi], si
    xor     rax, rax
    ret
.size fj_rt_bare_buffer_write_u16_le, . - fj_rt_bare_buffer_write_u16_le

/* fj_rt_bare_buffer_write_u32_le(addr: rdi, val: rsi) -> rax=0 */
.global fj_rt_bare_buffer_write_u32_le
.type fj_rt_bare_buffer_write_u32_le, @function
fj_rt_bare_buffer_write_u32_le:
    mov     DWORD PTR [rdi], esi
    xor     rax, rax
    ret
.size fj_rt_bare_buffer_write_u32_le, . - fj_rt_bare_buffer_write_u32_le

/* --- Big-Endian Writes (byte-swap on x86) --- */

/* fj_rt_bare_buffer_write_u16_be(addr: rdi, val: rsi) -> rax=0 */
.global fj_rt_bare_buffer_write_u16_be
.type fj_rt_bare_buffer_write_u16_be, @function
fj_rt_bare_buffer_write_u16_be:
    mov     ax, si
    xchg    al, ah
    mov     WORD PTR [rdi], ax
    xor     rax, rax
    ret
.size fj_rt_bare_buffer_write_u16_be, . - fj_rt_bare_buffer_write_u16_be

/* fj_rt_bare_buffer_write_u32_be(addr: rdi, val: rsi) -> rax=0 */
.global fj_rt_bare_buffer_write_u32_be
.type fj_rt_bare_buffer_write_u32_be, @function
fj_rt_bare_buffer_write_u32_be:
    mov     eax, esi
    bswap   eax
    mov     DWORD PTR [rdi], eax
    xor     rax, rax
    ret
.size fj_rt_bare_buffer_write_u32_be, . - fj_rt_bare_buffer_write_u32_be

/* ════════════════════════════════════════════════════════════════════
   Missing stubs — added to resolve all 24 bare-metal symbols
   ════════════════════════════════════════════════════════════════════ */

/* fj_rt_bare_print_i64(val: rdi) -> void
   Print integer to serial port (COM1: 0x3F8) as decimal */
.weak fj_rt_bare_print_i64
.type fj_rt_bare_print_i64, @function
fj_rt_bare_print_i64:
    /* Simple: convert to decimal, output each digit to serial */
    push    rbx
    push    rcx
    mov     rax, rdi
    test    rax, rax
    jns     .pi64_positive
    /* Negative: print '-' and negate */
    push    rax
    mov     al, '-'
    mov     dx, 0x3F8
    out     dx, al
    pop     rax
    neg     rax
.pi64_positive:
    mov     rcx, rsp
    sub     rsp, 24
    mov     rbx, 10
.pi64_loop:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     rcx
    mov     BYTE PTR [rcx], dl
    test    rax, rax
    jnz     .pi64_loop
    /* Output digits */
    mov     dx, 0x3F8
.pi64_out:
    mov     al, BYTE PTR [rcx]
    out     dx, al
    inc     rcx
    cmp     rcx, rsp
    jb      .pi64_out
    add     rsp, 24
    pop     rcx
    pop     rbx
    ret
.size fj_rt_bare_print_i64, . - fj_rt_bare_print_i64

/* fj_rt_bare_pci_read32(bus_dev_fn_reg: rdi) -> rax = value */
.weak fj_rt_bare_pci_read32
.type fj_rt_bare_pci_read32, @function
fj_rt_bare_pci_read32:
    mov     eax, edi
    or      eax, 0x80000000     /* Enable bit */
    mov     dx, 0xCF8
    out     dx, eax
    mov     dx, 0xCFC
    in      eax, dx
    ret
.size fj_rt_bare_pci_read32, . - fj_rt_bare_pci_read32

/* fj_rt_bare_pci_write32(bus_dev_fn_reg: rdi, value: rsi) */
.weak fj_rt_bare_pci_write32
.type fj_rt_bare_pci_write32, @function
fj_rt_bare_pci_write32:
    mov     eax, edi
    or      eax, 0x80000000
    mov     dx, 0xCF8
    out     dx, eax
    mov     eax, esi
    mov     dx, 0xCFC
    out     dx, eax
    xor     rax, rax
    ret
.size fj_rt_bare_pci_write32, . - fj_rt_bare_pci_write32

/* fj_rt_bare_memcpy_buf(dst: rdi, src: rsi, len: rdx) -> rax=0 */
.weak fj_rt_bare_memcpy_buf
.type fj_rt_bare_memcpy_buf, @function
fj_rt_bare_memcpy_buf:
    mov     rcx, rdx
    rep     movsb
    xor     rax, rax
    ret
.size fj_rt_bare_memcpy_buf, . - fj_rt_bare_memcpy_buf

/* fj_rt_bare_memset_buf(dst: rdi, val: rsi, len: rdx) -> rax=0 */
.weak fj_rt_bare_memset_buf
.type fj_rt_bare_memset_buf, @function
fj_rt_bare_memset_buf:
    mov     rcx, rdx
    mov     rax, rsi
    rep     stosb
    xor     rax, rax
    ret
.size fj_rt_bare_memset_buf, . - fj_rt_bare_memset_buf

/* fj_rt_bare_read_timer_ticks() -> rax = rdtsc value */
.weak fj_rt_bare_read_timer_ticks
.type fj_rt_bare_read_timer_ticks, @function
fj_rt_bare_read_timer_ticks:
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    ret
.size fj_rt_bare_read_timer_ticks, . - fj_rt_bare_read_timer_ticks

/* fj_rt_bare_set_current_pid(pid: rdi) -> rax=0
   Store PID at kernel data area (0x6FA00) */
.weak fj_rt_bare_set_current_pid
.type fj_rt_bare_set_current_pid, @function
fj_rt_bare_set_current_pid:
    mov     QWORD PTR [0x6FA00], rdi
    xor     rax, rax
    ret
.size fj_rt_bare_set_current_pid, . - fj_rt_bare_set_current_pid

/* fj_rt_bare_x86_serial_init() -> rax=0
   Initialize COM1 (0x3F8) at 115200 baud */
.weak fj_rt_bare_x86_serial_init
.type fj_rt_bare_x86_serial_init, @function
fj_rt_bare_x86_serial_init:
    mov     dx, 0x3F9       /* IER: disable interrupts */
    xor     al, al
    out     dx, al
    mov     dx, 0x3FB       /* LCR: enable DLAB */
    mov     al, 0x80
    out     dx, al
    mov     dx, 0x3F8       /* Divisor low: 1 (115200 baud) */
    mov     al, 1
    out     dx, al
    mov     dx, 0x3F9       /* Divisor high: 0 */
    xor     al, al
    out     dx, al
    mov     dx, 0x3FB       /* LCR: 8N1, DLAB off */
    mov     al, 0x03
    out     dx, al
    mov     dx, 0x3FC       /* MCR: DTR + RTS + OUT2 */
    mov     al, 0x0B
    out     dx, al
    xor     rax, rax
    ret
.size fj_rt_bare_x86_serial_init, . - fj_rt_bare_x86_serial_init

/* fj_rt_bare_acpi_shutdown() -> never returns
   ACPI S5 shutdown via QEMU/Bochs I/O port 0x604 */
.weak fj_rt_bare_acpi_shutdown
.type fj_rt_bare_acpi_shutdown, @function
fj_rt_bare_acpi_shutdown:
    mov     dx, 0x604
    mov     ax, 0x2000
    out     dx, ax
    hlt
    jmp     fj_rt_bare_acpi_shutdown
.size fj_rt_bare_acpi_shutdown, . - fj_rt_bare_acpi_shutdown

/* fj_rt_bare_pic_remap() -> rax=0
   Remap PIC to IRQ 32-47 */
.weak fj_rt_bare_pic_remap
.type fj_rt_bare_pic_remap, @function
fj_rt_bare_pic_remap:
    mov     al, 0x11        /* ICW1: init + ICW4 needed */
    out     0x20, al
    out     0xA0, al
    mov     al, 0x20        /* ICW2: PIC1 offset 32 */
    out     0x21, al
    mov     al, 0x28        /* ICW2: PIC2 offset 40 */
    out     0xA1, al
    mov     al, 4           /* ICW3: PIC1 has slave on IRQ2 */
    out     0x21, al
    mov     al, 2           /* ICW3: PIC2 cascade identity */
    out     0xA1, al
    mov     al, 1           /* ICW4: 8086 mode */
    out     0x21, al
    out     0xA1, al
    mov     al, 0xFB        /* Mask all except IRQ2 (cascade) */
    out     0x21, al
    mov     al, 0xFF
    out     0xA1, al
    xor     rax, rax
    ret
.size fj_rt_bare_pic_remap, . - fj_rt_bare_pic_remap

/* ═══════════════════════════════════════════════════════════════════
   Phase 2: IDT + TSS + PIT — Real Interrupt Infrastructure

   Memory layout:
     0xA50000  IDT       (256 × 16 = 4096 bytes)
     0xA51000  IDTR      (10 bytes: 2 limit + 8 base)
     0xA52000  TSS       (104 bytes)
     0xA53000  IST1 base (4KB double-fault stack)
     0xA54000  IST1 top
     0xA54008  Global tick counter (8 bytes)
   ═══════════════════════════════════════════════════════════════════ */

/* ─── Exception Stub Macros ──────────────────────────────────────── */
/* Vectors WITH CPU error code: 8,10,11,12,13,14,17,21,29,30        */
/* All others in 0-31: no error code — push dummy 0                  */

.macro ISR_NOERR vec
__isr_\vec :
    push    0
    push    \vec
    jmp     __isr_common
.endm

.macro ISR_ERR vec
__isr_\vec :
    push    \vec
    jmp     __isr_common
.endm

/* ─── Exception Stubs (vectors 0–31) ────────────────────────────── */

ISR_NOERR 0                     /* #DE  Divide Error */
ISR_NOERR 1                     /* #DB  Debug */
ISR_NOERR 2                     /* NMI */
ISR_NOERR 3                     /* #BP  Breakpoint */
ISR_NOERR 4                     /* #OF  Overflow */
ISR_NOERR 5                     /* #BR  Bound Range */
ISR_NOERR 6                     /* #UD  Invalid Opcode */
ISR_NOERR 7                     /* #NM  Device Not Available */
ISR_ERR   8                     /* #DF  Double Fault */
ISR_NOERR 9                     /* Coprocessor Segment (legacy) */
ISR_ERR   10                    /* #TS  Invalid TSS */
ISR_ERR   11                    /* #NP  Segment Not Present */
ISR_ERR   12                    /* #SS  Stack-Segment Fault */
ISR_ERR   13                    /* #GP  General Protection */
ISR_ERR   14                    /* #PF  Page Fault */
ISR_NOERR 15                    /* Reserved */
ISR_NOERR 16                    /* #MF  x87 FP Exception */
ISR_ERR   17                    /* #AC  Alignment Check */
ISR_NOERR 18                    /* #MC  Machine Check */
ISR_NOERR 19                    /* #XM  SIMD FP Exception */
ISR_NOERR 20                    /* #VE  Virtualization */
ISR_ERR   21                    /* #CP  Control Protection */
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28                    /* #HV  Hypervisor Injection */
ISR_ERR   29                    /* #VC  VMM Communication */
ISR_ERR   30                    /* #SX  Security Exception */
ISR_NOERR 31                    /* Reserved */

/* ─── Common Exception Handler ──────────────────────────────────── */
/* Stack on entry from stub:                                         */
/*   [rsp+0]  vector   [rsp+8] error_code   [rsp+16] RIP            */
/*   [rsp+24] CS       [rsp+32] RFLAGS                               */
/*   [rsp+40] RSP (Ring 3)   [rsp+48] SS (Ring 3)                   */

__isr_common:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    rbp
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    /* Frame ptr as arg1 — exception_dispatch reads offsets from it  */
    mov     rdi, rsp
    call    exception_dispatch

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax

    add     rsp, 16             /* skip vector + error code */
    iretq

/* ─── Timer ISR (vector 32 = PIT IRQ0) ──────────────────────────── */
/* Phase 4: Full context-switch timer ISR                               */
/* Save 15 GPRs → call timer_tick_handler(rsp) → switch stack → iretq  */
.global __isr_32_timer
__isr_32_timer:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    rbp
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rdi, rsp                /* arg0 = saved stack pointer */
    call    timer_tick_handler      /* returns new_rsp in rax     */
    mov     rsp, rax                /* switch to (possibly new) stack */

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    iretq

/* ─── SYS_EXIT scheduler trampoline ─────────────────────────────── */
/* Called via jmp [0xA54010].  Marks process ZOMBIE, switches to next */
.global __sched_exit
__sched_exit:
    /* Current PID → FREE (for reuse) */
    mov     rax, QWORD PTR [0x6FE00]
    mov     rcx, rax
    shl     rcx, 8                  /* pid * 256 */
    add     rcx, 0x890000           /* PROC_TABLE base */
    mov     QWORD PTR [rcx], 0     /* PROC_STATE_FREE */

    /* Set PID = 0 (kernel) */
    mov     QWORD PTR [0x6FE00], 0

    /* Restore kernel page table (PML4 at 0x70000) */
    mov     rax, 0x70000
    mov     cr3, rax

    /* Load kernel stack (top of PID 0's kernel stack area) */
    /* KSTACK_BASE(0x900000) + (0+1)*KSTACK_SIZE(0x10000) = 0x910000 */
    mov     rsp, 0x910000

    /* Print "\nnova> " directly via serial */
    mov     dx, 0x3F8
    mov     al, 10
    out     dx, al
    mov     al, 110             /* 'n' */
    out     dx, al
    mov     al, 111             /* 'o' */
    out     dx, al
    mov     al, 118             /* 'v' */
    out     dx, al
    mov     al, 97              /* 'a' */
    out     dx, al
    mov     al, 62              /* '>' */
    out     dx, al
    mov     al, 32              /* ' ' */
    out     dx, al

    /* Reset cmdbuf: clear len at 0x6F7F8 */
    mov     QWORD PTR [0x6F7F8], 0

    /* Re-enable interrupts */
    sti

    /* Call Fajar Lang shell loop handler (never returns) */
    call    fj_exec_exit_handler
    cli
    hlt

.Lse_switch_to_process:
    /* Activate next process (PID > 0) */
    mov     QWORD PTR [0x6FE00], rax
    mov     rcx, rax
    shl     rcx, 8
    add     rcx, 0x890000
    mov     QWORD PTR [rcx], 2     /* PROC_STATE_RUNNING */

    /* Load saved RSP (offset 40) */
    mov     rsp, QWORD PTR [rcx + 40]

    /* Load CR3 (offset 48) — skip if same */
    mov     rdx, QWORD PTR [rcx + 48]
    mov     rdi, cr3
    cmp     rdx, rdi
    je      .Lse_nocr3
    mov     cr3, rdx
.Lse_nocr3:

    /* Update TSS RSP0 = KSTACK_BASE + (pid+1)*KSTACK_SIZE */
    mov     rdx, rax
    inc     rdx
    shl     rdx, 16                /* (pid+1) * 0x10000 */
    add     rdx, 0x900000          /* KSTACK_BASE */
    mov     QWORD PTR [0xA52004], rdx

    /* LAPIC EOI + PIC EOI (safety) */
    mov     rdx, 0xFEE000B0
    mov     DWORD PTR [rdx], 0
    mov     al, 0x20
    out     0x20, al

    /* Restore context from next process's stack */
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    iretq

/* ─── PIC IRQ Stubs ─────────────────────────────────────────────── */
/* Master PIC (vectors 33-39 = IRQ1-7): EOI master only              */
__irq_master_stub:
    push    rax
    mov     al, 0x20
    out     0x20, al
    pop     rax
    iretq

/* Slave PIC (vectors 40-47 = IRQ8-15): EOI slave then master       */
__irq_slave_stub:
    push    rax
    mov     al, 0x20
    out     0xA0, al
    out     0x20, al
    pop     rax
    iretq

/* ─── Default + Spurious Handlers ───────────────────────────────── */
__isr_default:
    iretq

__isr_spurious:
    iretq

/* ─── ISR Address Table (vectors 0-31) ──────────────────────────── */
.section .rodata
.align 8
__isr_table:
    .quad __isr_0,  __isr_1,  __isr_2,  __isr_3
    .quad __isr_4,  __isr_5,  __isr_6,  __isr_7
    .quad __isr_8,  __isr_9,  __isr_10, __isr_11
    .quad __isr_12, __isr_13, __isr_14, __isr_15
    .quad __isr_16, __isr_17, __isr_18, __isr_19
    .quad __isr_20, __isr_21, __isr_22, __isr_23
    .quad __isr_24, __isr_25, __isr_26, __isr_27
    .quad __isr_28, __isr_29, __isr_30, __isr_31
.section .text

/* ─── Serial Output Helper (local) ─────────────────────────────── */
/* rdi = buffer, rsi = length.  Busy-waits on COM1 TX ready.         */
__serial_out:
    test    rsi, rsi
    jle     .Lso_ret
.Lso_lp:
    mov     dx, 0x3FD
.Lso_wt:
    in      al, dx
    test    al, 0x20
    jz      .Lso_wt
    mov     dx, 0x3F8
    mov     al, BYTE PTR [rdi]
    out     dx, al
    inc     rdi
    dec     rsi
    jnz     .Lso_lp
.Lso_ret:
    ret

/* ─── IDT Gate Installer ────────────────────────────────────────── */
/* rdi = vector  rsi = handler addr  edx = type_attr  ecx = IST     */
__install_idt_gate:
    mov     rax, rdi
    shl     rax, 4              /* vector × 16 */
    add     rax, 0xA50000

    mov     WORD PTR [rax],      si         /* offset [15:0]   */
    mov     WORD PTR [rax + 2],  0x0008     /* kernel CS       */
    mov     BYTE PTR [rax + 4],  cl         /* IST             */
    mov     BYTE PTR [rax + 5],  dl         /* type/attr       */
    mov     r8, rsi
    shr     r8, 16
    mov     WORD PTR [rax + 6],  r8w        /* offset [31:16]  */
    shr     r8, 16
    mov     DWORD PTR [rax + 8], r8d        /* offset [63:32]  */
    mov     DWORD PTR [rax + 12], 0         /* reserved        */
    ret

/* ═══════════════════════════════════════════════════════════════════
   fj_rt_bare_idt_init() — Build 256-entry IDT and execute LIDT
   ═══════════════════════════════════════════════════════════════════ */
.global fj_rt_bare_idt_init
.type fj_rt_bare_idt_init, @function
fj_rt_bare_idt_init:
    push    rbx
    push    r12
    push    r13

    /* 1. Zero IDT area (4096 bytes) + tick counter */
    mov     rdi, 0xA50000
    xor     eax, eax
    mov     rcx, 512            /* 4096 / 8 */
    cld
    rep     stosq
    mov     QWORD PTR [0xA54008], 0

    /* 2. Exception handlers (vectors 0-31) from address table */
    lea     r12, [rip + __isr_table]
    xor     r13d, r13d
.Lidt_exc:
    mov     rdi, r13
    mov     rsi, QWORD PTR [r12 + r13 * 8]
    mov     edx, 0x8E           /* P=1 DPL=0 interrupt gate */
    xor     ecx, ecx
    call    __install_idt_gate
    inc     r13
    cmp     r13, 32
    jb      .Lidt_exc

    /* Double fault (vec 8) on IST1 — separate stack if kernel RSP corrupt */
    mov     rdi, 8
    lea     rsi, [rip + __isr_8]
    mov     edx, 0x8E
    mov     ecx, 1              /* IST = 1 */
    call    __install_idt_gate

    /* 3. Timer ISR (vector 32 = IRQ0 after PIC remap) */
    mov     rdi, 32
    lea     rsi, [rip + __isr_32_timer]
    mov     edx, 0x8E
    xor     ecx, ecx
    call    __install_idt_gate

    /* 4. Master PIC IRQs — vectors 33-39 */
    mov     r13, 33
.Lidt_mpic:
    mov     rdi, r13
    lea     rsi, [rip + __irq_master_stub]
    mov     edx, 0x8E
    xor     ecx, ecx
    call    __install_idt_gate
    inc     r13
    cmp     r13, 40
    jb      .Lidt_mpic

    /* 5. Slave PIC IRQs — vectors 40-47 */
.Lidt_spic:
    mov     rdi, r13
    lea     rsi, [rip + __irq_slave_stub]
    mov     edx, 0x8E
    xor     ecx, ecx
    call    __install_idt_gate
    inc     r13
    cmp     r13, 48
    jb      .Lidt_spic

    /* 6. Default handler — vectors 48-254 */
    mov     r13, 48
.Lidt_def:
    mov     rdi, r13
    lea     rsi, [rip + __isr_default]
    mov     edx, 0x8E
    xor     ecx, ecx
    call    __install_idt_gate
    inc     r13
    cmp     r13, 255
    jb      .Lidt_def

    /* 7. Spurious (vector 255) */
    mov     rdi, 255
    lea     rsi, [rip + __isr_spurious]
    mov     edx, 0x8E
    xor     ecx, ecx
    call    __install_idt_gate

    /* 8. Set up IDTR and load */
    mov     rdi, 0xA51000
    mov     WORD PTR [rdi], 0x0FFF          /* limit = 4095 */
    mov     QWORD PTR [rdi + 2], 0xA50000   /* base  */
    lidt    [rdi]

    /* 9. Store __sched_exit address at 0xA54010 for SYS_EXIT trampoline */
    lea     rax, [rip + __sched_exit]
    mov     QWORD PTR [0xA54010], rax

    /* 10. Serial confirmation */
    lea     rdi, [rip + .Lidt_msg]
    mov     rsi, .Lidt_msg_end - .Lidt_msg
    call    __serial_out

    pop     r13
    pop     r12
    pop     rbx
    xor     eax, eax
    ret
.Lidt_msg:      .ascii  "[IDT] 256 entries loaded\n"
.Lidt_msg_end:
.size fj_rt_bare_idt_init, . - fj_rt_bare_idt_init

/* ═══════════════════════════════════════════════════════════════════
   fj_rt_bare_tss_init() — TSS at 0xA52000, RSP0=0x7EF000, LTR 0x28
   ═══════════════════════════════════════════════════════════════════ */
.global fj_rt_bare_tss_init
.type fj_rt_bare_tss_init, @function
fj_rt_bare_tss_init:
    push    rbx

    /* 1. Zero TSS area (128 bytes) */
    mov     rdi, 0xA52000
    xor     eax, eax
    mov     rcx, 16             /* 128 / 8 */
    cld
    rep     stosq

    /* 2. RSP0 — kernel stack for Ring 3→0 transitions */
    mov     QWORD PTR [0xA52004], 0x7EF000      /* TSS+4  = RSP0 */

    /* 3. IST1 — separate 4KB stack for #DF (top of 0xA53000..0xA54000) */
    mov     QWORD PTR [0xA52024], 0xA54000       /* TSS+36 = IST1 */

    /* 4. I/O map base past end of TSS = no I/O bitmap */
    mov     WORD PTR [0xA52066], 104              /* TSS+102 */

    /* 5. Patch GDT slots 0x28/0x30 with TSS descriptor */
    sub     rsp, 16
    sgdt    [rsp]
    mov     rbx, QWORD PTR [rsp + 2]    /* GDT base address */
    add     rsp, 16

    /* TSS descriptor: base=0x00A52000, limit=103 (0x67) */
    lea     rdi, [rbx + 0x28]
    mov     WORD PTR [rdi],      0x0067  /* limit [15:0]            */
    mov     WORD PTR [rdi + 2],  0x2000  /* base  [15:0]            */
    mov     BYTE PTR [rdi + 4],  0xA5    /* base  [23:16]           */
    mov     BYTE PTR [rdi + 5],  0x89    /* P=1 DPL=0 Type=9 (TSS) */
    mov     BYTE PTR [rdi + 6],  0x00    /* limit [19:16] + flags   */
    mov     BYTE PTR [rdi + 7],  0x00    /* base  [31:24]           */
    mov     DWORD PTR [rdi + 8],  0      /* base  [63:32]           */
    mov     DWORD PTR [rdi + 12], 0      /* reserved                */

    /* 6. Load task register */
    mov     ax, 0x28
    ltr     ax

    /* 7. Serial confirmation */
    lea     rdi, [rip + .Ltss_msg]
    mov     rsi, .Ltss_msg_end - .Ltss_msg
    call    __serial_out

    pop     rbx
    xor     eax, eax
    ret
.Ltss_msg:      .ascii  "[TSS] RSP0=0x7EF000 loaded\n"
.Ltss_msg_end:
.size fj_rt_bare_tss_init, . - fj_rt_bare_tss_init

/* ═══════════════════════════════════════════════════════════════════
   fj_rt_bare_pit_init(freq_hz: rdi) — PIT channel 0, mode 2
   ═══════════════════════════════════════════════════════════════════ */
.global fj_rt_bare_pit_init
.type fj_rt_bare_pit_init, @function
fj_rt_bare_pit_init:
    /* divisor = 1193182 / freq_hz */
    mov     rax, 1193182
    xor     rdx, rdx
    div     rdi
    mov     rcx, rax

    /* channel 0, access lo/hi, mode 2 (rate generator) */
    mov     al, 0x34
    out     0x43, al

    /* send divisor low then high byte */
    mov     al, cl
    out     0x40, al
    mov     al, ch
    out     0x40, al

    /* Serial confirmation */
    push    rcx
    lea     rdi, [rip + .Lpit_msg]
    mov     rsi, .Lpit_msg_end - .Lpit_msg
    call    __serial_out
    pop     rcx

    xor     eax, eax
    ret
.Lpit_msg:      .ascii  "[PIT] Timer configured\n"
.Lpit_msg_end:
.size fj_rt_bare_pit_init, . - fj_rt_bare_pit_init
