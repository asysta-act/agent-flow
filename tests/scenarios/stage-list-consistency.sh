#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-stage-list-consistency.sh
# Falsifies:,
# FC mapped:   FC-REL-1 (a/b/c/d/e)
# What it checks:
#   Parses canonical stage names from 3 authoritative sources and asserts parity:
#   Source 1: hooks/validate-dispatch.sh — STAGES=(...) array
#   Source 2: skills/fix-bugs/SKILL.md + skills/implement-feature/SKILL.md
#             — <stage_allowlist> blocks (REQUIRED + OPTIONAL union)
#   Source 3: state/schema.md — "- **Applicable stages:**" anchor (L411)
#   ASSERT-1) S1 union == S3 union (strict: same 10 stages, no extras)
#   ASSERT-2) Every S2 stage is also in S1 (subset check)
#   ASSERT-3) Sanity floor: >= 10 stages extracted from S1 and S3
#   No jq, no yq, no python. Line budget: 60-120.
# Expected GREEN phase: PASS (stages already consistent); FAIL on future drift.
# ===========================================================================
set -uo pipefail

REPO_ROOT="${CEOS_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
. "$REPO_ROOT/tests/lib/assert.sh"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: FC-REL-1.$1" >&2; FAIL=1; }

# Source 1: STAGES from hooks/validate-dispatch.sh single-line array
HOOK="hooks/validate-dispatch.sh"
[ -f "$HOOK" ] || { fail "src1-missing: $HOOK not found"; exit 1; }
S1=$(grep -E '^STAGES=\(' "$HOOK" \
  | sed -E 's/^STAGES=\(([^)]*)\).*/\1/' \
  | tr ' ' '\n' | grep -v '^$' | sort -u)

# Source 2: <stage_allowlist> union from both skills
S2=""
for skill_file in skills/fix-bugs/SKILL.md skills/implement-feature/SKILL.md; do
  [ -f "$skill_file" ] || { fail "src2-missing: $skill_file not found"; continue; }
  block=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' "$skill_file")
  names=$(printf '%s' "$block" \
    | sed -E 's/(required|optional):[[:space:]]*//' \
    | tr '[],' '\n' | grep -oE '[a-z][a-z0-9_]+' | grep -v '^$')
  S2=$(printf '%s\n%s' "$S2" "$names")
done
S2=$(printf '%s' "$S2" | grep -v '^$' | sort -u)

# Source 3: state/schema.md "Applicable stages:" anchor (L411 — line-prefix unique).
# Character class MUST be [a-z0-9_]+ (not [a-z_]+) to capture "e2e_test" (has digit).
# Empirically verified 2026-05-12: [a-z_]+ extracts only 9 (drops e2e_test).
SCHEMA="state/schema.md"
[ -f "$SCHEMA" ] || { fail "src3-missing: $SCHEMA not found"; exit 1; }
S3=$(grep -E '^\- \*\*Applicable stages:\*\*' "$SCHEMA" \
  | grep -oE '`[a-z0-9_]+`' | tr -d '`' | sort -u)

# ASSERT-1: S1 == S3 (strict union equality)
diff_s1_s3=$(comm -3 <(printf '%s\n' "$S1") <(printf '%s\n' "$S3"))
if [ -n "$diff_s1_s3" ]; then
  fail "s1-s3-drift: hooks/validate-dispatch.sh STAGES vs state/schema.md 'Applicable stages' diverged:"
  printf '%s\n' "$diff_s1_s3" >&2
fi

# ASSERT-2: Every S2 stage is in S1 (per-skill allow-lists are subsets)
while IFS= read -r stage; do
  [ -z "$stage" ] && continue
  if ! contains $'\n'"$S1"$'\n' $'\n'"$stage"$'\n'; then
    fail "s2-not-in-s1: skill stage '$stage' not in hooks/validate-dispatch.sh STAGES"
  fi
done <<< "$S2"

# ASSERT-3: Sanity floor >= 10 stages
s1_count=$(printf '%s\n' "$S1" | grep -c '.' || true)
s3_count=$(printf '%s\n' "$S3" | grep -c '.' || true)
[ "$s1_count" -ge 10 ] || fail "s1-count: extracted only $s1_count stages from STAGES (expected >= 10)"
[ "$s3_count" -ge 10 ] || fail "s3-count: extracted only $s3_count stages from schema (expected >= 10; verify [a-z0-9_]+ class captures e2e_test)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-stage-list-consistency — ${s1_count} stages consistent across hooks/STAGES, skill allow-lists, schema/Applicable-stages"
  exit 0
fi
exit 1
