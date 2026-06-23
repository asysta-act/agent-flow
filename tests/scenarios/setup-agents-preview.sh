#!/usr/bin/env bash
# Verifies: AC-SETUP-007
# Description: /setup-agents without --yolo shows preview diff and waits for user input
#   before writing each file
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
# Assertion 1: setup-agents SKILL.md documents preview-before-write behavior
# ---------------------------------------------------------------------------
echo "--- Assertion 1: setup-agents SKILL.md documents preview diff before write ---"
SETUP_SKILL="$REPO_ROOT/skills/setup-agents/SKILL.md"
if [ ! -f "$SETUP_SKILL" ]; then
  echo "SKIP: skills/setup-agents/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'preview.*diff|preview.*write|diff.*before|show.*preview' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents preview diff before write"
else
  fail "setup-agents SKILL.md missing preview diff before write documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: --yolo flag documented as skip for preview prompt
# ---------------------------------------------------------------------------
echo "--- Assertion 2: --yolo skips preview prompt documented ---"
if grep -qiE '\-\-yolo.*skip.*preview|\-\-yolo.*no.*prompt|unless.*\-\-yolo' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents --yolo skips preview"
else
  fail "setup-agents SKILL.md missing --yolo skips preview documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: docs/guides/setup-agents-skill.md documents interactive preview
# ---------------------------------------------------------------------------
echo "--- Assertion 3: setup-agents-skill.md guide documents interactive preview ---"
SETUP_GUIDE="$REPO_ROOT/docs/guides/setup-agents-skill.md"
if [ ! -f "$SETUP_GUIDE" ]; then
  echo "SKIP: docs/guides/setup-agents-skill.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'preview|interactive|diff.*before|confirm.*write' "$SETUP_GUIDE"; then
  echo "OK: setup-agents guide documents preview/interactive mode"
else
  fail "setup-agents guide missing preview/interactive mode documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 4: setup-agents SKILL.md step 4 documents preview flow
# ---------------------------------------------------------------------------
echo "--- Assertion 4: setup-agents SKILL.md includes preview diff step ---"
if grep -qiE 'preview.*diff|display.*preview|UNLESS.*\-\-yolo' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md includes preview diff step"
else
  fail "setup-agents SKILL.md missing preview diff step"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-007 — preview diff before write documented (skipped with --yolo)"
fi
exit "$FAIL"
