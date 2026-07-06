#!/usr/bin/env bash
set -euo pipefail

# AC-11: Webhook failure is advisory (WARN + continue, pipeline not blocked)
# Traces: WEBHOOK-R5
# Description: Verifies core/post-publish-hook.md documents advisory failure semantics
#
# NOTE: This is the canonical scenario for the AC-11 advisory-failure mechanics
# ('[WARN] Webhook delivery failed' message, advisory/non-blocking semantics, and
# the curl max-time timeout pattern) against core/post-publish-hook.md. The
# separate CLAUDE.md forward-compatibility paragraph for webhook payloads is
# covered by ac-webhook-advisory-failure.sh, which does NOT re-assert the checks
# below. Per CONTRIBUTING.md rule 9 ("no duplicate coverage for an existing AC
# id"), do not reintroduce the CLAUDE.md check here — extend this file instead
# of adding a near-duplicate.

# Depends on Phase 7 implementation

cd "$(dirname "$0")/../.."

FILE="core/post-publish-hook.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: $FILE does not exist — create it in Phase 7" >&2
  exit 1
fi

FAIL=0

# Advisory failure message documented
if ! grep -qF '[WARN] Webhook delivery failed' "$FILE"; then
  echo "FAIL: $FILE missing '[WARN] Webhook delivery failed' advisory message" >&2
  FAIL=1
fi

# Pipeline must not block on webhook failure
if ! grep -qiE 'advisory|not block|pipeline.*continue|continue.*pipeline' "$FILE"; then
  echo "FAIL: $FILE does not document advisory (non-blocking) failure semantics" >&2
  FAIL=1
fi

# curl max-time pattern preserved
if ! grep -qiE 'max-time 5|max.time.*5' "$FILE"; then
  echo "FAIL: $FILE missing 'max-time 5' curl timeout pattern" >&2
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "PASS: webhook-advisory-failure — advisory failure + WARN + non-blocking documented"
exit "$FAIL"
