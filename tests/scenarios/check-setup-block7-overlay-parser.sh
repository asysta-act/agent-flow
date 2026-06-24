#!/usr/bin/env bash
# ===========================================================================
# Test:        check-setup-block7-overlay-parser.sh
# Covers:      PR #12 — check-setup "Block 7: Agent Overrides (TOML overlay
#              parsing)" wiring in skills/check-setup/SKILL.md
# What it checks (STRUCTURAL, read-only):
#   ASSERT-1) A "Block 7" heading about Agent Overrides / TOML overlay parsing
#             is present.
#   ASSERT-2) The probe references python3, tomllib, and tomli.
#   ASSERT-3) The block distinguishes [SKIP] (no overlays / no dir),
#             [OK] (parser available), and [FAIL] (overlays present, no parser).
#   ASSERT-4) The block states its [FAIL] results COUNT toward the final FAIL
#             verdict ("count toward the final FAIL verdict").
# Scope: Block 7 facts ONLY — deliberately decoupled from step-5 optional
#        section list edits owned by other in-flight agents.
# Cross-platform: Win Git-Bash + Linux GNU + macOS BSD
# Exit codes: 0=PASS, 1=FAIL, 77=SKIP
# ===========================================================================
set -uo pipefail

REPO_ROOT="${CEOS_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# SIGPIPE-safe assert helpers: contains / contains_i / matches_re
. "$REPO_ROOT/tests/lib/assert.sh"

SKILL_FILE="$REPO_ROOT/skills/check-setup/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '[PASS] %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Guard: the SKILL.md must exist; otherwise SKIP (nothing to assert against).
# ---------------------------------------------------------------------------
if [ ! -f "$SKILL_FILE" ]; then
  echo "[SKIP] skills/check-setup/SKILL.md not found — Block 7 test skipped"
  exit 77
fi

# Slurp the file once into a single variable for builtin substring tests.
SKILL_CONTENT="$(cat "$SKILL_FILE")"

# ---------------------------------------------------------------------------
# ASSERT-1: "Block 7" heading about Agent Overrides / TOML overlay parsing.
# ---------------------------------------------------------------------------
if contains_i "$SKILL_CONTENT" "Block 7: Agent Overrides" \
   && contains_i "$SKILL_CONTENT" "TOML overlay"; then
  pass "ASSERT-1 Block 7 heading about Agent Overrides / TOML overlay parsing present"
else
  fail "ASSERT-1 Block 7 heading about Agent Overrides / TOML overlay parsing MISSING"
fi

# ---------------------------------------------------------------------------
# ASSERT-2: probe references python3, tomllib, and tomli.
# ---------------------------------------------------------------------------
for token in "python3" "tomllib" "tomli"; do
  if contains "$SKILL_CONTENT" "$token"; then
    pass "ASSERT-2 probe references '$token'"
  else
    fail "ASSERT-2 probe does NOT reference '$token'"
  fi
done

# ---------------------------------------------------------------------------
# ASSERT-3: block distinguishes [SKIP], [OK], and [FAIL] for agent overrides.
# Use the distinctive 'Agent overrides -' status-line prefix that the probe
# emits so we are asserting against Block-7 output, not unrelated checks.
# ---------------------------------------------------------------------------
if contains "$SKILL_CONTENT" "[SKIP] Agent overrides -"; then
  pass "ASSERT-3 [SKIP] Agent overrides branch present (no overlays / no dir)"
else
  fail "ASSERT-3 [SKIP] Agent overrides branch MISSING"
fi

if contains "$SKILL_CONTENT" "[OK] Agent overrides -"; then
  pass "ASSERT-3 [OK] Agent overrides branch present (parser available)"
else
  fail "ASSERT-3 [OK] Agent overrides branch MISSING"
fi

if contains "$SKILL_CONTENT" "[FAIL] Agent overrides -"; then
  pass "ASSERT-3 [FAIL] Agent overrides branch present (overlays, no parser)"
else
  fail "ASSERT-3 [FAIL] Agent overrides branch MISSING"
fi

# ---------------------------------------------------------------------------
# ASSERT-4: [FAIL] results in this block COUNT toward the final FAIL verdict.
# ---------------------------------------------------------------------------
if contains "$SKILL_CONTENT" "count toward the final FAIL verdict"; then
  pass "ASSERT-4 Block 7 [FAIL] declared to count toward the final FAIL verdict"
else
  fail "ASSERT-4 Block 7 missing 'count toward the final FAIL verdict' wording"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "[PASS] check-setup-block7-overlay-parser: all assertions passed"
  exit 0
else
  echo "[FAIL] check-setup-block7-overlay-parser: $FAIL_COUNT assertion(s) failed"
  exit 1
fi
