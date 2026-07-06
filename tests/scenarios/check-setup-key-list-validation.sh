#!/usr/bin/env bash
# Test: check-setup-key-list-validation
# FC mapped: FC-16
# What it checks:
#   A config.toml with an unknown key yields [WARN]; a config.toml missing a required
#   section yields [FAIL]. Distinguishes unknown (non-fatal) from missing-required
#   (fatal) key-list violations.
# Expected RED (pre-impl): skills/check-setup/SKILL.md's current Block 1 validates
#   CLAUDE.md's `## Automation Config` table structure, not a config.toml key list --
#   the TOML-specific unknown-key/missing-required-section distinction is absent today.
# Expected GREEN (post-impl): SKILL.md documents both the [WARN] (unknown key) and [FAIL]
#   (missing required section/key) outcomes against config.toml.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SKILL="skills/check-setup/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
[ -f "$SKILL" ] || fail "$SKILL not found"

contains "$skill_content" ".agent-flow/config.toml" || fail "FC-16: $SKILL does not reference .agent-flow/config.toml"
contains "$skill_content" "[WARN]" || fail "FC-16: $SKILL does not use the [WARN] token"
contains "$skill_content" "[FAIL]" || fail "FC-16: $SKILL does not use the [FAIL] token"
contains_i "$skill_content" "unknown key" || fail "FC-16: $SKILL does not document an 'unknown key' check for config.toml"
contains_i "$skill_content" "missing.*required" || matches_re "$skill_content" 'missing[[:space:]]+required' \
  || fail "FC-16: $SKILL does not document a 'missing required section' check"

# --- Behavioural: run the reference config_validate against two fixtures. ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc16.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Fixture A: complete valid required set + one UNKNOWN key -> [WARN], not [FAIL].
cat > "$TMP/unknown.toml" <<'EOF'
[issue_tracker]
type = "github"
instance = "i"
project = "P"
bug_query = "q"
state_transitions = "a: b"
on_start_set = "x"
totally_unknown_key = "leak"
[source_control]
remote = "o/r"
base_branch = "main"
branch_naming = "f"
[pr_rules]
labels = "bug"
[pr_description_template]
template = "S"
[build_and_test]
build_command = "make"
test_command = "pytest"
EOF
unknown_out="$(config_validate "$TMP/unknown.toml" 2>&1)"; unknown_rc=$?
contains "$unknown_out" "[WARN]" || fail "FC-16: unknown-key config.toml did not yield a [WARN]"
contains "$unknown_out" "totally_unknown_key" || fail "FC-16: the [WARN] does not name the unknown key"
contains "$unknown_out" "[FAIL]" && fail "FC-16: an unknown key must NOT escalate to [FAIL]"
[ "$unknown_rc" -eq 0 ] || fail "FC-16: unknown-key validation returned non-zero (rc=$unknown_rc); unknown keys are non-fatal"

# Fixture B: missing a required section -> [FAIL].
cat > "$TMP/missing.toml" <<'EOF'
[source_control]
remote = "o/r"
base_branch = "main"
branch_naming = "f"
EOF
if contains "$(cat "$TMP/missing.toml")" "[issue_tracker]"; then
  fail "missing-required-section fixture incorrectly contains [issue_tracker]"
fi
missing_out="$(config_validate "$TMP/missing.toml" 2>&1)"; missing_rc=$?
contains "$missing_out" "[FAIL]" || fail "FC-16: missing-required-section config.toml did not yield a [FAIL]"
[ "$missing_rc" -ne 0 ] || fail "FC-16: missing-required-section validation returned 0 (must be fatal)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup-key-list-validation -- unknown key -> [WARN] (rc 0); missing required section -> [FAIL] (rc!=0)"
  exit 0
fi
exit 1
