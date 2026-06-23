#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-hidden-agent-contract-injection.sh (HIDDEN)
# What it checks (for a deterministic 3-agent sample, picking files that span
# the role spectrum: fixer (execution), reviewer (read-only), publisher (haiku)):
#   1) The '## Step Completion Invariants' section, after extraction, has
#      between 10 and 50 non-empty lines (size sanity — neither stub nor bloated).
#   2) The section opens with a directive sentence (first non-blank line is
#      a complete sentence: contains 'SHALL' or 'MUST' or 'shall' or 'must'
#      OR ends with a period and is ≥40 chars long). Pure bullet-only sections
#      fail; section must lead with prose.
#   3) The section explicitly references the agent's stage_name binding.
#      For fixer, stage = `fixer_reviewer`. For reviewer, stage = `fixer_reviewer`.
#      For publisher, stage = `publisher`. The section MUST contain the literal
#      stage name as a backticked token within the section body.
# Falsification angle this catches that the visible test does not:
#   - Section present but is a one-liner stub.
#   - Section present but is bullet-only (no directive prose).
#   - Section present but missing the agent-stage binding mentioned
#     per-agent stage-name mapping table.
# Expected RED phase: FAIL — section does not yet exist on any agent.
# Expected GREEN phase: PASS.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# Deterministic sample of 3 agents spanning role types.
# pair format: "<agent-filename>|<expected-stage-name-binding>"
SAMPLES=(
  "fixer.md|fixer_reviewer"
  "reviewer.md|fixer_reviewer"
  "publisher.md|publisher"
)

for pair in "${SAMPLES[@]}"; do
  agent_base="${pair%%|*}"
  expected_stage="${pair##*|}"
  agent_file="agents/${agent_base}"

  if [ ! -f "$agent_file" ]; then
    fail "hidden-injection.file: $agent_file missing"
    continue
  fi

  # Extract section body
  section=$(awk '/^## Step Completion Invariants$/{f=1; next} /^## /&&f{exit} f' "$agent_file")
  if [ -z "$section" ]; then
    fail "hidden-injection.empty: $agent_base has no '## Step Completion Invariants' section body"
    continue
  fi

  # 1) Size sanity: 10-50 NON-EMPTY lines.
  nonempty=$(printf '%s\n' "$section" | grep -cE '\S' || true)
  [ -z "$nonempty" ] && nonempty=0
  if [ "$nonempty" -lt 10 ]; then
    fail "hidden-injection.size-min: $agent_base section has ${nonempty} non-empty lines (need ≥10)"
  fi
  if [ "$nonempty" -gt 50 ]; then
    fail "hidden-injection.size-max: $agent_base section has ${nonempty} non-empty lines (need ≤50)"
  fi

  # 2) Directive opener: first non-blank line is a directive sentence.
  first_line=$(printf '%s\n' "$section" | awk 'NF{print; exit}')
  if [ -z "$first_line" ]; then
    fail "hidden-injection.opener-empty: $agent_base section opener line is empty"
  else
    # Test for SHALL/MUST/shall/must token OR period-ending sentence ≥40 chars.
    if ! matches_re "$first_line" 'SHALL|MUST|shall|must'; then
      # Length check fallback
      line_len=${#first_line}
      ends_with_period=0
      case "$first_line" in
        *.|*.\ |*.\$) ends_with_period=1 ;;
        *) [ "${first_line: -1}" = "." ] && ends_with_period=1 ;;
      esac
      if [ "$line_len" -lt 40 ] || [ "$ends_with_period" -eq 0 ]; then
        fail "hidden-injection.opener-directive: $agent_base section opener is not a directive sentence (no SHALL/MUST + not period-ended ≥40 chars): '${first_line}'"
      fi
    fi
  fi

  # 3) Agent stage-name binding present.
  # Accept backticked form `stage_name` OR plain literal in the section body.
  # grep is line-oriented; '^'/'$' anchor per-line. Replicate by also allowing a newline boundary.
  if ! matches_re "$section" "\`${expected_stage}\`|(^|"$'\n'"| )${expected_stage}( |$|"$'\n'"|,|\.|:)"; then
    fail "hidden-injection.stage-binding: $agent_base section missing stage-name binding '${expected_stage}'"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-hidden-agent-contract-injection — sampled 3 agents (fixer, reviewer, publisher) all pass size + directive + stage-binding checks"
  exit 0
fi
exit 1
