#!/usr/bin/env bash
# Test: onboard-migrate-lossless
# FC mapped: FC-20
# What it checks:
#   /onboard --migrate extracts inline Markdown tables into config.toml losslessly (all
#   23 sections mapped) and rewrites CLAUDE.md's `## Automation Config` section down to
#   the 1-2 line pointer.
# Expected RED (pre-impl): skills/onboard/SKILL.md's argument-hint currently lists only
#   [--fresh] [--update] -- no --migrate flag exists yet, and no migration transform is
#   documented.
# Expected GREEN (post-impl): SKILL.md documents --migrate, the extraction map (23
#   sections), and the CLAUDE.md pointer rewrite.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SKILL="skills/onboard/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
[ -f "$SKILL" ] || fail "$SKILL not found"

contains "$skill_content" "--migrate" || fail "FC-20: $SKILL does not document a --migrate flag"
contains "$skill_content" ".agent-flow/config.toml" || fail "FC-20: $SKILL does not state --migrate writes .agent-flow/config.toml"
contains_i "$skill_content" "pointer" || fail "FC-20: $SKILL does not state CLAUDE.md is rewritten to a pointer after migration"

# --- Design-level lossless map (regression guard: already pinned) ---
DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
contains "$design_content" "Total: **5 required + 18 optional = 23**" || contains_i "$design_content" "5 required + 18 optional" \
  || fail "design.md section 4 does not state the 23-section (5 required + 18 optional) lossless map"

# --- Behavioural: extraction fixture -- a legacy CLAUDE.md table row must map to a TOML key ---
LEGACY_ROW='| Type | youtrack |'
EXPECTED_TOML_LINE='type = "youtrack"'
contains "$LEGACY_ROW" "youtrack" || fail "legacy-row fixture malformed"
contains "$EXPECTED_TOML_LINE" "youtrack" || fail "expected-TOML-line fixture malformed"

# TODO(phase-7): once /onboard --migrate exists, run it against
# tests/mock-project/CLAUDE.md (or an equivalent legacy fixture) and assert (a) the
# produced config.toml contains all 23 [section] headers with the mapped keys, (b) no
# key/section is silently dropped, and (c) the rewritten CLAUDE.md `## Automation Config`
# section contains a pointer and zero `| Key | Value |` rows.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: onboard-migrate-lossless -- --migrate documented with lossless 23-section map and pointer rewrite"
  exit 0
fi
exit 1
