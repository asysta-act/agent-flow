#!/usr/bin/env bash
# ===========================================================================
# Test:     witness-keyed-parity.sh                              [NAMED-1]
# AC:       AC-012  (REQ-010, REQ-011, REQ-012, REQ-029, REQ-030, REQ-038)
# Drives:   the A1/drift regression — the bash read-path and the Python audit
#           path MUST return the SAME verdict for the SAME state.json, for a
#           matrix of prompt_head_128 values that trip the legacy sed reader
#           (`{ISSUE_ID}` -> contains `}`, `triage, impact` -> `,`,
#           `say "hi"` -> `"`), plus non-ASCII and a literal `|`.  Pre-fix the
#           bash sed-reader truncates at the first }/,/" and yields a FALSE
#           WITNESS_MISMATCH while json.load yields WITNESS_OK -> verdicts
#           DIVERGE -> this test FAILS (RED).  Post-fix both read byte-exact.
#
#           Plus a golden keyed-tag KNOWN-ANSWER (defense-in-depth, NON-
#           TAUTOLOGICAL): the expected HMAC tag is pinned as a literal and
#           independently re-derived INSIDE this test with `openssl dgst`
#           (Option-A: hexkey-as-ASCII).  It is then asserted byte-equal to the
#           tag the PRODUCTION gate writes into the gate-owned ledger — the
#           expected value is NEVER produced by the code under test.
#
# Run:      HARNESS_JOBS=1; sequential only; never parallel, never kill.
# Asserts:  assert.sh helpers / here-string grep / exact `[ ]` only.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

LIB="$REPO_ROOT/core/lib/stage-invariant.sh"
AUDIT="$REPO_ROOT/hooks/validate-dispatch.sh"
GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
PYBIN="$(command -v python3 || command -v python || true)"

[ -f "$LIB" ]   || { echo "SKIP: $LIB missing" >&2; exit 77; }
[ -f "$AUDIT" ] || { echo "SKIP: $AUDIT missing" >&2; exit 77; }
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }

# shellcheck disable=SC1090
. "$LIB"

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/wkp_$$")"
ISO_OVR="$WORK/override-empty"   # empty so V2 never fires
mkdir -p "$ISO_OVR"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# PART A — bash read-path verdict == Python audit verdict over the head matrix.
#   The legacy V1 witness is built with an INLINE independent printf|sha256sum
#   over the RAW (unescaped) head; the fixture is written with json.dumps so
#   the `"` / `\` escaping is correct and the readers see the same bytes.
# ---------------------------------------------------------------------------
heads=( 'triage {ISSUE_ID}' 'triage, impact' 'say "hi"' 'triage {ISSUE_ID}, say "hi"' 'unícodé—é' 'a|b' )

for head in "${heads[@]}"; do
  # Route the head through a FILE (never Python argv) so non-ASCII bytes survive
  # the Windows MSYS2 cp1252 argv/stdout traps. bash printf emits exact UTF-8.
  printf '%s' "$head" > "$WORK/head.bin"
  # Independent V1 reference witness: sha256(agent|model|head|src|dig), no NL.
  printf '%s|%s|%s|%s|%s' "agent-flow:analyst" "sonnet" "$head" "none" "none" > "$WORK/canon.bin"
  W=$(sha256sum < "$WORK/canon.bin" | awk '{print $1}')
  f="$WORK/state.json"
  "$PYBIN" - "$f" "$WORK/head.bin" "$W" <<'PY'
import json, sys
f, headfile, w = sys.argv[1], sys.argv[2], sys.argv[3]
head = open(headfile, encoding="utf-8").read()
doc = {"schema_version": "1.0", "stages": {"triage": {
    "dispatched_at": "2026-05-12T10:00:00Z", "agent_name": "agent-flow:analyst",
    "model": "sonnet", "stage_name": "triage", "prompt_head_128": head,
    "overlay_source": "none", "overlay_digest": "none",
    "dispatch_witness": w, "status": "in_progress"}}}
open(f, "w", encoding="utf-8").write(json.dumps(doc, indent=2, ensure_ascii=False))
PY

  # bash read-path verdict (demoted self-test path; legacy v1.0 dual-mode).
  V_BASH=$(check_dispatch_witness triage "$f" "$ISO_OVR" 2>/dev/null)

  # Python audit verdict (the authority): sweep, read the Sweep-2 triage line.
  alog="$WORK/audit.log"; : > "$alog"
  env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_STATE_JSON="$f" AGENT_FLOW_AUDIT_LOG="$alog" \
    AGENT_FLOW_OVERRIDE_PATH="$ISO_OVR" bash "$AUDIT" >/dev/null 2>&1 || true
  pyline=$(grep -E 'triage WITNESS_' "$alog" | tail -n 1)
  V_PY="${pyline##* }"

  # The load-bearing parity assertion: the two readers AGREE, and both say OK
  # (a correct reader of a valid witness, with an A1-tripping head, returns OK).
  [ "$V_BASH" = "$V_PY" ] \
    || fail "A.parity head=[$head]: bash=$V_BASH != python=$V_PY (A1 read drift)"
  [ "$V_BASH" = "WITNESS_OK" ] \
    || fail "A.bash head=[$head]: expected WITNESS_OK, got $V_BASH (sed truncation at }/,/\")"
  [ "$V_PY" = "WITNESS_OK" ] \
    || fail "A.python head=[$head]: expected WITNESS_OK, got $V_PY"
