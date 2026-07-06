#!/usr/bin/env bash
# Scenario: hostname neutralization in user-facing files
# Expected outcome: PASS — all internal hostnames neutralized in user-facing files
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

INSTALLATION="$REPO_ROOT/docs/guides/installation.md"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
MOCK_CLAUDE="$REPO_ROOT/tests/mock-project/CLAUDE.md"
ONBOARD_SKILL="$REPO_ROOT/skills/onboard/SKILL.md"
ROADMAP="$REPO_ROOT/docs/roadmap.md"

# Assertion 1 (NEGATIVE): no internal hostname in any user-facing file
# Note: plugin.json intentionally contains the internal URL — see Item 8
echo "--- Assertion 1 (NEGATIVE): no github.com/asysta-act/agent-flow in user-facing files ---"
for f in "$INSTALLATION" "$MOCK_CLAUDE" "$ONBOARD_SKILL"; do
  if [ ! -f "$f" ]; then
    fail "file does not exist: $f"
    continue
  fi
  if grep -qE 'github\.com/asysta-act/agent-flow' "$f"; then
    fail "internal hostname 'github.com/asysta-act/agent-flow' found in $f (must be replaced with placeholder)"
  else
    echo "OK: no internal hostname in $f"
  fi
done

# Assertion 2: installation.md uses <your-git-host> placeholder (>=5 occurrences)
echo "--- Assertion 2: installation.md has >=5 <your-git-host> placeholders ---"
if [ -f "$INSTALLATION" ]; then
  count=$(grep -c '<your-git-host>' "$INSTALLATION" 2>/dev/null || true)
  if [ "$count" -ge 5 ]; then
    echo "OK: installation.md has $count '<your-git-host>' placeholders (>=5 required)"
  else
    fail "installation.md has only $count '<your-git-host>' placeholder(s) — need >=5"
  fi
  if grep -qF '<owner>/<repo>' "$INSTALLATION"; then
    echo "OK: installation.md has '<owner>/<repo>' placeholder"
  else
    fail "installation.md missing '<owner>/<repo>' placeholder"
  fi
fi

# Assertion 3: onboard SKILL.md uses <your-gitea-host>/org/repo placeholder
echo "--- Assertion 3: onboard SKILL.md placeholder neutralized ---"
if [ -f "$ONBOARD_SKILL" ]; then
  if grep -qF '<your-gitea-host>/org/repo' "$ONBOARD_SKILL"; then
    echo "OK: skills/onboard/SKILL.md uses '<your-gitea-host>/org/repo' placeholder"
  else
    fail "skills/onboard/SKILL.md missing '<your-gitea-host>/org/repo' placeholder"
  fi
fi

# Assertion 4: mock-project config uses <your-gitea-host>/test/mock-project.
# Post-migration the Source Control value moved from the inline CLAUDE.md table to the
# committed .agent-flow/config.toml (CLAUDE.md is now a pointer), so the placeholder is
# asserted there.
echo "--- Assertion 4: tests/mock-project/.agent-flow/config.toml placeholder neutralized ---"
MOCK_CONFIG="$REPO_ROOT/tests/mock-project/.agent-flow/config.toml"
if [ -f "$MOCK_CONFIG" ]; then
  if grep -qF '<your-gitea-host>/test/mock-project' "$MOCK_CONFIG"; then
    echo "OK: tests/mock-project/.agent-flow/config.toml uses '<your-gitea-host>/test/mock-project' placeholder"
  else
    fail "tests/mock-project/.agent-flow/config.toml missing '<your-gitea-host>/test/mock-project' placeholder"
  fi
else
  fail "tests/mock-project/.agent-flow/config.toml does not exist"
fi

# Assertion 5: plugin.json does not contain example.invalid URL (was a placeholder, now resolved)
echo "--- Assertion 5: plugin.json has no example.invalid placeholder URL ---"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  if grep -qF 'example.invalid' "$PLUGIN_JSON"; then
    fail "plugin.json still contains example.invalid placeholder URL — replace with the real repository URL"
  else
    echo "OK: plugin.json has no example.invalid placeholder (URL is set)"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: all internal hostnames neutralized + placeholder tokens in user-facing files"
fi
exit "$FAIL"
