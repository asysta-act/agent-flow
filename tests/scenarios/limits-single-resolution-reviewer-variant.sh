#!/usr/bin/env bash
# Test: limits-single-resolution-reviewer-variant  [HIDDEN]
# FC mapped: FC-13 [DEDICATED] -- mandatory hidden variant
# What it checks:
#   The SAME section-2.4 single-resolution invariant as the visible
#   tests/limits-single-resolution.sh scenario, but with a DELIBERATELY DIFFERENT
#   agent + limit + value set, so an implementation that special-cases the visible
#   fixture (fixer / build_retries / 3-vs-2) cannot pass this one by accident:
#     visible fixture: agent=fixer,    limit=build_retries/max_build_retries, 3 -> 2
#     hidden  fixture: agent=reviewer, limit=max_review_iterations,           5 -> 3
#   config.toml sets review iterations to 5; customization/reviewer.toml [limits]
#   overrides max_review_iterations to 3. Both the loop-enforcement channel and the
#   prompt-injection channel MUST resolve to 3 -- neither may diverge.
# Expected RED (pre-impl): docs/guides/toml-overlay-syntax.md's Tier-3 merge section
#   still merges [limits] against the raw plugin default (not the config-resolved
#   value), and core/agent-override-injector.md's Limits render still renders whatever
#   resolve_overlay() returns rather than a single pure-bash resolved value -- both
#   fail today for reviewer/max_review_iterations exactly as they do for
#   fixer/max_build_retries in the visible scenario.
# Expected GREEN (post-impl): both channels resolve reviewer's max_review_iterations to
#   3 identically.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Pre-impl regression guard (identical spec citation requirement as the visible test,
# re-verified independently here so a partial/half-applied fix cannot slip through) ---
matches_re "$design_content" 'one\*?\*? resolution function' || fail "design.md section 3.2 does not state a single resolution function feeds both channels"
contains "$design_content" "toml-overlay-syntax.md:150-157" || fail "design.md does not cite the corrected toml-overlay-syntax.md:150-157 site"
contains "$design_content" "toml-overlay-syntax.md:149-150" && fail "design.md still cites the STALE toml-overlay-syntax.md:149-150 label"

# --- Implementation target 1 (loop-enforcement channel) ---
OVERLAY_DOC="docs/guides/toml-overlay-syntax.md"
overlay_content=""; [ -f "$OVERLAY_DOC" ] && overlay_content="$(cat "$OVERLAY_DOC")"
contains_i "$overlay_content" "config-resolved value" || fail "FC-13 (hidden/reviewer variant, loop-enforcement channel): $OVERLAY_DOC still merges [limits] against the raw plugin default"

# --- Implementation target 2 (prompt-injection channel) ---
INJECTOR="core/agent-override-injector.md"
injector_content=""; [ -f "$INJECTOR" ] && injector_content="$(cat "$INJECTOR")"
contains_i "$injector_content" "single resolved" || fail "FC-13 (hidden/reviewer variant, prompt-injection channel): $INJECTOR does not consume a single pure-bash resolved value"

# --- Distinct hidden fixture: reviewer / max_review_iterations, 5 -> 3 (NOT fixer/build_retries) ---
CONFIG_REVIEW_ITERATIONS=5
OVERLAY_MAX_REVIEW_ITERATIONS=3
EXPECTED_RESOLVED=3
if [ "$CONFIG_REVIEW_ITERATIONS" -eq "$OVERLAY_MAX_REVIEW_ITERATIONS" ]; then
  fail "hidden-fixture sanity: config.toml value must differ from the overlay value"
fi
[ "$EXPECTED_RESOLVED" -eq "$OVERLAY_MAX_REVIEW_ITERATIONS" ] || fail "hidden-fixture sanity: expected resolved value must equal the top-tier (customization) value"
# Distinctness guard: this fixture must not literally match the visible scenario's numbers,
# proving it exercises a genuinely different agent/limit pairing.
if [ "$CONFIG_REVIEW_ITERATIONS" -eq 3 ] && [ "$OVERLAY_MAX_REVIEW_ITERATIONS" -eq 2 ]; then
  fail "hidden-fixture sanity: values collide with the visible fixer/build_retries fixture (3 -> 2) -- must be genuinely distinct"
fi

# TODO(phase-7): once a single resolution function exists, run it against config.toml
# (retry.max_review_iterations analog = 5) + customization/reviewer.toml ([limits]
# max_review_iterations = 3), capture BOTH channels, and assert enforced == injected == 3.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: limits-single-resolution-reviewer-variant -- section 2.4 fix holds for a distinct agent/limit pairing (reviewer/max_review_iterations)"
  exit 0
fi
exit 1
