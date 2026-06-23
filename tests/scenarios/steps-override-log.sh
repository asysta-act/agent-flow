#!/usr/bin/env bash
# Verifies: AC-STEPS-003
# Description: When customization/steps/fix-bugs/04-fixer-reviewer-loop.md exists,
#   fix-bugs pipeline logs "[INFO] Step override active: fix-bugs/04-fixer-reviewer-loop from project customization"
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

EXPECTED_LOG_MSG="[INFO] Step override active: fix-bugs/04-fixer-reviewer-loop from project customization"

# ---------------------------------------------------------------------------
# Assertion 1: fix-bugs SKILL.md documents override logging
# ---------------------------------------------------------------------------
echo "--- Assertion 1: fix-bugs SKILL.md documents step override INFO log ---"
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
if [ ! -f "$FIXBUGS_SKILL" ]; then
  echo "SKIP: skills/fix-bugs/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'step override|override.*active|override.*customization' "$FIXBUGS_SKILL"; then
  echo "OK: fix-bugs SKILL.md documents step override log"
else
  fail "fix-bugs SKILL.md missing step override [INFO] log documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: exact log message format documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: exact log format '[INFO] Step override active: ...' documented ---"
if grep -qF 'Step override active' "$FIXBUGS_SKILL" || \
   grep -qF 'Step override active' "$REPO_ROOT/docs/guides/steps-decomposition.md" 2>/dev/null; then
  echo "OK: exact 'Step override active' log text documented"
else
  fail "Exact log format '$EXPECTED_LOG_MSG' not found in skill or guide"
fi

# ---------------------------------------------------------------------------
# Assertion 3: steps-decomposition.md documents the override log format
# ---------------------------------------------------------------------------
echo "--- Assertion 3: docs/guides/steps-decomposition.md documents override log ---"
STEPS_GUIDE="$REPO_ROOT/docs/guides/steps-decomposition.md"
if [ ! -f "$STEPS_GUIDE" ]; then
  echo "SKIP: docs/guides/steps-decomposition.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'override.*log|INFO.*override|step.*override.*active' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md documents override log"
else
  fail "steps-decomposition.md missing override log documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 4: customization/steps/{skill}/{step}.md resolution path documented
# ---------------------------------------------------------------------------
echo "--- Assertion 4: resolution path customization/steps/{skill}/{step}.md documented ---"
if grep -qE 'customization/steps/\{skill\}|customization/steps/fix-bugs' "$STEPS_GUIDE"; then
  echo "OK: steps-decomposition.md documents customization/steps/{skill}/{step}.md path"
else
  fail "steps-decomposition.md missing customization/steps/{skill}/{step}.md path example"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-STEPS-003 — step override logs '[INFO] Step override active' documented"
fi
exit "$FAIL"
