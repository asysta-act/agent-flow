#!/bin/bash
# PURPOSE: For each agent file that HAS a ## Output Contract section, assert the section is
#          well-formed: Inputs table header, Outputs table header, and at least one backtick-quoted
#          ## Heading row in the Outputs table. Polymorphic agents assert per-phase sub-blocks.
# AC-H-N covered: AC-H-003, AC-H-014
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (all 17 agents have well-formed Output Contract)
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

# Polymorphic agents: these declare per-phase H3 sub-blocks instead of a single Inputs/Outputs pair
POLYMORPHIC="analyst test-engineer browser-agent spec-reviewer"

checked=0
skipped=0

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name=$(basename "$agent_file" .md)

  # SKIP-guard: if the agent has no ## Output Contract yet, skip this file (transition window )
  if ! grep -qE '^## Output Contract$' "$agent_file"; then
    skipped=$((skipped + 1))
    continue
  fi

  checked=$((checked + 1))

  # Extract the ## Output Contract section content (from ## Output Contract up to next ^## line)
  oc_section=$(awk '/^## Output Contract$/{found=1; next} found && /^## [A-Z]/{exit} found{print}' "$agent_file")

  # Check if this is a polymorphic agent
  is_poly=0
  for poly in $POLYMORPHIC; do
    if [ "$agent_name" = "$poly" ]; then
      is_poly=1
      break
    fi
  done

  if [ "$is_poly" -eq 1 ]; then
    # Polymorphic: assert H3 sub-blocks exist; per-block shape validated in polymorphic-split scenario
    # Here we just assert both Inputs AND Outputs headers appear somewhere in the oc_section
    # (they will be inside the sub-blocks per design.md §1.2 with #### headings)
    if ! contains "$oc_section" "Section | Source | Required"; then
      fail "$agent_name (polymorphic): ## Output Contract section missing Inputs table header 'Section | Source | Required'"
      # Mutation catch: removing the Inputs table entirely from a poly agent fails here
    fi
    if ! contains "$oc_section" "Section produced | When | Required fields"; then
      fail "$agent_name (polymorphic): ## Output Contract section missing Outputs table header 'Section produced | When | Required fields'"
    fi
    # Assert at least one backtick-quoted ## Heading in Outputs column
    if ! matches_re "$oc_section" '`## [A-Za-z][A-Za-z _:-]*`'; then
      fail "$agent_name (polymorphic): ## Output Contract Outputs table has no backtick-quoted ## Heading row"
      # Mutation catch: removing backticks from a heading in the Outputs table fails here
    fi
  else
    # Non-polymorphic: assert top-level Inputs and Outputs table headers present
    if ! contains "$oc_section" "Section | Source | Required"; then
      fail "$agent_name: ## Output Contract section missing Inputs table header '| Section | Source | Required |'"
      # Mutation catch: wrong column name (e.g., 'Input' instead of 'Section') fails here
    fi
    if ! contains "$oc_section" "Section produced | When | Required fields"; then
      fail "$agent_name: ## Output Contract section missing Outputs table header '| Section produced | When | Required fields |'"
      # Mutation catch: wrong column name (e.g., 'Output' instead of 'Section produced') fails here
    fi
    # Assert at least one backtick-quoted ## Heading in Outputs table
    if ! matches_re "$oc_section" '`## [A-Za-z][A-Za-z _:-]*`'; then
      fail "$agent_name: ## Output Contract Outputs table has no backtick-quoted ## Heading row"
    fi
    # Negative assertion: no prose-only output description (if section has >10 lines and no table, that's wrong)
    line_count=$(wc -l <<< "$oc_section")
    table_lines=$(grep -c '|' <<< "$oc_section" || true)
    if [ "$line_count" -gt 10 ] && [ "$table_lines" -lt 4 ]; then
      fail "$agent_name: ## Output Contract section appears to be prose-only (no table rows) requires tables"
    fi
  fi
done

# If every agent was skipped, exit 77
if [ "$checked" -eq 0 ] && [ "$skipped" -gt 0 ]; then
  echo "SKIP: all $skipped agents lack ## Output Contract section" >&2
  exit 77
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-003, AC-H-014 — $checked agents have well-formed ## Output Contract sections ($skipped skipped during transition)"
fi
exit "$FAIL"
