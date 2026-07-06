#!/usr/bin/env bash
# ===========================================================================
# Test:     claim-ritual-centralized.sh
# AC:       AC-015 (REQ-015) — the dispatch claim-write ritual is centralized and
#   used by fix-bugs, implement-feature AND scaffold (scaffold is NOT exempted).
#   The ritual writes the per-dispatch marker .agent-flow/pending-dispatch.json
#   with the structural fields (claim_nonce, dispatch_seq) and does NOT commit a
#   compared prompt_head_128 (the head is gate-observed). RED today: no ritual /
#   marker exists in the skills, and scaffold has its documented 0-witness gap.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# (1) every governed skill references the per-dispatch marker (the ritual output).
for sk in fix-bugs implement-feature scaffold; do
  d="skills/$sk"
  [ -d "$d" ] || { fail "skill dir $d missing"; continue; }
  if ! grep -rIlq 'pending-dispatch' "$d" 2>/dev/null; then
    fail "ritual: skills/$sk does not reference the marker pending-dispatch.json (centralized ritual missing — scaffold must NOT be exempt)"
  fi
done

# (2) the ritual commits the structural anti-replay fields.
if grep -rIlq 'pending-dispatch' skills 2>/dev/null; then
  grep -rIlq 'claim_nonce' skills 2>/dev/null || fail "ritual: claim_nonce not written by the claim-write ritual"
  grep -rIlq 'dispatch_seq' skills 2>/dev/null || fail "ritual: dispatch_seq not written by the claim-write ritual"
fi

# (3) the ritual must NOT commit a COMPARED prompt_head_128 (gate observes it).
#     A line that writes prompt_head_128 into the CLAIM as a compared field is a
#     regression of REQ-003/REQ-015; flag a committed/compared prompt_head_128.
if grep -rInE 'compared[^\n]*prompt_head_128|prompt_head_128[^\n]*compared' skills 2>/dev/null | grep -qi compared; then
  fail "ritual: a COMPARED prompt_head_128 is committed by a skill (head must be gate-observed, not compared)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: claim-ritual-centralized — fix-bugs/implement-feature/scaffold all use the shared ritual + marker; structural fields written; no compared prompt_head"
  exit 0
fi
exit 1
