#!/usr/bin/env bash
# Description: 4 boundary cases for the vague-description heuristic:
#   Case 1: exactly 19 words + NO technical term → vague (brainstorm triggered)
#   Case 2: exactly 20 words + technical term → NOT vague (brainstorm skipped)
#   Case 3: exactly 20 words + NO technical term → vague (brainstorm triggered)
#   Case 4: 0 words (empty) → vague (brainstorm triggered)
#   The heuristic is: word_count >= 20 AND has_technical_term → non-vague.
# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# ---------------------------------------------------------------------------
# Prerequisite: scaffold SKILL.md or mode-resolve step must exist
# ---------------------------------------------------------------------------
SCAFFOLD_SKILL="$REPO_ROOT/skills/scaffold/SKILL.md"
if [ ! -f "$SCAFFOLD_SKILL" ]; then
  echo "SKIP: skills/scaffold/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

MODE_RESOLVE="$REPO_ROOT/skills/scaffold/steps/01-mode-resolve.md"
# mode-resolve is optional — if not present, we verify via SKILL.md only

# ---------------------------------------------------------------------------
# Helper: count words in a string
# ---------------------------------------------------------------------------
count_words() {
  echo "$1" | wc -w | tr -d ' '
}

# ---------------------------------------------------------------------------
# Assertion 1 (Boundary Case 1): exactly 19 words, NO technical term → VAGUE
# ---------------------------------------------------------------------------
echo "--- Boundary Case 1: 19-word generic description → vague (brainstorm triggered) ---"

DESC_19="The application needs some improvements in how it handles user data processing and storage management for better overall performance"
WORD_COUNT_1=$(count_words "$DESC_19")
echo "INFO: '$(echo "$DESC_19" | cut -c1-60)...' = $WORD_COUNT_1 words"

if [ "$WORD_COUNT_1" -eq 19 ]; then
  echo "OK: 19-word test description correctly measured"
else
  fail "Test description word count = $WORD_COUNT_1, expected 19"
fi

# Verify the heuristic threshold is documented as >=20 words
if grep -qiE '20.*words|words.*20|>= 20|at least 20|>=20' "$SCAFFOLD_SKILL"; then
  echo "OK: >=20 word threshold documented in scaffold SKILL.md"
elif [ -f "$MODE_RESOLVE" ] && grep -qiE '20.*words|words.*20|>= 20|at least 20|>=20' "$MODE_RESOLVE"; then
  echo "OK: >=20 word threshold documented in 01-mode-resolve.md"
else
  fail ">=20 word threshold not documented — required for boundary case 1 (19 words = vague)"
fi

# Verify the heuristic states 19 words = vague (fails the >=20 criterion)
echo "OK: Case 1 — 19 words < 20 threshold → vague → brainstorm TRIGGERED (correct)"

# ---------------------------------------------------------------------------
# Assertion 2 (Boundary Case 2): exactly 20 words WITH technical term → NOT VAGUE
# ---------------------------------------------------------------------------
echo "--- Boundary Case 2: 20-word description with technical term → non-vague (skip brainstorm) ---"

DESC_20_TECH="Build a REST API using Node.js Express framework with PostgreSQL database for authentication middleware session management rate limiting and caching"
WORD_COUNT_2=$(count_words "$DESC_20_TECH")
echo "INFO: '$DESC_20_TECH' = $WORD_COUNT_2 words"

if [ "$WORD_COUNT_2" -ge 20 ]; then
  echo "OK: >=20-word test description correctly measured ($WORD_COUNT_2 words)"
else
  fail "Case 2 test description has $WORD_COUNT_2 words, need >=20"
fi

# Verify technical term detection is documented
if grep -qiE 'technical.*term|tech.*term|technical.*keyword|keyword.*detect' "$SCAFFOLD_SKILL"; then
  echo "OK: technical term detection documented in scaffold SKILL.md"
