#!/usr/bin/env bash
# Test: limits-pure-bash-no-tomllib
# FC mapped: FC-26 [DEDICATED]
# What it checks:
#   The limits-resolution path -- including the top-precedence
#   customization/{agent}.toml [limits] read -- has NO python3/tomllib/tomli dependency
#   and does NOT route through skills/setup-agents/lib/toml-merge.sh (whose
#   `import tomllib` fails on the real Python 3.10 host, silently dropping the overlay --
#   see design.md section 1.4). Behavioural host-regression guard: the top-tier value
#   must actually apply (not silently fall back to a lower tier) even when tomllib is
#   unavailable. Complements FC-13 (enforce==inject) -- FC-26 asserts the top tier
#   actually applies on the real host.
# Expected RED (pre-impl): core/config-reader.md does not yet document hosting the
#   [limits] read via the pure-bash parser -- fails until Phase 7.
# Expected GREEN (post-impl): core/config-reader.md documents the pure-bash [limits] read
#   with no tomllib dependency, and skills/setup-agents/lib/toml-merge.sh is UNCHANGED
#   (per its NEVER-modify status).
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Pre-impl (already pinned; regression guard) ---
contains_i "$design_content" "fails on 3.10" || contains "$design_content" "import tomllib" \
  || fail "design.md section 1.4 does not describe the tomllib import failure mode on Python 3.10"
contains "$design_content" "NOT modified" || fail "design.md does not state toml-merge.sh is NOT modified"

# --- Implementation target: core/config-reader.md ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains "$reader_content" "tomllib" && fail "FC-26: core/config-reader.md references tomllib on the limits path"
contains "$reader_content" "tomli"   && fail "FC-26: core/config-reader.md references tomli on the limits path"
contains "$reader_content" "skills/setup-agents/lib/toml-merge.sh" && fail "FC-26: core/config-reader.md routes [limits] through toml-merge.sh (forbidden per design.md section 1.4)"
contains_i "$reader_content" "pure-bash" || fail "FC-26: core/config-reader.md does not state the [limits] tier is read by the pure-bash parser"
contains_i "$reader_content" "[limits]" || fail "FC-26: core/config-reader.md does not document reading the [limits] tier at all"

# --- toml-merge.sh must remain untouched / must not be re-purposed as the limits path ---
TOML_MERGE="skills/setup-agents/lib/toml-merge.sh"
if [ -f "$TOML_MERGE" ]; then
  toml_merge_content="$(cat "$TOML_MERGE")"
  contains_i "$toml_merge_content" "limits.*resolution.*single" && fail "FC-26: toml-merge.sh appears to have been modified to host limits single-resolution (NEVER-modify status violated)"
fi

# --- Host-regression behavioural fixture: simulate the 3.10 failure mode ---
CONFIG_BUILD_RETRIES=3
OVERLAY_MAX_BUILD_RETRIES=2
EXPECTED_ON_310_HOST=2   # top tier must apply even when `import tomllib` fails
if [ "$EXPECTED_ON_310_HOST" -eq "$CONFIG_BUILD_RETRIES" ]; then
  fail "fixture sanity: expected top-tier value must differ from config.toml's value to prove no silent fallback"
fi

# TODO(phase-7): once the pure-bash limits resolver exists, run it in an environment where
# `python3 -c "import tomllib"` fails (simulating 3.10) and assert the resolved+injected
# value is 2 (top tier applied) -- i.e. it does NOT silently fall back to 3 or empty.

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: limits-pure-bash-no-tomllib -- limits path documented pure-bash, no tomllib/toml-merge.sh dependency"
  exit 0
fi
exit 1
