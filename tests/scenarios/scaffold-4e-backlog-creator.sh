#!/usr/bin/env bash
# Test: skills/scaffold/SKILL.md Step 4e references backlog-creator agent dispatch
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

SCAFFOLD_FILE="$REPO_ROOT/skills/scaffold/SKILL.md"

# 1. skills/scaffold/SKILL.md must exist
if [ ! -f "$SCAFFOLD_FILE" ]; then
  fail "skills/scaffold/SKILL.md does not exist"
  exit 1
fi

# 2. Step 4e must exist in scaffold
if ! grep -qi "Step 4e\|4e\." "$SCAFFOLD_FILE"; then
  fail "skills/scaffold/SKILL.md missing Step 4e"
fi

# 3. Step 4e must reference backlog-creator (or create-backlog skill)
# Extract section around 4e to verify backlog context
# Find the Step 4e section heading (### Step 4e), not casual references
step_4e_line=$(grep -in "^### Step 4e\|^#### Step 4e" "$SCAFFOLD_FILE" | head -1 | cut -d: -f1)

if [ -z "$step_4e_line" ]; then
  # Fallback: any "Step 4e:" pattern (heading-like)
  step_4e_line=$(grep -in "Step 4e:" "$SCAFFOLD_FILE" | head -1 | cut -d: -f1)
fi

if [ -n "$step_4e_line" ]; then
  # Extract a window of ~15 lines after Step 4e to check for backlog-creator reference
  step_4e_section=$(awk -v start="$step_4e_line" 'NR>=start && NR<=start+15{print}' "$SCAFFOLD_FILE")
  if ! matches_re "${step_4e_section,,}" 'backlog-creator|create-backlog|backlog.*creat|creat.*backlog'; then
    fail "skills/scaffold/SKILL.md Step 4e does not reference backlog-creator or create-backlog dispatch"
  fi
else
  fail "skills/scaffold/SKILL.md Step 4e not found (cannot verify backlog-creator reference)"
fi

# 4. Global check: backlog-creator is mentioned in scaffold at least once
if ! grep -qi "backlog-creator\|create-backlog" "$SCAFFOLD_FILE"; then
  fail "skills/scaffold/SKILL.md never references backlog-creator or create-backlog"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: skills/scaffold/SKILL.md Step 4e references backlog-creator agent dispatch"
exit "$FAIL"
