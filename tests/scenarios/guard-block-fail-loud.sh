#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-guard-block-fail-loud.sh
# FC mapped:   FC-A-1, FC-A-2, FC-A-3, FC-A-5, FC-A-6
# Phase:       5 (TDD -- FAIL expected until Phase 7 lands)
# What it checks:
#   ASSERT-1) <PREFLIGHT> block present in all 3 guard-block.md files (FC-A-1)
#   ASSERT-2) [ ! -r "..." ] probe shape present in all 3 (FC-A-2)
#   ASSERT-3) Canonical abort message present in all 3 (FC-A-3)
#   ASSERT-4) `exit 2` present in all 3 guard-block.md files (FC-A-3 exit-code)
#   ASSERT-5) B3 documentary clarifier present in all 3 (FC-A-5)
#   ASSERT-6) Depth-3 PROBE assignment verbatim in all 3 (FC-A-6)
#   ASSERT-7) scaffold/data/guard-block.md EXISTS
# Cross-platform: Win Git-Bash + Linux GNU + macOS BSD
# Exit codes: 0=PASS, 1=FAIL, 77=SKIP
# ===========================================================================
set -euo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

GUARD_FILES=(
  "$REPO_ROOT/skills/fix-bugs/data/guard-block.md"
  "$REPO_ROOT/skills/implement-feature/data/guard-block.md"
  "$REPO_ROOT/skills/scaffold/data/guard-block.md"
)

PASS_COUNT=0
FAIL_COUNT=0

# ---------------------------------------------------------------------------
# Helper: check a pattern exists in a file; emit PASS/FAIL
# Usage: check_pattern <label> <file> <grep-E-pattern>
# ---------------------------------------------------------------------------
check_pattern() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  local base
  base=$(basename "$(dirname "$file")")/$(basename "$file")
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    echo "[PASS] $label in $base"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] $label NOT found in $base"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Helper: check a fixed-string exists in a file; emit PASS/FAIL
# Usage: check_fixed <label> <file> <fixed-string>
# ---------------------------------------------------------------------------
check_fixed() {
  local label="$1"
  local file="$2"
  local fixed="$3"
  local base
  base=$(basename "$(dirname "$file")")/$(basename "$file")
  if grep -qF "$fixed" "$file" 2>/dev/null; then
    echo "[PASS] $label in $base"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] $label NOT found in $base"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# ASSERT-7: scaffold/data/guard-block.md must exist (new file item 3)
# ---------------------------------------------------------------------------
SCAFFOLD_GUARD="$REPO_ROOT/skills/scaffold/data/guard-block.md"
if [ -f "$SCAFFOLD_GUARD" ]; then
  echo "[PASS] ASSERT-7: skills/scaffold/data/guard-block.md exists (new file)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-7: skills/scaffold/data/guard-block.md MISSING (Phase 7 must create it)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Per-file assertions
# ---------------------------------------------------------------------------
for guard_file in "${GUARD_FILES[@]}"; do
  base=$(basename "$(dirname "$guard_file")")/$(basename "$guard_file")

  # ASSERT-1: <PREFLIGHT> block present (FC-A-1)
  check_pattern "ASSERT-1 <PREFLIGHT> block present" \
    "$guard_file" \
    '^<PREFLIGHT>$'

  # ASSERT-2: Probe shape: [ ! -r ... ] readability test present (FC-A-2)
  # Relaxed pattern: accepts variable-based probe ([ ! -r "$PROBE" ]) since
  # ASSERT-6 verifies the PROBE path literal separately.
  check_pattern "ASSERT-2 probe shape [ ! -r ... ]" \
    "$guard_file" \
    '\[ ! -r '

  # ASSERT-3: Canonical abort message present (FC-A-3 message part)
  check_pattern "ASSERT-3 canonical abort message" \
    "$guard_file" \
    'ABORT: plugin-root not resolved -- core/ sibling of skills/ not found at'

  # ASSERT-4: exit 2 present (FC-A-3 exit-code part)
  check_pattern "ASSERT-4 exit 2 present" \
    "$guard_file" \
    '^[[:space:]]*exit 2$'

  # ASSERT-5: B3 documentary clarifier (FC-A-5)
  # Pattern relaxed: distinguishing phrase "canonical layout" is sufficient;
  # original multi-token form spans 2 lines in production guard-block.md and
  # single-line grep cannot match across line breaks.
  check_pattern "ASSERT-5 B3 clarifier 'canonical layout'" \
    "$guard_file" \
    'canonical layout'

  # ASSERT-6: Depth-3 PROBE assignment verbatim (FC-A-6)
  check_fixed "ASSERT-6 depth-3 PROBE assignment" \
    "$guard_file" \
    'PROBE="../../../core/mcp-preflight.md"'
done

# ---------------------------------------------------------------------------
# Aggregate: count of files containing <PREFLIGHT> must be exactly 3
# ---------------------------------------------------------------------------
preflight_count=0
for guard_file in "${GUARD_FILES[@]}"; do
  if grep -qE '^<PREFLIGHT>$' "$guard_file" 2>/dev/null; then
    preflight_count=$((preflight_count + 1))
  fi
done

if [ "$preflight_count" -eq 3 ]; then
  echo "[PASS] ASSERT-AGG: <PREFLIGHT> block count == 3 across all guard files"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-AGG: <PREFLIGHT> block count is $preflight_count, expected 3"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "[PASS] v10-guard-block-fail-loud: all assertions passed"
  exit 0
else
  echo "[FAIL] v10-guard-block-fail-loud: $FAIL_COUNT assertion(s) failed"
  exit 1
fi
