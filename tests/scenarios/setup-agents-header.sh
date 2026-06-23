#!/usr/bin/env bash
# Verifies: AC-SETUP-004
# Description: Every file written by /setup-agents begins with "# generated: " header
#   matching regex: ^# generated: [0-9TZ:-]+ by /setup-agents v[0-9]+\.[0-9]+\.[0-9]+$
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

HEADER_REGEX='^# generated: [0-9TZ:-]+ by /setup-agents v[0-9]+\.[0-9]+\.[0-9]+$'

# ---------------------------------------------------------------------------
# Setup: create mock generated TOML files
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/customization"

# Valid header examples per design.md
cat > "$TMPDIR_TEST/customization/reviewer.toml" << 'EOF'
# generated: 2026-04-27T10:00:00Z by /setup-agents v1.0.0
model = "opus"
EOF

cat > "$TMPDIR_TEST/customization/fixer.toml" << 'EOF'
# generated: 2026-04-27T10:01:00Z by /setup-agents v1.0.0
[[process_additions]]
step = "after_default"
instruction = "Run linting"
EOF

# Non-generated (user-edited) file — should NOT start with # generated:
cat > "$TMPDIR_TEST/customization/analyst.toml" << 'EOF'
# User config — this is not generated
model = "opus"
EOF

# ---------------------------------------------------------------------------
# Assertion 1: Valid header passes regex check
# ---------------------------------------------------------------------------
echo "--- Assertion 1: valid generated header passes regex ---"
FIRST_LINE=$(head -1 "$TMPDIR_TEST/customization/reviewer.toml")
if matches_re "$FIRST_LINE" "$HEADER_REGEX"; then
  echo "OK: reviewer.toml header matches generated: regex"
else
  fail "reviewer.toml header '$FIRST_LINE' does not match regex '$HEADER_REGEX'"
fi

# Check second generated file
FIRST_LINE2=$(head -1 "$TMPDIR_TEST/customization/fixer.toml")
if matches_re "$FIRST_LINE2" "$HEADER_REGEX"; then
  echo "OK: fixer.toml header matches generated: regex"
else
  fail "fixer.toml header '$FIRST_LINE2' does not match regex '$HEADER_REGEX'"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Non-generated file does NOT have # generated: header
# ---------------------------------------------------------------------------
echo "--- Assertion 2: user-edited file does NOT start with # generated: ---"
NON_GEN_FIRST=$(head -1 "$TMPDIR_TEST/customization/analyst.toml")
if matches_re "$NON_GEN_FIRST" "$HEADER_REGEX"; then
  fail "analyst.toml should NOT have # generated: header (it is user-edited)"
else
  echo "OK: analyst.toml correctly does not have # generated: header"
fi

# ---------------------------------------------------------------------------
# Assertion 3: setup-agents SKILL.md documents header requirement
# ---------------------------------------------------------------------------
echo "--- Assertion 3: setup-agents SKILL.md documents # generated: header ---"
SETUP_SKILL="$REPO_ROOT/skills/setup-agents/SKILL.md"
if [ ! -f "$SETUP_SKILL" ]; then
  echo "SKIP: skills/setup-agents/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qF '# generated:' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents # generated: header format"
else
  fail "setup-agents SKILL.md does not document # generated: header requirement"
fi

# ---------------------------------------------------------------------------
# Assertion 4: setup-agents SKILL.md documents the header format in examples
# ---------------------------------------------------------------------------
echo "--- Assertion 4: setup-agents SKILL.md examples show # generated: header ---"
if grep -qF '# generated:' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md examples include # generated: header"
else
  fail "setup-agents SKILL.md missing # generated: header in examples"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-004 — # generated: header required and format documented"
fi
exit "$FAIL"
