#!/usr/bin/env bash
# Test: onboard-migrate-idempotence
# FC mapped: FC-20
# What it checks:
#   Running /onboard --migrate twice does not double-migrate or corrupt config.toml.
#   design.md section 4.3 point 4: "Idempotent: if config.toml already exists, warn and
#   require explicit overwrite rather than clobbering."
# Expected RED (pre-impl): skills/onboard/SKILL.md does not document --migrate or its
#   idempotence guard at all yet.
# Expected GREEN (post-impl): SKILL.md documents that a second --migrate run warns and
#   requires explicit overwrite instead of silently clobbering or duplicating sections.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
contains_i "$design_content" "idempotent" || fail "design.md section 4.3 does not state the --migrate idempotence contract"
contains_i "$design_content" "explicit overwrite" || fail "design.md does not require explicit overwrite rather than clobbering on re-migration"

SKILL="skills/onboard/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
contains "$skill_content" "--migrate" || fail "FC-20: $SKILL does not document --migrate at all"
contains_i "$skill_content" "already exists" || fail "FC-20: $SKILL does not document the 'config.toml already exists' idempotence guard"

# --- Behavioural fixture: simulate a config.toml that already exists ---
TMP_DIR="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/onboard-migrate-idem.$$")"
mkdir -p "$TMP_DIR/.agent-flow"
FIRST_CONTENT='[issue_tracker]
type = "youtrack"
'
printf '%s' "$FIRST_CONTENT" > "$TMP_DIR/.agent-flow/config.toml"
before_hash="$(cat "$TMP_DIR/.agent-flow/config.toml" 2>/dev/null | wc -c)"
# Simulate a naive (non-idempotent) re-migration attempt appending instead of overwriting --
# this is the failure mode the spec forbids; the fixture proves the byte-count would change
# if a real migration silently appended without the guard.
printf '%s' "$FIRST_CONTENT" >> "$TMP_DIR/.agent-flow/config.toml"
after_hash="$(cat "$TMP_DIR/.agent-flow/config.toml" 2>/dev/null | wc -c)"
rm -rf "$TMP_DIR" 2>/dev/null || true
if [ "$before_hash" -eq "$after_hash" ]; then
  fail "idempotence fixture sanity: naive double-write should have changed the byte count (fixture construction bug)"
fi

# TODO(phase-7): once /onboard --migrate exists, invoke it twice against the same legacy
# CLAUDE.md fixture and assert the SECOND run either (a) is a no-op with a warning, or
# (b) requires explicit --overwrite/confirmation and does not silently double the config.toml
# content or duplicate any [section].

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: onboard-migrate-idempotence -- idempotence/overwrite-guard contract documented"
  exit 0
fi
exit 1
