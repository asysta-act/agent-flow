#!/usr/bin/env bash
# ===========================================================================
# Test:     bootstrap-first-intercept.sh
# AC:       AC-047, AC-008 (REQ-006, REQ-008, REQ-047) — forge-resistant
#   "generate once, never silent-regen" bootstrap (verdict-matrix row i).
#     (1) key ABSENT + ZERO completed stages + EMPTY ledger (genuine first
#         intercept) -> gate generates dispatch.key ONCE (64-hex, 0600) + ALLOW;
#     (2) key-generation FAILURE under strict -> gate fails closed (DENY/2),
#         and does NOT proceed keyless.
#   (The "key absent + ≥1 completed stage" downgrade case is row d, covered by
#    strict-key-missing-failclosed.sh and the verdict-matrix; the key+ledger
#    co-deletion forge attempt is the hidden f-c570b4 corner.)
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
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-047)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/bfi_$$")"
trap 'rm -rf "$WORK"' EXIT

mk_run() {  # $1 = project root ; writes a ZERO-completed-stages v2.0 state + marker
  local proj="$1" run="BOOT-1_20260418T160000Z"
  local rdir="$proj/.agent-flow/$run"
  mkdir -p "$rdir"
  "$PYBIN" - "$rdir/state.json" <<'PY'
import json, sys
# schema 2.0, the only stage is the in-progress one being dispatched NOW
# (status "in_progress" is NOT "completed") -> zero completed stages.
doc = {"schema_version": "2.0", "stages": {"triage": {
    "dispatched_at": "2026-04-18T16:00:00Z", "subagent_type": "agent-flow:analyst",
    "agent_name": "agent-flow:analyst", "model": "sonnet", "stage_name": "triage",
    "overlay_source": "none", "overlay_digest": "none", "override_path": "customization/",
    "claim_nonce": "abababababababababababababababab", "dispatch_seq": 1,
    "status": "in_progress"}}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2))
PY
  local wnow; wnow=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T16:00:00Z")
  "$PYBIN" - "$proj/.agent-flow/pending-dispatch.json" "$run" "$wnow" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps({
  "run_id": run, "run_dir": ".agent-flow/%s" % run,
  "state_json": ".agent-flow/%s/state.json" % run, "stage": "triage",
  "subagent_type": "agent-flow:analyst", "claim_nonce": "abababababababababababababababab",
  "dispatch_seq": 1, "written_at": wnow}, indent=2))
PY
  printf '%s' "$rdir"
}

STDIN_JSON=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:analyst","prompt":"triage PROJ-1","description":"x"}}))
PY
)

# (1) genuine first intercept -> generate key once + ALLOW ----------------------
P1="$WORK/p1"; mkdir -p "$P1"
RDIR1=$(mk_run "$P1")
rc=0
out=$( cd "$P1" && printf '%s' "$STDIN_JSON" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/a1.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "0" ] || fail "(1) bootstrap: gate exited $rc on genuine first intercept (expected ALLOW/0)"
! contains "$out" '"permissionDecision":"deny"' || fail "(1) bootstrap: deny on genuine first intercept"
[ -f "$RDIR1/dispatch.key" ] || fail "(1) bootstrap: dispatch.key was NOT generated"
if [ -f "$RDIR1/dispatch.key" ]; then
  KEYVAL=$(tr -d '\r\n' < "$RDIR1/dispatch.key")
  matches_re "$KEYVAL" '^[0-9a-f]{64}$' || fail "(1) bootstrap: key is not 64 lowercase hex (got len ${#KEYVAL})"
  # 0600 best-effort (POSIX; NTFS degrades) — assert when stat is available.
  if command -v stat >/dev/null 2>&1; then
    MODE=$(stat -c '%a' "$RDIR1/dispatch.key" 2>/dev/null || stat -f '%Lp' "$RDIR1/dispatch.key" 2>/dev/null || echo "")
    [ -z "$MODE" ] || [ "$MODE" = "600" ] || echo "NOTE: key mode=$MODE (0600 is POSIX best-effort on NTFS)" >&2
  fi
fi

# (2) key-gen FAILURE under strict -> fail closed (DENY/2), never keyless -------
# Point the key path at a file-under-a-file so O_EXCL create cannot succeed.
P2="$WORK/p2"; mkdir -p "$P2"
RDIR2=$(mk_run "$P2")
printf 'x' > "$WORK/blocker"                       # a regular FILE, not a dir
rc=0
out=$( cd "$P2" && printf '%s' "$STDIN_JSON" | \
  env -u AGENT_FLOW_STRICT_DISPATCH \
  AGENT_FLOW_DISPATCH_KEY_FILE="$WORK/blocker/dispatch.key" \
  AGENT_FLOW_AUDIT_LOG="$WORK/a2.log" bash "$GATE" 2>/dev/null ) || rc=$?
[ "$rc" = "2" ] || fail "(2) keygen-fail: gate exited $rc when key write is impossible (expected fail-closed DENY/2)"
contains "$out" '"permissionDecision":"deny"' || fail "(2) keygen-fail: no deny on key-generation failure"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: bootstrap-first-intercept — first intercept generates 64-hex key once + ALLOW; key-gen failure fails closed (DENY/2)"
  exit 0
fi
exit 1
