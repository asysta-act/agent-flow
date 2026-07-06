#!/usr/bin/env bash
# Test: toml-required-sections-present
# FC mapped: FC-07
# What it checks:
#   The migration map covers each of the 5 required sections -- Issue Tracker, Source
#   Control, PR Rules, PR Description Template, Build & Test -- and the mock config.toml
#   fixture contains the corresponding [section] header for each.
# Expected RED (pre-impl): tests/mock-project/.agent-flow/config.toml does not exist yet
#   (the real fixture; a staging draft lives at
#   .forge/phase-5-tdd/tests/fixtures/mock-project-config.toml for this phase only).
# Expected GREEN (post-impl): tests/mock-project/.agent-flow/config.toml exists with all
#   5 required [section] headers.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

REQUIRED_NAMES=("Issue Tracker" "Source Control" "PR Rules" "PR Description Template" "Build & Test")
REQUIRED_TABLES=("[issue_tracker]" "[source_control]" "[pr_rules]" "[pr_description_template]" "[build_and_test]")

for name in "${REQUIRED_NAMES[@]}"; do
  contains "$design_content" "$name" || fail "design.md does not name the required section '$name'"
done

REAL_FIXTURE="tests/mock-project/.agent-flow/config.toml"
if [ ! -f "$REAL_FIXTURE" ]; then
  fail "FC-07: $REAL_FIXTURE does not exist yet (required-section [table] headers cannot be verified) -- create it in Phase 7"
else
  fixture_content="$(cat "$REAL_FIXTURE")"
  for table in "${REQUIRED_TABLES[@]}"; do
    contains "$fixture_content" "$table" || fail "FC-07: $REAL_FIXTURE missing required table header $table"
  done
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-required-sections-present -- all 5 required sections named in design.md and present as [table]s in the fixture"
  exit 0
fi
exit 1
