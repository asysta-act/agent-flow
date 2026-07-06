#!/usr/bin/env bash
# ===========================================================================
# Test:     overlay-digest-toml-branch.sh
# AC:       AC-034b (REQ-031, REQ-034) — corrected model (S2). The KEYED-witness
#   overlay-digest AUTHORITY is hooks/lib/witness_overlay.py::recompute_overlay_digest
#   (the ONE LF-normalizing authority the gate computes & signs). This test pins:
#     (1) its toml branch to an EXACT 64-hex known-answer over the RAW LF-normalized
#         .toml FILE bytes, AND
#     (2) the load-bearing S2 property: a CRLF .toml and an LF .toml with identical
#         logical content hash to the SAME digest (platform-stable -> a Windows/CRLF
#         producer can never diverge from the gate -> no false-DENY), AND
#     (3) the legacy bash core/lib/stage-invariant.sh::compute_overlay_digest is
#         retained but is NON-authoritative — it does NOT LF-normalize (its CRLF and
#         LF outputs DIFFER), so it is correctly excluded from the keyed compared path.
# Known-answer (independent, re-derived inline with sha256sum AND pinned literal):
#   sha256 of the RAW LF file bytes  model = "sonnet"\nstyle = "Terse"\n  ==
#   9332d62be687fc1ab1419c5688060c19dbc1d0b5c1fb75d4fabb7c1b2b22cbf8
# ===========================================================================
set -uo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

LIB="$REPO_ROOT/core/lib/stage-invariant.sh"
WO="$REPO_ROOT/hooks/lib/witness_overlay.py"
PYBIN="$(command -v python3 || command -v python || true)"
[ -f "$LIB" ] || { echo "SKIP: $LIB missing" >&2; exit 77; }
[ -f "$WO" ]  || { echo "SKIP: $WO missing" >&2; exit 77; }
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }

GOLDEN_LF="9332d62be687fc1ab1419c5688060c19dbc1d0b5c1fb75d4fabb7c1b2b22cbf8"

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/odtb_$$")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/customization"

# Byte-exact LF .toml -> independent reference + golden self-validation.
"$PYBIN" - "$WORK/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Terse"\n')
PY
REF_LF=$(sha256sum "$WORK/customization/fixer.toml" | awk '{print $1}')
[ "$REF_LF" = "$GOLDEN_LF" ] || fail "reference: inline sha256 of LF file ($REF_LF) != pinned golden ($GOLDEN_LF)"

# (1) AUTHORITY toml branch == golden over the RAW LF file bytes.
OUT=$("$PYBIN" "$WO" digest "customization/" "fixer" "$WORK")
ST="${OUT%% *}"; DIG="${OUT#* }"
[ "$ST" = "OK" ] || fail "authority LF: status '$ST' (expected OK)"
[ "$DIG" = "$GOLDEN_LF" ] || fail "authority LF: digest '$DIG' != golden '$GOLDEN_LF' (formula/normalize drift)"
matches_re "$DIG" '^[0-9a-f]{64}$' || fail "authority LF: digest '$DIG' is not 64 lowercase hex"

# (2) S2 LOCK: CRLF .toml hashes to the SAME digest (LF-normalized -> platform-stable).
"$PYBIN" - "$WORK/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\r\nstyle = "Terse"\r\n')
PY
NAIVE_CRLF=$(sha256sum "$WORK/customization/fixer.toml" | awk '{print $1}')
[ "$NAIVE_CRLF" != "$GOLDEN_LF" ] || fail "precondition: a naive CRLF file digest must differ from the LF digest"
OUT=$("$PYBIN" "$WO" digest "customization/" "fixer" "$WORK")
ST="${OUT%% *}"; DIG="${OUT#* }"
[ "$ST" = "OK" ] || fail "authority CRLF: status '$ST' (expected OK)"
[ "$DIG" = "$GOLDEN_LF" ] \
  || fail "authority CRLF: digest '$DIG' != LF golden '$GOLDEN_LF' — the authority does NOT LF-normalize (S2 regression)"

# Boundary sentinels: absent .toml -> MISMATCH ; traversal short -> DENY.
rm -f "$WORK/customization/fixer.toml"
OUT=$("$PYBIN" "$WO" digest "customization/" "fixer" "$WORK"); ST="${OUT%% *}"
[ "$ST" = "MISMATCH" ] || fail "authority absent: status '$ST' (expected MISMATCH, not a crash)"
OUT=$("$PYBIN" "$WO" digest "customization/" "../escape" "$WORK"); ST="${OUT%% *}"
[ "$ST" = "DENY" ] || fail "authority traversal: status '$ST' (expected DENY)"

# (3) LEGACY bash helper: retained + exercised, but NON-authoritative (no LF-normalize).
# shellcheck disable=SC1090
. "$LIB"
[ "$(compute_overlay_digest none)" = "none" ] || fail "legacy none-branch: expected literal 'none'"
[ "$(compute_overlay_digest md_rejected)" = "md_rejected" ] || fail "legacy md_rejected-branch: expected literal 'md_rejected'"
LEG_TOML=$(compute_overlay_digest toml "$(printf 'model = "sonnet"\nstyle = "Terse"')") \
  || fail "legacy toml-branch returned non-zero"
matches_re "$LEG_TOML" '^[0-9a-f]{64}$' || fail "legacy toml-branch: '$LEG_TOML' is not 64 lowercase hex"
# The legacy helper hashes the bytes AS GIVEN — CRLF vs LF MUST differ (proving it
# is NOT the LF-normalizing keyed authority, hence excluded from the compared path).
LEG_LF=$(compute_overlay_digest toml "$(printf 'x\ny')")
LEG_CRLF=$(compute_overlay_digest toml "$(printf 'x\r\ny')")
[ "$LEG_LF" != "$LEG_CRLF" ] \
  || fail "legacy helper unexpectedly LF-normalizes — it must stay distinct from the keyed authority"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: overlay-digest-toml-branch — authority (witness_overlay) digest == $GOLDEN_LF and is CRLF==LF stable (S2 locked); legacy bash helper retained, non-authoritative"
  exit 0
fi
exit 1
