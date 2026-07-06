#!/usr/bin/env bash
# Test: toml-parser-malformed-warn
# FC mapped: FC-05 [DEDICATED]
# What it checks:
#   Given a config.toml with a valid required set plus a malformed OPTIONAL section
#   (unterminated """, or a garbage scalar), the parser exits 0, emits a [WARN] naming
#   the section, applies that section's default, and NEVER crashes. Includes a
#   \r-terminated-line (MSYS2/CRLF) fixture case per the task brief.
# Expected RED (pre-impl): core/config-reader.md's current Failure Handling section
#   describes Markdown-table malformation ("table has wrong columns"), not TOML
#   malformation -- the TOML-specific WARN+default+no-crash contract is absent today.
# Expected GREEN (post-impl): core/config-reader.md documents the TOML malformed-optional
#   degradation (design.md section 1.3 / REQ-13) and the fixture below is exercised by a
#   real pure-bash reader (Phase 7) without crashing.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

READER="core/config-reader.md"
DESIGN="spec/design.md"
REQS="spec/requirements.md"

reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
reqs_content="";   [ -f "$REQS" ]   && reqs_content="$(cat "$REQS")"

# --- Spec commitment (already pinned; regression guard) ---
contains_i "$design_content" "never crash" || fail "design.md section 1.3 does not state 'never crash' for malformed optional TOML"
contains "$design_content" "[WARN]" || fail "design.md does not show the [WARN] + default degradation format"
contains "$reqs_content" "REQ-13" || fail "requirements.md missing REQ-13 (malformed optional input degrades, never crashes)"
matches_re "$design_content" 'Strip a trailing.*\\r' || fail "design.md section 1.2 step 1 does not document stripping a trailing \\r (MSYS2/CRLF discipline)"

# --- Implementation target: core/config-reader.md Failure Handling must adopt the TOML contract ---
contains "$reader_content" "[WARN]" || fail "FC-05: core/config-reader.md Failure Handling does not use the [WARN] token"
contains_i "$reader_content" "toml" || fail "FC-05: core/config-reader.md Failure Handling section does not mention TOML-specific malformation (unterminated \"\"\", garbage scalar)"

# --- Fixture: malformed-optional config.toml with a \r-terminated line (MSYS2 case) ---
FIXTURE_DIR="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/toml-malformed-warn.$$")"
mkdir -p "$FIXTURE_DIR" 2>/dev/null || true
FIXTURE="$FIXTURE_DIR/config.toml"
{
  printf '[issue_tracker]\r\n'
  printf 'type = "github"\r\n'
  printf 'instance = "https://github.com"\r\n'
  printf 'project = "acme/repo"\r\n'
  printf 'bug_query = "is:issue is:open label:bug"\r\n'
  printf 'state_transitions = "In Progress: In Progress"\r\n'
  printf 'on_start_set = "In Progress"\r\n'
  printf '\r\n'
  printf '[metrics]\r\n'
  printf 'output = """\r\n'
  printf 'unterminated multi-line block (missing closing triple-quote)\r\n'
} > "$FIXTURE"
[ -f "$FIXTURE" ] || fail "could not construct the malformed-optional + \\r-terminated-line fixture"
if [ -f "$FIXTURE" ]; then
  # NOTE: grep -F on this platform can silently treat CRLF as a line terminator and never
  # match a lone \r, so detection uses bash's own (SIGPIPE-safe) case-pattern match instead.
  fixture_bytes="$(cat "$FIXTURE")"
  contains "$fixture_bytes" $'\r' || fail "fixture does not actually contain \\r-terminated lines (MSYS2 case not represented)"
fi

# --- Behavioural: PARSE the fixture with the reference resolver. strict=0 isolates the
# optional-malformed degradation (required-section absence is FC-21). Must NOT crash: exit 0,
# emit a [WARN] naming "metrics", and leave metrics.output unset so its default applies. ---
parse_out="$(config_parse "$FIXTURE" 0 2>&1)"; parse_rc=$?
config_parse "$FIXTURE" 0 >/dev/null 2>&1   # repopulate CR_CFG for the getter below
[ "$parse_rc" -eq 0 ] || fail "FC-05: config_parse crashed / non-zero (rc=$parse_rc) on a malformed OPTIONAL section — must degrade, never crash"
contains "$parse_out" "[WARN]" || fail "FC-05: no [WARN] emitted for the unterminated \"\"\" block"
contains "$parse_out" "metrics" || fail "FC-05: the [WARN] does not name the malformed section 'metrics'"
[ -z "$(config_get metrics.output)" ] || fail "FC-05: metrics.output should be unset (default applies) after the unterminated block was rejected"

rm -rf "$FIXTURE_DIR" 2>/dev/null || true

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-parser-malformed-warn -- unterminated \"\"\" under [metrics] parsed: exit 0 + [WARN] metrics + default applied"
  exit 0
fi
exit 1
