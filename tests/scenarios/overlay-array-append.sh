#!/usr/bin/env bash
# Verifies: AC-OVR-002 Tier 2
# Description: TOML overlay array append — [[process_additions]] entries appended after plugin defaults
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
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# ---------------------------------------------------------------------------
# Setup: TOML overlay with [[process_additions]]
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/customization"

cat > "$TMPDIR_TEST/customization/reviewer.toml" << 'EOF'
[[process_additions]]
step = "after_default"
instruction = "Check SQLi"
EOF

# ---------------------------------------------------------------------------
# Assertion 1: TOML overlay syntax doc documents [[process_additions]] array append
# ---------------------------------------------------------------------------
echo "--- Assertion 1: toml-overlay-syntax.md documents [[process_additions]] ---"
TOML_DOC="$REPO_ROOT/docs/guides/toml-overlay-syntax.md"
if [ ! -f "$TOML_DOC" ]; then
  echo "SKIP: docs/guides/toml-overlay-syntax.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qF '[[process_additions]]' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents [[process_additions]] array of tables"
else
  fail "toml-overlay-syntax.md missing [[process_additions]] documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Tier 2 / array append semantics documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: Tier 2 / array append section present ---"
if grep -qiE 'tier 2|array.*append|append.*semantics|appended' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md has Tier 2 / array append section"
else
  fail "toml-overlay-syntax.md missing Tier 2 array append documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: 'step' and 'instruction' keys documented
# ---------------------------------------------------------------------------
echo "--- Assertion 3: 'step' and 'instruction' keys documented in syntax doc ---"
if grep -qF '"step"' "$TOML_DOC" || grep -qE '^step\s*=' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents 'step' key"
else
  fail "toml-overlay-syntax.md missing 'step' key documentation"
fi

if grep -qF '"instruction"' "$TOML_DOC" || grep -qE '^instruction\s*=' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents 'instruction' key"
else
  fail "toml-overlay-syntax.md missing 'instruction' key documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Ordering — plugin defaults appear BEFORE project additions
# ---------------------------------------------------------------------------
echo "--- Assertion 4: ordering — plugin defaults appear before project additions ---"
if grep -qiE 'plugin.default.*before|appear.*before|appended after' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents append ordering (defaults first)"
else
  fail "toml-overlay-syntax.md does not specify append ordering (plugin defaults before project additions)"
fi

# ---------------------------------------------------------------------------
# Assertion 5: [[constraints]] also documented as array append
# ---------------------------------------------------------------------------
echo "--- Assertion 5: [[constraints]] documented as array append ---"
if grep -qF '[[constraints]]' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents [[constraints]] append"
else
  fail "toml-overlay-syntax.md missing [[constraints]] documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-OVR-002 — TOML overlay array append semantics documented"
fi
exit "$FAIL"
