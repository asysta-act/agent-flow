#!/bin/bash
# Test: Scaffold MCP chicken-and-egg fix
# Validates: init CLI flags, scaffold Step 0-MCP interactive menu, resume auto-recheck
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
INIT_SKILL="$REPO_ROOT/skills/setup-mcp/SKILL.md"
SCAFFOLD_SKILL="$REPO_ROOT/skills/scaffold/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

# === INIT CLI FLAGS (task-001) ===

# 1. Init argument-hint includes --tracker-type
if ! grep -q '\-\-tracker-type' "$INIT_SKILL"; then
  fail "init SKILL.md missing --tracker-type flag"
fi

# 2. Init argument-hint includes --tracker-instance
if ! grep -q '\-\-tracker-instance' "$INIT_SKILL"; then
  fail "init SKILL.md missing --tracker-instance flag"
fi

# 3. Init argument-hint includes --sc-remote
if ! grep -q '\-\-sc-remote' "$INIT_SKILL"; then
  fail "init SKILL.md missing --sc-remote flag"
fi

# 4. Init has Step 0 (Parameter Override) before Step 1
step0_line=$(grep -n "Step 0.*Parameter Override\|Parameter Override" "$INIT_SKILL" | head -1 | cut -d: -f1)
step1_line=$(grep -n "Step 1.*Read Automation Config\|Read Automation Config" "$INIT_SKILL" | head -1 | cut -d: -f1)
if [ -z "$step0_line" ]; then
  fail "init SKILL.md missing Step 0: Parameter Override"
elif [ -z "$step1_line" ]; then
  fail "init SKILL.md missing Step 1 anchor"
elif [ "$step0_line" -ge "$step1_line" ]; then
  fail "init SKILL.md Step 0 must appear before Step 1 (Step 0 at line $step0_line, Step 1 at $step1_line)"
fi

# 5. Init validates --tracker-type against known types
if ! grep -q 'youtrack.*github.*jira.*linear.*gitea.*redmine\|Valid.*types\|Invalid.*tracker.*type' "$INIT_SKILL"; then
  fail "init SKILL.md missing tracker-type validation against known types"
fi

# 6. Init mentions composability with --update
if ! grep -q '\-\-update.*\-\-tracker-type\|\-\-tracker-type.*\-\-update\|compos.*update\|Composability.*update' "$INIT_SKILL"; then
  fail "init SKILL.md missing --update composability documentation"
fi

# === SCAFFOLD STEP 0-MCP GUIDANCE (task-002) ===

# 7. Scaffold Step 0-MCP offers "Configure now" option
if ! grep -q 'Configure now\|configure now' "$SCAFFOLD_SKILL"; then
  fail "scaffold SKILL.md Step 0-MCP missing 'Configure now' option"
fi

# 8. Scaffold Step 0-MCP displays init command with flags
if ! grep -q 'init.*\-\-tracker-type' "$SCAFFOLD_SKILL"; then
  fail "scaffold SKILL.md Step 0-MCP missing init command with --tracker-type flag"
fi

# 9. Scaffold Step 0-MCP mentions checkpoint/STOP after init
if ! grep -q 'checkpoint\|STOP scaffold\|restart.*resume\|session restart' "$SCAFFOLD_SKILL"; then
  fail "scaffold SKILL.md Step 0-MCP missing checkpoint + STOP guidance after init"
fi

# 10. Scaffold Step 0-MCP has Skip option (existing downgrade behavior)
mcp_section_start=$(grep -n "mcp_available: false" "$SCAFFOLD_SKILL" | head -1 | cut -d: -f1)
if [ -n "$mcp_section_start" ]; then
  mcp_context=$(sed -n "$mcp_section_start,$((mcp_section_start + 50))p" "$SCAFFOLD_SKILL")
  if ! matches_re "${mcp_context,,}" 'skip|downgrad'; then
    fail "scaffold SKILL.md Step 0-MCP missing Skip/downgrade option"
  fi
fi

# === SCAFFOLD RESUME AUTO-RECHECK (task-003) ===

# 11. Resume section mentions auto-recheck for downgraded services
resume_line=$(grep -n "On resume" "$SCAFFOLD_SKILL" | head -1 | cut -d: -f1)
if [ -n "$resume_line" ]; then
  context=$(sed -n "$resume_line,$((resume_line + 25))p" "$SCAFFOLD_SKILL")
  if ! matches_re "${context,,}" 'downgraded.*re-check|re-check.*downgraded|auto-recheck|re-run.*0-mcp|re-checking.*mcp'; then
    fail "scaffold SKILL.md resume section missing auto-recheck for downgraded services"
  fi
fi

# 12. Resume section distinguishes "downgraded" from "later"
if [ -n "$resume_line" ]; then
  context=$(sed -n "$resume_line,$((resume_line + 30))p" "$SCAFFOLD_SKILL")
  if ! matches_re "${context,,}" 'later.*no action|later.*skip|later.*defer|respect.*choice'; then
    fail "scaffold SKILL.md resume section missing 'later' = no-recheck semantics"
  fi
fi

# 13. Resume auto-recheck upgrades status on success
if [ -n "$resume_line" ]; then
  context=$(sed -n "$resume_line,$((resume_line + 30))p" "$SCAFFOLD_SKILL")
  if ! matches_re "${context,,}" 'ready|upgrade.*status|status.*ready'; then
    fail "scaffold SKILL.md resume auto-recheck missing upgrade to ready on success"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "PASS: Scaffold MCP chicken-and-egg fix verified"
exit "$FAIL"
