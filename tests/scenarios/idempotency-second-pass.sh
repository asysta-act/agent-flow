#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-idempotency-second-pass.sh  [HIDDEN -- 20%]
# FC mapped:   FC-B-7
# Phase:       5 (TDD -- FAIL expected until Phase 7 lands, then must PASS)
# What it checks:
#   Runs the canonical depth-aware sed patterns from design.md a SECOND time
#   against the post-Phase-7 tree and asserts ZERO diff vs the first pass.
#   A single-pass test misses non-idempotent regexes that double-prefix on
#   re-application (e.g., `../../core/X.md` -> `../../../../core/X.md`).
#
# Design note on pattern:
#   The canonical sed uses `([^./])core/` to avoid matching already-
#   prefixed paths. This test validates that invariant holds for ALL 4 depth classes.
# Cross-platform: Win Git-Bash + Linux GNU + macOS BSD
# Exit codes: 0=PASS, 1=FAIL, 77=SKIP
# ===========================================================================
set -euo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

PASS_COUNT=0
FAIL_COUNT=0
TMPDIR_IDEM=""

cleanup() {
  if [ -n "$TMPDIR_IDEM" ] && [ -d "$TMPDIR_IDEM" ]; then
    rm -rf "$TMPDIR_IDEM"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Require mktemp
# ---------------------------------------------------------------------------
if ! TMPDIR_IDEM=$(mktemp -d 2>/dev/null); then
  if ! TMPDIR_IDEM=$(mktemp -d -t v10idem.XXXXXX 2>/dev/null); then
    echo "[SKIP] mktemp -d unavailable on this platform"
    exit 77
  fi
fi

# ---------------------------------------------------------------------------
# Helper: run ONE depth-class sed transformation (in-memory, no file mutation)
# Applies the canonical pattern / design.md §B.1 to each file
# in the glob, returns lines that changed (empty = idempotent).
# ---------------------------------------------------------------------------

# The 4 canonical sed patterns (2-backslash ERE, as specified):
#   Depth 1: agents/*.md           `([^./])core/X.md` -> `\1../core/X.md`
#   Depth 2: skills/*/SKILL.md     `([^./])core/X.md` -> `\1../../core/X.md`
#   Depth 3: skills/*/steps/*.md   `([^./])core/X.md` -> `\1../../../core/X.md`
#   Depth 3: skills/*/data/*.md    `([^./])core/X.md` -> `\1../../../core/X.md`

check_idempotent() {
  local label="$1"
  local prefix="$2"   # e.g. ../../
  shift 2
  local files=("$@")
  local non_idem=0

  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    # Apply the sed pattern to the file contents (in memory)
    before=$(cat "$f")
    after=$(printf '%s\n' "$before" | \
      sed -E "s|([^./])core/([a-z][a-z-]*\\.md)|\1${prefix}core/\2|g")
    if [ "$before" != "$after" ]; then
      echo "[INFO] NOT IDEMPOTENT: $f (second sed pass changed content)"
      non_idem=$((non_idem + 1))
    fi
  done

  if [ "$non_idem" -eq 0 ]; then
    echo "[PASS] $label: idempotent (second sed pass -> zero changes)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] $label: $non_idem file(s) changed on second pass -- regex is NOT idempotent"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Depth 1: agents/*.md  (prefix: ../)
# ---------------------------------------------------------------------------
agent_files=()
for f in "$REPO_ROOT/agents/"*.md; do
  [ -f "$f" ] && agent_files+=("$f")
done

if [ "${#agent_files[@]}" -gt 0 ]; then
  check_idempotent "Depth-1 agents/*.md" "../" "${agent_files[@]}"
else
  echo "[INFO] No agents/*.md found -- pre-Phase-7 tree, skipping depth-1 idempotency check"
fi

# ---------------------------------------------------------------------------
# Depth 2: skills/*/SKILL.md  (prefix: ../../)
# ---------------------------------------------------------------------------
skill_files=()
for f in "$REPO_ROOT/skills/"*/SKILL.md; do
  [ -f "$f" ] && skill_files+=("$f")
done

if [ "${#skill_files[@]}" -gt 0 ]; then
  check_idempotent "Depth-2 skills/*/SKILL.md" "../../" "${skill_files[@]}"
else
  echo "[INFO] No skills/*/SKILL.md found -- skipping"
fi

# ---------------------------------------------------------------------------
# Depth 3: skills/*/steps/*.md  (prefix: ../../../)
# ---------------------------------------------------------------------------
steps_files=()
for f in "$REPO_ROOT/skills/"*/steps/*.md; do
  [ -f "$f" ] && steps_files+=("$f")
done

if [ "${#steps_files[@]}" -gt 0 ]; then
  check_idempotent "Depth-3 skills/*/steps/*.md" "../../../" "${steps_files[@]}"
else
  echo "[INFO] No skills/*/steps/*.md found -- skipping"
fi

# ---------------------------------------------------------------------------
# Depth 3: skills/*/data/*.md  (prefix: ../../../)
# ---------------------------------------------------------------------------
data_files=()
for f in "$REPO_ROOT/skills/"*/data/*.md; do
  [ -f "$f" ] && data_files+=("$f")
done

if [ "${#data_files[@]}" -gt 0 ]; then
  check_idempotent "Depth-3 skills/*/data/*.md" "../../../" "${data_files[@]}"
else
  echo "[INFO] No skills/*/data/*.md found -- skipping"
fi

# ---------------------------------------------------------------------------
# EXTRA: Verify the non-idempotency failure mode is detectable
# Synthesize a file with a PRE-PREFIXED path and run the depth-2 sed on it.
# If the pattern is correct, `../../core/X.md` should NOT be re-prefixed.
# If the pattern is wrong (missing [^./] guard), it would produce `../../../../core/X.md`.
# ---------------------------------------------------------------------------
echo "[INFO] Counterfactual: verifying pattern does not double-prefix already-correct refs..."

SYNTHETIC="$TMPDIR_IDEM/synthetic_skill.md"
cat > "$SYNTHETIC" <<'SYN_EOF'
# Synthetic SKILL.md for idempotency self-test

Read: ../../core/mcp-preflight.md
Use: ../../core/state-manager.md
SYN_EOF

before=$(cat "$SYNTHETIC")
after=$(printf '%s\n' "$before" | \
  sed -E 's|([^./])core/([a-z][a-z-]*\.md)|\1../../core/\2|g')

if [ "$before" = "$after" ]; then
  echo "[PASS] Counterfactual: already-prefixed ../../core/ refs unchanged by depth-2 sed"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] Counterfactual: depth-2 sed DOUBLE-PREFIXED already-correct refs!"
  echo "[INFO] before: $(printf '%s\n' "$before" | head -5)"
  echo "[INFO] after:  $(printf '%s\n' "$after" | head -5)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Also verify depth-3 doesn't double-prefix ../../../
SYNTHETIC3="$TMPDIR_IDEM/synthetic_step.md"
cat > "$SYNTHETIC3" <<'SYN3_EOF'
Read: ../../../core/mcp-preflight.md
Use: ../../../core/state-manager.md
SYN3_EOF

before3=$(cat "$SYNTHETIC3")
after3=$(printf '%s\n' "$before3" | \
  sed -E 's|([^./])core/([a-z][a-z-]*\.md)|\1../../../core/\2|g')

if [ "$before3" = "$after3" ]; then
  echo "[PASS] Counterfactual: already-prefixed ../../../core/ refs unchanged by depth-3 sed"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] Counterfactual: depth-3 sed DOUBLE-PREFIXED already-correct refs!"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "[PASS] v10-idempotency-second-pass: all assertions passed"
  exit 0
else
  echo "[FAIL] v10-idempotency-second-pass: $FAIL_COUNT assertion(s) failed"
  exit 1
fi
