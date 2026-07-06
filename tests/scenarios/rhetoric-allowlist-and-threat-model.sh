#!/usr/bin/env bash
# ===========================================================================
# Test:     rhetoric-allowlist-and-threat-model.sh
# AC:       AC-005, AC-026, AC-027, AC-028 (REQ-005, REQ-026, REQ-027, REQ-028)
#   (1) CI rhetoric grep: every line in the witness docs containing a BANNED
#       stem (attestation / tamper-evident / tamper evident / distinct trust
#       domain / the conjugation-robust `prov(e|es|ing) the subagent ran`) must
#       match an exact ALLOWLISTED phrase — else the doc fails.
#   (2) the mandatory honest threat-model paragraph is PRESENT (positive
#       phrases), and itself passes the grep (uses "detection of out-of-key
#       tampering", not the bare stem).
#   (3) the audit log is labeled "best-effort append-only audit log" and leaks
#       no key / HMAC tag / preimage (lines are `<iso> <stage> <verdict>` only).
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DOCS=( state/schema.md CLAUDE.md README.md docs/architecture.md \
       docs/guides/dispatch-enforcement.md core/agent-override-injector.md )

allowlisted() {  # $1 = line ; 0 if it carries an exact sanctioned phrase
  case "$1" in
    *"does NOT prove the subagent ran"*) return 0 ;;
    *"not an attestation"*)              return 0 ;;
    *"NOT tamper-evident"*)              return 0 ;;
    *"separate verifier role, same trust domain"*) return 0 ;;
    *"detection of out-of-key tampering"*) return 0 ;;
  esac
  return 1
}

scan_doc() {  # $1 = path
  local p="$1" line lc
  [ -f "$p" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    lc="${line,,}"
    local banned=1
    case "$lc" in
      *attestation*|*"tamper-evident"*|*"tamper evident"*|*"distinct trust domain"*) banned=0 ;;
    esac
    if matches_re "$line" 'prov(e|es|ing) the subagent ran'; then banned=0; fi
    if [ "$banned" = "0" ] && ! allowlisted "$line"; then
      fail "rhetoric: $p has an un-allowlisted banned stem -> $line"
    fi
  done < "$p"
}

for d in "${DOCS[@]}"; do scan_doc "$d"; done

# (2) mandatory honest threat-model paragraph — positive presence in schema.md.
if [ -f state/schema.md ]; then
  S=$(cat state/schema.md)
  contains "$S" 'detection of out-of-key tampering' || fail "threat-model: missing 'detection of out-of-key tampering'"
  contains "$S" 'a same-user producer can still forge' || fail "threat-model: missing residual 'a same-user producer can still forge'"
  contains "$S" 'does NOT prove the subagent ran' || fail "threat-model: missing 'does NOT prove the subagent ran'"
  contains "$S" 'separate OS trust domain' || fail "threat-model: missing 'separate OS trust domain ... OUT OF SCOPE'"
  contains "$S" 'OUT OF SCOPE' || fail "threat-model: missing 'OUT OF SCOPE' note"
  # REQ-021b residuals: the marker-deletion DoS is documented as an accepted
  # residual, and there is NO prompt-head-drift residual (head is gate-observed).
  contains_i "$S" 'marker' && contains_i "$S" 'dos' \
    || fail "threat-model (REQ-021b): missing the accepted marker-deletion DoS residual"
else
  fail "threat-model: state/schema.md not found"
fi

# (3) audit-log label + no-leak runtime check on a keyless v1.0 anchor.
LABEL_OK=0
for d in state/schema.md docs/guides/dispatch-enforcement.md docs/architecture.md; do
  [ -f "$d" ] && contains "$(cat "$d")" 'best-effort append-only audit log' && LABEL_OK=1
done
[ "$LABEL_OK" = "1" ] || fail "audit-log: docs do not label it 'best-effort append-only audit log'"

AUDIT="hooks/validate-dispatch.sh"; FIX="tests/fixtures/witness/state-a.json"
PYBIN="$(command -v python3 || command -v python || true)"
if [ -f "$AUDIT" ] && [ -f "$FIX" ] && [ -n "$PYBIN" ]; then
  WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/ral_$$")"
  trap 'rm -rf "$WORK"' EXIT
  alog="$WORK/audit.log"; : > "$alog"
  env -u AGENT_FLOW_STRICT_DISPATCH AGENT_FLOW_STATE_JSON="$FIX" \
    AGENT_FLOW_AUDIT_LOG="$alog" bash "$AUDIT" >/dev/null 2>&1 || true
  # No 64-hex token (key/tag/preimage) may appear in the audit log.
  if grep -qE '[0-9a-f]{64}' "$alog" 2>/dev/null; then
    fail "audit-log: a 64-hex token (key/tag/preimage) leaked into the audit log"
  fi
  # Every non-empty line is `<iso-ts> <stage> <verdict>`.
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    # Stage-name class is [a-z0-9_]+ (not [a-z_]+): the hardcoded stage "e2e_test"
    # contains a digit. Same house rule documented in stage-list-consistency.sh:48.
    matches_re "$line" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z[[:space:]]+[a-z0-9_]+[[:space:]]+WITNESS_[A-Z]+$' \
      || matches_re "$line" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z[[:space:]]+[a-z0-9_]+[[:space:]]+(OK|MISSING)$' \
      || fail "audit-log: line not in '<iso> <stage> <verdict>' form -> $line"
  done < "$alog"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: rhetoric-allowlist-and-threat-model — banned stems allowlist-gated; honest threat-model paragraph present; audit log labeled + leak-free"
  exit 0
fi
exit 1
