#!/usr/bin/env bash
# Test: hard-cut-removal-guard
# FC mapped: FC-02 [DEDICATED]
# What it checks:
#   No config-consuming file contains a code path that PARSES Automation Config from
#   CLAUDE.md into the config object (inline parse, fallback, dual-read, deprecation
#   shim) -- targeting core/config-reader.md, skills/*/steps/*.md,
#   skills/setup-agents/lib/*.sh, and skills/*/SKILL.md EXCLUDING
#   skills/check-setup/SKILL.md (whose detect-and-warn read is explicitly permitted, per
#   FC-17/REQ-11(d)). Separately asserts check-setup's permitted detection read does NOT
#   itself map legacy tables into a config object -- two assertions, not one, per the
#   tdd-refined.md success criteria.
# Expected RED (pre-impl): core/config-reader.md's CURRENT content literally IS a
#   CLAUDE.md-table parser (claude_md_content input, `### {Section}` table walking) --
#   this scenario is expected to fail loudly today, proving the hard-cut has not yet
#   happened. This is the correct TDD red state for the migration's core removal.
# Expected GREEN (post-impl): the parse-into-config signature patterns are gone from the
#   config surface (excluding check-setup's detect-only read).
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# Config surface, EXCLUDING skills/check-setup/SKILL.md (its detect-and-warn read is permitted).
mapfile -t ALL_SURFACE_FILES < <(
  {
    [ -f core/config-reader.md ] && printf '%s\n' core/config-reader.md
    find skills -type f -path '*/steps/*.md' 2>/dev/null
    find skills/setup-agents/lib -type f -name '*.sh' 2>/dev/null
    find skills -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null
  } | sort -u
)

SURFACE_FILES=()
for f in "${ALL_SURFACE_FILES[@]}"; do
  case "$f" in
    'skills/check-setup/SKILL.md') continue ;;
  esac
  SURFACE_FILES+=("$f")
done

for f in "${SURFACE_FILES[@]}"; do
  [ -f "$f" ] || continue
  content="$(cat "$f")"
  matches_re "$content" 'parse.*Automation Config.*table' && fail "FC-02: $f contains a 'parse Automation Config table' signature (hard-cut violation)"
  matches_re "$content" 'fall ?back.*CLAUDE\.md' && fail "FC-02: $f contains a CLAUDE.md fallback signature (hard-cut violation)"
  contains "$content" "claude_md_content" && fail "FC-02: $f still names claude_md_content (hard-cut violation)"
done

READER="core/config-reader.md"
if [ -f "$READER" ]; then
  reader_content="$(cat "$READER")"
  contains_i "$reader_content" "overlay_source=md" && fail "FC-02: $READER contains an overlay_source=md dual-read branch"
fi

# --- Second, SEPARATE assertion: check-setup's PERMITTED detect-only read must not itself
# map legacy tables into a config object (FC-02/FC-17 joint satisfiability). ---
CHECK_SETUP="skills/check-setup/SKILL.md"
if [ -f "$CHECK_SETUP" ]; then
  cs_content="$(cat "$CHECK_SETUP")"
  matches_re "$cs_content" 'parse.*Automation Config.*table' && fail "FC-02: $CHECK_SETUP maps legacy tables into a config object (only detect-and-warn is permitted here)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: hard-cut-removal-guard -- no parse-into-config path survives outside check-setup's permitted detection"
  exit 0
fi
exit 1
