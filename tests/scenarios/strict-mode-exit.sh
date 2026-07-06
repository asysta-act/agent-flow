#!/usr/bin/env bash
# ===========================================================================
# Test:     v10-strict-mode-exit.sh
# Semantics: STRICT-BY-DEFAULT dispatch-witness gate in hooks/validate-dispatch.sh.
#   strict ON  when AGENT_FLOW_STRICT_DISPATCH is unset OR != "0"  (default)
#   advisory   when AGENT_FLOW_STRICT_DISPATCH == "0"
# Checks:
#   (a) default (var UNSET) + a true WITNESS_MISMATCH  => exit 2 + audit entry
#   (b) AGENT_FLOW_STRICT_DISPATCH=0 + same mismatch    => advisory exit 0
#   (c) WITNESS_MISSING (no mismatch) in default strict => exit 0 (never exit 2)
#   (d) fully-consistent state (witness == recompute,
#       no customization/<agent>.toml on disk)          => exit 0
# Mismatch is a REAL V1 recompute miss: the stored model is corrupted so the
# recompute over (agent_name|model|prompt_head_128|overlay_source|overlay_digest)
# no longer equals the stored dispatch_witness.
# ===========================================================================
set -uo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

HOOK="hooks/validate-dispatch.sh"
LIB="core/lib/stage-invariant.sh"
[ -f "$HOOK" ] || { echo "SKIP: $HOOK not found" >&2; exit 77; }
[ -f "$LIB" ]  || { echo "SKIP: $LIB not found" >&2; exit 77; }

# shellcheck disable=SC1090
. "$LIB"

# ---------------------------------------------------------------------------
# Build a real V1-mismatch fixture: a valid 5-tuple witness for the publisher
# stage, but with the stored MODEL deliberately corrupted so the hook's
# recompute differs from the stored witness => WITNESS_MISMATCH.
# overlay_source=none keeps V2 quiet (no customization/<agent>.toml needed).
# ---------------------------------------------------------------------------
HEAD="PROMPT_HEAD_publisher"
GOOD_WITNESS=$(compute_dispatch_witness "publisher" "agent-flow:publisher" "sonnet" "$HEAD" "none" "none") \
  || { echo "SKIP: cannot compute witness (no sha256 tool)" >&2; exit 77; }

tmp_mismatch=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/v10sm_mismatch_$$")
tmp_missing=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/v10sm_missing_$$")
tmp_ok=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/v10sm_ok_$$")
tmp_audit=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/v10sm_audit_$$")
trap 'rm -f "$tmp_mismatch" "$tmp_missing" "$tmp_ok" "$tmp_audit"' EXIT

# Mismatch: stored model "opus" but witness computed for "sonnet" => recompute miss.
cat > "$tmp_mismatch" <<FIXTURE
{
  "schema_version": "1.0",
  "stages": {
    "publisher": {
      "dispatched_at": "2026-05-12T10:09:00Z",
      "agent_name": "agent-flow:publisher",
      "model": "opus",
      "stage_name": "publisher",
      "prompt_head_128": "$HEAD",
      "overlay_source": "none",
      "overlay_digest": "none",
      "dispatch_witness": "$GOOD_WITNESS",
      "status": "in_progress"
    }
  }
}
FIXTURE

# Missing: publisher has dispatched_at but no witness inputs => WITNESS_MISSING.
cat > "$tmp_missing" <<'FIXTURE'
{
  "schema_version": "1.0",
  "stages": {
    "publisher": {
      "dispatched_at": "2026-05-12T10:09:00Z",
      "stage_name": "publisher",
      "status": "in_progress"
    }
  }
}
FIXTURE

# Consistent: stored witness == recompute, overlay_source=none (no .toml on disk).
cat > "$tmp_ok" <<FIXTURE
{
  "schema_version": "1.0",
  "stages": {
    "publisher": {
      "dispatched_at": "2026-05-12T10:09:00Z",
      "agent_name": "agent-flow:publisher",
      "model": "sonnet",
      "stage_name": "publisher",
      "prompt_head_128": "$HEAD",
      "overlay_source": "none",
      "overlay_digest": "none",
      "dispatch_witness": "$GOOD_WITNESS",
      "status": "in_progress"
    }
  }
}
FIXTURE

