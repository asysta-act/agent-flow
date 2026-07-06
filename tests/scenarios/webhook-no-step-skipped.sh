#!/usr/bin/env bash
set -euo pipefail

# AC-33: No step-skipped webhook emission site in pipeline skills or core
# Traces: WEBHOOK-R7
# Description: Verifies 'step-skipped' is absent from all pipeline SKILL.md files and core hook

# CONSOLIDATION NOTE (CONTRIBUTING.md rule 9 — "No duplicate coverage for an
# existing AC id"): this scenario and ac-webhook-no-step-skipped.sh previously
# asserted the identical criterion via near-duplicate grep logic (same FILES
# array, same `grep -qF 'step-skipped'` check) — the exact kind of ungoverned
# test regeneration rule 9 exists to prevent. The assertion logic now has a
# single source of truth in ac-webhook-no-step-skipped.sh (the canonical
# AC-labeled scenario for AC-33/WEBHOOK-R7); this file delegates to it instead
# of re-implementing the same check, so both scenario names still resolve to
# one PASS/FAIL outcome without duplicated logic to drift out of sync.

exec bash "$(dirname "$0")/ac-webhook-no-step-skipped.sh"
