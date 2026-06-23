#!/usr/bin/env bash
# Verifies: AC-AGT-003
# Description: agents/analyst.md has Phase Dispatch section, name: analyst, model: sonnet
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

ANALYST_FILE="$REPO_ROOT/agents/analyst.md"

if [ ! -f "$ANALYST_FILE" ]; then
  echo "SKIP: agents/analyst.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Assertion 1: frontmatter name: analyst
# ---------------------------------------------------------------------------
echo "--- Assertion 1: analyst.md frontmatter name: analyst ---"
if grep -qE '^name:\s*analyst$' "$ANALYST_FILE"; then
  echo "OK: analyst.md has name: analyst"
else
  fail "analyst.md missing name: analyst in frontmatter"
fi

# ---------------------------------------------------------------------------
# Assertion 2: frontmatter model: sonnet
# ---------------------------------------------------------------------------
echo "--- Assertion 2: analyst.md frontmatter model: sonnet ---"
if grep -qE '^model:\s*sonnet$' "$ANALYST_FILE"; then
  echo "OK: analyst.md has model: sonnet"
else
  fail "analyst.md missing model: sonnet in frontmatter"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Phase Dispatch section present
# ---------------------------------------------------------------------------
echo "--- Assertion 3: analyst.md has ## Phase Dispatch section ---"
if grep -qE '^## Phase Dispatch' "$ANALYST_FILE"; then
  echo "OK: analyst.md has ## Phase Dispatch section"
else
  fail "analyst.md missing ## Phase Dispatch section"
fi

# ---------------------------------------------------------------------------
# Assertion 4: --phase triage and --phase impact documented
# ---------------------------------------------------------------------------
echo "--- Assertion 4: analyst.md documents --phase triage and --phase impact ---"
if grep -qE '\-\-phase.*triage|phase.*triage' "$ANALYST_FILE"; then
  echo "OK: analyst.md documents --phase triage"
else
  fail "analyst.md missing --phase triage documentation"
fi

if grep -qE '\-\-phase.*impact|phase.*impact' "$ANALYST_FILE"; then
  echo "OK: analyst.md documents --phase impact"
else
  fail "analyst.md missing --phase impact documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 5: description mentions both phases
# ---------------------------------------------------------------------------
echo "--- Assertion 5: analyst.md description mentions both phases ---"
if grep -qiE 'triage.*impact|impact.*triage' "$ANALYST_FILE"; then
  echo "OK: analyst.md description references both triage and impact phases"
else
  fail "analyst.md description does not reference both phases"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-AGT-003 — analyst.md has correct shape (Phase Dispatch, name, model)"
fi
exit "$FAIL"
