#!/usr/bin/env bash
# ===========================================================================
# Test:     acceptance-gate-selfcheck-repoint.sh
# AC:       AC-040 (REQ-040) — the 21-file Step-Completion-Invariants lockstep
#   and the acceptance-gate self-check CONTENT change.
#     - NO stale 3-tuple "{subagent_type}|{model}|{prompt_head_128}" remains in
#       any agents/*.md or examples/custom-agents/*.md (RED today);
#     - agents/acceptance-gate.md invariant #2 no longer contains "sha256", the
#       3-tuple, "before Tier-1 variable expansion", nor a reference to
#       core/lib/stage-invariant.sh's check_dispatch_witness (RED today);
#     - the repointed self-check reads the gate-owned LEDGER (read-only);
#     - `ls agents/*.md` == 17.
#   (The runtime "keyed run + legacy v1.0 run both pass the self-check" lives in
#    audit-reverify-matrix.sh / inflight-keyless-missing.sh.)
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

AG="agents/acceptance-gate.md"
[ -f "$AG" ] || { echo "SKIP: $AG missing" >&2; exit 77; }

# No stale 3-tuple anywhere in the lockstep file set.
if grep -rIl '{subagent_type}|{model}|{prompt_head_128}' agents/*.md examples/custom-agents/*.md >/dev/null 2>&1; then
  HITS=$(grep -rIl '{subagent_type}|{model}|{prompt_head_128}' agents/*.md examples/custom-agents/*.md 2>/dev/null | tr '\n' ' ')
  fail "lockstep: stale 3-tuple still present in: $HITS"
fi

# acceptance-gate invariant #2 content change — banned strings gone.
AGTXT=$(cat "$AG")
contains "$AGTXT" 'sha256' && fail "acceptance-gate: still references 'sha256' (must be struck)"
contains "$AGTXT" '{subagent_type}|{model}|{prompt_head_128}' && fail "acceptance-gate: still carries the 3-tuple"
contains "$AGTXT" 'before Tier-1 variable expansion' && fail "acceptance-gate: still says 'before Tier-1 variable expansion'"
contains "$AGTXT" 'check_dispatch_witness' && fail "acceptance-gate: still points the self-check at check_dispatch_witness (demoted)"

# Repointed self-check reads the gate-owned ledger.
contains_i "$AGTXT" 'ledger' || fail "acceptance-gate: self-check does not reference the gate-owned ledger"

AGENTS=$(ls agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$AGENTS" = "17" ] || fail "count: agents/*.md = $AGENTS (expected 17)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: acceptance-gate-selfcheck-repoint — no 3-tuple in 17 agents + custom-agents; invariant #2 sha256/3-tuple/Tier-1/check_dispatch_witness struck; ledger-read self-check"
  exit 0
fi
exit 1
