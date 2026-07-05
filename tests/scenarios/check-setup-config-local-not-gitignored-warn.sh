#!/usr/bin/env bash
# Test: check-setup-config-local-not-gitignored-warn
# FC mapped: FC-28
# What it checks:
#   Accidental-commit guard, DISTINCT from FC-15: if .agent-flow/config.local.toml is
#   present but NOT gitignored, check-setup emits a [WARN] (not a [FAIL]/block -- this is
#   advisory, unlike the config.toml-must-be-tracked FC-15 check which goes the other
#   direction). If it IS gitignored, no such WARN fires.
# Expected RED (pre-impl):
#   (a) the git-mechanics assertions below ALREADY PASS today (real git check-ignore).
#   (b) skills/check-setup/SKILL.md does not document a config.local.toml
#       not-gitignored WARN today -- correct red.
# Expected GREEN (post-impl): SKILL.md documents the WARN paired with git check-ignore.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# --- Genuine behavioural test: git check-ignore mechanics for config.local.toml ---
TMP_REPO="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/check-setup-local-gitignore.$$")"
mkdir -p "$TMP_REPO"
(
  cd "$TMP_REPO" || exit 1
  git init -q .
  mkdir -p .agent-flow
  : > .agent-flow/config.local.toml

  # (a) Tracked (NOT gitignored) -> the accidental-commit condition that should WARN
  : > .gitignore
  if git check-ignore .agent-flow/config.local.toml >/dev/null 2>&1; then
    echo "FAIL: config.local.toml unexpectedly reported as ignored with an empty .gitignore" >&2
    exit 1
  else
    echo "OK: config.local.toml is tracked (not ignored) -- the WARN-triggering state"
  fi

  # (b) Properly gitignored -> no WARN should fire
  printf '.agent-flow/config.local.toml\n' > .gitignore
  if git check-ignore .agent-flow/config.local.toml >/dev/null 2>&1; then
    echo "OK: config.local.toml is gitignored -- no WARN should fire"
  else
    echo "FAIL: config.local.toml still reported as tracked after adding the ignore rule" >&2
    exit 1
  fi
)
git_mechanics_status=$?
rm -rf "$TMP_REPO" 2>/dev/null || true
[ "$git_mechanics_status" -eq 0 ] || fail "FC-28: git check-ignore mechanics for config.local.toml did not behave as documented"

# --- Structural: skills/check-setup/SKILL.md must document the WARN, distinct from FC-15's FAIL ---
SKILL="skills/check-setup/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
contains "$skill_content" "config.local.toml" || fail "FC-28: $SKILL does not mention config.local.toml"
contains "$skill_content" "[WARN]" || fail "FC-28: $SKILL does not use the [WARN] token"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup-config-local-not-gitignored-warn -- accidental-commit WARN mechanics verified"
  exit 0
fi
exit 1
