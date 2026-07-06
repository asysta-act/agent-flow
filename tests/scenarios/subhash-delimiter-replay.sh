#!/usr/bin/env bash
# ===========================================================================
# Test:     subhash-delimiter-replay.sh
# AC:       AC-011, AC-011b, AC-011c (REQ-011) — construction property lock for
#   the canonical preimage  canon = sha256(f1)|...|sha256(f8).  Pinned facts:
#     (C8) the NAIVE pipe-join COLLIDES on (x, "y|z") vs ("x|y", z) — the
#          delimiter-injection vuln — while the SUB-HASH canon does NOT;
#     (C5) folding `stage` and `run_id` makes test≠e2e_test and run R1≠R2;
#     (nonce) folding `claim_nonce` makes two otherwise-identical dispatches
#          (the ≤5× fixer_reviewer loop) produce DISTINCT tags.
#   This locks the EXACT construction the execute phase must implement; the
#   golden-tag tests (witness-keyed-parity / gate-owned-ledger) catch a wrong
#   production construction end-to-end.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }
command -v openssl   >/dev/null 2>&1 || { echo "SKIP: no openssl"  >&2; exit 77; }

KEY="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
_h()   { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
_tag() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$KEY" | awk '{print $NF}'; }

# --- (C8) delimiter injection: naive join collides, sub-hash does not ---------
# X = (subagent_type="x", model="y|z"); Y = (subagent_type="x|y", model="z").
NAIVE_X="x|y|z"; NAIVE_Y="x|y|z"
[ "$NAIVE_X" = "$NAIVE_Y" ] || fail "C8 premise: the naive join was expected to collide"
SUB_X="$(_h 'x')|$(_h 'y|z')"
SUB_Y="$(_h 'x|y')|$(_h 'z')"
[ "$SUB_X" != "$SUB_Y" ] || fail "C8: sub-hash canon COLLIDED on (x,'y|z') vs ('x|y',z) — injection not closed"
[ "$(_tag "$SUB_X")" != "$(_tag "$SUB_Y")" ] || fail "C8: HMAC over sub-hash canon collided"

# Full 8-field canon helper (subagent_type|model|head|src|dig|stage|run|nonce).
canon() { printf '%s|%s|%s|%s|%s|%s|%s|%s' \
  "$(_h "$1")" "$(_h "$2")" "$(_h "$3")" "$(_h "$4")" "$(_h "$5")" "$(_h "$6")" "$(_h "$7")" "$(_h "$8")"; }

BASE_ST="agent-flow:test-engineer"; BASE_MO="sonnet"; BASE_PH="PROMPT_HEAD"
BASE_SR="none"; BASE_DG="none"; RUN1="RUN-ONE"; N1="11111111111111111111111111111111"

# --- (C5) stage folding: test vs e2e_test, identical otherwise, differ --------
C_TEST=$(canon "$BASE_ST" "$BASE_MO" "$BASE_PH" "$BASE_SR" "$BASE_DG" "test"     "$RUN1" "$N1")
C_E2E=$(canon  "$BASE_ST" "$BASE_MO" "$BASE_PH" "$BASE_SR" "$BASE_DG" "e2e_test" "$RUN1" "$N1")
[ "$(_tag "$C_TEST")" != "$(_tag "$C_E2E")" ] || fail "C5: test and e2e_test tags collided (stage not folded)"

# --- (C5) run_id folding: R1 vs R2 differ -------------------------------------
C_R2=$(canon "$BASE_ST" "$BASE_MO" "$BASE_PH" "$BASE_SR" "$BASE_DG" "test" "RUN-TWO" "$N1")
[ "$(_tag "$C_TEST")" != "$(_tag "$C_R2")" ] || fail "C5: cross-run tags collided (run_id not folded)"

# --- (nonce) claim_nonce folding: iter-1 vs iter-5 of one loop differ ---------
N5="55555555555555555555555555555555"
C_N5=$(canon "$BASE_ST" "$BASE_MO" "$BASE_PH" "$BASE_SR" "$BASE_DG" "test" "$RUN1" "$N5")
[ "$(_tag "$C_TEST")" != "$(_tag "$C_N5")" ] || fail "nonce: same tuple+stage+run but different claim_nonce collided"

# Every sub-hash token is fixed-length 64-hex (can never contain the join byte).
for tok in $(printf '%s' "$C_TEST" | tr '|' ' '); do
  matches_re "$tok" '^[0-9a-f]{64}$' || fail "token '$tok' is not 64-hex (join ambiguity risk)"
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: subhash-delimiter-replay — naive join collides while sub-hash does not; stage/run_id/claim_nonce folding all distinguish tags"
  exit 0
fi
exit 1
