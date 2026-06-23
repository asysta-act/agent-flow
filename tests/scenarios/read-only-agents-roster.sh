#!/bin/bash
# PURPOSE: Validate the 9-agent read-only roster.
#          Stale names (triage-analyst, code-analyst, stack-selector) must not be present. Verifies
#          none of the 9 read-only agents contain write-tool phrases in their Process sections.
#          Final list: analyst reviewer spec-analyst architect priority-engine
#          spec-reviewer acceptance-gate backlog-creator sprint-planner (AC-H-083).
# AC-H-N covered: AC-H-083
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (9 correct read-only agents pass write-tool phrase check)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# Read-only agents (9 agents)
READ_ONLY_AGENTS=(
  analyst reviewer spec-analyst architect priority-engine
  spec-reviewer acceptance-gate backlog-creator sprint-planner
)

for agent in "${READ_ONLY_AGENTS[@]}"; do
  file="$REPO_ROOT/agents/$agent.md"
  if [ ! -f "$file" ]; then
    fail "Missing read-only agent file: agents/$agent.md"
    continue
  fi

  # Extract the ## Process section content (between first ## Process and ## Constraints or ## Output Contract)
  process_section=$(awk '/^## Process/{found=1} found && /^## (Constraints|Output Contract)/{found=0} found{print}' "$file")

  # Assert no write-tool phrases in Process section
  if contains_i "$process_section" "Write tool"; then
    fail "$agent.md Process section contains 'Write tool' — read-only agent must not write files"
    # Mutation catch: accidentally adding a write step to a read-only agent's Process fails here
  fi
  if contains_i "$process_section" "Edit tool"; then
    fail "$agent.md Process section contains 'Edit tool' — read-only agent must not edit files"
  fi
  if contains_i "$process_section" "write to file"; then
    fail "$agent.md Process section contains 'write to file' — read-only agent must not write files"
  fi
  if contains_i "$process_section" "create file"; then
    fail "$agent.md Process section contains 'create file' — read-only agent must not create files"
  fi
  if contains_i "$process_section" "save file"; then
    fail "$agent.md Process section contains 'save file' — read-only agent must not save files"
  fi
done

# Confirm the count is exactly 9
expected_count=9
actual_count="${#READ_ONLY_AGENTS[@]}"
if [ "$actual_count" -ne "$expected_count" ]; then
  fail "Read-only agents array has $actual_count entries, expected $expected_count"
fi

# Negative assertion: stale v7 read-only agent names must not exist as files
for stale in triage-analyst code-analyst stack-selector; do
  if [ -f "$REPO_ROOT/agents/$stale.md" ]; then
    fail "Stale agent agents/$stale.md still exists — roster does not include it"
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS: AC-H-083 — all 9 read-only agents have no write-tool phrases in Process sections"
exit "$FAIL"
