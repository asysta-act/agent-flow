#!/bin/bash
# PURPOSE: Validate section ordering for the 17-agent roster, tolerating the
#          optional ## Output Contract section between ## Process and ## Constraints.
#          Verifies the core Goal -> Expertise -> Process -> Constraints order is preserved, and
#          if ## Output Contract is present, it sits between Process and Constraints (AC-H-002).
# AC-H-N covered: AC-H-080, AC-H-081
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (17 agents with correct section order including optional Output Contract)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if contains "$REPO_ROOT" ".forge"; then
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

  goal_line=$(grep -nE '^## Goal$' "$file" | head -1 | cut -d: -f1)
  expertise_line=$(grep -nE '^## Expertise$' "$file" | head -1 | cut -d: -f1)
  # For process_line: use FIRST ^## Process match (may be bare or with suffix)
  process_line=$(grep -nE '^## Process' "$file" | head -1 | cut -d: -f1)
  constraints_line=$(grep -nE '^## Constraints$' "$file" | head -1 | cut -d: -f1)

  if [ -z "$goal_line" ]; then
    fail "$agent.md missing ## Goal section"
    continue
  fi
  if [ -z "$expertise_line" ]; then
    fail "$agent.md missing ## Expertise section"
    continue
  fi
  if [ -z "$process_line" ]; then
    fail "$agent.md missing ## Process section"
    continue
  fi
  if [ -z "$constraints_line" ]; then
    fail "$agent.md missing ## Constraints section"
    continue
  fi

  # Core ordering: Goal < Expertise < Process < Constraints
  if [ "$goal_line" -ge "$expertise_line" ]; then
    fail "$agent.md: ## Goal (line $goal_line) must precede ## Expertise (line $expertise_line)"
    # Mutation catch: swapping section order fails here
  fi
  if [ "$expertise_line" -ge "$process_line" ]; then
    fail "$agent.md: ## Expertise (line $expertise_line) must precede ## Process (line $process_line)"
  fi
  if [ "$process_line" -ge "$constraints_line" ]; then
    fail "$agent.md: ## Process (line $process_line) must precede ## Constraints (line $constraints_line)"
  fi

  # Optional position assertion: if ## Output Contract present, it must sit between
  # last ## Process line and ## Constraints
  if grep -qE '^## Output Contract$' "$file"; then
    last_process_line=$(grep -nE '^## Process' "$file" | tail -1 | cut -d: -f1)
    oc_line=$(grep -nE '^## Output Contract$' "$file" | head -1 | cut -d: -f1)

    if [ "$last_process_line" -ge "$oc_line" ]; then
      fail "$agent.md: ## Output Contract (line $oc_line) must come AFTER last ## Process line (line $last_process_line)"
    fi
    if [ "$oc_line" -ge "$constraints_line" ]; then
      fail "$agent.md: ## Output Contract (line $oc_line) must come BEFORE ## Constraints (line $constraints_line)"
    fi
  fi
done

# Assert stack-selector does not exist
if [ -f "$REPO_ROOT/agents/stack-selector.md" ]; then
  fail "agents/stack-selector.md exists — must be deleted"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: AC-H-080, AC-H-081 — all 17 agents follow Goal -> Expertise -> Process -> [Output Contract] -> Constraints section order"
exit "$FAIL"
