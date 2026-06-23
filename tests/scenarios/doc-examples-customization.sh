#!/usr/bin/env bash
# Verifies: AC-DOC-011
# Description: examples/customization/ exists with >= 4 required example files
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

CUSTOM_EXAMPLES_DIR="$REPO_ROOT/examples/customization"

# ---------------------------------------------------------------------------
# Assertion 1: directory exists
# ---------------------------------------------------------------------------
echo "--- Assertion 1: examples/customization/ directory exists ---"
if [ -d "$CUSTOM_EXAMPLES_DIR" ]; then
  echo "OK: examples/customization/ directory exists"
else
  fail "examples/customization/ directory missing"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Required 4 example files present
# ---------------------------------------------------------------------------
echo "--- Assertion 2: required 4 example files present ---"
REQUIRED_FILES=(
  "reviewer-strict-security.toml"
  "fixer-no-tests.toml"
  "analyst-monorepo.toml"
  "README.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$CUSTOM_EXAMPLES_DIR/$f" ]; then
    echo "OK: examples/customization/$f exists"
  else
    fail "examples/customization/$f missing"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 3: TOML files have # generated: header or valid TOML content
# ---------------------------------------------------------------------------
echo "--- Assertion 3: TOML example files have valid structure ---"
for toml_file in reviewer-strict-security.toml fixer-no-tests.toml analyst-monorepo.toml; do
  FILE_PATH="$CUSTOM_EXAMPLES_DIR/$toml_file"
  [ -f "$FILE_PATH" ] || continue

  if grep -qE '^\[\[|^model\s*=|^style\s*=|^\[\[process_additions\]\]|^\[limits\]' "$FILE_PATH"; then
    echo "OK: $toml_file has valid TOML overlay structure"
  else
    fail "$toml_file missing valid TOML overlay structure"
  fi
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-DOC-011 — examples/customization/ has all 4 required example files"
fi
exit "$FAIL"
