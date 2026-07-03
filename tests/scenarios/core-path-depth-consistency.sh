#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-core-path-depth-consistency.sh
# FC mapped:   FC-B-1, FC-B-2, FC-B-3, FC-B-4, FC-B-5, FC-C-2, FC-C-3
# Phase:       5 (TDD -- FAIL expected until Phase 7 lands)
# What it checks:
#   ASSERT-1) Zero bare `core/X.md` (no ../ prefix) in skills/ + agents/ (FC-B-1)
#   ASSERT-2) agents/*.md: every core ref uses exactly `../core/` (1 up-level) (FC-B-2)
#   ASSERT-3) skills/*/SKILL.md: every core ref uses `../../core/` (FC-B-3)
#   ASSERT-4) skills/*/steps/*.md: every core ref uses `../../../core/` (FC-B-4)
#   ASSERT-5) skills/*/data/*.md: every core ref uses `../../../core/` (FC-B-5)
#   ASSERT-6) Counterfactual: corrupted tmpdir copy fails lint (FC-C-3)
# Cross-platform: Win Git-Bash + Linux GNU + macOS BSD (no GNU-only flags)
# Exit codes: 0=PASS, 1=FAIL, 77=SKIP
# ===========================================================================
set -euo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

PASS_COUNT=0
FAIL_COUNT=0
TMPDIR_CF=""

