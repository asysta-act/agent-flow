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
source "$REPO_ROOT/core/lib/config-reader.sh"

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

# --- Layered behavioural fixture: 4 distinct tier values, only the top present tier wins ---
PLUGIN_DEFAULT=5
CONFIG_TOML_VAL=3
CONFIG_LOCAL_VAL=4
CUSTOMIZATION_VAL=2
vals=("$PLUGIN_DEFAULT" "$CONFIG_TOML_VAL" "$CONFIG_LOCAL_VAL" "$CUSTOMIZATION_VAL")
for i in 0 1 2 3; do
  for j in 0 1 2 3; do
    [ "$i" -eq "$j" ] && continue
    if [ "${vals[$i]}" -eq "${vals[$j]}" ]; then
      fail "layered-fixture sanity: tiers $i and $j collide on value ${vals[$i]} (all 4 tiers must be distinct)"
    fi
  done
done

TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc14.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
printf '[retry_limits]\nbuild_retries = %s\n' "$CONFIG_TOML_VAL" > "$TMP/config.toml"
printf '[retry_limits]\nbuild_retries = %s\n' "$CONFIG_LOCAL_VAL" > "$TMP/config.local.toml"
mkdir -p "$TMP/customization"
printf '[limits]\nmax_build_retries = %s\n' "$CUSTOMIZATION_VAL" > "$TMP/customization/fixer.toml"

# Case 1 (full 4-tier): top tier (customization) wins over all lower tiers.
r_full="$(resolve_limit fixer "$TMP/config.toml" "$TMP/config.local.toml" "$TMP/customization" build_retries max_build_retries "$PLUGIN_DEFAULT")"
[ "$r_full" = "$CUSTOMIZATION_VAL" ] || fail "FC-14: full-chain resolution '$r_full' != top tier $CUSTOMIZATION_VAL (customization/{agent}.toml [limits] must win)"

# Case 2 (R3 tier-distinguishing): config.local sets the limit and there is NO customization
# top tier -> config.local MUST win over config.toml. This is the case a 4-tier-with-top-tier
# fixture masks; it proves config.local is a genuine, distinct contributing tier (design §2.4).
r_local="$(resolve_limit fixer "$TMP/config.toml" "$TMP/config.local.toml" "" build_retries max_build_retries "$PLUGIN_DEFAULT")"
[ "$r_local" = "$CONFIG_LOCAL_VAL" ] || fail "FC-14: with no customization tier, config.local ($CONFIG_LOCAL_VAL) must win over config.toml ($CONFIG_TOML_VAL); got '$r_local'"

# Case 3: config.toml wins over plugin default when no higher tier present.
r_conf="$(resolve_limit fixer "$TMP/config.toml" "" "" build_retries max_build_retries "$PLUGIN_DEFAULT")"
[ "$r_conf" = "$CONFIG_TOML_VAL" ] || fail "FC-14: config.toml ($CONFIG_TOML_VAL) must win over plugin default ($PLUGIN_DEFAULT); got '$r_conf'"

# Case 4: nothing set -> plugin default.
r_def="$(resolve_limit fixer "" "" "" build_retries max_build_retries "$PLUGIN_DEFAULT")"
[ "$r_def" = "$PLUGIN_DEFAULT" ] || fail "FC-14: with no tiers set, plugin default ($PLUGIN_DEFAULT) must apply; got '$r_def'"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: limits-precedence-chain -- full chain + config.local tier + config.toml tier + default all resolve in documented order"
  exit 0
fi
exit 1