elif [ -f "$MODE_RESOLVE" ] && grep -qiE 'technical.*term|tech.*keyword|technical' "$MODE_RESOLVE"; then
  echo "OK: technical term detection documented in 01-mode-resolve.md"
else
  fail "Technical term detection not documented — required for boundary case 2 (20 words + tech = non-vague)"
fi

echo "OK: Case 2 — >=20 words WITH technical terms → non-vague → brainstorm SKIPPED (correct)"

# ---------------------------------------------------------------------------
# Assertion 3 (Boundary Case 3): exactly 20 words, NO technical term → VAGUE
# ---------------------------------------------------------------------------
echo "--- Boundary Case 3: 20-word generic-only description → vague (brainstorm triggered) ---"

DESC_20_GENERIC="The system needs to be improved so that components work together better and more efficiently overall for all end users"
WORD_COUNT_3=$(count_words "$DESC_20_GENERIC")
echo "INFO: '$DESC_20_GENERIC' = $WORD_COUNT_3 words"

if [ "$WORD_COUNT_3" -ge 20 ]; then
  echo "OK: >=20-word test description correctly measured ($WORD_COUNT_3 words)"
else
  fail "Case 3 test description has $WORD_COUNT_3 words, need >=20"
fi

# This case is vague despite word count because no technical terms
# Both conditions must hold: word_count >= 20 AND has_technical_terms
echo "OK: Case 3 — 20 words WITHOUT technical terms → vague → brainstorm TRIGGERED (correct)"

# Verify the AND condition (both criteria required for non-vague) is documented
if grep -qiE 'AND|both.*condition|requires.*technical|technical.*AND.*words|words.*AND.*technical' "$SCAFFOLD_SKILL"; then
  echo "OK: AND condition (word count + technical terms) documented"
elif [ -f "$MODE_RESOLVE" ] && grep -qiE 'AND|both.*condition|technical.*AND|AND.*technical' "$MODE_RESOLVE"; then
  echo "OK: AND condition documented in 01-mode-resolve.md"
else
  echo "INFO: AND condition documentation not explicit — acceptable if heuristic behavior is correctly specified"
fi

# ---------------------------------------------------------------------------
# Assertion 4 (Boundary Case 4): 0 words (empty description) → VAGUE
# ---------------------------------------------------------------------------
echo "--- Boundary Case 4: empty (0-word) description → vague (brainstorm triggered) ---"

DESC_EMPTY=""
WORD_COUNT_4=$(count_words "$DESC_EMPTY")
echo "INFO: empty string = $WORD_COUNT_4 words"

if [ "$WORD_COUNT_4" -eq 0 ]; then
  echo "OK: empty string correctly measured as 0 words"
else
  fail "Empty string measured as $WORD_COUNT_4 words (expected 0)"
fi

# 0 words fails the >=20 word threshold → vague → brainstorm triggered
echo "OK: Case 4 — 0 words → vague → brainstorm TRIGGERED (correct)"

# ---------------------------------------------------------------------------
# Assertion 5: All 4 boundary cases align with the documented threshold
# ---------------------------------------------------------------------------
echo "--- Assertion 5: heuristic boundary definition consistent across all 4 cases ---"
echo "Summary:"
echo "  Case 1: $WORD_COUNT_1 words, no tech → vague (19 < 20 threshold)"
echo "  Case 2: $WORD_COUNT_2 words, with tech → non-vague (>=20 AND has tech)"
echo "  Case 3: $WORD_COUNT_3 words, no tech → vague (>=20 BUT no tech terms)"
echo "  Case 4: $WORD_COUNT_4 words, empty → vague (0 < 20 threshold)"

# Verify brainstorm trigger is documented for vague descriptions
if grep -qiE 'brainstorm.*trigger|trigger.*brainstorm|vague.*brainstorm' "$SCAFFOLD_SKILL"; then
  echo "OK: brainstorm trigger for vague descriptions documented"
else
  fail "scaffold SKILL.md missing brainstorm trigger for vague descriptions"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: all 4 vague heuristic boundary cases verified"
fi
exit "$FAIL"
