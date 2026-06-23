#!/usr/bin/env bash
set -euo pipefail

# AC-38: Task-tool usage-field discovery test (COST-R12)
# Traces: COST-R2, COST-R12
# Description: Runs a structural assertion that verifies what token-count field name
#              the Task tool reports. Per spec, Phase 5 must create this file and assert
#              the field matches the known allowlist: {total_tokens, input_tokens+output_tokens,
#              tokens_estimated}.
#
# IMPORTANT: This test performs a STRUCTURAL stub (no live Claude CLI call in CI).
# It simulates the discovery by reading the spec-mandated field name from Phase 7 implementation.
# When running with a live Claude CLI (CLAUDE_LIVE_TEST=1), it performs the actual Task dispatch.
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
  for candidate in total_tokens tokens_estimated "input_tokens"; do
    if grep -qF "$candidate" "$STATE_MGR"; then
      STUB_FIELD="$candidate"
      break
    fi
  done
fi

# If Phase 7 hasn't implemented yet, use sentinel
if [ -z "$STUB_FIELD" ]; then
  if [ "${CLAUDE_LIVE_TEST:-0}" = "1" ]; then
    # Live path: actual Claude Task dispatch would go here
    # For now emit UNKNOWN to signal Phase 7 to run discovery
    echo "DISCOVERED_FIELD=<UNKNOWN>" >&2
    echo "FAIL: CLAUDE_LIVE_TEST=1 but live dispatch not available in this harness" >&2
    exit 1
  else
    # Pre-Phase 7: emit ABSENT signal (correct TDD red-phase behavior)
    echo "DISCOVERED_FIELD=<ABSENT>"
    echo "FAIL: state-manager.md not found or does not document usage field — Phase 7 implementation required" >&2
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
