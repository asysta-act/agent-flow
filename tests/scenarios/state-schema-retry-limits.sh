#!/usr/bin/env bash
# Test: state/schema.md contains spec_iterations and root_cause_iterations retry limit fields
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

SCHEMA="$REPO_ROOT/state/schema.md"

if [ ! -f "$SCHEMA" ]; then
  fail "state/schema.md does not exist"
  exit "$FAIL"
fi

# Field table contains config.retry_limits.spec_iterations with default 5
if ! grep 'config.retry_limits.spec_iterations' "$SCHEMA" | grep -q '5'; then
  fail "state/schema.md missing field config.retry_limits.spec_iterations with default 5"
fi

# Field table contains config.retry_limits.root_cause_iterations with default 3
if ! grep 'config.retry_limits.root_cause_iterations' "$SCHEMA" | grep -q '3'; then
  fail "state/schema.md missing field config.retry_limits.root_cause_iterations with default 3"
fi

# spec_iterations row appears after build_retries row and before infrastructure row
build_line=$(grep -n 'build_retries' "$SCHEMA" | grep '|' | tail -1 | cut -d: -f1)
spec_line=$(grep -n 'spec_iterations' "$SCHEMA" | grep '|' | head -1 | cut -d: -f1)
infra_line=$(grep -n '| `infrastructure`' "$SCHEMA" | head -1 | cut -d: -f1)

if [ -z "$build_line" ] || [ -z "$spec_line" ] || [ -z "$infra_line" ]; then
  fail "state/schema.md: Could not find all required row markers (build_retries, spec_iterations, infrastructure)"
else
  if [ "$spec_line" -le "$build_line" ]; then
    fail "state/schema.md: spec_iterations row (line $spec_line) must appear after build_retries row (line $build_line)"
  fi
  if [ "$spec_line" -ge "$infra_line" ]; then
    fail "state/schema.md: spec_iterations row (line $spec_line) must appear before infrastructure row (line $infra_line)"
  fi
fi

# JSON example block contains both spec_iterations and root_cause_iterations fields
if ! grep -q '"spec_iterations"' "$SCHEMA"; then
  fail "state/schema.md: JSON example block missing \"spec_iterations\" field"
fi
if ! grep -q '"root_cause_iterations"' "$SCHEMA"; then
  fail "state/schema.md: JSON example block missing \"root_cause_iterations\" field"
fi

# build_retries line in JSON block ends with comma (trailing comma fix)
if ! grep '"build_retries"' "$SCHEMA" | grep -v '|' | grep -q ','; then
  fail "state/schema.md: JSON example 'build_retries' line does not end with comma (trailing comma required before spec_iterations)"
fi

# spec_iterations description uses the ↔ separator (spec-writer↔spec-reviewer)
if ! grep 'spec_iterations' "$SCHEMA" | grep -q '↔'; then
  fail "state/schema.md: spec_iterations description missing ↔ separator (expected: spec-writer↔spec-reviewer)"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: state/schema.md retry limit fields spec_iterations and root_cause_iterations are present and correctly structured"
exit "$FAIL"
