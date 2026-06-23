#!/usr/bin/env bash
# Test: CLAUDE.md claims 17 agents, CLAUDE.md claims 17 skills,
#       and model table includes backlog-creator and sprint-planner
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

# 1. CLAUDE.md must exist
if [ ! -f "$CLAUDE_MD" ]; then
  fail "CLAUDE.md not found"
  exit 1
fi

# -----------------------------------------------------------------------
# 2. CLAUDE.md claims 17 agents
# -----------------------------------------------------------------------
agents_claimed=$(grep '`agents/`' "$CLAUDE_MD" | grep -oE '[0-9]+' | head -1)
if [ -z "$agents_claimed" ]; then
  fail "Could not find agent count claim in CLAUDE.md (expected '17 agent definitions')"
elif [ "$agents_claimed" -ne 17 ]; then
  fail "CLAUDE.md claims $agents_claimed agents but expected 17"
fi

# -----------------------------------------------------------------------
# 3. skills/ directory has 17 SKILL.md files (estimate, migrate-config, pipeline-status, scaffold-validate, version-bump removed)
# -----------------------------------------------------------------------
skills_fs=$(find "$REPO_ROOT/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
skills_claimed=$(grep '`skills/`' "$CLAUDE_MD" | grep -oE '[0-9]+' | head -1)

if [ "$skills_fs" -ne 17 ]; then
  fail "skills/ has $skills_fs SKILL.md files but expected 17"
fi

if [ -n "$skills_claimed" ] && [ "$skills_claimed" -ne 17 ]; then
  fail "CLAUDE.md claims $skills_claimed skills but expected 17"
fi

# -----------------------------------------------------------------------
# 4. Model Selection table includes backlog-creator
# -----------------------------------------------------------------------
if ! grep -q "backlog-creator" "$CLAUDE_MD"; then
  fail "CLAUDE.md Model Selection table missing backlog-creator"
fi

# 5. Model Selection table includes sprint-planner
if ! grep -q "sprint-planner" "$CLAUDE_MD"; then
  fail "CLAUDE.md Model Selection table missing sprint-planner"
fi

# 6. Both new agents are listed under sonnet model row
sonnet_row=$(awk '/^### Model Selection/{found=1} found && /sonnet/{print; exit}' "$CLAUDE_MD")
if ! contains_i "$sonnet_row" "backlog-creator"; then
  fail "CLAUDE.md Model Selection table: backlog-creator should be in sonnet row"
fi
if ! contains_i "$sonnet_row" "sprint-planner"; then
  fail "CLAUDE.md Model Selection table: sprint-planner should be in sonnet row"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: CLAUDE.md claims 17 agents, skills/ has 17 SKILL.md files, model table includes backlog-creator and sprint-planner under sonnet"
exit "$FAIL"
