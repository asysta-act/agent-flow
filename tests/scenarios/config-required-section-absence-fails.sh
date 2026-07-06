#!/usr/bin/env bash
# Test: config-required-section-absence-fails
# FC mapped: FC-21
# What it checks:
#   A config.toml missing a required section causes the reader to BLOCK/FAIL (not
#   silently default) -- the WARN-and-default degradation (FC-05/REQ-13) applies to
#   OPTIONAL sections only. Complements FC-05.
# Expected RED (pre-impl): core/config-reader.md's Failure Handling section currently
#   blocks on a missing `## Automation Config` heading / missing `### {Section}`
#   Markdown headings in CLAUDE.md -- not on a missing config.toml [section]. The
#   TOML-specific required-section-missing contract is absent today.
# Expected GREEN (post-impl): core/config-reader.md documents BLOCK/FAIL for a config.toml
#   missing any of the 5 required [section]s, using the standard Block Comment Template.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

REQS="spec/requirements.md"
reqs_content=""; [ -f "$REQS" ] && reqs_content="$(cat "$REQS")"
contains "$reqs_content" "REQ-20" || fail "requirements.md missing REQ-20 (required-section absence still FAILs)"
contains_i "$reqs_content" "BLOCK/FAIL" || fail "requirements.md does not state the BLOCK/FAIL response for required-section absence"

READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
[ -f "$READER" ] || fail "$READER not found"

contains "$reader_content" ".agent-flow/config.toml" || fail "FC-21: $READER Failure Handling does not target .agent-flow/config.toml"
contains "$reader_content" "[agent-flow]" || fail "FC-21: $READER does not use the standard Block Comment Template ([agent-flow] prefix)"
contains_i "$reader_content" "required" || fail "FC-21: $READER does not distinguish required-section absence from optional malformation"

# --- Behavioural: parse (strict, default) a config.toml missing [issue_tracker] entirely.
# Degradation is OPTIONAL-only, so a missing REQUIRED section must BLOCK (non-zero) with the
# standard [agent-flow] Block Comment Template naming the missing section. ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc21.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/config.toml" <<'EOF'
[source_control]
remote = "org/repo"
base_branch = "main"
branch_naming = "fix/{issue-id}-{description}"
EOF
if contains "$(cat "$TMP/config.toml")" "[issue_tracker]"; then
  fail "fixture sanity: [issue_tracker] must be absent to exercise the required-section-missing path"
fi

block_out="$(config_parse "$TMP/config.toml" 2>&1)"; block_rc=$?
[ "$block_rc" -ne 0 ] || fail "FC-21: config_parse returned 0 on a config missing the required [issue_tracker] section (must BLOCK, not silently default)"
contains "$block_out" "[agent-flow]" || fail "FC-21: BLOCK output missing the standard [agent-flow] Block Comment Template"
contains "$block_out" "issue_tracker" || fail "FC-21: BLOCK output does not name the missing [issue_tracker] section"

# Contrast with FC-05: a well-formed required set + a malformed OPTIONAL section must NOT block.
cat > "$TMP/ok.toml" <<'EOF'
[issue_tracker]
type = "github"
instance = "i"
project = "P"
bug_query = "q"
state_transitions = "a: b"
on_start_set = "x"
[source_control]
remote = "o/r"
base_branch = "main"
branch_naming = "f"
[pr_rules]
labels = "bug"
[pr_description_template]
template = "S"
[build_and_test]
build_command = "make"
test_command = "pytest"
[metrics]
output = garbage words here
EOF
config_parse "$TMP/ok.toml" >/dev/null 2>&1; ok_rc=$?
[ "$ok_rc" -eq 0 ] || fail "FC-21: a complete required set with only a malformed OPTIONAL section must NOT block (rc=$ok_rc) — degradation is optional-only"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-required-section-absence-fails -- missing required [issue_tracker] BLOCKs; optional malformation does not"
  exit 0
fi
exit 1
