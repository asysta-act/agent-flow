#!/usr/bin/env bash
# Verifies: AC-DOC-006
# Description: docs/reference/skills.md contains exactly 17 canonical skill names
#   as table rows
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if matches_re "$REPO_ROOT" '\.forge'; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SKILLS_DOC="$REPO_ROOT/docs/reference/skills.md"
if [ ! -f "$SKILLS_DOC" ]; then
  fail "docs/reference/skills.md not found"
  exit 1
fi

# Canonical 17 skill names (estimate, migrate-config, pipeline-status, scaffold-validate, version-bump removed)
CANONICAL_SKILLS=(
  analyze-bug autopilot changelog check-setup create-backlog
  discuss fix-bugs implement-feature metrics
  onboard prioritize publish scaffold
  setup-agents setup-mcp sprint-plan
  version-check
)

printf '%s\n' "${CANONICAL_SKILLS[@]}" | sort > "$TMPDIR_TEST/expected.txt"

# Extract skill names from table rows
SKILL_PATTERN=$(IFS='|'; echo "${CANONICAL_SKILLS[*]}")
grep -oE "^\|[[:space:]]*($SKILL_PATTERN)[[:space:]]*\|" "$SKILLS_DOC" | \
  sed 's/|//g' | tr -d '[:space:]' | sort > "$TMPDIR_TEST/actual.txt"

# ---------------------------------------------------------------------------
# Assertion 1: all 17 skills present
# ---------------------------------------------------------------------------
echo "--- Assertion 1: all 17 canonical skills in skills.md ---"
for skill in "${CANONICAL_SKILLS[@]}"; do
  if grep -qF "$skill" "$SKILLS_DOC"; then
    echo "OK: '$skill' found in skills.md"
  else
    fail "skills.md missing '$skill'"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 2: setup-agents specifically present (new v8 skill)
# ---------------------------------------------------------------------------
echo "--- Assertion 2: setup-agents listed in skills.md ---"
if grep -qF 'setup-agents' "$SKILLS_DOC"; then
  echo "OK: setup-agents in skills.md"
else
  fail "skills.md missing setup-agents"
fi

# ---------------------------------------------------------------------------
# Assertion 3: no create-pr (removed)
# ---------------------------------------------------------------------------
echo "--- Assertion 3: create-pr NOT in skills.md (removed) ---"
if grep -qF 'create-pr' "$SKILLS_DOC"; then
  fail "skills.md still contains create-pr (should be removed)"
else
  echo "OK: create-pr absent from skills.md"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-006 — docs/reference/skills.md has exactly 17 canonical skills"
fi
exit "$FAIL"
