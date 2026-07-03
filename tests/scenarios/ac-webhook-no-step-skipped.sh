#!/usr/bin/env bash
set -euo pipefail

# AC-33: No step-skipped webhook emission site exists in pipeline skills or core
# Traces: WEBHOOK-R7
# Description: Verifies 'step-skipped' does not appear in pipeline SKILL.md files or post-publish-hook

# NOTE: This test checks negative absence — passes green before Phase 7 IF no such string exists.
# Must remain green after Phase 7 (NOT_IN_SCOPE per requirements.md Section 6).

# CONSOLIDATION NOTE (CONTRIBUTING.md rule 9 — "No duplicate coverage for an
# existing AC id"): this scenario and webhook-no-step-skipped.sh previously
# asserted the identical criterion via near-duplicate grep logic (same FILES
# array, same `grep -qF 'step-skipped'` check) — the exact kind of ungoverned
# test regeneration rule 9 exists to prevent. This file (ac-webhook-no-step-skipped.sh,
# the canonical AC-labeled scenario for AC-33/WEBHOOK-R7) is now the single source
# of truth for the assertion logic; webhook-no-step-skipped.sh delegates to it
# instead of re-implementing the same check, so both scenario names still resolve
# to one PASS/FAIL outcome without duplicated logic to drift out of sync.

cd "$(dirname "$0")/../.."

FAIL=0

FILES=(
  "skills/fix-ticket/SKILL.md"
  "skills/fix-bugs/SKILL.md"
  "skills/implement-feature/SKILL.md"
  "skills/scaffold/SKILL.md"
  "core/post-publish-hook.md"
)

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    continue  # file may not exist yet; skip
  fi
  if grep -qF 'step-skipped' "$f"; then
    echo "FAIL: '$f' contains 'step-skipped' (must be absent)" >&2
    FAIL=1
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS: no step-skipped event emission site found in pipeline skills/core"
exit "$FAIL"
