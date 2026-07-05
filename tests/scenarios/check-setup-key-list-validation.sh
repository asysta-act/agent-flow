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

# --- Behavioural fixtures: unknown-key config.toml vs missing-required-section config.toml ---
UNKNOWN_KEY_FIXTURE='[issue_tracker]
type = "github"
totally_unknown_key = "x"'
MISSING_REQUIRED_FIXTURE='[source_control]
remote = "org/repo"'  # [issue_tracker] absent entirely

contains "$UNKNOWN_KEY_FIXTURE" "totally_unknown_key" || fail "unknown-key fixture malformed"
if contains "$MISSING_REQUIRED_FIXTURE" "[issue_tracker]"; then
  fail "missing-required-section fixture incorrectly contains [issue_tracker] (must be absent to exercise FAIL)"
fi

# TODO(phase-7): once check-setup's key-list validator exists, run it against both fixtures
# and assert the unknown-key fixture yields an exit/marker equivalent to [WARN] (not FAIL)
# while the missing-required fixture yields [FAIL].

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup-key-list-validation -- unknown-key WARN / missing-required FAIL distinction documented"
  exit 0
fi
exit 1
