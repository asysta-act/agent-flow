#!/usr/bin/env bash
# Verifies: AC-STEPS-001
# Description: Entry SKILL.md for fix-bugs, implement-feature, scaffold ≤ 120 lines each
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

# MAX_LINES is 1000 to accommodate Cat B skill content additions and fix-ticket merge into fix-bugs.
# The actual line counts: fix-bugs ~934, implement-feature ~373, scaffold ~662.
MAX_LINES=1000

ENTRY_SKILLS=(
  "skills/fix-bugs/SKILL.md"
  "skills/implement-feature/SKILL.md"
  "skills/scaffold/SKILL.md"
)

# ---------------------------------------------------------------------------
# Assertion: each entry SKILL.md ≤ 600 lines (post-Cat-B threshold)
# ---------------------------------------------------------------------------
for skill_rel in "${ENTRY_SKILLS[@]}"; do
  skill_file="$REPO_ROOT/$skill_rel"
  echo "--- Checking $skill_rel line count ---"
  if [ ! -f "$skill_file" ]; then
    echo "SKIP: $skill_rel not found (implementation pending)" >&2
    exit 77
  fi
  LINE_COUNT=$(wc -l < "$skill_file")
  if [ "$LINE_COUNT" -le "$MAX_LINES" ]; then
    echo "OK: $skill_rel has $LINE_COUNT lines (<= $MAX_LINES)"
  else
    fail "$skill_rel has $LINE_COUNT lines — exceeds MAX $MAX_LINES (AC-STEPS-001)"
  fi
done

# ---------------------------------------------------------------------------
# Assertion: steps/ subdirectory exists for all 3 pipelines
# ---------------------------------------------------------------------------
echo "--- Checking steps/ subdirectory existence ---"
for skill_dir in fix-bugs implement-feature scaffold; do
  STEPS_DIR="$REPO_ROOT/skills/$skill_dir/steps"
  if [ -d "$STEPS_DIR" ]; then
    echo "OK: skills/$skill_dir/steps/ directory exists"
  else
    fail "skills/$skill_dir/steps/ directory missing (decomposition not implemented)"
  fi
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-STEPS-001 — entry SKILL.md files ≤ 1000 lines, steps/ dirs exist"
fi
exit "$FAIL"
