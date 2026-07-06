#!/usr/bin/env bash
# ===========================================================================
# Test:     inflight-keyless-missing.sh                  [NAMED-6] [NAMED-13]
# AC:       AC-024, AC-025 (REQ-023, REQ-024, REQ-025) — graceful migration.
#   The frozen backward-compat anchor fixtures tests/fixtures/witness/state-{a,b,c}.json
#   are at schema_version "1.0" with NO sibling dispatch.key. The keyed
#   verifier MUST fall back to the legacy sha256 dual-mode:
#     state-a -> every stage WITNESS_OK (no false MISMATCH), audit exit 0
#     state-b -> acceptance_gate WITNESS_MISSING, audit exit 0 (MISSING≠exit2)
#     state-c -> acceptance_gate WITNESS_MISMATCH (deliberate malformed), exit 2
#   NO valid v1.0 stage is flipped to a false MISMATCH and NO strict exit 2 is
#   raised on a valid v1.0 state (no migration self-DoS).
#   This is ALSO the A13 wiring of the previously-ORPHAN a/b/c fixtures.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

AUDIT="$REPO_ROOT/hooks/validate-dispatch.sh"
LIB="$REPO_ROOT/core/lib/stage-invariant.sh"
FIXDIR="$REPO_ROOT/tests/fixtures/witness"
PYBIN="$(command -v python3 || command -v python || true)"
[ -f "$AUDIT" ] || { echo "SKIP: $AUDIT missing" >&2; exit 77; }
[ -f "$LIB" ]   || { echo "SKIP: $LIB missing" >&2; exit 77; }
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
for n in a b c; do [ -f "$FIXDIR/state-$n.json" ] || { echo "SKIP: state-$n.json missing" >&2; exit 77; }; done
# shellcheck disable=SC1090
. "$LIB"

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/ikm_$$")"
ISO_OVR="$WORK/override-empty"; mkdir -p "$ISO_OVR"
trap 'rm -rf "$WORK"' EXIT

run_audit() {  # $1 = fixture path ; echoes "rc|logpath"
  local fix="$1"
  local log="$WORK/$(basename "$fix").log"
  local rc=0
  : > "$log"
  env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_STATE_JSON="$fix" AGENT_FLOW_AUDIT_LOG="$log" \
    AGENT_FLOW_OVERRIDE_PATH="$ISO_OVR" bash "$AUDIT" >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$log"
}

# Frozen anchor invariant: schema 1.0 + no sibling key.
for n in a b c; do
  matches_re "$(cat "$FIXDIR/state-$n.json")" '"schema_version"[[:space:]]*:[[:space:]]*"1\.0"' \
    || fail "frozen: state-$n.json is not pinned at schema_version 1.0"
  [ ! -f "$FIXDIR/dispatch.key" ] || fail "frozen: a dispatch.key sibling exists next to the v1.0 anchors"
done

# state-a : all OK, exit 0, NO mismatch/unverifiable.
R=$(run_audit "$FIXDIR/state-a.json"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "0" ] || fail "state-a: audit exited $rc (expected 0; a valid v1.0 state must never strict-exit-2)"
matches_re "$log" 'triage WITNESS_OK' || fail "state-a: triage not WITNESS_OK under keyless dual-mode"
matches_re "$log" 'WITNESS_MISMATCH'  && fail "state-a: a valid v1.0 stage was FALSE-flipped to WITNESS_MISMATCH"
matches_re "$log" 'WITNESS_UNVERIFIABLE' && fail "state-a: keyless v1.0 must NEVER be WITNESS_UNVERIFIABLE"

# state-b : acceptance_gate MISSING, exit 0.
R=$(run_audit "$FIXDIR/state-b.json"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "0" ] || fail "state-b: audit exited $rc (WITNESS_MISSING must never exit 2)"
matches_re "$log" 'acceptance_gate WITNESS_MISSING' || fail "state-b: acceptance_gate not WITNESS_MISSING"

# state-c : acceptance_gate MISMATCH (malformed witness), exit 2.
R=$(run_audit "$FIXDIR/state-c.json"); rc="${R%%|*}"; log=$(cat "${R#*|}")
[ "$rc" = "2" ] || fail "state-c: audit exited $rc (expected 2; a real malformed witness IS a mismatch)"
matches_re "$log" 'acceptance_gate WITNESS_MISMATCH' || fail "state-c: acceptance_gate not WITNESS_MISMATCH"

# Demoted bash verifier agrees on the acceptance_gate stage (a/b/c).
[ "$(check_dispatch_witness acceptance_gate "$FIXDIR/state-a.json" "$ISO_OVR" 2>/dev/null)" = "WITNESS_OK" ] \
  || fail "bash state-a: acceptance_gate expected WITNESS_OK"
[ "$(check_dispatch_witness acceptance_gate "$FIXDIR/state-b.json" "$ISO_OVR" 2>/dev/null)" = "WITNESS_MISSING" ] \
  || fail "bash state-b: acceptance_gate expected WITNESS_MISSING"
[ "$(check_dispatch_witness acceptance_gate "$FIXDIR/state-c.json" "$ISO_OVR" 2>/dev/null)" = "WITNESS_MISMATCH" ] \
  || fail "bash state-c: acceptance_gate expected WITNESS_MISMATCH"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: inflight-keyless-missing — frozen v1.0 a/b/c -> OK/MISSING/MISMATCH (0/0/2); no false MISMATCH, no UNVERIFIABLE; orphans wired"
  exit 0
fi
exit 1
