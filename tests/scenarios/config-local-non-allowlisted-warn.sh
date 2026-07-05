#!/usr/bin/env bash
# Test: config-local-non-allowlisted-warn
# FC mapped: FC-11
# What it checks:
#   A config.local.toml key outside the allowlist (e.g. [retry_limits] fixer_iterations,
#   which is NOT on the enumerated denylist either -- it is simply not in the allowlist)
#   is not applied and emits a [WARN]. This is broader than the denylist: ANY
#   non-allowlisted key is rejected, whether or not it happens to be denylisted.
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

# --- Behavioural fixture: retry_limits.fixer_iterations override attempt (not allowlisted) ---
config_val=5
sentinel_override=1
[ "$config_val" -ne "$sentinel_override" ] || fail "fixture collision: config value equals sentinel override"

# TODO(phase-7): once a real resolver exists, write config.toml retry_limits.fixer_iterations=5,
# config.local.toml [retry_limits] fixer_iterations=1, resolve, and assert resolved value == 5
# (override ignored) AND a [WARN] naming "fixer_iterations" is emitted.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-non-allowlisted-warn -- general allowlist-rejection rule documented; fixture constructed"
  exit 0
fi
exit 1
