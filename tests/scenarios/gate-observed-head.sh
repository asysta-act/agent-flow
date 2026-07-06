#!/usr/bin/env bash
# ===========================================================================
# Test:     gate-observed-head.sh                                [NAMED-12]
# AC:       AC-051, AC-003 (REQ-003, REQ-051) — the prompt head is GATE-OBSERVED
#   and signed as ground truth, NEVER compared against an orchestrator claim.
#   Given a CLAIM that carries an ADVISORY prompt_head_128 which DISAGREES with
#   the bytes the orchestrator actually dispatches, the gate MUST:
#     (1) NOT DENY (the head is not a compared field — no LLM byte-reproducibility
#         dependency, so a differing/unreproducible head never false-DENYs);
#     (2) sign its OWN observed head128(tool_input.prompt) into the ledger
#         (the ledger prompt_head_128 == head128(observed), NOT the claim value).
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
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-051)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/goh_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-8_20260418T200000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"; : > "$RDIR/dispatch-ledger.jsonl"

OBSERVED="ACTUAL OBSERVED PROMPT BODY"     # < 128 bytes, so head128 == itself
# CLAIM deliberately stores a WRONG advisory head; it must be ignored by the gate.
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-18T20:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "prompt_head_128":"ORCHESTRATOR_CLAIMED_HEAD_THAT_IS_WRONG",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T20:00:00Z")
"$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
STDIN_JSON=$("$PYBIN" - "$OBSERVED" <<'PY'
import json, sys
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":sys.argv[1],"description":"x"}}))
PY
)
rc=0
OUT=$( cd "$PROJ" && printf '%s' "$STDIN_JSON" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
  AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" AGENT_FLOW_AUDIT_LOG="$WORK/a.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?

# (1) A differing/unreproducible head does NOT cause a DENY.
[ "$rc" = "0" ] || fail "(1) head-not-compared: gate exited $rc on a claim/observed head difference (expected ALLOW/0)"
! contains "$OUT" '"permissionDecision":"deny"' || fail "(1) head-not-compared: gate DENIED on a head difference"

# (2) the ledger records the gate's OBSERVED head, not the wrong claim value.
LH=$("$PYBIN" - "$RDIR/dispatch-ledger.jsonl" <<'PY'
import json, sys
last=None
for ln in open(sys.argv[1], encoding="utf-8"):
    ln=ln.strip()
    if ln: last=json.loads(ln)
print((last or {}).get("prompt_head_128",""))
PY
)
[ "$LH" = "$OBSERVED" ] \
  || fail "(2) observe-and-sign: ledger prompt_head_128='$LH', expected the OBSERVED head '$OBSERVED'"
[ "$LH" != "ORCHESTRATOR_CLAIMED_HEAD_THAT_IS_WRONG" ] \
  || fail "(2) observe-and-sign: gate signed the orchestrator CLAIM head instead of its own observation"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: gate-observed-head — claim/observed head difference does NOT DENY; ledger signs the gate's OBSERVED head"
  exit 0
fi
exit 1
