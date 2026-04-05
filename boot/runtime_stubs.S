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
