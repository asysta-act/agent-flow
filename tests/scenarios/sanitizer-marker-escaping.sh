#!/usr/bin/env bash
# Test: core/external-input-sanitizer.md has step 1b with marker escape logic
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

SANITIZER="$REPO_ROOT/core/external-input-sanitizer.md"

if [ ! -f "$SANITIZER" ]; then
  fail "core/external-input-sanitizer.md does not exist"
  exit "$FAIL"
fi

# Step 1b exists (marker escape logic step)
if ! grep -q '1b\.' "$SANITIZER"; then
  fail "core/external-input-sanitizer.md missing step 1b"
fi

# Step 1b specifies [ESCAPED: EXTERNAL INPUT START] replacement format
if ! grep -q '\[ESCAPED: EXTERNAL INPUT START\]' "$SANITIZER"; then
  fail "core/external-input-sanitizer.md Step 1b missing replacement format '[ESCAPED: EXTERNAL INPUT START]'"
fi

# Step 1b specifies [ESCAPED: EXTERNAL INPUT END] replacement format
if ! grep -q '\[ESCAPED: EXTERNAL INPUT END\]' "$SANITIZER"; then
  fail "core/external-input-sanitizer.md Step 1b missing replacement format '[ESCAPED: EXTERNAL INPUT END]'"
fi

# Step 1b mentions idempotency
if ! grep -A 10 '1b\.' "$SANITIZER" | grep -qi 'idempotent'; then
  fail "core/external-input-sanitizer.md Step 1b does not mention idempotency"
fi

# Step 1b appears before step 2 (wrapping) in file order
step1b_line=$(grep -n '1b\.' "$SANITIZER" | head -1 | cut -d: -f1)
step2_line=$(grep -n '^2\. Wrap each piece' "$SANITIZER" | head -1 | cut -d: -f1)

if [ -z "$step1b_line" ] || [ -z "$step2_line" ]; then
  fail "core/external-input-sanitizer.md: Could not find step 1b or step 2 line markers"
else
  if [ "$step1b_line" -ge "$step2_line" ]; then
    fail "core/external-input-sanitizer.md: Step 1b (line $step1b_line) must appear before Step 2 wrapping (line $step2_line)"
  fi
fi

# Step 1b says "Before wrapping" to clarify ordering
if ! grep '1b\.' "$SANITIZER" | grep -qi 'before wrapping'; then
  fail "core/external-input-sanitizer.md Step 1b does not say 'Before wrapping' (ordering clarification missing)"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: core/external-input-sanitizer.md Step 1b marker escape logic is present and correctly structured"
exit "$FAIL"
