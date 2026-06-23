#!/usr/bin/env bash
# Verifies: AC-SETUP-001
# Description: skills/setup-agents/SKILL.md exists with correct frontmatter name: setup-agents
# Post-cleanup baseline: skills reduced from 22 to 17.
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

SKILL_FILE="$REPO_ROOT/skills/setup-agents/SKILL.md"

# ---------------------------------------------------------------------------
# Assertion 1: file exists
# ---------------------------------------------------------------------------
echo "--- Assertion 1: skills/setup-agents/SKILL.md exists ---"
if [ -f "$SKILL_FILE" ]; then
  echo "OK: skills/setup-agents/SKILL.md exists"
else
  fail "skills/setup-agents/SKILL.md not found"
fi

# ---------------------------------------------------------------------------
# Assertion 2: YAML frontmatter contains name: setup-agents
# ---------------------------------------------------------------------------
echo "--- Assertion 2: frontmatter name: setup-agents ---"
if [ -f "$SKILL_FILE" ]; then
  if grep -qE '^name:\s*setup-agents' "$SKILL_FILE"; then
    echo "OK: setup-agents/SKILL.md has name: setup-agents in frontmatter"
  else
    fail "setup-agents/SKILL.md missing name: setup-agents in frontmatter"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 3: skills/setup-agents/ directory exists
# ---------------------------------------------------------------------------
echo "--- Assertion 3: skills/setup-agents/ directory exists ---"
if [ -d "$REPO_ROOT/skills/setup-agents" ]; then
  echo "OK: skills/setup-agents/ directory exists"
else
  fail "skills/setup-agents/ directory not found"
fi

# ---------------------------------------------------------------------------
# Assertion 4: skill count includes setup-agents (17 total)
# ---------------------------------------------------------------------------
echo "--- Assertion 4: skills/ count is 17 (includes setup-agents) ---"
SKILL_COUNT=$(find "$REPO_ROOT/skills" -maxdepth 2 -name 'SKILL.md' -not -path '*/steps/*' -type f | wc -l)
if [ "$SKILL_COUNT" -eq 17 ]; then
  echo "OK: skills/ contains 17 SKILL.md files"
else
  echo "INFO: skills/ contains $SKILL_COUNT SKILL.md files (expected 17)"
  fail "skills/ has $SKILL_COUNT SKILL.md files — expected 17"
fi

# ---------------------------------------------------------------------------
# Assertion 5: CLAUDE.md documents /setup-agents in skills list
# ---------------------------------------------------------------------------
echo "--- Assertion 5: CLAUDE.md references /setup-agents ---"
if grep -qF 'setup-agents' "$REPO_ROOT/CLAUDE.md"; then
  echo "OK: CLAUDE.md references setup-agents skill"
else
  fail "CLAUDE.md does not reference setup-agents skill"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-001 — skills/setup-agents/SKILL.md exists with correct frontmatter; 17 skills total"
fi
exit "$FAIL"
