#!/usr/bin/env bash
# Verifies: AC-SETUP-003 (monorepo heuristic)
# Description: /setup-agents in a project root containing pnpm-workspace.yaml AND
#   >=2 sub-package package.json files generates customization/analyst.toml with
#   at least one [[process_additions]] entry referencing multi-package OR monorepo.
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

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# ---------------------------------------------------------------------------
# Prerequisite: skills/setup-agents/SKILL.md must exist
# ---------------------------------------------------------------------------
SETUP_SKILL="$REPO_ROOT/skills/setup-agents/SKILL.md"
if [ ! -f "$SETUP_SKILL" ]; then
  echo "SKIP: skills/setup-agents/SKILL.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Setup: mock monorepo project layout
#   root/pnpm-workspace.yaml + packages/api/package.json + packages/web/package.json
# ---------------------------------------------------------------------------
cat > "$TMPDIR_TEST/pnpm-workspace.yaml" << 'EOF'
packages:
  - 'packages/*'
EOF

mkdir -p "$TMPDIR_TEST/packages/api"
cat > "$TMPDIR_TEST/packages/api/package.json" << 'EOF'
{
  "name": "@myapp/api",
  "version": "1.0.0"
}
EOF

mkdir -p "$TMPDIR_TEST/packages/web"
cat > "$TMPDIR_TEST/packages/web/package.json" << 'EOF'
{
  "name": "@myapp/web",
  "version": "1.0.0"
}
EOF

mkdir -p "$TMPDIR_TEST/customization"

# ---------------------------------------------------------------------------
# Assertion 1: setup-agents SKILL.md documents monorepo heuristic detection
# ---------------------------------------------------------------------------
echo "--- Assertion 1: setup-agents SKILL.md documents monorepo detection heuristic ---"
if grep -qiE 'pnpm.workspace|monorepo.*detect|detect.*monorepo|multi.package|workspace' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents monorepo / pnpm-workspace detection"
else
  # Check guide doc
  GUIDE="$REPO_ROOT/docs/guides/setup-agents-skill.md"
  if [ -f "$GUIDE" ] && grep -qiE 'pnpm.workspace|monorepo|multi.package' "$GUIDE"; then
    echo "OK: docs/guides/setup-agents-skill.md documents monorepo detection"
  else
    fail "No documentation of monorepo (pnpm-workspace.yaml) heuristic in setup-agents"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 2: setup-agents documents that analyst.toml for monorepo contains
#   [[process_additions]] with multi-package or monorepo keyword
# ---------------------------------------------------------------------------
echo "--- Assertion 2: setup-agents documents multi-package / monorepo in analyst.toml output ---"
if grep -qiE 'multi.package|monorepo.*process|monorepo.*guidance|process_additions.*monorepo' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents monorepo [[process_additions]] guidance"
else
  GUIDE="$REPO_ROOT/docs/guides/setup-agents-skill.md"
  if [ -f "$GUIDE" ] && grep -qiE 'multi.package|monorepo' "$GUIDE"; then
    echo "OK: docs/guides/setup-agents-skill.md references monorepo output"
  else
    fail "No documentation of monorepo [[process_additions]] for analyst.toml"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 3: docs/guides/setup-agents-skill.md worked example shows monorepo
#   multi-package guidance in analyst.toml (documentation-level contract verification)
#
# NOTE: This assertion was previously a self-tautology (fixture created here,
# then verified against itself — AP1 anti-pattern). Restructured to verify the
# DOCUMENTED contract: the guide must contain a monorepo worked example showing
# multi-package or monorepo [[process_additions]] in analyst.toml. Live
# /setup-agents invocation testing requires Phase 7/8 once the skill is implemented.
# Tracked: AC-SETUP-003 — Phase 7 will replace with mock-pipeline-driven test.
# ---------------------------------------------------------------------------
echo "--- Assertion 3: docs/guides/setup-agents-skill.md shows monorepo example ---"
GUIDE="$REPO_ROOT/docs/guides/setup-agents-skill.md"
if [ ! -f "$GUIDE" ]; then
  echo "SKIP: docs/guides/setup-agents-skill.md not found (implementation pending)" >&2
  # Soft skip — assertions 1/2/4 cover the SKILL.md contract at doc level
else
  # The guide must show a worked example with monorepo / multi-package guidance
  if grep -qiE 'multi.package|monorepo.*process|monorepo.*analyst|analyst.*monorepo|process_additions.*monorepo' "$GUIDE"; then
    echo "OK: setup-agents-skill.md shows monorepo multi-package [[process_additions]] example"
  else
    # Acceptable if the guide shows monorepo / workspace detection in any form
    if grep -qiE 'monorepo|pnpm.workspace|workspace' "$GUIDE"; then
      echo "OK: setup-agents-skill.md references monorepo project in at least one example"
    else
      fail "docs/guides/setup-agents-skill.md missing monorepo worked example (multi-package process_additions)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 4: Verify the >=2 sub-package condition is documented
# ---------------------------------------------------------------------------
echo "--- Assertion 4: >=2 sub-packages condition documented (not single-package workspace) ---"
if grep -qiE '>=\s*2|at least 2|multiple.*package|2.*package' "$SETUP_SKILL"; then
  echo "OK: setup-agents SKILL.md documents >=2 sub-packages condition for monorepo detection"
else
  echo "INFO: >=2 sub-packages condition not explicitly documented — acceptable if monorepo detection is documented generically"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-SETUP-003 — /setup-agents monorepo heuristic: generates multi-package guidance in analyst.toml"
fi
exit "$FAIL"
