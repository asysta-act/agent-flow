#!/usr/bin/env bash
# Verifies: AC-NF-004
# Description: agents/analyst.md, agents/test-engineer.md, agents/browser-agent.md
#   each contain the prompt-injection constraint paragraph
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

# Canonical prompt-injection constraint phrase
INJECTION_REGEX='prompt.injection|malicious.*input|EXTERNAL INPUT|sanitize.*input|untrusted.*content'

MERGED_AGENTS=(analyst test-engineer browser-agent)

echo "--- Checking prompt-injection constraint in merged agent files ---"
for agent in "${MERGED_AGENTS[@]}"; do
  AGENT_FILE="$REPO_ROOT/agents/$agent.md"
  if [ ! -f "$AGENT_FILE" ]; then
    echo "SKIP: agents/$agent.md not found (implementation pending)" >&2
    continue
  fi

  if grep -qiE "$INJECTION_REGEX" "$AGENT_FILE"; then
    echo "OK: agents/$agent.md contains prompt-injection constraint"
  else
    fail "agents/$agent.md missing prompt-injection constraint (required)"
  fi
done

# ---------------------------------------------------------------------------
# Assertion: existing non-merged agents also have constraint (regression guard)
# ---------------------------------------------------------------------------
echo "--- Regression: existing agents retain prompt-injection constraint ---"
for agent in fixer reviewer; do
  AGENT_FILE="$REPO_ROOT/agents/$agent.md"
  if [ ! -f "$AGENT_FILE" ]; then
    continue
  fi
  if grep -qiE "$INJECTION_REGEX" "$AGENT_FILE"; then
    echo "OK: agents/$agent.md retains prompt-injection constraint"
  else
    fail "agents/$agent.md lost prompt-injection constraint (regression)"
  fi
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-NF-004 — merged agent files contain prompt-injection constraints"
fi
exit "$FAIL"
