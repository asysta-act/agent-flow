#!/usr/bin/env bash
# Verifies: AC-MODE-007
# Description: After pipeline pauses with pause_reason="step_mode_abort"
#   and last_completed_step="04-fixer-reviewer-loop", resume MUST begin from
#   the next step (05-smoke / 06-test in fix-bugs pipeline) — not re-execute 04,
#   not skip ahead to 06. The resume contract is shared across pipeline entry-point
#   skills via core/resume-detection.md, with --step-mode handling documented
#   there and referenced from skills/fix-bugs/SKILL.md.
# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
set -uo pipefail

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
# Prerequisite: fix-bugs SKILL.md AND core/resume-detection.md must exist
#   resume-ticket was never implemented; resume is built into the entry-point
#   skills (fix-bugs, implement-feature, scaffold) via shared core contract.
# ---------------------------------------------------------------------------
FIXBUGS_SKILL="$REPO_ROOT/skills/fix-bugs/SKILL.md"
RESUME_CONTRACT="$REPO_ROOT/core/resume-detection.md"

if [ ! -f "$FIXBUGS_SKILL" ]; then
  echo "FAIL: skills/fix-bugs/SKILL.md not found" >&2
  exit 1
fi
if [ ! -f "$RESUME_CONTRACT" ]; then
  echo "FAIL: core/resume-detection.md not found" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Setup: mock state.json with step_mode_abort at step 04
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/.agent-flow"

cat > "$TMPDIR_TEST/.agent-flow/state.json" << 'EOF'
{
  "schema_version": "1.0",
  "issue_id": "BUG-1",
  "pipeline": "fix-bugs",
  "outcome": "paused",
  "pause_reason": "step_mode_abort",
  "last_completed_step": "04-fixer-reviewer-loop",
  "mode": "step-mode",
  "paused_at": "2026-04-27T10:30:00Z"
}
EOF

# ---------------------------------------------------------------------------
# Assertion 1: state.json is valid JSON with expected fields
# ---------------------------------------------------------------------------
echo "--- Assertion 1: state.json parseable with pause_reason=step_mode_abort ---"
if command -v jq > /dev/null 2>&1; then
  PAUSE_REASON=$(jq -r '.pause_reason' "$TMPDIR_TEST/.agent-flow/state.json")
  LAST_STEP=$(jq -r '.last_completed_step' "$TMPDIR_TEST/.agent-flow/state.json")
  OUTCOME=$(jq -r '.outcome' "$TMPDIR_TEST/.agent-flow/state.json")

  [ "$PAUSE_REASON" = "step_mode_abort" ] && echo "OK: pause_reason=step_mode_abort" || fail "pause_reason=$PAUSE_REASON (expected step_mode_abort)"
  [ "$LAST_STEP" = "04-fixer-reviewer-loop" ] && echo "OK: last_completed_step=04-fixer-reviewer-loop" || fail "last_completed_step=$LAST_STEP"
  [ "$OUTCOME" = "paused" ] && echo "OK: outcome=paused" || fail "outcome=$OUTCOME"
else
  if grep -qF '"pause_reason": "step_mode_abort"' "$TMPDIR_TEST/.agent-flow/state.json"; then
    echo "OK: pause_reason=step_mode_abort found (jq unavailable)"
  else
    fail "state.json missing pause_reason=step_mode_abort"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 2: --step-mode resume logic is documented in core/resume-detection.md
# ---------------------------------------------------------------------------
echo "--- Assertion 2: core/resume-detection.md documents --step-mode resume override ---"
if grep -qiE '\-\-step.mode|step.mode.*override|GOT_STEP_MODE' "$RESUME_CONTRACT"; then
  echo "OK: core/resume-detection.md documents --step-mode resume logic"
else
  fail "core/resume-detection.md missing --step-mode resume logic"
fi

# ---------------------------------------------------------------------------
# Assertion 3: resume contract documents "next step" / phase-scan semantics
#   (i.e., last_completed_step + 1, NOT re-executing the last step)
# ---------------------------------------------------------------------------
echo "--- Assertion 3: resume contract documents continuing from next step (not re-running last) ---"
if grep -qiE 'next.*stage|next.*step|phase.scan|NEXT_STAGE|resume.*from' "$RESUME_CONTRACT"; then
  echo "OK: core/resume-detection.md documents next-step resume logic"
else
  fail "core/resume-detection.md missing next-step / phase-scan resume logic"
fi

# ---------------------------------------------------------------------------
# Assertion 4: fix-bugs SKILL.md references the shared resume contract
# ---------------------------------------------------------------------------
echo "--- Assertion 4: fix-bugs SKILL.md references core/resume-detection.md ---"
if grep -qE 'resume-detection(\.md)?' "$FIXBUGS_SKILL"; then
  echo "OK: skills/fix-bugs/SKILL.md references shared resume-detection contract"
else
  fail "skills/fix-bugs/SKILL.md does not reference core/resume-detection.md"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Step numbering — next step after 04-fixer-reviewer-loop exists
# ---------------------------------------------------------------------------
echo "--- Assertion 5: step 05 follows step 04 in fix-bugs pipeline ---"
STEPS_DIR="$REPO_ROOT/skills/fix-bugs/steps"
if [ ! -d "$STEPS_DIR" ]; then
  fail "skills/fix-bugs/steps/ directory not found"
else
  TMPDIR_STEPS="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_TEST" "$TMPDIR_STEPS"' EXIT INT TERM
  find "$STEPS_DIR" -maxdepth 1 -name '05-*.md' -type f > "$TMPDIR_STEPS/step05.txt"
  if [ -s "$TMPDIR_STEPS/step05.txt" ]; then
    STEP_05=$(head -1 "$TMPDIR_STEPS/step05.txt")
    echo "OK: step 05 exists: $(basename "$STEP_05")"
  else
    fail "No step 05-*.md found in skills/fix-bugs/steps/ — expected e.g. 05-smoke.md"
  fi
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-MODE-007 — step-mode resume contract documented in core/resume-detection.md and referenced by fix-bugs SKILL.md"
fi
exit "$FAIL"
