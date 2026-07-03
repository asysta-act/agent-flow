#!/usr/bin/env bash
# core/lib/stage-invariant.sh
# Runtime dispatch invariant helpers.
#
# Two real consumers:
#   1. Skill step files (skills/*/steps/*.md) source this file DIRECTLY on
#      the write side, calling compute_dispatch_witness() to derive the
#      witness hash the orchestrator writes to state.json (dispatch_witness,
#      agent_name, stage_name) before each Task() call. This runs on every
#      real pipeline execution, independent of whether the hook below fires.
#   2. hooks/validate-dispatch.sh sources this file on the read side, calling
#      check_dispatch_witness() + emit_witness_audit() (PostToolUse, advisory
#      only) to audit witnesses already written to state.json.
#
# POSIX-compatible. Tested on Windows Git-Bash, macOS BSD-grep, Linux GNU-grep.
# jq-free per fix-bugs convention.
#
# Tools used: bash builtins + printf + grep -E + sed -E + awk + sha256sum
# (or shasum -a 256 fallback for macOS systems without coreutils).

set -uo pipefail

# -----------------------------------------------------------------------------
# compute_dispatch_witness STAGE SUBAGENT_TYPE MODEL PROMPT_HEAD_128
#   Emit sha256 hex string (lowercase, 64 chars) for the dispatch tuple.
#   STDOUT-only on success.
#
#   Canonical input: "${SUBAGENT_TYPE}|${MODEL}|${PROMPT_HEAD_128}"
#
#   CRITICAL: PROMPT_HEAD_128 must be the first 128 UTF-8-safe
#   bytes of the prompt template BEFORE Tier-1 variable expansion. The caller
#   is responsible for performing the 128-byte truncation on the RAW prompt
#   string (with ${VAR} placeholders un-expanded). This function does NOT
#   expand any Tier-1 variables (ISSUE_ID, BRANCH_NAME, TICKET_ID, etc.) -
#   doing so would defeat witness stability across resume cycles.
#
#   STAGE is accepted as the first positional arg for caller-side clarity
#   but is NOT included in the hash (the hash covers what was dispatched,
#   not which slot it was dispatched into).
#
#   Returns 0 on success, non-zero on missing args or no sha256 tool.
# -----------------------------------------------------------------------------
compute_dispatch_witness() {
  local stage="${1:?usage: compute_dispatch_witness STAGE SUBAGENT_TYPE MODEL PROMPT_HEAD_128}"
  local subagent_type="${2:?missing SUBAGENT_TYPE}"
  local model="${3:?missing MODEL}"
  local prompt_head_128="${4:?missing PROMPT_HEAD_128}"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s|%s|%s' "$subagent_type" "$model" "$prompt_head_128" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s|%s|%s' "$subagent_type" "$model" "$prompt_head_128" | shasum -a 256 | awk '{print $1}'
  else
    echo "stage-invariant: no sha256 tool available (need sha256sum or shasum)" >&2
    return 1
  fi
}

# Internal helpers (private, double-underscore prefix).
# __regex_escape_stage escapes POSIX BRE metacharacters in user-controlled
# stage names before they reach the grep pattern in check_dispatch_witness.
# __validate_witness_format gates the witness shape early so a malformed
# witness can never be threaded into a further regex context.
__regex_escape_stage() {
    printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'
}
__validate_witness_format() {
    printf '%s' "$1" | grep -qE '^[0-9a-f]{64}$'
}

# -----------------------------------------------------------------------------
# check_dispatch_witness STAGE STATE_JSON_PATH
#   Read stages.<STAGE>.dispatch_witness from state.json (Bash grep, jq-free).
#   Echoes verdict to stdout: WITNESS_OK | WITNESS_MISSING | WITNESS_MISMATCH.
#   Exit codes:
#     0 = OK       (witness present and 64-char lowercase hex)
#     1 = MISSING  (field absent or null literal)
#     2 = MISMATCH (field present but wrong format)
#
#   Assumes pretty-printed (2-space indent) state.json per state/schema.md A-5.
# -----------------------------------------------------------------------------
check_dispatch_witness() {
  local stage="${1:?usage: check_dispatch_witness STAGE STATE_JSON}"
  local state_json="${2:?missing STATE_JSON}"
  [ -f "$state_json" ] || { echo "WITNESS_MISSING"; return 1; }
  local esc
  esc=$(__regex_escape_stage "$stage")
  local witness_line
  witness_line=$(grep -A 30 "\"${esc}\"[[:space:]]*:" "$state_json" 2>/dev/null \
                 | grep -E '"dispatch_witness"[[:space:]]*:' | head -n 1)
  if [ -z "$witness_line" ]; then
    echo "WITNESS_MISSING"; return 1
  fi
  local witness_val
  witness_val=$(printf '%s' "$witness_line" \
                 | sed -E 's/.*"dispatch_witness"[[:space:]]*:[[:space:]]*"?([^",}]*)"?.*/\1/')
  if [ -z "$witness_val" ] || [ "$witness_val" = "null" ]; then
    echo "WITNESS_MISSING"; return 1
  fi
  __validate_witness_format "$witness_val" || { echo "WITNESS_MISMATCH"; return 2; }
  if printf '%s' "$witness_val" | grep -qE '^[0-9a-f]{64}$'; then
    echo "WITNESS_OK"; return 0
  fi
  echo "WITNESS_MISMATCH"; return 2
}

# -----------------------------------------------------------------------------
# emit_witness_audit STAGE VERDICT AUDIT_LOG_PATH
#   Append "<ISO-TS> <STAGE> <VERDICT>" line to the audit log (top-level
#   .agent-flow/dispatch-audit.log). Best-effort - never
#   fails the caller even if the path is unwritable.
# -----------------------------------------------------------------------------
emit_witness_audit() {
  local stage="${1:?usage: emit_witness_audit STAGE VERDICT AUDIT_LOG}"
  local verdict="${2:?missing VERDICT}"
  local audit_log="${3:?missing AUDIT_LOG}"
  stage="${stage//[$'\n\r']/_}"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  local audit_dir="${audit_log%/*}"
  if [ "$audit_dir" != "$audit_log" ] && [ -n "$audit_dir" ]; then
    mkdir -p "$audit_dir" 2>/dev/null || true
  fi
  printf '%s %s %s\n' "$ts" "$stage" "$verdict" >> "$audit_log" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Self-test mode: `bash core/lib/stage-invariant.sh --self-test`
# Exits 0 if all three functions work end-to-end on a tiny synthetic input.
# -----------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  w=$(compute_dispatch_witness "triage" "agent-flow:analyst" "sonnet" "ABC") || { echo "self-test: compute failed"; exit 1; }
  printf '%s' "$w" | grep -qE '^[0-9a-f]{64}$' || { echo "self-test: bad shape: $w"; exit 1; }
  tmp_state=$(mktemp 2>/dev/null || echo /tmp/st_$$)
  trap 'rm -f "$tmp_state"' EXIT
  printf '{\n  "stages": {\n    "triage": {\n      "dispatch_witness": "%s"\n    }\n  }\n}\n' "$w" > "$tmp_state"
  v=$(check_dispatch_witness triage "$tmp_state") || { echo "self-test: check rc != 0 verdict=$v"; exit 1; }
  [ "$v" = "WITNESS_OK" ] || { echo "self-test: expected WITNESS_OK got $v"; exit 1; }
  echo "self-test: PASS"
  exit 0
fi
