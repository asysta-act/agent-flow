#!/usr/bin/env bash
# Test: scaffold-emits-config-toml
# FC mapped: FC-22
# What it checks:
#   /scaffold writes .agent-flow/config.toml directly, and the scaffold no longer emits
#   a `## Automation Config` table block into the generated CLAUDE.md (the generated-
#   CLAUDE.md template must contain a pointer, no `| Key | Value |` rows).
# Expected RED (pre-impl): skills/scaffold/steps/03-scaffold.md's current "03c. Auto-fill
#   CLAUDE.md" step auto-fills Automation Config VALUES DIRECTLY INTO CLAUDE.md -- it does
#   not emit .agent-flow/config.toml at all today.
# Expected GREEN (post-impl): the step emits .agent-flow/config.toml and the generated
#   CLAUDE.md template contains only the pointer.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

STEP="skills/scaffold/steps/03-scaffold.md"
step_content=""; [ -f "$STEP" ] && step_content="$(cat "$STEP")"
[ -f "$STEP" ] || fail "$STEP not found"

contains "$step_content" ".agent-flow/config.toml" || fail "FC-22: $STEP does not document emitting .agent-flow/config.toml"

# The generated-CLAUDE.md template must be pointer-only: no '| Key | Value |' authoring
# instructions for Automation Config content within the scaffold step.
if matches_re "$step_content" 'CLAUDE\.md \(with Automation Config\)'; then
  fail "FC-22: $STEP still describes generating 'CLAUDE.md (with Automation Config)' inline tables"
fi
contains_i "$step_content" "pointer" || fail "FC-22: $STEP does not describe writing a pointer-only Automation Config section into the generated CLAUDE.md"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: scaffold-emits-config-toml -- scaffold documented to emit config.toml + pointer-only CLAUDE.md"
  exit 0
fi
exit 1
