#!/bin/bash
# PURPOSE: Validate frontmatter for the 17-agent roster.
#          Stale names (triage-analyst, code-analyst, e2e-test-engineer, reproducer,
#          browser-verifier, stack-selector) must not be present. Validates 4 required
#          frontmatter fields (name, description, model, style) for all 17 agents.
# AC-H-N covered: AC-H-082
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (17 agents, all with correct frontmatter)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if matches_re "$REPO_ROOT" '\.forge'; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# Current roster: 17 agents (stack-selector deleted)
AGENTS=(
  acceptance-gate analyst architect backlog-creator browser-agent
  deployment-verifier fixer priority-engine publisher reviewer
  rollback-agent scaffolder spec-analyst spec-reviewer spec-writer
  sprint-planner test-engineer
)

for agent in "${AGENTS[@]}"; do
  file="$REPO_ROOT/agents/$agent.md"
  if [ ! -f "$file" ]; then
    fail "Missing agent file: agents/$agent.md"
    continue
  fi
  for field in name description model style; do
    if ! grep -qE "^${field}:" "$file"; then
      fail "$agent.md missing frontmatter field: $field"
      # Mutation catch: removing any frontmatter field from any agent fails here
    fi
  done
done

# Assert stack-selector is NOT present (AC-H-040 / )
if [ -f "$REPO_ROOT/agents/stack-selector.md" ]; then
  fail "agents/stack-selector.md exists — must be deleted; v9 roster has 17 agents"
fi

# Assert agent count is exactly 17
actual_count=$(find "$REPO_ROOT/agents" -maxdepth 1 -name "*.md" | wc -l)
if [ "$actual_count" -ne 17 ]; then
  fail "agents/ contains $actual_count .md files, expected exactly 17"
  # Mutation catch: adding or forgetting to delete an agent file fails here
fi

# Negative assertions: stale v7 names must NOT be present
for stale in triage-analyst code-analyst e2e-test-engineer reproducer browser-verifier stack-selector; do
  if [ -f "$REPO_ROOT/agents/$stale.md" ]; then
    fail "Stale agent file agents/$stale.md still exists — must be removed"
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS: AC-H-082 — all 17 agents have all 4 required frontmatter fields (name, description, model, style)"
exit "$FAIL"
