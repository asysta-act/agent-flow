#!/usr/bin/env bash
# ===========================================================================
# Test:     deny-canary-version-assert.sh   (hidden — version theater)
# AC:       AC-049 (REQ-049, REQ-016) — runtime version assertion + deny-canary.
#     - the gate UNCONDITIONALLY DENIES the reserved sentinel subagent_type
#       `agent-flow:__deny_canary__` (deny-JSON + exit 2), EVEN with no marker
#       (where an ordinary unmatched Task would pass through). The canary is the
#       once-per-machine handshake that detects a pre-2.1.90 client (where deny
#       is a no-op);
#     - /check-setup runs `claude --version` and fails on < 2.1.90 (the
#       load-bearing primary). (RED today: no version probe in /check-setup.)
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }

# (1) gate: the reserved canary is unconditionally denied (no marker present).
if [ ! -f "$GATE" ]; then
  fail "gate $GATE missing (REQ-049) — canary deny cannot be asserted"
else
  WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/dcv_$$")"
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/.agent-flow"     # NO marker on purpose
  rc=0
  out=$( cd "$WORK" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"agent-flow:__deny_canary__","prompt":"inert","description":"canary"}}' | \
    env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_AUDIT_LOG="$WORK/a.log" bash "$GATE" 2>/dev/null ) || rc=$?
  [ "$rc" = "2" ] || fail "canary: reserved sentinel exited $rc (expected unconditional DENY/2, even with no marker)"
  contains "$out" '"permissionDecision":"deny"' || fail "canary: no deny decision for the reserved sentinel"
fi

# (2) /check-setup carries the parseable Claude-Code-version probe (>= 2.1.90).
if grep -rIl 'check-setup' skills >/dev/null 2>&1 && [ -d skills/check-setup ]; then
  if ! grep -rqE 'claude --version' skills/check-setup 2>/dev/null; then
    fail "check-setup: missing 'claude --version' probe (REQ-049 load-bearing primary)"
  fi
  if ! grep -rqE '2\.1\.90' skills/check-setup 2>/dev/null; then
    fail "check-setup: missing the >= 2.1.90 minimum-version assertion"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: deny-canary-version-assert — reserved canary unconditionally DENIED/2; /check-setup asserts claude --version >= 2.1.90"
  exit 0
fi
exit 1
