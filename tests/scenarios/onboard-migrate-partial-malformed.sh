#!/usr/bin/env bash
# Test: onboard-migrate-partial-malformed  [HIDDEN]
# FC mapped: FC-20 (robustness clause, design.md section 4.3 point 5)
# What it checks:
#   design.md section 4.3 point 5 (robustness, "m5"): if the inline block is malformed
#   or missing required sections, --migrate SHALL emit a [WARN] listing each section it
#   could not extract, SHALL NOT silently drop a section, and SHALL NOT leave a
#   half-written config.toml that would fail /check-setup. Concretely: (a) aborts before
#   writing config.toml when a REQUIRED section is unextractable (CLAUDE.md untouched),
#   or (b) when only OPTIONAL sections are malformed, writes the clean sections and
#   reports the skipped optional ones. It never rewrites CLAUDE.md to the pointer unless
#   a valid, check-setup-passing config.toml was produced.
#   Kept hidden because a naive implementation of --migrate that only handles the
#   well-formed happy path (visible tests/onboard-migrate-lossless.sh) would still pass
#   the visible test while silently corrupting or half-writing on malformed input --
#   this is exactly the kind of criterion the visible suite alone would not catch.
# Expected RED (pre-impl): skills/onboard/SKILL.md does not document --migrate, its
#   partial/malformed-input handling, or the "never half-write" guarantee at all.
# Expected GREEN (post-impl): SKILL.md documents both the required-section-abort path and
#   the optional-section-skip-and-report path.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
contains_i "$design_content" "half-written" || fail "design.md section 4.3 point 5 does not state the never-half-written config.toml guarantee"
contains_i "$design_content" "each section it could not extract" || fail "design.md does not require [WARN]-listing every unextractable section"

SKILL="skills/onboard/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
contains "$skill_content" "--migrate" || fail "FC-20 (hidden/partial-malformed): $SKILL does not document --migrate at all"
contains_i "$skill_content" "half-written" || contains_i "$skill_content" "half write" \
  || fail "FC-20 (hidden/partial-malformed): $SKILL does not document the never-half-written guarantee"
contains_i "$skill_content" "required" || fail "FC-20 (hidden/partial-malformed): $SKILL does not distinguish required-section-unextractable (abort) from optional-only malformation (skip+report)"

# --- Fixture A: REQUIRED section unextractable (broken pipe table for Issue Tracker) ---
REQUIRED_BROKEN_FIXTURE='### Issue Tracker
| Key | Value
|------|---------|
| Type | youtrack
'
if contains "$REQUIRED_BROKEN_FIXTURE" "| Key | Value |"; then
  fail "fixture-A sanity: header row must be malformed (missing closing pipe) to exercise the abort path"
fi

# --- Fixture B: only an OPTIONAL section malformed (Metrics), required sections intact ---
OPTIONAL_BROKEN_FIXTURE='### Metrics
| Key | Value
|-----|-------
| Output | stdout
'
contains "$OPTIONAL_BROKEN_FIXTURE" "Metrics" || fail "fixture-B sanity: must target the Metrics optional section"

# TODO(phase-7): once /onboard --migrate exists, run it against a CLAUDE.md containing
# Fixture A and assert (a) NO config.toml is written, (b) CLAUDE.md is untouched (still has
# the original tables, no pointer rewrite), and (c) a [WARN] names Issue Tracker as
# unextractable. Separately, run it against a CLAUDE.md containing Fixture B (all 5
# required sections well-formed, only Metrics malformed) and assert (a) config.toml IS
# written with all required sections + any other clean optional sections, (b) Metrics is
# skipped with a [WARN] naming it, and (c) config.toml passes /check-setup (no half-write).

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: onboard-migrate-partial-malformed -- required-abort vs optional-skip-and-report contract documented"
  exit 0
fi
exit 1
