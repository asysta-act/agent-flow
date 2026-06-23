#!/usr/bin/env bash
# Verifies: AC-DOC-005
# Description: docs/reference/agents.md contains exactly the 17 canonical agent names
#   as table rows — no more, no less
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

AGENTS_DOC="$REPO_ROOT/docs/reference/agents.md"
if [ ! -f "$AGENTS_DOC" ]; then
  fail "docs/reference/agents.md not found"
  exit 1
fi

# Canonical 17 names
CANONICAL=(analyst fixer reviewer acceptance-gate test-engineer publisher rollback-agent
  spec-analyst architect scaffolder priority-engine spec-writer spec-reviewer
  browser-agent deployment-verifier backlog-creator sprint-planner)

printf '%s\n' "${CANONICAL[@]}" | sort > "$TMPDIR_TEST/expected.txt"

# Extract agent names from markdown table rows (| name | ...)
grep -oE "^\|[[:space:]]*(analyst|fixer|reviewer|acceptance-gate|test-engineer|publisher|rollback-agent|spec-analyst|architect|scaffolder|priority-engine|spec-writer|spec-reviewer|browser-agent|deployment-verifier|backlog-creator|sprint-planner)[[:space:]]*\|" "$AGENTS_DOC" | \
  sed 's/|//g' | tr -d ' \t' | sort > "$TMPDIR_TEST/actual.txt"

# ---------------------------------------------------------------------------
# Assertion 1: all expected agents found
# ---------------------------------------------------------------------------
echo "--- Assertion 1: all 17 canonical agents in agents.md table ---"
for agent in "${CANONICAL[@]}"; do
  if grep -qF "$agent" "$TMPDIR_TEST/actual.txt"; then
    echo "OK: '$agent' found in agents.md table"
  else
    fail "agents.md missing '$agent' from table"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 2: no extra agents beyond 17
# ---------------------------------------------------------------------------
echo "--- Assertion 2: no extra agents beyond canonical 17 ---"
if diff -q "$TMPDIR_TEST/expected.txt" "$TMPDIR_TEST/actual.txt" > /dev/null 2>&1; then
  echo "OK: agents.md table matches exactly canonical 17 agents"
else
  echo "Diff (expected vs actual):"
  diff "$TMPDIR_TEST/expected.txt" "$TMPDIR_TEST/actual.txt" || true
  fail "agents.md table enumeration does not match canonical 17"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-005 — docs/reference/agents.md has exactly 17 canonical agent rows"
fi
exit "$FAIL"
