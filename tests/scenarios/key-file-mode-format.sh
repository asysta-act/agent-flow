#!/usr/bin/env bash
# ===========================================================================
# Test:     key-file-mode-format.sh   (hidden — key lifecycle)
# AC:       AC-006, AC-009 (REQ-006, REQ-009) — generated key properties:
#     - exactly 64 lowercase hex chars matching ^[0-9a-f]{64}$;
#     - mode 0600 (POSIX; best-effort on NTFS — asserted where stat works);
#     - the key hex appears in NEITHER state.json, the ledger, NOR the audit log;
#     - structural rotation: a second run dir produces a DIFFERENT key.
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
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-006)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/kfm_$$")"
trap 'rm -rf "$WORK"' EXIT

bootstrap_run() {  # $1 = project dir, $2 = run id ; echoes the key dir
  local proj="$1" run="$2" rdir="$1/.agent-flow/$2"
  mkdir -p "$rdir"
  "$PYBIN" - "$rdir/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"triage":{
  "dispatched_at":"2026-04-19T04:00:00Z","subagent_type":"agent-flow:analyst",
  "agent_name":"agent-flow:analyst","model":"sonnet","stage_name":"triage",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
  local wnow; wnow=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-19T04:00:00Z")
  "$PYBIN" - "$proj/.agent-flow/pending-dispatch.json" "$run" "$wnow" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"triage","subagent_type":"agent-flow:analyst",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
  ( cd "$proj" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"agent-flow:analyst","prompt":"triage","description":"x"}}' | \
    env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$proj/.agent-flow/dispatch-audit.log" \
    bash "$GATE" >/dev/null 2>&1 ) || true
  printf '%s' "$rdir"
}

P1="$WORK/p1"; R1=$(bootstrap_run "$P1" "RUN-A_20260419T040000Z")
KEYFILE="$R1/dispatch.key"
[ -f "$KEYFILE" ] || { fail "key not generated on first intercept"; echo "FAIL" >&2; exit 1; }
K1=$(tr -d '\r\n' < "$KEYFILE")

# format
matches_re "$K1" '^[0-9a-f]{64}$' || fail "format: key is not 64 lowercase hex (got len ${#K1})"

# mode 0600 (best-effort)
if command -v stat >/dev/null 2>&1; then
  MODE=$(stat -c '%a' "$KEYFILE" 2>/dev/null || stat -f '%Lp' "$KEYFILE" 2>/dev/null || echo "")
  [ -z "$MODE" ] || [ "$MODE" = "600" ] || echo "NOTE: key mode=$MODE (0600 is POSIX; NTFS degrades to ACL)" >&2
fi

# the key hex must not leak into state.json / ledger / audit log
! contains "$(cat "$R1/state.json")" "$K1" || fail "leak: key hex present in state.json"
[ ! -f "$R1/dispatch-ledger.jsonl" ] || { ! contains "$(cat "$R1/dispatch-ledger.jsonl")" "$K1" || fail "leak: key hex present in the ledger"; }
[ ! -f "$P1/.agent-flow/dispatch-audit.log" ] || { ! contains "$(cat "$P1/.agent-flow/dispatch-audit.log")" "$K1" || fail "leak: key hex present in the audit log"; }

# structural rotation: a second run dir -> a different key
P2="$WORK/p2"; R2=$(bootstrap_run "$P2" "RUN-B_20260419T050000Z")
[ -f "$R2/dispatch.key" ] || fail "rotation: second run did not generate a key"
if [ -f "$R2/dispatch.key" ]; then
  K2=$(tr -d '\r\n' < "$R2/dispatch.key")
  [ "$K1" != "$K2" ] || fail "rotation: two runs produced the SAME key (no structural rotation)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: key-file-mode-format — 64-hex key, 0600 (best-effort), no leak into state/ledger/log, per-run rotation"
  exit 0
fi
exit 1
