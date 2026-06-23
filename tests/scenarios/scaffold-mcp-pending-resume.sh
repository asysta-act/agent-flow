#!/bin/bash
# Test: Scaffold MCP pending-resume checkpoint
# Validates: mcp_setup_pending marker written before STOP, post-resume check in SKILL.md,
#            clear-on-success/skip semantics, no false-positive on FRESH runs
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAFFOLD_SKILL="$REPO_ROOT/skills/scaffold/SKILL.md"
STEP_01="$REPO_ROOT/skills/scaffold/steps/01-mode-resolve.md"
SCHEMA="$REPO_ROOT/state/schema.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
. "$REPO_ROOT/tests/lib/assert.sh"

# === WRITE-BEFORE-STOP (marker written before STOP message) ===

# 1. SKILL.md specifies mcp_setup_pending in the "Configure now" block
if ! grep -q 'mcp_setup_pending.*true\|"mcp_setup_pending": true' "$SCAFFOLD_SKILL"; then
  fail "SKILL.md missing mcp_setup_pending:true in Configure-now block"
fi

# 2. SKILL.md specifies mcp_pause_step (not paused_at for stage name)
if ! grep -q 'mcp_pause_step' "$SCAFFOLD_SKILL"; then
  fail "SKILL.md missing mcp_pause_step field (must not reuse paused_at for non-timestamp)"
fi

# 3. SKILL.md specifies status:paused in the checkpoint write
configure_now_line=$(grep -n 'Configure now.*interactive\|interactive.*Configure now\|Configure now.*unreachable' "$SCAFFOLD_SKILL" | head -1 | cut -d: -f1)
if [ -z "$configure_now_line" ]; then
  fail "SKILL.md missing 'Configure now (interactive mode only)' guard"
else
  context=$(sed -n "$configure_now_line,$((configure_now_line + 10))p" "$SCAFFOLD_SKILL")
  if ! matches_re "$context" '"status".*"paused"|status.*paused'; then
    fail "SKILL.md Configure-now block missing status:paused in write payload"
  fi
fi

# 4. SKILL.md specifies webhook before STOP
if [ -n "$configure_now_line" ]; then
  context=$(sed -n "$configure_now_line,$((configure_now_line + 12))p" "$SCAFFOLD_SKILL")
  if ! matches_re "${context,,}" 'pipeline-paused|webhook.*paused|paused.*webhook'; then
    fail "SKILL.md Configure-now block missing pipeline-paused webhook instruction"
  fi
fi

# 5. 01-mode-resolve.md has the same three fields in the write payload
step_configure_line=$(grep -n 'Configure now.*interactive\|interactive.*Configure now\|On.*Configure now' "$STEP_01" | head -1 | cut -d: -f1)
if [ -z "$step_configure_line" ]; then
  fail "01-mode-resolve.md missing 'Configure now (interactive mode only)' block"
else
  context=$(sed -n "$step_configure_line,$((step_configure_line + 8))p" "$STEP_01")
  if ! matches_re "$context" 'mcp_setup_pending.*true|"mcp_setup_pending": true'; then
    fail "01-mode-resolve.md Configure-now block missing mcp_setup_pending:true"
  fi
  if ! contains "$context" "mcp_pause_step"; then
    fail "01-mode-resolve.md Configure-now block missing mcp_pause_step"
  fi
  if ! matches_re "$context" '"status".*"paused"|status.*paused'; then
    fail "01-mode-resolve.md Configure-now block missing status:paused"
  fi
fi

# === POST-RESUME CHECK ===

# 6. SKILL.md post-resume check defines STATE_FILE before reading it
post_resume_line=$(grep -n 'Post-resume MCP checkpoint check' "$SCAFFOLD_SKILL" | head -1 | cut -d: -f1)
if [ -z "$post_resume_line" ]; then
  fail "SKILL.md missing 'Post-resume MCP checkpoint check' section"
else
  context=$(sed -n "$post_resume_line,$((post_resume_line + 15))p" "$SCAFFOLD_SKILL")
  if ! matches_re "$context" 'STATE_FILE=|STATE_FILE ='; then
    fail "SKILL.md post-resume block missing STATE_FILE definition"
  fi
  # 7. File-existence guard before grep
  if ! matches_re "$context" '\[ -f.*STATE_FILE|test -f.*STATE_FILE'; then
    fail "SKILL.md post-resume block missing file-existence guard before grep"
  fi
  # 8. Overrides RESUME_POINT when flag is true
  if ! matches_re "${context,,}" 'resume_point.*0-mcp|override.*resume_point|resume_point = "0-mcp"'; then
    fail "SKILL.md post-resume block missing RESUME_POINT override to 0-mcp"
  fi
fi

# === SKIP PATH CLEARS MARKER ===

# 9. 01-mode-resolve.md Skip path clears mcp_setup_pending
skip_line=$(grep -n 'On.*Skip\|"Skip"\|skip.*marker\|mcp_setup_pending.*false' "$STEP_01" | head -1 | cut -d: -f1)
if [ -z "$skip_line" ]; then
  fail "01-mode-resolve.md missing Skip path with mcp_setup_pending clear"
else
  context=$(sed -n "$skip_line,$((skip_line + 5))p" "$STEP_01")
  if ! matches_re "$context" 'mcp_setup_pending.*false|"mcp_setup_pending": false'; then
    fail "01-mode-resolve.md Skip path missing mcp_setup_pending:false clear"
  fi
fi

# === NO DUPLICATE CLEAR DIRECTIVE ===

# 10. SKILL.md post-resume block documents that clearing is delegated to 01-mode-resolve.md
post_resume_end=$((post_resume_line + 25))
resume_context=$(sed -n "${post_resume_line},${post_resume_end}p" "$SCAFFOLD_SKILL")
if ! matches_re "${resume_context,,}" 'do not clear|handled exclusively|single source of truth|01-mode-resolve'; then
  fail "SKILL.md post-resume block must document that clearing is delegated to 01-mode-resolve.md (single source of truth)"
fi

# === SCHEMA DOCUMENTATION ===

# 11. state/schema.md documents mcp_setup_pending
if ! grep -q 'mcp_setup_pending' "$SCHEMA"; then
  fail "state/schema.md missing documentation for mcp_setup_pending field"
fi

# 12. state/schema.md documents mcp_pause_step
if ! grep -q 'mcp_pause_step' "$SCHEMA"; then
  fail "state/schema.md missing documentation for mcp_pause_step field"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: Scaffold MCP pending-resume checkpoint verified"
exit "$FAIL"
