#!/usr/bin/env bash
# Test: 'Create tracker subtasks' config key in CLAUDE.md and docs/reference/automation-config.md
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
AUTOCONFIG="$REPO_ROOT/docs/reference/automation-config.md"

# -----------------------------------------------------------------------
# 'Create tracker subtasks' key present in CLAUDE.md config contract
# -----------------------------------------------------------------------
if [ ! -f "$CLAUDE_MD" ]; then
  fail "CLAUDE.md not found"
else
  if ! grep -q 'Create tracker subtasks' "$CLAUDE_MD" 2>/dev/null; then
    fail "'Create tracker subtasks' key not found in CLAUDE.md"
  fi

  # -----------------------------------------------------------------------
  # The key must appear in or after the Decomposition section
  # -----------------------------------------------------------------------
  DECOMP_LINE=$(grep -n 'Decomposition' "$CLAUDE_MD" | grep -v '#\|---' | head -1 | cut -d: -f1 || true)
  KEY_LINE=$(grep -n 'Create tracker subtasks' "$CLAUDE_MD" | head -1 | cut -d: -f1 || true)

  if [ -z "$DECOMP_LINE" ]; then
    fail "Decomposition section not found in CLAUDE.md config contract"
  elif [ -n "$KEY_LINE" ] && [ "$KEY_LINE" -lt "$DECOMP_LINE" ]; then
    fail "'Create tracker subtasks' (line $KEY_LINE) appears before Decomposition section (line $DECOMP_LINE)"
  fi

  # -----------------------------------------------------------------------
  # Default must be 'enabled'
  # -----------------------------------------------------------------------
  key_line=$(grep 'Create tracker subtasks' "$CLAUDE_MD" | grep 'enabled\|disabled' | head -1 || true)
  if ! contains "$key_line" "enabled"; then
    fail "'Create tracker subtasks' entry in CLAUDE.md does not show default value 'enabled'"
  fi
fi

# -----------------------------------------------------------------------
# 'Create tracker subtasks' key present in docs/reference/automation-config.md
# -----------------------------------------------------------------------
if [ ! -f "$AUTOCONFIG" ]; then
  fail "docs/reference/automation-config.md not found"
else
  if ! grep -q 'Create tracker subtasks' "$AUTOCONFIG" 2>/dev/null; then
    fail "'Create tracker subtasks' key not found in docs/reference/automation-config.md"
  fi

  # -----------------------------------------------------------------------
  # Must mention both 'enabled' and 'disabled' values
  # -----------------------------------------------------------------------
  key_context=$(grep -A5 'Create tracker subtasks' "$AUTOCONFIG" 2>/dev/null | head -6 || true)
  if ! contains "$key_context" "enabled"; then
    fail "'Create tracker subtasks' in automation-config.md does not document 'enabled' value"
  fi
  if ! contains "$key_context" "disabled"; then
    fail "'Create tracker subtasks' in automation-config.md does not document 'disabled' value"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: 'Create tracker subtasks' config key present with correct defaults in CLAUDE.md and docs/reference/automation-config.md"
exit "$FAIL"
