#!/bin/bash
# Covers: AC-20 (skills/check-setup/SKILL.md does not reference /migrate-config)
# FC mapped: FC-18 [DEDICATED] (STRENGTHENED for the .agent-flow/config.toml migration,
# per design.md section 5.3 -- "already-present forward-looking scenarios to keep
# green": no /migrate-config command exists anywhere; migration lives exclusively under
# /onboard --migrate). Preserved in spirit (still asserts the absence originally covered
# by AC-20), plus:
#   (a) broadened the pattern from the narrow "run /migrate-config" phrase to FC-18's
#       full `/(agent-flow:)?migrate-config` form, so ANY mention (not just a "run ..."
#       instruction) is caught; and
#   (b) asserts no skills/migrate-config/ directory exists at all (FC-18's other clause).
# This scenario is expected to stay GREEN throughout the migration (FC-18 requires an
# absence that already holds and must continue to hold -- unlike the other reworked
# scenarios, there is no red phase here).
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/assert.sh
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: v9-5-check-setup-no-migrate-config — $1"; FAIL=1; }

FILE="$REPO_ROOT/skills/check-setup/SKILL.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: v9-5-check-setup-no-migrate-config — skills/check-setup/SKILL.md not found"
  exit 1
fi

file_content="$(cat "$FILE")"

if matches_re "$file_content" '/(agent-flow:)?migrate-config'; then
  fail "skills/check-setup/SKILL.md still references /migrate-config or /agent-flow:migrate-config (FC-18)"
else
  echo "PASS: /migrate-config reference absent from check-setup SKILL.md"
fi

if [ -d "$REPO_ROOT/skills/migrate-config" ]; then
  fail "skills/migrate-config/ directory exists -- FC-18 requires migration to live exclusively under /onboard --migrate"
else
  echo "PASS: no skills/migrate-config/ directory exists"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v9-5-check-setup-no-migrate-config — no /migrate-config surface anywhere"
  exit 0
fi
exit 1
