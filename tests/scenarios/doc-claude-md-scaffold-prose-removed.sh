#!/usr/bin/env bash
# Verifies: AC-DOC-014b
# Description: CLAUDE.md has ZERO occurrences of v7 scaffold mode descriptor strings:
#   "(a) Interactive", "(b) YOLO with checkpoint", "(c) Full YOLO"
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ]; then
  fail "CLAUDE.md not found"
  exit 1
fi

# ---------------------------------------------------------------------------
# Legacy v7 scaffold mode strings that must be removed
# ---------------------------------------------------------------------------
LEGACY_STRINGS=(
  "(a) Interactive"
  "(b) YOLO with checkpoint"
  "(c) Full YOLO"
)

echo "--- Checking CLAUDE.md for removed v7 scaffold mode strings ---"
for str in "${LEGACY_STRINGS[@]}"; do
  COUNT=$(grep -cF "$str" "$CLAUDE_MD" 2>/dev/null); COUNT=${COUNT:-0}
  if [ "$COUNT" -eq 0 ]; then
    echo "OK: '$str' count = 0 in CLAUDE.md"
  else
    fail "CLAUDE.md has $COUNT occurrence(s) of '$str' (must be 0 per AC-DOC-014b)"
  fi
done

# ---------------------------------------------------------------------------
# Assertion: scaffold section updated to v8 mode descriptions
# ---------------------------------------------------------------------------
echo "--- Assertion: CLAUDE.md scaffold section references new v8 mode flags ---"
if grep -qiE '\-\-yolo|\-\-step.mode' "$CLAUDE_MD"; then
  echo "OK: CLAUDE.md scaffold section references v8 mode flags (--yolo / --step-mode)"
else
  fail "CLAUDE.md scaffold section missing v8 mode flag documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-014b — CLAUDE.md has no v7 scaffold mode strings"
fi
exit "$FAIL"
