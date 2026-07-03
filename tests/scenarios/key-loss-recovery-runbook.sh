#!/usr/bin/env bash
# ===========================================================================
# Test:     key-loss-recovery-runbook.sh
# AC:       S1 (Phase-8 cycle-1) — benign key-loss recovery is DOCUMENTED and
#   OPERATOR-EXPLICIT, never auto-regen. Asserts:
#     (A) progressed-run key-loss is STILL fail-closed: gate DENY/2 +
#         WITNESS_UNVERIFIABLE, audit UNVERIFIABLE/2, and NO key is silently
#         regenerated. The gate deny reason NAMES the recovery runbook.
#     (B) STRICT_DISPATCH_OFF recovery: the SAME progressed run downgrades to
#         advisory — gate exit 0, audit exit 0 — while STILL recording
#         WITNESS_UNVERIFIABLE (a temporary unblock, not a forge).
#     (C) fresh-run-dir recovery: a genuinely fresh keyed run (zero completed
#         stages + empty ledger + key absent) bootstraps GENERATE -> ALLOW + a
#         new 0600 dispatch.key (rebaseline). This is the documented "archive the
#         run dir and re-run" path.
#     (D) the recovery runbook is DOCUMENTED in state/schema.md and referenced by
#         /check-setup; it explicitly forbids auto-regen on a progressed run.
#   Lock: key-loss must NEVER silently regenerate on a progressed run.
# ===========================================================================
set -uo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
AUDIT="$REPO_ROOT/hooks/validate-dispatch.sh"
SCHEMA="$REPO_ROOT/state/schema.md"
CHECKSETUP="$REPO_ROOT/skills/check-setup/SKILL.md"
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
[ -f "$GATE" ]  || { fail "gate $GATE missing"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }
[ -f "$AUDIT" ] || { fail "audit $AUDIT missing"; echo "FAIL (RED): audit not implemented" >&2; exit 1; }

TASK_STDIN='{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix","description":"x"}}'

