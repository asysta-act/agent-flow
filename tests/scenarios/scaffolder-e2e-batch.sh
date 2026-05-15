#!/usr/bin/env bash
# Test: Scaffolder agent has Batch 7 (E2E) and Batch 8 (Docs) with correct structure
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
SCAFFOLDER="$REPO_ROOT/agents/scaffolder.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

# Pre-extract Batch 7 section once -- avoids `sed | grep -q` SIGPIPE race on Linux
BATCH7_SECTION=$(sed -n '/Batch 7/,/Batch 8/p' "$SCAFFOLDER")

# Batch 7 heading present
grep -q "Batch 7.*E2E" "$SCAFFOLDER" || fail "scaffolder.md missing Batch 7 (E2E Tests)"

# Batch 7 conditional pattern (section-scoped: must appear within Batch 7 section, not Batch 6)
contains "$BATCH7_SECTION" "Skip this batch entirely" || fail "scaffolder.md Batch 7 missing conditional skip pattern"

# Batch 7 Playwright detection (cross-stack)
grep -q "@playwright/test" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing JS Playwright dependency check"
grep -q "pytest-playwright" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Python Playwright dependency check"
grep -q "capybara-playwright-driver" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Ruby Playwright dependency check"
grep -q "com.microsoft.playwright" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Java Playwright dependency check"
grep -q "Microsoft.Playwright" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing .NET Playwright dependency check"
grep -q "playwright-go" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Go Playwright dependency check"

# Batch 7 playwright.config
grep -q "playwright.config" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing playwright.config generation"

# Batch 7 smoke test (section-scoped)
contains "$BATCH7_SECTION" "smoke" || fail "scaffolder.md Batch 7 missing smoke test reference"

# Batch 8 heading
grep -q "Batch 8.*Documentation" "$SCAFFOLDER" || fail "scaffolder.md missing Batch 8 (Application Documentation)"

# Batch 8 always generated
grep -q "always generated" "$SCAFFOLDER" || fail "scaffolder.md Batch 8 missing 'always generated' marker"

# Batch 8 ARCHITECTURE.md
grep -q "docs/ARCHITECTURE.md" "$SCAFFOLDER" || fail "scaffolder.md Batch 8 missing docs/ARCHITECTURE.md reference"

# Batch 8 required sections
for section in "Stack Choices" "Directory Structure" "Key Patterns" "Configuration Approach"; do
  grep -q "$section" "$SCAFFOLDER" || fail "scaffolder.md Batch 8 missing required section: $section"
done

# Scorecard items
grep -q "E2E test setup" "$SCAFFOLDER" || fail "scaffolder.md scorecard missing 'E2E test setup' item"
grep -qi "App.* documentation\|App documentation" "$SCAFFOLDER" || fail "scaffolder.md scorecard missing 'App documentation' item"

# File count ceiling (context-aware: match exact phrase, not bare number)
grep -q "up to 27" "$SCAFFOLDER" || fail "scaffolder.md constraints missing updated file count ceiling (up to 27)"

# Module Docs in optional sections
grep -q "Module Docs" "$SCAFFOLDER" || fail "scaffolder.md missing Module Docs in CLAUDE.md optional sections"

# Batch 7 cross-stack: language-specific test file generation
grep -q "test_smoke.py" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Python e2e test file (test_smoke.py)"
grep -q "smoke_spec.rb" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Ruby e2e test file (smoke_spec.rb)"
grep -q "SmokeTest.java" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Java e2e test file (SmokeTest.java)"
grep -q "SmokeTest.cs" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing .NET e2e test file (SmokeTest.cs)"
grep -q "smoke_test.go" "$SCAFFOLDER" || fail "scaffolder.md Batch 7 missing Go e2e test file (smoke_test.go)"

# Batch ordering
BATCH7_LINE=$(grep -n "Batch 7" "$SCAFFOLDER" | head -1 | cut -d: -f1)
BATCH8_LINE=$(grep -n "Batch 8" "$SCAFFOLDER" | head -1 | cut -d: -f1)
if [ -z "$BATCH7_LINE" ] || [ -z "$BATCH8_LINE" ] || [ "$BATCH7_LINE" -ge "$BATCH8_LINE" ]; then
  fail "Batch 7 must appear before Batch 8 in scaffolder.md"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: Scaffolder Batch 7 (E2E) + Batch 8 (Docs) structure"
exit "$FAIL"
