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

# --- Behavioural fixture: config.toml missing [issue_tracker] entirely ---
MISSING_REQUIRED_FIXTURE='[source_control]
remote = "org/repo"
base_branch = "main"
branch_naming = "fix/{issue-id}-{description}"
'
if contains "$MISSING_REQUIRED_FIXTURE" "[issue_tracker]"; then
  fail "fixture sanity: [issue_tracker] must be absent to exercise the required-section-missing path"
fi

# TODO(phase-7): once a real reader exists, parse the fixture above and assert a non-zero
# exit / BLOCK outcome with the [agent-flow] Block Comment Template naming the missing
# [issue_tracker] section -- distinct from the WARN+default path exercised by FC-05.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-required-section-absence-fails -- required-section BLOCK/FAIL contract documented, distinct from optional WARN+default"
  exit 0
fi
exit 1
