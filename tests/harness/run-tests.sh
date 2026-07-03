#!/bin/bash
# Run all test scenarios for agent-flow
# Usage: ./tests/harness/run-tests.sh [scenario-name]
#        HARNESS_JOBS=8 ./tests/harness/run-tests.sh  (override parallelism)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/../scenarios"

# Prevent recursive invocation — harness-pass.sh detects this and exits 77 (SKIP)
export AGENT_FLOW_HARNESS_RECURSIVE=1

# Parallelism: default 4, override via HARNESS_JOBS env var or nproc
JOBS="${HARNESS_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "=== agent-flow Test Harness ==="
echo ""

# Single scenario mode — run one test with visible output
if [ -n "${1:-}" ]; then
  scenario="$SCENARIOS_DIR/$1.sh"
  if [ ! -f "$scenario" ]; then
    echo "ERROR: Scenario '$1' not found at $scenario"
    exit 1
  fi
  bash "$scenario"
  exit $?
fi

# Temp directory for per-test results and logs
RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "$RESULTS_DIR"' EXIT

# Worker script — runs one scenario, writes result and log to RESULTS_DIR
WORKER="$RESULTS_DIR/_worker.sh"
cat > "$WORKER" << 'WORKER_EOF'
#!/bin/bash
scenario="$1"
results_dir="$2"
name=$(basename "$scenario" .sh)
if bash "$scenario" > "$results_dir/$name.log" 2>&1; then
  echo "PASS" > "$results_dir/$name.result"
else
  exit_code=$?
  if [ "$exit_code" -eq 77 ]; then
    echo "SKIP" > "$results_dir/$name.result"
  else
    echo "FAIL" > "$results_dir/$name.result"
  fi
fi
echo "  $(cat "$results_dir/$name.result"): $name"
WORKER_EOF
chmod +x "$WORKER"

# Run all scenarios in parallel (JOBS workers)
find "$SCENARIOS_DIR" -maxdepth 1 -name "*.sh" | sort | \
  xargs -P "$JOBS" -I {} bash "$WORKER" {} "$RESULTS_DIR"

# Collect results in sorted order
PASS=0; FAIL=0; SKIP=0
FAIL_NAMES=()

for scenario in $(find "$SCENARIOS_DIR" -maxdepth 1 -name "*.sh" | sort); do
  name=$(basename "$scenario" .sh)
  result=$(cat "$RESULTS_DIR/$name.result" 2>/dev/null || echo "UNKNOWN")
  case "$result" in
    PASS) PASS=$((PASS + 1)) ;;
    SKIP) SKIP=$((SKIP + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)); FAIL_NAMES+=("$name") ;;
  esac
done

# Print failure details (output of failed tests)
if [ "${#FAIL_NAMES[@]}" -gt 0 ]; then
  echo ""
  echo "=== Failure Details ==="
  for name in "${FAIL_NAMES[@]}"; do
    echo ""
    echo "--- FAIL: $name ---"
    grep -v "^$" "$RESULTS_DIR/$name.log" 2>/dev/null | tail -20
  done
fi

# Summary
echo ""
echo "=== Test Results ==="
for scenario in $(find "$SCENARIOS_DIR" -maxdepth 1 -name "*.sh" | sort); do
  name=$(basename "$scenario" .sh)
  result=$(cat "$RESULTS_DIR/$name.result" 2>/dev/null || echo "UNKNOWN")
  echo "  $result: $name"
done

echo ""
echo "Total: $((PASS + FAIL + SKIP)) | Pass: $PASS | Fail: $FAIL | Skip: $SKIP"

[ "$FAIL" -eq 0 ]
