#!/usr/bin/env bash
set -euo pipefail

# Webhook payload forward-compatibility guarantee is documented in CLAUDE.md
# Description: Verifies CLAUDE.md documents the forward-compatible webhook payload
#              guarantee (additive fields, no schema version bump).
#
# NOTE: The advisory-failure mechanics for core/post-publish-hook.md (the
# '[WARN] Webhook delivery failed' message and the advisory/non-blocking semantics
# regex) are already asserted by webhook-advisory-failure.sh (AC-11, Traces:
# WEBHOOK-R5). Per CONTRIBUTING.md rule 9 ("no duplicate coverage for an existing
# AC id"), this file does NOT re-assert those checks — it covers only the
# CLAUDE.md forward-compatibility paragraph, which webhook-advisory-failure.sh
# does not check (that file inspects core/post-publish-hook.md only).

cd "$(dirname "$0")/../.."

FILE="CLAUDE.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: $FILE does not exist" >&2
  exit 1
fi

FAIL=0

# Forward-compat guarantee paragraph in CLAUDE.md
if ! grep -qF 'Webhook payloads are forward-compatible' "$FILE"; then
  echo "FAIL: $FILE missing 'Webhook payloads are forward-compatible' paragraph" >&2
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "PASS: CLAUDE.md documents webhook payload forward-compatibility guarantee (advisory-failure mechanics covered separately by webhook-advisory-failure.sh)"
exit "$FAIL"
