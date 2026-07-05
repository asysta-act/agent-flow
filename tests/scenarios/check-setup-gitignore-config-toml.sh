#!/usr/bin/env bash
# Test: check-setup-gitignore-config-toml
# FC mapped: FC-15 [DEDICATED]
# What it checks:
#   /check-setup FAILs when .agent-flow/config.toml is gitignored and passes when it is
#   tracked. This scenario is genuinely BEHAVIOURAL for the git mechanics (git
#   check-ignore is a real command, needs no plugin implementation) and structural
#   (spec-conformance) for the "check-setup reports [FAIL]/[OK]" claim, since
#   check-setup is a Claude-Code-interpreted skill, not directly bash-invokable.
# Expected RED (pre-impl):
#   (a) the git-mechanics assertions below ALREADY PASS today (git check-ignore works
#       regardless of plugin implementation status) -- these are real behavioural checks.
#   (b) the "skills/check-setup/SKILL.md documents git check-ignore for config.toml"
#       assertion FAILS today (current SKILL.md checks CLAUDE.md structure, not
#       .agent-flow/config.toml via git check-ignore) -- correct red.
# Expected GREEN (post-impl): skills/check-setup/SKILL.md documents both paths.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# --- Genuine behavioural test: git check-ignore mechanics in an isolated temp repo ---
TMP_REPO="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/check-setup-gitignore.$$")"
mkdir -p "$TMP_REPO"
(
  cd "$TMP_REPO" || exit 1
  git init -q .
  mkdir -p .agent-flow
  : > .agent-flow/config.toml

  # (a) FAIL path: config.toml is gitignored
  printf '.agent-flow/config.toml\n' > .gitignore
  if git check-ignore .agent-flow/config.toml >/dev/null 2>&1; then
    echo "OK: git check-ignore exits 0 (ignored) when config.toml is gitignored"
  else
    echo "FAIL: git check-ignore did not detect the ignored config.toml" >&2
    exit 1
  fi

  # (b) OK path: remove the ignore rule -> config.toml is tracked
  : > .gitignore
  if git check-ignore .agent-flow/config.toml >/dev/null 2>&1; then
    echo "FAIL: git check-ignore still reports config.toml as ignored after removing the rule" >&2
    exit 1
  else
    echo "OK: git check-ignore exits 1 (not ignored) once the ignore rule is removed"
  fi
)
git_mechanics_status=$?
rm -rf "$TMP_REPO" 2>/dev/null || true
[ "$git_mechanics_status" -eq 0 ] || fail "FC-15: git check-ignore FAIL/OK path mechanics did not behave as documented"

# --- Structural (spec-conformance): skills/check-setup/SKILL.md must document this check ---
SKILL="skills/check-setup/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
contains "$skill_content" "git check-ignore" || fail "FC-15: $SKILL does not mention 'git check-ignore'"
contains "$skill_content" ".agent-flow/config.toml" || fail "FC-15: $SKILL does not reference .agent-flow/config.toml"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup-gitignore-config-toml -- git check-ignore FAIL/OK mechanics verified; SKILL.md documents the check"
  exit 0
fi
exit 1
