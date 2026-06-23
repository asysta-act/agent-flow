#!/bin/bash
# Test: Fix verification step exists in fix-bugs, implement-feature
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"

# v10 thin-controller: verification steps live in step files (publish step
# contains fix-verification block). Aggregate SKILL.md + steps/*.md.
fixbugs_agg=$( cat "$REPO_ROOT/skills/fix-bugs/SKILL.md" "$REPO_ROOT/skills/fix-bugs/steps"/*.md 2>/dev/null )
if matches_re "$fixbugs_agg" 'Fix Verification|fix-verification|fix_verification'; then
  echo "PASS: fix-bugs has Fix Verification step (in SKILL.md or step file)"
else
  echo "FAIL: fix-bugs missing Fix Verification step"
  exit 1
fi

impl_agg=$( cat "$REPO_ROOT/skills/implement-feature/SKILL.md" "$REPO_ROOT/skills/implement-feature/steps"/*.md 2>/dev/null )
if matches_re "$impl_agg" 'Feature Verification|feature-verification|feature_verification'; then
  echo "PASS: implement-feature has Feature Verification step (in SKILL.md or step file)"
else
  echo "FAIL: implement-feature missing Feature Verification step"
  exit 1
fi
