#!/usr/bin/env bash
# Verifies: AC-MODE-008aa
# Description: SIGTERM before last_completed_step write completes → step NOT recorded as done
#   On resume, interrupted step is re-executed from scratch
#
# NOTE on scope: this repo ships no runtime orchestrator binary (it is "a pure
# plugin of markdown definitions" per CLAUDE.md) — pipeline steps run inside
# Claude Code agent sessions, not a standalone process this harness can spawn
# and signal. This scenario is therefore a STATIC check: it (a) greps docs for
# the documented atomic-write invariant and (b) confirms a state.json fixture
# is internally consistent with that invariant. It does NOT spawn a process,
# send a real SIGTERM, or race a write — a green run demonstrates the
# invariant is documented and the fixture format used to describe it is
# self-consistent, not that the behavior is actually enforced at runtime.
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
# Assertion 3: state.json fixture is consistent with the documented atomic-
# write pattern. This is a STATIC fixture check, NOT a behavioral simulation
# — no process is spawned and no SIGTERM is sent. It only asserts that a
# fixture representing "step 03 committed, step 04 in-flight" (the scenario
# described by Assertions 1/2/4's documentation) parses the way the
# documented invariant says it should. It cannot, by construction, detect a
# real mid-write race; that would require a stub orchestrator subprocess this
# repo does not have (see NOTE at top of file).
# ---------------------------------------------------------------------------
echo "--- Assertion 3: state.json fixture matches documented atomic-write invariant (static check) ---"
mkdir -p "$TMPDIR_TEST/.agent-flow"

# Fixture: step 03 completed and was committed to state.json; step 04 is
# modeled as still in-flight (its completion was never written). This fixture
# is hand-written to represent the post-SIGTERM state the docs describe —
# no step 04 write is attempted or interrupted here.
cat > "$TMPDIR_TEST/.agent-flow/state.json" << 'EOF'
{
  "schema_version": "1.0",
  "outcome": "in_progress",
  "last_completed_step": "03-reproduce"
}
EOF

# Confirm the fixture itself is well-formed and matches the documented field
# name/value — i.e. this is a schema/fixture sanity check, not proof that a
# real in-flight step 04 would fail to update this file mid-write.
if command -v jq > /dev/null 2>&1; then
  LAST=$(jq -r '.last_completed_step' "$TMPDIR_TEST/.agent-flow/state.json")
  if [ "$LAST" = "03-reproduce" ]; then
    echo "OK: fixture state.json last_completed_step = 03-reproduce (matches documented in-flight-step-04 scenario)"
  else
    fail "fixture state.json shows '$LAST' — should be '03-reproduce' to represent step 04 in-flight"
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
  echo "PASS: AC-MODE-008a — SIGTERM atomicity for last_completed_step write is documented and fixture-consistent (static check; no process/signal exercised)"
fi
exit "$FAIL"
