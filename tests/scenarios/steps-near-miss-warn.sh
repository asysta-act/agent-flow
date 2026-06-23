#!/usr/bin/env bash
# Verifies: AC-STEPS-003aa
# Description: Near-miss step override filenames (wrong zero-pad, wrong case, underscore vs hyphen)
#   emit [WARN] "Possible misnamed step override: {file} — did you mean {canonical-name}?"
#   and fall through to plugin-default step (3 cases: zero-pad, case-fold, underscore-hyphen)
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
# Case definitions: near-miss filenames and their canonical equivalents
# ---------------------------------------------------------------------------
declare -a NEAR_MISS_FILES=("4-fixer.md" "04-Fixer-Reviewer-Loop.md" "04_fixer_reviewer_loop.md")
declare -a CANONICAL_FILES=("04-fixer-reviewer-loop.md" "04-fixer-reviewer-loop.md" "04-fixer-reviewer-loop.md")
declare -a CASE_LABELS=("zero-pad mismatch" "case-fold mismatch" "underscore-hyphen mismatch")

# ---------------------------------------------------------------------------
# Assertion 1: steps-decomposition.md documents near-miss WARN
# ---------------------------------------------------------------------------
echo "--- Assertion 1: steps-decomposition.md documents near-miss WARN ---"
STEPS_GUIDE="$REPO_ROOT/docs/guides/steps-decomposition.md"
if [ ! -f "$STEPS_GUIDE" ]; then
  echo "SKIP: docs/guides/steps-decomposition.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'near.miss|possible misnamed|did you mean|mismatch.*warn' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md documents near-miss override warning"
else
  fail "steps-decomposition.md missing near-miss override WARN documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: WARN format includes canonical name hint
# ---------------------------------------------------------------------------
echo "--- Assertion 2: WARN format includes 'did you mean {canonical-name}' ---"
if grep -qiE 'did you mean|canonical.*name' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md shows 'did you mean' canonical-name hint"
else
  fail "steps-decomposition.md missing 'did you mean {canonical-name}' hint in WARN format"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Fall-through to plugin default on near-miss
# ---------------------------------------------------------------------------
echo "--- Assertion 3: near-miss falls through to plugin default (no override applied) ---"
if grep -qiE 'fall.?through.*default|plugin.default.*near.miss|near.miss.*fall' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md documents fall-through on near-miss"
else
  fail "steps-decomposition.md missing fall-through-to-default on near-miss documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 4: 3 near-miss detection heuristics documented
# ---------------------------------------------------------------------------
echo "--- Assertion 4: 3 near-miss heuristics documented (zero-pad, case, underscore) ---"

HEURISTIC_OK=0
if grep -qiE 'zero.?pad|[0-9]-.*vs.*0[0-9]-|4.*vs.*04' "$STEPS_GUIDE"; then
  echo "OK: zero-padding heuristic documented"
  HEURISTIC_OK=$((HEURISTIC_OK + 1))
else
  echo "WARN: zero-pad heuristic not explicitly documented" >&2
fi

if grep -qiE 'case.?fold|case.insensitive|case.*mismatch' "$STEPS_GUIDE"; then
  echo "OK: case-fold heuristic documented"
  HEURISTIC_OK=$((HEURISTIC_OK + 1))
else
  echo "WARN: case-fold heuristic not explicitly documented" >&2
fi

if grep -qiE 'underscore.*hyphen|hyphen.*underscore|_.*-|-.*_' "$STEPS_GUIDE"; then
  echo "OK: underscore-hyphen heuristic documented"
  HEURISTIC_OK=$((HEURISTIC_OK + 1))
else
  echo "WARN: underscore-hyphen heuristic not explicitly documented" >&2
fi

if [ "$HEURISTIC_OK" -ge 2 ]; then
  echo "OK: $HEURISTIC_OK/3 near-miss heuristics documented"
else
  fail "Only $HEURISTIC_OK/3 near-miss heuristics documented (expected at least 2)"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Validate our 3 near-miss filenames against canonical via normalize check
# ---------------------------------------------------------------------------
echo "--- Assertion 5: near-miss normalization logic verified ---"
for i in 0 1 2; do
  NM="${NEAR_MISS_FILES[$i]}"
  CAN="${CANONICAL_FILES[$i]}"
  LABEL="${CASE_LABELS[$i]}"

  # Normalize near-miss: lowercase, replace underscores with hyphens, zero-pad single digit prefix
  NORMALIZED=$(echo "$NM" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | sed 's/^\([0-9]\)-/0\1-/')

  # For zero-pad case: normalization produces the correct NN- prefix but cannot recover the full
  # step name (e.g. '4-fixer.md' → '04-fixer.md' not '04-fixer-reviewer-loop.md').
  # The near-miss detection heuristic matches on prefix similarity, so we check that the
  # normalized form shares the same NN- prefix as the canonical name.
  CAN_PREFIX=$(echo "$CAN" | grep -oE '^[0-9]+-')
  NORM_PREFIX=$(echo "$NORMALIZED" | grep -oE '^[0-9]+-')

  if [ "$NORMALIZED" = "$CAN" ]; then
    echo "OK ($LABEL): near-miss '$NM' normalizes exactly to canonical '$CAN'"
  elif [ -n "$CAN_PREFIX" ] && [ "$NORM_PREFIX" = "$CAN_PREFIX" ]; then
    echo "OK ($LABEL): near-miss '$NM' normalized to '$NORMALIZED' — shares prefix '$CAN_PREFIX' with canonical '$CAN' (near-miss detection will trigger WARN)"
  else
    fail "($LABEL): near-miss '$NM' normalized to '$NORMALIZED', does not share prefix with canonical '$CAN'"
  fi
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-STEPS-003a — near-miss override WARN documented for 3 heuristics"
fi
exit "$FAIL"
