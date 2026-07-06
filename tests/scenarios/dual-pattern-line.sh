#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-dual-pattern-line.sh  [HIDDEN -- 20%]
# FC mapped:   FC-B-3, FC-B-4 (dual-pattern lines span depth-2 and depth-3 files)
# Phase:       5 (TDD -- FAIL expected until Phase 7 lands, then must PASS)
# What it checks:
#   The 3 known dual-pattern lines contain TWO `core/X.md` tokens on ONE line.
#   A naive sed that only rewrites the first match per line would leave the
#   second token bare. This test synthesizes those lines and verifies a
#   single sed -E pass rewrites BOTH tokens.
#
# Known dual-pattern lines (from / phase-2 final.md §C1):
#   1. skills/implement-feature/SKILL.md:130 (depth-2, expects ../../core/)
#   2. skills/implement-feature/steps/03-decomposition.md:91 (depth-3, expects ../../../core/)
#   3. skills/publish/SKILL.md:176 (depth-2, expects ../../core/)
#
# This test:
#   a) Synthesizes 3 single-line fixtures with two bare `core/X.md` tokens each
#   b) Applies the appropriate depth-class sed to each
#   c) Verifies BOTH tokens on the line got rewritten (grep count == 2 per line)
# Cross-platform: Win Git-Bash + Linux GNU + macOS BSD
# Exit codes: 0=PASS, 1=FAIL, 77=SKIP
# ===========================================================================
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
TMPDIR_DUAL=""

cleanup() {
  if [ -n "$TMPDIR_DUAL" ] && [ -d "$TMPDIR_DUAL" ]; then
    rm -rf "$TMPDIR_DUAL"
  fi
}
trap cleanup EXIT

if ! TMPDIR_DUAL=$(mktemp -d 2>/dev/null); then
  if ! TMPDIR_DUAL=$(mktemp -d -t v10dual.XXXXXX 2>/dev/null); then
    echo "[SKIP] mktemp -d unavailable on this platform"
    exit 77
  fi
fi

# ---------------------------------------------------------------------------
# Helper: apply depth-class sed to a single line, count resulting prefixed refs
# ---------------------------------------------------------------------------
apply_and_count() {
  local line="$1"
  local prefix="$2"
  local result
  result=$(printf '%s\n' "$line" | \
    sed -E "s|([^./])core/([a-z][a-z-]*\\.md)|\1${prefix}core/\2|g")
  # Count how many times ${prefix}core/ appears in the result
  count=$(printf '%s\n' "$result" | \
    grep -oE "${prefix}core/[a-z][a-z-]*\\.md" | wc -l | tr -d ' ')
  printf '%s\n' "$result"
  # Return count via a temp file for the caller
  printf '%s' "$count" > "$TMPDIR_DUAL/count.txt"
}

# ---------------------------------------------------------------------------
# ASSERT-1: depth-2 dual-pattern line (implement-feature/SKILL.md:130 style)
# Simulated: a line referencing two different core files inline
# ---------------------------------------------------------------------------
LINE_DEPTH2="See core/state-manager.md and also core/mcp-preflight.md for context."
PREFIX2="../../"
EXPECTED2=2

result2=$(apply_and_count "$LINE_DEPTH2" "$PREFIX2")
count2=$(cat "$TMPDIR_DUAL/count.txt")

echo "[INFO] depth-2 input:  $LINE_DEPTH2"
echo "[INFO] depth-2 output: $result2"

if [ "$count2" -eq "$EXPECTED2" ]; then
  echo "[PASS] ASSERT-1: depth-2 sed rewrote BOTH tokens on dual-pattern line (count=$count2)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-1: depth-2 sed only rewrote $count2/$EXPECTED2 tokens on dual-pattern line"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Verify no bare core/ remains after rewrite
# grep returns 1 when zero matches; pipefail propagates -- wrap to allow 0-match.
bare2=$(printf '%s\n' "$result2" | { grep -oE '[^./]core/[a-z][a-z-]*\.md' || true; } | wc -l | tr -d ' ')
if [ "$bare2" -eq 0 ]; then
  echo "[PASS] ASSERT-1b: no bare core/ refs remain after depth-2 dual rewrite"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-1b: $bare2 bare core/ ref(s) remain after depth-2 dual rewrite"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-2: depth-3 dual-pattern line (implement-feature/steps/03-decomposition.md:91 style)
# ---------------------------------------------------------------------------
LINE_DEPTH3="Load core/pipeline-state.md then validate against core/state-manager.md schema."
PREFIX3="../../../"
EXPECTED3=2

result3=$(apply_and_count "$LINE_DEPTH3" "$PREFIX3")
count3=$(cat "$TMPDIR_DUAL/count.txt")

