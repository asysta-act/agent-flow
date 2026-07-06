#!/usr/bin/env bash
# ===========================================================================
# Test:     keyless-codeletion-unverifiable.sh   (hidden — f-c570b4 corner)
# AC:       AC-025 (fixture ii), AC-047 (REQ-047, REQ-025) — the forge-resistant
#   bootstrap predicate is NOT fakeable by ledger truncation.
#   Given a v2.0 run with ≥1 COMPLETED stage in state.json, an attacker deletes
#   BOTH dispatch.key AND dispatch-ledger.jsonl to fake an "empty ledger / first
#   intercept". Because the zero-completed-stages predicate STILL fails (the
#   completed stage cannot be fabricated away by truncation), the gate MUST
#   return WITNESS_UNVERIFIABLE + DENY — NOT a silent bootstrap re-sign — and it
#   MUST NOT regenerate the key. The audit reports WITNESS_UNVERIFIABLE / exit 2.
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

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/kcu_$$")"
trap 'rm -rf "$WORK"' EXIT
RUN="PROJ-99_20260419T000000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"

# Progressed v2.0 run: triage COMPLETED, fixer_reviewer in-flight.
# BOTH dispatch.key AND dispatch-ledger.jsonl are absent (co-deleted).
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{
  "triage":{"dispatched_at":"2026-04-19T00:00:00Z","subagent_type":"agent-flow:analyst",
    "agent_name":"agent-flow:analyst","model":"sonnet","stage_name":"triage",
    "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
    "claim_nonce":"aaaa1111aaaa1111aaaa1111aaaa1111","dispatch_seq":1,"status":"completed"},
  "fixer_reviewer":{"dispatched_at":"2026-04-19T00:05:00Z","subagent_type":"agent-flow:fixer",
    "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
    "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
    "claim_nonce":"bbbb2222bbbb2222bbbb2222bbbb2222","dispatch_seq":2,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY

# --- audit side: UNVERIFIABLE + exit 2 ----------------------------------------
alog="$WORK/audit.log"; : > "$alog"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_STATE_JSON="$RDIR/state.json" \
  AGENT_FLOW_AUDIT_LOG="$alog" bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || fail "audit: key+ledger co-deletion on a progressed run exited $rc (expected UNVERIFIABLE→2, never bootstrap)"
matches_re "$(cat "$alog")" 'fixer_reviewer WITNESS_UNVERIFIABLE' \
  || fail "audit: not WITNESS_UNVERIFIABLE for the co-deletion forge attempt"

# --- gate side: DENY + exit 2 AND no key regenerated --------------------------
if [ -f "$GATE" ]; then
  WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-19T00:05:00Z")
  "$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"bbbb2222bbbb2222bbbb2222bbbb2222","dispatch_seq":2,"written_at":wnow}, indent=2))
PY
  rc=0
  out=$( cd "$PROJ" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix","description":"x"}}' | \
    env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/g.log" bash "$GATE" 2>/dev/null ) || rc=$?
  [ "$rc" = "2" ] || fail "gate: co-deletion forge attempt exited $rc (expected DENY/2, never silent re-sign)"
  contains "$out" 'WITNESS_UNVERIFIABLE' || fail "gate: reason not WITNESS_UNVERIFIABLE (got: $out)"
  [ ! -f "$RDIR/dispatch.key" ] || fail "gate: a NEW dispatch.key was regenerated on a progressed run (silent re-sign — forbidden)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: keyless-codeletion-unverifiable — key+ledger co-deletion on a progressed run -> UNVERIFIABLE/2, no key regen (bootstrap predicate not forgeable)"
  exit 0
fi
exit 1
