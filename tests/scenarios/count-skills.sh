#!/usr/bin/env bash
# Verifies: AC-CT-002
# Description: skills/ contains exactly 29 SKILL.md files (not counting steps/ subdirs)
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

EXPECTED_SKILL_COUNT=17

# ---------------------------------------------------------------------------
# Assertion: find skills with explicit -not -path '*/steps/*' guard
# ---------------------------------------------------------------------------
echo "--- Assertion: skills/ has exactly 17 SKILL.md files (excluding steps/) ---"
ACTUAL_COUNT=$(find "$REPO_ROOT/skills" -maxdepth 2 -name 'SKILL.md' -not -path '*/steps/*' -type f | wc -l)

if [ "$ACTUAL_COUNT" -eq "$EXPECTED_SKILL_COUNT" ]; then
  echo "OK: skills/ has $ACTUAL_COUNT SKILL.md files (expected $EXPECTED_SKILL_COUNT)"
else
  fail "skills/ has $ACTUAL_COUNT SKILL.md files — expected $EXPECTED_SKILL_COUNT"
fi

# ---------------------------------------------------------------------------
# Assertion: setup-agents is in the count
# ---------------------------------------------------------------------------
echo "--- Assertion: skills/setup-agents/SKILL.md present ---"
if [ -f "$REPO_ROOT/skills/setup-agents/SKILL.md" ]; then
  echo "OK: skills/setup-agents/SKILL.md exists"
else
  fail "skills/setup-agents/SKILL.md missing — required for 17-skill count"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-CT-002 — skills/ has exactly 17 SKILL.md files"
fi
exit "$FAIL"
