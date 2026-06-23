#!/bin/bash
# PURPOSE: Assert CLAUDE.md Versioning Policy table has been amended to include the new clause
#          for mandatory structured contract sections in agent definition files.
#          Also asserts the verbatim clarification paragraph was appended (AC-H-060, AC-H-061).
# AC-H-N covered: AC-H-060, AC-H-061
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (CLAUDE.md has both the new MAJOR row text and clarification paragraph)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
  fail "CLAUDE.md not found at $CLAUDE_MD"
  exit 1
fi

# AC-H-060: MAJOR row text contains new clause
if ! grep -qF 'mandatory new structured contract section in agent definition files that prior-version agents would fail validation against' "$CLAUDE_MD"; then
  fail "CLAUDE.md Versioning Policy MAJOR row missing new clause 'mandatory new structured contract section...'"
  # Mutation catch: omitting the new MAJOR clause text fails here
fi

# AC-H-061 assertion 1: clarification paragraph opener
if ! grep -qF 'Adding new static declaration sections to agent definition files' "$CLAUDE_MD"; then
  fail "CLAUDE.md missing Versioning Policy clarification paragraph opener ('Adding new static declaration sections...')"
  # Mutation catch: deleting the clarification paragraph fails here
fi

# AC-H-061 assertion 2: key phrase from clarification paragraph
if ! grep -qF 'structure-blind and is not "external tooling that parses" agent body sections' "$CLAUDE_MD"; then
  fail "CLAUDE.md missing clarification paragraph phrase 'structure-blind and is not \"external tooling that parses\" agent body sections'"
fi

# Additional: assert the versioning policy section exists at all (sanity check)
if ! grep -qE '^## Versioning Policy$' "$CLAUDE_MD"; then
  fail "CLAUDE.md missing '## Versioning Policy' section"
fi

# Negative assertion: the old MAJOR row text without the new clause should not be the only occurrence
# (old text ends at "...that Agent Overrides or external tooling may parse)" without the new OR clause)
# We can't easily assert the OLD text is gone since the new text is appended, but we CAN assert the new text IS there (done above)

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-060, AC-H-061 — CLAUDE.md Versioning Policy has new MAJOR clause and clarification paragraph"
fi
exit "$FAIL"
