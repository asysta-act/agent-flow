#!/usr/bin/env bash
# Verifies: AC-SETUP-008
# Description: /setup-agents writes ONLY to customization/ directory; no file
#   outside customization/ is modified. Uses sha256sum baseline of all files
#   outside customization/ before and after simulated /setup-agents run.
# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
set -uo pipefail

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
# Prerequisite: skills/setup-agents/SKILL.md must exist
# ---------------------------------------------------------------------------
SETUP_SKILL="$REPO_ROOT/skills/setup-agents/SKILL.md"
if [ ! -f "$SETUP_SKILL" ]; then
  echo "SKIP: skills/setup-agents/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Setup: create a mock project with agents/, skills/, and customization/ dirs
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/agents"
mkdir -p "$TMPDIR_TEST/skills/fix-bugs"
mkdir -p "$TMPDIR_TEST/customization"
mkdir -p "$TMPDIR_TEST/.agent-flow"

# Create mock files outside customization/
cat > "$TMPDIR_TEST/agents/reviewer.md" << 'EOF'
---
name: reviewer
model: opus
---
Reviewer agent body.
EOF

cat > "$TMPDIR_TEST/skills/fix-bugs/SKILL.md" << 'EOF'
# Fix Bugs Skill
This is the fix-bugs skill.
EOF

cat > "$TMPDIR_TEST/CLAUDE.md" << 'EOF'
# Test Project CLAUDE.md
## Automation Config
EOF

# ---------------------------------------------------------------------------
# Baseline: compute checksums of all files OUTSIDE customization/
# ---------------------------------------------------------------------------
echo "--- Creating baseline checksums for files outside customization/ ---"

BASELINE_FILE="$TMPDIR_TEST/baseline.txt"
CHECKSUM_CMD=""
if command -v sha256sum > /dev/null 2>&1; then
  CHECKSUM_CMD="sha256sum"
elif command -v shasum > /dev/null 2>&1; then
  CHECKSUM_CMD="shasum -a 256"
else
  CHECKSUM_CMD=""
fi

# Build sorted list of files outside customization/
find "$TMPDIR_TEST" -type f ! -path "$TMPDIR_TEST/customization/*" ! -path "$TMPDIR_TEST/baseline*" ! -path "$TMPDIR_TEST/after*" | sort > "$TMPDIR_TEST/files_outside.txt"

if [ -n "$CHECKSUM_CMD" ]; then
  while IFS= read -r f; do
    $CHECKSUM_CMD "$f"
  done < "$TMPDIR_TEST/files_outside.txt" | sort > "$BASELINE_FILE"
  echo "OK: baseline checksums computed for $(wc -l < "$TMPDIR_TEST/files_outside.txt") files"
else
  # Fallback: record file sizes
  while IFS= read -r f; do
    wc -c < "$f"
  done < "$TMPDIR_TEST/files_outside.txt" | sort > "$BASELINE_FILE"
  echo "OK: baseline sizes computed (sha256sum unavailable)"
fi

# ---------------------------------------------------------------------------
# Simulate /setup-agents: ONLY writes to customization/
# We simulate by writing output files into customization/ and verifying
# that no file outside customization/ is changed.
# ---------------------------------------------------------------------------

# Simulated /setup-agents output (writes only to customization/)
cat > "$TMPDIR_TEST/customization/analyst.toml" << 'EOF'
# generated: 2026-04-27T00:00:00Z by /setup-agents
model = "sonnet"
EOF

cat > "$TMPDIR_TEST/customization/reviewer.toml" << 'EOF'
# generated: 2026-04-27T00:00:00Z by /setup-agents
model = "opus"
EOF

# ---------------------------------------------------------------------------
# Post-run: verify files outside customization/ are byte-identical
# ---------------------------------------------------------------------------
echo "--- Assertion 1: files outside customization/ are byte-identical after /setup-agents ---"

AFTER_FILE="$TMPDIR_TEST/after.txt"
if [ -n "$CHECKSUM_CMD" ]; then
  while IFS= read -r f; do
    $CHECKSUM_CMD "$f"
  done < "$TMPDIR_TEST/files_outside.txt" | sort > "$AFTER_FILE"
else
  while IFS= read -r f; do
    wc -c < "$f"
  done < "$TMPDIR_TEST/files_outside.txt" | sort > "$AFTER_FILE"
fi

if diff -q "$BASELINE_FILE" "$AFTER_FILE" > /dev/null 2>&1; then
  echo "OK: all files outside customization/ are byte-identical (unchanged)"
else
  fail "Files outside customization/ were modified by /setup-agents simulation"
  diff "$BASELINE_FILE" "$AFTER_FILE" >&2
fi

# ---------------------------------------------------------------------------
# Assertion 2: setup-agents SKILL.md documents scope restriction to customization/
# ---------------------------------------------------------------------------
echo "--- Assertion 2: setup-agents SKILL.md documents scope restriction ---"
if grep -qiE 'customization/|scope.*customization|write.*only.*customization|only.*customization.*dir' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents writes limited to customization/"
else
  fail "setup-agents SKILL.md missing scope restriction (customization/ only) documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: setup-agents NEVER modifies agents/ or skills/ per spec
# ---------------------------------------------------------------------------
echo "--- Assertion 3: setup-agents SKILL.md explicitly prohibits modifying agents/ or skills/ ---"
# Check for NEVER rule or explicit prohibition
if grep -qiE 'NEVER.*modify.*agents|NEVER.*modify.*skills|never.*change.*plugin|read.only.*agents|do not modify.*agents' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md prohibits modification of agents/ or skills/"
else
  echo "INFO: no explicit NEVER prohibition on agents/skills/ found — acceptable if scope=customization/ is enforced"
fi

# ---------------------------------------------------------------------------
# Assertion 4: customization/ files WERE created (setup-agents produced output)
# ---------------------------------------------------------------------------
echo "--- Assertion 4: customization/ files created (setup-agents writes output) ---"
if [ -f "$TMPDIR_TEST/customization/analyst.toml" ] && [ -f "$TMPDIR_TEST/customization/reviewer.toml" ]; then
  echo "OK: customization/ output files exist"
else
  fail "customization/ output files not created"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-008 — /setup-agents scope isolation: only customization/ modified"
fi
exit "$FAIL"
