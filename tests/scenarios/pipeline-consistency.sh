#!/bin/bash
# Test: Pipeline consistency across all commands containing the fixer/reviewer/test loop
# Validates: block comment format, git add -A, retry context strings, safety checks, rollback context
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
SKILLS_DIR="$REPO_ROOT/skills"
# v10 thin-controller: SKILL.md is the controller, but step files in steps/*.md
# carry the dispatch detail. For each skill that has rollback/fixer/reviewer
# references anywhere in its skill tree, evaluate SKILL.md + steps/*.md as a unit.
PIPELINE_FILES=""
for skill_dir in "$SKILLS_DIR"/*/; do
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue
  if grep -rqE 'rollback-agent|fixer.*Task tool|fixer.*subagent_type' "$skill_dir" 2>/dev/null; then
    PIPELINE_FILES="$PIPELINE_FILES $skill_md"
  fi
done
PIPELINE_FILES=$(echo "$PIPELINE_FILES" | tr -s ' ')

# Helper: aggregate SKILL.md + steps/*.md into one logical view per skill
aggregate_skill() {
  local skill_md="$1"
  local skill_dir
  skill_dir="$(dirname "$skill_md")"
  cat "$skill_md"
  if [ -d "$skill_dir/steps" ]; then
    cat "$skill_dir/steps/"*.md 2>/dev/null
  fi
  # Include data/ files (guard blocks etc.)
  if [ -d "$skill_dir/data" ]; then
    cat "$skill_dir/data/"*.md 2>/dev/null
  fi
}

FAIL=0
fail() {
  echo "FAIL: $1"
  FAIL=1
}

# 1. Block comment format uses emoji consistently
# Use byte-level grep (LC_ALL=C) for the U+1F534 emoji to avoid Windows UTF-8
# round-trip corruption through bash command substitution.
EMOJI_BYTES=$'\xf0\x9f\x94\xb4'
for f in $PIPELINE_FILES; do
  name=$(basename "$f")
  body=$(aggregate_skill "$f")
  if grep -q '\[agent-flow\].*Pipeline Block' <<< "$body"; then
    # Every occurrence must have the emoji (compare at byte level)
    bad=$(printf '%s' "$body" | LC_ALL=C grep '\[agent-flow\].*Pipeline Block' | LC_ALL=C grep -v "$EMOJI_BYTES" || true)
    if [ -n "$bad" ]; then
      fail "$name has block comment without emoji: $bad"
    fi
  fi
done

# 2. Decomposition/subtask commits use git add -A (not git add .)
for f in $PIPELINE_FILES; do
  name=$(basename "$f")
  body=$(aggregate_skill "$f")
  # Look for "git add ." that is NOT "git add -A" (exclude git add . in init contexts)
  if echo "$body" | grep 'git add \.' | grep -v 'git add -A' | grep -v 'git add \.\.' > /dev/null 2>&1; then
    bad_lines=$(echo "$body" | grep 'git add \.' | grep -v 'git add -A' | grep -v 'git add \.\.')
    while IFS= read -r line; do
      # In aggregate mode, allow git init contexts
      if echo "$body" | grep -A 5 'git init' | grep -qF "$line"; then
        continue
      fi
      fail "$name (aggregate) uses 'git add .' instead of 'git add -A': $line"
    done <<< "$bad_lines"
  fi
done

# 3. Retry limits are mentioned for fixer/reviewer/test-engineer
# Each command must reference build retries, fixer iterations, and test attempts (case-insensitive)
for f in $PIPELINE_FILES; do
  name=$(basename "$f")
  body=$(aggregate_skill "$f")
  if grep -qiE 'fixer.*Task tool|Run.*fixer|fixer.*subagent_type' <<< "$body"; then
    if ! grep -qi 'build retries\|Build retries\|retry.*build\|build_retries' <<< "$body"; then
      fail "$name calls fixer but does not mention build retries"
    fi
  fi
  if grep -qiE 'reviewer.*Task tool|Run.*reviewer|reviewer.*subagent_type' <<< "$body"; then
    if ! grep -qi 'fixer iterations\|fixer_iterations\|Fixer iterations' <<< "$body"; then
      fail "$name calls reviewer but does not mention fixer iterations"
    fi
  fi
  if grep -qiE 'test-engineer.*Task tool|Run.*test-engineer|test-engineer.*subagent_type' <<< "$body"; then
    if ! grep -qi 'test attempts\|test_attempts\|Test attempts' <<< "$body"; then
      fail "$name calls test-engineer but does not mention test attempts"
    fi
  fi
done

# 4. Safety checks for temp directory cleanup include explicit failure action
for f in $PIPELINE_FILES; do
  name=$(basename "$f")
  body=$(aggregate_skill "$f")
  if grep -q 'rm -rf.*SCAFFOLD_TEMP' <<< "$body"; then
    if ! contains "$body" "DO NOT run rm -rf"; then
      fail "$name has rm -rf \$SCAFFOLD_TEMP but no explicit 'DO NOT run rm -rf' safety check"
    fi
  fi
done

# 5. Rollback-agent context includes issue tracker instruction
for f in $PIPELINE_FILES; do
  name=$(basename "$f")
  body=$(aggregate_skill "$f")
  if contains "$body" "rollback-agent"; then
    if ! contains "$body" "issue tracker"; then
      fail "$name references rollback-agent but has no issue tracker context instruction"
    fi
  fi
done

if [ "$FAIL" -eq 1 ]; then
  exit 1
fi

pipeline_count=$(echo $PIPELINE_FILES | wc -w)
echo "PASS: Pipeline consistency — all patterns verified across $pipeline_count pipeline commands"
