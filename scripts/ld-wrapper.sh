#!/bin/bash
# V30 P3.6: ld wrapper that saves intermediate .o files before linking.
# The C vecmat (vecmat_v8_c.o) needs to be linked AFTER the FJ compilation
# step. This wrapper captures combined.o and combined.start.o so the
# Makefile can relink with the C object.
for arg in "$@"; do
    if [[ "$arg" == *.o ]]; then
        cp "$arg" "${arg}.saved" 2>/dev/null
    fi
done
exec /usr/bin/ld "$@"
