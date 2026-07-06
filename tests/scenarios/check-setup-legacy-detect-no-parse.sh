#!/usr/bin/env bash
# Test: check-setup-legacy-detect-no-parse  [HIDDEN]
# FC mapped: FC-02 [DEDICATED] / FC-17 -- joint satisfiability, hidden guard
# What it checks:
#   check-setup's PERMITTED legacy-detection read (which pairs with the /onboard
#   --migrate hint, FC-17) must remain a DETECT-ONLY read -- it must never itself walk
#   `### {Section}` Markdown tables into a config object (that would silently reintroduce
#   the hard-cut-removed dual-read path via the one file that's allowed to still look at
#   CLAUDE.md at all). This is the specific joint-satisfiability edge the tdd-refined.md
#   coordinator note calls out: FC-02 and FC-17 must BOTH hold on check-setup/SKILL.md
#   simultaneously. Kept hidden because it is easy for an implementation to satisfy FC-17
#   (emit the migrate hint) by reusing/adapting the OLD table-walking parser code
#   in-place inside check-setup -- which would pass a shallow FC-17-only test while
#   quietly violating FC-02's hard-cut scope.
# Expected RED (pre-impl): skills/check-setup/SKILL.md's CURRENT Block 1 already walks
#   CLAUDE.md's `## Automation Config` / `### {Section}` structure into pass/fail
#   judgments over key-by-key values (Step 3's required-keys table) -- this is
#   structurally adjacent to "parsing into a config object" and must be distinguished
#   post-migration from a bare presence/absence detection. Fails today because the
#   post-migration detect-only contract does not exist yet.
# Expected GREEN (post-impl): SKILL.md documents a legacy-block check that only detects
#   presence (to emit the migrate hint) and does not extract per-key values into a
#   resolved config object.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

REQS="spec/requirements.md"
reqs_content=""; [ -f "$REQS" ] && reqs_content="$(cat "$REQS")"
contains "$reqs_content" "REQ-11" || fail "requirements.md missing REQ-11 (check-setup validation, including the legacy-inline hint)"
contains_i "$reqs_content" "merely" || contains_i "$reqs_content" "detects" \
  || fail "requirements.md does not describe the legacy-block read as detection-only (distinct from parsing)"

SKILL="skills/check-setup/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
[ -f "$SKILL" ] || fail "$SKILL not found"

# FC-17 half: the migrate hint must be present.
contains "$skill_content" "/onboard --migrate" || fail "FC-17: $SKILL does not hint at /onboard --migrate"

# FC-02 half: the SAME file must NOT map legacy tables into a config object.
matches_re "$skill_content" 'parse.*Automation Config.*table' && fail "FC-02 (hidden): $SKILL maps legacy Automation Config tables into a config object -- the permitted read must stay detect-only"
contains "$skill_content" "claude_md_content" && fail "FC-02 (hidden): $SKILL references claude_md_content (a config-object input name), not a bare detection read"

# --- Distinctness guard: the post-migration SKILL.md's config.toml-key-list validation
# (FC-16, a DIFFERENT and PERMITTED behaviour: validating config.toml's OWN keys) must not
# be confused with parsing CLAUDE.md's legacy tables -- these are two separate data
# sources and only the CLAUDE.md-legacy-table path is restricted by FC-02. ---
if contains "$skill_content" ".agent-flow/config.toml"; then
  echo "OK: $SKILL also validates config.toml directly (FC-16 path) -- distinct from the CLAUDE.md legacy-detection path"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup-legacy-detect-no-parse -- FC-02 and FC-17 jointly satisfied on check-setup/SKILL.md"
  exit 0
fi
exit 1
