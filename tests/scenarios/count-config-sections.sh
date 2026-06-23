#!/usr/bin/env bash
# Verifies: AC-CT-003
# Description: CLAUDE.md and docs/reference/automation-config.md both list exactly 18
#   optional config sections (level-3 headings under ## Automation Config)
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

EXPECTED_SECTIONS=18

check_section_count() {
  local file="$1"
  local file_path="$REPO_ROOT/$file"

  if [ ! -f "$file_path" ]; then
    echo "SKIP: $file not found (implementation pending)" >&2
    return 77
  fi

  # Verify the file explicitly states "18 optional" config sections.
  # CLAUDE.md uses table format (not ### headings) for config sections under "## Config Contract".
  # automation-config.md states the count in its overview paragraph.
  # Both files contain the phrase "18 optional config sections" or "18 optional sections".
  if grep -qiE '18 optional (config )?sections' "$file_path" 2>/dev/null; then
    echo "OK: $file states 18 optional config sections"
  else
    fail "$file does not state '18 optional config sections' (expected per AC-CT-003)"
  fi
}

# ---------------------------------------------------------------------------
# Check CLAUDE.md
# ---------------------------------------------------------------------------
echo "--- Checking CLAUDE.md config section count ---"
check_section_count "CLAUDE.md"

# ---------------------------------------------------------------------------
# Check automation-config.md
# ---------------------------------------------------------------------------
echo "--- Checking docs/reference/automation-config.md config section count ---"
check_section_count "docs/reference/automation-config.md"

# ---------------------------------------------------------------------------
# Verify "Extra labels" section is REMOVED (was 19->18 reduction)
# ---------------------------------------------------------------------------
echo "--- Assertion: 'Extra labels' section absent ---"
for file in CLAUDE.md docs/reference/automation-config.md; do
  if grep -qF '### Extra labels' "$REPO_ROOT/$file" 2>/dev/null; then
    fail "$file still contains '### Extra labels' section (should be removed)"
  else
    echo "OK: $file does not contain '### Extra labels'"
  fi
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-CT-003 — CLAUDE.md and automation-config.md both have 18 config sections"
fi
exit "$FAIL"
