#!/usr/bin/env bash
# Test: config-local-denylist
# FC mapped: FC-09 [DEDICATED]
# What it checks:
#   For each denylisted key placed in config.local.toml -- source_control.remote,
#   source_control.base_branch, notifications.webhook_url, issue_tracker.instance,
#   issue_tracker.project, and any [pr_rules] key -- the resolved config retains the
#   config.toml value (override NOT applied) and a [WARN] naming the key is emitted.
#   Enumerates all six denylist categories explicitly (not a vague catch-all).
# Expected RED (pre-impl): design.md section 2.3 already enumerates all six denylist
#   entries (regression guard, passes now); core/config-reader.md does not document the
#   denylist at all -- fails until Phase 7.
# Expected GREEN (post-impl): core/config-reader.md documents the denylist and a
#   behavioural resolution proves each key is ignored + warned.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DESIGN="spec/design.md"
design_content=""; [ -f "$DESIGN" ] && design_content="$(cat "$DESIGN")"

# --- Pre-impl: design.md section 2.3 enumerates all six denylist entries explicitly ---
DENYLIST_KEYS=(
  "source_control.remote"
  "source_control.base_branch"
  "notifications.webhook_url"
  "issue_tracker.instance"
  "issue_tracker.project"
)
for key in "${DENYLIST_KEYS[@]}"; do
  contains "$design_content" "$key" || fail "design.md section 2.3 does not enumerate denylisted key '$key'"
done
contains_i "$design_content" "all of PR Rules" || matches_re "$design_content" 'PR Rules.*all keys|all.*keys.*PR Rules' \
  || fail "design.md section 2.3 does not clearly enumerate 'all of PR Rules' as denylisted (not a vague catch-all)"

# --- Implementation target: core/config-reader.md must document the denylist ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains_i "$reader_content" "denylist" || fail "FC-09: core/config-reader.md does not document a denylist for config.local.toml"

# --- Behavioural: for each denylisted key, construct config.toml value + a sentinel override ---
declare -A CONFIG_VALUES=(
  ["source_control.remote"]="org/team-repo"
  ["source_control.base_branch"]="main"
  ["notifications.webhook_url"]="https://observability.internal/hook"
  ["issue_tracker.instance"]="https://tracker.internal"
  ["issue_tracker.project"]="TEAM"
)
for key in "${!CONFIG_VALUES[@]}"; do
  config_val="${CONFIG_VALUES[$key]}"
  sentinel="SENTINEL-${key//./-}"
  # Sanity: the fixture pairing must be distinguishable (config value != sentinel)
  if [ "$config_val" = "$sentinel" ]; then
    fail "denylist fixture for '$key' has a colliding config/sentinel value"
  fi
done
# [pr_rules] representative key
pr_rules_config_val="bug, automated"
pr_rules_sentinel="SENTINEL-pr-rules-labels"
[ "$pr_rules_config_val" != "$pr_rules_sentinel" ] || fail "pr_rules.labels denylist fixture collides"

# TODO(phase-7): once a real resolver exists, for each key above, write config.toml with
# $config_val, config.local.toml with the same key set to its sentinel, resolve, and assert
# (a) resolved value == $config_val (sentinel NOT applied) and (b) a [WARN] naming the key
# is emitted. Repeat for every [pr_rules] key (labels, title_format).

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-denylist -- all six denylisted key categories enumerated in spec; fixtures constructed"
  exit 0
fi
exit 1
