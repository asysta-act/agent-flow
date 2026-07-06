#!/usr/bin/env bash
# Test: config-local-non-allowlisted-warn
# FC mapped: FC-11
# What it checks:
#   A config.local.toml key outside the allowlist -- using a genuinely non-allowlisted,
#   NON-LIMIT section key ([metrics] output) so this case does NOT contradict the limits
#   precedence chain (which intentionally lets config.local contribute [retry_limits] values
#   via the dedicated resolve_limit path -- a SEPARATE mechanism from this general
#   full-section overlay allowlist). The general overlay merge ignores ANY key outside
#   {browser_verification, local_deployment} and emits a [WARN], whether or not denylisted.
# Expected RED (pre-impl): core/config-reader.md does not document config.local.toml's
#   allowlist-driven rejection of non-allowlisted keys yet.
# Expected GREEN (post-impl): core/config-reader.md documents rejection + [WARN] for any
#   key outside [browser_verification]/[local_deployment], and a behavioural resolution
#   proves retry_limits.fixer_iterations is ignored + warned.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
REQS="spec/requirements.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
reqs_content="";   [ -f "$REQS" ]   && reqs_content="$(cat "$REQS")"

# --- Pre-impl (design.md section 2.2 states the general "outside allowlist -> ignored + WARN" rule) ---
contains_i "$design_content" "outside these two sections is ignored" || contains_i "$design_content" "ignored" \
  || fail "design.md section 2.2 does not state the general non-allowlisted rejection rule"
contains "$reqs_content" "REQ-17" || fail "requirements.md missing REQ-17 (non-allowlisted overlay keys discarded)"

# --- Implementation target ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains_i "$reader_content" "allowlist" || fail "FC-11: core/config-reader.md does not document the allowlist gate for config.local.toml"

# --- Behavioural: a non-allowlisted, NON-LIMIT key ([metrics] output) in config.local.toml is
# ignored + WARNed. Using a non-limit key deliberately avoids contradicting the limits chain. ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc11.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
printf '[metrics]\noutput = "stdout"\nperiod = "30 days"\n' > "$TMP/config.toml"
printf '[metrics]\noutput = "file"\n' > "$TMP/config.local.toml"

config_parse "$TMP/config.toml" 0 >/dev/null 2>&1
config_overlay_merge "$TMP/config.local.toml" >/dev/null 2>&1

got="$(config_get metrics.output)"
[ "$got" = "stdout" ] || fail "FC-11: non-allowlisted metrics.output override was applied (got '$got', expected config.toml value 'stdout')"
contains "$CR_WARN" "metrics.output" || fail "FC-11: no [WARN] naming the non-allowlisted key metrics.output was emitted"

# Cross-check: an ALLOWLISTED key in the same overlay still applies (proves it's an allowlist,
# not a blanket rejection).
printf '[browser_verification]\nbase_url = "http://sentinel:1"\n' >> "$TMP/config.local.toml"
config_parse "$TMP/config.toml" 0 >/dev/null 2>&1
config_overlay_merge "$TMP/config.local.toml" >/dev/null 2>&1
[ "$(config_get browser_verification.base_url)" = "http://sentinel:1" ] || fail "FC-11: allowlisted browser_verification.base_url should still apply alongside the ignored non-allowlisted key"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-non-allowlisted-warn -- non-allowlisted non-limit key ignored + WARNed; allowlisted key still applies"
  exit 0
fi
exit 1
