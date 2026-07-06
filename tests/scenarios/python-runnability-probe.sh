#!/usr/bin/env bash
# ===========================================================================
# Test:     python-runnability-probe.sh
# AC:       AC-018 (REQ-018) — select Python by RUNNABILITY (`cand -c 'import
#   sys'`), not mere PATH presence. A Windows-Store-style stub that is ON PATH
#   but exits non-zero on `-c` must NOT be treated as runnable. Under strict:
#     - the PostToolUse audit emits a LOUD exit 2 (NOT a silent exit 0);
#     - the PreToolUse gate DENYs (deny-JSON + exit 2);
#   advisory (AGENT_FLOW_STRICT_DISPATCH=0) downgrades to exit 0.
#   (Current code does `command -v` then exec -> inherits the stub's exit code,
#    NOT a deliberate fail-closed 2; this FAILS RED until the probe lands.)
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
REALPY="$(command -v python3 || command -v python || true)"
[ -f "$AUDIT" ] || { echo "SKIP: $AUDIT missing" >&2; exit 77; }
[ -n "$REALPY" ] || { echo "SKIP: no real python to build fixtures" >&2; exit 77; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/prp_$$")"
trap 'rm -rf "$WORK"' EXIT

# Build a keyed v2.0 state.json with the REAL python BEFORE we shadow PATH.
RUN="PROJ-1_20260418T230000Z"; RDIR="$WORK/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff" > "$RDIR/dispatch.key"
"$REALPY" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"triage":{
  "dispatched_at":"2026-04-18T23:00:00Z","subagent_type":"agent-flow:analyst",
  "agent_name":"agent-flow:analyst","model":"sonnet","stage_name":"triage",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"99999999999999999999999999999999","dispatch_seq":1,"status":"completed"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY

# A stub PATH whose python/python3 exit non-zero on `-c` (the Windows-Store trap).
STUB="$WORK/stubbin"; mkdir -p "$STUB"
for n in python python3; do
  printf '#!/bin/sh\nexit 9\n' > "$STUB/$n"
  chmod +x "$STUB/$n"
done

# --- audit (strict): LOUD exit 2, not silent 0 --------------------------------
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH PATH="$STUB:$PATH" \
  AGENT_FLOW_STATE_JSON="$RDIR/state.json" AGENT_FLOW_AUDIT_LOG="$WORK/a.log" \
  bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || fail "audit-strict: no runnable python exited $rc (expected LOUD exit 2, NOT silent 0/passthrough)"

# --- audit (advisory): downgrades to exit 0 -----------------------------------
rc=0
env PATH="$STUB:$PATH" AGENT_FLOW_STRICT_DISPATCH=0 \
  AGENT_FLOW_STATE_JSON="$RDIR/state.json" AGENT_FLOW_AUDIT_LOG="$WORK/a2.log" \
  bash "$AUDIT" >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "audit-advisory: AGENT_FLOW_STRICT_DISPATCH=0 exited $rc (expected 0)"

# --- gate (strict): fail-closed DENY + exit 2 ---------------------------------
if [ -f "$GATE" ]; then
  rc=0
  out=$( cd "$WORK" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"agent-flow:analyst","prompt":"x","description":"x"}}' | \
    env -u AGENT_FLOW_STRICT_DISPATCH PATH="$STUB:$PATH" \
    AGENT_FLOW_AUDIT_LOG="$WORK/g.log" bash "$GATE" 2>/dev/null ) || rc=$?
  [ "$rc" = "2" ] || fail "gate-strict: no runnable python exited $rc (expected fail-closed DENY/2)"
  contains "$out" '"permissionDecision":"deny"' || fail "gate-strict: no deny decision when python is unrunnable"
else
  echo "NOTE: PreToolUse gate $GATE not present yet — gate-side probe assertion deferred (RED until implemented)" >&2
  fail "gate $GATE missing (REQ-018 gate-side runnability probe)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: python-runnability-probe — unrunnable python stub -> audit LOUD exit 2 / gate DENY 2 under strict; advisory exits 0"
  exit 0
fi
exit 1
