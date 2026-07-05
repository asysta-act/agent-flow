#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-counts-invariants.sh
# FC mapped:   FC-06 (config surface documents 23 [section]s: 5 required + 18 optional)
#              [also gates FC-7's original 4 repo-shape count invariants]
# What it checks:
#   1) skills/ direct-child dirs == 17
#   2) core/ top-level *.md (maxdepth 1) == 17
#   3) agents/*.md == 17
#   4) docs/reference/*.md == 11
#   5) [REWORKED for the .agent-flow/config.toml migration, per design.md section 5.3]
#      The config surface documents exactly 23 TOML `[section]`s (5 required +
#      18 optional), per FC-06. Retargeted AWAY from the OLD Markdown-table
#      `## Automation Config` H3 sub-section count (that heading's inline tables are
#      REMOVED by the hard-cut migration -- CLAUDE.md becomes a 1-2 line pointer, REQ-02)
#      and ONTO counting TOML `[section]` / `[[pipeline_profiles]]` bracket-token
#      references documented within docs/reference/automation-config.md's
#      "## Required Sections" and "## Optional Sections" reference blocks.
# Expected RED phase status:
#   - assertions 1-4 already pass on current repo (counts already at 17/17/17/11).
#     These act as regression gates against future bloat.
#   - assertion 5 FAILS on current repo: docs/reference/automation-config.md's Required/
#     Optional Sections blocks currently document sections via `### {Section Name}`
#     Markdown headings with prose key lists -- they do not yet annotate each section
#     with its TOML `[section]` table name, so both counts read 0 today (correct red
#     state for a not-yet-migrated config surface).
# Expected GREEN phase (post-impl): PASS for all 5 (5 required [section]s + 18 optional
#   [section]s = 23 total).
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck source=tests/lib/assert.sh
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# 1) Skills count == 17
n=$(find skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
if [ "$n" -ne 17 ]; then
  fail "FC-7.1: skills/ direct-child dir count = ${n} (expected 17)"
fi

# 2) core top-level *.md count == 17
n=$(find core -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
if [ "$n" -ne 17 ]; then
  fail "FC-7.2: core/*.md (maxdepth 1) count = ${n} (expected 17)"
fi

# 3) agents/*.md count == 17
n=$(find agents -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
if [ "$n" -ne 17 ]; then
  fail "FC-7.3: agents/*.md count = ${n} (expected 17)"
fi

# 4) docs/reference/*.md count == 11
n=$(find docs/reference -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
if [ "$n" -ne 11 ]; then
  fail "FC-7.4: docs/reference/*.md count = ${n} (expected 11)"
fi

# 5) FC-06: config surface documents exactly 23 TOML [section]s (5 required + 18
# optional). Count occurrences of the 23 CANONICAL Automation Config TOML table names
# (design.md section 4's migration map) within docs/reference/automation-config.md's
# "## Required Sections" and "## Optional Sections" blocks -- NOT a bare `[a-z_]+`
# bracket regex, which would also match unrelated TOML overlay-example tokens like
# [[process_additions]] / [limits] / [meta] that appear in the Agent Overrides example.
REQUIRED_TABLES='issue_tracker source_control pr_rules pr_description_template build_and_test'
OPTIONAL_TABLES='retry_limits module_docs hooks custom_agents notifications worktrees e2e_test browser_verification error_handling feature_workflow decomposition pipeline_profiles metrics agent_overrides local_deployment sprint_planning autopilot pause_limits'

req_block="$(awk '/^## Required Sections[[:space:]]*$/{f=1;next} /^## /&&f{exit} f' docs/reference/automation-config.md 2>/dev/null || true)"
opt_block="$(awk '/^## Optional Sections[[:space:]]*$/{f=1;next} /^## /&&f{exit} f' docs/reference/automation-config.md 2>/dev/null || true)"

req_sections=0
for name in $REQUIRED_TABLES; do
  matches_re "$req_block" "\[${name}\]" && req_sections=$((req_sections + 1))
done
opt_sections=0
for name in $OPTIONAL_TABLES; do
  matches_re "$opt_block" "\[${name}\]|\[\[${name}\]\]" && opt_sections=$((opt_sections + 1))
done
total_sections=$((req_sections + opt_sections))

if [ "$req_sections" -ne 5 ]; then
  fail "FC-06.a: docs/reference/automation-config.md 'Required Sections' block documents ${req_sections} TOML [section] headers (expected 5)"
fi
if [ "$opt_sections" -ne 18 ]; then
  fail "FC-06.b: docs/reference/automation-config.md 'Optional Sections' block documents ${opt_sections} TOML [section] headers (expected 18)"
fi
if [ "$total_sections" -ne 23 ]; then
  fail "FC-06.c: total TOML [section] headers documented = ${total_sections} (expected 23 = 5 required + 18 optional)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-counts-invariants — 17 skills / 17 core / 17 agents / 11 docs-ref / 23 config.toml [section]s (5 required + 18 optional)"
  exit 0
fi
exit 1
