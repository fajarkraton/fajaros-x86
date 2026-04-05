/* FajarOS Nova v3.0 "Nusantara" — x86_64 Boot Startup
   Custom startup assembly for manual/advanced builds.
   For standard builds, `fj build --no-std` auto-generates equivalent startup.

   Boot sequence:
     1. GRUB/QEMU loads us in 32-bit protected mode (Multiboot2)
     2. 32-bit trampoline: set up page tables, enable long mode
     3. Far jump to 64-bit code
     4. Zero BSS, set stack, init serial
     5. CPUID feature detection
     6. Call kernel_main()

   Build: as --64 -o startup.o boot/startup.S
   Link:  ld -T linker.ld -o kernel.elf startup.o program.o
*/

.intel_syntax noprefix

/* ═══════════════════════════════════════════════════════════════════
   Multiboot2 Header — must be within first 32KB of kernel image
   Magic: 0xE85250D6, Architecture: 0 (i386/x86_64)
   ═══════════════════════════════════════════════════════════════════ */
.section .multiboot_header, "a"
.align 8
multiboot_header_start:
    .long   0xE85250D6                                          /* magic */
    .long   0                                                    /* architecture: i386 */
    .long   multiboot_header_end - multiboot_header_start       /* header length */
    .long   -(0xE85250D6 + 0 + (multiboot_header_end - multiboot_header_start))  /* checksum */

    /* Address tag (type=2): load at 1MB */
    .align  8
    .short  2                   /* type = address */
    .short  0                   /* flags */
    .long   24                  /* size */
    .long   multiboot_header_start  /* header_addr */
    .long   0x100000            /* load_addr (1MB) */
    .long   0                   /* load_end_addr (entire file) */
    .long   0                   /* bss_end_addr */

    /* Entry address tag (type=3): jump to _start */
    .align  8
    .short  3                   /* type = entry_addr */
    .short  0                   /* flags */
    .long   12                  /* size */
    .long   _start              /* entry_addr (32-bit) */

    /* Framebuffer tag (type=5): request 1024x768x32 */
    .align  8
    .short  5                   /* type = framebuffer */
    .short  0                   /* flags */
    .long   20                  /* size */
    .long   1024                /* width */
    .long   768                 /* height */
    .long   32                  /* depth (bpp) */

    /* End tag */
    .align  8
    .short  0
    .short  0
    .long   8
multiboot_header_end:

/* ═══════════════════════════════════════════════════════════════════
   32-bit Entry Point
   GRUB loads us in 32-bit protected mode. We must transition to
   64-bit long mode: set up page tables, enable PAE+LME, far jump.

   Encoded as raw .byte because we're assembling as ELF64 but this
   code runs in 32-bit mode.
   ═══════════════════════════════════════════════════════════════════ */
.section .text.start, "ax"
.global _start
.type _start, @function

_start:
    /* cli */
    .byte 0xFA
    /* mov esp, 0x00200000 (temporary stack at 2MB) */
    .byte 0xBC, 0x00, 0x00, 0x20, 0x00
    /* mov edi, ebx (save Multiboot2 info pointer) */
    .byte 0x89, 0xDF

    /* --- Early serial: "[BOOT32]\n" to COM1 (0x3F8) --- */
    .byte 0x66, 0xBA, 0xF8, 0x03   /* mov dx, 0x3F8 */
    .byte 0xB0, 0x5B, 0xEE         /* '[' */
    .byte 0xB0, 0x42, 0xEE         /* 'B' */
    .byte 0xB0, 0x4F, 0xEE         /* 'O' */
    .byte 0xB0, 0x4F, 0xEE         /* 'O' */
    .byte 0xB0, 0x54, 0xEE         /* 'T' */
    .byte 0xB0, 0x33, 0xEE         /* '3' */
    .byte 0xB0, 0x32, 0xEE         /* '2' */
    .byte 0xB0, 0x5D, 0xEE         /* ']' */
    .byte 0xB0, 0x0A, 0xEE         /* '\n' */

    /* --- Zero 12KB at 0x70000 for page tables --- */
    /* PML4=0x70000, PDPT=0x71000, PD=0x72000 */
    .byte 0x31, 0xC0               /* xor eax, eax */
    .byte 0xBF, 0x00, 0x00, 0x07, 0x00  /* mov edi, 0x70000 */
    .byte 0xB9, 0x00, 0x0C, 0x00, 0x00  /* mov ecx, 0xC00 (3072 dwords) */
    .byte 0xFC, 0xF3, 0xAB         /* cld; rep stosd */

    /* --- Identity map first 128MB with 2MB huge pages --- */
    /* PML4[0] -> PDPT at 0x71000 */
    .byte 0xB8, 0x00, 0x00, 0x07, 0x00  /* mov eax, 0x70000 */
    .byte 0xC7, 0x00, 0x07, 0x10, 0x07, 0x00  /* mov [eax], 0x71007 */

    /* PDPT[0] -> PD at 0x72000 */
    .byte 0xB8, 0x00, 0x10, 0x07, 0x00  /* mov eax, 0x71000 */
    .byte 0xC7, 0x00, 0x07, 0x20, 0x07, 0x00  /* mov [eax], 0x72007 */

    /* Fill PD[0..63] with 2MB pages: 0x0 - 0x7FFFFFF */
    .byte 0xB8, 0x00, 0x20, 0x07, 0x00  /* mov eax, 0x72000 */
    .byte 0xB9, 0x00, 0x00, 0x00, 0x00  /* mov ecx, 0 */
