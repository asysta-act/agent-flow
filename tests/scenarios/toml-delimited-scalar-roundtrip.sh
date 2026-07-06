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
source "$REPO_ROOT/core/lib/config-reader.sh"

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

# --- Behavioural: parse a config.toml with all 4 delimited-scalar cases and split via the
# reference resolver (config_list / config_map). ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc27.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/config.toml" <<'EOF'
[pr_rules]
labels = "bug, automated"
[issue_tracker]
state_transitions = "triage: In Progress; fixed: Fixed"
[notifications]
on_events = ""
[local_deployment]
ports = "3000"
EOF
config_parse "$TMP/config.toml" 0 >/dev/null 2>&1

# Case 1: multi-element list -> exactly 2 elements "bug" and "automated".
mapfile -t labels < <(config_list pr_rules.labels)
[ "${#labels[@]}" -eq 2 ] || fail "FC-27: pr_rules.labels split to ${#labels[@]} elements, expected 2"
[ "${labels[0]:-}" = "bug" ] || fail "FC-27: labels[0]='${labels[0]:-}', expected 'bug'"
[ "${labels[1]:-}" = "automated" ] || fail "FC-27: labels[1]='${labels[1]:-}', expected 'automated' (trimmed)"

# Case 2: multi-entry map -> {triage: "In Progress", fixed: "Fixed"}.
mapfile -t stmap < <(config_map issue_tracker.state_transitions)
[ "${#stmap[@]}" -eq 2 ] || fail "FC-27: state_transitions split to ${#stmap[@]} entries, expected 2"
contains "${stmap[*]}" "triage=In Progress" || fail "FC-27: state_transitions missing 'triage=In Progress' (map value must keep its internal space)"
contains "${stmap[*]}" "fixed=Fixed" || fail "FC-27: state_transitions missing 'fixed=Fixed'"

# Case 3: empty string -> empty list.
mapfile -t empty_list < <(config_list notifications.on_events)
[ "${#empty_list[@]}" -eq 0 ] || fail "FC-27: empty on_events split to ${#empty_list[@]} elements, expected 0 (empty string -> empty list)"

# Case 4: no-delimiter value -> single-element list.
mapfile -t ports < <(config_list local_deployment.ports)
[ "${#ports[@]}" -eq 1 ] || fail "FC-27: ports split to ${#ports[@]} elements, expected 1 (no-delimiter -> single element)"
[ "${ports[0]:-}" = "3000" ] || fail "FC-27: ports[0]='${ports[0]:-}', expected '3000'"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-delimited-scalar-roundtrip -- list(2)/map(2)/empty(0)/single(1) all split correctly via the reference resolver"
  exit 0
fi
exit 1
