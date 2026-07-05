#!/usr/bin/env bash
# Test: toml-parser-malformed-crlf-variant  [HIDDEN]
# FC mapped: FC-05 [DEDICATED] -- hidden variant
# What it checks:
#   A DIFFERENT malformed-optional-section shape than the visible
#   tests/toml-parser-malformed-warn.sh scenario (which uses an unterminated """ block
#   under [metrics]): here the malformed construct is a garbage (unquoted, multi-word,
#   non-boolean/non-integer) scalar under [error_handling] (an entirely different
#   optional section), combined with \r-terminated lines throughout AND a comment line
#   whose trailing # appears after a quoted string (i.e. a comment-stripping edge case:
#   `on_block = "comment" # inline note`) to make sure comment-stripping doesn't corrupt
#   the string value. Still must degrade to [WARN] + default + exit 0, never crash.
# Expected RED (pre-impl): core/config-reader.md's Failure Handling section does not yet
#   describe TOML-specific malformed-optional handling at all.
# Expected GREEN (post-impl): the fixture below parses without crashing, applies
#   error_handling's defaults, and warns naming "error_handling".
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
[ -f "$READER" ] || fail "$READER not found"
contains "$reader_content" "[WARN]" || fail "FC-05 (hidden/CRLF variant): core/config-reader.md Failure Handling does not use the [WARN] token"
contains_i "$reader_content" "toml" || fail "FC-05 (hidden/CRLF variant): core/config-reader.md Failure Handling section does not mention TOML-specific malformation"

# --- Distinct hidden fixture: garbage scalar under [error_handling] (NOT [metrics]),
# every line \r-terminated, plus a quoted-string-then-inline-comment edge case ---
FIXTURE_DIR="$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/toml-malformed-crlf.$$")"
mkdir -p "$FIXTURE_DIR" 2>/dev/null || true
FIXTURE="$FIXTURE_DIR/config.toml"
fixture_bytes=""
{
  printf '[issue_tracker]\r\n'
  printf 'type = "github"\r\n'
  printf 'instance = "https://github.com"\r\n'
  printf 'project = "acme/repo"\r\n'
  printf 'bug_query = "is:issue is:open label:bug"\r\n'
  printf 'state_transitions = "In Progress: In Progress"\r\n'
  printf 'on_start_set = "In Progress"\r\n'
  printf '\r\n'
  printf '[error_handling]\r\n'
  printf 'on_block = "comment" # inline note after a quoted string\r\n'
  printf 'max_blocked_per_run = unlimited but with trailing words\r\n'
} > "$FIXTURE"

[ -f "$FIXTURE" ] || fail "could not construct the hidden CRLF + garbage-scalar fixture"
if [ -f "$FIXTURE" ]; then
  fixture_bytes="$(cat "$FIXTURE")"
  contains "$fixture_bytes" $'\r' || fail "hidden fixture does not contain \\r-terminated lines"
  contains "$fixture_bytes" '[error_handling]' || fail "hidden fixture missing the [error_handling] malformed section"
  contains "$fixture_bytes" 'unlimited but with trailing words' || fail "hidden fixture missing the garbage multi-word scalar"
fi
rm -rf "$FIXTURE_DIR" 2>/dev/null || true

# Distinctness guard vs. the visible scenario (which targets [metrics] with an unterminated
# triple-quote): this hidden variant targets [error_handling] with a garbage bare scalar.
# Checks the fixture's actual CONTENT (not its temp-dir path, which could never contain
# "metrics" and would make this guard permanently unable to fire).
if contains "$fixture_bytes" "metrics"; then
  fail "hidden-fixture sanity: accidentally reused the visible scenario's [metrics] target section"
fi

# TODO(phase-7): once a real pure-bash config reader exists, run it against $FIXTURE and
# assert exit code 0, a [WARN] line naming "error_handling", the error_handling defaults
# applied (on_block=comment, max_blocked_per_run=unlimited), AND that on_block's resolved
# value is the clean string "comment" (the inline # comment after the closing quote must
# be stripped without corrupting the quoted value).

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-parser-malformed-crlf-variant -- distinct malformed-section + CRLF + inline-comment-after-string fixture constructed"
  exit 0
fi
exit 1
