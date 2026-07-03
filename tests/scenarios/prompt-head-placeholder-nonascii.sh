#!/usr/bin/env bash
# ===========================================================================
# Test:     prompt-head-placeholder-nonascii.sh                  [NAMED-5]
# AC:       AC-034a (REQ-029, REQ-034, REQ-051) — the A1 read-robustness lock.
#   A stored prompt_head_128 containing `{ISSUE_ID}` (a `}`), a `,`, and a `"`
#   (and a separate non-ASCII head) MUST be READ byte-exact by BOTH the fixed
#   bash __read_stage_field and Python json.load — so the demoted self-test
#   returns WITNESS_OK over the stored bytes.  Pre-fix the bash sed reader
#   truncates `triage {ISSUE_ID}, say "hi"` to `triage {ISSUE_ID` -> a FALSE
#   WITNESS_MISMATCH (this test FAILS RED today; that is the regression guard).
#   NOTE: this is bash JSON-READ robustness ONLY — it is independent of the
#   gate's post-expansion head OBSERVATION (REQ-051 / AC-051 covers that).
#   The head MUST contain }/,/" or it would never have tripped the A1 bug.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

LIB="$REPO_ROOT/core/lib/stage-invariant.sh"
PYBIN="$(command -v python3 || command -v python || true)"
[ -f "$LIB" ] || { echo "SKIP: $LIB missing" >&2; exit 77; }
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }
# shellcheck disable=SC1090
. "$LIB"

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/php_$$")"
ISO_OVR="$WORK/override-empty"; mkdir -p "$ISO_OVR"
trap 'rm -rf "$WORK"' EXIT

# Heads that MUST trip the old sed (contain }/,/") plus a non-ASCII head.
declare -a HEADS=( 'triage {ISSUE_ID}, say "hi"' 'unícodé—é' )

for head in "${HEADS[@]}"; do
  # Route the head through a FILE (never Python argv/stdout) so non-ASCII bytes
  # survive the Windows MSYS2 cp1252 traps. bash printf emits exact UTF-8.
  printf '%s' "$head" > "$WORK/head.bin"
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

  # (1) bash __read_stage_field returns the head BYTE-EXACT (the named A1 fix).
  GOT_BASH=$(__read_stage_field triage "$f" prompt_head_128)
  [ "$GOT_BASH" = "$head" ] \
    || fail "read-bash head=[$head]: got [$GOT_BASH] (sed truncated at the first }/,/\")"

  # (2) Python json.load returns the same bytes (written to a FILE in UTF-8 to
  #     dodge the cp1252 stdout trap, then byte-compared to the original head).
  "$PYBIN" - "$f" "$WORK/got_py.bin" <<'PY'
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))["stages"]["triage"]["prompt_head_128"]
open(sys.argv[2], "w", encoding="utf-8").write(v)
PY
  GOT_PY=$(cat "$WORK/got_py.bin")
  [ "$GOT_PY" = "$head" ] || fail "read-python head=[$head]: round-trip mismatch"

  # (3) consequently the demoted self-test verdict is WITNESS_OK (not a false mismatch).
  V=$(check_dispatch_witness triage "$f" "$ISO_OVR" 2>/dev/null); rc=$?
  [ "$V" = "WITNESS_OK" ] \
    || fail "verdict head=[$head]: expected WITNESS_OK, got $V (false mismatch from truncated read)"
  [ "$rc" = "0" ] || fail "verdict head=[$head]: rc=$rc (expected 0 for WITNESS_OK)"
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: prompt-head-placeholder-nonascii — {ISSUE_ID}/,/\"/non-ASCII read byte-exact by bash+python; WITNESS_OK (A1 locked out)"
  exit 0
fi
exit 1
