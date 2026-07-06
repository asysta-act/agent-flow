#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-schema-witness-coverage.sh
# FC mapped:   FC-3 (schema documents witness + agent_name + stage_name; schema_version stable)
# What it checks:
#   A)  state/schema.md contains '#### `stages.{stage}.dispatch_witness`' sub-section
#   A') state/schema.md contains '#### `stages.{stage}.agent_name`' sub-section
#   A") state/schema.md contains '#### `stages.{stage}.stage_name`' sub-section
#   A3) state/schema.md contains '#### `stages.{stage}.prompt_head_128`' sub-section
#   A4) state/schema.md contains '#### `stages.{stage}.overlay_source`' sub-section
#   A5) state/schema.md contains '#### `stages.{stage}.overlay_digest`' sub-section
#   B)  All 10 stage names appear in state/schema.md
#   C)  schema_version literal `"1.0"` still present (5-tuple change is additive)
# Expected RED phase: FAIL — state/schema.md does not yet document these fields
# Expected GREEN phase (post-impl): PASS
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

SCHEMA="state/schema.md"
if [ ! -f "$SCHEMA" ]; then
  fail "FC-3.file: $SCHEMA missing"
  exit 1
fi

# A. dispatch_witness sub-section header
if ! grep -qE '^#### `stages\.\{stage\}\.dispatch_witness`$' "$SCHEMA"; then
  fail "FC-3.A: $SCHEMA missing '#### \`stages.{stage}.dispatch_witness\`' sub-section header"
fi

# A'. agent_name sub-section header
if ! grep -qE '^#### `stages\.\{stage\}\.agent_name`$' "$SCHEMA"; then
  fail "FC-3.A-prime-1: $SCHEMA missing '#### \`stages.{stage}.agent_name\`' sub-section header"
fi

# A". stage_name sub-section header
if ! grep -qE '^#### `stages\.\{stage\}\.stage_name`$' "$SCHEMA"; then
  fail "FC-3.A-prime-2: $SCHEMA missing '#### \`stages.{stage}.stage_name\`' sub-section header"
fi

# A3-A5. New 5-tuple witness-input field headers (additive — schema_version stays 1.0).
if ! grep -qE '^#### `stages\.\{stage\}\.prompt_head_128`$' "$SCHEMA"; then
  fail "FC-3.A3: $SCHEMA missing '#### \`stages.{stage}.prompt_head_128\`' sub-section header"
fi
if ! grep -qE '^#### `stages\.\{stage\}\.overlay_source`$' "$SCHEMA"; then
  fail "FC-3.A4: $SCHEMA missing '#### \`stages.{stage}.overlay_source\`' sub-section header"
fi
if ! grep -qE '^#### `stages\.\{stage\}\.overlay_digest`$' "$SCHEMA"; then
  fail "FC-3.A5: $SCHEMA missing '#### \`stages.{stage}.overlay_digest\`' sub-section header"
fi

# B. All 10 stage names appear in schema.md
STAGES=(triage code_analysis reproduce_browser fixer_reviewer smoke_check test e2e_test browser_verification acceptance_gate publisher)
for stage in "${STAGES[@]}"; do
  if ! grep -qw "$stage" "$SCHEMA"; then
    fail "FC-3.B: $SCHEMA missing stage name '${stage}'"
  fi
done

# C. schema_version still "1.0"
# Accept either:
#   `schema_version` ... `"1.0"`
#   OR the legacy form `"schema_version": "1.0"` in JSON example block.
if ! grep -qE '`schema_version`.*`"1\.0"`|"schema_version"[[:space:]]*:[[:space:]]*"1\.0"' "$SCHEMA"; then
  fail "FC-3.C: $SCHEMA schema_version no longer '1.0' (bump is FORBIDDEN)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-schema-witness-coverage — schema documents witness/agent_name/stage_name + 5-tuple inputs (prompt_head_128/overlay_source/overlay_digest) across 10 stages; schema_version=1.0 stable"
  exit 0
fi
exit 1
