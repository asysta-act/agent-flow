#!/usr/bin/env bash
# Verifies: AC-CT-004 (counts contract)
# Description: core/ has exactly 17 .md files at maxdepth 1
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

EXPECTED_CORE_COUNT=17

echo "--- Assertion: core/ has exactly 17 .md files ---"
ACTUAL_COUNT=$(find "$REPO_ROOT/core" -maxdepth 1 -name '*.md' -type f | wc -l)

if [ "$ACTUAL_COUNT" -eq "$EXPECTED_CORE_COUNT" ]; then
  echo "OK: core/ has $ACTUAL_COUNT .md files (expected $EXPECTED_CORE_COUNT)"
else
  fail "core/ has $ACTUAL_COUNT .md files — expected $EXPECTED_CORE_COUNT"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-CT-004 — core/ has exactly 17 contracts"
fi
exit "$FAIL"
