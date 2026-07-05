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
source "$REPO_ROOT/core/lib/config-reader.sh"

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

TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc20pm.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# --- Fixture A: a REQUIRED section (Issue Tracker) is malformed (rows missing the closing pipe).
# config_migrate MUST abort: no config.toml written, CLAUDE.md untouched, [WARN] names it. ---
cat > "$TMP/A.md" <<'EOF'
# P
## Automation Config

### Issue Tracker
| Key | Value
|------|---------
| Type | youtrack
EOF
cp "$TMP/A.md" "$TMP/A.orig"
a_out="$(config_migrate "$TMP/A.md" "$TMP/outA.toml" 2>&1)"; a_rc=$?
[ "$a_rc" -ne 0 ] || fail "FC-20 (partial): a malformed REQUIRED section must abort (rc!=0), got rc=$a_rc"
[ ! -f "$TMP/outA.toml" ] || fail "FC-20 (partial): config.toml was written despite a malformed required section (half-write forbidden)"
diff -q "$TMP/A.md" "$TMP/A.orig" >/dev/null 2>&1 || fail "FC-20 (partial): CLAUDE.md was modified on abort (must be left untouched)"
contains "$a_out" "issue_tracker" || contains "$a_out" "Issue Tracker" || fail "FC-20 (partial): abort [WARN] does not name the unextractable required section"

# --- Fixture B: all required sections well-formed; only an OPTIONAL section (Metrics) malformed.
# config_migrate writes config.toml with the clean sections, skips Metrics with a [WARN], and the
# produced config.toml passes config_validate (no half-write). ---
cat > "$TMP/B.md" <<'EOF'
# P
## Automation Config

### Issue Tracker
| Key | Value |
|-----|-------|
| Type | youtrack |
| Instance | i |
| Project | P |
| Bug query | q |
| State transitions | a: b |
| On start set | x |

### Source Control
| Key | Value |
|-----|-------|
| Remote | o/r |
| Base branch | main |
| Branch naming | f |

### PR Rules
| Key | Value |
|-----|-------|
| Labels | bug |

### PR Description Template
| Key | Value |
|-----|-------|
| Template | S |

### Build & Test
| Key | Value |
|-----|-------|
| Build command | make |
| Test command | pytest |

### Metrics
| Key | Value
|-----|------
| Output | stdout
EOF
b_out="$(config_migrate "$TMP/B.md" "$TMP/outB.toml" 2>&1)"; b_rc=$?
[ "$b_rc" -eq 0 ] || fail "FC-20 (partial): optional-only malformation must still succeed (rc=$b_rc)"
[ -f "$TMP/outB.toml" ] || fail "FC-20 (partial): config.toml not written when only an optional section is malformed"
produced="$(cat "$TMP/outB.toml")"
contains "$produced" "[issue_tracker]" || fail "FC-20 (partial): required [issue_tracker] missing from output"
contains "$produced" "[metrics]" && fail "FC-20 (partial): malformed [metrics] was written (must be skipped, not half-written)"
contains "$b_out" "metrics" || fail "FC-20 (partial): no [WARN] naming the skipped optional 'metrics' section"
# No half-write: the produced config.toml must pass key-list validation.
config_validate "$TMP/outB.toml" >/dev/null 2>&1 || fail "FC-20 (partial): produced config.toml fails config_validate (half-write leaked an invalid file)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: onboard-migrate-partial-malformed -- required-broken aborts (no write, CLAUDE.md untouched); optional-broken skips+reports and stays valid"
  exit 0
fi
exit 1
