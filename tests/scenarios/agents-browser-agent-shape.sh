#!/usr/bin/env bash
# Verifies: AC-AGT-005
# Description: agents/browser-agent.md has Phase Dispatch with reproduce and verify,
#   name: browser-agent, model: sonnet
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

BA_FILE="$REPO_ROOT/agents/browser-agent.md"

if [ ! -f "$BA_FILE" ]; then
  echo "SKIP: agents/browser-agent.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Assertion 1: frontmatter name: browser-agent
# ---------------------------------------------------------------------------
echo "--- Assertion 1: browser-agent.md frontmatter name: browser-agent ---"
if grep -qE '^name:\s*browser-agent$' "$BA_FILE"; then
  echo "OK: browser-agent.md has name: browser-agent"
else
  fail "browser-agent.md missing name: browser-agent"
fi

# ---------------------------------------------------------------------------
# Assertion 2: frontmatter model: sonnet
# ---------------------------------------------------------------------------
echo "--- Assertion 2: browser-agent.md frontmatter model: sonnet ---"
if grep -qE '^model:\s*sonnet$' "$BA_FILE"; then
  echo "OK: browser-agent.md has model: sonnet"
else
  fail "browser-agent.md missing model: sonnet"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Phase Dispatch section present
# ---------------------------------------------------------------------------
echo "--- Assertion 3: browser-agent.md has ## Phase Dispatch section ---"
if grep -qE '^## Phase Dispatch' "$BA_FILE"; then
  echo "OK: browser-agent.md has ## Phase Dispatch section"
else
  fail "browser-agent.md missing ## Phase Dispatch section"
fi

# ---------------------------------------------------------------------------
# Assertion 4: reproduce and verify phases documented
# ---------------------------------------------------------------------------
echo "--- Assertion 4: browser-agent.md documents reproduce and verify phases ---"
if grep -qiE '\-\-phase.*reproduce|phase.*reproduce' "$BA_FILE"; then
  echo "OK: browser-agent.md documents --phase reproduce"
else
  fail "browser-agent.md missing --phase reproduce"
fi

if grep -qiE '\-\-phase.*verify|phase.*verify' "$BA_FILE"; then
  echo "OK: browser-agent.md documents --phase verify"
else
  fail "browser-agent.md missing --phase verify"
fi

# ---------------------------------------------------------------------------
# Assertion 5: old files reproducer.md and browser-verifier.md absent
# ---------------------------------------------------------------------------
echo "--- Assertion 5: agents/reproducer.md and browser-verifier.md absent ---"
if [ -f "$REPO_ROOT/agents/reproducer.md" ]; then
  fail "agents/reproducer.md still exists — should be merged into browser-agent.md"
else
  echo "OK: agents/reproducer.md correctly absent"
fi

if [ -f "$REPO_ROOT/agents/browser-verifier.md" ]; then
  fail "agents/browser-verifier.md still exists — should be merged into browser-agent.md"
else
  echo "OK: agents/browser-verifier.md correctly absent"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-AGT-005 — browser-agent.md has Phase Dispatch (reproduce + verify)"
fi
exit "$FAIL"
