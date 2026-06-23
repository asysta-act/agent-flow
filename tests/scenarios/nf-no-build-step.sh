#!/usr/bin/env bash
# Verifies: AC-NF-002
# Description: No build manifest (package.json, pyproject.toml, Makefile, Dockerfile)
#   at repository root
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Guard: ensure we are not running from staging location
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# ---------------------------------------------------------------------------
# Build manifests that must NOT exist at repo root
# ---------------------------------------------------------------------------
FORBIDDEN_FILES=(
  "package.json"
  "pyproject.toml"
  "Makefile"
  "Dockerfile"
  "setup.py"
  "setup.cfg"
  "pom.xml"
  "build.gradle"
  "Cargo.toml"
  "go.mod"
)

echo "--- Checking for build manifests at repo root ---"
for manifest in "${FORBIDDEN_FILES[@]}"; do
  if [ -f "$REPO_ROOT/$manifest" ]; then
    fail "$manifest found at repo root — plugin must remain pure markdown with no build step"
  else
    echo "OK: $manifest absent"
  fi
done

# ---------------------------------------------------------------------------
# Assertion: tests/mock-project/ may have pyproject.toml for testing, that is OK
# ---------------------------------------------------------------------------
echo "--- Note: tests/mock-project/ build manifests are allowed (test fixtures) ---"
if [ -f "$REPO_ROOT/tests/mock-project/pyproject.toml" ]; then
  echo "INFO: tests/mock-project/pyproject.toml exists (expected test fixture)"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-NF-002 — no build manifests at repo root"
fi
exit "$FAIL"
