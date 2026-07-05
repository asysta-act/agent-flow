#!/usr/bin/env bash
# Test: claude-md-pointer-only
# FC mapped: FC-03
# What it checks:
#   In tests/mock-project/CLAUDE.md (the fixture), the `## Automation Config` section
#   contains a pointer to .agent-flow/config.toml and NO `| Key | Value |` table rows.
# Expected RED (pre-impl): tests/mock-project/CLAUDE.md still contains the full inline
#   Markdown tables (Issue Tracker, Source Control, etc.) under `## Automation Config` --
#   both assertions fail against the CURRENT fixture.
# Expected GREEN (post-impl): the fixture's `## Automation Config` section is a 1-2 line
#   pointer with zero table rows; the real config lives in
#   tests/mock-project/.agent-flow/config.toml.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

FIXTURE="tests/mock-project/CLAUDE.md"
[ -f "$FIXTURE" ] || fail "$FIXTURE not found"

section=""
if [ -f "$FIXTURE" ]; then
  section="$(awk '/^## Automation Config[[:space:]]*$/{f=1;next} /^## /&&f{exit} f' "$FIXTURE")"
fi

contains "$section" ".agent-flow/config.toml" || fail "FC-03: tests/mock-project/CLAUDE.md's Automation Config section does not point to .agent-flow/config.toml"

table_row_found=0
if [ -n "$section" ]; then
  while IFS= read -r line; do
    if matches_re "$line" '^\|.*\|.*\|'; then
      table_row_found=1
    fi
  done <<< "$section"
fi
[ "$table_row_found" -eq 0 ] || fail "FC-03: tests/mock-project/CLAUDE.md's Automation Config section still contains '| Key | Value |' table rows"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: claude-md-pointer-only -- mock CLAUDE.md Automation Config section is pointer-only, no table rows"
  exit 0
fi
exit 1
