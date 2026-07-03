#!/usr/bin/env bash
# ===========================================================================
# Test:     audit-reverify-matrix.sh
# AC:       AC-017, AC-022 (REQ-014, REQ-017, REQ-022) — the PostToolUse audit
#   re-verifies the gate signature (2nd layer; cannot block) across matrix rows.
#   The valid tag is MINTED BY THE GATE (no hand-built HMAC), then the audit
#   re-verifies the same run:
#     row a : valid gate-signed ledger  -> WITNESS_OK / exit 0
#     row c : ledger tag corrupted      -> WITNESS_MISMATCH / exit 2 (strict)
#     row f : key present, claimed stage, NO ledger entry -> WITNESS_UNVERIFIABLE / exit 2
#     row e : stage status "skipped"    -> WITNESS_MISSING / exit 0 (never 2)
#   (row d — key absent + completed stage — is covered by strict-key-missing-failclosed.sh)
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

AUDIT="$REPO_ROOT/hooks/validate-dispatch.sh"
GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
PYBIN="$(command -v python3 || command -v python || true)"
[ -f "$AUDIT" ] || { echo "SKIP: $AUDIT missing" >&2; exit 77; }
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-014) — cannot mint a valid ledger for re-verify"; echo "FAIL (RED)" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/arm_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-42_20260418T133000Z"
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
  AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" AGENT_FLOW_AUDIT_LOG="$WORK/g.log" \
  bash "$GATE" >/dev/null 2>&1 ) || rc=$?
[ "$rc" = "0" ] || fail "setup: gate did not ALLOW the valid dispatch (rc=$rc) — cannot seed row a"
cp "$RDIR/dispatch-ledger.jsonl" "$WORK/ledger.good"

run_audit() {  # $1 = ledger path ; echoes "rc|logpath"
  local led="$1" log="$WORK/audit.$RANDOM.log" rc=0
  : > "$log"
  env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_STATE_JSON="$RDIR/state.json" AGENT_FLOW_LEDGER="$led" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" AGENT_FLOW_AUDIT_LOG="$log" \
    bash "$AUDIT" >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$log"
}

# row a : valid gate-signed ledger -> WITNESS_OK / 0
R=$(run_audit "$WORK/ledger.good"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "0" ] || fail "row a: audit re-verify exited $rc on a valid gate signature (expected 0)"
matches_re "$log" 'fixer_reviewer WITNESS_OK' || fail "row a: not WITNESS_OK"

# row c : corrupt the ledger tag -> WITNESS_MISMATCH / 2
"$PYBIN" - "$WORK/ledger.good" "$WORK/ledger.bad" <<'PY'
import json, sys
lines=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
e=lines[-1]; t=e["tag"]; e["tag"]=("f" if t[0]!="f" else "0")+t[1:]   # flip one hex char
open(sys.argv[2],"w",encoding="utf-8").write("\n".join(json.dumps(x) for x in lines)+"\n")
PY
R=$(run_audit "$WORK/ledger.bad"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "2" ] || fail "row c: corrupted tag exited $rc (expected MISMATCH→exit 2)"
matches_re "$log" 'fixer_reviewer WITNESS_MISMATCH' || fail "row c: not WITNESS_MISMATCH"

# row f : key present, claimed non-skipped stage, NO ledger entry -> UNVERIFIABLE / 2
: > "$WORK/ledger.empty"
R=$(run_audit "$WORK/ledger.empty"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "2" ] || fail "row f: empty ledger for a claimed stage exited $rc (expected UNVERIFIABLE→exit 2)"
matches_re "$log" 'fixer_reviewer WITNESS_UNVERIFIABLE' || fail "row f: not WITNESS_UNVERIFIABLE"

# row e : stage skipped -> WITNESS_MISSING / 0 (never exit 2)
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
d["stages"]["fixer_reviewer"]["status"]="skipped"
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(d, indent=2))
PY
R=$(run_audit "$WORK/ledger.empty"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "0" ] || fail "row e: skipped stage exited $rc (WITNESS_MISSING must never exit 2)"
matches_re "$log" 'fixer_reviewer WITNESS_MISSING' || fail "row e: not WITNESS_MISSING"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: audit-reverify-matrix — re-verify rows a/c/f/e -> OK/0, MISMATCH/2, UNVERIFIABLE/2, MISSING/0"
  exit 0
fi
exit 1
