#!/usr/bin/env bash
# Verifies: AC-AGT-003
# Description: agents/analyst.md has Phase Dispatch section, name: analyst, model: sonnet.
# Also verifies CLAUDE.md's Bug-Fix Pipeline callouts for analyst --phase triage
# (reproduction_steps) and --phase impact (<=5 affected files) are backed by matching
# agents/analyst.md content, and that CLAUDE.md's "PR descriptions always in English"
# Key Convention is backed by matching agents/publisher.md enforcement.
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

ANALYST_FILE="$REPO_ROOT/agents/analyst.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
PUBLISHER_FILE="$REPO_ROOT/agents/publisher.md"

if [ ! -f "$ANALYST_FILE" ]; then
  echo "SKIP: agents/analyst.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Assertion 1: frontmatter name: analyst
# ---------------------------------------------------------------------------
echo "--- Assertion 1: analyst.md frontmatter name: analyst ---"
if grep -qE '^name:\s*analyst$' "$ANALYST_FILE"; then
  echo "OK: analyst.md has name: analyst"
else
  fail "analyst.md missing name: analyst in frontmatter"
fi

# ---------------------------------------------------------------------------
# Assertion 2: frontmatter model: sonnet
# ---------------------------------------------------------------------------
echo "--- Assertion 2: analyst.md frontmatter model: sonnet ---"
if grep -qE '^model:\s*sonnet$' "$ANALYST_FILE"; then
  echo "OK: analyst.md has model: sonnet"
else
  fail "analyst.md missing model: sonnet in frontmatter"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Phase Dispatch section present
# ---------------------------------------------------------------------------
echo "--- Assertion 3: analyst.md has ## Phase Dispatch section ---"
if grep -qE '^## Phase Dispatch' "$ANALYST_FILE"; then
  echo "OK: analyst.md has ## Phase Dispatch section"
else
  fail "analyst.md missing ## Phase Dispatch section"
fi

# ---------------------------------------------------------------------------
# Assertion 4: --phase triage and --phase impact documented
# ---------------------------------------------------------------------------
echo "--- Assertion 4: analyst.md documents --phase triage and --phase impact ---"
if grep -qE '\-\-phase.*triage|phase.*triage' "$ANALYST_FILE"; then
  echo "OK: analyst.md documents --phase triage"
else
  fail "analyst.md missing --phase triage documentation"
fi

if grep -qE '\-\-phase.*impact|phase.*impact' "$ANALYST_FILE"; then
  echo "OK: analyst.md documents --phase impact"
else
  fail "analyst.md missing --phase impact documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 5: description mentions both phases
# ---------------------------------------------------------------------------
echo "--- Assertion 5: analyst.md description mentions both phases ---"
if grep -qiE 'triage.*impact|impact.*triage' "$ANALYST_FILE"; then
  echo "OK: analyst.md description references both triage and impact phases"
else
  fail "analyst.md description does not reference both phases"
fi

# ---------------------------------------------------------------------------
# Assertion 6: CLAUDE.md's "+reproduction_steps" callout on ANALYST --phase
# triage is backed by an actual reproduction-steps extraction step in
# agents/analyst.md's triage phase
# ---------------------------------------------------------------------------
echo "--- Assertion 6: CLAUDE.md +reproduction_steps callout matches analyst.md triage phase ---"
if grep -qE 'ANALYST --phase triage.*reproduction_steps' "$CLAUDE_MD"; then
  echo "OK: CLAUDE.md documents +reproduction_steps for ANALYST --phase triage"
else
  fail "CLAUDE.md missing the +reproduction_steps callout on the ANALYST --phase triage pipeline step"
fi

if grep -qE 'Extract reproduction steps for browser automation' "$ANALYST_FILE"; then
  echo "OK: analyst.md triage phase documents reproduction steps extraction"
else
  fail "analyst.md triage phase missing the reproduction steps extraction step (contradicts CLAUDE.md +reproduction_steps callout)"
fi

# ---------------------------------------------------------------------------
# Assertion 7: CLAUDE.md's "<=5 affected files" callout on analyst --phase
# impact is backed by the matching cap in analyst.md's impact-phase Output
# Contract and Constraints
# ---------------------------------------------------------------------------
echo "--- Assertion 7: CLAUDE.md <=5 affected files callout matches analyst.md impact phase ---"
if grep -qF '≤5 affected files' "$CLAUDE_MD"; then
  echo "OK: CLAUDE.md documents analyst (--phase impact) reports <=5 affected files"
else
  fail "CLAUDE.md missing the '<=5 affected files' callout for analyst (--phase impact)"
fi

if grep -qE 'Affected files.*max 5' "$ANALYST_FILE" && grep -qE 'Max 5 affected files in output' "$ANALYST_FILE"; then
  echo "OK: analyst.md impact phase Output Contract and Constraints cap affected files at 5"
else
  fail "analyst.md impact phase missing the max-5 affected files cap (contradicts CLAUDE.md '<=5 affected files' callout)"
fi

# ---------------------------------------------------------------------------
# Assertion 8: CLAUDE.md's "PR descriptions always in English" Key Convention
# is backed by matching enforcement in agents/publisher.md — the agent that
# authors PR descriptions later in the same bug-fix pipeline analyst triages
# ---------------------------------------------------------------------------
echo "--- Assertion 8: CLAUDE.md 'PR descriptions always in English' matches publisher.md enforcement ---"
if grep -qF 'PR descriptions always in English' "$CLAUDE_MD"; then
  echo "OK: CLAUDE.md documents the 'PR descriptions always in English' Key Convention"
else
  fail "CLAUDE.md missing the 'PR descriptions always in English' Key Convention"
fi

if [ -f "$PUBLISHER_FILE" ] && grep -qiE 'never write the pr description in a language other than english' "$PUBLISHER_FILE"; then
  echo "OK: publisher.md enforces English-only PR descriptions"
else
  fail "publisher.md missing English-only PR description enforcement (contradicts CLAUDE.md 'PR descriptions always in English')"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-AGT-003 — analyst.md has correct shape (Phase Dispatch, name, model)"
fi
exit "$FAIL"
