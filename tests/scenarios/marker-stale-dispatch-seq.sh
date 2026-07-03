#!/usr/bin/env bash
# ===========================================================================
# Test:     marker-stale-dispatch-seq.sh   (hidden — row g1 monotonicity)
# AC:       AC-046 (REQ-046) — the OTHER g1 stale trigger: a marker that MATCHES
#   the observed subagent_type and whose claim_nonce is NOT yet consumed, but
#   whose dispatch_seq is <= the last consumed dispatch_seq in the ledger (a
#   stale marker from a crashed/older stage), MUST be DENIED as
#   WITNESS_UNVERIFIABLE — never wrong-matched to this Task.
#   (The claim_nonce-already-consumed g1 trigger is covered by
#    marker-match-or-passthrough.sh.)
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

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/msd_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-46_20260419T030000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"

# Ledger shows the LAST consumed dispatch_seq = 5 for this run/stage.
printf '%s\n' "{\"run_id\":\"$RUN\",\"stage\":\"fixer_reviewer\",\"claim_nonce\":\"55555555555555555555555555555555\",\"dispatch_seq\":5,\"tag\":\"00\",\"verdict\":\"WITNESS_OK\"}" > "$RDIR/dispatch-ledger.jsonl"

# A FRESH (unconsumed) claim_nonce, but dispatch_seq = 3 (<= 5) -> stale marker.
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-19T03:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"33333333333333333333333333333333","dispatch_seq":3,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-19T03:00:00Z")
"$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"33333333333333333333333333333333","dispatch_seq":3,"written_at":wnow}, indent=2))
PY
rc=0
out=$( cd "$PROJ" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix","description":"x"}}' | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
  AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" AGENT_FLOW_AUDIT_LOG="$WORK/a.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?

[ "$rc" = "2" ] || fail "stale-seq: dispatch_seq=3 <= last-consumed=5 exited $rc (expected DENY/2, never wrong-match)"
contains "$out" 'WITNESS_UNVERIFIABLE' || fail "stale-seq: reason not WITNESS_UNVERIFIABLE (got: $out)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: marker-stale-dispatch-seq — dispatch_seq <= last consumed -> DENY/WITNESS_UNVERIFIABLE (monotonicity enforced)"
  exit 0
fi
exit 1