.Lpd_loop:
    .byte 0x89, 0xCA               /* mov edx, ecx */
    .byte 0xC1, 0xE2, 0x15         /* shl edx, 21 (counter * 2MB) */
    .byte 0x81, 0xCA, 0x87, 0x00, 0x00, 0x00  /* or edx, 0x87 (P+W+U+PS) */
    .byte 0x89, 0x14, 0xC8         /* mov [eax+ecx*8], edx */
    .byte 0xC7, 0x44, 0xC8, 0x04, 0x00, 0x00, 0x00, 0x00  /* mov [eax+ecx*8+4], 0 */
    .byte 0x83, 0xC1, 0x01         /* add ecx, 1 */
    .byte 0x83, 0xF9, 0x40         /* cmp ecx, 64 */
    .byte 0x72, 0xE2               /* jb .Lpd_loop */

    /* --- Load CR3 with PML4 --- */
    .byte 0xB8, 0x00, 0x00, 0x07, 0x00  /* mov eax, 0x70000 */
    .byte 0x0F, 0x22, 0xD8         /* mov cr3, eax */

    /* --- Enable PAE (CR4.PAE = bit 5) --- */
    .byte 0x0F, 0x20, 0xE0         /* mov eax, cr4 */
    .byte 0x83, 0xC8, 0x20         /* or eax, 0x20 */
    .byte 0x0F, 0x22, 0xE0         /* mov cr4, eax */

    /* --- Enable long mode (EFER.LME = bit 8) --- */
    .byte 0xB9, 0x80, 0x00, 0x00, 0xC0  /* mov ecx, 0xC0000080 */
    .byte 0x0F, 0x32               /* rdmsr */
    .byte 0x0D, 0x00, 0x01, 0x00, 0x00  /* or eax, 0x100 */
    .byte 0x0F, 0x30               /* wrmsr */

    /* --- Enable paging (CR0.PG = bit 31) --- */
    .byte 0x0F, 0x20, 0xC0         /* mov eax, cr0 */
    .byte 0x0D, 0x00, 0x00, 0x00, 0x80  /* or eax, 0x80000000 */
    .byte 0x0F, 0x22, 0xC0         /* mov cr0, eax */

    /* --- Load GDT and far jump to 64-bit --- */
    .byte 0x0F, 0x01, 0x15         /* lgdt [__gdt64_ptr] */
    .long __gdt64_ptr
    .byte 0xEA                     /* jmp far 0x08:_start64 */
    .long _start64
    .word 0x0008

/* GDT: null + kcode + kdata + udata + ucode + TSS (2 slots) */
/* SYSCALL STAR: [47:32]=0x08 (kCS,kSS), [63:48]=0x10 (uSS-8,uCS-16) */
/* -> SYSCALL: CS=0x08, SS=0x10 | SYSRET: CS=0x20|3, SS=0x18|3 */
.align 16
__gdt64:
    .quad 0x0000000000000000    /* 0x00: Null */
    .quad 0x00AF9A000000FFFF    /* 0x08: Kernel Code (DPL=0, L=1, exec/read) */
    .quad 0x00CF92000000FFFF    /* 0x10: Kernel Data (DPL=0, read/write) */
    .quad 0x00CFF2000000FFFF    /* 0x18: User Data (DPL=3, read/write) */
    .quad 0x00AFFA000000FFFF    /* 0x20: User Code (DPL=3, L=1, exec/read) */
    .quad 0x0000000000000000    /* 0x28: TSS low (runtime init) */
    .quad 0x0000000000000000    /* 0x30: TSS high */
__gdt64_ptr:
    .word __gdt64_ptr - __gdt64 - 1
    .long __gdt64

/* ═══════════════════════════════════════════════════════════════════
   64-bit Entry — long mode active
   ═══════════════════════════════════════════════════════════════════ */
