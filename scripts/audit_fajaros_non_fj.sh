#!/usr/bin/env bash
# audit_fajaros_non_fj.sh — FAJAROS_100PCT_FJ_PLAN prevention layer.
#
# Lists every non-fj source file in the fajaros-x86 kernel build path
# (everything outside the F.11 BitNet TL2 vendoring + scripts/ host
# tooling, which are explicitly out-of-scope per the plan).
#
# Outputs a count line. The count must strictly DECREASE phase by phase
# until it reaches 0 at end of Phase 4.
#
# Per CLAUDE.md §6.8 R3 (prevention layer per phase) — wired into
# `make audit-100pct-fj`.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# Find all .S, .c, .cpp, .asm, .nasm files in the kernel build path.
# Exclude:
#   - target/ (Rust build output)
#   - .git/ (git internals)
#   - build/ (kernel build artifacts)
#   - scripts/ (host tooling, out-of-scope per plan)
NON_FJ=$(find . -type f \( \
        -name "*.S" -o \
        -name "*.c" -o \
        -name "*.cpp" -o \
        -name "*.asm" -o \
        -name "*.nasm" -o \
        -name "*.S.in" \
    \) \
    -not -path "*/target/*" \
    -not -path "*/.git/*" \
    -not -path "*/build/*" \
    -not -path "*/scripts/*" \
    2>/dev/null)

COUNT=$(echo -n "$NON_FJ" | grep -c . || true)

echo "=== FAJAROS_100PCT_FJ_PLAN — non-fj inventory ==="
if [ "$COUNT" -eq 0 ]; then
    echo "[PASS] zero non-fj files in kernel build path."
    echo "       FajarOS kernel + drivers + apps + boot all .fj source."
    exit 0
else
    echo "[INFO] $COUNT non-fj files remaining:"
    echo ""
    while IFS= read -r f; do
        loc=$(wc -l < "$f" 2>/dev/null || echo "?")
        printf "  %4s LOC  %s\n" "$loc" "$f"
    done <<< "$NON_FJ"
    total_loc=$(echo "$NON_FJ" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    echo ""
    echo "  TOTAL: $total_loc LOC"
    echo ""
    echo "Plan progress:"
    echo "  Phase 0 baseline:  3 files, 2,195 LOC (boot/startup.S 515 + boot/runtime_stubs.S 912 + kernel/compute/vecmat_v8.c 768)"
    echo "  Plan target:       0 files, 0 LOC (end of Phase 4)"
    exit 0  # Informational; CI gate is `make audit-100pct-fj-strict`
fi
