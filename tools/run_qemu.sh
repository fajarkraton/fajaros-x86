#!/bin/bash
# FajarOS Nova — Run in QEMU x86_64
# Usage: ./tools/run_qemu.sh [--kvm] [--vga] [--smp N] [--debug]

KERNEL="build/fajaros.elf"
QEMU="qemu-system-x86_64"
ARGS="-serial stdio -no-reboot -no-shutdown -m 512M"

# Default: no graphics, serial only
DISPLAY_ARG="-nographic"
CPU_ARG="-cpu qemu64,+avx2,+sse4.2"

while [[ $# -gt 0 ]]; do
    case $1 in
        --kvm)
            CPU_ARG="-enable-kvm -cpu host"
            shift
            ;;
        --vga)
            DISPLAY_ARG=""
            shift
            ;;
        --smp)
            ARGS="$ARGS -smp $2"
            shift 2
            ;;
        --debug)
            ARGS="$ARGS -s -S"
            echo "GDB server on :1234 — connect with:"
            echo "  gdb -ex 'target remote :1234' -ex 'symbol-file $KERNEL'"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ ! -f "$KERNEL" ]; then
    echo "Kernel not found: $KERNEL"
    echo "Run 'make build' first"
    exit 1
fi

echo "Booting FajarOS Nova..."
exec $QEMU -kernel $KERNEL $CPU_ARG $ARGS $DISPLAY_ARG
