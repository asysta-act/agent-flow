#!/usr/bin/env bash
# Verifies: AC-DOC-004
# Description: docs/guides/steps-decomposition.md has >= 1 step override example per pipeline
#   and documents customization/steps/{skill}/{step}.md resolution rules
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

STEPS_GUIDE="$REPO_ROOT/docs/guides/steps-decomposition.md"
if [ ! -f "$STEPS_GUIDE" ]; then
  fail "docs/guides/steps-decomposition.md not found"
  exit 1
fi

# ---------------------------------------------------------------------------
# Assertion 1: >= 1 step override example per pipeline (3 total)
# ---------------------------------------------------------------------------
echo "--- Assertion 1: examples for all 3 pipelines ---"
PIPELINES=(fix-bugs implement-feature scaffold)
for pipeline in "${PIPELINES[@]}"; do
  if grep -qiE "$pipeline.*override|override.*$pipeline|customization/steps/$pipeline" "$STEPS_GUIDE"; then
    echo "OK: steps-decomposition.md has $pipeline step override example"
  else
    fail "steps-decomposition.md missing $pipeline step override example"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 2: customization/steps/{skill}/{step}.md resolution rules
# ---------------------------------------------------------------------------
echo "--- Assertion 2: resolution rules for customization/steps/{skill}/{step}.md ---"
if grep -qE 'customization/steps/\{skill\}|customization/steps/fix-bugs' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md documents customization/steps/{skill}/{step}.md path"
else
  fail "steps-decomposition.md missing customization/steps resolution path documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Override is replace-only (not append/patch)
# ---------------------------------------------------------------------------
echo "--- Assertion 3: replace-only override semantics documented ---"
if grep -qiE 'replace.only|full.*replace|replac.*entire|not.*patch|not.*append' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md documents replace-only override semantics"
else
  fail "steps-decomposition.md missing replace-only semantics documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-004 — steps-decomposition.md has per-pipeline examples + resolution rules"
fi
exit "$FAIL"
