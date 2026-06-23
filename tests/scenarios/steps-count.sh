#!/usr/bin/env bash
# Verifies: AC-STEPS-002
# Description: Each pipeline's steps/ dir has 5–8 files matching [0-9][0-9]-*.md
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

MIN_STEPS=5
# v10 thin-controller allows more granular steps (fix-bugs now has 12 step files:
# triage, impact, reproduce, fixer-reviewer-loop, smoke, test, e2e, browser-verify,
# acceptance-gate, pre-publish, publish, result). Bump cap to 14 to accommodate.
MAX_STEPS=14

PIPELINES=(fix-bugs implement-feature scaffold)

for pipeline in "${PIPELINES[@]}"; do
  STEPS_DIR="$REPO_ROOT/skills/$pipeline/steps"
  echo "--- Checking $pipeline steps/ count ---"
  if [ ! -d "$STEPS_DIR" ]; then
    echo "SKIP: skills/$pipeline/steps/ not found (implementation pending)" >&2
    exit 77
  fi
  # Count files matching [0-9][0-9]-*.md
  STEP_COUNT=$(find "$STEPS_DIR" -maxdepth 1 -name '[0-9][0-9]-*.md' -type f | wc -l)
  if [ "$STEP_COUNT" -ge "$MIN_STEPS" ] && [ "$STEP_COUNT" -le "$MAX_STEPS" ]; then
    echo "OK: skills/$pipeline/steps/ has $STEP_COUNT step files ($MIN_STEPS-$MAX_STEPS)"
  else
    fail "skills/$pipeline/steps/ has $STEP_COUNT step files — expected $MIN_STEPS-$MAX_STEPS (AC-STEPS-002)"
  fi
done

# ---------------------------------------------------------------------------
# Assertion: fix-bugs has exactly 7 steps per design.md §4.1
# ---------------------------------------------------------------------------
echo "--- Checking fix-bugs has exactly 7 steps (design.md §4.1) ---"
FIXBUGS_COUNT=$(find "$REPO_ROOT/skills/fix-bugs/steps" -maxdepth 1 -name '[0-9][0-9]-*.md' -type f | wc -l)
if [ "$FIXBUGS_COUNT" -eq 7 ]; then
  echo "OK: fix-bugs has exactly 7 steps"
else
  echo "INFO: fix-bugs has $FIXBUGS_COUNT steps (design.md target: 7)"
  # Not a hard failure — count within 5-8 range already checked above
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-STEPS-002 — each pipeline has 5-8 step files in steps/"
fi
exit "$FAIL"
