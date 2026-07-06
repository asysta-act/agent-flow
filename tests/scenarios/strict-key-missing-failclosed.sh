#!/usr/bin/env bash
# ===========================================================================
# Test:     strict-key-missing-failclosed.sh                     [NAMED-2]
# AC:       AC-023 (REQ-008, REQ-018, REQ-022) — the "delete dispatch.key to
#   skip the gate" disarm must be LOUD, never a silent skip.
#   Given a schema_version "2.0" (keyed) run with ≥1 completed stage whose
#   dispatch.key has been deleted, under strict:
#     - the PreToolUse gate DENYs (deny-JSON + exit 2);
#     - the PostToolUse audit emits WITNESS_UNVERIFIABLE + exit 2;
#     - NEITHER silently exits 0.
#   Plus advisory (AGENT_FLOW_STRICT_DISPATCH=0): audit downgrades to exit 0
#   while STILL recording the WITNESS_UNVERIFIABLE verdict line.
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

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/skm_$$")"
trap 'rm -rf "$WORK"' EXIT
RUN="PROJ-9_20260418T150000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"
mkdir -p "$RDIR"

# Keyed v2.0 state with ONE completed stage (so absent key is row d, not bootstrap).
# NO dispatch.key file is created (deleted/lost). Ledger empty here; the completed
# stage is the positive fresh-run discriminator that fails the bootstrap predicate.
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc = {"schema_version": "2.0", "stages": {
  "triage": {"dispatched_at": "2026-04-18T15:00:00Z", "subagent_type": "agent-flow:analyst",
             "agent_name": "agent-flow:analyst", "model": "sonnet", "stage_name": "triage",
             "overlay_source": "none", "overlay_digest": "none", "override_path": "customization/",
             "claim_nonce": "11111111111111111111111111111111", "dispatch_seq": 1,
             "status": "completed"},
  "fixer_reviewer": {"dispatched_at": "2026-04-18T15:05:00Z", "subagent_type": "agent-flow:fixer",
             "agent_name": "agent-flow:fixer", "model": "opus", "stage_name": "fixer_reviewer",
             "overlay_source": "none", "overlay_digest": "none", "override_path": "customization/",
             "claim_nonce": "22222222222222222222222222222222", "dispatch_seq": 2,
             "status": "in_progress"}}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2))
PY

# ---- Gate side: DENY + exit 2 (key absent, ≥1 completed stage → row d) --------
if [ ! -f "$GATE" ]; then
  fail "gate-missing: $GATE not implemented (REQ-016) — cannot assert fail-closed gate DENY"
else
  WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T15:05:00Z")
  "$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps({
  "run_id": run, "run_dir": ".agent-flow/%s" % run,
  "state_json": ".agent-flow/%s/state.json" % run, "stage": "fixer_reviewer",
  "subagent_type": "agent-flow:fixer", "claim_nonce": "22222222222222222222222222222222",
  "dispatch_seq": 2, "written_at": wnow}, indent=2))
PY
  stdin_json=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix it","description":"x"}}))
PY
)
  rc=0
  out=$( cd "$PROJ" && printf '%s' "$stdin_json" | \
    env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/gate-audit.log" \
    bash "$GATE" 2>/dev/null ) || rc=$?
  [ "$rc" = "2" ] || fail "gate: exited $rc on missing key under strict (expected DENY/2, NOT silent 0)"
  contains "$out" '"permissionDecision":"deny"' || fail "gate: no deny decision on missing key"
  contains "$out" 'WITNESS_UNVERIFIABLE' || fail "gate: reason not WITNESS_UNVERIFIABLE (got: $out)"
fi

# ---- Audit side (strict): WITNESS_UNVERIFIABLE + exit 2 -----------------------
alog="$WORK/audit.log"; : > "$alog"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH \
  AGENT_FLOW_STATE_JSON="$RDIR/state.json" AGENT_FLOW_AUDIT_LOG="$alog" \
  bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || fail "audit-strict: exited $rc on missing key (expected UNVERIFIABLE→exit 2, NOT silent 0)"
matches_re "$(cat "$alog")" 'fixer_reviewer WITNESS_UNVERIFIABLE' \
  || fail "audit-strict: WITNESS_UNVERIFIABLE not recorded for fixer_reviewer"

# ---- Audit side (advisory): downgrades to exit 0 but STILL records verdict ----
alog2="$WORK/audit2.log"; : > "$alog2"
rc=0
AGENT_FLOW_STRICT_DISPATCH=0 \
  AGENT_FLOW_STATE_JSON="$RDIR/state.json" AGENT_FLOW_AUDIT_LOG="$alog2" \
  bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "audit-advisory: AGENT_FLOW_STRICT_DISPATCH=0 exited $rc (expected 0)"
matches_re "$(cat "$alog2")" 'fixer_reviewer WITNESS_UNVERIFIABLE' \
  || fail "audit-advisory: verdict line missing in advisory mode (must still record)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: strict-key-missing-failclosed — gate DENY/2 + audit UNVERIFIABLE/2 under strict; advisory exits 0 but still records"
  exit 0
fi
exit 1
