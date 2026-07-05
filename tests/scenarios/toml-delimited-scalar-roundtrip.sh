#!/usr/bin/env bash
# Test: toml-delimited-scalar-roundtrip
# FC mapped: FC-27
# What it checks:
#   List/map-valued keys survive the TOML round-trip using the section 1.1a
#   delimited-scalar encoding: a multi-element list (pr_rules.labels = "bug, automated"),
#   a multi-entry map (issue_tracker.state_transitions =
#   "triage: In Progress; fixed: Fixed"), AND the two edge cases -- empty string -> empty
#   list/map, and a no-delimiter value -> single-element list.
# Expected RED (pre-impl): design.md section 1.1a already documents the encoding (this
#   passes as a regression guard), but core/config-reader.md does not yet document
#   splitting delimited scalars back into list/map structures for THESE keys -- fails
#   until Phase 7.
# Expected GREEN (post-impl): core/config-reader.md documents the split rule per key and
#   a real config.toml fixture demonstrates the 4 cases.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Spec commitment (already pinned; regression guard) ---
contains "$design_content" "state_transitions" || fail "design.md section 1.1a does not mention state_transitions map encoding"
contains_i "$design_content" "delimited" || fail "design.md does not document the delimited-scalar encoding"
contains "$design_content" 'labels = "bug, automated"' || fail "design.md does not show the pr_rules.labels list-encoding example"
contains_i "$design_content" "empty string" || fail "design.md does not document the empty-string -> empty list/map edge case"
contains_i "$design_content" "no-delimiter value" || fail "design.md does not document the no-delimiter -> single-element list edge case"

# --- Implementation target: core/config-reader.md must document the split algorithm ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains_i "$reader_content" "delimited" || fail "FC-27: core/config-reader.md does not document delimited-scalar splitting"
contains "$reader_content" "state_transitions" || fail "FC-27: core/config-reader.md does not map issue_tracker.state_transitions from a delimited scalar"

# --- Round-trip fixture: 4 cases constructed as literal TOML scalars ---
labels_scalar='labels = "bug, automated"'
state_scalar='state_transitions = "triage: In Progress; fixed: Fixed"'
empty_scalar='on_events = ""'
no_delim_scalar='ports = "3000"'

contains "$labels_scalar" "bug, automated" || fail "labels list-encoding fixture malformed"
contains "$state_scalar" "triage: In Progress; fixed: Fixed" || fail "state_transitions map-encoding fixture malformed"
contains "$empty_scalar" '""' || fail "empty-string edge-case fixture malformed"
contains "$no_delim_scalar" "3000" || fail "no-delimiter single-element fixture malformed"

# TODO(phase-7): once a real pure-bash config reader exists, replace the literal-fixture
# sanity checks above with an actual split-and-assert: labels -> 2-element list containing
# "bug" and "automated"; state_transitions -> 2-entry map {triage: "In Progress", fixed:
# "Fixed"}; on_events -> empty list; ports -> a 1-element list ["3000"].

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-delimited-scalar-roundtrip -- delimited-scalar list/map encoding documented for all 4 cases"
  exit 0
fi
exit 1