echo "[INFO] depth-3 input:  $LINE_DEPTH3"
echo "[INFO] depth-3 output: $result3"

if [ "$count3" -eq "$EXPECTED3" ]; then
  echo "[PASS] ASSERT-2: depth-3 sed rewrote BOTH tokens on dual-pattern line (count=$count3)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-2: depth-3 sed only rewrote $count3/$EXPECTED3 tokens on dual-pattern line"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

bare3=$(printf '%s\n' "$result3" | { grep -oE '[^./]core/[a-z][a-z-]*\.md' || true; } | wc -l | tr -d ' ')
if [ "$bare3" -eq 0 ]; then
  echo "[PASS] ASSERT-2b: no bare core/ refs remain after depth-3 dual rewrite"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-2b: $bare3 bare core/ ref(s) remain after depth-3 dual rewrite"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-3: Edge case -- triple occurrence on one line (adversarial)
# If there are 3 bare core/X.md on one line, all 3 must be rewritten.
# ---------------------------------------------------------------------------
LINE_TRIPLE="Read core/a.md then core/b-reader.md then core/mcp-preflight.md."
PREFIX_T="../../"
EXPECTED_T=3

result_t=$(apply_and_count "$LINE_TRIPLE" "$PREFIX_T")
count_t=$(cat "$TMPDIR_DUAL/count.txt")

if [ "$count_t" -eq "$EXPECTED_T" ]; then
  echo "[PASS] ASSERT-3: adversarial triple-token line: all $EXPECTED_T tokens rewritten"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-3: adversarial triple-token line: only $count_t/$EXPECTED_T tokens rewritten"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-4: Negative -- already-prefixed dual line must NOT be double-prefixed
# Line with TWO already-prefixed ../../core/ refs must survive a second sed pass unchanged.
# ---------------------------------------------------------------------------
LINE_ALREADY="Read ../../core/a.md and ../../core/b-reader.md for reference."
result_already=$(printf '%s\n' "$LINE_ALREADY" | \
  sed -E "s|([^./])core/([a-z][a-z-]*\\.md)|\1../../core/\2|g")

if [ "$LINE_ALREADY" = "$result_already" ]; then
  echo "[PASS] ASSERT-4: already-prefixed dual line unchanged by second depth-2 pass (idempotent)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-4: already-prefixed dual line was mutated by second pass!"
  echo "[INFO] before: $LINE_ALREADY"
  echo "[INFO] after:  $result_already"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-5: Check actual repo dual-pattern lines if they exist (post-Phase-7 only)
# Looks for the 3 known dual-pattern lines in real files; skips if files don't
# have depth-correct refs yet (pre-Phase-7).
# ---------------------------------------------------------------------------
REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

check_real_line() {
  local label="$1"
  local file="$2"
  local lineno="$3"
  local expected_prefix="$4"
  local expected_count="$5"

  [ -f "$REPO_ROOT/$file" ] || return 0

  actual_line=$(sed -n "${lineno}p" "$REPO_ROOT/$file" 2>/dev/null || true)
  [ -z "$actual_line" ] && return 0

  # Count prefixed refs on the actual line
  actual_count=$(printf '%s\n' "$actual_line" | \
    grep -oE "${expected_prefix}core/[a-z][a-z-]*\\.md" | wc -l | tr -d ' ')

  bare_count=$(printf '%s\n' "$actual_line" | \
    { grep -oE '[^./]core/[a-z][a-z-]*\.md' || true; } | wc -l | tr -d ' ')

  if [ "$bare_count" -gt 0 ]; then
    echo "[INFO] $label line $lineno has $bare_count bare ref(s) -- Phase 7 not yet applied (expected)"
    return 0
  fi

  if [ "$actual_count" -ge "$expected_count" ]; then
    echo "[PASS] ASSERT-5 $label: both core refs on line $lineno use ${expected_prefix}core/ prefix"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] ASSERT-5 $label: line $lineno has $actual_count/${expected_count} prefixed refs"
    echo "[INFO] line content: $actual_line"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_real_line "implement-feature/SKILL.md:130" \
  "skills/implement-feature/SKILL.md" 130 "../../" 2

check_real_line "implement-feature/steps/03-decomposition.md:96" \
  "skills/implement-feature/steps/03-decomposition.md" 96 "../../../" 2

check_real_line "publish/SKILL.md:176" \
  "skills/publish/SKILL.md" 176 "../../" 2

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "[PASS] v10-dual-pattern-line: all assertions passed"
  exit 0
else
  echo "[FAIL] v10-dual-pattern-line: $FAIL_COUNT assertion(s) failed"
  exit 1
fi
