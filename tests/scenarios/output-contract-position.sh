#!/bin/bash
# PURPOSE: Assert positional invariant — when ## Output Contract is present, it sits AFTER the
#          last ^## Process line and BEFORE ^## Constraints in every agent file.
#          Handles browser-agent edge case: its Process headings are '## Process: Phase X' not
#          '## Process' bare, so we anchor to the LAST process-family line (review finding f-d2e44f).
# AC-H-N covered: AC-H-002
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (all 17 agents have correctly positioned ## Output Contract)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

AGENTS_DIR="$REPO_ROOT/agents"
if [ ! -d "$AGENTS_DIR" ]; then
  echo "SKIP: agents/ directory not found" >&2
  exit 77
fi

checked=0
skipped=0

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name=$(basename "$agent_file" .md)

  # SKIP-guard: if no ## Output Contract present, skip this file (transition window)
  if ! grep -qE '^## Output Contract$' "$agent_file"; then
    skipped=$((skipped + 1))
    continue
  fi

  checked=$((checked + 1))

  # Extract line numbers for positional check
  # process_line: the LAST line matching ^## Process (or ^## Process:) — handles browser-agent
  # whose headings are "## Process: Phase reproduce" and "## Process: Phase verify"
  # Review finding f-d2e44f: anchor to LAST process-family line, not first
  process_line=$(grep -nE '^## Process' "$agent_file" | tail -1 | cut -d: -f1)
  oc_line=$(grep -nE '^## Output Contract$' "$agent_file" | head -1 | cut -d: -f1)
  cons_line=$(grep -nE '^## Constraints$' "$agent_file" | head -1 | cut -d: -f1)

  if [ -z "$process_line" ]; then
    fail "$agent_name: no '## Process' heading found — required for position check"
    continue
  fi
  if [ -z "$oc_line" ]; then
    # Should not happen since we checked above, but guard anyway
    fail "$agent_name: ## Output Contract line number could not be determined"
    continue
  fi
  if [ -z "$cons_line" ]; then
    fail "$agent_name: no '## Constraints' heading found — required for position check"
    continue
  fi

  # Assert: last_process_line < oc_line < cons_line
  if [ "$process_line" -ge "$oc_line" ]; then
    fail "$agent_name: '## Output Contract' (line $oc_line) must come AFTER last '## Process' line (line $process_line)"
    # Mutation catch: inserting ## Output Contract before ## Process fails here
  fi
  if [ "$oc_line" -ge "$cons_line" ]; then
    fail "$agent_name: '## Output Contract' (line $oc_line) must come BEFORE '## Constraints' (line $cons_line)"
    # Mutation catch: inserting ## Output Contract after ## Constraints fails here
  fi

  # Extra negative assertion: no duplicate ## Output Contract headings
  oc_count=$(grep -cE '^## Output Contract$' "$agent_file" || true)
  if [ "$oc_count" -gt 1 ]; then
    fail "$agent_name: found $oc_count '## Output Contract' headings — only one is allowed"
  fi
done

if [ "$checked" -eq 0 ] && [ "$skipped" -gt 0 ]; then
  echo "SKIP: all $skipped agents lack ## Output Contract section" >&2
  exit 77
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-002 — $checked agents have ## Output Contract correctly positioned between ## Process and ## Constraints"
fi
exit "$FAIL"
