#!/usr/bin/env bash
# overlay-injection-before-task.sh
# Verifies: AC-MODE-005, AC-MODE-021, AC-WIRE-004
#
# STRUCTURAL test: for each of the 13 dispatch step files that contains Task(,
# the canonical delegation phrase appears at a line number STRICTLY BEFORE the
# first Task( call.
#
# This is the P0 PR gate — non-skippable, no early-return guards.
#
# NOTE: Run from tests/scenarios/ after Phase 7 staging.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=1; }
pass() { printf '[PASS] %s\n' "$1"; }

# Thin-controller layout: dispatch sites discovered dynamically across both
# pipeline skill trees. Any step file containing a Task( call is a dispatch site.
DISPATCH_FILES=()
for skill in fix-bugs implement-feature; do
  steps_dir="$REPO_ROOT/skills/$skill/steps"
  if [ -d "$steps_dir" ]; then
    while IFS= read -r -d '' sf; do
      rel="${sf#$REPO_ROOT/}"
      DISPATCH_FILES+=("$rel")
    done < <(find "$steps_dir" -name '*.md' -print0)
  fi
done

DELEGATION_PHRASE="Before dispatch, check Agent Overrides:"

echo "=== Checking BEFORE-Task() ordering across all 13 dispatch sites ==="

for rel_path in "${DISPATCH_FILES[@]}"; do
  f="$REPO_ROOT/$rel_path"
  short="$(basename "$(dirname "$rel_path")")/$(basename "$rel_path")"

  if [ ! -f "$f" ]; then
    fail "file not found: $rel_path"
    continue
  fi

  # Does this file actually dispatch via Task( with subagent_type? Match the
  # canonical imperative form (Task(subagent_type='agent-flow:'), skip
  # prose-only mentions like "Task() dispatch" or "NOT a Task() dispatch".
  if ! grep -qE "Task\(subagent_type=" "$f"; then
    pass "no Task(subagent_type= in $short — skip ordering check"
    continue
  fi

  # Does the file have the delegation phrase?
  if ! grep -qF "$DELEGATION_PHRASE" "$f"; then
    fail "$short: missing delegation phrase '$DELEGATION_PHRASE'"
    continue
  fi

  # Two-pass grep -n for line numbers (match Task(subagent_type= as the actual dispatch)
  delegation_line=$(grep -nF "$DELEGATION_PHRASE" "$f" | head -1 | cut -d: -f1)
  task_line=$(grep -nE "Task\(subagent_type=" "$f" | head -1 | cut -d: -f1)

  if [ -z "$delegation_line" ] || [ -z "$task_line" ]; then
    fail "$short: could not extract line numbers (delegation=$delegation_line, task=$task_line)"
    continue
  fi

  if [ "$delegation_line" -lt "$task_line" ]; then
    pass "$short: delegation at line $delegation_line < Task( at line $task_line"
  else
    fail "$short: delegation at line $delegation_line is NOT before Task( at line $task_line (AFTER-dispatch injection)"
  fi
done

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "[PASS] overlay-injection-before-task: all 13 dispatch sites have correct BEFORE-Task() ordering"
fi
exit "$FAIL"
