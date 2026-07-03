#!/usr/bin/env bash
# ===========================================================================
# Test:     head128-midcodepoint.sh   (hidden — boundary)
# AC:       AC-051 (REQ-051) — canonical head128() drops a trailing PARTIAL
#   codepoint deterministically. Order: LF-normalize -> UTF-8 -> first 128
#   bytes -> drop trailing partial codepoint.
#   Input: 127 'x' + 'é' (é = 0xC3 0xA9). bytes[:128] = 127 'x' + 0xC3 (a lone
#   lead byte) -> the partial codepoint is DROPPED -> head == 127 'x'.
#   Known-answer (independent): sha256(127*'x') ==
#     70156a14adbabf98cff3a71c7084b417abf057a8efd27329ca36b7202c87d81f
#   If the gate exists, the gate's OBSERVED head signed into the ledger MUST
#   equal this dropped form (the gate computes head128 from tool_input.prompt).
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }

EXPECT_HEAD=$(printf 'x%.0s' $(seq 1 127))    # 127 x's
GOLDEN_SHA="70156a14adbabf98cff3a71c7084b417abf057a8efd27329ca36b7202c87d81f"

# (1) reference self-validation: the canonical head128 drops the partial é.
REF=$("$PYBIN" - <<'PY'
def head128(p):
    b = p.replace("\r\n","\n").replace("\r","\n").encode("utf-8")[:128]
    return b.decode("utf-8","ignore")
print(head128("x"*127 + "é"), end="")
PY
)
[ "$REF" = "$EXPECT_HEAD" ] || fail "reference: head128 did not drop the trailing partial codepoint (len=${#REF})"
RSHA=$(printf '%s' "$REF" | sha256sum | awk '{print $1}')
[ "$RSHA" = "$GOLDEN_SHA" ] || fail "reference: sha256(head) $RSHA != golden $GOLDEN_SHA"

# (2) behavioral: the gate signs head128(observed) — ledger head == dropped form.
GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
if [ -f "$GATE" ]; then
  WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/h128_$$")"
  trap 'rm -rf "$WORK"' EXIT
  RUN="PROJ-4_20260419T010000Z"
  PROJ="$WORK/proj"; RDIR="$PROJ/.agent-flow/$RUN"; mkdir -p "$RDIR"
  printf '%s' "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff" > "$RDIR/dispatch.key"
  : > "$RDIR/dispatch-ledger.jsonl"
  "$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc={"schema_version":"2.0","stages":{"fixer_reviewer":{
  "dispatched_at":"2026-04-19T01:00:00Z","subagent_type":"agent-flow:fixer",
  "agent_name":"agent-flow:fixer","model":"opus","stage_name":"fixer_reviewer",
  "overlay_source":"none","overlay_digest":"none","override_path":"customization/",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"status":"in_progress"}}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(doc, indent=2))
PY
  WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-19T01:00:00Z")
  "$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps({
  "run_id":run,"run_dir":".agent-flow/%s"%run,"state_json":".agent-flow/%s/state.json"%run,
  "stage":"fixer_reviewer","subagent_type":"agent-flow:fixer",
  "claim_nonce":"0123456789abcdef0123456789abcdef","dispatch_seq":1,"written_at":wnow}, indent=2))
PY
  # prompt = 127 'x' + 'é' (the 128th byte straddles a codepoint)
  STDIN_JSON=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"x"*127+"é","description":"x"}}))
PY
)
  ( cd "$PROJ" && printf '%s' "$STDIN_JSON" | \
    env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" AGENT_FLOW_AUDIT_LOG="$WORK/a.log" \
    bash "$GATE" >/dev/null 2>&1 ) || true
  LH=$("$PYBIN" - "$RDIR/dispatch-ledger.jsonl" <<'PY'
import json, sys
last=None
for ln in open(sys.argv[1], encoding="utf-8"):
    ln=ln.strip()
    if ln: last=json.loads(ln)
print((last or {}).get("prompt_head_128",""), end="")
PY
)
  [ "$LH" = "$EXPECT_HEAD" ] \
    || fail "behavioral: ledger head len=${#LH} != dropped form len=${#EXPECT_HEAD} (partial codepoint not dropped by the gate)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: head128-midcodepoint — trailing partial codepoint dropped deterministically (127 x); sha256 == golden; gate signs the dropped head"
  exit 0
fi
exit 1
