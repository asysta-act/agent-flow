#!/usr/bin/env bash
# ===========================================================================
# Test:     strict-toggle-reach.sh
# AC:       AC-020 (REQ-020, REQ-050) — the rollback toggle must REACH the
#   Claude-Code-spawned gate, INCLUDING when marker/run resolution is the broken
#   component (a row-g1 DENY — exactly when an operator reaches for rollback).
#   Using a row-g1 brick (matched marker whose claim_nonce is already consumed):
#     - default strict                      -> gate DENY/2
#     - TOP-LEVEL .agent-flow/STRICT_DISPATCH_OFF (checked FIRST) -> ALLOW/0
#     - AGENT_FLOW_STRICT_DISPATCH=0 (settings.json env lever)    -> ALLOW/0
#     - removing the flag / unsetting env restores the strict DENY (no latching)
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-050)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/str_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-7_20260418T220000Z"; NONCE="70707070707070707070707070707070"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"
# Pre-consume the claim_nonce -> a marker that matches subagent_type but is a replay (row g1).
printf '%s\n' "{\"run_id\":\"$RUN\",\"stage\":\"fixer_reviewer\",\"claim_nonce\":\"$NONCE\",\"dispatch_seq\":1,\"tag\":\"00\",\"verdict\":\"WITNESS_OK\"}" > "$RDIR/dispatch-ledger.jsonl"
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-18T22:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"70707070707070707070707070707070","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
write_marker() {
  local wnow; wnow=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T22:00:00Z")
  "$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$wnow" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"70707070707070707070707070707070","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
}
STDIN_JSON=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix","description":"x"}}))
PY
)
run_gate() {  # $1 extra env assignments (space-sep) ; echoes rc
  write_marker
  local rc=0
  ( cd "$PROJ" && printf '%s' "$STDIN_JSON" | \
    env $1 AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
    AGENT_FLOW_AUDIT_LOG="$WORK/a.log" bash "$GATE" >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

# (1) default strict -> DENY/2 (the brick).
rc=$(run_gate "-u AGENT_FLOW_STRICT_DISPATCH")
[ "$rc" = "2" ] || fail "(1) strict: row-g1 replay exited $rc (expected DENY/2 baseline)"

# (2) TOP-LEVEL flag (checked before marker resolution) -> ALLOW/0.
: > "$PROJ/.agent-flow/STRICT_DISPATCH_OFF"
rc=$(run_gate "-u AGENT_FLOW_STRICT_DISPATCH")
[ "$rc" = "0" ] || fail "(2) top-level flag: gate exited $rc (expected ALLOW/0 — flag must reach the gate even when marker resolution bricks)"
rm -f "$PROJ/.agent-flow/STRICT_DISPATCH_OFF"

# (3) AGENT_FLOW_STRICT_DISPATCH=0 env (settings.json env lever) -> ALLOW/0.
rc=$(run_gate "AGENT_FLOW_STRICT_DISPATCH=0")
[ "$rc" = "0" ] || fail "(3) env lever: AGENT_FLOW_STRICT_DISPATCH=0 exited $rc (expected ALLOW/0)"

# (4) no latching: with flag gone and env unset, strict DENY is restored.
rc=$(run_gate "-u AGENT_FLOW_STRICT_DISPATCH")
[ "$rc" = "2" ] || fail "(4) restore: strict DENY not restored after toggle removed (got $rc) — toggle latched"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: strict-toggle-reach — top-level flag + env lever both downgrade a marker-resolution brick to ALLOW; strict restored after removal"
  exit 0
fi
exit 1
