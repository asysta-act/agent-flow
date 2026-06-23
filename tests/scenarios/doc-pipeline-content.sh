#!/usr/bin/env bash
# Verifies: AC-DOC-009
# Description: docs/reference/pipeline.md has all required section headings + code block
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

PIPELINE_DOC="$REPO_ROOT/docs/reference/pipeline.md"
if [ ! -f "$PIPELINE_DOC" ]; then
  fail "docs/reference/pipeline.md not found"
  exit 1
fi

# Required section headings (case-insensitive ## H2 match per AC-DOC-009)
REQUIRED_HEADINGS=(
  "Entry SKILL.md responsibilities"
  "Step file responsibilities"
  "Step override resolution"
  "Mode flag dispatch"
  "Named-phase Skip stages syntax"
)

echo "--- Checking required headings in pipeline.md ---"
for heading in "${REQUIRED_HEADINGS[@]}"; do
  if grep -qiE "^## .*$heading" "$PIPELINE_DOC"; then
    echo "OK: heading '$heading' found"
  else
    fail "pipeline.md missing heading: '$heading'"
  fi
done

# ---------------------------------------------------------------------------
# Assertion: at least one fenced code block with step file path example
# ---------------------------------------------------------------------------
echo "--- Assertion: code block with step file path example ---"
if grep -qE '\`\`\`' "$PIPELINE_DOC"; then
  if grep -qE 'skills/\{?skill\}?/steps|skills/fix-bugs/steps|customization/steps' "$PIPELINE_DOC"; then
    echo "OK: pipeline.md has code block with step file path example"
  else
    fail "pipeline.md has code blocks but none show step file path example"
  fi
else
  fail "pipeline.md has no fenced code blocks (required by AC-DOC-009)"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-009 — docs/reference/pipeline.md has all required sections + code block"
fi
exit "$FAIL"
