#!/bin/bash
# FajarOS Nova — Create Bootable ISO with GRUB2
# Output: build/fajaros.iso

set -e

KERNEL="build/fajaros.elf"
ISO="build/fajaros.iso"
ISO_DIR="build/iso"

if [ ! -f "$KERNEL" ]; then
    echo "Error: Kernel not found: $KERNEL"
    echo "Run 'make build' first"
    exit 1
fi

# Check dependencies
for cmd in grub-mkrescue xorriso; do
    if ! command -v $cmd &>/dev/null; then
        echo "Error: $cmd not found. Install with:"
        echo "  sudo apt install grub-pc-bin grub-common xorriso mtools"
        exit 1
    fi
done

# Create ISO directory structure
mkdir -p "$ISO_DIR/boot/grub"
cp "$KERNEL" "$ISO_DIR/boot/fajaros.elf"
cp grub.cfg "$ISO_DIR/boot/grub/grub.cfg"

# Create ISO
grub-mkrescue -o "$ISO" "$ISO_DIR" 2>/dev/null

echo "ISO created: $ISO"
echo "Boot with: qemu-system-x86_64 -cdrom $ISO -serial stdio"
echo "Or write to USB: sudo dd if=$ISO of=/dev/sdX bs=4M status=progress"
