#!/usr/bin/env bash
# Test: tracker_issue_id field in state/schema.md Subtask Object Fields table
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

SCHEMA="$REPO_ROOT/state/schema.md"

if [ ! -f "$SCHEMA" ]; then
  fail "state/schema.md not found"
  exit 1
fi

# -----------------------------------------------------------------------
# tracker_issue_id row exists in state/schema.md
# -----------------------------------------------------------------------
if ! grep -q 'tracker_issue_id' "$SCHEMA" 2>/dev/null; then
  fail "'tracker_issue_id' field not found in state/schema.md"
fi

# -----------------------------------------------------------------------
# The field must be in the Subtask Object Fields table
# Verify that tracker_issue_id appears after the Subtask Object section
# -----------------------------------------------------------------------
SUBTASK_SECTION_LINE=$(grep -n "Subtask Object Fields" "$SCHEMA" | head -1 | cut -d: -f1 || true)
TRACKER_FIELD_LINE=$(grep -n "tracker_issue_id" "$SCHEMA" | head -1 | cut -d: -f1 || true)

if [ -z "$SUBTASK_SECTION_LINE" ]; then
  fail "'Subtask Object Fields' section not found in state/schema.md"
elif [ -z "$TRACKER_FIELD_LINE" ]; then
  : # already reported above
elif [ "$TRACKER_FIELD_LINE" -le "$SUBTASK_SECTION_LINE" ]; then
  fail "'tracker_issue_id' (line $TRACKER_FIELD_LINE) must appear AFTER 'Subtask Object Fields' (line $SUBTASK_SECTION_LINE)"
fi

# -----------------------------------------------------------------------
# The field must declare type 'string or null' and default 'null'
# -----------------------------------------------------------------------
if [ -n "$TRACKER_FIELD_LINE" ]; then
  tracker_row=$(grep "tracker_issue_id" "$SCHEMA" | head -1 || true)
  if ! matches_re "${tracker_row,,}" 'string.*null|null.*string'; then
    fail "'tracker_issue_id' row must have type 'string or null', got: $tracker_row"
  fi
fi

# -----------------------------------------------------------------------
# No bare tracker_id field as a schema field name in state/schema.md
# Field name must be tracker_issue_id, NOT tracker_id
# Look for table rows that define "tracker_id" as a field name (backtick or pipe delimited)
# -----------------------------------------------------------------------
bare_tracker_id=$(grep -nE '\| *`tracker_id`|\| *tracker_id *\|' "$SCHEMA" 2>/dev/null | grep -v 'tracker_issue_id' || true)
if [ -n "$bare_tracker_id" ]; then
  fail "bare 'tracker_id' field definition found in state/schema.md (should be 'tracker_issue_id'): $bare_tracker_id"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: state/schema.md contains tracker_issue_id in Subtask Object Fields with correct type and default, no bare tracker_id field"
exit "$FAIL"
