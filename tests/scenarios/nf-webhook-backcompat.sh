#!/usr/bin/env bash
# Verifies: AC-NF-008
# Description: Webhook payload schema in core/post-publish-hook.md contains
#   NO renamed fields; new optional fields are additive only.
#   Asserts all canonical payload field names still present in documentation.
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
# Prerequisite: core/post-publish-hook.md must exist
# ---------------------------------------------------------------------------
HOOK_DOC="$REPO_ROOT/core/post-publish-hook.md"
if [ ! -f "$HOOK_DOC" ]; then
  echo "SKIP: core/post-publish-hook.md not found (implementation pending)" >&2
  exit 77
fi

# ---------------------------------------------------------------------------
# Canonical webhook payload field names
# These are the fields present per CLAUDE.md Webhook Payloads section.
# None of these may be renamed. New fields may be additive.
# Webhook events: pr-created, pipeline-started, step-completed,
#                 pipeline-completed, issue-blocked, pipeline-paused
# ---------------------------------------------------------------------------
V7_FIELDS=(
  "pr_url"
  "issue_id"
  "agent"
  "status"
  "run_id"
  "pipeline"
  "step"
  "outcome"
)

# ---------------------------------------------------------------------------
# Assertion 1: All v7 payload field names still present in core/post-publish-hook.md
# ---------------------------------------------------------------------------
echo "--- Assertion 1: All v7 webhook payload fields still present in v8 ---"
MISSING_FIELDS=0
for field in "${V7_FIELDS[@]}"; do
  if grep -qE "\"${field}\"|'${field}'|${field}:" "$HOOK_DOC"; then
    echo "OK: v7 field '${field}' still present in post-publish-hook.md"
  else
    echo "WARN: v7 field '${field}' not found in post-publish-hook.md — checking if renamed"
    MISSING_FIELDS=$((MISSING_FIELDS + 1))
    fail "v7 webhook field '${field}' absent or renamed in v8 (breaking change: AC-NF-008)"
  fi
done

# ---------------------------------------------------------------------------
# Assertion 2: post-publish-hook.md documents additive-only policy
# ---------------------------------------------------------------------------
echo "--- Assertion 2: post-publish-hook.md documents additive-only payload evolution ---"
if grep -qiE 'additive|forward.compat|backward.compat|new.*field.*only|never.*rename|no.*rename|no.*remove' "$HOOK_DOC"; then
  echo "OK: post-publish-hook.md documents additive-only webhook payload evolution"
else
  fail "post-publish-hook.md missing additive-only payload evolution documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 3: CLAUDE.md webhook forward-compatibility notice still present
# ---------------------------------------------------------------------------
echo "--- Assertion 3: CLAUDE.md documents webhook payload forward-compatibility ---"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  if grep -qiE 'additive.*field|forward.compat|webhook.*payload|lenient.*json' "$CLAUDE_MD"; then
    echo "OK: CLAUDE.md documents webhook payload forward-compatibility"
  else
    fail "CLAUDE.md missing webhook payload forward-compatibility documentation"
  fi
fi

# ---------------------------------------------------------------------------
# Assertion 4: No v7 field appears to have been renamed (no renamed field alert)
#   This checks for common rename patterns: _v8 suffix, v8_ prefix, renaming
# ---------------------------------------------------------------------------
echo "--- Assertion 4: no evidence of renamed v7 fields in v8 webhook schema ---"
for field in "${V7_FIELDS[@]}"; do
  # Check for suspicious v8-suffixed variants that would indicate rename
  if grep -qE "\"${field}_v8\"|\"v8_${field}\"" "$HOOK_DOC"; then
    fail "Potential rename detected: '${field}' has '_v8' variant — if original '${field}' is absent, this is a breaking rename"
  fi
done
echo "OK: no v7-field rename patterns detected"

# ---------------------------------------------------------------------------
# Assertion 5: pr-created and agent-flow-block event names preserved
#   Per CLAUDE.md: "Existing payload fields (pr-created, agent-flow-block)
#   are never renamed or removed."
# ---------------------------------------------------------------------------
echo "--- Assertion 5: pr-created and agent-flow-block event names preserved ---"
if grep -qF 'pr-created' "$HOOK_DOC" || grep -qF 'pr_created' "$HOOK_DOC"; then
  echo "OK: pr-created event name documented"
else
  fail "pr-created event name absent from post-publish-hook.md (breaking rename)"
fi

if grep -qF 'agent-flow-block' "$HOOK_DOC" || grep -qF 'issue-blocked' "$HOOK_DOC"; then
  echo "OK: agent-flow-block / issue-blocked event name documented"
else
  fail "agent-flow-block event name absent from post-publish-hook.md (breaking rename)"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-NF-008 — webhook payload schema: all v7 fields preserved in v8 (additive-only)"
fi
exit "$FAIL"
