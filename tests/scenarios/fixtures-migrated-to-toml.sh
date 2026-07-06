#!/usr/bin/env bash
# Test: fixtures-migrated-to-toml
# FC mapped: FC-24
# What it checks:
#   tests/mock-project/.agent-flow/config.toml exists, and
#   tests/harness/fixtures/automation-config.md is either replaced by a .toml form or
#   contains TOML [section] content rather than `| Key | Value |` tables.
# Expected RED (pre-impl): neither the mock-project .agent-flow/config.toml exists nor
#   has tests/harness/fixtures/automation-config.md been converted -- both fixtures
#   still carry inline Markdown tables today. (Staging drafts of both exist for THIS
#   phase only at .forge/phase-5-tdd/tests/fixtures/ -- not the real fixtures.)
# Expected GREEN (post-impl): both real fixtures exist in TOML form.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

MOCK_TOML="tests/mock-project/.agent-flow/config.toml"
[ -f "$MOCK_TOML" ] || fail "FC-24: $MOCK_TOML does not exist yet -- create it in Phase 7"

HARNESS_TOML="tests/harness/fixtures/automation-config.toml"
HARNESS_MD="tests/harness/fixtures/automation-config.md"

if [ -f "$HARNESS_TOML" ]; then
  echo "OK: $HARNESS_TOML exists (replacement form present)"
elif [ -f "$HARNESS_MD" ]; then
  md_content="$(cat "$HARNESS_MD")"
  if matches_re "$md_content" '^\|.*\|.*\|'; then
    fail "FC-24: $HARNESS_MD still contains '| Key | Value |' table rows and no .toml replacement exists"
  else
    contains "$md_content" "[section]" || contains_i "$md_content" "toml" \
      || fail "FC-24: $HARNESS_MD has no table rows but also does not look like TOML [section] content"
  fi
else
  fail "FC-24: neither $HARNESS_TOML nor $HARNESS_MD exists -- the harness fixture is missing entirely"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: fixtures-migrated-to-toml -- both fixtures migrated to TOML form"
  exit 0
fi
exit 1
