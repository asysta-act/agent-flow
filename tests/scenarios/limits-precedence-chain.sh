#!/usr/bin/env bash
# Test: limits-precedence-chain
# FC mapped: FC-14
# What it checks:
#   Resolution order is: plugin default < config.toml < config.local.toml <
#   customization/{agent}.toml [limits]. requirements.md renders this chain
#   single-spaced verbatim; design.md renders it inside a padded code block. The primary
#   check targets the single-spaced form in requirements.md (exact string match); a
#   whitespace-tolerant regex check against design.md is the fallback/secondary check.
# Expected RED (pre-impl): the requirements.md/design.md spec-text checks already PASS
#   today (regression guard -- the chain is already pinned in the spec). The
#   IMPLEMENTATION-target assertion against core/config-reader.md is what fails until
#   Phase 7: the current file does not document config.local.toml or the
#   customization/{agent}.toml [limits] tier at all, so it cannot yet state the full
#   4-tier chain.
# Expected GREEN (post-impl): core/config-reader.md documents the full chain, and a
#   layered fixture (plugin default, config.toml, config.local.toml,
#   customization/{agent}.toml) resolves in the documented order.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

REQS="spec/requirements.md"
DESIGN="spec/design.md"
reqs_content="";   [ -f "$REQS" ]   && reqs_content="$(cat "$REQS")"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Primary check: exact single-spaced chain string in requirements.md ---
CHAIN='plugin default < config.toml < config.local.toml < customization/{agent}.toml [limits]'
contains "$reqs_content" "$CHAIN" || fail "requirements.md does not contain the exact single-spaced precedence chain: '$CHAIN'"

# --- Secondary/whitespace-tolerant check against design.md's padded code-block form ---
matches_re "$design_content" 'plugin default[[:space:]]+<[[:space:]]+config\.toml[[:space:]]+<[[:space:]]+config\.local\.toml[[:space:]]+<[[:space:]]+customization/\{agent\}\.toml \[limits\]' \
  || fail "design.md section 3.2 does not render the precedence chain (whitespace-tolerant match failed)"

# --- Implementation target: core/config-reader.md must document the FULL 4-tier chain
# (not just the 2-tier plugin-default/config.toml chain it documents today) ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
matches_re "$reader_content" 'plugin default[[:space:]]*<[[:space:]]*config\.toml[[:space:]]*<[[:space:]]*config\.local\.toml[[:space:]]*<[[:space:]]*customization' \
  || fail "FC-14: core/config-reader.md does not document the full plugin-default < config.toml < config.local.toml < customization/{agent}.toml [limits] chain"

# --- Layered behavioural fixture: 4 tiers, only the top tier should win ---
PLUGIN_DEFAULT=5
CONFIG_TOML_VAL=3
CONFIG_LOCAL_VAL=4
CUSTOMIZATION_VAL=2
# Sanity: all four tiers must be distinct so precedence is actually exercised
vals=("$PLUGIN_DEFAULT" "$CONFIG_TOML_VAL" "$CONFIG_LOCAL_VAL" "$CUSTOMIZATION_VAL")
for i in 0 1 2 3; do
  for j in 0 1 2 3; do
    [ "$i" -eq "$j" ] && continue
    if [ "${vals[$i]}" -eq "${vals[$j]}" ]; then
      fail "layered-fixture sanity: tiers $i and $j collide on value ${vals[$i]} (all 4 tiers must be distinct)"
    fi
  done
done
EXPECTED_RESOLVED="$CUSTOMIZATION_VAL"

# TODO(phase-7): once a single resolution function exists, feed it all four tiers above and
# assert the resolved value equals $CUSTOMIZATION_VAL (2) -- proving the FULL chain, not just
# a 2-tier comparison.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: limits-precedence-chain -- exact chain string present in requirements.md; layered fixture is well-formed"
  exit 0
fi
exit 1
