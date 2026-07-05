#!/usr/bin/env bash
# Test: config-local-denylist-project-variant  [HIDDEN]
# FC mapped: FC-09 [DEDICATED] -- mandatory hidden variant
# What it checks:
#   The SAME denylist-leak invariant as the visible tests/config-local-denylist.sh
#   scenario, but centered on a DIFFERENT denylisted key so an implementation that only
#   special-cases the visible test's most-emphasized key cannot pass by accident:
#     visible emphasis: enumerates all six categories generically (remote, base_branch,
#       webhook_url, instance, project, pr_rules.*) with equal weight
#     hidden focus:      notifications.webhook_url SPECIFICALLY -- design.md itself
#       documents this key's rationale as "prevents personal-URL leakage / SSRF surface",
#       making it the single highest-value key to prove is actually denylisted rather
#       than just enumerated -- PLUS a [pr_rules] key OTHER than 'labels' (title_format)
#       to prove the "all of PR Rules" denylist clause is not narrowly interpreted as
#       "labels only".
# Expected RED (pre-impl): core/config-reader.md does not document a denylist for
#   config.local.toml at all yet.
# Expected GREEN (post-impl): notifications.webhook_url and pr_rules.title_format
#   overrides in config.local.toml are both ignored + warned.
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

# --- Pre-impl: design.md must specifically enumerate notifications.webhook_url (not just
# 'Notifications' generically) and the blanket PR Rules clause ---
contains "$design_content" "notifications.webhook_url" || fail "design.md section 2.3 does not enumerate notifications.webhook_url as denylisted"
matches_re "$design_content" 'PR Rules.*all keys|all.*keys.*PR Rules' \
  || fail "design.md section 2.3 does not clearly denylist ALL of PR Rules (not just Labels)"

# --- Implementation target ---
READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
contains_i "$reader_content" "denylist" || fail "FC-09 (hidden/webhook variant): core/config-reader.md does not document a denylist for config.local.toml"

# --- Distinct hidden fixture: notifications.webhook_url + pr_rules.title_format (NOT labels) ---
CONFIG_WEBHOOK_URL="https://ci.internal.example.com/hooks/agent-flow"
SENTINEL_WEBHOOK_URL="https://attacker.example.net/exfil"
[ "$CONFIG_WEBHOOK_URL" != "$SENTINEL_WEBHOOK_URL" ] || fail "hidden-fixture sanity: webhook_url config/sentinel collide"

CONFIG_TITLE_FORMAT="{issue-id}-{mode}-{summary}"
SENTINEL_TITLE_FORMAT="{issue-id}: PERSONAL OVERRIDE {summary}"
[ "$CONFIG_TITLE_FORMAT" != "$SENTINEL_TITLE_FORMAT" ] || fail "hidden-fixture sanity: title_format config/sentinel collide"

# Distinctness guard vs. the visible scenario's own notifications.webhook_url fixture
# value ("https://observability.internal/hook") -- this hidden variant's fixture must
# probe a DIFFERENT literal value for the SAME key, not silently reuse the visible test's.
if [ "$CONFIG_WEBHOOK_URL" = "https://observability.internal/hook" ]; then
  fail "hidden-fixture sanity: reused the visible scenario's notifications.webhook_url fixture value"
fi

# --- Behavioural: resolve config.toml + config.local.toml overriding BOTH keys with sentinels;
# both must retain the config.toml value AND emit a [WARN]. ---
TMP="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/fc09h.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
{
  printf '[notifications]\nwebhook_url = "%s"\n\n' "$CONFIG_WEBHOOK_URL"
  printf '[pr_rules]\ntitle_format = "%s"\n' "$CONFIG_TITLE_FORMAT"
} > "$TMP/config.toml"
{
  printf '[notifications]\nwebhook_url = "%s"\n\n' "$SENTINEL_WEBHOOK_URL"
  printf '[pr_rules]\ntitle_format = "%s"\n' "$SENTINEL_TITLE_FORMAT"
} > "$TMP/config.local.toml"

config_parse "$TMP/config.toml" 0 >/dev/null 2>&1
config_overlay_merge "$TMP/config.local.toml" >/dev/null 2>&1
warns="$CR_WARN"

got_webhook="$(config_get notifications.webhook_url)"
[ "$got_webhook" = "$CONFIG_WEBHOOK_URL" ] || fail "FC-09 (hidden): notifications.webhook_url resolved to '$got_webhook' (sentinel leaked); expected '$CONFIG_WEBHOOK_URL'"
contains "$got_webhook" "attacker" && fail "FC-09 (hidden): webhook_url leaked the attacker sentinel"
contains "$warns" "notifications.webhook_url" || fail "FC-09 (hidden): no [WARN] naming notifications.webhook_url"

got_title="$(config_get pr_rules.title_format)"
[ "$got_title" = "$CONFIG_TITLE_FORMAT" ] || fail "FC-09 (hidden): pr_rules.title_format resolved to '$got_title' (sentinel leaked); expected '$CONFIG_TITLE_FORMAT' — proves 'all of PR Rules' is denylisted, not just labels"
contains "$warns" "pr_rules.title_format" || fail "FC-09 (hidden): no [WARN] naming pr_rules.title_format (the blanket PR Rules denylist must cover title_format)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: config-local-denylist-project-variant -- webhook_url + pr_rules.title_format both rejected + WARNed (distinct keys)"
  exit 0
fi
exit 1
