#!/bin/bash
# PURPOSE: Assert no skill uses the legacy prose dispatch idiom "Run `agent-flow:X` (Task tool, ...)"
#          or "Dispatch `agent-flow:X` (Task tool, ...)". All dispatches must use the strict form
#          Task(subagent_type='agent-flow:{name}', model='{tier}').
# AC-H-N covered: AC-H-050
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (all dispatches harmonized to strict idiom)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SKILLS_DIR="$REPO_ROOT/skills"
if [ ! -d "$SKILLS_DIR" ]; then
  fail "skills/ directory not found at $SKILLS_DIR"
  exit 1
fi

# Pattern 1: Run `agent-flow:X` (Task tool, ...)
# Pattern 2: Dispatch `agent-flow:X` (Task tool, ...)
# Pattern 3: Run agent-flow:X (Task tool, ...)  (without backticks)
# All are legacy prose idioms per design.md §5

prose_matches=$(grep -rnE "(Run|Dispatch)\s+\`?agent-flow:[a-z-]+\`?\s*\(Task tool" "$SKILLS_DIR" --include="*.md" 2>/dev/null || true)

if [ -n "$prose_matches" ]; then
  echo "FAIL: Found legacy prose dispatch idiom(s) in skills:" >&2
  echo "$prose_matches" >&2
  fail "Skills still contain prose dispatch idiom 'Run/Dispatch agent-flow:X (Task tool, ...)' — must be harmonized to Task(subagent_type=...)"
  # Mutation catch: reverting one dispatch to prose idiom fails here
fi

# Also check for the variant "Run the {name} agent (Task tool, model: X)" pattern
# (seen in scaffold-add/SKILL.md: "Run the scaffolder agent (Task tool, model: sonnet)")
prose_agent_matches=$(grep -rnE "Run the [a-z-]+ agent \(Task tool" "$SKILLS_DIR" --include="*.md" 2>/dev/null || true)
if [ -n "$prose_agent_matches" ]; then
  echo "FAIL: Found 'Run the X agent (Task tool, ...)' prose idiom in skills:" >&2
  echo "$prose_agent_matches" >&2
  fail "Skills still contain 'Run the {name} agent (Task tool, ...)' prose idiom — must be harmonized"
fi

# Also check create-backlog style: "Run the architect agent (Task tool, model: opus)"
# (already caught by the pattern above, but add a named check for traceability)
architect_prose=$(grep -rnE "Run the architect agent \(Task tool" "$SKILLS_DIR" --include="*.md" 2>/dev/null || true)
if [ -n "$architect_prose" ]; then
  fail "skills/create-backlog/ still has 'Run the architect agent (Task tool, ...)' prose idiom"
fi

# Positive assertion: verify strict idiom appears in at least some skill files
# (sanity check that we haven't accidentally removed ALL dispatch lines)
strict_count=$(grep -rnE "Task\(subagent_type='agent-flow:[a-z-]+'" "$SKILLS_DIR" --include="*.md" 2>/dev/null | wc -l || true)
if [ "$strict_count" -lt 10 ]; then
  fail "Very few strict idiom dispatches found ($strict_count) — expected at least 10 across all skills (sanity check)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-050 — no legacy prose dispatch idiom found in skills/; $strict_count strict Task(subagent_type=...) dispatches verified"
fi
exit "$FAIL"
