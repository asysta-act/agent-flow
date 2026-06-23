#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-step-completion-invariants-completeness-EXTENDED.sh
# Falsifies:,
#              (this is the EXTENDED version for Phase 5 TDD;
#              Phase 7 edits the existing scenario in-place — this file
#              documents the target shape)
# FC mapped:   FC-REL-2 (a/b/c/d)
# What it checks (this EXTENDED version covers both agents/ AND examples/custom-agents/):
#   ASSERT-1) DIRS array contains both "agents" and "examples/custom-agents"
#   ASSERT-2) Each directory in DIRS exists (FAIL not SKIP for examples/custom-agents)
#   ASSERT-3) agents/*.md count == 17 (scoped to agents/ only, NOT custom-agents)
#   ASSERT-4) examples/custom-agents/*.md count == 4 (hardcoded literal — dual-anchor)
#   ASSERT-5) All files in both dirs have '## Step Completion Invariants' header exactly once
#   ASSERT-6) All files have the 5 mandatory invariant names in the section body
#   ASSERT-7) All files have EXPECTED_AGENT_NAME and EXPECTED_STAGE_NAME tokens
#   ASSERT-8) Section placement: Output Contract < SCI < Constraints (or Process fallback)
# Expected: PASS — all agents and custom-agent examples
#   already contain ## Step Completion Invariants.
#   Scenario fails when a future file is added without the section.
# Expected GREEN phase (post-impl): PASS continuously.
# ===========================================================================
set -uo pipefail

REPO_ROOT="${CEOS_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
. "$REPO_ROOT/tests/lib/assert.sh"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# ---------------------------------------------------------------------------
# Directory list and expected counts (parallel-indexed arrays)
# M2 acknowledgement: count 5 is intentionally hardcoded here (dual-anchor
# with FC-COUNTS-8). Dual anchor is defense-in-depth: a 6th custom-agent
# added without updating BOTH sites will be caught.
# Count is 5: 4 agent example files + 1 README.md
# ---------------------------------------------------------------------------
# [ASSERT-1] DIRS contains both agents and examples/custom-agents
DIRS=("agents" "examples/custom-agents")
EXPECTED_COUNTS=([0]=17 [1]=5)

INVARIANTS=(dispatched_at dispatch_witness status stage_name agent_name)
ALL_FILES=()

