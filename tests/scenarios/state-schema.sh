#!/usr/bin/env bash
# Test: State management infrastructure exists with required structure
# Validates: state/schema.md, core/state-manager.md, state.json refs in commands
# PR 1: State management
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

# 1. state/ directory and schema.md exist with schema_version
if [ ! -d "$REPO_ROOT/state" ]; then
  fail "state/ directory does not exist"
fi

if [ ! -f "$REPO_ROOT/state/schema.md" ]; then
  fail "state/schema.md does not exist"
else
  if ! grep -q "schema_version" "$REPO_ROOT/state/schema.md"; then
    fail "state/schema.md does not contain 'schema_version' field"
  fi
fi

# 2. core/state-manager.md exists with required contract sections
STATE_MGR="$REPO_ROOT/core/state-manager.md"
if [ ! -f "$STATE_MGR" ]; then
  fail "core/state-manager.md does not exist"
else
  for section in "## Purpose" "## Input" "## Output" "## Failure"; do
    if ! grep -q "$section" "$STATE_MGR"; then
      fail "core/state-manager.md missing section: $section"
    fi
  done
  if ! grep -q "\.tmp" "$STATE_MGR"; then
    fail "core/state-manager.md missing .tmp atomic write pattern"
  fi
  if ! grep -qi "rename" "$STATE_MGR"; then
    fail "core/state-manager.md missing rename step in atomic write protocol"
  fi
fi

# 3. All 3 pipeline entry-point commands reference state.json
for cmd in fix-bugs implement-feature scaffold; do
  CMD_FILE="$REPO_ROOT/skills/${cmd}/SKILL.md"
  if [ -f "$CMD_FILE" ]; then
    count=$(grep -c 'state\.json\|state-manager' "$CMD_FILE" || true)
    if [ "$count" -lt 5 ]; then
      fail "$cmd.md has only $count state references (expected >= 5)"
    fi
  fi
done

# 4. core/resume-detection.md (shared resume contract; successor to the deleted
#    resume-ticket skill — see tests/scenarios/test-cross-skill-consistency.sh)
#    references state.json and documents the FRESH fallback resume point.
RESUME="$REPO_ROOT/core/resume-detection.md"
if [ ! -f "$RESUME" ]; then
  fail "core/resume-detection.md does not exist"
else
  if ! grep -q 'state\.json' "$RESUME"; then
    fail "core/resume-detection.md does not reference state.json"
  fi
  if ! grep -qi 'FRESH' "$RESUME"; then
    fail "core/resume-detection.md missing FRESH fallback resume point"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: State management infrastructure is valid"
exit "$FAIL"
