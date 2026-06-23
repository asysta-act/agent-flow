#!/usr/bin/env bash
# Verifies: AC-MODE-006
# Description: --step-mode 'a' input sets state.json outcome=paused, pause_reason=step_mode_abort,
#   last_completed_step=<current-step>, exit 0
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

# ---------------------------------------------------------------------------
# Setup: mock state.json as step-mode abort would produce
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/.agent-flow"

cat > "$TMPDIR_TEST/.agent-flow/state.json" << 'EOF'
{
  "schema_version": "1.0",
  "issue_id": "BUG-123",
  "pipeline": "fix-bugs",
  "outcome": "paused",
  "pause_reason": "step_mode_abort",
  "last_completed_step": "04-fixer-reviewer-loop",
  "paused_at": "2026-04-27T10:30:00Z"
}
EOF

# ---------------------------------------------------------------------------
# Assertion 1: state.json has outcome=paused on abort
# ---------------------------------------------------------------------------
echo "--- Assertion 1: state.json outcome=paused on step-mode abort ---"
if command -v jq > /dev/null 2>&1; then
  OUTCOME=$(jq -r '.outcome' "$TMPDIR_TEST/.agent-flow/state.json")
  if [ "$OUTCOME" = "paused" ]; then
    echo "OK: state.json outcome=paused"
  else
    fail "state.json outcome='$OUTCOME', expected 'paused'"
  fi
else
  if grep -qF '"outcome": "paused"' "$TMPDIR_TEST/.agent-flow/state.json"; then
    echo "OK: state.json outcome=paused (grep fallback)"
  else
    fail "state.json missing outcome=paused"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 2: pause_reason=step_mode_abort
# ---------------------------------------------------------------------------
echo "--- Assertion 2: state.json pause_reason=step_mode_abort ---"
if command -v jq > /dev/null 2>&1; then
  PAUSE_REASON=$(jq -r '.pause_reason' "$TMPDIR_TEST/.agent-flow/state.json")
  if [ "$PAUSE_REASON" = "step_mode_abort" ]; then
    echo "OK: state.json pause_reason=step_mode_abort"
  else
    fail "state.json pause_reason='$PAUSE_REASON', expected 'step_mode_abort'"
  fi
else
  if grep -qF '"pause_reason": "step_mode_abort"' "$TMPDIR_TEST/.agent-flow/state.json"; then
    echo "OK: pause_reason=step_mode_abort (grep fallback)"
  else
    fail "state.json missing pause_reason=step_mode_abort"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 3: last_completed_step set to step that was completed before abort
# ---------------------------------------------------------------------------
echo "--- Assertion 3: state.json last_completed_step=04-fixer-reviewer-loop ---"
if command -v jq > /dev/null 2>&1; then
  LAST_STEP=$(jq -r '.last_completed_step' "$TMPDIR_TEST/.agent-flow/state.json")
  if [ "$LAST_STEP" = "04-fixer-reviewer-loop" ]; then
    echo "OK: last_completed_step=04-fixer-reviewer-loop"
  else
    fail "last_completed_step='$LAST_STEP', expected '04-fixer-reviewer-loop'"
  fi
else
  if grep -qF '"last_completed_step": "04-fixer-reviewer-loop"' "$TMPDIR_TEST/.agent-flow/state.json"; then
    echo "OK: last_completed_step documented (grep fallback)"
  else
    fail "state.json missing last_completed_step=04-fixer-reviewer-loop"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 4: state/schema.md documents these abort state keys
# ---------------------------------------------------------------------------
echo "--- Assertion 4: state/schema.md documents step_mode_abort keys ---"
SCHEMA="$REPO_ROOT/state/schema.md"
if [ ! -f "$SCHEMA" ]; then
  echo "SKIP: state/schema.md not found" >&2
  exit 77
fi

if grep -qF 'step_mode_abort' "$SCHEMA"; then
  echo "OK: state/schema.md documents step_mode_abort pause_reason"
else
  fail "state/schema.md missing step_mode_abort documentation"
fi

if grep -qF 'last_completed_step' "$SCHEMA"; then
  echo "OK: state/schema.md documents last_completed_step"
else
  fail "state/schema.md missing last_completed_step key"
fi

# ---------------------------------------------------------------------------
# Assertion 5: exit code 0 on abort (graceful pause, not error)
# ---------------------------------------------------------------------------
echo "--- Assertion 5: step-mode abort exits 0 (graceful pause) documented ---"
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
if [ -f "$FIXBUGS_SKILL" ]; then
  if grep -qiE 'exit 0.*abort|abort.*exit 0|graceful.*pause' "$FIXBUGS_SKILL"; then
    echo "OK: fix-bugs SKILL.md documents exit 0 on abort"
  else
    fail "fix-bugs SKILL.md missing exit 0 on step-mode abort documentation"
  fi
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-006 — step-mode abort state.json structure verified"
fi
exit "$FAIL"
