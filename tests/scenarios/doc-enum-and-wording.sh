#!/usr/bin/env bash
# ===========================================================================
# Test:     doc-enum-and-wording.sh
# AC:       AC-019, AC-033, AC-035 (REQ-019, REQ-033, REQ-035) — doc reconciliations.
#   REQ-019: /check-setup probes the Python stdlib (import sys,hmac,hashlib,secrets)
#            and the zero-dep promise is reworded to "zero third-party PACKAGE
#            dependencies; requires bash + Python 3 (stdlib only)".
#   REQ-033: the overlay_source STATE enum is exactly {toml, none, md_rejected};
#            "md" is provenance-log-only (never written to the state field).
#   REQ-035: stale "hook sources the lib" claims are removed (the PostToolUse
#            hook is pure Python and sources nothing).
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# --- REQ-019: check-setup stdlib probe + reworded zero-dep promise -------------
if [ -d skills/check-setup ]; then
  grep -rqE 'import[[:space:]]+sys,[[:space:]]*hmac,[[:space:]]*hashlib,[[:space:]]*secrets' skills/check-setup 2>/dev/null \
    || fail "check-setup: missing the Python-stdlib probe 'import sys,hmac,hashlib,secrets'"
fi
WORDING_OK=0
for d in README.md CLAUDE.md docs/architecture.md docs/guides/dispatch-enforcement.md; do
  [ -f "$d" ] && contains "$(cat "$d")" 'zero third-party' && WORDING_OK=1
done
[ "$WORDING_OK" = "1" ] || fail "zero-dep: no 'zero third-party PACKAGE dependencies' reconciliation found in the docs"

# --- REQ-033: overlay_source enum reconciled to toml|none|md_rejected ----------
ENUM_OK=0
for d in core/agent-override-injector.md state/schema.md docs/architecture.md; do
  [ -f "$d" ] || continue
  if contains "$(cat "$d")" 'md_rejected' && contains_i "$(cat "$d")" 'provenance'; then ENUM_OK=1; fi
done
[ "$ENUM_OK" = "1" ] || fail "enum: overlay_source not reconciled to {toml,none,md_rejected} with 'md' as provenance-log-only"

# --- REQ-035: stale "sources the lib" claim removed ---------------------------
LIB="core/lib/stage-invariant.sh"
if [ -f "$LIB" ]; then
  HEAD=$(head -n 12 "$LIB")
  contains "$HEAD" 'Sourced by hooks/validate-dispatch.sh' \
    && fail "stale-claim: $LIB still says it is 'Sourced by hooks/validate-dispatch.sh' (the hook is pure Python — A9)"
fi
for d in docs/architecture.md docs/guides/dispatch-enforcement.md; do
  [ -f "$d" ] || continue
  if grep -qiE 'hook[^.]*sources the (lib|library)' "$d" 2>/dev/null; then
    fail "stale-claim: $d still claims the hook 'sources the lib'"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: doc-enum-and-wording — check-setup stdlib probe + zero-third-party wording; overlay enum {toml,none,md_rejected}; no 'sources the lib' claim"
  exit 0
fi
exit 1
