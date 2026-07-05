#!/usr/bin/env bash
# Test: limits-precedence-citation-verbatim  [HIDDEN]
# FC mapped: FC-13 [DEDICATED] / FC-14 -- citation-correction regression guard
# What it checks:
#   The CITATION CORRECTION from tdd-refined.md: any test asserting the
#   toml-overlay-syntax.md line-citation for the section-2.4 Tier-3 [limits] merge MUST
#   use ":150-157" (the round-2 corrected label), NEVER the stale ":149-150" label from
#   tdd.md's CODEBASE_CONTEXT. This is checked independently of the visible
#   tests/limits-single-resolution.sh scenario (which also asserts this) so that if a
#   future edit to the visible test accidentally regresses the citation (e.g. someone
#   "fixes" it back to :149-150 during a refactor), this hidden guard still catches it.
#   Also verifies design.md does not carry BOTH citations simultaneously (which would be
#   an ambiguous, half-corrected state).
# Expected RED (pre-impl): the citation-integrity assertions against tdd-refined.md /
#   design.md already PASS today (the spec docs are already correct) -- but the final
#   implementation-target assertion below fails: docs/guides/toml-overlay-syntax.md's
#   actual Tier-3 section (the citation's real target, at its CURRENT pre-migration line
#   numbers) still merges [limits] against the raw plugin default, not the
#   config-resolved value the corrected citation describes -- so the file the citation
#   POINTS AT has not yet caught up with the citation itself. That mismatch is the red
#   condition this scenario pins.
# Expected GREEN (post-impl): docs/guides/toml-overlay-syntax.md's Tier-3 section merges
#   against the config-resolved value, matching what the corrected citation describes.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
REFINED="spec/tdd-refined.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
refined_content=""; [ -f "$REFINED" ] && refined_content="$(cat "$REFINED")"

# The correction itself must be documented in tdd-refined.md (the authority for this fact).
contains "$refined_content" ":150-157" || fail "tdd-refined.md does not state the corrected :150-157 citation"
contains "$refined_content" ":149-150" || fail "tdd-refined.md does not name the stale :149-150 label it is correcting"

# design.md must use ONLY the corrected citation -- never the stale one, and never both
# simultaneously (a half-corrected doc would be worse than a fully-stale one: it would
# suggest reviewers already looked and left an inconsistency).
contains "$design_content" "toml-overlay-syntax.md:150-157" || fail "design.md does not cite the corrected toml-overlay-syntax.md:150-157"
contains "$design_content" "toml-overlay-syntax.md:149-150" && fail "design.md STILL carries the stale toml-overlay-syntax.md:149-150 citation (must be fully replaced, not merely supplemented)"

# Implementation target: the citation's actual referent, docs/guides/toml-overlay-syntax.md's
# Tier-3 section, must itself state the config-resolved-value semantics -- not merely exist.
OVERLAY_DOC="docs/guides/toml-overlay-syntax.md"
overlay_content=""; [ -f "$OVERLAY_DOC" ] && overlay_content="$(cat "$OVERLAY_DOC")"
[ -f "$OVERLAY_DOC" ] || fail "$OVERLAY_DOC not found"
contains "$overlay_content" "Tier 3" || fail "$OVERLAY_DOC has no 'Tier 3' section at all (citation target section missing)"
contains_i "$overlay_content" "config-resolved value" || fail "FC-13 (hidden/citation variant): $OVERLAY_DOC's Tier-3 section (the citation's actual referent) still merges against the raw plugin default, not the config-resolved value the corrected citation describes"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: limits-precedence-citation-verbatim -- :150-157 citation correction holds with no stale :149-150 regression"
  exit 0
fi
exit 1
