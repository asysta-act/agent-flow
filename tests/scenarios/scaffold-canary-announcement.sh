#!/bin/bash
# Test: scaffold.md Step 0-MCP announces canary-write test to user (UXP-2)
# Validates: informational canary announcement is present before write check runs
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
SCAFFOLD_CMD="$REPO_ROOT/skills/scaffold/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

# 1. Announcement text present — check for key phrases that describe the canary write
# Acceptable variants: "canary", "test issue", "test write", "temporary issue", "write test"
if ! grep -qi 'canary\|test.*write\|write.*test\|test.*issue.*creat\|temporary.*issue\|verificat.*write' "$SCAFFOLD_CMD"; then
  fail "scaffold.md Step 0-MCP missing canary-write announcement text"
fi

# 2. Announcement is informational — must NOT ask Y/n confirmation for the write test itself
# (Confirmation is only asked for "Continue without {service}?" — not for running the canary)
# Check that the canary context does not have a [Y/n] immediately after it
# Strategy: find lines with canary/write-test context and ensure no adjacent [Y/n] prompt
canary_line=$(grep -n -i 'canary\|test.*write\|write.*test' "$SCAFFOLD_CMD" | head -1 | cut -d: -f1)
if [ -n "$canary_line" ]; then
  nearby=$(sed -n "$((canary_line)),$(( canary_line + 3 ))p" "$SCAFFOLD_CMD")
  if contains "$nearby" "[Y/n]"; then
    fail "scaffold.md canary announcement appears to ask for Y/n confirmation (should be informational)"
  fi
fi

# 3. Canary content appears within the MCP Verification section (Step 0-MCP)
mcp_start=$(grep -n "Step 0-MCP" "$SCAFFOLD_CMD" | head -1 | cut -d: -f1)
orchestration_start=$(grep -n "^## Orchestration\|^### Step 0: Mode Selection" "$SCAFFOLD_CMD" | head -1 | cut -d: -f1)
if [ -z "$mcp_start" ] || [ -z "$orchestration_start" ]; then
  fail "scaffold.md missing Step 0-MCP or Orchestration anchor (cannot verify canary placement)"
else
  canary_line_check=$(grep -n -i 'canary\|test.*write\|write.*test' "$SCAFFOLD_CMD" | head -1 | cut -d: -f1)
  if [ -n "$canary_line_check" ]; then
    if [ "$canary_line_check" -lt "$mcp_start" ] || [ "$canary_line_check" -gt "$orchestration_start" ]; then
      fail "scaffold.md canary announcement is outside Step 0-MCP section (line $canary_line_check, expected between $mcp_start and $orchestration_start)"
    fi
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: scaffold.md canary-write announcement verified (UXP-2)"
exit "$FAIL"
