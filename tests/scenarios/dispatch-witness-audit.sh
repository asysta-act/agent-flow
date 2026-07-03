#!/usr/bin/env bash
# ===========================================================================
# Test:        v10-dispatch-witness-audit.sh
# FC mapped:   FC-2 (witness audit emission)
# What it checks:
#   1) core/lib/stage-invariant.sh exists
#   2) The library defines the 3 mandatory functions: compute_dispatch_witness,
#      check_dispatch_witness, emit_witness_audit
#   3) The witness algorithm uses sha256 and concatenates the 5-tuple
#      subagent_type|model|prompt_head_128|overlay_source|overlay_digest
#   4) The library is jq-free ("jq-free implementation")
#   5) The library is ≤340 lines (raised from 140 to accommodate the
#      overlay-aware 5-tuple witness: compute_overlay_digest, V1+V2
#      check_dispatch_witness, jq-free field readers, and --self-test)
# Expected RED phase: FAIL — core/lib/stage-invariant.sh does not yet exist
# Expected GREEN phase (post-impl): PASS
# Notes:
#   - We do NOT exercise the hook end-to-end with fixtures here (that requires
#     fixtures files outside .forge/phase-5-tdd/ and would violate scope guard).
#     Phase 7 implementation will land the canonical FC-2 fixture-driven test.
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

count_lines() { tr -d '\r' < "$1" | wc -l | tr -d ' '; }

LIB="core/lib/stage-invariant.sh"

# 1) File exists
if [ ! -f "$LIB" ]; then
  fail "FC-2.lib-missing: $LIB does not exist"
  exit 1
fi

# 2) Three mandatory function signatures present
# Accept either `funcname() {` or `function funcname` style.
for fn in compute_dispatch_witness check_dispatch_witness emit_witness_audit; do
  if ! grep -qE "(^|[[:space:]])(function[[:space:]]+)?${fn}[[:space:]]*\(" "$LIB"; then
    fail "FC-2.fn: $LIB missing function definition '${fn}'"
  fi
done

# 3) Algorithm references sha256 (any of the common spellings the impl might use)
if ! grep -qiE 'sha256|sha-256' "$LIB"; then
  fail "FC-2.algo-sha256: $LIB does not reference sha256 hashing"
fi

# 3b) Algorithm concatenates the 5-tuple
#     subagent_type|model|prompt_head_128|overlay_source|overlay_digest.
# Look for the literal pipe-separated canonical form documented, else fall back
# to a proximity check requiring all five tokens within close range.
# Case-insensitive: the lib documents the canonical form with UPPERCASE
# placeholders (<SUBAGENT_TYPE>|<MODEL>|...) and uses lowercase locals elsewhere.
if ! grep -qiE 'subagent_type.*\|.*model.*\|.*prompt_head_128.*\|.*overlay_source.*\|.*overlay_digest' "$LIB"; then
  # Permissive fallback: require all five tokens within a 12-line window.
  if ! awk 'BEGIN{IGNORECASE=1}
      /subagent_type/{a=NR} /model/{b=NR} /prompt_head_128/{c=NR}
      /overlay_source/{d=NR} /overlay_digest/{e=NR}
      END{
        if(a&&b&&c&&d&&e){
          n=a; m=a;
          split(a" "b" "c" "d" "e, arr, " ");
          for(i=1;i<=5;i++){ if(arr[i]>m)m=arr[i]; if(arr[i]<n)n=arr[i]; }
          exit (m-n<=12)?0:1
        } else exit 1
      }' "$LIB"; then
    fail "FC-2.algo-canon: $LIB witness algorithm does not concatenate subagent_type|model|prompt_head_128|overlay_source|overlay_digest"
  fi
fi

# 4) jq-free — no `jq` invocations.
if grep -qE '(^|[[:space:]])jq([[:space:]]|$)' "$LIB"; then
  fail "FC-2.no-jq: $LIB invokes 'jq' but the contract mandates jq-free implementation"
fi

# 5) Line ceiling: ≤340 (raised from 140 for the overlay-aware 5-tuple witness)
LIB_LINES=$(count_lines "$LIB")
if [ "$LIB_LINES" -gt 340 ]; then
  fail "FC-2.lib-size: $LIB = ${LIB_LINES}L (ceiling 340)"
fi

# 6) compute_overlay_digest helper present (produces the 5th witness input).
if ! grep -qE "(^|[[:space:]])(function[[:space:]]+)?compute_overlay_digest[[:space:]]*\(" "$LIB"; then
  fail "FC-2.overlay-digest: $LIB missing function definition 'compute_overlay_digest'"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: v10-dispatch-witness-audit — $LIB ${LIB_LINES}L, 4 fns, sha256, jq-free, canonical 5-tuple pipe form"
  exit 0
fi
exit 1
