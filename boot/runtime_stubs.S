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

/* fj_rt_bare_idt_init() -> rax=0 (stub — IDT setup done in .fj) */
.weak fj_rt_bare_idt_init
.type fj_rt_bare_idt_init, @function
fj_rt_bare_idt_init:
    xor     rax, rax
    ret
.size fj_rt_bare_idt_init, . - fj_rt_bare_idt_init

/* fj_rt_bare_pit_init() -> rax=0 (stub — PIT setup done in .fj) */
.weak fj_rt_bare_pit_init
.type fj_rt_bare_pit_init, @function
fj_rt_bare_pit_init:
    xor     rax, rax
    ret
.size fj_rt_bare_pit_init, . - fj_rt_bare_pit_init

/* fj_rt_bare_tss_init() -> rax=0 (stub — TSS setup done in .fj) */
.weak fj_rt_bare_tss_init
.type fj_rt_bare_tss_init, @function
fj_rt_bare_tss_init:
    xor     rax, rax
    ret
.size fj_rt_bare_tss_init, . - fj_rt_bare_tss_init
