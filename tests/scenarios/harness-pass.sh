#!/bin/bash
# Covers: AC-66 (test harness passes on jq-equipped CI)
#
# Recursive-call protection: this scenario invokes run-tests.sh which itself
# discovers and runs every scenario in tests/scenarios/ — including this one.
# Without a guard the recursive call would never terminate. Detect via
# AGENT_FLOW_HARNESS_RECURSIVE env var: if set, exit 77 (SKIP) immediately.
set -e

if [ "${AGENT_FLOW_HARNESS_RECURSIVE:-0}" = "1" ]; then
  echo "SKIP: harness-pass — recursive invocation detected (parent harness already running)"
  exit 77
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

HARNESS="$REPO_ROOT/tests/harness/run-tests.sh"

if [ ! -f "$HARNESS" ]; then
  echo "FAIL: harness-pass — tests/harness/run-tests.sh not found"
  exit 1
fi

echo "Running full test harness..."
if AGENT_FLOW_HARNESS_RECURSIVE=1 bash "$HARNESS"; then
  echo "PASS: harness-pass — full harness passed with 0 FAIL"
  exit 0
else
  echo "FAIL: harness-pass — harness reported failures (see above)"
  exit 1
fi
