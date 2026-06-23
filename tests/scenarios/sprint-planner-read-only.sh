#!/usr/bin/env bash
# Test: sprint-planner is a read-only agent — no write-tool phrases in Process section,
#       and is listed in CLAUDE.md read-only agents
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

AGENT_FILE="$REPO_ROOT/agents/sprint-planner.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

# 1. File must exist to test it
if [ ! -f "$AGENT_FILE" ]; then
  fail "agents/sprint-planner.md does not exist — cannot verify read-only status"
  exit 1
fi

# 2. Extract the ## Process section only (between ## Process and ## Constraints)
process_section=$(awk '/^## Process/{found=1} found && /^## Constraints/{found=0} found{print}' "$AGENT_FILE")

# 3. No write-tool phrases in Process section
if contains_i "$process_section" "Write tool"; then
  fail "sprint-planner.md Process section contains 'Write tool' — read-only agent must not write files"
fi
if contains_i "$process_section" "Edit tool"; then
  fail "sprint-planner.md Process section contains 'Edit tool' — read-only agent must not edit files"
fi
if contains_i "$process_section" "write to file"; then
  fail "sprint-planner.md Process section contains 'write to file' — read-only agent must not write files"
fi
if contains_i "$process_section" "create file"; then
  fail "sprint-planner.md Process section contains 'create file' — read-only agent must not create files"
fi
if contains_i "$process_section" "save file"; then
  fail "sprint-planner.md Process section contains 'save file' — read-only agent must not save files"
fi

# 4. sprint-planner appears in CLAUDE.md
if ! grep -q "sprint-planner" "$CLAUDE_MD"; then
  fail "sprint-planner not mentioned in CLAUDE.md"
fi

# 5. Verify sprint-planner is in the Read-only agents clause of CLAUDE.md
readonly_line=$(grep -i "read.only agents" "$CLAUDE_MD" | head -1)
if [ -n "$readonly_line" ]; then
  readonly_section=$(awk '/[Rr]ead-only agents/{found=1; lines=0} found{print; lines++; if(lines>3)found=0}' "$CLAUDE_MD")
  if ! contains_i "$readonly_section" "sprint-planner"; then
    fail "sprint-planner not listed in CLAUDE.md read-only agents line"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: sprint-planner is read-only — no write-tool phrases in Process, listed in CLAUDE.md read-only agents"
exit "$FAIL"
