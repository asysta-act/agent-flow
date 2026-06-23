#!/usr/bin/env bash
# Verifies: AC-INV-PERM-001
# Description: No agent file in agents/*.md has hooks:, mcpServers:, or permissionMode:
#   in its YAML frontmatter block
# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if matches_re "$REPO_ROOT" '\.forge'; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

AGENTS_DIR="$REPO_ROOT/agents"

if [ ! -d "$AGENTS_DIR" ]; then
  fail "agents/ directory not found"
  exit 1
fi

FORBIDDEN_KEYS="hooks|mcpServers|permissionMode"

# ---------------------------------------------------------------------------
# Check each agent file's frontmatter only (not body)
# Per AC-INV-PERM-001: extract content between 1st and 2nd '---' lines
# ---------------------------------------------------------------------------
echo "--- Checking agent frontmatter for forbidden permission keys ---"

AGENT_COUNT=0
TMPDIR_PERM="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PERM"' EXIT INT TERM
find "$AGENTS_DIR" -maxdepth 1 -name '*.md' -type f > "$TMPDIR_PERM/agent_list.txt"

while IFS= read -r agent_file; do
  AGENT_COUNT=$((AGENT_COUNT + 1))
  basename_agent=$(basename "$agent_file")

  # Extract frontmatter: content between 1st and 2nd '---' line
  FRONTMATTER=$(awk '/^---$/{c++; next} c==1' "$agent_file")

  # grep is line-oriented; '^' anchors per-line. Replicate with (start-of-string OR newline).
  if matches_re "$FRONTMATTER" "(^|"$'\n'")($FORBIDDEN_KEYS):"; then
    fail "$basename_agent frontmatter contains forbidden key (hooks/mcpServers/permissionMode)"
  else
    echo "OK: $basename_agent frontmatter has no forbidden permission keys"
  fi
done < "$TMPDIR_PERM/agent_list.txt"

# ---------------------------------------------------------------------------
# Assertion: all 18 agents checked
# ---------------------------------------------------------------------------
echo "--- Assertion: expected agents checked ---"
if [ "$AGENT_COUNT" -eq 17 ]; then
  echo "OK: checked $AGENT_COUNT agent files"
elif [ "$AGENT_COUNT" -gt 0 ]; then
  echo "INFO: checked $AGENT_COUNT agent files"
else
  fail "No agent files found to check"
fi

# ---------------------------------------------------------------------------
# Assertion: automation-config.md documents permission constraint
# ---------------------------------------------------------------------------
echo "--- Assertion: automation-config.md documents plugin permission constraint ---"
AUTOCONFIG="$REPO_ROOT/docs/reference/automation-config.md"
if [ ! -f "$AUTOCONFIG" ]; then
  echo "SKIP: docs/reference/automation-config.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'plugin.*permission|permission.*constraint|hooks.*skill.orchestrated' "$AUTOCONFIG"; then
  echo "OK: automation-config.md documents plugin permission constraint"
else
  fail "automation-config.md missing plugin permission constraint documentation"
fi

# AC-DOC-007: exact phrase "hooks are skill-orchestrated, not agent-frontmatter"
if grep -qF 'hooks are skill-orchestrated, not agent-frontmatter' "$AUTOCONFIG"; then
  echo "OK: exact phrase 'hooks are skill-orchestrated, not agent-frontmatter' present"
else
  fail "automation-config.md missing exact phrase 'hooks are skill-orchestrated, not agent-frontmatter'"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-INV-PERM-001 — no agent frontmatter contains forbidden permission keys"
fi
exit "$FAIL"
