#!/usr/bin/env bash
# ===========================================================================
# Test:     alg-hint-downgrade-resistance.sh   (hidden — downgrade attack)
# AC:       AC-013 (REQ-013) — alg/version are HINTS; key-file presence is the
#   authority. A v2.0 keyed run (key PRESENT) whose ledger entry carries a tag
#   computed as a BARE LEGACY sha256 (64-hex, but NOT the HMAC) and whose
#   in-file dispatch_witness_alg hint is STRIPPED MUST still be verified under
#   HMAC: the legacy-shape tag fails the HMAC recompute -> WITNESS_MISMATCH /
#   exit 2. Stripping the hint does NOT downgrade verification.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

AUDIT="$REPO_ROOT/hooks/validate-dispatch.sh"
PYBIN="$(command -v python3 || command -v python || true)"
[ -f "$AUDIT" ] || { echo "SKIP: $AUDIT missing" >&2; exit 77; }
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/ahd_$$")"
trap 'rm -rf "$WORK"' EXIT
RUN="PROJ-13_20260419T020000Z"
PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
printf '%s' "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff" > "$RDIR/dispatch.key"

"$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-19T02:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY

# A LEGACY-SHAPE tag: bare sha256 (64-hex) that is NOT the HMAC, and NO
# dispatch_witness_alg hint field in the ledger entry (stripped).
LEGACY_TAG=$(printf '%s' "legacy-bare-sha256" | sha256sum | awk '{print $1}')
"$PYBIN" - "$RDIR/dispatch-ledger.jsonl" "$RUN" "$LEGACY_TAG" <<'PY'
import json, sys
run, tag = sys.argv[2], sys.argv[3]
e={"run_id":run,"stage":"fixer_reviewer","claim_nonce":"0123456789abcdef0123456789abcdef",
   "dispatch_seq":1,"subagent_type":"agent-flow:fixer","model":"opus",
   "prompt_head_128":"PROMPT_HEAD_fixer_reviewer","overlay_source":"none","overlay_digest":"none",
   "tag":tag,"verdict":"WITNESS_OK"}   # NOTE: no dispatch_witness_alg key (hint stripped)
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(e)+"\n")
PY

alog="$WORK/audit.log"; : > "$alog"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_STATE_JSON="$RDIR/state.json" \
  AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
  AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
  AGENT_FLOW_AUDIT_LOG="$alog" bash "$AUDIT" >/dev/null 2>&1 || rc=$?

[ "$rc" = "2" ] || fail "downgrade: legacy-shape tag + stripped hint exited $rc (expected HMAC MISMATCH→2; hint must NOT downgrade)"
matches_re "$(cat "$alog")" 'fixer_reviewer WITNESS_MISMATCH' \
  || fail "downgrade: not WITNESS_MISMATCH — the stripped alg hint wrongly downgraded to legacy sha256 acceptance"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: alg-hint-downgrade-resistance — key present is authority; legacy-shape tag + stripped hint -> WITNESS_MISMATCH/2 (no downgrade)"
  exit 0
fi
exit 1
