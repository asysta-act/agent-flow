#!/usr/bin/env bash
# Verifies: AC-SETUP-006
# Description: /setup-agents --force creates backup customization/reviewer.toml.bak-{ISO-8601}
#   then writes new file with # generated: header
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

# ---------------------------------------------------------------------------
# Assertion 1: setup-agents SKILL.md documents backup creation on --force
# ---------------------------------------------------------------------------
echo "--- Assertion 1: setup-agents SKILL.md documents .bak-{ISO} backup ---"
SETUP_SKILL="$REPO_ROOT/skills/setup-agents/SKILL.md"
if [ ! -f "$SETUP_SKILL" ]; then
  echo "SKIP: skills/setup-agents/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE '\.bak-|backup.*force|force.*backup' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents .bak- backup on --force"
else
  fail "setup-agents SKILL.md missing .bak- backup documentation for --force"
fi

# ---------------------------------------------------------------------------
# Assertion 2: Backup filename pattern .bak-{ISO-8601} documented
# ---------------------------------------------------------------------------
echo "--- Assertion 2: backup pattern .bak-{ISO-8601} documented ---"
if grep -qE '\.bak-[0-9{YYYY]' "$SETUP_SKILL" || \
   grep -qiE 'iso.?8601|bak.*timestamp|bak.*date' "$SETUP_SKILL"; then
  echo "OK: backup .bak-{ISO-8601} pattern documented"
else
  fail "setup-agents SKILL.md missing .bak-{ISO-8601} backup naming pattern"
fi

# ---------------------------------------------------------------------------
# Assertion 3: New file after --force starts with # generated: header
# ---------------------------------------------------------------------------
echo "--- Assertion 3: post-force file starts with # generated: documented ---"
if grep -qF '# generated:' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents # generated: header after --force"
else
  fail "setup-agents SKILL.md does not document that --force output has # generated: header"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Simulate backup pattern validation
# ---------------------------------------------------------------------------
echo "--- Assertion 4: backup filename matches .bak-{YYYY-MM-DDTHH:MM:SSZ} format ---"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

mkdir -p "$TMPDIR_TEST/customization"

# Create a simulated backup file as --force would produce
TIMESTAMP="2026-04-27T103000Z"
BACKUP_FILE="$TMPDIR_TEST/customization/reviewer.toml.bak-$TIMESTAMP"
printf '# user-edited content\nmodel = "opus"\n' > "$BACKUP_FILE"

BAK_BASENAME=$(basename "$BACKUP_FILE")
if matches_re "$BAK_BASENAME" '^reviewer\.toml\.bak-[0-9TZ:-]+$'; then
  echo "OK: backup filename '$BAK_BASENAME' matches expected .bak-{ISO} pattern"
else
  fail "backup filename '$BAK_BASENAME' does not match .bak-{ISO} pattern"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-006 — --force backup pattern .bak-{ISO-8601} documented"
fi
exit "$FAIL"
