#!/usr/bin/env bash
# tests/lib/assert.sh — SIGPIPE-safe assertion helpers.
#
# Usage: . "$REPO_ROOT/tests/lib/assert.sh"
#
# Why this exists:
#   The pattern `producer | grep -q PATTERN` interacts badly with `set -o
#   pipefail` on Linux. `grep -q` exits as soon as it finds the first match
#   and closes its stdin; the producer (echo, sed, awk) then writes to the
#   closed pipe, receives SIGPIPE, and exits with 141. `pipefail` propagates
#   that 141, and `|| fail` triggers despite the match having been found.
#   The race is timing-dependent (Linux schedules grep early-exit before the
#   producer flushes), so it appears flaky on CI but rarely on Windows MSYS2.
#
# These helpers use bash builtins (case, [[ ... =~ ]]) so there is no pipe
# at all -- nothing to break.
#
# Idempotency sentinel
[ "${ASSERT_SH_LOADED:-}" = "1" ] && return 0
ASSERT_SH_LOADED=1

# contains HAYSTACK NEEDLE -- substring match, case-sensitive.
# Returns 0 if HAYSTACK contains NEEDLE, 1 otherwise.
contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# contains_i HAYSTACK NEEDLE -- substring match, case-insensitive.
# Requires bash 4+ for ${var,,} expansion (CI Linux + Windows MSYS2 both ship 4+).
contains_i() {
  local hay="${1,,}"
  local needle="${2,,}"
  case "$hay" in
    *"$needle"*) return 0 ;;
    *) return 1 ;;
  esac
}

# matches_re HAYSTACK ERE_PATTERN -- bash extended-regex match.
matches_re() {
  [[ "$1" =~ $2 ]]
}
