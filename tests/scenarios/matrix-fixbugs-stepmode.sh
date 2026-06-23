#!/usr/bin/env bash
# Verifies: AC-MODE-MATRIX-003
# Description: fix-bugs + --step-mode = per-step prompt after each step; c/s/a behavior
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if matches_re "$REPO_ROOT" '\.forge'; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# ---------------------------------------------------------------------------
# Assertion 1: fix-bugs SKILL.md documents step-mode per-step prompting
# ---------------------------------------------------------------------------
echo "--- Assertion 1: fix-bugs SKILL.md documents --step-mode per-step prompts ---"
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
if [ ! -f "$FIXBUGS_SKILL" ]; then
  echo "SKIP: skills/fix-bugs/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE '\-\-step.mode|step.mode.*prompt|per.step.*prompt' "$FIXBUGS_SKILL"; then
  echo "OK: fix-bugs SKILL.md documents --step-mode per-step prompting"
else
  fail "fix-bugs SKILL.md missing --step-mode documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: c=continue, s=skip-to-yolo, a=abort behavior documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: c/s/a behavioral table documented for fix-bugs step-mode ---"
PIPELINE_DOC="$REPO_ROOT/docs/reference/pipeline.md"
if [ ! -f "$PIPELINE_DOC" ]; then
  echo "SKIP: docs/reference/pipeline.md not found (implementation pending)" >&2
  exit 77
fi

for action in "continue" "skip" "abort"; do
  if grep -qiE "\\b$action\\b" "$PIPELINE_DOC"; then
    echo "OK: '$action' action documented in pipeline.md"
  else
    fail "pipeline.md missing '$action' action for step-mode"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 3: 's' switches to yolo for remaining steps
# ---------------------------------------------------------------------------
echo "--- Assertion 3: 's' switches to yolo for remaining steps ---"
if grep -qiE 'step.mode escape|switch.*yolo|s.*yolo|skip.*remaining' "$PIPELINE_DOC" || \
   grep -qiE 'step.mode escape|switch.*yolo' "$FIXBUGS_SKILL"; then
  echo "OK: 's' skip-to-yolo behavior documented"
else
  fail "skip-to-yolo behavior for 's' input not documented"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-MATRIX-003 — fix-bugs --step-mode per-step prompts documented"
fi
exit "$FAIL"
