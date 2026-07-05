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
source "$REPO_ROOT/core/lib/config-reader.sh"

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

# --- Behavioural: run config_migrate twice against the SAME legacy CLAUDE.md. The first run
# writes config.toml; the second run (no --force) must NOT clobber -- it warns "already exists"
# and returns non-zero, leaving config.toml byte-identical (idempotence / never-clobber). ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc20i.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/CLAUDE.md" <<'EOF'
# P
## Automation Config

### Issue Tracker
| Key | Value |
|-----|-------|
| Type | youtrack |

### Source Control
| Key | Value |
|-----|-------|
| Remote | o/r |

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
EOF

config_migrate "$TMP/CLAUDE.md" "$TMP/out.toml" >/dev/null 2>&1; first_rc=$?
[ "$first_rc" -eq 0 ] || fail "FC-20 (idempotence): first migrate returned non-zero (rc=$first_rc)"
[ -f "$TMP/out.toml" ] || fail "FC-20 (idempotence): first migrate did not write config.toml"
before="$(cat "$TMP/out.toml")"

second_out="$(config_migrate "$TMP/CLAUDE.md" "$TMP/out.toml" 2>&1)"; second_rc=$?
[ "$second_rc" -ne 0 ] || fail "FC-20 (idempotence): second migrate returned 0 (must not silently overwrite an existing config.toml)"
contains "$second_out" "already exists" || fail "FC-20 (idempotence): second migrate did not warn that config.toml already exists"
after="$(cat "$TMP/out.toml")"
[ "$before" = "$after" ] || fail "FC-20 (idempotence): config.toml changed on the second run (must be byte-identical — no clobber, no duplicate sections)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: onboard-migrate-idempotence -- second --migrate warns + refuses to clobber; config.toml byte-identical"
  exit 0
fi
exit 1
