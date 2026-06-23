#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-terminal-report-witness-surface.sh
# FC mapped:   FC-5 (terminal report surfaces WITNESS_MISSING + per-skill allow-list)
# What it checks:
#   A) skills/fix-bugs/SKILL.md contains <stage_allowlist> ... </stage_allowlist>
#      block with the 6 REQUIRED stages.
#   A') skills/implement-feature/SKILL.md contains <stage_allowlist> with 4 REQUIRED
#       stages AND must NOT mention triage/reproduce_browser/e2e_test/browser_verification
#       (BLOCKER-2 alarm-fatigue suppression).
#   B) skills/fix-bugs/steps/12-result.md exists AND contains:
#       - literal "WITNESS_MISSING"
#       - literal "dispatch-audit.log"
#       - literal "stage_allowlist"
#   C) skills/implement-feature/steps/08-publish.md exists AND contains the same
#      three tokens (mirror).
# Expected RED phase: FAIL — none of the steps or allow-lists exist yet
# Expected GREEN phase (post-impl): PASS
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

FB_SKILL="skills/fix-bugs/SKILL.md"
IF_SKILL="skills/implement-feature/SKILL.md"
FB_STEP="skills/fix-bugs/steps/12-result.md"
IF_STEP="skills/implement-feature/steps/08-publish.md"

# ============================================================================
# A. fix-bugs <stage_allowlist> block
# ============================================================================
if [ ! -f "$FB_SKILL" ]; then
  fail "FC-5.A.file: $FB_SKILL missing"
else
  if ! grep -q '<stage_allowlist>' "$FB_SKILL"; then
    fail "FC-5.A0: $FB_SKILL missing '<stage_allowlist>' opening tag"
  fi
  if ! grep -q '</stage_allowlist>' "$FB_SKILL"; then
    fail "FC-5.A0b: $FB_SKILL missing '</stage_allowlist>' closing tag"
  fi
  # Extract block content
  FB_BLOCK=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' "$FB_SKILL")
  for s in triage code_analysis fixer_reviewer smoke_check test publisher; do
    if ! contains "$FB_BLOCK" "$s"; then
      fail "FC-5.A1: $FB_SKILL <stage_allowlist> missing required stage '${s}'"
    fi
  done
fi

# ============================================================================
# A'. implement-feature <stage_allowlist> block + negative-list check
# ============================================================================
if [ ! -f "$IF_SKILL" ]; then
  fail "FC-5.Aif.file: $IF_SKILL missing"
else
  if ! grep -q '<stage_allowlist>' "$IF_SKILL"; then
    fail "FC-5.Aif0: $IF_SKILL missing '<stage_allowlist>' opening tag"
  fi
  IF_BLOCK=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' "$IF_SKILL")
  for s in code_analysis fixer_reviewer test publisher; do
    if ! contains "$IF_BLOCK" "$s"; then
      fail "FC-5.Aif1: $IF_SKILL <stage_allowlist> missing required stage '${s}'"
    fi
  done
  # NEGATIVE check (BLOCKER-2): must NOT contain these 4 stages
  for forbidden in triage reproduce_browser e2e_test browser_verification; do
    if matches_re "$IF_BLOCK" "(^|[,[:space:]:])${forbidden}([,[:space:]]|$)"; then
      fail "FC-5.Aif2: $IF_SKILL <stage_allowlist> MUST NOT include '${forbidden}' (suppressed BLOCKER-2 fix)"
    fi
  done
fi

# ============================================================================
# B. fix-bugs result step file
# ============================================================================
if [ ! -f "$FB_STEP" ]; then
  fail "FC-5.B: $FB_STEP missing"
else
  if ! grep -q 'WITNESS_MISSING' "$FB_STEP"; then
    fail "FC-5.B1: $FB_STEP does not contain 'WITNESS_MISSING' string"
  fi
  if ! grep -q 'dispatch-audit\.log' "$FB_STEP"; then
    fail "FC-5.B2: $FB_STEP does not read 'dispatch-audit.log'"
  fi
  if ! grep -q 'stage_allowlist' "$FB_STEP"; then
    fail "FC-5.B3: $FB_STEP does not parse 'stage_allowlist' from parent SKILL.md"
  fi
fi

# ============================================================================
# C. implement-feature publish step file
# ============================================================================
if [ ! -f "$IF_STEP" ]; then
  fail "FC-5.C: $IF_STEP missing"
else
  if ! grep -q 'WITNESS_MISSING' "$IF_STEP"; then
    fail "FC-5.C1: $IF_STEP does not contain 'WITNESS_MISSING' string"
  fi
  if ! grep -q 'dispatch-audit\.log' "$IF_STEP"; then
    fail "FC-5.C2: $IF_STEP does not read 'dispatch-audit.log'"
  fi
  if ! grep -q 'stage_allowlist' "$IF_STEP"; then
    fail "FC-5.C3: $IF_STEP does not parse 'stage_allowlist' from parent SKILL.md"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-terminal-report-witness-surface — allow-lists + WITNESS_MISSING surfacing in both skill step files"
  exit 0
fi
exit 1
