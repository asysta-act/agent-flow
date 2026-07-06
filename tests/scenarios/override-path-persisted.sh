#!/usr/bin/env bash
# ===========================================================================
# Test:     override-path-persisted.sh
# AC:       AC-032 (REQ-032) — the resolved override_path is persisted in
#   state.json and READ FROM THERE by BOTH the gate and the audit (NOT from
#   AGENT_FLOW_OVERRIDE_PATH, which the Claude-Code-spawned hooks never inherit).
#   Corrected model (S2): overlay_digest is GATE-COMPUTED-ONLY — there is no
#   producer-claim-vs-gate digest compare. The configured allowlist root is
#   persisted as the top-level agent_overrides_path = custom-ovr/ (REQ-031 step 1),
#   so the per-stage override_path = custom-ovr/ is confined to the CONFIGURED
#   allowlist (NOT the project root). The proof that the persisted path is honored:
#     match (gate, env points at an EMPTY dir)  -> ALLOW  (env path would have
#       DENIED on an absent .toml; ALLOW proves the persisted path was used) AND
#       the SIGNED ledger digest == the gate's LF recompute of the persisted file.
#     audit pre-edit (env points at the EMPTY dir) -> WITNESS_OK and NO drift
#       advisory (the audit resolved override_path FROM state.json, not the env).
#     audit post-edit of THAT .toml -> OVERLAY_DRIFT_ADVISORY, exit 0 (the audit
#       DID hash the persisted-path .toml — V2 is not a no-op for the non-default
#       path — but a benign post-dispatch edit is advisory, not MISMATCH/2).
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
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }
[ -f "$GATE" ]  || { fail "gate $GATE missing (REQ-032)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }
[ -f "$AUDIT" ] || { fail "audit $AUDIT missing (REQ-032)"; echo "FAIL (RED): audit not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/opp_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-6_20260418T210000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"
mkdir -p "$RDIR" "$PROJ/custom-ovr" "$PROJ/env-empty"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"
"$PYBIN" - "$PROJ/custom-ovr/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Brisk"\n')
PY
DIG=$(sha256sum "$PROJ/custom-ovr/fixer.toml" | awk '{print $1}')

write_claim() {  # persisted override_path = custom-ovr/ ; CLAIM omits overlay_digest
  # The configured Agent-Overrides allowlist root is persisted as the top-level
  # agent_overrides_path = custom-ovr/ (REQ-031 step 1): the per-stage override_path
  # custom-ovr/ is within it, so the gate/audit confine to the CONFIGURED allowlist
  # (NOT the project root), and resolve the path from state.json (NOT env-empty/).
  "$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","agent_overrides_path":"custom-ovr/","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-18T21:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"toml","override_path":"custom-ovr/",
  "claim_nonce":"60606060606060606060606060606060","dispatch_seq":1,"status":"completed"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
}
run_gate() {
  : > "$RDIR/dispatch-ledger.jsonl"
  local wnow; wnow=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T21:00:00Z")
  "$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$wnow" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"60606060606060606060606060606060","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
  local stdin_json rc out
  stdin_json=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix","description":"x"}}))
PY
)
  rc=0
  # env var deliberately points at an EMPTY dir; the hooks must IGNORE it and use state.json.
  out=$( cd "$PROJ" && printf '%s' "$stdin_json" | \
    env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_OVERRIDE_PATH="env-empty/" \
    AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
    AGENT_FLOW_AUDIT_LOG="$WORK/a.log" bash "$GATE" 2>/dev/null ) || rc=$?
  printf '%s|%s' "$rc" "$out"
}
ledger_digest() {
  "$PYBIN" - "$RDIR/dispatch-ledger.jsonl" <<'PY'
import json, sys
last=None
try:
    for ln in open(sys.argv[1], encoding="utf-8"):
        ln=ln.strip()
        if ln: last=json.loads(ln)
except OSError:
    pass
print((last or {}).get("overlay_digest",""))
PY
}
run_audit() {  # env path = env-empty/ ; the audit must resolve override_path from state.json
  local rc=0
  : > "$WORK/postaudit.log"
  ( cd "$PROJ" && env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_OVERRIDE_PATH="env-empty/" \
    AGENT_FLOW_STATE_JSON="$RDIR/state.json" \
    AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
    AGENT_FLOW_AUDIT_LOG="$WORK/postaudit.log" bash "$AUDIT" >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

# match: gate reads custom-ovr/fixer.toml via state.json override_path -> ALLOW.
write_claim
R=$(run_gate); rc="${R%%|*}"; out="${R#*|}"
[ "$rc" = "0" ] || fail "match: gate exited $rc (expected ALLOW/0) — it used the env path, not the persisted override_path"
! contains "$out" '"permissionDecision":"deny"' || fail "match: deny despite a present overlay at the persisted path"
SIGNED=$(ledger_digest)
[ "$SIGNED" = "$DIG" ] || fail "match: ledger digest ($SIGNED) != LF recompute of the persisted-path .toml ($DIG) — V2 no-op / wrong path"

# audit pre-edit: WITNESS_OK + NO drift advisory proves the audit resolved
#   override_path from state.json (custom-ovr/) — had it used env-empty/, the
#   absent .toml would have produced an OVERLAY_DRIFT_ADVISORY notice.
arc=$(run_audit)
[ "$arc" = "0" ] || fail "audit pre-edit: exited $arc (expected 0); the audit must read override_path from state.json, not the env"
matches_re "$(cat "$WORK/postaudit.log")" 'fixer_reviewer WITNESS_OK' \
  || fail "audit pre-edit: expected WITNESS_OK (audit resolved the persisted path)"
! contains "$(cat "$WORK/postaudit.log")" 'OVERLAY_DRIFT_ADVISORY' \
  || fail "audit pre-edit: unexpected drift advisory — the audit hashed the WRONG path (env-empty/), not custom-ovr/"

# one-byte edit of THAT file -> audit ADVISORY (the audit DID hash the persisted-path
#   .toml — drift detected there — but a post-dispatch edit is advisory, not a
#   WITNESS_MISMATCH/exit2; integrity rests on the ledger HMAC tag + gate-time binding).
"$PYBIN" - "$PROJ/custom-ovr/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "brisk"\n')   # B->b, one byte
PY
arc=$(run_audit)
[ "$arc" = "0" ] || fail "audit post-edit: exited $arc (expected ADVISORY/0 — a benign post-dispatch overlay edit must not re-fire as a tamper alarm)"
contains "$(cat "$WORK/postaudit.log")" 'fixer_reviewer OVERLAY_DRIFT_ADVISORY' \
  || fail "audit post-edit: expected OVERLAY_DRIFT_ADVISORY at the persisted path (signed digest != on-disk custom-ovr/ .toml)"
! matches_re "$(cat "$WORK/postaudit.log")" 'fixer_reviewer WITNESS_MISMATCH' \
  || fail "audit post-edit: a benign post-dispatch overlay edit must NOT be WITNESS_MISMATCH (cry-wolf regression)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: override-path-persisted — gate+audit resolve overlay from state.json override_path (custom-ovr/) confined to the configured allowlist (agent_overrides_path), ignoring the env var; gate-signed digest is ground truth; post-dispatch edit is ADVISORY (not MISMATCH)"
  exit 0
fi
exit 1
