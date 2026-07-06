#!/usr/bin/env bash
# Test: config-local-absent-noop
# FC mapped: FC-12
# What it checks:
#   With no config.local.toml present, the resolved config equals config.toml merged
#   over plugin defaults, unchanged (no-op). REQ-21.
# Expected RED (pre-impl): core/config-reader.md does not document config.local.toml's
#   absence-is-a-no-op contract yet.
# Expected GREEN (post-impl): core/config-reader.md states the no-op contract, and a
#   behavioural resolution with/without an (absent) overlay yields byte-identical output.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"
source "$REPO_ROOT/core/lib/config-reader.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
REQS="spec/requirements.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"
reqs_content="";   [ -f "$REQS" ]   && reqs_content="$(cat "$REQS")"

# --- Pre-impl (already pinned; regression guard) ---
contains "$reqs_content" "REQ-21" || fail "requirements.md missing REQ-21 (absent overlay is a no-op)"
contains_i "$design_content" "no-op" || fail "design.md section 2.1 does not state the absent-overlay no-op contract"
contains "$design_content" "Absent overlay" || fail "design.md does not explicitly discuss the absent-overlay case"

# --- Implementation target ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains "$reader_content" "config.local.toml" || fail "FC-12: core/config-reader.md does not mention config.local.toml (cannot document its absence as a no-op)"

# --- Behavioural: resolve the same config.toml twice -- once WITHOUT calling overlay merge,
# once calling config_overlay_merge against an ABSENT config.local.toml -- and assert the two
# resolved dumps are byte-identical (absent overlay is a strict no-op). ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc12.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
{
  printf '[issue_tracker]\ntype = "youtrack"\ninstance = "i"\nproject = "P"\nbug_query = "q"\nstate_transitions = "a: b"\non_start_set = "x"\n\n'
  printf '[source_control]\nremote = "o/r"\nbase_branch = "main"\nbranch_naming = "f"\n\n'
  printf '[pr_rules]\nlabels = "bug"\n\n'
  printf '[pr_description_template]\ntemplate = """\nS\n"""\n\n'
  printf '[build_and_test]\nbuild_command = "make"\ntest_command = "pytest"\n\n'
  printf '[retry_limits]\nbuild_retries = 3\n'
} > "$TMP/config.toml"

config_parse "$TMP/config.toml" >/dev/null 2>&1
base_dump="$(config_dump)"

config_parse "$TMP/config.toml" >/dev/null 2>&1
config_overlay_merge "$TMP/config.local.toml" >/dev/null 2>&1   # file does NOT exist -> no-op
noop_dump="$(config_dump)"

[ "$base_dump" = "$noop_dump" ] || fail "FC-12: resolved config changed after merging an ABSENT config.local.toml (should be byte-identical no-op)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-absent-noop -- absent overlay is a byte-identical no-op (resolved dumps match)"
  exit 0
fi
exit 1
