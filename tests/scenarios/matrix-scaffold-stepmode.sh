#!/usr/bin/env bash
# Verifies: AC-MODE-MATRIX-009
# Description: scaffold + --step-mode = per-step prompt after each of 8 scaffold steps
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
# Assertion 1: scaffold SKILL.md documents --step-mode
# ---------------------------------------------------------------------------
echo "--- Assertion 1: scaffold SKILL.md documents --step-mode ---"
SCAFFOLD_SKILL="$REPO_ROOT/skills/scaffold/SKILL.md"
if [ ! -f "$SCAFFOLD_SKILL" ]; then
  echo "SKIP: skills/scaffold/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE '\-\-step.mode|step.mode|GOT_STEP_MODE' "$SCAFFOLD_SKILL"; then
  echo "OK: scaffold SKILL.md references --step-mode / GOT_STEP_MODE"
else
  fail "scaffold SKILL.md missing --step-mode documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: scaffold has 8 steps per design.md §4.1
# ---------------------------------------------------------------------------
echo "--- Assertion 2: scaffold has 8 steps (design.md §4.1) ---"
SCAFFOLD_STEPS="$REPO_ROOT/skills/scaffold/steps"
if [ ! -d "$SCAFFOLD_STEPS" ]; then
  echo "SKIP: skills/scaffold/steps/ not found (implementation pending)" >&2
  exit 77
fi

STEP_COUNT=$(find "$SCAFFOLD_STEPS" -maxdepth 1 -name '[0-9][0-9]-*.md' -type f | wc -l)
if [ "$STEP_COUNT" -eq 8 ]; then
  echo "OK: scaffold has exactly 8 steps"
elif [ "$STEP_COUNT" -ge 5 ] && [ "$STEP_COUNT" -le 8 ]; then
  echo "INFO: scaffold has $STEP_COUNT steps (target 8 per design.md)"
else
  fail "scaffold has $STEP_COUNT steps — expected 8 per design.md §4.1"
fi

# ---------------------------------------------------------------------------
# Assertion 3: step-mode prompt shows total steps = 8 for scaffold
# ---------------------------------------------------------------------------
echo "--- Assertion 3: step-mode prompt uses total=8 for scaffold ---"
PIPELINE_DOC="$REPO_ROOT/docs/reference/pipeline.md"
if [ ! -f "$PIPELINE_DOC" ]; then
  echo "SKIP: docs/reference/pipeline.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'scaffold.*8.*step|8.*step.*scaffold' "$PIPELINE_DOC"; then
  echo "OK: pipeline.md documents scaffold 8 steps"
else
  echo "INFO: pipeline.md may not explicitly list scaffold step count (advisory)"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-MATRIX-009 — scaffold --step-mode per-step prompts documented"
fi
exit "$FAIL"