done

# ---------------------------------------------------------------------------
# PART B — golden keyed-tag KNOWN-ANSWER, end-to-end through the PreToolUse gate.
#   The pinned key + tuple were computed offline with TWO independent refs
#   (python hmac + openssl). Here we (1) re-derive the expected tag with an
#   INDEPENDENT openssl one-liner and assert it equals the pinned golden, then
#   (2) drive the production gate and assert the LEDGER tag equals the golden.
# ---------------------------------------------------------------------------
KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
GOLDEN_TAG="2d98801abf01170d1a33478399a96740e92d234ba8d646b67847ed07dec9b735"

# (B0) self-validate the reference: per-field sub-hash canon, Option-A HMAC.
_h() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
CANON="$(_h 'agent-flow:fixer')|$(_h 'opus')|$(_h 'PROMPT_HEAD_fixer_reviewer')|$(_h 'none')|$(_h 'none')|$(_h 'fixer_reviewer')|$(_h 'PROJ-42_20260418T133000Z')|$(_h '0123456789abcdef0123456789abcdef')"
if command -v openssl >/dev/null 2>&1; then
  REF_TAG=$(printf '%s' "$CANON" | openssl dgst -sha256 -hmac "$KEYHEX" | awk '{print $NF}')
  [ "$REF_TAG" = "$GOLDEN_TAG" ] \
    || fail "B0.reference: openssl Option-A HMAC ($REF_TAG) != pinned golden ($GOLDEN_TAG) — reference broken"
fi

if [ ! -f "$GATE" ]; then
  fail "B.gate-missing: PreToolUse gate $GATE does not exist (REQ-016) — cannot pin the ledger tag known-answer"
else
  RUN="PROJ-42_20260418T133000Z"
  RDIR="$WORK/run/.agent-flow/$RUN"
  mkdir -p "$RDIR"
  printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"
  chmod 600 "$RDIR/dispatch.key" 2>/dev/null || true
  LEDGER="$RDIR/dispatch-ledger.jsonl"; : > "$LEDGER"

  "$PYBIN" - "$RDIR/state.json" <<'PY'
import json, sys
doc = {"schema_version": "2.0", "stages": {"fixer_reviewer": {
    "dispatched_at": "2026-04-18T13:30:00Z", "subagent_type": "agent-flow:fixer",
    "agent_name": "agent-flow:fixer", "model": "opus", "stage_name": "fixer_reviewer",
    "overlay_source": "none", "overlay_digest": "none", "override_path": "customization/",
    "claim_nonce": "0123456789abcdef0123456789abcdef", "dispatch_seq": 5,
    "status": "in_progress"}}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2))
PY

  WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T13:30:00Z")
  "$PYBIN" - "$WORK/run/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
m = {"run_id": run, "run_dir": ".agent-flow/%s" % run,
     "state_json": ".agent-flow/%s/state.json" % run, "stage": "fixer_reviewer",
     "subagent_type": "agent-flow:fixer",
     "claim_nonce": "0123456789abcdef0123456789abcdef", "dispatch_seq": 5,
     "written_at": wnow}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(m, indent=2))
PY

  STDIN_JSON=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Task",
    "tool_input": {"subagent_type": "agent-flow:fixer",
                   "prompt": "PROMPT_HEAD_fixer_reviewer",
                   "description": "fix"}}))
PY
)
  rc=0
  OUT=$( cd "$WORK/run" && printf '%s' "$STDIN_JSON" | \
    env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_LEDGER="$LEDGER" AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
    AGENT_FLOW_AUDIT_LOG="$WORK/audit2.log" bash "$GATE" 2>/dev/null ) || rc=$?

  [ "$rc" = "0" ] || fail "B.allow: gate exited $rc on a valid keyed dispatch (expected ALLOW/0)"
  ! contains "$OUT" '"permissionDecision":"deny"' \
    || fail "B.allow: gate emitted a deny decision on a valid keyed dispatch"

  LEDGER_TAG=""
  if [ -s "$LEDGER" ]; then
    LEDGER_TAG=$("$PYBIN" - "$LEDGER" <<'PY'
import json, sys
last = None
for ln in open(sys.argv[1], encoding="utf-8"):
    ln = ln.strip()
    if ln:
        last = json.loads(ln)
print((last or {}).get("tag", ""))
PY
)
  fi
  [ "$LEDGER_TAG" = "$GOLDEN_TAG" ] \
    || fail "B.golden: ledger tag ($LEDGER_TAG) != golden HMAC ($GOLDEN_TAG) — keyed construction drift"
fi

# ---------------------------------------------------------------------------
# PART C — the demoted bash --self-test must pass (parity-pinned smoke).
# ---------------------------------------------------------------------------
rc=0
bash "$LIB" --self-test >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "C.self-test: 'bash $LIB --self-test' exited $rc (expected 0)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: witness-keyed-parity — bash↔python verdicts byte-equal over the A1 head matrix; ledger tag == independently-derived golden HMAC; --self-test green"
  exit 0
fi
exit 1
