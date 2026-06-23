#!/usr/bin/env bash
# Test: agents/sprint-planner.md exists with correct frontmatter and required sections,
#       including NEVER re-rank constraint
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

AGENT_FILE="$REPO_ROOT/agents/sprint-planner.md"

# 1. File must exist
if [ ! -f "$AGENT_FILE" ]; then
  fail "agents/sprint-planner.md does not exist"
  exit 1
fi

# 2. Frontmatter: name: sprint-planner
if ! grep -q "^name: sprint-planner" "$AGENT_FILE"; then
  fail "agents/sprint-planner.md missing frontmatter 'name: sprint-planner'"
fi

# 3. Frontmatter: model: sonnet
if ! grep -q "^model: sonnet" "$AGENT_FILE"; then
  fail "agents/sprint-planner.md missing frontmatter 'model: sonnet'"
fi

# 4. Frontmatter: description field
if ! grep -q "^description:" "$AGENT_FILE"; then
  fail "agents/sprint-planner.md missing frontmatter 'description:' field"
fi

# 5. Frontmatter: style field
if ! grep -q "^style:" "$AGENT_FILE"; then
  fail "agents/sprint-planner.md missing frontmatter 'style:' field"
fi

# 6. Required sections in correct order
for section in "## Goal" "## Expertise" "## Process" "## Constraints"; do
  if ! grep -q "$section" "$AGENT_FILE"; then
    fail "agents/sprint-planner.md missing section: $section"
  fi
done

# 7. Verify section order: Goal before Expertise before Process before Constraints
goal_line=$(grep -n "^## Goal" "$AGENT_FILE" | head -1 | cut -d: -f1)
expertise_line=$(grep -n "^## Expertise" "$AGENT_FILE" | head -1 | cut -d: -f1)
process_line=$(grep -n "^## Process" "$AGENT_FILE" | head -1 | cut -d: -f1)
constraints_line=$(grep -n "^## Constraints" "$AGENT_FILE" | head -1 | cut -d: -f1)

if [ -n "$goal_line" ] && [ -n "$expertise_line" ] && [ "$goal_line" -ge "$expertise_line" ]; then
  fail "agents/sprint-planner.md: ## Goal must appear before ## Expertise"
fi
if [ -n "$expertise_line" ] && [ -n "$process_line" ] && [ "$expertise_line" -ge "$process_line" ]; then
  fail "agents/sprint-planner.md: ## Expertise must appear before ## Process"
fi
if [ -n "$process_line" ] && [ -n "$constraints_line" ] && [ "$process_line" -ge "$constraints_line" ]; then
  fail "agents/sprint-planner.md: ## Process must appear before ## Constraints"
fi

# 8. Constraints section must include "NEVER re-rank"
constraints_section=$(awk '/^## Constraints/{found=1} found && /^## /{if(!/^## Constraints/)found=0} found{print}' "$AGENT_FILE")
if ! matches_re "${constraints_section,,}" 'never.*re-rank|never.*rerank|never.*re.rank'; then
  fail "agents/sprint-planner.md Constraints section must include 'NEVER re-rank' rule"
fi

# 9. Constraints section contains at least one NEVER rule
if ! contains_i "$constraints_section" "NEVER"; then
  fail "agents/sprint-planner.md Constraints section must contain at least one NEVER rule"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: agents/sprint-planner.md has correct frontmatter, sections, section order, and NEVER re-rank constraint"
exit "$FAIL"
