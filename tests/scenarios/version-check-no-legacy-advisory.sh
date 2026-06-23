#!/bin/bash
# Covers: skills/version-check/SKILL.md lines 86-96 untouched — version comparison logic present
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

FILE="$REPO_ROOT/skills/version-check/SKILL.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: skills/version-check/SKILL.md not found"
  exit 1
fi

BLOCK=$(sed -n '86,96p' "$FILE")
if matches_re "$BLOCK" 'remote_version|repo_version|installed_version|pull|comparison'; then
  echo "PASS: version comparison logic (lines 86-96) preserved"
  exit 0
else
  echo "FAIL: version comparison logic not found in lines 86-96 of version-check SKILL.md"
  exit 1
fi
