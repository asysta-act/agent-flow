#!/usr/bin/env bash
# Test: check-setup-migrate-hint
# FC mapped: FC-17
# What it checks:
#   When a legacy `## Automation Config` table block is present in CLAUDE.md,
#   check-setup outputs a hint to run /onboard --migrate.
# Expected RED (pre-impl): skills/check-setup/SKILL.md does not mention /onboard
#   --migrate anywhere today.
# Expected GREEN (post-impl): SKILL.md documents the legacy-inline detection ->
#   /onboard --migrate hint.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SKILL="skills/check-setup/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
[ -f "$SKILL" ] || fail "$SKILL not found"

contains "$skill_content" "/onboard --migrate" || fail "FC-17: $SKILL does not hint at /onboard --migrate"
contains_i "$skill_content" "legacy" || fail "FC-17: $SKILL does not describe detecting a legacy inline config block"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup-migrate-hint -- /onboard --migrate hint documented for legacy inline config"
  exit 0
fi
exit 1
