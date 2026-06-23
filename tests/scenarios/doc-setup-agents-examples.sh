#!/usr/bin/env bash
# Verifies: AC-DOC-003
# Description: docs/guides/setup-agents-skill.md has >= 3 worked examples with input + output
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

SETUP_GUIDE="$REPO_ROOT/docs/guides/setup-agents-skill.md"

if [ ! -f "$SETUP_GUIDE" ]; then
  fail "docs/guides/setup-agents-skill.md not found"
  exit 1
fi

# ---------------------------------------------------------------------------
# Assertion 1: >= 3 example headings (### Example 1/2/3)
# ---------------------------------------------------------------------------
echo "--- Assertion 1: >= 3 example headings in setup-agents-skill.md ---"
EXAMPLE_COUNT=$(grep -cE '^### Example [0-9]+' "$SETUP_GUIDE" || echo 0)
if [ "$EXAMPLE_COUNT" -ge 3 ]; then
  echo "OK: $EXAMPLE_COUNT example headings (>= 3)"
else
  fail "setup-agents-skill.md has $EXAMPLE_COUNT example headings (expected >= 3)"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Input + output shown in examples
# ---------------------------------------------------------------------------
echo "--- Assertion 2: examples show both input project layout and expected .toml output ---"
if grep -qiE 'project.*layout|directory.*structure|input.*project' "$SETUP_GUIDE"; then
  echo "OK: setup-agents-skill.md shows input project layout"
else
  fail "setup-agents-skill.md missing input project layout in examples"
fi

if grep -qiE 'customization/.*\.toml|expected.*\.toml|output.*\.toml' "$SETUP_GUIDE"; then
  echo "OK: setup-agents-skill.md shows expected .toml output"
else
  fail "setup-agents-skill.md missing expected customization/*.toml output in examples"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Python and monorepo heuristics covered (AC-SETUP-002, AC-SETUP-003)
# ---------------------------------------------------------------------------
echo "--- Assertion 3: Python and monorepo heuristics documented ---"
if grep -qiE 'pyproject|python.*project|Python' "$SETUP_GUIDE"; then
  echo "OK: Python heuristic in setup-agents guide"
else
  fail "setup-agents-skill.md missing Python heuristic documentation"
fi

if grep -qiE 'monorepo|pnpm.workspace|multi.?package' "$SETUP_GUIDE"; then
  echo "OK: monorepo heuristic in setup-agents guide"
else
  fail "setup-agents-skill.md missing monorepo heuristic documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-003 — setup-agents-skill.md has 3+ worked examples"
fi
exit "$FAIL"
