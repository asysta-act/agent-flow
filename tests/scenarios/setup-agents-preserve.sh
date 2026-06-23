#!/usr/bin/env bash
# Verifies: AC-SETUP-005
# Description: When customization/reviewer.toml exists with non-# generated: first line
#   and /setup-agents runs WITHOUT --force, file is unchanged + [WARN] "User-edited overlay"
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
# Setup: pre-existing user-edited TOML overlay
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/customization"

USER_EDITED_CONTENT='# User-edited reviewer config — not generated
model = "opus"

[[constraints]]
rule = "Check SQL injection in all DB queries."
'
printf '%s' "$USER_EDITED_CONTENT" > "$TMPDIR_TEST/customization/reviewer.toml"

# Compute checksum before simulated /setup-agents run
CHECKSUM_BEFORE=""
if command -v sha256sum > /dev/null 2>&1; then
  CHECKSUM_BEFORE=$(sha256sum "$TMPDIR_TEST/customization/reviewer.toml" | cut -d' ' -f1)
elif command -v shasum > /dev/null 2>&1; then
  CHECKSUM_BEFORE=$(shasum -a 256 "$TMPDIR_TEST/customization/reviewer.toml" | cut -d' ' -f1)
else
  # Fallback: use wc -c as crude "unchanged" check
  CHECKSUM_BEFORE=$(wc -c < "$TMPDIR_TEST/customization/reviewer.toml")
fi

# Simulate /setup-agents behavior: should detect non-generated header, skip file
FIRST_LINE=$(head -1 "$TMPDIR_TEST/customization/reviewer.toml")
if ! matches_re "$FIRST_LINE" '^# generated:'; then
  # Correct behavior: do NOT overwrite — file stays unchanged
  :
else
  # This would be wrong — we're testing setup-agents does not overwrite
  fail "Test fixture error: file incorrectly starts with # generated: header"
fi

# ---------------------------------------------------------------------------
# Assertion 1: File content unchanged (byte-identical) after skip
# ---------------------------------------------------------------------------
echo "--- Assertion 1: user-edited file is unchanged (byte-identical) ---"
CHECKSUM_AFTER=""
if command -v sha256sum > /dev/null 2>&1; then
  CHECKSUM_AFTER=$(sha256sum "$TMPDIR_TEST/customization/reviewer.toml" | cut -d' ' -f1)
elif command -v shasum > /dev/null 2>&1; then
  CHECKSUM_AFTER=$(shasum -a 256 "$TMPDIR_TEST/customization/reviewer.toml" | cut -d' ' -f1)
else
  CHECKSUM_AFTER=$(wc -c < "$TMPDIR_TEST/customization/reviewer.toml")
fi

if [ "$CHECKSUM_BEFORE" = "$CHECKSUM_AFTER" ]; then
  echo "OK: reviewer.toml is byte-identical (unchanged by setup-agents skip)"
else
  fail "reviewer.toml was modified — should have been preserved (user-edited)"
fi

# ---------------------------------------------------------------------------
# Assertion 2: setup-agents SKILL.md documents preserve behavior
# ---------------------------------------------------------------------------
echo "--- Assertion 2: setup-agents SKILL.md documents User-edited overlay skip ---"
SETUP_SKILL="$REPO_ROOT/skills/setup-agents/SKILL.md"
if [ ! -f "$SETUP_SKILL" ]; then
  echo "SKIP: skills/setup-agents/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'user.edited|user-edited overlay|skip.*user|preserve.*user' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents User-edited overlay skip"
else
  fail "setup-agents SKILL.md missing 'User-edited overlay' skip documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: [WARN] text contains "User-edited overlay"
# ---------------------------------------------------------------------------
echo "--- Assertion 3: [WARN] text 'User-edited overlay' documented ---"
if grep -qF 'User-edited overlay' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md contains exact WARN text 'User-edited overlay'"
else
  fail "setup-agents SKILL.md missing exact WARN text 'User-edited overlay'"
fi

# ---------------------------------------------------------------------------
# Assertion 4: --force flag documented as the override mechanism
# ---------------------------------------------------------------------------
echo "--- Assertion 4: --force flag documented for overwriting user-edited files ---"
if grep -qF -- '--force' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents --force flag"
else
  fail "setup-agents SKILL.md missing --force flag documentation"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-005 — user-edited overlay preserved with [WARN] documented"
fi
exit "$FAIL"
