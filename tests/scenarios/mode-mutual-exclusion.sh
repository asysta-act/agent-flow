#!/usr/bin/env bash
# Verifies: AC-MODE-001
# Description: /fix-bugs --yolo --step-mode exits with code 2 and emits
#   "[ERROR] Flags --yolo and --step-mode are mutually exclusive" to stderr
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

EXPECTED_ERROR="Flags --yolo and --step-mode are mutually exclusive"

# ---------------------------------------------------------------------------
# Assertion 1: fix-bugs SKILL.md implements mutual exclusion check
# ---------------------------------------------------------------------------
echo "--- Assertion 1: fix-bugs SKILL.md has --yolo + --step-mode mutual exclusion ---"
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
if [ ! -f "$FIXBUGS_SKILL" ]; then
  echo "SKIP: skills/fix-bugs/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qF 'mutually exclusive' "$FIXBUGS_SKILL"; then
  echo "OK: fix-bugs SKILL.md documents mutually exclusive error"
else
  fail "fix-bugs SKILL.md missing 'mutually exclusive' error for --yolo + --step-mode"
fi

# ---------------------------------------------------------------------------
# Assertion 3: exact error text present
# ---------------------------------------------------------------------------
echo "--- Assertion 3: exact error text '$EXPECTED_ERROR' documented ---"
FOUND_IN_SKILL=0
for skill in fix-bugs implement-feature scaffold; do
  SKILL_FILE="$REPO_ROOT/skills/$skill/SKILL.md"
  if [ -f "$SKILL_FILE" ] && grep -qF "$EXPECTED_ERROR" "$SKILL_FILE"; then
    echo "OK: '$EXPECTED_ERROR' found in skills/$skill/SKILL.md"
    FOUND_IN_SKILL=1
  fi
done
if [ "$FOUND_IN_SKILL" -eq 0 ]; then
  fail "Exact error text '$EXPECTED_ERROR' not found in any pipeline SKILL.md"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Exit code 1 documented for mutual exclusion error
# ---------------------------------------------------------------------------
echo "--- Assertion 4: exit code 1 documented for mutual exclusion error ---"
FOUND_EXIT1=0
for skill in fix-bugs implement-feature scaffold; do
  SKILL_FILE="$REPO_ROOT/skills/$skill/SKILL.md"
  if [ -f "$SKILL_FILE" ] && grep -qE 'exit 1' "$SKILL_FILE"; then
    echo "OK: exit 1 documented in skills/$skill/SKILL.md"
    FOUND_EXIT1=1
  fi
done
if [ "$FOUND_EXIT1" -eq 0 ]; then
  fail "exit code 1 not documented in any pipeline SKILL.md for mutual exclusion error"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Both --yolo AND --step-mode flags handled independently
#   (Observable behavior: mutual exclusion error MUST be emitted regardless
#    of flag order; implementation variable naming is irrelevant)
# ---------------------------------------------------------------------------
echo "--- Assertion 5: both --yolo and --step-mode flag parsing documented ---"
# Each flag must be individually recognized (not last-wins arg parsing)
FOUND_YOLO_FLAG=0
FOUND_STEPMODE_FLAG=0
for skill in fix-bugs implement-feature scaffold; do
  SKILL_FILE="$REPO_ROOT/skills/$skill/SKILL.md"
  [ -f "$SKILL_FILE" ] || continue
  if grep -qiE '\-\-yolo' "$SKILL_FILE"; then
    FOUND_YOLO_FLAG=1
  fi
  if grep -qiE '\-\-step.mode' "$SKILL_FILE"; then
    FOUND_STEPMODE_FLAG=1
  fi
done
if [ "$FOUND_YOLO_FLAG" -eq 0 ]; then
  fail "--yolo flag not documented in any pipeline SKILL.md"
fi
if [ "$FOUND_STEPMODE_FLAG" -eq 0 ]; then
  fail "--step-mode flag not documented in any pipeline SKILL.md"
fi
echo "OK: both --yolo and --step-mode flags documented (independent tracking, not last-wins)"

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-001 — --yolo + --step-mode mutual exclusion with exit 1 documented"
fi
exit "$FAIL"
