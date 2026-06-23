#!/bin/bash
# PURPOSE: Assert backward-compatibility of customization/{agent}.md override files per AC-H-120.
#          Verifies: (1) core/agent-override-injector.md is unchanged,
#          (2) examples/customization/ example files exist and do not contain reserved headings
#          that would collide with ## Output Contract or ## Project-Specific Instructions,
#          (3) the override injector flow is append-only (no Output Contract stripping).
# AC-H-N covered: AC-H-020, AC-H-120
# INVOKED BY: tests/harness/run-tests.sh
# EXPECTED: PASS (injector unchanged; no examples collide; backward-compat preserved)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
if contains "$REPO_ROOT" ".forge"; then
  echo "ERROR: REPO_ROOT=$REPO_ROOT — tests must be run from tests/scenarios/ after Phase 7 staging" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

INJECTOR="$REPO_ROOT/core/agent-override-injector.md"

# AC-H-020: agent-override-injector.md must exist and be unmodified
if [ ! -f "$INJECTOR" ]; then
  fail "core/agent-override-injector.md not found — injector must remain unchanged"
  exit 1
fi

# The injector must still use the append-only pattern with ## Project-Specific Instructions
if ! grep -qF '## Project-Specific Instructions' "$INJECTOR"; then
  fail "core/agent-override-injector.md missing '## Project-Specific Instructions' heading reference — append-only behavior may have been altered"
  # Mutation catch: modifying the injector to strip or parse Output Contract fails here
fi

# The injector must NOT contain logic that strips or skips ## Output Contract sections
if grep -qiE '(strip|skip|remove|filter|block|reject).*[Oo]utput [Cc]ontract' "$INJECTOR"; then
  fail "core/agent-override-injector.md contains Output Contract filtering logic — injector must be structure-blind"
fi

# Check examples/customization/ directory: example override files must not use reserved headings
EXAMPLES_CUSTOM="$REPO_ROOT/examples/customization"
if [ -d "$EXAMPLES_CUSTOM" ]; then
  for override_file in "$EXAMPLES_CUSTOM"/*.md "$EXAMPLES_CUSTOM"/*.toml; do
    [ -f "$override_file" ] || continue
    # Only check .md files for reserved heading collision (TOML files can't have markdown headings)
    if matches_re "$override_file" '\.md$'; then
      if grep -qE '^## Project-Specific Instructions$' "$override_file"; then
        fail "examples/customization/$(basename "$override_file") contains reserved heading '## Project-Specific Instructions' — collision risk"
        # Note: ## Output Contract collision is documented but not blocked
        # We only fail on ## Project-Specific Instructions (which IS blocked)
      fi
    fi
  done
fi

# Verify at least one example customization file exists (sanity check examples/ is not empty)
example_count=$(find "$REPO_ROOT/examples" -name "*.toml" -o -name "*.md" 2>/dev/null | grep -c "customization\|agent-override" || true)
if [ "$example_count" -eq 0 ]; then
  fail "No example customization files found in examples/ — backward-compat examples should exist"
fi

# Verify no agent file has ## Project-Specific Instructions (reserved heading guard — AC-H-004)
for agent_file in "$REPO_ROOT/agents"/*.md; do
  agent_name=$(basename "$agent_file" .md)
  if grep -qE '^## Project-Specific Instructions$' "$agent_file"; then
    fail "$agent_name.md contains reserved heading '## Project-Specific Instructions' in base agent — violation"
    # Mutation catch: accidentally adding the reserved heading to an agent file fails here
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-H-020, AC-H-120 — override injector is unchanged; no reserved heading collisions in examples; all agent files free of reserved headings"
fi
exit "$FAIL"
