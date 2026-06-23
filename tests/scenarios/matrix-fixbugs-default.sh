#!/usr/bin/env bash
# Verifies: AC-MODE-MATRIX-002, AC-MODE-002
# Description: fix-bugs + default mode = Acceptance gate triggers when AC >= 3 OR complexity >= M
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
# Assertion 1: fix-bugs SKILL.md documents default mode with conditional gates
# ---------------------------------------------------------------------------
echo "--- Assertion 1: fix-bugs SKILL.md documents default mode conditional gates ---"
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
if [ ! -f "$FIXBUGS_SKILL" ]; then
  echo "SKIP: skills/fix-bugs/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'MODE.*default|default.*mode|no.*flag.*default' "$FIXBUGS_SKILL"; then
  echo "OK: fix-bugs SKILL.md documents default mode"
else
  fail "fix-bugs SKILL.md missing default mode documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Acceptance gate conditional (AC >= 3 OR complexity >= M) documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: acceptance gate condition AC>=3 OR complexity>=M documented ---"
ACCEPT_STEP="$REPO_ROOT/skills/fix-bugs/steps/09-acceptance-gate.md"
if [ ! -f "$ACCEPT_STEP" ]; then
  echo "SKIP: fix-bugs step 09-acceptance-gate.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'AC.*>=.*3|3.*AC.*or|acceptance.*conditional' "$ACCEPT_STEP"; then
  echo "OK: acceptance gate step documents AC>=3 condition"
else
  fail "acceptance gate step missing AC>=3 condition"
fi

if grep -qiE 'complexity.*[Mm]|>= M|Medium.*complex' "$ACCEPT_STEP"; then
  echo "OK: acceptance gate step documents complexity>=M condition"
else
  fail "acceptance gate step missing complexity>=M condition"
fi

# ---------------------------------------------------------------------------
# Assertion 3: pipeline.md documents default mode for fix-bugs
# ---------------------------------------------------------------------------
echo "--- Assertion 3: pipeline.md documents fix-bugs default conditional gates ---"
PIPELINE_DOC="$REPO_ROOT/docs/reference/pipeline.md"
if [ ! -f "$PIPELINE_DOC" ]; then
  echo "SKIP: docs/reference/pipeline.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'default.*mode.*fix.bugs|fix.bugs.*default|conditional.*gate' "$PIPELINE_DOC"; then
  echo "OK: pipeline.md documents fix-bugs default conditional gates"
else
  fail "pipeline.md missing fix-bugs default mode documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-MATRIX-002 — fix-bugs default mode conditional acceptance gate documented"
fi
exit "$FAIL"
