/* FajarOS Nova v3.0 "Nusantara" — Kernel Linker Script
   Target: x86_64 bare-metal (Multiboot2)
   Load address: 1MB (0x100000)
   Stack: 64KB (kernel needs headroom for deep call chains + ISR)
   Page tables: pre-allocated at 0x70000 (set up by startup.S)
*/

ENTRY(_start)

MEMORY
{
    /* Kernel loaded at 1MB by GRUB/QEMU, runs up to 16MB */
    KERNEL (rwx) : ORIGIN = 0x100000, LENGTH = 15M

    /* High memory for heap — 16MB to 512MB */
    HEAP   (rw)  : ORIGIN = 0x1000000, LENGTH = 496M
}

SECTIONS
{
    /* Multiboot2 header MUST be within first 32KB of kernel image */
    .multiboot_header : ALIGN(8)
    {
        KEEP(*(.multiboot_header))
    } > KERNEL

    /* Code — .text.start first (contains _start entry point) */
    .text : ALIGN(4096)
    {
        __text_start = .;
        *(.text.start)
        *(.text .text.*)
        __text_end = .;
    } > KERNEL

    /* Read-only data — page-aligned for NX enforcement */
    .rodata : ALIGN(4096)
    {
        __rodata_start = .;
        *(.rodata .rodata.*)
        __rodata_end = .;
    } > KERNEL

    /* Initialized data */
    .data : ALIGN(4096)
    {
        __data_start = .;
        *(.data .data.*)
        __data_end = .;
    } > KERNEL

    /* Uninitialized data — zeroed by startup.S */
    .bss : ALIGN(4096)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > KERNEL

    /* Kernel stack — 64KB, 16-byte aligned for x86_64 ABI */
    .stack (NOLOAD) : ALIGN(16)
    {
        __stack_bottom = .;
        . += 0x10000;
        __stack_top = .;
    } > KERNEL

    /* Kernel end marker — used by heap allocator to know where free memory starts */
    __kernel_end = .;

    /* Heap starts after kernel image */
    __heap_start = ORIGIN(HEAP);
    __heap_end = ORIGIN(HEAP) + LENGTH(HEAP);

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}

/* Exported symbols for runtime */
PROVIDE(__stack_ptr = __stack_top);
PROVIDE(__kernel_size = __kernel_end - ORIGIN(KERNEL));
