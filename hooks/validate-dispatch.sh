#!/usr/bin/env bash
# hooks/validate-dispatch.sh
# PostToolUse advisory hook: dispatched_at presence audit.
#
# Invoked automatically by Claude Code after each tool use.
# Reads state.json, checks whether each pipeline stage has a dispatched_at
# timestamp, and appends one audit-log line per stage to dispatch-audit.log.
#
# EXIT: always 0 (advisory-only; PostToolUse cannot block tool execution).
# LOG:  .agent-flow/dispatch-audit.log (append-only, plain text).
#
# NOT A SECURITY CONTROL: this hook (a) is not auto-installed — operators
# must opt in via ~/.claude/settings.json (see docs/guides/dispatch-enforcement.md)
# — and (b) even when installed, PostToolUse fires after the tool already
# ran, so it cannot block or undo anything. It does NOT technically enforce
# any agent "NEVER" constraint (e.g. publisher's "NEVER push to main/development
# directly") — those remain prompt-level instructions only. Operators who need
# a real backstop against direct pushes or destructive actions MUST enable
# server-side branch protection (required PR review + status checks) on the
# repository; see SECURITY.md "Known Limitations" for full operator guidance.
#
# Security contracts:
#   - STAGES are hardcoded; never derived from state.json field names
#   - All jq calls redirect stderr to /dev/null
#   - jq -e used for boolean branching

set -uo pipefail   # NOT -e: script must not exit on jq miss

# ---------------------------------------------------------------------------
# Hardcoded STAGES whitelist (no dynamic discovery)
# ---------------------------------------------------------------------------
STAGES=(triage code_analysis reproduce_browser fixer_reviewer smoke_check test e2e_test browser_verification acceptance_gate publisher)

# ---------------------------------------------------------------------------
# Source core/lib/stage-invariant.sh for dispatch witness audit.
# Resolves plugin-relative or repo-relative; silent no-op if not found.
# ---------------------------------------------------------------------------
STAGE_LIB="${CLAUDE_PLUGIN_DIR:-$(dirname "$0")/..}/core/lib/stage-invariant.sh"
if [ -f "$STAGE_LIB" ]; then
  # shellcheck source=/dev/null
  source "$STAGE_LIB"  # source core/lib/stage-invariant.sh
fi

# ---------------------------------------------------------------------------
# Resolve ISO timestamp via redirect+read (avoids command substitution).
# ---------------------------------------------------------------------------
_HOOK_TMPDIR="${TMPDIR:-/tmp}"
_TS_TMP="${_HOOK_TMPDIR}/.ceos_hook_ts_$$"
ISO_TS="unknown"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$_TS_TMP" 2>/dev/null || true
IFS= read -r ISO_TS < "$_TS_TMP" 2>/dev/null || true
rm -f "$_TS_TMP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Resolve audit log and state.json paths.
# ---------------------------------------------------------------------------
AUDIT_LOG="${CEOS_AUDIT_LOG:-.agent-flow/dispatch-audit.log}"
STATE_JSON="${CEOS_STATE_JSON:-}"

if [ -z "$STATE_JSON" ]; then
  latest=""
  for candidate in .agent-flow/*/state.json; do
    [ -f "$candidate" ] || continue
    latest="$candidate"
  done
  STATE_JSON="$latest"
fi

# ---------------------------------------------------------------------------
# Detect bypassPermissions mode from stdin JSON (non-blocking read).
# ---------------------------------------------------------------------------
BYPASS_MODE=0
if [ ! -t 0 ]; then
  stdin_json=""
  IFS= read -r -t 1 stdin_json 2>/dev/null || true
  if [ -n "$stdin_json" ]; then
    _PM_TMP="${_HOOK_TMPDIR}/.ceos_hook_pm_$$"
    printf '%s' "$stdin_json" | jq -r '.permission_mode // empty' > "$_PM_TMP" 2>/dev/null || true
    perm_mode=""
    IFS= read -r perm_mode < "$_PM_TMP" 2>/dev/null || true
    rm -f "$_PM_TMP" 2>/dev/null || true
    if [ "$perm_mode" = "bypassPermissions" ]; then
      BYPASS_MODE=1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# If no state.json found, not a pipeline run -- exit cleanly.
# ---------------------------------------------------------------------------
if [ -z "$STATE_JSON" ] || [ ! -f "$STATE_JSON" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Ensure audit log directory exists.
# ---------------------------------------------------------------------------
audit_dir="${AUDIT_LOG%/*}"
if [ "$audit_dir" != "$AUDIT_LOG" ] && [ -n "$audit_dir" ]; then
  mkdir -p "$audit_dir" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Note bypass mode in audit log.
# ---------------------------------------------------------------------------
if [ "$BYPASS_MODE" = "1" ]; then
  printf '%s [INFO] bypassPermissions mode detected -- audit proceeds normally\n' "$ISO_TS" >> "$AUDIT_LOG" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Check each stage for dispatched_at presence.
# STAGES array is hardcoded; stage names are never user-controlled.
# Bash-only grep probe (DP1): strict regex rejects null literal AND
# stringified-null ("null") — only matches when value starts with a digit
# (i.e., a valid ISO timestamp like "2026-04-30T12:00:00Z").
# Assumes pretty-printed (2-space indent) state.json per A-5.
# ---------------------------------------------------------------------------
for stage in "${STAGES[@]}"; do
  verdict="MISSING"
  if grep -A 4 "\"${stage}\"" "$STATE_JSON" 2>/dev/null | grep -qE '"dispatched_at"[[:space:]]*:[[:space:]]*"[0-9]'; then
    verdict="OK"
  fi
  printf '%s %s %s\n' "$ISO_TS" "$stage" "$verdict" >> "$AUDIT_LOG" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Dispatch-witness audit loop.
# Emits one WITNESS_OK / WITNESS_MISSING / WITNESS_MISMATCH line per stage.
# Strict mode: CEOS_STRICT_DISPATCH=1 causes exit 2 on MISMATCH.
# MISSING is NEVER exit-2-worthy (legitimate skips produce MISSING).
# ---------------------------------------------------------------------------
if declare -F check_dispatch_witness >/dev/null 2>&1; then
  for stage in "${STAGES[@]}"; do
    w_verdict="$(check_dispatch_witness "$stage" "$STATE_JSON" 2>/dev/null || true)"
    [ -n "$w_verdict" ] || w_verdict="WITNESS_MISSING"
    emit_witness_audit "$stage" "$w_verdict" "$AUDIT_LOG"
  done

  if [ "${CEOS_STRICT_DISPATCH:-0}" = "1" ]; then
    if grep -qE ' WITNESS_MISMATCH$' "$AUDIT_LOG" 2>/dev/null; then
      exit 2
    fi
  fi
fi

# Exit 0 ALWAYS -- advisory mode.
exit 0