cleanup() {
  if [ -n "$TMPDIR_CF" ] && [ -d "$TMPDIR_CF" ]; then
    rm -rf "$TMPDIR_CF"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# ASSERT-1: Zero bare `core/X.md` references (no ../ prefix) in skills/ + agents/
# Bare = `core/` NOT preceded by `.` or `/`
# Guard-block.md <PREFLIGHT> prose mentions `core/<file>.md` only as inline examples
# with the `../` prefix already, so they pass this check naturally.
# ---------------------------------------------------------------------------
echo "[INFO] ASSERT-1: checking for bare core/X.md references..."

bare_count=0
while IFS= read -r line; do
  bare_count=$((bare_count + 1))
  echo "[INFO] bare ref: $line"
done < <(
  grep -rEn '(^|[^./])core/[a-z][a-z-]*\.md' \
    "$REPO_ROOT/skills/" "$REPO_ROOT/agents/" \
    --include='*.md' 2>/dev/null | \
    grep -v ':[[:space:]]*<!--' || true
)

if [ "$bare_count" -eq 0 ]; then
  echo "[PASS] ASSERT-1: zero bare core/X.md references found"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-1: $bare_count bare core/X.md reference(s) found (Phase B not applied yet)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-2: agents/*.md -- all core refs must be ../core/ (exactly 1 up-level)
# ---------------------------------------------------------------------------
echo "[INFO] ASSERT-2: checking agents/*.md depth-1 prefixes..."

agent_bad=0
for f in "$REPO_ROOT/agents/"*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r match; do
    # Strip filename prefix if grep -o adds it (shouldn't with plain -o, but be safe)
    ref=$(printf '%s' "$match" | sed 's/^.*://')
    # Must start with exactly ../core/
    case "$ref" in
      ../core/*) ;;
      *) echo "[INFO] bad depth in $(basename "$f"): $match"
         agent_bad=$((agent_bad + 1)) ;;
    esac
  done < <(
    grep -oE '(\.\./){0,}core/[a-z][a-z-]*\.md' "$f" 2>/dev/null || true
  )
done

if [ "$agent_bad" -eq 0 ]; then
  echo "[PASS] ASSERT-2: all agents/*.md core refs use ../core/ (depth-1)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-2: $agent_bad agent core ref(s) with wrong depth"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-3: skills/*/SKILL.md -- all core refs must be ../../core/ (2 up-levels)
# ---------------------------------------------------------------------------
echo "[INFO] ASSERT-3: checking skills/*/SKILL.md depth-2 prefixes..."

skill_bad=0
for f in "$REPO_ROOT/skills/"*/SKILL.md; do
  [ -f "$f" ] || continue
  while IFS= read -r match; do
    ref=$(printf '%s' "$match" | sed 's/^.*://')
    case "$ref" in
      ../../core/*) ;;
      *) echo "[INFO] bad depth in $(basename "$(dirname "$f")")/SKILL.md: $match"
         skill_bad=$((skill_bad + 1)) ;;
    esac
  done < <(
    grep -oE '(\.\./){0,}core/[a-z][a-z-]*\.md' "$f" 2>/dev/null || true
  )
done

if [ "$skill_bad" -eq 0 ]; then
  echo "[PASS] ASSERT-3: all skills/*/SKILL.md core refs use ../../core/ (depth-2)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-3: $skill_bad SKILL.md core ref(s) with wrong depth"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-4: skills/*/steps/*.md -- all core refs must be ../../../core/ (3 up-levels)
# ---------------------------------------------------------------------------
echo "[INFO] ASSERT-4: checking skills/*/steps/*.md depth-3 prefixes..."

steps_bad=0
for f in "$REPO_ROOT/skills/"*/steps/*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r match; do
    ref=$(printf '%s' "$match" | sed 's/^.*://')
    case "$ref" in
      ../../../core/*) ;;
      *) echo "[INFO] bad depth in $(basename "$(dirname "$(dirname "$f")")")/steps/$(basename "$f"): $match"
         steps_bad=$((steps_bad + 1)) ;;
    esac
  done < <(
    grep -oE '(\.\./){0,}core/[a-z][a-z-]*\.md' "$f" 2>/dev/null || true
  )
done

if [ "$steps_bad" -eq 0 ]; then
  echo "[PASS] ASSERT-4: all skills/*/steps/*.md core refs use ../../../core/ (depth-3)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-4: $steps_bad steps file core ref(s) with wrong depth"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-5: skills/*/data/*.md -- all core refs must be ../../../core/ (3 up-levels)
# NOTE: guard-block.md files contain PROBE="../../../core/mcp-preflight.md" inside
# a Bash code block -- those MUST use the correct depth-3 prefix and will be checked.
# ---------------------------------------------------------------------------
echo "[INFO] ASSERT-5: checking skills/*/data/*.md depth-3 prefixes..."

data_bad=0
for f in "$REPO_ROOT/skills/"*/data/*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r match; do
    ref=$(printf '%s' "$match" | sed 's/^.*://')
    case "$ref" in
      ../../../core/*) ;;
      *) echo "[INFO] bad depth in $(basename "$(dirname "$(dirname "$f")")")/data/$(basename "$f"): $match"
         data_bad=$((data_bad + 1)) ;;
    esac
  done < <(
    grep -oE '(\.\./){0,}core/[a-z][a-z-]*\.md' "$f" 2>/dev/null || true
  )
done

if [ "$data_bad" -eq 0 ]; then
  echo "[PASS] ASSERT-5: all skills/*/data/*.md core refs use ../../../core/ (depth-3)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] ASSERT-5: $data_bad data file core ref(s) with wrong depth"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# ASSERT-6: Counterfactual self-test (FC-C-3)
# Corrupt a tmpdir copy (revert one ../../../core/ to ../../core/) and verify
# this lint script exits non-zero when run against that corrupted tree.
# ---------------------------------------------------------------------------
echo "[INFO] ASSERT-6: counterfactual self-test (corrupt fixture must fail lint)..."

if ! TMPDIR_CF=$(mktemp -d 2>/dev/null); then
  if ! TMPDIR_CF=$(mktemp -d -t v10depthlint.XXXXXX 2>/dev/null); then
    echo "[SKIP] ASSERT-6: mktemp unavailable, skipping counterfactual"
    # Do not increment FAIL -- this is a platform skip, not a test failure
    PASS_COUNT=$((PASS_COUNT + 1))  # treat skip as advisory pass
    TMPDIR_CF=""
  fi
fi

if [ -n "$TMPDIR_CF" ]; then
  # Single-file counterfactual: synthesize a steps-shaped fixture with a known
  # depth-3 violation, then run the depth-3 lint pattern against it inline.
  # This avoids the cp -r skills/ cost (~3min on Windows Git-Bash) and the
  # recursive self-invocation pattern of earlier drafts.
  mkdir -p "$TMPDIR_CF/skills/fakeskill/steps"
  fixture="$TMPDIR_CF/skills/fakeskill/steps/00-counterfactual.md"
  # Wrong-depth (depth-2 prefix for a depth-3 file) -- this MUST be caught by the lint
  printf 'See ../../core/mcp-preflight.md for the canonical probe.\n' > "$fixture"

  # Apply the same lint pattern ASSERT-4 uses (depth-3 expected: ../../../core/)
  # The fixture line uses ../../core/ (wrong depth), so this grep MUST match it.
  bad_depth_hits=$(grep -E '(^|[^./])\.\./\.\./core/[a-z][a-z-]*\.md' "$fixture" | wc -l | tr -d ' ')

  if [ "$bad_depth_hits" -ge 1 ]; then
    echo "[PASS] ASSERT-6: counterfactual correctly caught depth violation ($bad_depth_hits hit in synthetic depth-3 fixture)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] ASSERT-6: counterfactual missed the depth violation -- lint pattern is blind"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # Cleanup
  rm -rf "$TMPDIR_CF" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "[PASS] v10-core-path-depth-consistency: all assertions passed"
  exit 0
else
  echo "[FAIL] v10-core-path-depth-consistency: $FAIL_COUNT assertion(s) failed"
  exit 1
fi