.code64
_start64:
    /* Reload segment registers */
    mov     ax, 0x10
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax

    /* Set stack from linker script symbol */
    lea     rsp, [rip + __stack_top]

    /* Save Multiboot2 info pointer */
    mov     r12, rdi
    mov     QWORD PTR [0x6FF00], rdi

    /* --- Zero BSS section --- */
    lea     rdi, [rip + __bss_start]
    lea     rcx, [rip + __bss_end]
    sub     rcx, rdi
    shr     rcx, 3              /* count in qwords */
    xor     eax, eax
    cld
    rep     stosq

    /* --- Initialize COM1 serial (115200 baud, 8N1) --- */
    mov     dx, 0x3F9
    xor     al, al
    out     dx, al              /* IER: disable interrupts */

    mov     dx, 0x3FB
    mov     al, 0x80
    out     dx, al              /* LCR: enable DLAB */

    mov     dx, 0x3F8
    mov     al, 0x01
    out     dx, al              /* DLL: divisor 1 (115200 baud) */

    mov     dx, 0x3F9
    xor     al, al
    out     dx, al              /* DLH: 0 */

    mov     dx, 0x3FB
    mov     al, 0x03
    out     dx, al              /* LCR: 8N1, DLAB off */

    mov     dx, 0x3FA
    mov     al, 0xC7
    out     dx, al              /* FCR: enable FIFO, 14-byte */

    mov     dx, 0x3FC
    mov     al, 0x0B
    out     dx, al              /* MCR: RTS + DTR + OUT2 */

    /* --- Print boot banner --- */
    lea     rdi, [rip + .Lbanner]
    mov     rsi, .Lbanner_end - .Lbanner
    call    fj_serial_print

    /* --- CPUID feature detection --- */
    /* Check for CPUID support (toggle EFLAGS bit 21) */
    pushfq
    pop     rax
    mov     rbx, rax
    xor     rax, 0x200000       /* flip ID bit */
    push    rax
    popfq
    pushfq
    pop     rax
    push    rbx
    popfq                       /* restore original flags */
    xor     rax, rbx
    test    rax, 0x200000
    jz      .Lno_cpuid

    /* CPUID leaf 1: feature flags */
    mov     eax, 1
    cpuid
    /* ECX has SSE3, POPCNT, AES, AVX, RDRAND */
    /* EDX has FPU, SSE, SSE2 */
    mov     DWORD PTR [0x6FF10], ecx    /* save feature flags ECX */
    mov     DWORD PTR [0x6FF14], edx    /* save feature flags EDX */

    /* CPUID leaf 7: extended features (AVX2, etc.) */
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    mov     DWORD PTR [0x6FF18], ebx    /* save extended features */

    /* Print "[CPUID] OK\n" */
    lea     rdi, [rip + .Lcpuid_ok]
    mov     rsi, .Lcpuid_ok_end - .Lcpuid_ok
    call    fj_serial_print
    jmp     .Lcpuid_done

.Lno_cpuid:
    lea     rdi, [rip + .Lcpuid_no]
    mov     rsi, .Lcpuid_no_end - .Lcpuid_no
    call    fj_serial_print

.Lcpuid_done:
    /* --- Call kernel entry point --- */
    call    kernel_main

    /* Should never return */
.Lhalt:
    cli
    hlt
    jmp     .Lhalt

.size _start, . - _start

/* Boot banner strings */
.Lbanner:
    .ascii  "\n[FajarOS Nova v3.0 \"Nusantara\"]\n"
    .ascii  "[BOOT64] Long mode active\n"
.Lbanner_end:

.Lcpuid_ok:
    .ascii  "[CPUID] Feature detection OK\n"
.Lcpuid_ok_end:

.Lcpuid_no:
    .ascii  "[CPUID] Not available!\n"
.Lcpuid_no_end:

/* ═══════════════════════════════════════════════════════════════════
   Helper: serial print (used before kernel is running)
   rdi = buffer ptr, rsi = length
   ═══════════════════════════════════════════════════════════════════ */
fj_serial_print:
    test    rdi, rdi
    jz      .Lsp_done
    test    rsi, rsi
    jle     .Lsp_done
    mov     rcx, rsi
    mov     r8, rdi
.Lsp_loop:
    mov     dx, 0x3FD
.Lsp_wait:
    in      al, dx
    test    al, 0x20            /* TX empty? */
    jz      .Lsp_wait
    mov     dx, 0x3F8
    mov     al, [r8]
    out     dx, al
    inc     r8
    dec     rcx
    jnz     .Lsp_loop
.Lsp_done:
    ret

/* ═══════════════════════════════════════════════════════════════════
   Runtime stubs — these symbols are referenced by compiled .fj code.
   The compiler auto-generates equivalent functions, but these are
   provided for manual build scenarios.
   ═══════════════════════════════════════════════════════════════════ */

/* fj_rt_bare_print(ptr: rdi, len: rsi) */
.global fj_rt_bare_print
.type fj_rt_bare_print, @function
fj_rt_bare_print:
    jmp     fj_serial_print
.size fj_rt_bare_print, . - fj_rt_bare_print

