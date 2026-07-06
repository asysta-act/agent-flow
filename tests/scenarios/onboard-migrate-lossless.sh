#!/usr/bin/env bash
# Test: onboard-migrate-lossless
# FC mapped: FC-20
# What it checks:
#   /onboard --migrate extracts inline Markdown tables into config.toml losslessly (all
#   23 sections mapped) and rewrites CLAUDE.md's `## Automation Config` section down to
#   the 1-2 line pointer.
# Expected RED (pre-impl): skills/onboard/SKILL.md's argument-hint currently lists only
#   [--fresh] [--update] -- no --migrate flag exists yet, and no migration transform is
#   documented.
# Expected GREEN (post-impl): SKILL.md documents --migrate, the extraction map (23
#   sections), and the CLAUDE.md pointer rewrite.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SKILL="skills/onboard/SKILL.md"
skill_content=""; [ -f "$SKILL" ] && skill_content="$(cat "$SKILL")"
[ -f "$SKILL" ] || fail "$SKILL not found"

contains "$skill_content" "--migrate" || fail "FC-20: $SKILL does not document a --migrate flag"
contains "$skill_content" ".agent-flow/config.toml" || fail "FC-20: $SKILL does not state --migrate writes .agent-flow/config.toml"
contains_i "$skill_content" "pointer" || fail "FC-20: $SKILL does not state CLAUDE.md is rewritten to a pointer after migration"

# --- Design-level lossless map (regression guard: already pinned) ---
DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
contains "$design_content" "Total: **5 required + 18 optional = 23**" || contains_i "$design_content" "5 required + 18 optional" \
  || fail "design.md section 4 does not state the 23-section (5 required + 18 optional) lossless map"

# --- Behavioural: run the reference config_migrate transform against a legacy CLAUDE.md and
# assert (a) every source section maps to a [section] with its keys (lossless, no drops),
# (b) section-name mapping is correct ("Build & Test" -> [build_and_test]), and (c) the
# rewritten CLAUDE.md `## Automation Config` section is a pointer with zero table rows. ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc20l.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/CLAUDE.md" <<'EOF'
# Legacy Project

## Automation Config

### Issue Tracker
| Key | Value |
|-----|-------|
| Type | youtrack |
| Bug query | project: X |

### Source Control
| Key | Value |
|-----|-------|
| Remote | org/repo |
| Base branch | main |

### PR Rules
| Key | Value |
|-----|-------|
| Labels | bug |

### PR Description Template
| Key | Value |
|-----|-------|
| Template | ## Summary {summary} |

### Build & Test
| Key | Value |
|-----|-------|
| Build command | make |
| Test command | pytest |

### Retry Limits
| Key | Value |
|-----|-------|
| Build retries | 3 |

### Metrics
| Key | Value |
|-----|-------|
| Output | stdout |

## Downstream Section

Preserved.
EOF

config_migrate "$TMP/CLAUDE.md" "$TMP/.agent-flow/config.toml" >/dev/null 2>&1; mig_rc=$?
[ "$mig_rc" -eq 0 ] || fail "FC-20: config_migrate returned non-zero (rc=$mig_rc) on a well-formed legacy block"
[ -f "$TMP/.agent-flow/config.toml" ] || fail "FC-20: config.toml was not written"

produced="$(cat "$TMP/.agent-flow/config.toml" 2>/dev/null)"
# Lossless: every legacy ### section must appear as a [section] header (7 sections in the fixture).
for sec in issue_tracker source_control pr_rules pr_description_template build_and_test retry_limits metrics; do
  contains "$produced" "[$sec]" || fail "FC-20: produced config.toml is missing [$sec] (section silently dropped — not lossless)"
done
n_out="$(grep -c '^\[' "$TMP/.agent-flow/config.toml")"
[ "$n_out" -eq 7 ] || fail "FC-20: produced $n_out sections, expected 7 (one per legacy ### subsection — lossless)"
# Key mapping correctness.
contains "$produced" 'type = "youtrack"' || fail "FC-20: issue_tracker.type key not mapped losslessly"
contains "$produced" 'base_branch = "main"' || fail "FC-20: 'Base branch' did not map to base_branch"
contains "$produced" 'build_command = "make"' || fail "FC-20: 'Build command' under 'Build & Test' did not map to build_command"
matches_re "$produced" 'build_retries = 3' || fail "FC-20: integer 'Build retries' 3 did not round-trip as an int"

# Pointer rewrite: the CLAUDE.md ## Automation Config section must be pointer-only.
ac_section="$(awk '/^## Automation Config/{p=1;next} p&&/^## /{p=0} p' "$TMP/CLAUDE.md")"
contains "$ac_section" ".agent-flow/config.toml" || fail "FC-20: rewritten ## Automation Config lacks the pointer to .agent-flow/config.toml"
matches_re "$ac_section" '^\| .* \| .* \|' && fail "FC-20: rewritten ## Automation Config still contains | Key | Value | table rows"
grep -q '^## Downstream Section' "$TMP/CLAUDE.md" || fail "FC-20: downstream section after Automation Config was not preserved"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: onboard-migrate-lossless -- 7/7 legacy sections mapped losslessly + CLAUDE.md rewritten to pointer-only"
  exit 0
fi
exit 1
