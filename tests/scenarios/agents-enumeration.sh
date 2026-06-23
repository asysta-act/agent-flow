#!/usr/bin/env bash
# Verifies: AC-AGT-001, AC-CT-001
# Description: agents/ contains exactly 17 .md files with canonical names
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# Canonical 17-agent list per AC-AGT-001
EXPECTED_AGENTS=(
  "acceptance-gate.md"
  "analyst.md"
  "architect.md"
  "backlog-creator.md"
  "browser-agent.md"
  "deployment-verifier.md"
  "fixer.md"
  "priority-engine.md"
  "publisher.md"
  "reviewer.md"
  "rollback-agent.md"
  "scaffolder.md"
  "spec-analyst.md"
  "spec-reviewer.md"
  "spec-writer.md"
  "sprint-planner.md"
  "test-engineer.md"
)

AGENTS_DIR="$REPO_ROOT/agents"

if [ ! -d "$AGENTS_DIR" ]; then
  fail "agents/ directory not found"
  exit 1
fi

# ---------------------------------------------------------------------------
# Assertion 1: Count exactly 17 agents
# ---------------------------------------------------------------------------
echo "--- Assertion 1: agents/ has exactly 17 .md files ---"
ACTUAL_COUNT=$(find "$AGENTS_DIR" -maxdepth 1 -name '*.md' -type f | wc -l)
if [ "$ACTUAL_COUNT" -eq 17 ]; then
  echo "OK: agents/ has exactly 17 .md files"
else
  fail "agents/ has $ACTUAL_COUNT .md files — expected 17"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Enumeration check — expected names present
# ---------------------------------------------------------------------------
echo "--- Assertion 2: all 17 expected agent names present ---"
for agent in "${EXPECTED_AGENTS[@]}"; do
  if [ -f "$AGENTS_DIR/$agent" ]; then
    echo "OK: agents/$agent exists"
  else
    fail "agents/$agent missing (required by AC-AGT-001 canonical list)"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 3: No extra agent files beyond the 17
# ---------------------------------------------------------------------------
echo "--- Assertion 3: no extra agent files beyond canonical 17 ---"
printf '%s\n' "${EXPECTED_AGENTS[@]}" | sort > "$TMPDIR_TEST/expected.txt"
find "$AGENTS_DIR" -maxdepth 1 -name '*.md' -type f -exec basename {} \; | sort > "$TMPDIR_TEST/actual.txt"

if diff -q "$TMPDIR_TEST/expected.txt" "$TMPDIR_TEST/actual.txt" > /dev/null 2>&1; then
  echo "OK: agents/ contains exactly the canonical 17 files"
else
  echo "Diff (expected vs actual):"
  diff "$TMPDIR_TEST/expected.txt" "$TMPDIR_TEST/actual.txt" || true
  fail "agents/ enumeration does not match canonical 17-agent list"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-AGT-001 + AC-CT-001 — agents/ has exactly 17 canonical files"
fi
exit "$FAIL"
