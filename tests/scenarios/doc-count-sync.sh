#!/bin/bash
# Covers: AC-CNT-1 (CLAUDE.md states 17 skills),
#         AC-CNT-2 (README.md states 17 skills),
#         AC-CNT-3 (all 5 count-bearing docs reference 17 core),
#         AC-CNT-4 (no production claim of 22 skills or 16 core),
#         AC-CNT-5 (FC-23, REWORKED for the .agent-flow/config.toml migration, per
#           design.md section 5.3): the doc-count-drift sync set (CLAUDE.md, README.md,
#           docs/reference/automation-config.md, docs/guides/installation.md,
#           docs/architecture.md) all reference .agent-flow/config.toml as the config
#           location -- these 5 docs "encode the config lives in CLAUDE.md assumption"
#           per REQ-24 and must move together.
# Note: Skill count corrected from 18 -> 17 for v1.0.0 public release.
# Expected RED (AC-CNT-5, pre-impl): none of the 5 docs reference .agent-flow/config.toml
#   yet -- they all still describe the inline CLAUDE.md Automation Config location.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/assert.sh
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: v9-5-doc-count-sync — $1"; FAIL=1; }

# AC-CNT-1: CLAUDE.md states 17 skills
if grep -qE '\b17 skills\b|skills.*\b17\b|17\b.*skills' "$REPO_ROOT/CLAUDE.md"; then
  echo "PASS: CLAUDE.md references 17 skills"
else
  fail "CLAUDE.md does not reference 17 skills"
fi

# AC-CNT-2: README.md states 17 skills
if grep -qE '\b17 skills\b|skills.*\b17\b|17\b.*skills' "$REPO_ROOT/README.md"; then
  echo "PASS: README.md references 17 skills"
else
  fail "README.md does not reference 17 skills"
fi

# AC-CNT-3: All 5 docs reference 17 core
for f in CLAUDE.md README.md docs/reference/automation-config.md docs/reference/skills.md docs/architecture.md; do
  if grep -qE '17[[:space:]]+(core|shared pipeline|contracts)' "$REPO_ROOT/$f"; then
    echo "PASS: $f references 17 core"
  else
    fail "$f does not reference 17 core / 17 contracts / 17 shared pipeline"
  fi
done

# AC-CNT-4: No stale "22 skills" or "16 core" in production docs
COUNT=$(grep -rn '\b22 skills\b\|\b16 core\b\|\b16 contracts\b' \
  --include='*.md' \
  "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/README.md" "$REPO_ROOT/docs/" \
  2>/dev/null \
  | grep -v 'CHANGELOG.md' \
  | grep -v 'docs/plans/' \
  | wc -l | tr -d ' ')

if [ "$COUNT" -eq 0 ]; then
  echo "PASS: no stale '22 skills' or '16 core' claims in production docs"
else
  echo "FAIL: v9-5-doc-count-sync — found $COUNT stale count claim(s) in production docs"
  grep -rn '\b22 skills\b\|\b16 core\b\|\b16 contracts\b' \
    --include='*.md' \
    "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/README.md" "$REPO_ROOT/docs/" \
    2>/dev/null \
    | grep -v 'CHANGELOG.md' \
    | grep -v 'docs/plans/' \
    || true
  FAIL=1
fi

# AC-CNT-5 (FC-23): the doc-count-drift sync set all reference .agent-flow/config.toml
CONFIG_LOCATION_DOCS=(
  "CLAUDE.md"
  "README.md"
  "docs/reference/automation-config.md"
  "docs/guides/installation.md"
  "docs/architecture.md"
)
for f in "${CONFIG_LOCATION_DOCS[@]}"; do
  content="$(cat "$REPO_ROOT/$f" 2>/dev/null || true)"
  if contains "$content" ".agent-flow/config.toml"; then
    echo "PASS: $f references .agent-flow/config.toml"
  else
    fail "$f does not reference .agent-flow/config.toml (doc-count-drift sync set, FC-23/REQ-24)"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v9-5-doc-count-sync — all 5 docs correctly reference 17 skills, 17 core, and .agent-flow/config.toml"
fi
exit "$FAIL"
