#!/usr/bin/env bash
# Install git hooks for fajaros-x86 repo.
# V26 Phase B2.5 deliverable — mirrors fajar-lang scripts/install-git-hooks.sh
# pattern (commits 6775e44 + 0fdf477 in fajar-lang) but adapted for the
# fajaros-x86 .fj kernel codebase.
#
# V29.P1.P3 refactor: hook content lives in scripts/git-hooks/pre-commit
# as a real file (single source of truth). This installer simply copies
# the file into .git/hooks/ — no more heredoc drift between the installer
# and the tracked hook source.
#
# Installs pre-commit hook with five checks:
#   1. make build-llvm succeeds (kernel must always compile, including
#      the V29.P1 silent-build-failure gate in Makefile build-llvm)
#   2. No new @unsafe annotations without a `// SAFETY:` comment nearby
#   3. No new TODO comments without a severity tag (P0/P1/P2/P3)
#   4. Memory-map region collisions blocked (V28.5)
#   5. Makefile silent-build-failure gate must not be removed (V29.P1)
#
# Run from repo root: bash scripts/install-git-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK_SRC="$REPO_ROOT/scripts/git-hooks/pre-commit"
HOOK_FILE="$HOOK_DIR/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
    echo "❌ Source hook missing: $HOOK_SRC"
    echo "   Expected scripts/git-hooks/pre-commit to exist in the repo."
    exit 1
fi

mkdir -p "$HOOK_DIR"
cp "$HOOK_SRC" "$HOOK_FILE"
chmod +x "$HOOK_FILE"

echo "✅ pre-commit hook installed at $HOOK_FILE"
echo "   Source: $HOOK_SRC"
echo ""
echo "   Five checks enforced:"
echo "     1. make build-llvm succeeds (when .fj/Makefile/.S/.ld staged)"
echo "     2. New @unsafe annotations have // SAFETY: comment within 3 lines"
echo "     3. New TODO comments have severity tag (P0/P1/P2/P3)"
echo "     4. Memory map region overlaps (V28.5)"
echo "     5. Makefile silent-build-failure gate intact (V29.P1)"
echo ""
echo "   Test the hook manually with: bash $HOOK_FILE"
echo "   Bypass with: git commit --no-verify  (DISCOURAGED — see CLAUDE.md §6)"
