#!/usr/bin/env bash
# ===========================================================================
# Test:     gate-owned-ledger.sh
# AC:       AC-014 (REQ-014) — the signed tag lives in the gate-owned ledger,
#   NOT in state.json. After a valid keyed dispatch the gate MUST:
#     - append one line to .agent-flow/{RUN}/dispatch-ledger.jsonl keyed by
#       (run_id, stage, claim_nonce), carrying dispatch_witness_alg + tag + verdict;
#     - leave state.json with NO signed tag and NO key;
#   and no orchestrator/skill step writes or truncates the ledger.
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
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-014)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/gol_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-42_20260418T133000Z"; NONCE="0123456789abcdef0123456789abcdef"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"; : > "$RDIR/dispatch-ledger.jsonl"
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-18T13:30:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":5,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T13:30:00Z")
"$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":5,"written_at":wnow}, indent=2))
PY
STDIN_JSON=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"PROMPT_HEAD_fixer_reviewer","description":"x"}}))
PY
)
rc=0
( cd "$PROJ" && printf '%s' "$STDIN_JSON" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
  AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" AGENT_FLOW_AUDIT_LOG="$WORK/a.log" \
  bash "$GATE" >/dev/null 2>&1 ) || rc=$?
[ "$rc" = "0" ] || fail "setup: gate exited $rc on a valid dispatch (expected ALLOW/0)"

# Ledger line exists, keyed by (run_id, stage, claim_nonce), with alg + tag + verdict.
[ -s "$RDIR/dispatch-ledger.jsonl" ] || fail "ledger: no line written by the gate"
if [ -s "$RDIR/dispatch-ledger.jsonl" ]; then
  CHK=$("$PYBIN" - "$RDIR/dispatch-ledger.jsonl" "$RUN" "$NONCE" <<'PY'
import json, sys
last=None
for ln in open(sys.argv[1], encoding="utf-8"):
    ln=ln.strip()
    if ln: last=json.loads(ln)
e=last or {}
ok = (e.get("run_id")==sys.argv[2] and e.get("stage")=="fixer_reviewer"
      and e.get("claim_nonce")==sys.argv[3]
      and e.get("dispatch_witness_alg")=="hmac-sha256-subhash-v1"
      and e.get("verdict")=="WITNESS_OK"
      and isinstance(e.get("tag"),str) and len(e.get("tag"))==64
      and all(c in "0123456789abcdef" for c in e.get("tag","")))
print("OK" if ok else "BAD:%r"%e)
PY
)
  [ "$CHK" = "OK" ] || fail "ledger: line not correctly keyed/shaped — $CHK"
fi

# state.json carries NO signed tag and NO key.
SJ=$(cat "$RDIR/state.json")
! contains "$SJ" '"dispatch_witness"' || fail "state.json: contains a dispatch_witness tag (must live in the ledger only)"
! matches_re "$SJ" '"tag"[[:space:]]*:' || fail "state.json: contains a 'tag' field"
! contains "$SJ" "$KEYHEX" || fail "state.json: contains the per-run key hex (key must never be in state.json)"

# Orchestrator/skill steps never write or truncate the ledger.
if grep -rIl 'dispatch-ledger' "$REPO_ROOT/skills" >/dev/null 2>&1; then
  fail "ownership: a skill references dispatch-ledger.jsonl (orchestrator must NOT write/truncate the ledger)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: gate-owned-ledger — tag in dispatch-ledger.jsonl keyed by (run_id,stage,claim_nonce); state.json tag/key-free; skills don't write the ledger"
  exit 0
fi
exit 1
