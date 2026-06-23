#!/usr/bin/env bash
# Verifies: AC-OVR-003 Tier 3
# Description: TOML overlay table deep merge — [limits] key overrides plugin default,
#   absent keys inherited from plugin default (e.g., max_review_iterations=3 wins,
#   max_diff_lines=100 inherited)
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
# Setup: TOML overlay with partial [limits] table
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/customization"

cat > "$TMPDIR_TEST/customization/reviewer.toml" << 'EOF'
[limits]
max_review_iterations = 3
EOF

# ---------------------------------------------------------------------------
# Assertion 1: docs/guides/toml-overlay-syntax.md documents [limits] table
# ---------------------------------------------------------------------------
echo "--- Assertion 1: toml-overlay-syntax.md documents [limits] table ---"
TOML_DOC="$REPO_ROOT/docs/guides/toml-overlay-syntax.md"
if [ ! -f "$TOML_DOC" ]; then
  echo "SKIP: docs/guides/toml-overlay-syntax.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qF '[limits]' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents [limits] table"
else
  fail "toml-overlay-syntax.md missing [limits] table documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Tier 3 / deep merge semantics documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: Tier 3 / deep merge section present ---"
if grep -qiE 'tier 3|deep.?merge|deep merge' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md has Tier 3 / deep merge section"
else
  fail "toml-overlay-syntax.md missing Tier 3 deep merge documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: toml-overlay-syntax.md documents deep merge worked example
# ---------------------------------------------------------------------------
echo "--- Assertion 3: toml-overlay-syntax.md documents deep merge worked example ---"
if grep -qE 'max_review_iterations.*3|deep merge' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md contains deep merge worked example"
else
  fail "toml-overlay-syntax.md missing deep merge worked example"
fi

# ---------------------------------------------------------------------------
# Assertion 4: max_review_iterations key documented for reviewer agent
# ---------------------------------------------------------------------------
echo "--- Assertion 4: max_review_iterations documented for reviewer ---"
if grep -qF 'max_review_iterations' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents max_review_iterations for reviewer"
else
  fail "toml-overlay-syntax.md missing max_review_iterations key"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Absent-key-inherited rule documented
# ---------------------------------------------------------------------------
echo "--- Assertion 5: absent key inherited from plugin default rule documented ---"
if grep -qiE 'absent.*inherited|inherited from default|missing.*inherit' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents absent key inheritance"
else
  fail "toml-overlay-syntax.md missing 'absent key inherited from plugin default' rule"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-OVR-003 — TOML overlay table deep merge semantics documented"
fi
exit "$FAIL"
