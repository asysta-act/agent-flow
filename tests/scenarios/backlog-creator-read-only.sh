#!/usr/bin/env bash
# Test: backlog-creator is a read-only agent — no write-tool phrases in Process section,
#       and is listed in CLAUDE.md read-only agents
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

AGENT_FILE="$REPO_ROOT/agents/backlog-creator.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

# 1. File must exist to test it
if [ ! -f "$AGENT_FILE" ]; then
  fail "agents/backlog-creator.md does not exist — cannot verify read-only status"
  exit 1
fi

# 2. Extract the ## Process section only (between ## Process and ## Constraints)
process_section=$(awk '/^## Process/{found=1} found && /^## Constraints/{found=0} found{print}' "$AGENT_FILE")

# 3. No write-tool phrases in Process section
if contains_i "$process_section" "Write tool"; then
  fail "backlog-creator.md Process section contains 'Write tool' — read-only agent must not write files"
fi
if contains_i "$process_section" "Edit tool"; then
  fail "backlog-creator.md Process section contains 'Edit tool' — read-only agent must not edit files"
fi
if contains_i "$process_section" "write to file"; then
  fail "backlog-creator.md Process section contains 'write to file' — read-only agent must not write files"
fi
if contains_i "$process_section" "create file"; then
  fail "backlog-creator.md Process section contains 'create file' — read-only agent must not create files"
fi
if contains_i "$process_section" "save file"; then
  fail "backlog-creator.md Process section contains 'save file' — read-only agent must not save files"
fi

# 4. backlog-creator appears in CLAUDE.md read-only agents list
# The read-only agents line in CLAUDE.md names them explicitly
if ! grep -q "backlog-creator" "$CLAUDE_MD"; then
  fail "backlog-creator not mentioned in CLAUDE.md"
fi

# 5. Verify backlog-creator is in the Read-only agents clause of CLAUDE.md
readonly_line=$(grep -i "read.only agents" "$CLAUDE_MD" | head -1)
if [ -n "$readonly_line" ]; then
  # There is a read-only agents line; check backlog-creator is on or near it
  readonly_section=$(awk '/[Rr]ead-only agents/{found=1; lines=0} found{print; lines++; if(lines>3)found=0}' "$CLAUDE_MD")
  if ! contains_i "$readonly_section" "backlog-creator"; then
    fail "backlog-creator not listed in CLAUDE.md read-only agents line"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: backlog-creator is read-only — no write-tool phrases in Process, listed in CLAUDE.md read-only agents"
exit "$FAIL"
