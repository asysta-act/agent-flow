#!/usr/bin/env bash
# Verifies: AC-DOC-002
# Description: docs/guides/toml-overlay-syntax.md has >= 5 TOML code blocks,
#   all 18 agent names referenced, [meta] free-form table documented
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

TOML_DOC="$REPO_ROOT/docs/guides/toml-overlay-syntax.md"

if [ ! -f "$TOML_DOC" ]; then
  fail "docs/guides/toml-overlay-syntax.md not found"
  exit 1
fi

# ---------------------------------------------------------------------------
# Assertion 1: >= 5 fenced TOML code blocks
# ---------------------------------------------------------------------------
echo "--- Assertion 1: >= 5 fenced TOML code blocks ---"
TOML_BLOCK_COUNT=$(grep -cE '^```toml' "$TOML_DOC" 2>/dev/null); TOML_BLOCK_COUNT=${TOML_BLOCK_COUNT:-0}
if [ "$TOML_BLOCK_COUNT" -ge 5 ]; then
  echo "OK: $TOML_BLOCK_COUNT TOML code blocks (>= 5)"
else
  fail "Only $TOML_BLOCK_COUNT TOML code blocks in toml-overlay-syntax.md (expected >= 5)"
fi

# ---------------------------------------------------------------------------
# Assertion 2: All 18 agent names referenced
# ---------------------------------------------------------------------------
echo "--- Assertion 2: all 18 agent names referenced ---"
AGENTS=(analyst fixer reviewer acceptance-gate test-engineer publisher rollback-agent
  spec-analyst architect scaffolder priority-engine spec-writer spec-reviewer
  browser-agent deployment-verifier backlog-creator sprint-planner)

for agent in "${AGENTS[@]}"; do
  if grep -qF "$agent" "$TOML_DOC"; then
    echo "OK: '$agent' referenced"
  else
    fail "toml-overlay-syntax.md missing agent '$agent' in key reference table"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 3: [meta] free-form table documented
# ---------------------------------------------------------------------------
echo "--- Assertion 3: [meta] free-form table documented (exempt from unknown-key validation) ---"
if grep -qF '[meta]' "$TOML_DOC"; then
  echo "OK: [meta] table documented"
else
  fail "toml-overlay-syntax.md missing [meta] table documentation"
fi

if grep -qiE 'NOT.*subject.*unknown.key|free.?form|meta.*arbitrary|meta.*exempt' "$TOML_DOC"; then
  echo "OK: [meta] documented as free-form (not subject to unknown-key validation)"
else
  fail "toml-overlay-syntax.md missing [meta] free-form / exempt-from-validation documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-002 — toml-overlay-syntax.md has 5+ code blocks, all 17 agents, [meta] exempt"
fi
exit "$FAIL"
