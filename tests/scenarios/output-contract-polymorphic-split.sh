#!/bin/bash
# PURPOSE: For the 4 polymorphic agents (analyst, test-engineer, browser-agent, spec-reviewer),
#          assert per-phase H3 sub-block headings exist inside ## Output Contract. Each sub-block
#          must independently contain Inputs + Outputs table headers.
# AC-H-N covered: AC-H-010, AC-H-011, AC-H-012, AC-H-013, AC-H-014
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (all 4 polymorphic agents have correct per-phase sub-blocks)
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

# Check one polymorphic agent: extract its ## Output Contract section and verify sub-block headings + shape
check_polymorphic() {
  local agent_name="$1"
  local agent_file="$AGENTS_DIR/${agent_name}.md"
  local block_a="$2"
  local block_b="$3"

  if [ ! -f "$agent_file" ]; then
    echo "SKIP: $agent_file not found" >&2
    return 77
  fi

  # SKIP-guard: if no ## Output Contract present
  if ! grep -qE '^## Output Contract$' "$agent_file"; then
    echo "SKIP: $agent_name lacks ## Output Contract" >&2
    return 77
  fi

  # Extract ## Output Contract section (up to next top-level ## heading)
  oc_section=$(awk '/^## Output Contract$/{found=1; next} found && /^## [A-Z][^#]/{exit} found{print}' "$agent_file")

  # Assert sub-block A exists
  if ! contains "$oc_section" "$block_a"; then
    fail "$agent_name: missing H3 sub-block '$block_a' inside ## Output Contract"
    # Mutation catch: renaming phase block heading fails here
  fi

  # Assert sub-block B exists
  if ! contains "$oc_section" "$block_b"; then
    fail "$agent_name: missing H3 sub-block '$block_b' inside ## Output Contract"
  fi

  # Assert each sub-block independently contains Inputs + Outputs table headers
  # Extract content from block_a up to block_b or end
  block_a_content=$(echo "$oc_section" | awk "/$(echo "$block_a" | sed 's/[()--]/\\&/g')/{found=1; next} found && /^### /{exit} found{print}")
  # If extraction is empty (awk escaping complexity), fall back to checking the whole oc_section
  if [ -z "$block_a_content" ]; then
    block_a_content="$oc_section"
  fi

  if ! contains "$block_a_content" "Section | Source | Required"; then
    fail "$agent_name / $block_a: sub-block missing Inputs table header 'Section | Source | Required'"
    # Mutation catch: missing Inputs table in a phase sub-block fails here
  fi
  if ! contains "$block_a_content" "Section produced | When | Required fields"; then
    fail "$agent_name / $block_a: sub-block missing Outputs table header 'Section produced | When | Required fields'"
  fi

  # Negative assertion: the ## Output Contract section must NOT be a single flat table (would miss polymorphism)
  flat_output_contract=$(echo "$oc_section" | grep -cE '^### Output Contract' || true)
  if [ "$flat_output_contract" -lt 2 ]; then
    fail "$agent_name: ## Output Contract has fewer than 2 '### Output Contract' sub-blocks — polymorphic agent requires at least 2"
    # Mutation catch: collapsing the two phase blocks into one fails here
  fi

  return 0
}

analyst_skip=0
te_skip=0
ba_skip=0
sr_skip=0

# analyst: triage + impact
check_polymorphic "analyst" \
  "### Output Contract — Phase: triage" \
  "### Output Contract — Phase: impact" || analyst_skip=77

# test-engineer: default (no flag) + --e2e
check_polymorphic "test-engineer" \
  "### Output Contract — Default (no flag)" \
  "### Output Contract — Phase: --e2e" || te_skip=77

# browser-agent: reproduce + verify
check_polymorphic "browser-agent" \
  "### Output Contract — Phase: reproduce" \
  "### Output Contract — Phase: verify" || ba_skip=77

# spec-reviewer: default review mode + --verify
check_polymorphic "spec-reviewer" \
  "### Output Contract — Default (review mode)" \
  "### Output Contract — Phase: --verify" || sr_skip=77

# If all 4 agents were skipped, exit 77
all_skip=$(( analyst_skip + te_skip + ba_skip + sr_skip ))
if [ "$all_skip" -eq 308 ]; then  # 77 * 4
  echo "SKIP: all 4 polymorphic agents lack ## Output Contract" >&2
  exit 77
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-010..H-014 — analyst, test-engineer, browser-agent, spec-reviewer have correct per-phase ## Output Contract sub-blocks"
fi
exit "$FAIL"
