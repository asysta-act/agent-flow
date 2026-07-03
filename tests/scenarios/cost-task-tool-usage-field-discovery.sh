#!/usr/bin/env bash
set -euo pipefail

# AC-38: Task-tool usage-field discovery test (COST-R12)
# Traces: COST-R2, COST-R12
# Description: Runs a structural assertion that verifies what token-count field name
#              the Task tool reports. Per spec, Phase 5 must create this file and assert
#              the field matches the known allowlist: {total_tokens, input_tokens+output_tokens,
#              tokens_estimated}.
#
# IMPORTANT: This test performs a STRUCTURAL check only (no live Claude CLI call, ever).
# It discovers the field by parsing the `tokens_used = result.usage.<field>` assignment
# that Phase 7's state-manager.md implementation declares, then validates that field
# against the known allowlist. This shell-based harness has no runtime capable of
# invoking the Task tool, so CLAUDE_LIVE_TEST=1 is honored only as a request to SKIP
# (exit 77) rather than fabricate a result — genuine live-field verification, if ever
# needed, belongs in a scheduled job outside the main harness.
#
# The structured summary line DISCOVERED_FIELD={name} is the mechanical signal for Phase 7.

cd "$(dirname "$0")/../.."
. "$(pwd)/tests/lib/assert.sh"

# Discovery context: The Claude Task tool returns a result object with a `result.usage` field
# that contains token counts. The field name within result.usage may vary by Claude API version:
# - result.usage.total_tokens (most common)
# - result.usage.input_tokens + result.usage.output_tokens (computed sum)
# - result.usage.tokens_estimated (fallback when exact count unavailable)
# This test asserts which field name from result.usage the implementation reads.
# DISCOVERED_FIELD= emits the chosen field name as a structured summary line.

# Known token-count field allowlist
ALLOWLIST=(total_tokens "input_tokens+output_tokens" tokens_estimated)

# --- Structural stub path (CI / no Claude CLI) ---
# Read the discovered field from state-manager.md or metrics/SKILL.md
# (Phase 7 implementation documents the chosen field name)

STUB_FIELD=""
STATE_MGR="core/state-manager.md"
if [ -f "$STATE_MGR" ]; then
  # Extract the field actually DECLARED on the `tokens_used = result.usage.<field>`
  # assignment line (the implementation's real choice) instead of testing whether any
  # allowlist candidate string is present anywhere in the file. A presence-anywhere
  # match is tautological here: state-manager.md spells out the full allowlist in prose
  # right next to the assignment, so every candidate substring is always present
  # regardless of which field was actually chosen — this used to make the check
  # unconditionally pass and "discover" nothing.
  ASSIGNED_LINE="$(grep -E 'tokens_used[[:space:]]*=[[:space:]]*result\.usage\.[A-Za-z_]+' "$STATE_MGR" | head -1)"
  STUB_FIELD="$(printf '%s\n' "$ASSIGNED_LINE" | grep -oE 'result\.usage\.[A-Za-z_]+' | head -1 | sed 's/^result\.usage\.//')"
fi

# If Phase 7 hasn't documented a concrete tokens_used assignment yet, use sentinel
if [ -z "$STUB_FIELD" ]; then
  if [ "${CLAUDE_LIVE_TEST:-0}" = "1" ]; then
    # Live Task-tool dispatch is NOT implemented by this shell-based harness — there is
    # no runtime here capable of invoking the Task tool and reading a real response, so
    # CLAUDE_LIVE_TEST=1 can never do more than the structural stub above. Skip instead
    # of fabricating a FAIL: real live-field verification belongs in a scheduled job
    # outside the main harness (see COST-R12 discussion), not a permanently-failing
    # branch in this script.
    echo "DISCOVERED_FIELD=<UNKNOWN>" >&2
    echo "[SKIP] CLAUDE_LIVE_TEST=1 requested but live Task dispatch is not implemented in this harness" >&2
    exit 77
  else
    # Pre-Phase 7: emit ABSENT signal (correct TDD red-phase behavior)
    echo "DISCOVERED_FIELD=<ABSENT>"
    echo "FAIL: state-manager.md not found or does not document a tokens_used = result.usage.<field> assignment — Phase 7 implementation required" >&2
    exit 1
  fi
fi

# Validate field is in allowlist
MATCHED=0
for allowed in "${ALLOWLIST[@]}"; do
  if [ "$STUB_FIELD" = "$allowed" ] || contains "$STUB_FIELD" "$allowed"; then
    MATCHED=1
    break
  fi
done

if [ "$MATCHED" -eq 0 ]; then
  echo "DISCOVERED_FIELD=<UNKNOWN:$STUB_FIELD>"
  echo "FAIL: Discovered field '$STUB_FIELD' not in allowlist {total_tokens, input_tokens+output_tokens, tokens_estimated}" >&2
  exit 1
fi

echo "DISCOVERED_FIELD=$STUB_FIELD"
echo "PASS: AC-38 — DISCOVERED_FIELD=$STUB_FIELD (in allowlist)"
exit 0
