#!/usr/bin/env bash
set -euo pipefail

# AC-38: Task-tool usage-field discovery test exists, and its result is documented and
# wired into the real implementation contract (core/state-manager.md) per the known
# field-name allowlist
# Traces: COST-R12
# Description: This test VERIFIES two things: (1) the discovery test file exists and has
#              the minimal executable shape (emits DISCOVERED_FIELD=, handles the
#              UNKNOWN/ABSENT negative cases), and (2) core/state-manager.md — the actual
#              implementation contract that downstream agents read — documents the
#              result.usage read, the DISCOVERED_FIELD wiring, and the known field-name
#              allowlist. Check (2) is the substantive assertion: grepping only the
#              discovery script's own source text (as this file previously did for all
#              checks) can never fail once the script is written once, since a test
#              file trivially "documents" its own vocabulary — it proves nothing about
#              whether the field name was actually wired into the implementation.
#
# NOTE: The actual discovery test at tests/scenarios/cost-task-tool-usage-field-discovery.sh
# performs a structural check only (no live Claude CLI call, ever — see that file's header).
# This test does not execute it; it verifies the discovery script's shape plus the
# real documentation it depends on.

# Depends on Phase 7 implementation

cd "$(dirname "$0")/../.."

DISCOVERY="tests/scenarios/cost-task-tool-usage-field-discovery.sh"
STATE_MGR="core/state-manager.md"

# File must exist (AC-38 first check)
if [ ! -f "$DISCOVERY" ]; then
  echo "FAIL: $DISCOVERY does not exist — create it in Phase 7 (AC-38, COST-R12)" >&2
  exit 1
fi

FAIL=0

# --- Substantive checks: the real contract (core/state-manager.md), not the test's own text ---

# core/state-manager.md must document the result.usage read (the Task-tool response field)
if [ ! -f "$STATE_MGR" ] || ! grep -qF 'result.usage' "$STATE_MGR"; then
  echo "FAIL: $STATE_MGR does not reference 'result.usage'" >&2
  FAIL=1
fi

# core/state-manager.md must document the DISCOVERED_FIELD wiring (COST-R12)
if [ ! -f "$STATE_MGR" ] || ! grep -qE 'DISCOVERED_FIELD' "$STATE_MGR"; then
  echo "FAIL: $STATE_MGR does not document the DISCOVERED_FIELD wiring (COST-R12)" >&2
  FAIL=1
fi

# core/state-manager.md must document the known field-name allowlist
if [ ! -f "$STATE_MGR" ] || ! grep -qE 'total_tokens|input_tokens\+output_tokens|tokens_estimated' "$STATE_MGR"; then
  echo "FAIL: $STATE_MGR missing the known token-field allowlist" >&2
  FAIL=1
fi

# --- Minimal shape checks on the discovery script itself ---

# Must emit DISCOVERED_FIELD= structured summary line
if ! grep -qE 'DISCOVERED_FIELD=' "$DISCOVERY"; then
  echo "FAIL: $DISCOVERY does not emit 'DISCOVERED_FIELD=...' structured summary" >&2
  FAIL=1
fi

# Must exit non-zero on unknown/absent field (negative case documented)
if ! grep -qiE 'UNKNOWN|ABSENT' "$DISCOVERY"; then
  echo "FAIL: $DISCOVERY does not handle UNKNOWN/ABSENT field case" >&2
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "PASS: AC-38 — discovery test exists with required shape, and state-manager.md documents the field wiring + allowlist"
exit "$FAIL"
