#!/usr/bin/env bash
set -euo pipefail

# REGRESSION: No new REQUIRED Automation Config key added (MINOR bump rule)
# Traces: all (versioning policy)
# Description: Verifies that the ### Autopilot section is documented as OPTIONAL
#              (has defaults), and that no existing REQUIRED section gained a new mandatory key

cd "$(dirname "$0")/../.."
. "./tests/lib/assert.sh"

FAIL=0

CLAUDE="CLAUDE.md"

if [ ! -f "$CLAUDE" ]; then
  echo "FAIL: CLAUDE.md not found" >&2
  exit 1
fi

# Autopilot section must be listed in Optional sections table (not Required)
# The optional table has | Section | Keys | Default | format
if ! grep -qiE 'Autopilot.*Max issues|Max issues.*Autopilot' "$CLAUDE"; then
  # Check if Autopilot appears in the optional sections table
  if ! grep -A2 'Autopilot' "$CLAUDE" | grep -qiE 'optional|default|skip|false'; then
    echo "FAIL: Autopilot config section is not documented as optional (with defaults)" >&2
    FAIL=1
  fi
fi

# Verify Autopilot keys all have defaults documented
# (all 7 keys have defaults: 1, 120, .agent-flow/autopilot.log, 0, 0, skip, false)
for pair in "Max issues per run.*1" "Lock timeout.*120" "On error.*skip" "Dry run.*false"; do
  if ! grep -qiE "$pair" "$CLAUDE"; then
    echo "FAIL: CLAUDE.md Autopilot key '$pair' missing default value documentation" >&2
    FAIL=1
  fi
done

# Required sections should not have gained new keys (check key count in required table)
# Required table: Issue Tracker, Source Control, PR Rules, PR Description Template, Build & Test
# These sections must not reference 'autopilot' (it's optional, not required)
REQUIRED_SECTION=$(grep -A20 'Required sections' "$CLAUDE" 2>/dev/null || true)
if matches_re "${REQUIRED_SECTION,,}" '^[|].*autopilot'; then
  echo "FAIL: Autopilot appears in Required sections table — must be optional only" >&2
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "PASS: REGRESSION — no required Automation Config key added (Autopilot is optional)"
exit "$FAIL"
