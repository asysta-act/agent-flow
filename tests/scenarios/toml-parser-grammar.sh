#!/usr/bin/env bash
# Test: toml-parser-grammar
# FC mapped: FC-04, FC-08
# What it checks:
#   FC-04: core/config-reader.md documents parsing .agent-flow/config.toml via a
#   pure-bash TOML subset -- bare [section] headers, string/int/bool scalars, """
#   multi-line strings, and # comments -- with no tomllib/taplo/python3 dependency.
#   FC-08: the PR Description Template round-trips as a TOML """ multi-line string
#   under [pr_description_template], mapping to pr_rules.description_template.
# Expected RED (pre-impl): core/config-reader.md still describes parsing CLAUDE.md
#   Markdown tables (Input Contract names claude_md_content) -- these assertions fail
#   against the CURRENT file, which is correct TDD red state.
# Expected GREEN (post-impl): core/config-reader.md rewritten per design.md section 1;
#   all assertions below pass.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
# shellcheck source=tests/lib/assert.sh
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

READER="core/config-reader.md"
DESIGN="spec/design.md"

reader_content=""
[ -f "$READER" ] && reader_content="$(cat "$READER")"
[ -f "$READER" ] || fail "FC-04: $READER not found"

design_content=""
[ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Spec commitment checks (design.md already pins the target grammar; regression guard) ---
if [ -n "$design_content" ]; then
  contains "$design_content" '[section]'      || fail "design.md missing bare [section] header grammar row"
  contains "$design_content" 'Multi-line string' || fail "design.md missing multi-line string grammar row"
  contains "$design_content" '"""'            || fail "design.md missing triple-quote multi-line construct"
  contains_i "$design_content" 'comment'      || fail "design.md missing # comment construct"
fi

# --- Implementation target: core/config-reader.md must adopt the pure-bash reader ---
contains "$reader_content" ".agent-flow/config.toml" || fail "FC-04: core/config-reader.md does not reference .agent-flow/config.toml (still describes CLAUDE.md tables)"
contains_i "$reader_content" "pure-bash" || fail "FC-04: core/config-reader.md does not document a pure-bash parser"
if contains "$reader_content" "claude_md_content"; then
  fail "FC-04/REQ-16: core/config-reader.md still names claude_md_content as an input (hard-cut not applied)"
fi

# FC-08: PR Description Template as a """ multi-line string under [pr_description_template]
contains "$reader_content" "[pr_description_template]" || fail "FC-08: core/config-reader.md does not document [pr_description_template]"
matches_re "$reader_content" 'pr_rules\.description_template' || fail "FC-08: core/config-reader.md does not map the template to pr_rules.description_template"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-parser-grammar -- pure-bash [section]/scalar/multiline/comment grammar documented"
  exit 0
fi
exit 1