# ---------------------------------------------------------------------------
# (A) progressed run, key LOST -> still fail-closed (UNVERIFIABLE), no regen.
# ---------------------------------------------------------------------------
WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/klr_$$")"
trap 'rm -rf "$WORK"' EXIT
RUN="PROJ-71_20260629T120000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{
  "triage":{"dispatched_at":"2026-06-29T12:00:00Z","subagent_type":"agent-flow:analyst",
    "agent_name":"agent-flow:analyst","model":"sonnet","stage_name":"triage",
    "overlay_source":"none","override_path":"customization/",
    "claim_nonce":"11111111111111111111111111111111","dispatch_seq":1,"status":"completed"},
  "fixer_reviewer":{"dispatched_at":"2026-06-29T12:05:00Z","subagent_type":"agent-flow:fixer",
    "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
    "overlay_source":"none","override_path":"customization/",
    "claim_nonce":"22222222222222222222222222222222","dispatch_seq":2,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-06-29T12:05:00Z")
"$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"22222222222222222222222222222222","dispatch_seq":2,"written_at":wnow}, indent=2))
PY

rc=0
out=$( cd "$PROJ" && printf '%s' "$TASK_STDIN" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/g.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "2" ] || fail "(A) gate: key-loss on a progressed run exited $rc (expected fail-closed DENY/2)"
contains "$out" 'WITNESS_UNVERIFIABLE' || fail "(A) gate: reason not WITNESS_UNVERIFIABLE (got: $out)"
contains "$out" 'runbook' || fail "(A) gate: deny reason does not name the recovery runbook"
[ ! -f "$RDIR/dispatch.key" ] || fail "(A) gate: a NEW dispatch.key was regenerated on a progressed run (auto-regen FORBIDDEN)"

alog="$WORK/audit.log"; : > "$alog"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_STATE_JSON="$RDIR/state.json" \
  AGENT_FLOW_AUDIT_LOG="$alog" bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || fail "(A) audit: progressed-run key-loss exited $rc (expected UNVERIFIABLE/2)"
matches_re "$(cat "$alog")" 'fixer_reviewer WITNESS_UNVERIFIABLE' \
  || fail "(A) audit: WITNESS_UNVERIFIABLE not recorded"
[ ! -f "$RDIR/dispatch.key" ] || fail "(A) audit: a dispatch.key appeared (no component may regen on a progressed run)"

# ---------------------------------------------------------------------------
# (B) STRICT_DISPATCH_OFF recovery: advisory unblock, still records UNVERIFIABLE.
# ---------------------------------------------------------------------------
rc=0
out=$( cd "$PROJ" && printf '%s' "$TASK_STDIN" | \
  AGENT_FLOW_STRICT_DISPATCH=0 AGENT_FLOW_AUDIT_LOG="$WORK/g2.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "0" ] || fail "(B) gate advisory: AGENT_FLOW_STRICT_DISPATCH=0 exited $rc (expected 0 — temporary unblock)"
[ ! -f "$RDIR/dispatch.key" ] || fail "(B) gate advisory: must NOT regenerate a key even in advisory mode"
alog2="$WORK/audit2.log"; : > "$alog2"
rc=0
AGENT_FLOW_STRICT_DISPATCH=0 AGENT_FLOW_STATE_JSON="$RDIR/state.json" \
  AGENT_FLOW_AUDIT_LOG="$alog2" bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "(B) audit advisory: exited $rc (expected 0)"
matches_re "$(cat "$alog2")" 'fixer_reviewer WITNESS_UNVERIFIABLE' \
  || fail "(B) audit advisory: must STILL record WITNESS_UNVERIFIABLE"

# ---------------------------------------------------------------------------
# (C) fresh-run-dir recovery: a genuinely fresh keyed run bootstraps GENERATE.
# ---------------------------------------------------------------------------
RUN2="PROJ-71_20260629T130000Z"     # archive old dir, re-run -> a NEW run dir
PROJ2="$WORK/proj2"; RDIR2="$PROJ2/.agent-flow/$RUN2"; mkdir -p "$RDIR2"
"$PYBIN" - "$RDIR2/state.json" <<'PY'
import json, sys
# zero completed stages: the only stage is the one being dispatched now.
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-06-29T13:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","override_path":"customization/",
  "claim_nonce":"33333333333333333333333333333333","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
WNOW2=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-06-29T13:00:00Z")
"$PYBIN" - "$PROJ2/.agent-flow/pending-dispatch.json" "$RUN2" "$WNOW2" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"33333333333333333333333333333333","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
rc=0
out=$( cd "$PROJ2" && printf '%s' "$TASK_STDIN" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/g3.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "0" ] || fail "(C) fresh-run recovery: gate exited $rc (expected bootstrap ALLOW/0)"
! contains "$out" '"permissionDecision":"deny"' || fail "(C) fresh-run recovery: deny on a genuine fresh run"
[ -f "$RDIR2/dispatch.key" ] || fail "(C) fresh-run recovery: bootstrap did not mint a new dispatch.key"
if [ -f "$RDIR2/dispatch.key" ]; then
  KV=$(tr -d '\r\n' < "$RDIR2/dispatch.key")
  matches_re "$KV" '^[0-9a-f]{64}$' || fail "(C) fresh-run recovery: minted key is not 64 lowercase hex"
fi

# ---------------------------------------------------------------------------
# (D) the recovery runbook is DOCUMENTED (operator-explicit, NOT auto-regen).
# ---------------------------------------------------------------------------
[ -f "$SCHEMA" ] || fail "(D) state/schema.md missing"
if [ -f "$SCHEMA" ]; then
  S=$(cat "$SCHEMA")
  contains "$S" 'Key-loss recovery (operator runbook)' || fail "(D) schema: missing the 'Key-loss recovery (operator runbook)' section"
  contains "$S" 'NEVER silently regenerates the key on a progressed run' || fail "(D) schema: runbook must state auto-regen is forbidden on a progressed run"
  contains_i "$S" 'rebaseline' || fail "(D) schema: runbook must describe the rebaseline (fresh run dir) recovery"
  contains "$S" 'AGENT_FLOW_STRICT_DISPATCH=0' || fail "(D) schema: runbook must name the advisory unblock option"
fi
[ -f "$CHECKSETUP" ] || fail "(D) check-setup SKILL.md missing"
if [ -f "$CHECKSETUP" ]; then
  contains "$(cat "$CHECKSETUP")" 'Key-loss recovery' || fail "(D) check-setup: does not reference the key-loss recovery runbook"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: key-loss-recovery-runbook — progressed-run key-loss stays fail-closed (no regen); STRICT_OFF advisory unblock; fresh-run-dir bootstrap rebaselines; runbook documented + operator-explicit"
  exit 0
fi
exit 1
