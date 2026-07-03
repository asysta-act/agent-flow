#!/usr/bin/env bash
# ===========================================================================
# Test:     marker-match-or-passthrough.sh                       [NAMED-9]
# AC:       AC-046 (REQ-046) — the load-bearing match-or-pass-through rule.
#     (h1) NO marker present                     -> PASS THROUGH (allow/0, no sign)
#     (h2) marker.subagent_type != observed      -> PASS THROUGH (allow/0, no sign)
#     (multi-dir) marker pins the CHILD run_dir; sorted glob[-1] would pick the
#                 lexically-greater "scaffold-*" parent -> gate uses the MARKER,
#                 not glob[-1], and ALLOWs the valid child dispatch.
#     (g1) marker matches subagent_type but its claim_nonce is ALREADY in the
#          ledger (replay) -> DENY as WITNESS_UNVERIFIABLE (never wrong-match).
#   Pass-through MUST NOT write a ledger line (agent-flow does not govern it).
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
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-046)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/mmp_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

stdin_for() {  # $1 = subagent_type
  "$PYBIN" - "$1" <<'PY'
import json, sys
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":sys.argv[1],"prompt":"do work","description":"x"}}))
PY
}

# --- (h1) NO marker -> PASS THROUGH -------------------------------------------
P="$WORK/h1"; mkdir -p "$P/.agent-flow"
rc=0
out=$( cd "$P" && stdin_for "agent-flow:fixer" | bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "0" ] || fail "(h1) no-marker: gate exited $rc (expected PASS THROUGH/0)"
! contains "$out" '"permissionDecision":"deny"' || fail "(h1) no-marker: gate DENIED an unmarked Task"

# --- (h2) marker subagent_type != observed -> PASS THROUGH --------------------
P="$WORK/h2"; RUN="PROJ-2_20260418T180000Z"; RDIR="$P/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"; : > "$RDIR/dispatch-ledger.jsonl"
WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T18:00:00Z")
"$PYBIN" - "$P/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"dddddddddddddddddddddddddddddddd","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
rc=0
out=$( cd "$P" && stdin_for "some-other-plugin:helper" | \
  env AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "0" ] || fail "(h2) mismatch-marker: gate exited $rc (expected PASS THROUGH/0 for a non-agent-flow Task)"
! contains "$out" '"permissionDecision":"deny"' || fail "(h2) mismatch-marker: gate DENIED an unrelated Task"
[ ! -s "$RDIR/dispatch-ledger.jsonl" ] || fail "(h2) mismatch-marker: a ledger line was written for a pass-through Task"

# --- (multi-dir) marker pins the child; glob[-1] would mispick scaffold-* -----
P="$WORK/md"; mkdir -p "$P/.agent-flow"
CHILD="PROJ-42_20260418T133000Z"
SCAFF="scaffold-zzz_20260418T120000Z"     # sorts AFTER PROJ-* -> glob[-1] trap
CDIR="$P/.agent-flow/$CHILD"; SDIR="$P/.agent-flow/$SCAFF"
mkdir -p "$CDIR" "$SDIR"
printf '%s' "$KEYHEX" > "$CDIR/dispatch.key"; : > "$CDIR/dispatch-ledger.jsonl"
printf '%s' "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" > "$SDIR/dispatch.key"
"$PYBIN" - "$CDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-18T13:30:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":5,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
"$PYBIN" - "$P/.agent-flow/pending-dispatch.json" "$CHILD" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":5,"written_at":wnow}, indent=2))
PY
rc=0
out=$( cd "$P" && stdin_for "agent-flow:fixer" | \
  env AGENT_FLOW_LEDGER="$CDIR/dispatch-ledger.jsonl" \
  AGENT_FLOW_DISPATCH_KEY_FILE="$CDIR/dispatch.key" bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "0" ] || fail "(multi-dir): gate exited $rc — marker-resolved child should ALLOW (no glob[-1] false-DENY)"
! contains "$out" '"permissionDecision":"deny"' || fail "(multi-dir): gate DENIED a valid marker-resolved child dispatch"

# --- (g1) matched marker but claim_nonce already consumed (replay) -> DENY -----
P="$WORK/g1"; RUN="PROJ-3_20260418T190000Z"; RDIR="$P/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"
# Pre-seed the ledger with the SAME claim_nonce -> presenting it again is a replay.
printf '%s\n' '{"run_id":"PROJ-3_20260418T190000Z","stage":"fixer_reviewer","claim_nonce":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","dispatch_seq":1,"tag":"00","verdict":"WITNESS_OK"}' > "$RDIR/dispatch-ledger.jsonl"
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-18T19:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
"$PYBIN" - "$P/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
rc=0
out=$( cd "$P" && stdin_for "agent-flow:fixer" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
  AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "2" ] || fail "(g1) replay: consumed claim_nonce exited $rc (expected DENY/2, never wrong-match)"
contains "$out" 'WITNESS_UNVERIFIABLE' || fail "(g1) replay: reason not WITNESS_UNVERIFIABLE (got: $out)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: marker-match-or-passthrough — no/mismatched marker PASS THROUGH (no ledger); marker pins child over glob[-1]; replayed nonce DENY/UNVERIFIABLE"
  exit 0
fi
exit 1
