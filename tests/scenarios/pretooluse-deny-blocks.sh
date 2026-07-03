#!/usr/bin/env bash
# ===========================================================================
# Test:     pretooluse-deny-blocks.sh                            [NAMED-3]
# AC:       AC-016 (REQ-016) — a failing-verification Task() is truly BLOCKED.
#   Given a keyed v2.0 run whose marker matches the observed subagent_type
#   (so the gate ENFORCEs) but whose CLAIM forges a COMPARED field
#   (claim.subagent_type = agent-flow:publisher while the dispatched/observed
#   subagent_type = agent-flow:fixer), the gate MUST emit BOTH:
#     {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#       "permissionDecision":"deny","permissionDecisionReason":"<verdict>..."}}
#   AND exit 2 — the only combination that blocks Task on Claude Code ≥ 2.1.90.
#   (Asserts the deny output CONTRACT + exit code, the gate's observable proof
#    that the dispatch is blocked rather than merely logged.)
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
[ -f "$GATE" ] || { fail "gate $GATE missing (REQ-016)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/pdb_$$")"
trap 'rm -rf "$WORK"' EXIT
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-5_20260418T170000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"
mkdir -p "$RDIR"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"; chmod 600 "$RDIR/dispatch.key" 2>/dev/null || true
: > "$RDIR/dispatch-ledger.jsonl"

# CLAIM forges subagent_type = agent-flow:publisher (compared field), but the
# marker + the observed tool_input say agent-flow:fixer -> compared mismatch.
"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc = {"schema_version": "2.0", "stages": {"fixer_reviewer": {
    "dispatched_at": "2026-04-18T17:00:00Z", "subagent_type": "agent-flow:publisher",
    "agent_name": "agent-flow:publisher", "model": "opus", "stage_name": "fixer_reviewer",
    "overlay_source": "none", "overlay_digest": "none", "override_path": "customization/",
    "claim_nonce": "cccccccccccccccccccccccccccccccc", "dispatch_seq": 1,
    "status": "in_progress"}}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2))
PY
WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T17:00:00Z")
"$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps({
  "run_id": run, "run_dir": ".agent-flow/%s" % run,
  "state_json": ".agent-flow/%s/state.json" % run, "stage": "fixer_reviewer",
  "subagent_type": "agent-flow:fixer", "claim_nonce": "cccccccccccccccccccccccccccccccc",
  "dispatch_seq": 1, "written_at": wnow}, indent=2))
PY
STDIN_JSON=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"fix the bug","description":"x"}}))
PY
)
rc=0
OUT=$( cd "$PROJ" && printf '%s' "$STDIN_JSON" | \
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/a.log" \
  bash "$GATE" 2>/dev/null ) || rc=$?

# Exit code AND output contract are BOTH asserted (no truthiness).
[ "$rc" = "2" ] || fail "exit: gate exited $rc on a forged compared field (expected 2 to block)"
contains "$OUT" '"hookEventName":"PreToolUse"' || fail "contract: hookEventName PreToolUse missing"
contains "$OUT" '"permissionDecision":"deny"'  || fail "contract: permissionDecision deny missing"
contains "$OUT" '"permissionDecisionReason"'    || fail "contract: permissionDecisionReason missing"
contains "$OUT" 'WITNESS_MISMATCH'              || fail "verdict: reason not WITNESS_MISMATCH (got: $OUT)"

# Structural: the deny envelope is valid JSON with the nested key (here-string, no echo|pipe).
"$PYBIN" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["hookSpecificOutput"]["permissionDecision"]=="deny"' "$OUT" 2>/dev/null \
  || fail "contract: deny output is not valid JSON with hookSpecificOutput.permissionDecision=deny"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: pretooluse-deny-blocks — forged compared field -> deny-JSON {PreToolUse,deny,WITNESS_MISMATCH} + exit 2 (Task blocked)"
  exit 0
fi
exit 1