/* fj_rt_bare_println(ptr: rdi, len: rsi) */
.global fj_rt_bare_println
.type fj_rt_bare_println, @function
fj_rt_bare_println:
    call    fj_serial_print
    mov     dx, 0x3FD
.Lpl_wait:
    in      al, dx
    test    al, 0x20
    jz      .Lpl_wait
    mov     dx, 0x3F8
    mov     al, 0x0A
    out     dx, al
    ret
.size fj_rt_bare_println, . - fj_rt_bare_println

/* fj_rt_bare_print_i64(val: rdi) */
.global fj_rt_bare_print_i64
.type fj_rt_bare_print_i64, @function
fj_rt_bare_print_i64:
    push    rbx
    push    r12
    sub     rsp, 24
    mov     r12, rdi
    lea     rbx, [rsp + 20]
    mov     byte ptr [rbx], 0x0A

    test    r12, r12
    jnz     .Lpi_notzero
    dec     rbx
    mov     byte ptr [rbx], 0x30
    jmp     .Lpi_print
.Lpi_notzero:
    mov     rax, r12
    test    rax, rax
    jns     .Lpi_pos
    neg     rax
.Lpi_pos:
.Lpi_dloop:
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    add     dl, 0x30
    dec     rbx
    mov     [rbx], dl
    test    rax, rax
    jnz     .Lpi_dloop
    test    r12, r12
    jns     .Lpi_print
    dec     rbx
    mov     byte ptr [rbx], 0x2D
.Lpi_print:
    mov     rdi, rbx
    lea     rsi, [rsp + 21]
    sub     rsi, rbx
    call    fj_serial_print
    add     rsp, 24
    pop     r12
    pop     rbx
    ret
.size fj_rt_bare_print_i64, . - fj_rt_bare_print_i64

/* fj_rt_bare_halt() -> noreturn */
.global fj_rt_bare_halt
.type fj_rt_bare_halt, @function
fj_rt_bare_halt:
    cli
    hlt
    jmp     fj_rt_bare_halt
.size fj_rt_bare_halt, . - fj_rt_bare_halt

/* fj_rt_bare_panic() -> noreturn */
.global fj_rt_bare_panic
.type fj_rt_bare_panic, @function
fj_rt_bare_panic:
    lea     rdi, [rip + .Lpanic_msg]
    mov     rsi, 19
    call    fj_serial_print
    jmp     fj_rt_bare_halt
.Lpanic_msg:
    .ascii  "PANIC: kernel halt\n"
.size fj_rt_bare_panic, . - fj_rt_bare_panic

/* fj_rt_bare_memcpy(dst: rdi, src: rsi, n: rdx) -> rax=dst */
.global fj_rt_bare_memcpy
.type fj_rt_bare_memcpy, @function
fj_rt_bare_memcpy:
    mov     rax, rdi
    mov     rcx, rdx
    cld
    rep     movsb
    ret
.size fj_rt_bare_memcpy, . - fj_rt_bare_memcpy

/* fj_rt_bare_memset(dst: rdi, val: rsi, n: rdx) -> rax=dst */
.global fj_rt_bare_memset
.type fj_rt_bare_memset, @function
fj_rt_bare_memset:
    mov     rax, rdi
    mov     rcx, rdx
    mov     al, sil
    cld
    rep     stosb
    mov     rax, rdi
    ret
.size fj_rt_bare_memset, . - fj_rt_bare_memset

/* fj_rt_bare_memory_fence() */
.global fj_rt_bare_memory_fence
.type fj_rt_bare_memory_fence, @function
fj_rt_bare_memory_fence:
    mfence
    ret
.size fj_rt_bare_memory_fence, . - fj_rt_bare_memory_fence

/* Port I/O */
.global fj_rt_bare_port_outb
.type fj_rt_bare_port_outb, @function
fj_rt_bare_port_outb:
    mov     dx, di
    mov     al, sil
    out     dx, al
    xor     eax, eax
    ret
.size fj_rt_bare_port_outb, . - fj_rt_bare_port_outb

.global fj_rt_bare_port_inb
.type fj_rt_bare_port_inb, @function
fj_rt_bare_port_inb:
    mov     dx, di
    xor     eax, eax
    in      al, dx
    ret
.size fj_rt_bare_port_inb, . - fj_rt_bare_port_inb

/* Volatile memory access */
.global fj_rt_volatile_write
.type fj_rt_volatile_write, @function
fj_rt_volatile_write:
    mov     [rdi], rsi
    ret
.size fj_rt_volatile_write, . - fj_rt_volatile_write

.global fj_rt_volatile_read
.type fj_rt_volatile_read, @function
fj_rt_volatile_read:
    mov     rax, [rdi]
    ret
.size fj_rt_volatile_read, . - fj_rt_volatile_read
