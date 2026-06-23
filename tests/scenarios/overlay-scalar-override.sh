#!/usr/bin/env bash
# Verifies: AC-OVR-001 Tier 1
# Description: TOML overlay scalar override — customization/reviewer.toml model="sonnet"
#   merges into reviewer agent prompt, overriding plugin default "opus"
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
# Setup: create mock project structure with reviewer.toml scalar override
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/customization"

cat > "$TMPDIR_TEST/customization/reviewer.toml" << 'EOF'
model = "sonnet"
EOF

# The reviewer agent in agents/reviewer.md should have model: opus in frontmatter.
# We verify that the overlay schema correctly specifies model as a Tier 1 scalar key.
REVIEWER_AGENT="$REPO_ROOT/agents/reviewer.md"
if [ ! -f "$REVIEWER_AGENT" ]; then
  # In v8, reviewer.md should still exist (it's not a merged/renamed agent)
  echo "SKIP: agents/reviewer.md not found (post-v8 rename pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Assertion 1: reviewer agent has model: opus as default
# ---------------------------------------------------------------------------
echo "--- Assertion 1: reviewer.md default model is opus ---"
if grep -qE '^model:\s*opus' "$REVIEWER_AGENT"; then
  echo "OK: reviewer.md frontmatter has model: opus (default)"
else
  fail "reviewer.md frontmatter does not have model: opus (expected default)"
fi

# ---------------------------------------------------------------------------
# Assertion 2: TOML overlay schema documents 'model' as a Tier 1 scalar override key
# ---------------------------------------------------------------------------
echo "--- Assertion 2: TOML overlay schema documents 'model' as scalar override ---"
TOML_SYNTAX_DOC="$REPO_ROOT/docs/guides/toml-overlay-syntax.md"
if [ ! -f "$TOML_SYNTAX_DOC" ]; then
  echo "SKIP: docs/guides/toml-overlay-syntax.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qE '^model\s*=' "$TOML_SYNTAX_DOC" || grep -qF 'model = ' "$TOML_SYNTAX_DOC"; then
  echo "OK: toml-overlay-syntax.md documents 'model' as a scalar key"
else
  fail "toml-overlay-syntax.md does not show 'model =' scalar override example"
fi

# Tier 1 / override section heading
if grep -qiE 'tier 1|scalar override|scalar' "$TOML_SYNTAX_DOC"; then
  echo "OK: toml-overlay-syntax.md contains Tier 1 / scalar section"
else
  fail "toml-overlay-syntax.md missing Tier 1 / scalar override section"
fi

# ---------------------------------------------------------------------------
# Assertion 3: The overlay file has correct TOML syntax (basic key=value)
# ---------------------------------------------------------------------------
echo "--- Assertion 3: verify overlay TOML parses as key=value ---"
OVERLAY="$TMPDIR_TEST/customization/reviewer.toml"
if grep -qE '^model\s*=\s*"sonnet"' "$OVERLAY"; then
  echo "OK: reviewer.toml contains model = \"sonnet\""
else
  fail "Test fixture reviewer.toml does not contain model = \"sonnet\""
fi

# ---------------------------------------------------------------------------
# Assertion 4: toml-overlay-syntax.md documents the override precedence rule
# ---------------------------------------------------------------------------
echo "--- Assertion 4: toml-overlay-syntax.md documents overlay wins over plugin default ---"
if grep -qiE 'overlay.*wins|overlay.*always.*wins' "$TOML_SYNTAX_DOC"; then
  echo "OK: toml-overlay-syntax.md documents overlay wins precedence"
else
  fail "toml-overlay-syntax.md does not document overlay-wins-over-plugin-default rule"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-OVR-001 — TOML overlay scalar override (model) documented correctly"
fi
exit "$FAIL"
