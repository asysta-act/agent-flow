#!/bin/bash
# Covers: core/block-handler.md's rollback-exemption sentence ("Do NOT rollback on block
# from `analyst`...") does not reference legacy names triage-analyst or code-analyst.
# Anchored to the sentence's own substring (not a hardcoded line number) so an unrelated
# edit elsewhere in the file cannot silently defeat this check.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FILE="$REPO_ROOT/core/block-handler.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: core/block-handler.md not found"
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

TARGET_LINE=$(grep -F 'Do NOT rollback on block from' "$FILE" || true)

if [ -z "$TARGET_LINE" ]; then
  echo "FAIL: no line found containing 'Do NOT rollback on block from' in core/block-handler.md"
  exit 1
fi

# Target line must still reference analyst (canonical name)
if contains "$TARGET_LINE" "analyst"; then
  echo "PASS: rollback-exemption line references analyst (canonical)"
else
  fail "rollback-exemption line does not reference analyst at all: $TARGET_LINE"
fi

# v7 names must not appear in the target line
if matches_re "$TARGET_LINE" 'triage-analyst|code-analyst'; then
  fail "rollback-exemption line still contains v7 name (triage-analyst or code-analyst): $TARGET_LINE"
else
  echo "PASS: rollback-exemption line does not contain v7 names"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: block-handler.md rollback-exemption line uses canonical names only"
fi
exit "$FAIL"
