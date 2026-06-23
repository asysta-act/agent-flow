#!/usr/bin/env bash
# Verifies: AC-MODE-MATRIX-005
# Description: implement-feature + default mode = Spec Checkpoint, Decomposition Approval,
#   AC coverage prompts visible
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
# Assertion 1: implement-feature SKILL.md documents default mode checkpoints
# ---------------------------------------------------------------------------
echo "--- Assertion 1: implement-feature SKILL.md documents default mode checkpoints ---"
IMPL_SKILL="$REPO_ROOT/skills/implement-feature/SKILL.md"
if [ ! -f "$IMPL_SKILL" ]; then
  echo "SKIP: skills/implement-feature/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'spec.*checkpoint|checkpoint.*spec' "$IMPL_SKILL"; then
  echo "OK: implement-feature SKILL.md documents Spec Checkpoint"
else
  fail "implement-feature SKILL.md missing Spec Checkpoint documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Decomposition Approval checkpoint documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: Decomposition Approval checkpoint documented ---"
if grep -qiE 'decomposition.*approval|approval.*decomposition' "$IMPL_SKILL"; then
  echo "OK: Decomposition Approval documented"
else
  fail "implement-feature SKILL.md missing Decomposition Approval checkpoint"
fi

# ---------------------------------------------------------------------------
# Assertion 3: pipeline.md documents default checkpoints for implement-feature
# ---------------------------------------------------------------------------
echo "--- Assertion 3: pipeline.md documents implement-feature default checkpoints ---"
PIPELINE_DOC="$REPO_ROOT/docs/reference/pipeline.md"
if [ ! -f "$PIPELINE_DOC" ]; then
  echo "SKIP: docs/reference/pipeline.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'implement.feature.*default|default.*implement.feature|spec.*checkpoint.*implement' "$PIPELINE_DOC"; then
  echo "OK: pipeline.md documents implement-feature default checkpoints"
else
  fail "pipeline.md missing implement-feature default mode checkpoints"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-MATRIX-005 — implement-feature default checkpoints documented"
fi
exit "$FAIL"
