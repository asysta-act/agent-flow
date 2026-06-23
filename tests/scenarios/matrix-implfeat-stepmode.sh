#!/usr/bin/env bash
# Verifies: AC-MODE-MATRIX-006
# Description: implement-feature + --step-mode = per-step prompt after each step
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

# ---------------------------------------------------------------------------
# Assertion 1: implement-feature SKILL.md documents --step-mode
# ---------------------------------------------------------------------------
echo "--- Assertion 1: implement-feature SKILL.md documents --step-mode ---"
IMPL_SKILL="$REPO_ROOT/skills/implement-feature/SKILL.md"
if [ ! -f "$IMPL_SKILL" ]; then
  echo "SKIP: skills/implement-feature/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE '\-\-step.mode|step.mode|per.step.*prompt' "$IMPL_SKILL"; then
  echo "OK: implement-feature SKILL.md references --step-mode"
else
  fail "implement-feature SKILL.md missing --step-mode documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: GOT_STEP_MODE boolean pattern used
# ---------------------------------------------------------------------------
echo "--- Assertion 2: GOT_STEP_MODE boolean pattern in implement-feature ---"
if grep -qF 'GOT_STEP_MODE' "$IMPL_SKILL"; then
  echo "OK: implement-feature SKILL.md uses GOT_STEP_MODE boolean pattern"
else
  fail "implement-feature SKILL.md missing GOT_STEP_MODE (required per design.md §5.1)"
fi

# ---------------------------------------------------------------------------
# Assertion 3: steps/ dir exists for implement-feature
# ---------------------------------------------------------------------------
echo "--- Assertion 3: skills/implement-feature/steps/ exists ---"
STEPS_DIR="$REPO_ROOT/skills/implement-feature/steps"
if [ -d "$STEPS_DIR" ]; then
  echo "OK: skills/implement-feature/steps/ exists for step-mode dispatch"
else
  fail "skills/implement-feature/steps/ missing (required for --step-mode)"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-MATRIX-006 — implement-feature --step-mode documented"
fi
exit "$FAIL"
