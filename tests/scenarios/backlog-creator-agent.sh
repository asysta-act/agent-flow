#!/usr/bin/env bash
# Test: agents/backlog-creator.md exists with correct frontmatter and required sections
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

AGENT_FILE="$REPO_ROOT/agents/backlog-creator.md"

# 1. File must exist
if [ ! -f "$AGENT_FILE" ]; then
  fail "agents/backlog-creator.md does not exist"
  exit 1
fi

# 2. Frontmatter: name: backlog-creator
if ! grep -q "^name: backlog-creator" "$AGENT_FILE"; then
  fail "agents/backlog-creator.md missing frontmatter 'name: backlog-creator'"
fi

# 3. Frontmatter: model: sonnet
if ! grep -q "^model: sonnet" "$AGENT_FILE"; then
  fail "agents/backlog-creator.md missing frontmatter 'model: sonnet'"
fi

# 4. Frontmatter: description field
if ! grep -q "^description:" "$AGENT_FILE"; then
  fail "agents/backlog-creator.md missing frontmatter 'description:' field"
fi

# 5. Frontmatter: style field
if ! grep -q "^style:" "$AGENT_FILE"; then
  fail "agents/backlog-creator.md missing frontmatter 'style:' field"
fi

# 6. Required sections in correct order
for section in "## Goal" "## Expertise" "## Process" "## Constraints"; do
  if ! grep -q "$section" "$AGENT_FILE"; then
    fail "agents/backlog-creator.md missing section: $section"
  fi
done

# 7. Process mentions spec mode (from spec / from description)
process_section=$(awk '/^## Process/{found=1} found && /^## Constraints/{found=0} found{print}' "$AGENT_FILE")
if ! contains_i "$process_section" "spec"; then
  fail "agents/backlog-creator.md Process section must mention spec mode (spec / specification)"
fi

# 8. Process mentions task mode (task / issue / backlog item)
if ! contains_i "$process_section" "task" && ! contains_i "$process_section" "issue" && ! contains_i "$process_section" "backlog"; then
  fail "agents/backlog-creator.md Process section must mention task/issue/backlog mode"
fi

# 9. Constraints section contains at least one NEVER rule
constraints_section=$(awk '/^## Constraints/{found=1} found && /^## /{if(!/^## Constraints/)found=0} found{print}' "$AGENT_FILE")
if ! contains_i "$constraints_section" "NEVER"; then
  fail "agents/backlog-creator.md Constraints section must contain at least one NEVER rule"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: agents/backlog-creator.md has correct frontmatter, sections, spec+task mode, and NEVER constraints"
exit "$FAIL"