# ---------------------------------------------------------------------------
# ASSERT-2: Each directory exists + ASSERT-3/4: per-directory count checks
# ---------------------------------------------------------------------------
for i in "${!DIRS[@]}"; do
  d="${DIRS[$i]}"
  exp="${EXPECTED_COUNTS[$i]}"

  # [ASSERT-2] Directory must exist (FAIL not SKIP — must be present in-repo)
  if [ ! -d "$d" ]; then
    fail "FC-REL-2.dir: $d missing — expected to be present in-repo"
    continue
  fi

  FILES=("$d"/*.md)
  COUNT="${#FILES[@]}"

  # Guard against glob expansion when directory is empty (bash expands to literal pattern)
  if [ "$COUNT" -eq 1 ] && [ ! -f "${FILES[0]}" ]; then
    COUNT=0
    FILES=()
  fi

  # [ASSERT-3/4] Per-directory file count assertion (hardcoded literals)
  if [ "$COUNT" -ne "$exp" ]; then
    fail "FC-6.D.${d}: expected ${exp} *.md files in $d, found ${COUNT}"
  fi

  ALL_FILES+=("${FILES[@]}")
done

# ---------------------------------------------------------------------------
# Per-file checks across all collected files (agents + custom-agent examples)
# ---------------------------------------------------------------------------
for agent_file in "${ALL_FILES[@]}"; do
  # Skip glob non-matches (safety guard)
  [ -f "$agent_file" ] || continue
  base=$(basename "$agent_file")
  # Skip README.md — it is documentation, not an agent definition
  [ "$base" = "README.md" ] && continue

  # ---- ASSERT-5a: Section header presence (exactly once) ----
  hdr_count=$(grep -cE '^## Step Completion Invariants$' "$agent_file" || true)
  [ -z "$hdr_count" ] && hdr_count=0
  if [ "$hdr_count" -eq 0 ]; then
    fail "FC-6.A: $base missing '## Step Completion Invariants' header"
    continue
  fi
  if [ "$hdr_count" -gt 1 ]; then
    fail "FC-6.A-dup: $base has $hdr_count '## Step Completion Invariants' headers (expected exactly 1)"
  fi

  # Extract the section block (header line excluded)
  section=$(awk '/^## Step Completion Invariants$/{f=1; next} /^## /&&f{exit} f' "$agent_file")

  # SIGPIPE-safe equivalent of grep -qE "(`|^| )${inv}(`|$| )" against the
  # multiline section: bash [[ =~ ]] anchors match string start/end, not line
  # boundaries, so we wrap the section in newline sentinels and treat a leading
  # newline as ^ and a trailing newline as $ (the alternation already allowed
  # backtick and space delimiters).
  section_nl=$'\n'"$section"$'\n'

  # ---- ASSERT-6: All 5 mandatory invariant names referenced in section ----
  for inv in "${INVARIANTS[@]}"; do
    if ! matches_re "$section_nl" '(`|'$'\n''| )'"${inv}"'(`|'$'\n''| )'; then
      fail "FC-6.B: $base section missing invariant '${inv}'"
    fi
  done

  # ---- B': >= 2 invariant names in body ----
  body_hits=0
  for inv in "${INVARIANTS[@]}"; do
    if matches_re "$section_nl" '(`|'$'\n''| )'"${inv}"'(`|'$'\n''| )'; then
      body_hits=$((body_hits + 1))
    fi
  done
  if [ "$body_hits" -lt 2 ]; then
    fail "FC-6.B-prime: $base section body contains only ${body_hits}/5 invariant names (need >= 2)"
  fi

  # ---- ASSERT-7: EXPECTED_AGENT_NAME and EXPECTED_STAGE_NAME tokens ----
  if ! contains "$section" "EXPECTED_STAGE_NAME"; then
    fail "FC-6.B-doubleprime-1: $base section body missing 'EXPECTED_STAGE_NAME' token"
  fi
  if ! contains "$section" "EXPECTED_AGENT_NAME"; then
    fail "FC-6.B-doubleprime-2: $base section body missing 'EXPECTED_AGENT_NAME' token"
  fi

  # ---- ASSERT-8: Placement: Output Contract < SCI < Constraints (or Process fallback) ----
  oc_line=$(grep -nE '^## Output Contract$' "$agent_file" | head -n 1 | cut -d: -f1)
  sci_line=$(grep -nE '^## Step Completion Invariants$' "$agent_file" | head -n 1 | cut -d: -f1)
  con_line=$(grep -nE '^## Constraints$' "$agent_file" | head -n 1 | cut -d: -f1)

  if [ -n "$oc_line" ] && [ -n "$sci_line" ] && [ -n "$con_line" ]; then
    if ! { [ "$oc_line" -lt "$sci_line" ] && [ "$sci_line" -lt "$con_line" ]; }; then
      fail "FC-6.C: $base placement violation: OutputContract=L${oc_line}, SCI=L${sci_line}, Constraints=L${con_line}"
    fi
  elif [ -n "$sci_line" ] && [ -n "$con_line" ]; then
    proc_line=$(grep -nE '^## Process$' "$agent_file" | head -n 1 | cut -d: -f1)
    if [ -n "$proc_line" ]; then
      if ! { [ "$proc_line" -lt "$sci_line" ] && [ "$sci_line" -lt "$con_line" ]; }; then
        fail "FC-6.C-fallback: $base fallback placement: Process=L${proc_line}, SCI=L${sci_line}, Constraints=L${con_line}"
      fi
    fi
  fi
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
total="${#ALL_FILES[@]}"
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-step-completion-invariants-completeness-EXTENDED — all ${total} files (17 agents + 4 custom-agent examples) have complete '## Step Completion Invariants' section"
  exit 0
fi
exit 1
