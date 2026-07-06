#!/usr/bin/env bash
# Test: config-source-is-toml
# FC mapped: FC-01
# What it checks:
#   core/config-reader.md references .agent-flow/config.toml as the input it parses,
#   AND its Input Contract no longer names claude_md_content / CLAUDE.md as the config
#   source (the two halves of FC-01 must BOTH hold).
# Expected RED (pre-impl): the current core/config-reader.md Input Contract names
#   claude_md_content (full contents of CLAUDE.md) as its sole required input -- both
#   halves of this check fail against the current file.
# Expected GREEN (post-impl): the Input Contract is rewritten to take
#   .agent-flow/config.toml as input; claude_md_content is gone.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
[ -f "$READER" ] || fail "$READER not found"

contains "$reader_content" ".agent-flow/config.toml" || fail "FC-01: $READER does not reference .agent-flow/config.toml as its input"

# Extract the Input Contract section specifically (heading -> next ##)
input_contract=""
if [ -f "$READER" ]; then
  input_contract="$(awk '/^## Input Contract[[:space:]]*$/{f=1;next} /^## /&&f{exit} f' "$READER")"
fi
if contains "$input_contract" "claude_md_content"; then
  fail "FC-01: $READER's Input Contract still names claude_md_content as the config source"
fi
if contains_i "$input_contract" "CLAUDE.md"; then
  fail "FC-01: $READER's Input Contract still names CLAUDE.md as the config source"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-source-is-toml -- core/config-reader.md's Input Contract targets .agent-flow/config.toml, not CLAUDE.md"
  exit 0
fi
exit 1
