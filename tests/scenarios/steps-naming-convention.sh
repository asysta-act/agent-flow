#!/usr/bin/env bash
# Verifies: AC-STEPS-007
# Description: Every step file across all 3 pipelines matches ^[0-9][0-9]-[a-z0-9-]+\.md$
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

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

PIPELINES=(fix-bugs implement-feature scaffold)
VALID_REGEX='^[0-9][0-9]-[a-z0-9-]+\.md$'

TMPDIR_STEPS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_STEPS"' EXIT INT TERM

for pipeline in "${PIPELINES[@]}"; do
  STEPS_DIR="$REPO_ROOT/skills/$pipeline/steps"
  echo "--- Checking $pipeline step filename naming convention ---"
  if [ ! -d "$STEPS_DIR" ]; then
    echo "SKIP: skills/$pipeline/steps/ not found (implementation pending)" >&2
    exit 77
  fi

  find "$STEPS_DIR" -maxdepth 1 -name '*.md' -type f > "$TMPDIR_STEPS/${pipeline}_steps.txt"
  while IFS= read -r step_file; do
    basename_file=$(basename "$step_file")
    if matches_re "$basename_file" "$VALID_REGEX"; then
      echo "OK: $pipeline/steps/$basename_file matches naming convention"
    else
      fail "$pipeline/steps/$basename_file does NOT match naming convention '$VALID_REGEX'"
    fi
  done < "$TMPDIR_STEPS/${pipeline}_steps.txt"
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-STEPS-007 — all step files match ^[0-9][0-9]-[a-z0-9-]+\.md$ naming"
fi
exit "$FAIL"
