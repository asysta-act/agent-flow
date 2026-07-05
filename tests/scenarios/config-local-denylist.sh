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
source "$REPO_ROOT/core/lib/config-reader.sh"

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

# --- Behavioural: resolve config.toml + a config.local.toml that tries to override every
# denylisted key with a sentinel. Each denylisted key MUST retain its config.toml value and
# MUST emit a [WARN] naming it. ---
declare -A CONFIG_VALUES=(
  ["source_control.remote"]="org/team-repo"
  ["source_control.base_branch"]="main"
  ["notifications.webhook_url"]="https://observability.internal/hook"
  ["issue_tracker.instance"]="https://tracker.internal"
  ["issue_tracker.project"]="TEAM"
  ["pr_rules.labels"]="bug, automated"
)

TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc09.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
{
  printf '[source_control]\nremote = "org/team-repo"\nbase_branch = "main"\n\n'
  printf '[notifications]\nwebhook_url = "https://observability.internal/hook"\n\n'
  printf '[issue_tracker]\ninstance = "https://tracker.internal"\nproject = "TEAM"\n\n'
  printf '[pr_rules]\nlabels = "bug, automated"\n'
} > "$TMP/config.toml"
{
  printf '[source_control]\nremote = "SENTINEL-remote"\nbase_branch = "SENTINEL-base"\n\n'
  printf '[notifications]\nwebhook_url = "SENTINEL-webhook"\n\n'
  printf '[issue_tracker]\ninstance = "SENTINEL-instance"\nproject = "SENTINEL-project"\n\n'
  printf '[pr_rules]\nlabels = "SENTINEL-labels"\n'
} > "$TMP/config.local.toml"

config_parse "$TMP/config.toml" 0 >/dev/null 2>&1
config_overlay_merge "$TMP/config.local.toml" >/dev/null 2>&1
warns="$CR_WARN"

for key in "${!CONFIG_VALUES[@]}"; do
  expected="${CONFIG_VALUES[$key]}"
  got="$(config_get "$key")"
  [ "$got" = "$expected" ] || fail "FC-09: denylisted '$key' resolved to '$got' (sentinel leaked); expected config.toml value '$expected'"
  contains "$got" "SENTINEL" && fail "FC-09: denylisted '$key' contains a leaked SENTINEL override"
  contains "$warns" "$key" || fail "FC-09: no [WARN] naming denylisted key '$key' was emitted"
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-denylist -- all six denylisted keys retained config.toml value + WARNed (sentinels rejected)"
  exit 0
fi
exit 1
