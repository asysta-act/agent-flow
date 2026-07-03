#!/usr/bin/env bash
# ===========================================================================
# Test:     ceos-rename-and-counts.sh
# AC:       AC-037, AC-041 (REQ-037, REQ-041) — finish the CEOS_*→AGENT_FLOW_*
#   rename in the 4 named test files, and keep the doc-counts steady.
#     - zero `CEOS_` tokens remain in the 4 files (RED today: each has 1);
#     - `ls agents/*.md` == 17 and `ls skills/*/` == 17 (no skill/agent added);
#     - the strict toggle stays env-only (no new Automation Config section is
#       introduced as `### Strict ...`).
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

for f in stage-list-consistency check-setup-block7-overlay-parser \
         guard-block-overlay-source-parity step-completion-invariants-completeness; do
  p="tests/scenarios/$f.sh"
  [ -f "$p" ] || { fail "missing $p"; continue; }
  if grep -q 'CEOS_' "$p" 2>/dev/null; then
    fail "rename: $p still contains a CEOS_ token (A11 rename incomplete)"
  fi
done

# A13 cleanup: the dead EXPECTED_WITNESS var at witness-large-triage-block.sh:35 is gone.
WLT="tests/scenarios/witness-large-triage-block.sh"
if [ -f "$WLT" ] && grep -q 'EXPECTED_WITNESS' "$WLT" 2>/dev/null; then
  fail "deadvar: $WLT still defines the unused EXPECTED_WITNESS variable (A13 cleanup)"
fi

AGENTS=$(ls agents/*.md 2>/dev/null | wc -l | tr -d ' ')
SKILLS=$(ls -d skills/*/ 2>/dev/null | wc -l | tr -d ' ')
[ "$AGENTS" = "17" ] || fail "count: agents/*.md = $AGENTS (expected 17 — the review's '18' is stale)"
[ "$SKILLS" = "17" ] || fail "count: skills/*/ = $SKILLS (expected 17)"

# Strict toggle stays env-only: no `### Strict ...` Automation Config section added.
if grep -qiE '^###[[:space:]]+Strict[[:space:]]+Dispatch' CLAUDE.md 2>/dev/null; then
  fail "config: a '### Strict Dispatch' section was added (toggle must stay env-only; config count stays 18)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: ceos-rename-and-counts — no CEOS_ in the 4 files; 17 agents / 17 skills; strict toggle stays env-only"
  exit 0
fi
exit 1
