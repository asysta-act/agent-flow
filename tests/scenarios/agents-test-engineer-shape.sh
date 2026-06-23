#!/usr/bin/env bash
# Verifies: AC-AGT-004
# Description: agents/test-engineer.md describes --e2e flag, name: test-engineer, model: sonnet
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

TE_FILE="$REPO_ROOT/agents/test-engineer.md"

if [ ! -f "$TE_FILE" ]; then
  echo "SKIP: agents/test-engineer.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Assertion 1: frontmatter name: test-engineer
# ---------------------------------------------------------------------------
echo "--- Assertion 1: test-engineer.md frontmatter name: test-engineer ---"
if grep -qE '^name:\s*test-engineer$' "$TE_FILE"; then
  echo "OK: test-engineer.md has name: test-engineer"
else
  fail "test-engineer.md missing name: test-engineer in frontmatter"
fi

# ---------------------------------------------------------------------------
# Assertion 2: frontmatter model: sonnet
# ---------------------------------------------------------------------------
echo "--- Assertion 2: test-engineer.md frontmatter model: sonnet ---"
if grep -qE '^model:\s*sonnet$' "$TE_FILE"; then
  echo "OK: test-engineer.md has model: sonnet"
else
  fail "test-engineer.md missing model: sonnet in frontmatter"
fi

# ---------------------------------------------------------------------------
# Assertion 3: --e2e flag described in prompt body
# ---------------------------------------------------------------------------
echo "--- Assertion 3: test-engineer.md documents --e2e flag ---"
if grep -qE '\-\-e2e|e2e.*flag|e2e.*test|end.to.end' "$TE_FILE"; then
  echo "OK: test-engineer.md documents --e2e flag"
else
  fail "test-engineer.md missing --e2e flag documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 4: e2e-test-engineer merged into test-engineer (no separate file)
# ---------------------------------------------------------------------------
echo "--- Assertion 4: agents/e2e-test-engineer.md does NOT exist ---"
if [ -f "$REPO_ROOT/agents/e2e-test-engineer.md" ]; then
  fail "agents/e2e-test-engineer.md still exists — should be merged into test-engineer.md"
else
  echo "OK: agents/e2e-test-engineer.md correctly absent"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-AGT-004 — test-engineer.md correct shape with --e2e extension"
fi
exit "$FAIL"
