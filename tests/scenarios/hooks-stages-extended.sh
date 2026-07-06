#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-hooks-stages-extended.sh
# FC mapped:   FC-4 (hook STAGES array exact set of 10)
# What it checks:
#   A) hooks/validate-dispatch.sh defines `STAGES=(...)` line
#   B) STAGES contains ALL 10 stages (sorted-set equality):
#       triage, code_analysis, reproduce_browser, fixer_reviewer, smoke_check,
#       test, e2e_test, browser_verification, acceptance_gate, publisher
#   C) NEW v10 stages present (sanity sub-asserts):
#       reproduce_browser, smoke_check, e2e_test, browser_verification, acceptance_gate
# Note: the hook is a Python process; STAGES is a Python list, not a bash array.
# Expected RED phase: FAIL — current STAGES has 5 entries
# Expected GREEN phase (post-impl): PASS
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

HOOK="hooks/validate-dispatch.sh"
if [ ! -f "$HOOK" ]; then
  fail "FC-4.file: $HOOK missing"
  exit 1
fi

# A. Extract the STAGES Python list (multi-line: STAGES = [ "a", "b", ... ]).
STAGES_BLOCK=$(awk '/^STAGES = \[/{f=1} f{print} /\]/{if(f)exit}' "$HOOK")
if [ -z "$STAGES_BLOCK" ]; then
  fail "FC-4.A: $HOOK missing 'STAGES = [ ... ]' declaration"
  exit 1
fi

# Extract the quoted stage names from the block.
NAMES=$(printf '%s' "$STAGES_BLOCK" | grep -oE '"[a-z][a-z0-9_]+"' | tr -d '"')

# Build sorted-unique sets.
SORTED_ACTUAL=$(printf '%s\n' $NAMES | sort -u)
SORTED_EXPECTED=$(printf '%s\n' triage code_analysis reproduce_browser fixer_reviewer smoke_check test e2e_test browser_verification acceptance_gate publisher | sort -u)

# B. Sorted-set equality.
if [ "$SORTED_ACTUAL" != "$SORTED_EXPECTED" ]; then
  fail "FC-4.B: STAGES set mismatch"
  echo "Expected:" >&2
  printf '%s\n' "$SORTED_EXPECTED" | sed 's/^/  /' >&2
  echo "Actual:" >&2
  printf '%s\n' "$SORTED_ACTUAL" | sed 's/^/  /' >&2
fi

# C. Count check (≥10; tolerates harmless extras — but B above enforces exactness).
ACTUAL_COUNT=$(printf '%s\n' $NAMES | wc -l | tr -d ' ')
if [ "$ACTUAL_COUNT" -lt 10 ]; then
  fail "FC-4.C: STAGES has only ${ACTUAL_COUNT} entries"
fi

# D. Sanity sub-asserts for the 5 NEW stages
# Whole-word match (grep -w equivalent): token bounded by non-word chars or string ends.
NAMES_LINES=$(printf '%s\n' $NAMES)
for new_stage in reproduce_browser smoke_check e2e_test browser_verification acceptance_gate; do
  if ! matches_re "$NAMES_LINES" "(^|[^[:alnum:]_])${new_stage}([^[:alnum:]_]|\$)"; then
    fail "FC-4.D: STAGES missing stage '${new_stage}'"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-hooks-stages-extended — STAGES has 10 stages"
  exit 0
fi
exit 1
