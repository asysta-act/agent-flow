#!/usr/bin/env bash
# Test: config-reader-sections
# FC mapped: FC-01, FC-06, FC-07
# What it checks (REWORKED for the .agent-flow/config.toml migration, per design.md
# section 5.3): the 18 optional TOML `[section]` table names for the config.toml surface
# match between docs/reference/automation-config.md (the canonical config.toml section
# reference, post-migration) and core/config-reader.md (the pure-bash reader that must
# recognize each section). Retargeted AWAY from the OLD CLAUDE.md-inline-table <->
# config-reader prose-name cross-check (CLAUDE.md no longer carries any Automation
# Config tables post-migration -- REQ-02 -- so it is no longer a meaningful source of
# truth for this check) and ONTO the config.toml `[section]` bracket-token surface.
# Expected RED (pre-impl): docs/reference/automation-config.md documents these sections
# via `### {Section Name}` prose headings, not `[section]` TOML bracket tokens, and
# core/config-reader.md still describes Markdown-table parsing -- neither file contains
# the bracket-token forms yet, so every section fails both halves of the cross-check.
# Expected GREEN (post-impl): both files reference each `[section]` bracket token.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck source=tests/lib/assert.sh
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

DOC_REF="$REPO_ROOT/docs/reference/automation-config.md"
CONFIG_READER="$REPO_ROOT/core/config-reader.md"

[ -f "$DOC_REF" ]        || { echo "FAIL: docs/reference/automation-config.md not found"; exit 1; }
[ -f "$CONFIG_READER" ]  || { echo "FAIL: core/config-reader.md not found"; exit 1; }

doc_ref_content="$(cat "$DOC_REF")"
config_reader_content="$(cat "$CONFIG_READER")"

# 18 optional TOML table names (design.md section 4.2 migration map)
OPTIONAL_TABLES=(
  retry_limits
  module_docs
  hooks
  custom_agents
  notifications
  worktrees
  e2e_test
  browser_verification
  error_handling
  feature_workflow
  decomposition
  pipeline_profiles
  metrics
  agent_overrides
  local_deployment
  sprint_planning
  autopilot
  pause_limits
)

missing_in_docref=()
missing_in_reader=()

for table in "${OPTIONAL_TABLES[@]}"; do
  bracket="[${table}]"
  double_bracket="[[${table}]]"

  if contains "$doc_ref_content" "$bracket" || contains "$doc_ref_content" "$double_bracket"; then
    echo "OK: '$bracket' present in docs/reference/automation-config.md"
  else
    fail "'$bracket' not found in docs/reference/automation-config.md"
    missing_in_docref+=("$table")
  fi

  if contains "$config_reader_content" "$bracket" || contains "$config_reader_content" "$double_bracket"; then
    echo "OK: '$bracket' present in core/config-reader.md"
  else
    fail "'$bracket' is documented as an optional section but NOT recognized in core/config-reader.md"
    missing_in_reader+=("$table")
  fi
done

if [ ${#missing_in_docref[@]} -gt 0 ]; then
  echo ""
  echo "[section]s missing from docs/reference/automation-config.md:"
  for s in "${missing_in_docref[@]}"; do
    echo "  - [$s]"
  done
fi
if [ ${#missing_in_reader[@]} -gt 0 ]; then
  echo ""
  echo "[section]s missing from core/config-reader.md:"
  for s in "${missing_in_reader[@]}"; do
    echo "  - [$s]"
  done
fi

[ "$FAIL" -eq 0 ] && echo "PASS: all 18 optional config.toml [section]s are documented in both docs/reference/automation-config.md and core/config-reader.md"
exit "$FAIL"
