#!/usr/bin/env bash
# ===========================================================================
# Test:     dispatch-hook-tree-detection.sh
# Subject:  core/lib/detect-dispatch-hooks.sh — tree-aware hook detection.
#   The earlier check read ONLY ~/.claude/settings.json, so a dispatch hook
#   wired at the project or project-local scope was reported "not configured"
#   (false negative). Claude Code MERGES the settings tree and hooks COMBINE
#   across scopes, so "wired" must mean "present in ANY scope".
#
#   Asserts:
#     (1) gate wired in USER only            -> GATE_WIRED=1, scope user, Task ok
#     (2) gate+audit wired in LOCAL only      -> detected (the core regression:
#                                                absent from ~/.claude/settings.json)
#     (3) nothing wired                       -> GATE_WIRED=0, AUDIT_WIRED=0
#     (4) gate (local) + audit (user) combine -> both wired, distinct scopes
#     (5) gate present but matcher != "Task"  -> GATE_WIRED=1, GATE_MATCHER_TASK=0
#     (6) disableAllHooks: true               -> DISABLE_ALL_HOOKS=1
#     (7) ONLY the gate is wired              -> AUDIT_WIRED=0 (filename
#                                                discrimination: validate-dispatch.sh
#                                                is NOT a substring of -pre.sh)
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

LIB="$REPO_ROOT/core/lib/detect-dispatch-hooks.sh"
[ -f "$LIB" ] || { echo "FAIL (RED): $LIB missing — helper not implemented" >&2; exit 1; }
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable (primary parser unavailable)" >&2; exit 77; }
# shellcheck disable=SC1090
. "$LIB"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/dht_$$")"
trap 'rm -rf "$WORK"' EXIT

GATE_CMD="/path/to/agent-flow/hooks/validate-dispatch-pre.sh"
AUDIT_CMD="/path/to/agent-flow/hooks/validate-dispatch.sh"

# get_val OUTPUT KEY — pure-bash line extractor (no pipe -> no pipefail/SIGPIPE).
# Strips a trailing CR defensively so the assertion never depends on the
# platform's stdout newline translation.
get_val() {
  local line v
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      "$2="*) v="${line#*=}"; printf '%s' "${v%$'\r'}"; return 0 ;;
    esac
  done <<EOF
$1
EOF
  printf ''
}

# fresh PROJ/HOME pair under a uniquely-named case dir; echoes "<proj> <home>".
mk_case() {
  local d="$WORK/$1"
  mkdir -p "$d/proj/.claude" "$d/home/.claude"
  printf '%s %s' "$d/proj" "$d/home"
}

write_gate_settings() {  # <file> <matcher>
  cat > "$1" <<EOF
{ "hooks": { "PreToolUse": [ { "matcher": "$2",
  "hooks": [ { "type": "command", "command": "$GATE_CMD" } ] } ] } }
EOF
}
write_audit_settings() {  # <file>
  cat > "$1" <<EOF
{ "hooks": { "PostToolUse": [ { "matcher": "Bash",
  "hooks": [ { "type": "command", "command": "$AUDIT_CMD" } ] } ] } }
EOF
}

# (1) gate wired in USER settings only.
read -r P H <<<"$(mk_case c1)"
write_gate_settings "$H/.claude/settings.json" "Task"
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" GATE_WIRED)" = "1" ]        || fail "(1) gate in user not detected: $out"
[ "$(get_val "$out" GATE_SCOPES)" = "user" ]     || fail "(1) gate scope != user: $(get_val "$out" GATE_SCOPES)"
[ "$(get_val "$out" GATE_MATCHER_TASK)" = "1" ]  || fail "(1) Task matcher not recognized"

# (2) gate + audit wired ONLY in project-local — the core regression.
read -r P H <<<"$(mk_case c2)"
cat > "$P/.claude/settings.local.json" <<EOF
{ "hooks": {
  "PreToolUse":  [ { "matcher": "Task", "hooks": [ { "type": "command", "command": "$GATE_CMD" } ] } ],
  "PostToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$AUDIT_CMD" } ] } ]
} }
EOF
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" GATE_WIRED)" = "1" ]   || fail "(2) gate in settings.local.json NOT detected (regression): $out"
[ "$(get_val "$out" GATE_SCOPES)" = "local" ] || fail "(2) gate scope != local: $(get_val "$out" GATE_SCOPES)"
[ "$(get_val "$out" AUDIT_WIRED)" = "1" ]  || fail "(2) audit in settings.local.json NOT detected: $out"
[ "$(get_val "$out" AUDIT_SCOPES)" = "local" ] || fail "(2) audit scope != local"

# (3) nothing wired (empty .claude dirs).
read -r P H <<<"$(mk_case c3)"
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" GATE_WIRED)" = "0" ]  || fail "(3) gate falsely detected when none wired: $out"
[ "$(get_val "$out" AUDIT_WIRED)" = "0" ] || fail "(3) audit falsely detected when none wired: $out"

# (4) gate in LOCAL + audit in USER -> both wired, hooks COMBINE across scopes.
read -r P H <<<"$(mk_case c4)"
write_gate_settings "$P/.claude/settings.local.json" "Task"
write_audit_settings "$H/.claude/settings.json"
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" GATE_WIRED)" = "1" ]    || fail "(4) gate (local) not detected when audit is in user"
[ "$(get_val "$out" GATE_SCOPES)" = "local" ] || fail "(4) gate scope != local"
[ "$(get_val "$out" AUDIT_WIRED)" = "1" ]   || fail "(4) audit (user) not detected when gate is in local"
[ "$(get_val "$out" AUDIT_SCOPES)" = "user" ] || fail "(4) audit scope != user"

# (5) gate present but matcher "Bash" (wrong) -> wired but not Task-ok.
read -r P H <<<"$(mk_case c5)"
write_gate_settings "$H/.claude/settings.json" "Bash"
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" GATE_WIRED)" = "1" ]        || fail "(5) gate-on-wrong-matcher not detected as present"
[ "$(get_val "$out" GATE_MATCHER_TASK)" = "0" ] || fail "(5) wrong matcher should yield GATE_MATCHER_TASK=0: $out"

# (6) disableAllHooks: true is surfaced.
read -r P H <<<"$(mk_case c6)"
cat > "$P/.claude/settings.json" <<EOF
{ "disableAllHooks": true,
  "hooks": { "PreToolUse": [ { "matcher": "Task", "hooks": [ { "type": "command", "command": "$GATE_CMD" } ] } ] } }
EOF
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" DISABLE_ALL_HOOKS)" = "1" ] || fail "(6) disableAllHooks:true not surfaced: $out"

# (7) ONLY the gate wired -> audit must be 0 (filename discrimination).
read -r P H <<<"$(mk_case c7)"
write_gate_settings "$H/.claude/settings.json" "Task"
out="$(detect_dispatch_hooks "$P" "$H")"
[ "$(get_val "$out" AUDIT_WIRED)" = "0" ] || fail "(7) audit falsely detected from a gate-only wiring (substring collision): $out"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: dispatch-hook-tree-detection — gate/audit detected across user+project+local; hooks combine; matcher + disableAllHooks + filename discrimination all correct"
  exit 0
fi
exit 1
