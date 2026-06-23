#!/usr/bin/env bash
# Verifies: AC-MODE-MATRIX-004
# Description: implement-feature + --yolo = zero checkpoints, autonomous spec->architect->fixer->publisher
# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
set -uo pipefail

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
# Assertion 1: implement-feature SKILL.md documents --yolo zero checkpoints
# ---------------------------------------------------------------------------
echo "--- Assertion 1: implement-feature SKILL.md documents --yolo zero checkpoints ---"
IMPL_SKILL="$REPO_ROOT/skills/implement-feature/SKILL.md"
if [ ! -f "$IMPL_SKILL" ]; then
  echo "SKIP: skills/implement-feature/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE '\-\-yolo|yolo.*zero.*gate|zero.*checkpoint.*yolo' "$IMPL_SKILL"; then
  echo "OK: implement-feature SKILL.md references --yolo flag"
else
  fail "implement-feature SKILL.md missing --yolo documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: --yolo skips ALL checkpoints in implement-feature
#   (Spec checkpoint, Decomposition approval, AC coverage gate all skipped)
#   Observable behavior: no interactive prompts documented under --yolo.
# ---------------------------------------------------------------------------
echo "--- Assertion 2: implement-feature --yolo skips all spec/decomp/AC checkpoints ---"
if grep -qiE 'yolo.*skip.*checkpoint|yolo.*no.*checkpoint|yolo.*spec.*skip|yolo.*no.*prompt|skip.*all.*checkpoint' "$IMPL_SKILL" || \
   grep -qiE 'yolo.*autonomous|autonomous.*yolo|no.*gate.*yolo' "$IMPL_SKILL"; then
  echo "OK: implement-feature SKILL.md documents --yolo skips all checkpoints"
else
  fail "implement-feature SKILL.md missing observable --yolo zero-checkpoints contract"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Spec->Architect->Fixer->Publisher flow documented for yolo mode
# ---------------------------------------------------------------------------
echo "--- Assertion 3: yolo autonomous flow: spec->architect->fixer->publisher ---"
if grep -qiE 'spec.analyst|architect|fixer.*publisher' "$IMPL_SKILL"; then
  echo "OK: implement-feature SKILL.md references spec-analyst/architect/fixer pipeline"
else
  fail "implement-feature SKILL.md missing autonomous flow documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-MATRIX-004 — implement-feature --yolo zero checkpoints documented"
fi
exit "$FAIL"
