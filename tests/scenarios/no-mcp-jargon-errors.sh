#!/bin/bash
# Test: No "MCP server for {Type} is not available" in user-facing error messages (UXP-3)
# Validates: jargon replaced with friendly "Cannot connect to your {Type} issue tracker"
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

# Files that MUST have the old pattern replaced (standard error files)
# (estimate and pipeline-status deleted)
STANDARD_ERROR_FILES=(
  "skills/analyze-bug/SKILL.md"
  "skills/changelog/SKILL.md"
  "skills/metrics/SKILL.md"
  "skills/prioritize/SKILL.md"
)

# Additional files with user-facing errors that must be updated
ADDITIONAL_FILES=(
  "skills/publish/SKILL.md"
  "skills/scaffold/SKILL.md"
  "skills/implement-feature/SKILL.md"
)

OLD_PATTERN='MCP server for.*is not available'
NEW_PATTERN='Cannot connect to your'

# 1. Check standard error files: old pattern must be absent
for rel_path in "${STANDARD_ERROR_FILES[@]}"; do
  f="$REPO_ROOT/$rel_path"
  if [ ! -f "$f" ]; then
    fail "File not found: $rel_path"
    continue
  fi
  if grep -q "$OLD_PATTERN" "$f"; then
    fail "$rel_path still contains old MCP jargon: 'MCP server for {Type} is not available'"
  fi
done

# 2. Check standard error files: new pattern must be present
for rel_path in "${STANDARD_ERROR_FILES[@]}"; do
  f="$REPO_ROOT/$rel_path"
  [ ! -f "$f" ] && continue  # already failed above
  if ! grep -q "$NEW_PATTERN" "$f"; then
    fail "$rel_path missing new friendly error: 'Cannot connect to your'"
  fi
done

# 3. Check additional files: user-facing error occurrences must use new pattern
# fix-bugs.md: line ~80 (standard error) must be updated; lines ~99 and ~321 (agent dispatch context) may keep old pattern
# We check that the STOP/Display/Block-user-facing occurrences are updated.
# Strategy: check that at least one occurrence of the new pattern exists in each additional file.
for rel_path in "${ADDITIONAL_FILES[@]}"; do
  f="$REPO_ROOT/$rel_path"
  if [ ! -f "$f" ]; then
    fail "File not found: $rel_path"
    continue
  fi
  # These files have a mix of user-facing and internal references.
  # We verify the new pattern is present (at least one user-facing occurrence was updated).
  if ! grep -q "$NEW_PATTERN" "$f"; then
    fail "$rel_path missing new friendly error pattern: 'Cannot connect to your'"
  fi
done

# 4. scaffold/SKILL.md MCP Pre-flight Check standard error must use new pattern
# (The pre-flight section has a "Standard error message" block — verify it)
SCAFFOLD="$REPO_ROOT/skills/scaffold/SKILL.md"
preflight_line=$(grep -n "Standard error message" "$SCAFFOLD" | head -1 | cut -d: -f1)
if [ -n "$preflight_line" ]; then
  # Check the 5 lines after "Standard error message:" header
  context=$(sed -n "$preflight_line,$((preflight_line + 5))p" "$SCAFFOLD")
  if grep -q "$OLD_PATTERN" <<< "$context"; then
    fail "scaffold.md MCP Pre-flight 'Standard error message' still uses old jargon"
  fi
fi

# 5. core/mcp-preflight.md must not have old pattern in Reason/Recommendation fields
MCP_PREFLIGHT="$REPO_ROOT/core/mcp-preflight.md"
if [ -f "$MCP_PREFLIGHT" ]; then
  # Extract Reason/Recommendation lines and check for old pattern
  if grep -i 'Reason:\|Recommendation:' "$MCP_PREFLIGHT" | grep -q "$OLD_PATTERN"; then
    fail "core/mcp-preflight.md Reason/Recommendation fields still use old MCP jargon"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: No MCP jargon in user-facing error messages — all 7 files verified (UXP-3)"
exit "$FAIL"
