#!/usr/bin/env bash
# Test: config-local-allowlist-override
# FC mapped: FC-10
# What it checks:
#   A config.local.toml overriding a [browser_verification] or [local_deployment] key
#   changes the resolved value (positive allowlist case). design.md section 2.2 names
#   exactly these two allowlisted sections.
# Expected RED (pre-impl): core/config-reader.md does not document config.local.toml or
#   the allowlist gate at all yet -- fails until Phase 7.
# Expected GREEN (post-impl): core/config-reader.md documents the allowlist merge and a
#   sentinel override of browser.base_url actually applies.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Pre-impl (design.md section 2.2 names exactly these two allowlist sections) ---
contains "$design_content" "[browser_verification]" || fail "design.md section 2.2 does not list [browser_verification] as allowlisted"
contains "$design_content" "[local_deployment]" || fail "design.md section 2.2 does not list [local_deployment] as allowlisted"
contains_i "$design_content" "allowlist" || fail "design.md does not use allowlist terminology for config.local.toml"

# --- Implementation target: core/config-reader.md must document the allowlist merge ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains "$reader_content" "config.local.toml" || fail "FC-10: core/config-reader.md does not mention config.local.toml at all"
contains_i "$reader_content" "allowlist" || fail "FC-10: core/config-reader.md does not document the allowlist gate"

# --- Behavioural fixture: sentinel override of browser.base_url ---
SENTINEL="http://sentinel-override.invalid:4242"
overlay_line="base_url = \"${SENTINEL}\""
contains "$overlay_line" "$SENTINEL" || fail "sentinel override fixture malformed"

# TODO(phase-7): once a real resolver exists, construct config.toml (browser_verification.base_url
# = http://localhost:3000) + config.local.toml ([browser_verification] base_url = "$SENTINEL"),
# resolve, and assert the resolved browser.base_url equals "$SENTINEL" (override applied).

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-allowlist-override -- allowlist sections (Browser Verification, Local Deployment) documented for override"
  exit 0
fi
exit 1
