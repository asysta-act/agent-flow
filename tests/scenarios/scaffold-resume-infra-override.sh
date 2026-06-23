#!/bin/bash
# Test: scaffold.md resume --infra override logic (UXP-4)
# Validates: On resume section describes --infra override behavior with new named format
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
SCAFFOLD_CMD="$REPO_ROOT/skills/scaffold/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

# 1. "On resume" section exists in Step 0-INFRA
if ! grep -q "On resume" "$SCAFFOLD_CMD"; then
  fail "scaffold.md missing 'On resume' section in Step 0-INFRA"
fi

# 2. On resume section mentions --infra flag override behavior
# Check that the resume section references the --infra flag
resume_line=$(grep -n "On resume" "$SCAFFOLD_CMD" | head -1 | cut -d: -f1)
if [ -n "$resume_line" ]; then
  # Read 15 lines after "On resume" to check for override logic
  context=$(sed -n "$resume_line,$((resume_line + 15))p" "$SCAFFOLD_CMD")
  if ! contains "$context" "--infra"; then
    fail "scaffold.md 'On resume' section does not mention --infra override"
  fi
fi

# 3. Override logic references new named format keys (tracker: or sc:)
resume_line=$(grep -n "On resume" "$SCAFFOLD_CMD" | head -1 | cut -d: -f1)
if [ -n "$resume_line" ]; then
  context=$(sed -n "$resume_line,$((resume_line + 20))p" "$SCAFFOLD_CMD")
  if ! matches_re "$context" 'tracker:|sc:'; then
    fail "scaffold.md 'On resume' override does not reference named format (tracker: or sc:)"
  fi
fi

# 4. Override must describe re-verification (when upgrading from later to ready, Step 0-MCP must re-run)
if ! grep -q 're-run.*0-MCP\|0-MCP.*re-run\|re-check\|re-verify\|run.*MCP.*again\|re-ask' "$SCAFFOLD_CMD"; then
  fail "scaffold.md resume --infra override missing re-verification instruction (Step 0-MCP must re-run on upgrade)"
fi

# 5. No-change case documented: if --infra values match state, skip re-verification
if ! grep -q 'no changes\|match.*state\|already.*ready\|same.*values\|unchanged' "$SCAFFOLD_CMD"; then
  fail "scaffold.md resume --infra override missing no-change case (same values → skip re-verification)"
fi

# 6. Downgrade case: clearing detail fields on ready→later override
if ! grep -q 'clear\|null\|downgrade.*override\|override.*downgrade' "$SCAFFOLD_CMD"; then
  fail "scaffold.md resume --infra override missing downgrade/clear logic (ready→later must clear detail fields)"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: scaffold.md resume --infra override logic verified (UXP-4)"
exit "$FAIL"
