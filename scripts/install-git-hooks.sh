#!/usr/bin/env bash
# Install git hooks for fajaros-x86 repo.
# V26 Phase B2.5 deliverable — mirrors fajar-lang scripts/install-git-hooks.sh
# pattern (commits 6775e44 + 0fdf477 in fajar-lang) but adapted for the
# fajaros-x86 .fj kernel codebase.
#
# Installs pre-commit hook with three checks:
#   1. make build-llvm succeeds (kernel must always compile)
#   2. No new @unsafe annotations without a `// SAFETY:` comment nearby
#   3. No new TODO comments without a severity tag (P0/P1/P2/P3)
#
# Run from repo root: bash scripts/install-git-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK_FILE="$HOOK_DIR/pre-commit"

mkdir -p "$HOOK_DIR"

cat > "$HOOK_FILE" <<'HOOK'
#!/usr/bin/env bash
# fajaros-x86 pre-commit hook — V26 Phase B2.5
#
# Rejects commits that:
#   1. Break `make build-llvm` (kernel must always compile)
#   2. Add new @unsafe annotations without a `// SAFETY:` comment
#   3. Add new TODO comments without a severity tag (P0/P1/P2/P3)
#
# Bypass with --no-verify if absolutely necessary (discouraged — leaves
# the kernel in an unverified state). Per CLAUDE.md §6 + V26 §B2.5.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ─────────────────────────────────────────────────────────────────
# Detect what kinds of files are staged
# ─────────────────────────────────────────────────────────────────
STAGED_ALL=$(git diff --cached --name-only --diff-filter=ACMR || true)
STAGED_FJ=$(echo "$STAGED_ALL" | grep -E '\.fj$' || true)
STAGED_BUILD=$(echo "$STAGED_ALL" | grep -E '\.(fj|S|ld)$|^Makefile$' || true)

# ─────────────────────────────────────────────────────────────────
# Check 1: make build-llvm (skip if nothing build-affecting is staged)
# ─────────────────────────────────────────────────────────────────
if [ -n "$STAGED_BUILD" ]; then
    printf '[1/3] make build-llvm ... '
    if ! make build-llvm > /tmp/fajaros_precommit_build.log 2>&1; then
        echo "❌"
        echo ""
        echo "make build-llvm failed. Last 25 lines:"
        echo "─────────────────────────────────────────────────────────"
        tail -25 /tmp/fajaros_precommit_build.log
        echo "─────────────────────────────────────────────────────────"
        echo "Full log: /tmp/fajaros_precommit_build.log"
        exit 1
    fi
    echo "✅"
else
    echo "[1/3] make build-llvm ... SKIPPED (no .fj/Makefile/.S/.ld changes)"
fi

# ─────────────────────────────────────────────────────────────────
# Check 2: @unsafe annotations require // SAFETY: comment
# Looks at ADDED lines only (not the whole file), so existing
# violations don't block unrelated commits.
# ─────────────────────────────────────────────────────────────────
if [ -n "$STAGED_FJ" ]; then
    printf '[2/3] @unsafe needs // SAFETY: ... '
    UNSAFE_VIOLATIONS=0
    UNSAFE_REPORT=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ -f "$f" ] || continue
        # Get unified diff with 2 lines of context so we can see preceding comments
        DIFF=$(git diff --cached -U2 -- "$f" 2>/dev/null || true)
        # Walk added lines (lines starting with + but not +++ headers)
        # For each added @unsafe line, check that the preceding 3 lines
        # (in the same diff hunk) contain // SAFETY:
        ADDED_LINENOS=$(echo "$DIFF" | grep -nE '^\+[^+]' | grep -E '@unsafe' | cut -d: -f1 || true)
        for ln in $ADDED_LINENOS; do
            # Look at lines (ln-3) to (ln-1) in the diff for SAFETY comment
            START=$((ln - 3))
            [ $START -lt 1 ] && START=1
            CONTEXT=$(echo "$DIFF" | sed -n "${START},${ln}p")
            if ! echo "$CONTEXT" | grep -qE '//\s*SAFETY:'; then
                UNSAFE_VIOLATIONS=$((UNSAFE_VIOLATIONS + 1))
                BAD_LINE=$(echo "$DIFF" | sed -n "${ln}p")
                UNSAFE_REPORT="$UNSAFE_REPORT  $f: $BAD_LINE
"
            fi
        done
    done <<< "$STAGED_FJ"
    if [ "$UNSAFE_VIOLATIONS" -gt 0 ]; then
        echo "❌"
        echo ""
        echo "$UNSAFE_VIOLATIONS new @unsafe annotation(s) without preceding // SAFETY: comment:"
        printf '%s' "$UNSAFE_REPORT"
        echo ""
        echo "Add a '// SAFETY: <reason>' comment within 3 lines above each @unsafe."
        echo "See CLAUDE.md §6 for the safety convention."
        exit 1
    fi
    echo "✅"
else
    echo "[2/3] @unsafe SAFETY ... SKIPPED (no .fj changes)"
fi

# ─────────────────────────────────────────────────────────────────
# Check 3: New TODOs require P0/P1/P2/P3 severity tag
# Same approach: only flag ADDED TODO lines, not pre-existing ones.
# ─────────────────────────────────────────────────────────────────
if [ -n "$STAGED_FJ" ]; then
    printf '[3/3] TODOs need P0/P1/P2/P3 severity ... '
    TODO_VIOLATIONS=0
    TODO_REPORT=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ -f "$f" ] || continue
        # Get added lines (no context needed — severity must be on same line as TODO)
        ADDED=$(git diff --cached -U0 -- "$f" 2>/dev/null | grep -E '^\+[^+]' || true)
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if echo "$line" | grep -qE '\bTODO\b'; then
                if ! echo "$line" | grep -qE 'P[0-3]\b'; then
                    TODO_VIOLATIONS=$((TODO_VIOLATIONS + 1))
                    TODO_REPORT="$TODO_REPORT  $f: ${line#+}
"
                fi
            fi
        done <<< "$ADDED"
    done <<< "$STAGED_FJ"
    if [ "$TODO_VIOLATIONS" -gt 0 ]; then
        echo "❌"
        echo ""
        echo "$TODO_VIOLATIONS new TODO(s) without severity tag (P0/P1/P2/P3):"
        printf '%s' "$TODO_REPORT"
        echo ""
        echo "Add a severity tag inline, e.g.:"
        echo "  // TODO P0: critical bug, blocks production"
        echo "  // TODO P1: leak / correctness issue, fix this sprint"
        echo "  // TODO P2: hardening / nice-to-have"
        echo "  // TODO P3: cosmetic / refactor"
        exit 1
    fi
    echo "✅"
else
    echo "[3/3] TODO severity ... SKIPPED (no .fj changes)"
fi

echo ""
echo "✅ fajaros-x86 pre-commit OK (build, @unsafe SAFETY, TODO severity)"
HOOK

chmod +x "$HOOK_FILE"

echo "✅ pre-commit hook installed at $HOOK_FILE"
echo ""
echo "   Three checks enforced:"
echo "     1. make build-llvm succeeds (when .fj/Makefile/.S/.ld staged)"
echo "     2. New @unsafe annotations have // SAFETY: comment within 3 lines"
echo "     3. New TODO comments have severity tag (P0/P1/P2/P3)"
echo ""
echo "   Test the hook manually with: bash $HOOK_FILE"
echo "   Bypass with: git commit --no-verify  (DISCOURAGED — see CLAUDE.md §6)"
