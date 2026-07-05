#!/usr/bin/env bash
# Test: version-neutral-source-pr
# FC mapped: FC-25
# What it checks:
#   The migration's source change does not edit release-bump files: the changeset must
#   touch none of .claude-plugin/plugin.json, .claude-plugin/marketplace.json,
#   CHANGELOG.md (the single version bump is finalized on the integration branch, per
#   REQ-27 and CLAUDE.md's Release Process).
# Expected RED / SKIP (pre-impl): there is no migration implementation diff yet to check
#   against a base ref -- this scenario degrades to [SKIP] (not a hard FAIL) when it
#   cannot resolve a base..HEAD diff, OR when a diff exists but does not look like the
#   migration PR (no config.toml/config-reader-shaped changes in it). The current working
#   branch is unrelated audit-remediation work that also happens to touch CHANGELOG.md /
#   plugin.json -- asserting FC-25 against THAT diff would fail for the wrong reason (an
#   unrelated branch's changes), not the right one (the actual migration PR touching a
#   release-bump file). Once the real migration PR is open, its diff will touch
#   core/config-reader.md and this becomes a genuine regression gate.
# Expected GREEN (post-impl): a real base..HEAD diff exists and touches none of the three
#   release-bump files.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# Resolve a base ref: prefer origin/release/v2.0.0 (the migration's stated integration
# branch per requirements.md REQ-27 / analysis.md), fall back to the merge-base with HEAD,
# then to origin/main.
base_ref=""
for candidate in origin/release/v2.0.0 release/v2.0.0 origin/main main; do
  if git rev-parse --verify -q "$candidate" >/dev/null 2>&1; then
    base_ref="$candidate"
    break
  fi
done

if [ -z "$base_ref" ]; then
  echo "SKIP: version-neutral-source-pr -- no resolvable base ref (release/v2.0.0 or main); cannot compute a diff pre-implementation"
  exit 0
fi

merge_base="$(git merge-base "$base_ref" HEAD 2>/dev/null || true)"
if [ -z "$merge_base" ]; then
  echo "SKIP: version-neutral-source-pr -- could not compute merge-base against $base_ref"
  exit 0
fi

changed_files="$(git diff --name-only "$merge_base"..HEAD 2>/dev/null || true)"
if [ -z "$changed_files" ]; then
  echo "SKIP: version-neutral-source-pr -- no diff vs $base_ref yet (pre-implementation)"
  exit 0
fi

# Heuristic gate: only enforce FC-25 when the diff actually looks like the migration PR
# (touches the config-reader / config.toml surface). Otherwise the diff belongs to
# unrelated work and asserting against it would fail for the wrong reason.
if ! matches_re "$changed_files" 'config-reader\.md|\.agent-flow/config(\.local)?\.toml|config\.toml'; then
  echo "SKIP: version-neutral-source-pr -- diff vs $base_ref does not touch the config-reader/config.toml surface; not the migration PR yet"
  exit 0
fi

if matches_re "$changed_files" 'plugin\.json|marketplace\.json|CHANGELOG\.md'; then
  fail "FC-25: changeset vs $base_ref touches a release-bump file (plugin.json / marketplace.json / CHANGELOG.md) -- source PR must be version-neutral per REQ-27"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: version-neutral-source-pr -- no release-bump files touched in the diff vs $base_ref"
  exit 0
fi
exit 1
