#!/usr/bin/env bash
# Hidden tests: check-setup SKILL.md edge cases
# Validates: insecure workaround absent, curl guard present, Step 7 path reuse
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
SKILL="$REPO_ROOT/skills/check-setup/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

if [ ! -f "$SKILL" ]; then
  echo "FAIL: skills/check-setup/SKILL.md not found at $SKILL"
  exit 1
fi

# -----------------------------------------------------------------------
# Edge case 1: NODE_TLS_REJECT_UNAUTHORIZED must NOT appear
# Recommending NODE_TLS_REJECT_UNAUTHORIZED=0 disables TLS verification entirely
# and is a security anti-pattern. The fix must use --use-system-ca instead.
# -----------------------------------------------------------------------
echo "--- Edge case 1: NODE_TLS_REJECT_UNAUTHORIZED must not appear ---"

if grep -q 'NODE_TLS_REJECT_UNAUTHORIZED' "$SKILL"; then
  fail "SECURITY: NODE_TLS_REJECT_UNAUTHORIZED found in $SKILL — insecure workaround must not be recommended"
else
  echo "OK: NODE_TLS_REJECT_UNAUTHORIZED not present — secure TLS guidance only"
fi

# -----------------------------------------------------------------------
# Edge case 2: curl availability guard must be present
# The TLS diagnostic uses curl, so the skill must check whether curl exists
# before invoking it (which curl / command -v curl / curl --version).
# -----------------------------------------------------------------------
echo "--- Edge case 2: curl availability guard ---"

if grep -qE 'which curl|command -v curl|curl.*--version' "$SKILL"; then
  echo "OK: curl availability guard present (which curl / command -v curl)"
else
  fail "Edge case 2: No curl availability guard found — curl probe assumes curl is installed without checking"
fi

# -----------------------------------------------------------------------
# Edge case 3: Step 7 references Step 3a for path reuse
# Step 7 must explicitly reference the path resolved in Step 3a rather than
# running its own Glob. The word "Step 3a" (or "3a") must appear in the
# context of Step 7's trackers.md instructions.
# -----------------------------------------------------------------------
echo "--- Edge case 3: Step 7 references Step 3a for path reuse ---"

# Find the line number of step 7 instructions for trackers.md
step7_line=$(grep -n '^7\.\|^### Block 2\|Compare MCP servers\|MCP Server Detection' "$SKILL" | head -1 | cut -d: -f1 || true)
if [ -z "$step7_line" ]; then
  fail "Edge case 3: Could not locate Step 7 in $SKILL"
else
  # Extract the region around Step 7 (up to 30 lines) and check for Step 3a reference
  context=$(sed -n "${step7_line},$((step7_line + 30))p" "$SKILL")
  if grep -qi 'Step 3a\|3a\|resolved.*path\|path.*3a' <<< "$context"; then
    echo "OK: Step 7 references Step 3a resolved path within 30 lines of its definition"
  else
    fail "Edge case 3: Step 7 does not reference Step 3a path — may re-glob or use bare path"
  fi
fi

# -----------------------------------------------------------------------
# Edge case 4: Step 7 must NOT contain its own Glob call for trackers.md
# If Step 7 re-globs, it defeats the purpose of the fix.
# -----------------------------------------------------------------------
echo "--- Edge case 4: Step 7 must not contain a redundant Glob for trackers.md ---"

# Extract Step 7 region (Block 2 through Block 3 boundary)
block2_start=$(grep -n 'Block 2\|Compare MCP servers' "$SKILL" | head -1 | cut -d: -f1 || true)
block3_start=$(grep -n 'Block 3\|Connectivity' "$SKILL" | head -1 | cut -d: -f1 || true)

if [ -n "$block2_start" ] && [ -n "$block3_start" ] && [ "$block3_start" -gt "$block2_start" ]; then
  step7_region=$(sed -n "${block2_start},${block3_start}p" "$SKILL")
  # A redundant Glob in Step 7 would look like: Glob `**/trackers.md` or Glob `.claude/plugins/**`
  if grep -qE "Glob.*trackers|Glob.*\.claude/plugins" <<< "$step7_region"; then
    fail "Edge case 4: Step 7 contains its own Glob for trackers.md — must reuse Step 3a resolved path"
  else
    echo "OK: Step 7 does not redundantly re-Glob for trackers.md"
  fi
else
  # Fallback: just ensure no second Glob after the first occurrence in Step 3a region
  glob_count=$(grep -c 'Glob.*trackers\|Glob.*\.claude/plugins' "$SKILL" || true)
  if [ "$glob_count" -le 1 ]; then
    echo "OK: trackers.md Glob appears at most once (Step 3a only)"
  else
    fail "Edge case 4: trackers.md Glob appears $glob_count times — Step 7 should reuse Step 3a path, not re-Glob"
  fi
fi

# -----------------------------------------------------------------------
# Final result
# -----------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup edge cases — no insecure NODE_TLS_REJECT_UNAUTHORIZED, curl guard present, Step 7 reuses Step 3a path"
fi
exit "$FAIL"
