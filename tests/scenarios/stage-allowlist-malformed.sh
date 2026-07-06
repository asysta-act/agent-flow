#!/usr/bin/env bash
# ===========================================================================
# Test:        stage-allowlist-malformed.sh
# Falsifies:,
# FC mapped:   FC-REL-4 (a/b/c/d/e/f/g/h)
# What it checks:
#   ASSERT-1) 3 malformed fixture files exist in tests/fixtures/stage-allowlist/
#   ASSERT-2) Both step files contain "[WARN] malformed" prose
#   ASSERT-3) Both step files contain "allow-all-stages" fallback prose
#   ASSERT-4) Neither step file contains forbidden silent-skip prose
#   ASSERT-5) Verbatim awk fragments present in step files (extraction precondition)
#   ASSERT-6) awk parser on malformed-empty.md => empty output (zero-content trigger)
#   ASSERT-7) awk parser on malformed-truncated.md reads body to EOF + prose covers it
#   ASSERT-8) awk parser on malformed-extra-tags.md produces unrecognized lines
# Line budget: 50-100 lines.
# Expected RED phase: ASSERT-2/3 FAIL (WARN prose not yet in step files).
# Expected GREEN phase (post-impl): all ASSERTs PASS.
# ===========================================================================
set -uo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

FIX_DIR="tests/fixtures/stage-allowlist"
STEP_FB="skills/fix-bugs/steps/12-result.md"
STEP_IF="skills/implement-feature/steps/08-publish.md"

# ASSERT-1: 3 malformed fixture files with canonical names
[ -d "$FIX_DIR" ] || { fail "FC-REL-4.a: $FIX_DIR missing"; exit 1; }
for f in malformed-empty.md malformed-truncated.md malformed-extra-tags.md; do
  [ -f "$FIX_DIR/$f" ] || fail "FC-REL-4.b: $FIX_DIR/$f missing"
done

# ASSERT-2: [WARN] malformed prose in both step files
for step in "$STEP_FB" "$STEP_IF"; do
  [ -f "$step" ] || { fail "FC-REL-4.c-missing: $step not found"; continue; }
  grep -q '\[WARN\] malformed' "$step" \
    || fail "FC-REL-4.c: $step missing [WARN] malformed prose (/4.3)"
done

# ASSERT-3: allow-all-stages fallback prose in both step files
for step in "$STEP_FB" "$STEP_IF"; do
  [ -f "$step" ] || continue
  grep -q 'allow-all-stages' "$step" \
    || fail "FC-REL-4.c2: $step missing allow-all-stages fallback prose"
done

# ASSERT-4: No forbidden silent-skip-as-acceptable wording
for step in "$STEP_FB" "$STEP_IF"; do
  [ -f "$step" ] || continue
  ! grep -qE 'silent[ -]?skip.*acceptable|acceptable.*silent[ -]?skip' "$step" \
    || fail "FC-REL-4.d: $step contains forbidden silent-skip-as-acceptable phrasing"
done

# ASSERT-5: Verbatim awk fragments present (extraction precondition, LOW-5 guard)
[ -f "$STEP_FB" ] || { fail "FC-REL-4.e-missing: $STEP_FB not found"; exit 1; }
grep -qF '/<stage_allowlist>/{f=1;next}' "$STEP_FB" \
  || fail "FC-REL-4.f1a: $STEP_FB missing verbatim awk opening-tag fragment"
grep -qF '/<\/stage_allowlist>/{exit}' "$STEP_FB" \
  || fail "FC-REL-4.f1b: $STEP_FB missing verbatim awk closing-tag fragment"

# ASSERT-6: awk on malformed-empty.md => empty output (triggers WARN+fallback)
if [ -f "$FIX_DIR/malformed-empty.md" ]; then
  out_empty=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' \
    "$FIX_DIR/malformed-empty.md")
  [ -z "$out_empty" ] \
    || fail "FC-REL-4.empty: awk on malformed-empty.md produced non-empty output (expected empty => WARN trigger)"
fi

# ASSERT-7: awk on malformed-truncated.md reads body to EOF (no closing tag)
if [ -f "$FIX_DIR/malformed-truncated.md" ]; then
  out_trunc=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' \
    "$FIX_DIR/malformed-truncated.md")
  [ -n "$out_trunc" ] \
    || fail "FC-REL-4.truncated: awk on malformed-truncated.md produced empty output (expected body read to EOF)"
fi
for step in "$STEP_FB" "$STEP_IF"; do
  [ -f "$step" ] || continue
  grep -qE 'no closing tag|EOF|closing.*tag|truncat' "$step" \
    || fail "FC-REL-4.truncated-prose: $step prose does not address no-closing-tag case"
done

# ASSERT-8: awk on malformed-extra-tags.md produces unrecognized content lines
if [ -f "$FIX_DIR/malformed-extra-tags.md" ]; then
  out_extra=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' \
    "$FIX_DIR/malformed-extra-tags.md")
  has_invalid=$(printf '%s' "$out_extra" | grep -vE '^[[:space:]]*$' | grep -vcE '^(required|optional):' || true)
  [ "$has_invalid" -ge 1 ] \
    || fail "FC-REL-4.extra-tags: malformed-extra-tags.md block has no unrecognized lines (fixture setup error)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: stage-allowlist-malformed — 3 fixtures; WARN+allow-all-stages prose in step files; awk parser behaviors for empty/truncated/extra-tags confirmed"
  exit 0
fi
exit 1
