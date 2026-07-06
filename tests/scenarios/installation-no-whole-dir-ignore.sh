#!/usr/bin/env bash
# Test: installation-no-whole-dir-ignore
# FC mapped: FC-19 [DEDICATED]
# What it checks:
#   docs/guides/installation.md's .gitignore guidance uses PER-FILE entries and does NOT
#   ignore the whole .agent-flow/ directory (the trailing-slash footgun that would
#   silently drop the tracked config.toml). It adds config.local.toml and never lists
#   config.toml as an ignored entry. Asserts the NEGATIVE (whole-dir pattern absence) as
#   rigorously as the positive (config.local.toml present, config.toml absent).
# Expected RED (pre-impl): installation.md's current gitignore block (lines ~86-89) lists
#   only per-file entries from the OLD contract (autopilot.lock/, state.json,
#   pipeline.log, autopilot.log) and does not yet mention config.local.toml -- the
#   positive assertion fails today. The negative (no whole-dir ignore) assertion already
#   PASSES today, since the current guidance never had a whole-dir pattern.
# Expected GREEN (post-impl): installation.md's gitignore block adds config.local.toml,
#   keeps config.toml tracked, and never introduces a bare .agent-flow/ ignore line.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

DOC="docs/guides/installation.md"
[ -f "$DOC" ] || fail "$DOC not found"

# Extract the fenced gitignore code block following "Recommended `.gitignore` entries:"
block=""
if [ -f "$DOC" ]; then
  block="$(awk '/Recommended `\.gitignore` entries/{f=1} f && /^```/{c++; if (c==2) exit} f && c==1 && !/^```/{print}' "$DOC")"
fi

# --- Negative assertion: no bare whole-directory ignore pattern.
# NOTE: bash's [[ =~ ]] anchors ^/$ to the WHOLE string, not per line, so a multi-line
# $block must be checked line-by-line rather than with a single matches_re call. ---
whole_dir_line_found=0
config_toml_ignored_found=0
if [ -n "$block" ]; then
  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$trimmed" ] && continue
    if [ "$trimmed" = ".agent-flow/" ] || [ "$trimmed" = ".agent-flow" ]; then
      whole_dir_line_found=1
    fi
    if [ "$trimmed" = "config.toml" ] || [ "$trimmed" = ".agent-flow/config.toml" ]; then
      config_toml_ignored_found=1
    fi
  done <<< "$block"
fi
[ "$whole_dir_line_found" -eq 0 ] || fail "FC-19: installation.md gitignore block contains a bare whole-directory '.agent-flow/' ignore line (forbidden trailing-slash footgun)"
[ "$config_toml_ignored_found" -eq 0 ] || fail "FC-19: installation.md gitignore block lists config.toml as an ignored entry (it must stay tracked)"

# --- Positive assertion: config.local.toml added as a per-file ignore ---
contains "$block" "config.local.toml" || fail "FC-19: installation.md gitignore block does not add config.local.toml as a per-file ignore"

# --- Behavioural: seed a temp repo with the extracted guidance and verify config.toml stays tracked ---
if [ -n "$block" ]; then
  TMP_REPO="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/installation-gitignore.$$")"
  mkdir -p "$TMP_REPO"
  (
    cd "$TMP_REPO" || exit 1
    git init -q .
    mkdir -p .agent-flow
    : > .agent-flow/config.toml
    printf '%s\n' "$block" > .gitignore
    if git check-ignore .agent-flow/config.toml >/dev/null 2>&1; then
      echo "FAIL: seeding installation.md's gitignore guidance causes config.toml to be ignored" >&2
      exit 1
    else
      echo "OK: config.toml remains tracked under installation.md's gitignore guidance"
    fi
  )
  seed_status=$?
  rm -rf "$TMP_REPO" 2>/dev/null || true
  [ "$seed_status" -eq 0 ] || fail "FC-19: behavioural seeding of installation.md's gitignore block did not keep config.toml tracked"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: installation-no-whole-dir-ignore -- per-file-only gitignore guidance verified (no whole-dir footgun)"
  exit 0
fi
exit 1
