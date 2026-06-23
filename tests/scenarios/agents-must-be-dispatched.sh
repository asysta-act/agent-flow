#!/bin/bash
# PURPOSE: Prevent future orphan agents. Every agent file under
#          agents/*.md MUST appear as a subagent_type='agent-flow:{name}' literal in at
#          least one file under skills/**/*.md. Catches the stack-selector orphan defect.
# AC-H-N covered: AC-H-034
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (stack-selector deleted; all 17 remaining agents are dispatched)
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
SKILLS_DIR="$REPO_ROOT/skills"

if [ ! -d "$AGENTS_DIR" ]; then
  fail "agents/ directory not found at $AGENTS_DIR"
  exit 1
fi
if [ ! -d "$SKILLS_DIR" ]; then
  fail "skills/ directory not found at $SKILLS_DIR"
  exit 1
fi

agent_count=0
orphan_count=0

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name=$(basename "$agent_file" .md)

  # Extract name: from YAML frontmatter (first occurrence)
  frontmatter_name=$(grep -m1 -E '^name:\s*' "$agent_file" | sed 's/^name:[[:space:]]*//' | tr -d '\r')

  if [ -z "$frontmatter_name" ]; then
    fail "$agent_name: no 'name:' frontmatter field found"
    continue
  fi

  agent_count=$((agent_count + 1))

  # Build the strict dispatch pattern: subagent_type='agent-flow:{name}'
  dispatch_pattern="subagent_type='agent-flow:${frontmatter_name}'"

  # Search in all skills/**/*.md files
  found=0
  if grep -rl -F "$dispatch_pattern" "$SKILLS_DIR" --include="*.md" 2>/dev/null | grep -q .; then
    found=1
  fi

  if [ "$found" -eq 0 ]; then
    fail "agent '$frontmatter_name' ($agent_name) is not dispatched by any skill via '$dispatch_pattern' — orphan agent"
    orphan_count=$((orphan_count + 1))
    # Mutation catch: adding an agent file without adding a skill dispatch fails here
    # Also catches the stack-selector orphan on the current codebase
  fi
done

if [ "$agent_count" -eq 0 ]; then
  fail "No agent files found in $AGENTS_DIR"
  exit 1
fi

# Negative assertion: assert stack-selector is NOT present (AC-H-040)
# If stack-selector.md exists it will fail (file should have been deleted)
if [ -f "$AGENTS_DIR/stack-selector.md" ]; then
  fail "agents/stack-selector.md still exists — must be deleted (AC-H-040)"
  # This test doubles as AC-H-040 enforcement
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-034 — all $agent_count agents are dispatched by at least one skill; no orphan agents"
fi
exit "$FAIL"
