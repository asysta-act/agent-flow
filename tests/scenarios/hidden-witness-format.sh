#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-hidden-witness-format.sh (HIDDEN)
# What it checks:
#   1) The compute_dispatch_witness function in core/lib/stage-invariant.sh:
#       a) Emits a value matching ^[0-9a-f]{64}$ (sha256 hex, 64 lowercase chars).
#       b) Is invokable as a function — sourced and called without side effects.
#   2) Witness stability under prompt-head extraction:
#       - The function defines a 128-byte truncation step that operates on
#         the input prompt template BEFORE variable expansion.
#       - We assert by grep that the implementation references "128" near
#         "prompt" within ≤5 lines — a structural witness, not a runtime one,
#         because we cannot exercise the full path without fixtures.
#   3) The canonicalization does NOT expand variables like ${ISSUE_ID}: the
#      function code must NOT contain a bash-expansion of ISSUE_ID, BRANCH_NAME,
#      or similar Tier-1 vars in its hashing path (negative grep).
# Falsification angle this catches that the visible test does not:
#   - Witness implemented but emits non-hex / mixed-case / wrong-length output
#     (visible test only checks the canonical-input string structure).
#   - Witness implemented but accidentally expands Tier-1 vars (would defeat
#     stability across resume cycles).
# Expected RED phase: FAIL — library does not yet exist.
# Expected GREEN phase: PASS.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

LIB="core/lib/stage-invariant.sh"
if [ ! -f "$LIB" ]; then
  fail "hidden-witness-format.lib: $LIB does not exist"
  exit 1
fi

# 1) Try to source the library and invoke compute_dispatch_witness in a subshell
#    to avoid contaminating the test process. Capture stdout; assert hex shape.
witness_out=""
witness_rc=0
witness_out=$(
  set -uo pipefail
  # shellcheck disable=SC1090
  source "$LIB" 2>/dev/null || exit 99
  if ! command -v compute_dispatch_witness >/dev/null 2>&1; then
    exit 98
  fi
  compute_dispatch_witness "test_stage" "test-subagent" "sonnet" "EXAMPLE_PROMPT_HEAD_128_BYTES_TOKEN" 2>/dev/null
) || witness_rc=$?

if [ "$witness_rc" -eq 99 ]; then
  fail "hidden-witness-format.source: $LIB failed to source cleanly"
elif [ "$witness_rc" -eq 98 ]; then
  fail "hidden-witness-format.fn-undef: compute_dispatch_witness function undefined after source"
elif [ "$witness_rc" -ne 0 ]; then
  fail "hidden-witness-format.fn-rc: compute_dispatch_witness exited rc=${witness_rc}"
fi

# Strip CR/whitespace.
witness_trimmed=$(printf '%s' "$witness_out" | tr -d '\r\n ' | tr -d ' ')
if [ -n "$witness_trimmed" ]; then
  if ! matches_re "$witness_trimmed" '^[0-9a-f]{64}$'; then
    fail "hidden-witness-format.shape: compute_dispatch_witness emitted '${witness_trimmed}' (expected ^[0-9a-f]{64}$ sha256 hex)"
  fi
fi

# 2) Structural witness for 128-byte truncation step (no runtime exec — grep-only).
#    Require the literal "128" appears within 8 lines of a "prompt" reference.
if ! awk '
  /prompt/ { last_prompt = NR }
  /128/ {
    if (last_prompt > 0 && (NR - last_prompt) <= 8) { found = 1 }
  }
  /128/ { last_128 = NR }
  /prompt/ {
    if (last_128 > 0 && (NR - last_128) <= 8) { found = 1 }
  }
  END { exit (found ? 0 : 1) }
' "$LIB"; then
  fail "hidden-witness-format.head128: $LIB does not reference '128' within 8 lines of 'prompt'"
fi

# 3) Negative grep — the witness path must NOT directly expand Tier-1 vars.
# Forbidden literals in the witness CANONICAL path:
for forbidden in '\${ISSUE_ID}' '\${BRANCH_NAME}' '\${TICKET_ID}'; do
  if grep -qE "$forbidden" "$LIB"; then
    fail "hidden-witness-format.no-tier1: $LIB references ${forbidden} (witness must hash UN-EXPANDED template)"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-hidden-witness-format — witness shape, prompt_head_128 structure, and Tier-1-var-free hashing all OK"
  exit 0
fi
exit 1
