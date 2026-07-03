#!/usr/bin/env bash
# ===========================================================================
# Test:     overlay-short-traversal-guard.sh                     [NAMED-11]
# AC:       AC-038 (REQ-038) — path-traversal guard on the derived overlay
#   short name. __overlay_short_name (which forms <override_path>/<short>.toml)
#   MUST REJECT any value containing "/", "\\", or ".." so a forged
#   subagent_type/override_path cannot redirect the digest target outside the
#   repo. Clean names still resolve. Today the function is a bare
#   `${name##*:}` with no guard -> the traversal inputs pass through -> this
#   test FAILS (RED) until the guard lands.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

LIB="$REPO_ROOT/core/lib/stage-invariant.sh"
[ -f "$LIB" ] || { echo "SKIP: $LIB missing" >&2; exit 77; }
# shellcheck disable=SC1090
. "$LIB"

# Clean names resolve to the short form, return 0.
v=$(__overlay_short_name "agent-flow:fixer"); rc=$?
{ [ "$v" = "fixer" ] && [ "$rc" = "0" ]; } || fail "clean: 'agent-flow:fixer' -> '$v' rc=$rc (expected 'fixer'/0)"
v=$(__overlay_short_name "analyst"); rc=$?
{ [ "$v" = "analyst" ] && [ "$rc" = "0" ]; } || fail "clean: bare 'analyst' -> '$v' rc=$rc (expected 'analyst'/0)"

# Traversal payloads MUST be rejected (non-zero return; no clean short emitted).
assert_rejected() {  # $1 = payload  $2 = label
  local rc=0
  __overlay_short_name "$1" >/dev/null 2>&1 || rc=$?
  [ "$rc" != "0" ] || fail "guard: '$2' was ACCEPTED (rc=0) — traversal payload not rejected"
}
assert_rejected "agent-flow:../evil"  "namespaced ../ traversal"
assert_rejected "../../etc/passwd"    "bare ../ traversal"
assert_rejected "a/b"                 "forward-slash"
assert_rejected 'a\b'                 "back-slash"
assert_rejected ".."                  "parent-dir token"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: overlay-short-traversal-guard — clean names resolve; / \\ .. payloads rejected (no traversal .toml path formed)"
  exit 0
fi
exit 1
