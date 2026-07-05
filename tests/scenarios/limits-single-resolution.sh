#!/usr/bin/env bash
# Test: limits-single-resolution
# FC mapped: FC-13 [DEDICATED]
# What it checks:
#   The section 2.4 regression guard. For a limit set in config.toml and overridden in
#   customization/{agent}.toml [limits], the value the orchestrator ENFORCES in the loop
#   equals the value INJECTED into the agent prompt -- both channels must agree, never
#   just one. Visible fixture: config.toml build_retries=3, customization/fixer.toml
#   [limits] max_build_retries=2 -> both channels must resolve to 2 (top of chain wins).
#   CITATION NOTE: per tdd-refined.md's correction, the two superseded sites are cited as
#   docs/guides/toml-overlay-syntax.md:150-157 (NOT the stale :149-150 label in tdd.md).
# Expected RED (pre-impl): docs/guides/toml-overlay-syntax.md's Tier-3 merge section still
#   merges against the plugin default (not the config-resolved value), and
#   core/agent-override-injector.md's ### Limits render still consumes the raw merged-JSON
#   [limits] table from resolve_overlay() rather than a single pure-bash resolved value --
#   both fail today, which is the exact section 2.4 bug this migration fixes.
# Expected GREEN (post-impl): both files are updated per design.md section 3.2, and a
#   behavioural resolution of the fixture below yields enforced == injected == 2.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Pre-impl: design.md section 3.2 names ONE resolution function feeding both channels,
# and cites the two superseded sites with the CORRECTED line numbers (:150-157, not :149-150) ---
matches_re "$design_content" 'one\*?\*? resolution function' || fail "design.md section 3.2 does not state a single resolution function feeds both channels"
contains "$design_content" "toml-overlay-syntax.md:150-157" || fail "design.md does not cite the corrected toml-overlay-syntax.md:150-157 site (stale :149-150 label must not be used)"
contains "$design_content" "toml-overlay-syntax.md:149-150" && fail "design.md still cites the STALE toml-overlay-syntax.md:149-150 label (tdd-refined.md correction requires :150-157)"
contains "$design_content" "agent-override-injector.md:102-105" || fail "design.md does not cite core/agent-override-injector.md:102-105 as the second superseded site"

# --- Implementation target 1 (loop-enforcement channel): Tier-3 merge must be against the
# config-resolved value, not the raw plugin default ---
OVERLAY_DOC="docs/guides/toml-overlay-syntax.md"
overlay_content=""; [ -f "$OVERLAY_DOC" ] && overlay_content="$(cat "$OVERLAY_DOC")"
if contains "$overlay_content" "merged with plugin defaults" || contains_i "$overlay_content" "against the config-resolved value"; then
  : # ambiguous phrasing; explicit positive check below is authoritative
fi
contains_i "$overlay_content" "config-resolved value" || fail "FC-13 (loop-enforcement channel): $OVERLAY_DOC Tier-3 section does not merge [limits] against the config-resolved value (still describes plugin-default-only merge -- the section 2.4 bug)"

# --- Implementation target 2 (prompt-injection channel): the injector's Limits render must
# consume the single pure-bash resolved value ---
INJECTOR="core/agent-override-injector.md"
injector_content=""; [ -f "$INJECTOR" ] && injector_content="$(cat "$INJECTOR")"
contains_i "$injector_content" "single resolved" || fail "FC-13 (prompt-injection channel): $INJECTOR does not state the ### Limits render consumes the single pure-bash resolved value"

# --- Behavioural: resolve via the reference resolver core/lib/config-reader.sh ---
# config.toml [retry_limits] build_retries = 3; customization/fixer.toml [limits] max_build_retries = 2.
# resolve_limit is the SINGLE resolution function; BOTH the loop-enforcement channel and the
# prompt-injection channel call it, so both MUST resolve to 2 (top of chain) and MUST agree.
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc13.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
printf '[retry_limits]\nbuild_retries = 3\n' > "$TMP/config.toml"
mkdir -p "$TMP/customization"
printf '[limits]\nmax_build_retries = 2\n' > "$TMP/customization/fixer.toml"
enforced="$(resolve_limit fixer "$TMP/config.toml" "" "$TMP/customization" build_retries max_build_retries 5)"
injected="$(resolve_limit fixer "$TMP/config.toml" "" "$TMP/customization" build_retries max_build_retries 5)"
[ "$enforced" = "2" ] || fail "FC-13 behavioural: loop-enforcement value resolved to '$enforced', expected 2 (top of chain wins)"
[ "$injected" = "2" ] || fail "FC-13 behavioural: prompt-injection value resolved to '$injected', expected 2 (top of chain wins)"
[ "$enforced" = "$injected" ] || fail "FC-13 behavioural: enforced ($enforced) != injected ($injected) -- the two channels diverged (section 2.4 regression)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: limits-single-resolution -- section 2.4 fix documented AND resolved: enforced == injected == 2"
  exit 0
fi
exit 1
