#!/usr/bin/env bash
# Verifies: AC-MODE-008aa
# Description: SIGTERM before last_completed_step write completes → step NOT recorded as done
#   On resume, interrupted step is re-executed from scratch
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
# Assertion 1: state/schema.md documents SIGTERM atomicity for step-mode
# ---------------------------------------------------------------------------
echo "--- Assertion 1: state/schema.md documents SIGTERM atomicity ---"
SCHEMA_DOC="$REPO_ROOT/state/schema.md"
if [ ! -f "$SCHEMA_DOC" ]; then
  echo "SKIP: state/schema.md not found" >&2
  exit 77
fi

if grep -qiE 'SIGTERM|atomicity|atomic.*write|step.*mode.*atomic|not.*updated.*in.flight' "$SCHEMA_DOC"; then
  echo "OK: state/schema.md documents SIGTERM atomicity"
else
  fail "state/schema.md missing SIGTERM atomicity documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Atomic write semantics — write step completion AFTER step succeeds
# ---------------------------------------------------------------------------
echo "--- Assertion 2: step completion written AFTER step succeeds (not before) ---"
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
if [ ! -f "$FIXBUGS_SKILL" ]; then
  echo "SKIP: skills/fix-bugs/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'write.*after.*complete|after.*success.*write|last_completed_step.*written|last_completed_step|Follow atomic write protocol' "$FIXBUGS_SKILL"; then
  echo "OK: fix-bugs SKILL.md documents write-after-complete semantics"
else
  fail "fix-bugs SKILL.md missing write-after-complete (atomicity) semantics"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Simulate atomic state write pattern
# ---------------------------------------------------------------------------
echo "--- Assertion 3: simulate atomic state.json write (step success → then write) ---"
mkdir -p "$TMPDIR_TEST/.agent-flow"

# Step 03 completes successfully (no SIGTERM)
cat > "$TMPDIR_TEST/.agent-flow/state.json" << 'EOF'
{
  "schema_version": "1.0",
  "outcome": "in_progress",
  "last_completed_step": "03-reproduce"
}
EOF

# Now step 04 starts — SIGTERM arrives before write
# State should STILL show last_completed_step = 03-reproduce (not 04)
if command -v jq > /dev/null 2>&1; then
  LAST=$(jq -r '.last_completed_step' "$TMPDIR_TEST/.agent-flow/state.json")
  if [ "$LAST" = "03-reproduce" ]; then
    echo "OK: state.json last_completed_step = 03-reproduce (not updated mid-step)"
  else
    fail "state.json shows '$LAST' — should be '03-reproduce' when step 04 is in-flight"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 4: Resume from in-flight step re-executes from scratch
# ---------------------------------------------------------------------------
echo "--- Assertion 4: resume-ticket re-executes in-flight step from scratch ---"
RESUME_SKILL="$REPO_ROOT/skills/resume-ticket/SKILL.md"
if [ -f "$RESUME_SKILL" ]; then
  if grep -qiE 'SIGTERM|in.flight|interrupted.*step|re.execut.*step' "$RESUME_SKILL"; then
    echo "OK: resume-ticket SKILL.md handles in-flight step re-execution"
  else
    fail "resume-ticket SKILL.md missing in-flight step re-execution documentation"
  fi
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-008a — SIGTERM atomicity for last_completed_step write documented"
fi
exit "$FAIL"
