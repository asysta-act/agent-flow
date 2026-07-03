#!/usr/bin/env bash
# ===========================================================================
# Test:     model-shared-parser-resolution.sh   (hidden — false-DENY corner)
# AC:       AC-048 (REQ-048) — model resolution reuses the SINGLE injector TOML
#   parser (skills/setup-agents/lib/toml-merge.sh resolve_overlay), NEVER a
#   naive `grep '^model ='` line-scan (which diverges on `model = "x"  # comment`
#   or `[table]`-scoped keys, re-introducing the orchestrator-vs-gate false-DENY).
#   Structural contract (the durable, environment-independent driver):
#     - the shared parser exists and exports resolve_overlay;
#     - the gate hook references the shared parser (resolve_overlay / toml-merge);
#     - the gate hook does NOT extract `model` via a naive `^model =` grep.
#   (A behavioral `model="sonnet"  # comment` no-false-DENY case is noted for the
#    execute-phase port; tomli is present on this runtime, so it is portable.)
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

PARSER="skills/setup-agents/lib/toml-merge.sh"
GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"

# The single shared parser must exist and export resolve_overlay.
[ -f "$PARSER" ] || fail "shared parser $PARSER missing"
[ -f "$PARSER" ] && { grep -q 'resolve_overlay' "$PARSER" || fail "$PARSER does not define resolve_overlay"; }

if [ ! -f "$GATE" ]; then
  fail "gate $GATE missing (REQ-048) — cannot verify it reuses the shared parser"
else
  GTXT=$(cat "$GATE")
  # MUST reuse the shared parser (by name or path).
  { contains "$GTXT" 'resolve_overlay' || contains "$GTXT" 'toml-merge'; } \
    || fail "gate: does not reference the shared overlay parser (resolve_overlay / toml-merge.sh)"
  # MUST NOT extract model via a naive '^model =' grep.
  if grep -qE "grep[^|]*\^model[[:space:]]*=" "$GATE" 2>/dev/null; then
    fail "gate: extracts model via a naive '^model =' grep (diverges from the TOML parser — false-DENY)"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: model-shared-parser-resolution — shared resolve_overlay parser reused by the gate; no naive '^model =' grep"
  exit 0
fi
exit 1
