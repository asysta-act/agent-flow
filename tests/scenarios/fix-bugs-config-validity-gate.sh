#!/usr/bin/env bash
# Test: fix-bugs SKILL.md contains a Config Validity Gate mirroring
# implement-feature.md's Step 0b, adapted to fix-bugs' own heading/step
# numbering conventions (fix-bugs already uses "Step 0a"/"Step 0b" for
# argument auto-detection and resume detection, and delegates its block
# comment template to core/block-handler.md rather than inlining it, so
# this gate is a "### Config Validity Gate" sub-heading under
# "## Configuration", not a colliding top-level "Step 0b").
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

FIX_BUGS="$REPO_ROOT/skills/fix-bugs/SKILL.md"

if [ ! -f "$FIX_BUGS" ]; then
  fail "skills/fix-bugs/SKILL.md does not exist"
  exit "$FAIL"
fi

# Config Validity Gate heading exists
if ! grep -q '### Config Validity Gate' "$FIX_BUGS"; then
  fail "skills/fix-bugs/SKILL.md missing heading: '### Config Validity Gate'"
fi

# Extract the gate section as a single-line blob so natural prose wrapping
# doesn't defeat multi-term checks below.
GATE_BLOB=$(grep -A 20 '### Config Validity Gate' "$FIX_BUGS" | tr '\n' ' ')

# Gate references implement-feature.md Step 0b as canonical source
if ! grep -q 'implement-feature/SKILL.md' <<< "$GATE_BLOB" || ! grep -q 'Step 0b: Config Validity Gate' <<< "$GATE_BLOB"; then
  fail "skills/fix-bugs/SKILL.md Config Validity Gate does not reference implement-feature/SKILL.md's Step 0b as canonical source"
fi

# Gate checks all 5 required config sections (matches this skill's own
# "## Configuration" required-sections list)
if ! grep -q 'Issue Tracker' <<< "$GATE_BLOB" || ! grep -q 'Source Control' <<< "$GATE_BLOB" || \
   ! grep -q 'PR Rules' <<< "$GATE_BLOB" || ! grep -q 'Build & Test' <<< "$GATE_BLOB"; then
  fail "skills/fix-bugs/SKILL.md Config Validity Gate does not check the required sections (Issue Tracker, Source Control, PR Rules, Build & Test) together"
fi

# Block handling is delegated to core/block-handler.md (thin-controller
# convention), not inlined as a literal '[agent-flow] Pipeline Block' block
if ! grep -q 'core/block-handler.md' "$FIX_BUGS"; then
  fail "skills/fix-bugs/SKILL.md does not delegate block handling to core/block-handler.md"
fi
if grep -q '\[agent-flow\].*Pipeline Block' "$FIX_BUGS"; then
  fail "skills/fix-bugs/SKILL.md inlines a literal Pipeline Block template — thin controllers should delegate to core/block-handler.md instead"
fi

# Config Validity Gate appears between the Configuration section's required-
# sections list and the Preflight checks section (structural position).
# The section was renamed from "Architecture freshness" to "Preflight checks"
# when dispatch-enforcement-preflight was folded into it alongside
# architecture-freshness (v2.0) -- match either name so this stays green
# across that rename.
config_line=$(grep -n '^## Configuration' "$FIX_BUGS" | head -1 | cut -d: -f1)
gate_line=$(grep -n '### Config Validity Gate' "$FIX_BUGS" | head -1 | cut -d: -f1)
arch_line=$(grep -nE '^## (Architecture freshness|Preflight checks)' "$FIX_BUGS" | head -1 | cut -d: -f1)

if [ -z "$config_line" ] || [ -z "$gate_line" ] || [ -z "$arch_line" ]; then
  fail "skills/fix-bugs/SKILL.md: could not find all required structural markers (Configuration, Config Validity Gate, Architecture freshness/Preflight checks)"
else
  if [ "$gate_line" -le "$config_line" ]; then
    fail "skills/fix-bugs/SKILL.md: Config Validity Gate (line $gate_line) must appear after the Configuration heading (line $config_line)"
  fi
  if [ "$gate_line" -ge "$arch_line" ]; then
    fail "skills/fix-bugs/SKILL.md: Config Validity Gate (line $gate_line) must appear before Architecture freshness/Preflight checks (line $arch_line)"
  fi
fi

# Gate says it proceeds to Step 00 (fix-bugs' own zero-padded Step Dispatch
# numbering — see the "| 00 |" row in ## Step Dispatch)
if ! grep -A 15 '### Config Validity Gate' "$FIX_BUGS" | grep -q 'Step 00'; then
  fail "skills/fix-bugs/SKILL.md Config Validity Gate missing terminal instruction referencing Step 00"
fi

[ "$FAIL" -eq 0 ] && echo "PASS: fix-bugs SKILL.md Config Validity Gate is present and correctly structured"
exit "$FAIL"
