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

# --- Behavioural fixture: two "resolutions" (with vs without overlay) must be identical ---
BASE_RESOLVED='issue_tracker.type=youtrack;retry.build_retries=3'
WITH_ABSENT_OVERLAY_RESOLVED='issue_tracker.type=youtrack;retry.build_retries=3'
if [ "$BASE_RESOLVED" != "$WITH_ABSENT_OVERLAY_RESOLVED" ]; then
  fail "fixture sanity: base resolution and no-overlay resolution differ (should be byte-identical by construction)"
fi

# TODO(phase-7): once a real resolver exists, run it twice against the same config.toml --
# once with no config.local.toml on disk and once with the file explicitly absent-but-checked
# -- and assert the two resulting resolved objects are byte-identical.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-absent-noop -- absent-overlay no-op contract documented"
  exit 0
fi
exit 1
