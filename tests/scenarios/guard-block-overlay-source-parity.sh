#!/usr/bin/env bash
# ===========================================================================
# Test:        guard-block-overlay-source-parity.sh
# Covers:      PR #12 — overlay-injection contract present and consistent
#              across the 3 orchestrator guard-block files.
# Files under test:
#   skills/fix-bugs/data/guard-block.md
#   skills/implement-feature/data/guard-block.md
#   skills/scaffold/data/guard-block.md
# What it checks (STRUCTURAL, read-only) — for ALL THREE files:
#   ASSERT-1) `stages.<stage>.overlay_source` appears in the state.json
#             schema block.
#   ASSERT-2) The THIN CONTROLLER pre-dispatch list mentions resolving /
#             injecting Agent Overrides before each Task (either
#             "Resolve + inject Agent Overrides" or "agent-override-injector").
#   ASSERT-3) A rationalization-trap row about NOT resolving
#             `customization/<agent>.toml` is present.
# Each missing assertion fails loudly with the offending filename.
# Modeled on guard-block-fail-loud.sh (loop over the 3 guard files).
# Cross-platform: Win Git-Bash + Linux GNU + macOS BSD
# Exit codes: 0=PASS, 1=FAIL, 77=SKIP
# ===========================================================================
set -uo pipefail

REPO_ROOT="${CEOS_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# SIGPIPE-safe assert helpers: contains / contains_i / matches_re
. "$REPO_ROOT/tests/lib/assert.sh"

GUARD_FILES=(
  "$REPO_ROOT/skills/fix-bugs/data/guard-block.md"
  "$REPO_ROOT/skills/implement-feature/data/guard-block.md"
  "$REPO_ROOT/skills/scaffold/data/guard-block.md"
)

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '[PASS] %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Helper: assert that FILE's content (already slurped) contains NEEDLE.
# Usage: check_contains <label> <base> <content> <needle>
# ---------------------------------------------------------------------------
check_contains() {
  local label="$1" base="$2" content="$3" needle="$4"
  if contains "$content" "$needle"; then
    pass "$label in $base"
  else
    fail "$label NOT found in $base"
  fi
}

# ---------------------------------------------------------------------------
# Per-file assertions (loop — each missing assertion names the file).
# ---------------------------------------------------------------------------
for guard_file in "${GUARD_FILES[@]}"; do
  # Include the skill dir (parent of data/) so failures name the exact file,
  # e.g. fix-bugs/data/guard-block.md vs implement-feature/data/guard-block.md.
  data_dir="$(dirname "$guard_file")"
  base="$(basename "$(dirname "$data_dir")")/$(basename "$data_dir")/$(basename "$guard_file")"

  if [ ! -f "$guard_file" ]; then
    fail "guard-block file MISSING: $base"
    continue
  fi

  content="$(cat "$guard_file")"

  # ASSERT-1: state.json schema records stages.<stage>.overlay_source
  check_contains "ASSERT-1 stages.<stage>.overlay_source in state.json schema" \
    "$base" "$content" "stages.<stage>.overlay_source"

  # ASSERT-2: THIN CONTROLLER pre-dispatch list mentions resolving / injecting
  # Agent Overrides before each Task. Accept either the imperative phrase or a
  # direct reference to the injector contract file.
  if contains "$content" "Resolve + inject Agent Overrides" \
     || contains "$content" "agent-override-injector"; then
    pass "ASSERT-2 pre-dispatch Agent Override resolve/inject directive in $base"
  else
    fail "ASSERT-2 pre-dispatch Agent Override resolve/inject directive NOT found in $base"
  fi

  # ASSERT-3: rationalization-trap row about not resolving customization/<agent>.toml
  check_contains "ASSERT-3 rationalization trap: resolving customization/<agent>.toml" \
    "$base" "$content" "resolving \`customization/<agent>.toml\`"
done

# ---------------------------------------------------------------------------
# Aggregate: overlay_source must appear in all 3 guard files (parity guard).
# ---------------------------------------------------------------------------
overlay_count=0
for guard_file in "${GUARD_FILES[@]}"; do
  [ -f "$guard_file" ] || continue
  if contains "$(cat "$guard_file")" "stages.<stage>.overlay_source"; then
    overlay_count=$((overlay_count + 1))
  fi
done

if [ "$overlay_count" -eq 3 ]; then
  pass "ASSERT-AGG: overlay_source contract present in all 3 guard files"
else
  fail "ASSERT-AGG: overlay_source contract present in $overlay_count/3 guard files (expected 3)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "[PASS] guard-block-overlay-source-parity: all assertions passed"
  exit 0
else
  echo "[FAIL] guard-block-overlay-source-parity: $FAIL_COUNT assertion(s) failed"
  exit 1
fi