# Sanity: confirm the lib agrees with our intent before exercising the hook.
v=$(check_dispatch_witness publisher "$tmp_mismatch"); [ "$v" = "WITNESS_MISMATCH" ] \
  || fail "precondition: expected WITNESS_MISMATCH for corrupted-model fixture, got $v"
v=$(check_dispatch_witness publisher "$tmp_missing"); [ "$v" = "WITNESS_MISSING" ] \
  || fail "precondition: expected WITNESS_MISSING for no-inputs fixture, got $v"
v=$(check_dispatch_witness publisher "$tmp_ok"); [ "$v" = "WITNESS_OK" ] \
  || fail "precondition: expected WITNESS_OK for consistent fixture, got $v"

# Isolated override path so V2 never finds a .toml (we test V1 here).
ISO_OVERRIDE=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/v10sm_ovr_$$")
mkdir -p "$ISO_OVERRIDE" 2>/dev/null || true
trap 'rm -f "$tmp_mismatch" "$tmp_missing" "$tmp_ok" "$tmp_audit"; rm -rf "$ISO_OVERRIDE"' EXIT

# ---------------------------------------------------------------------------
# (a) DEFAULT strict (var UNSET) + true MISMATCH => exit 2 + audit MISMATCH line.
# ---------------------------------------------------------------------------
> "$tmp_audit"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH \
  AGENT_FLOW_STATE_JSON="$tmp_mismatch" AGENT_FLOW_AUDIT_LOG="$tmp_audit" \
  AGENT_FLOW_OVERRIDE_PATH="$ISO_OVERRIDE" \
  bash "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] || fail "(a) default-strict exit: expected exit 2 on MISMATCH, got $rc"
grep -q 'WITNESS_MISMATCH' "$tmp_audit" 2>/dev/null \
  || fail "(a) audit-entry: WITNESS_MISMATCH not written to audit log in default-strict mode"

# ---------------------------------------------------------------------------
# (b) AGENT_FLOW_STRICT_DISPATCH=0 + same MISMATCH => advisory exit 0.
# ---------------------------------------------------------------------------
> "$tmp_audit"
rc=0
AGENT_FLOW_STRICT_DISPATCH=0 \
  AGENT_FLOW_STATE_JSON="$tmp_mismatch" AGENT_FLOW_AUDIT_LOG="$tmp_audit" \
  AGENT_FLOW_OVERRIDE_PATH="$ISO_OVERRIDE" \
  bash "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "(b) advisory exit: AGENT_FLOW_STRICT_DISPATCH=0 exited $rc on MISMATCH (expected 0)"
grep -q 'WITNESS_MISMATCH' "$tmp_audit" 2>/dev/null \
  || fail "(b) advisory still audits: WITNESS_MISMATCH line missing in advisory mode"

# ---------------------------------------------------------------------------
# (c) DEFAULT strict + WITNESS_MISSING (no mismatch) => exit 0 (never exit 2).
# ---------------------------------------------------------------------------
> "$tmp_audit"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH \
  AGENT_FLOW_STATE_JSON="$tmp_missing" AGENT_FLOW_AUDIT_LOG="$tmp_audit" \
  AGENT_FLOW_OVERRIDE_PATH="$ISO_OVERRIDE" \
  bash "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = "2" ] && fail "(c) missing-no-exit2: WITNESS_MISSING triggered strict exit 2 (only MISMATCH may)"

# ---------------------------------------------------------------------------
# (d) DEFAULT strict + fully-consistent state => exit 0.
# ---------------------------------------------------------------------------
> "$tmp_audit"
rc=0
env -u AGENT_FLOW_STRICT_DISPATCH \
  AGENT_FLOW_STATE_JSON="$tmp_ok" AGENT_FLOW_AUDIT_LOG="$tmp_audit" \
  AGENT_FLOW_OVERRIDE_PATH="$ISO_OVERRIDE" \
  bash "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "(d) consistent-exit0: consistent state exited $rc (expected 0)"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-strict-mode-exit — strict-by-default exits 2 on true MISMATCH; AGENT_FLOW_STRICT_DISPATCH=0 advisory exits 0; MISSING never exits 2; consistent state exits 0"
  exit 0
fi
exit 1
