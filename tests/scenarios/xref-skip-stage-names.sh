#!/usr/bin/env bash
# Test: Skippable stage names in CLAUDE.md match stage mapping in pipeline commands
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
[ -f "$CLAUDE_MD" ] || { echo "FAIL: CLAUDE.md not found"; exit 1; }

# Assertion 1: CLAUDE.md lists the skippable stage names on the expected line
SKIP_LINE=$(grep "Stage names for skip:" "$CLAUDE_MD" || true)
if [ -z "$SKIP_LINE" ]; then
  fail "CLAUDE.md missing 'Stage names for skip:' line"
else
  for stage in triage analyst-impact spec-analyst test-engineer test-engineer-e2e browser-agent-reproduce browser-agent-verify; do
    if contains "$SKIP_LINE" "$stage"; then
      echo "OK: skippable stage '$stage' listed in CLAUDE.md"
    else
      fail "skippable stage '$stage' not found in 'Stage names for skip:' line"
    fi
  done
fi

# Assertion 2: CLAUDE.md states which stages CANNOT be skipped
CANNOT_LINE=$(grep "CANNOT be skipped" "$CLAUDE_MD" || true)
if [ -z "$CANNOT_LINE" ]; then
  fail "CLAUDE.md missing 'CANNOT be skipped' line"
else
  for mandatory in fixer reviewer publisher; do
    if contains "$CANNOT_LINE" "$mandatory"; then
      echo "OK: mandatory stage '$mandatory' listed as CANNOT be skipped in CLAUDE.md"
    else
      fail "mandatory stage '$mandatory' not found in 'CANNOT be skipped' line"
    fi
  done
fi

# Assertion 3: Each pipeline command mentions NEVER + skip in the context of fixer, reviewer, publisher
for cmd in fix-bugs implement-feature; do
  CMD_FILE="$REPO_ROOT/skills/$cmd/SKILL.md"
  [ -f "$CMD_FILE" ] || { fail "skills/$cmd/SKILL.md not found"; continue; }

  NEVER_LINE=$(grep -i "NEVER.*skip" "$CMD_FILE" || true)
  if [ -z "$NEVER_LINE" ]; then
    fail "$cmd.md has no 'NEVER skip' restriction line"
  else
    for mandatory in fixer reviewer publisher; do
      if contains "$NEVER_LINE" "$mandatory"; then
        echo "OK: $cmd.md lists '$mandatory' as unskippable in NEVER-skip line"
      else
        fail "$cmd.md NEVER-skip line does not mention '$mandatory'"
      fi
    done
  fi
done

# Assertion 4: Each skippable stage appears in at least one pipeline command's stage mapping or skip logic
SKIPPABLE_STAGES="triage analyst-impact spec-analyst test-engineer test-engineer-e2e browser-agent-reproduce browser-agent-verify"
for stage in $SKIPPABLE_STAGES; do
  found=0
  for cmd in fix-bugs implement-feature; do
    CMD_FILE="$REPO_ROOT/skills/$cmd/SKILL.md"
    [ -f "$CMD_FILE" ] || continue
    if grep -qi "$stage" "$CMD_FILE"; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 1 ]; then
    echo "OK: skippable stage '$stage' referenced in at least one pipeline command"
  else
    fail "skippable stage '$stage' not referenced in any pipeline command"
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS: all skippable/unskippable stage names are consistent between CLAUDE.md and pipeline commands"
exit "$FAIL"
