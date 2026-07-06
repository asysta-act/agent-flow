#!/usr/bin/env bash
# Test: config-required-keys
# FC mapped: FC-07
# What it checks (REWORKED for the .agent-flow/config.toml migration, per design.md
# section 5.3): every required config.toml dot-notation key (design.md section 4.1
# migration map's "Resolved keys" column) sourced from config.toml is consumed by at
# least one skill. Retargeted AWAY from searching skills for the OLD Title-Case
# Markdown-table key names (e.g. "Bug query", "Base branch") and ONTO the resolved
# dot-notation key names core/config-reader.md exposes from config.toml
# (e.g. issue_tracker.bug_query, source_control.base_branch) -- the actual identifiers
# downstream skills read once the migration lands (REQ-04: dot-notation is unchanged by
# the relocation, only the keys' TEXTUAL FORM in skills changes from Title-Case English
# phrases to dot-notation).
# Expected RED (pre-impl): skills/*/SKILL.md files currently reference the OLD Title-Case
# key names (since they still read from CLAUDE.md's Markdown tables) -- none of them
# reference the NEW dot-notation forms yet, so every key fails.
# Expected GREEN (post-impl): each dot-notation key is referenced in at least one skill.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

SKILLS_DIR="$REPO_ROOT/skills"
[ -d "$SKILLS_DIR" ] || { echo "FAIL: skills/ directory not found"; exit 1; }

# Required dot-notation keys from design.md section 4.1 (5 required sections):
# issue_tracker: type, instance, project, bug_query, state_transitions, on_start_set
# source_control: remote, base_branch, branch_naming
# pr_rules: labels
# build (Build & Test): build_command, test_command
# (pr_rules.description_template is the PR Description Template subsection body, not a
# discrete key search target -- excluded, consistent with the original test's exclusion)
REQUIRED_KEYS=(
  "issue_tracker.type"
  "issue_tracker.instance"
  "issue_tracker.project"
  "issue_tracker.bug_query"
  "issue_tracker.state_transitions"
  "issue_tracker.on_start_set"
  "source_control.remote"
  "source_control.base_branch"
  "source_control.branch_naming"
  "pr_rules.labels"
  "build.build_command"
  "build.test_command"
)

for key in "${REQUIRED_KEYS[@]}"; do
  matched_skills=()
  for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    if contains "$(cat "$skill_file")" "$key"; then
      matched_skills+=("$(basename "$(dirname "$skill_file")")")
    fi
  done
  if [ ${#matched_skills[@]} -gt 0 ]; then
    echo "OK: required key '$key' referenced in: ${matched_skills[*]}"
  else
    fail "required key '$key' not found in any skill"
  fi
done

[ "$FAIL" -eq 0 ] && echo "PASS: all required config.toml dot-notation keys are consumed by at least one command"
exit "$FAIL"
