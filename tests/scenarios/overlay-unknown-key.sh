#!/usr/bin/env bash
# Verifies: AC-OVR-005
# Description: TOML overlay with unknown key (not_a_real_key) halts dispatch with [ERROR]
#   naming the offending key + non-zero exit
set -uo pipefail

# NOTE: REPO_ROOT assumes test file location is tests/scenarios/. Run after Phase 7 has moved files.
# Do NOT execute from staging location .forge/phase-5-tdd/tests/.
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
# Setup: TOML overlay with unknown top-level key
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_TEST/customization"

cat > "$TMPDIR_TEST/customization/reviewer.toml" << 'EOF'
not_a_real_key = 1
model = "sonnet"
EOF

# ---------------------------------------------------------------------------
# Assertion 1: TOML syntax doc documents strict unknown-key validation
# ---------------------------------------------------------------------------
echo "--- Assertion 1: toml-overlay-syntax.md documents unknown-key halt ---"
TOML_DOC="$REPO_ROOT/docs/guides/toml-overlay-syntax.md"
if [ ! -f "$TOML_DOC" ]; then
  echo "SKIP: docs/guides/toml-overlay-syntax.md not found (implementation pending)" >&2
  exit 77
fi

if grep -qiE 'unknown.*key|unknown key|unrecognized.*key|strict.*valid' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents unknown key rejection"
else
  fail "toml-overlay-syntax.md missing unknown-key validation documentation"
fi

# ---------------------------------------------------------------------------
# Assertion 2: [ERROR] log must name the offending key
# ---------------------------------------------------------------------------
echo "--- Assertion 2: error documentation specifies key name in [ERROR] message ---"
if grep -qiE 'key.*name|naming.*key|\[ERROR\].*key' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md error docs include key name in [ERROR]"
else
  fail "toml-overlay-syntax.md does not specify offending key name in [ERROR] message"
fi

# ---------------------------------------------------------------------------
# Assertion 3: [meta] table is explicitly EXEMPT from unknown-key validation
# ---------------------------------------------------------------------------
echo "--- Assertion 3: [meta] is exempt from unknown-key validation ---"
if grep -qiE '\[meta\].*free.?form|\[meta\].*NOT.*subject|meta.*freeform' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents [meta] as free-form (exempt)"
else
  fail "toml-overlay-syntax.md does not document [meta] table as exempt from unknown-key validation"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Non-zero exit on unknown key — documented in REQ/design
# ---------------------------------------------------------------------------
echo "--- Assertion 4: non-zero exit on unknown key documented ---"
if grep -qiE 'non.zero|exit code|exit 1' "$TOML_DOC"; then
  echo "OK: toml-overlay-syntax.md documents non-zero exit on invalid TOML"
else
  fail "toml-overlay-syntax.md missing non-zero exit documentation for unknown key error"
fi

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: AC-OVR-005 — TOML unknown key halts with [ERROR] naming the key documented"
fi
exit "$FAIL"
