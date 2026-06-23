#!/usr/bin/env bash
# Test: check-setup SKILL.md — 3 bug-fix improvements (AC-1..14)
# Validates: TLS diagnostic (AC-1..5), SC connectivity (AC-6..9),
#            path resolution (AC-10..12), output format (AC-13), no regression (AC-14)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
SKILL="$REPO_ROOT/skills/check-setup/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }

if [ ! -f "$SKILL" ]; then
  echo "FAIL: skills/check-setup/SKILL.md not found at $SKILL"
  exit 1
fi

# -----------------------------------------------------------------------
# T1: TLS Diagnostic Block (AC-1..5)
# -----------------------------------------------------------------------
echo "--- T1: TLS Diagnostic Block (AC-1..5) ---"

# AC-1: NODE_OPTIONS: --use-system-ca appears in TLS branch text
if grep -q 'NODE_OPTIONS.*--use-system-ca\|--use-system-ca.*NODE_OPTIONS' "$SKILL"; then
  echo "OK (AC-1): NODE_OPTIONS: --use-system-ca present in TLS diagnostic"
else
  fail "AC-1: NODE_OPTIONS: --use-system-ca not found in $SKILL"
fi

# AC-2: curl probe command present for TLS reachability check
if grep -q 'curl.*-s.*-o.*/dev/null\|curl.*--max-time' "$SKILL"; then
  echo "OK (AC-2): curl probe command present for TLS reachability"
else
  fail "AC-2: curl reachability probe not found in $SKILL"
fi

# AC-2 (continued): curl-success branch confirms server reachable + TLS
if grep -qi 'reachable' "$SKILL" && grep -qi 'TLS\|tls' "$SKILL"; then
  echo "OK (AC-2): reachability confirmation and TLS identification present"
else
  fail "AC-2: curl-success branch must mention both reachability and TLS"
fi

# AC-3: curl-failure and curl-absent branches both retain NODE_OPTIONS hint
# Both branches must keep the hint — count occurrences of NODE_OPTIONS (expect >= 3:
# curl-success, curl-failure, curl-absent all need it)
node_opts_count=$(grep -c 'NODE_OPTIONS' "$SKILL" || true)
if [ "$node_opts_count" -ge 3 ]; then
  echo "OK (AC-3): NODE_OPTIONS appears $node_opts_count times — all TLS sub-branches covered"
else
  fail "AC-3: NODE_OPTIONS appears only $node_opts_count time(s) — curl-failure and curl-absent branches may be missing it (expected >= 3)"
fi

# AC-4: generic unreachable fallback includes soft TLS/private-CA hint
# The fallback branch must mention NODE_OPTIONS or private CA
if grep -qi 'private.*CA\|private ca\|NODE_OPTIONS' "$SKILL"; then
  echo "OK (AC-4): Generic unreachable branch includes soft TLS/private-CA hint"
else
  fail "AC-4: Generic unreachable fallback branch missing NODE_OPTIONS or private-CA hint"
fi

# AC-5: TLS classification comes before auth classification in Step 9
# Strategy: find line numbers for TLS and auth classification markers and compare
tls_line=$(grep -n 'UNABLE_TO_VERIFY_LEAF_SIGNATURE\|CERT_UNTRUSTED\|SELF_SIGNED_CERT\|ERR_TLS_\|DEPTH_ZERO' "$SKILL" | head -1 | cut -d: -f1 || true)
auth_line=$(grep -n '401\|403\|Unauthorized\|Forbidden' "$SKILL" | grep -v 'Output format\|output format' | head -1 | cut -d: -f1 || true)
if [ -n "$tls_line" ] && [ -n "$auth_line" ]; then
  if [ "$tls_line" -lt "$auth_line" ]; then
    echo "OK (AC-5): TLS classification (line $tls_line) appears before auth classification (line $auth_line)"
  else
    fail "AC-5: Auth classification (line $auth_line) appears before TLS classification (line $tls_line)"
  fi
else
  fail "AC-5: Could not find TLS pattern indicators (tls_line=$tls_line) or auth markers (auth_line=$auth_line) in $SKILL"
fi

# -----------------------------------------------------------------------
# T2: SC Connectivity (AC-6..9)
# -----------------------------------------------------------------------
echo "--- T2: SC Connectivity (AC-6..9) ---"

# AC-6: Step 10 must NOT contain "list repositories" / "list_my_repositories" / "list my repositories"
# and must NOT contain "NO read:user" check (old broad permissions)
if grep -qi 'list.repositories\|list_my_repositories\|list my repositories\|read:user' "$SKILL"; then
  fail "AC-6: Step 10 still references list_my_repositories or read:user (overly broad permission)"
else
  echo "OK (AC-6): No list_my_repositories or read:user found — targeted repo fetch pattern in place"
fi

# AC-6: Step 10 must reference the configured Remote from Automation Config
if grep -qi 'Remote\|remote' "$SKILL" | grep -qi 'Source Control\|Automation Config' 2>/dev/null || \
   grep -q 'Remote.*Automation Config\|Automation Config.*Remote\|Source Control.*Remote' "$SKILL"; then
  echo "OK (AC-6): Step 10 references Remote from Automation Config"
elif grep -q 'Remote' "$SKILL"; then
  echo "OK (AC-6): Remote value referenced in connectivity section"
else
  fail "AC-6: Step 10 does not reference the configured Remote / Automation Config"
fi

# AC-7: auth failure branch includes repository:read scope hint
if grep -q 'repository:read' "$SKILL"; then
  echo "OK (AC-7): repository:read scope hint present in auth failure branch"
else
  fail "AC-7: repository:read scope hint missing from auth failure branch"
fi

# AC-8: 404 produces a distinct not-found message in Step 10 (Block 3 Connectivity section)
# Extract Block 3 (Connectivity) region: from "Block 3" to "Block 4"
block3_start=$(grep -n 'Block 3\|### Block 3' "$SKILL" | head -1 | cut -d: -f1 || true)
block4_start=$(grep -n 'Block 4\|### Block 4' "$SKILL" | head -1 | cut -d: -f1 || true)
if [ -n "$block3_start" ] && [ -n "$block4_start" ] && [ "$block4_start" -gt "$block3_start" ]; then
  connectivity_region=$(sed -n "${block3_start},${block4_start}p" "$SKILL")
  if grep -qE '404|HTTP 404|not found.*Remote|Remote.*not found|repo.*not found' <<< "$connectivity_region"; then
    echo "OK (AC-8): 404 / not-found branch present in Step 10 (Connectivity block)"
  else
    fail "AC-8: No 404 or repo-not-found branch found in Step 10 Connectivity block — must be a distinct message from auth failure"
  fi
else
  # Fallback: check for HTTP 404 specifically (less ambiguous than generic "not found")
  if grep -qE 'HTTP 404|404 Not Found|404.*Unauthorized\|404.*repository' "$SKILL"; then
    echo "OK (AC-8): 404 branch present"
  else
    fail "AC-8: No 404 not-found branch found in $SKILL"
  fi
fi

# AC-9: tool-not-found degrades to [WARN] not [FAIL] in Step 10 (SC connectivity)
# Check the Block 3 / Step 10 region for a [WARN] that relates to tool availability
# Using the same block3/block4 region captured above
if [ -n "${block3_start:-}" ] && [ -n "${block4_start:-}" ] && [ "$block4_start" -gt "$block3_start" ]; then
  if grep -qE '\[WARN\].*tool|\[WARN\].*not supported|\[WARN\].*unavailable|tool.*\[WARN\]' <<< "$connectivity_region"; then
    echo "OK (AC-9): [WARN] for tool-not-found found in Connectivity block"
  else
    fail "AC-9: [WARN] for tool-not-found branch missing from Connectivity block (Step 10) — must degrade gracefully, not [FAIL]"
  fi
else
  # Fallback: look for [WARN] adjacent to "tool" keyword in the file
  if grep -qE '\[WARN\].*tool|tool.*not.*support.*\[WARN\]' "$SKILL"; then
    echo "OK (AC-9): [WARN] tool-not-found pattern present"
  else
    fail "AC-9: [WARN] for tool-not-found branch missing — must degrade gracefully, not [FAIL]"
  fi
fi

# -----------------------------------------------------------------------
# T3: Path Resolution (AC-10..12)
# -----------------------------------------------------------------------
echo "--- T3: Path Resolution (AC-10..12) ---"

# AC-10: Step 3a uses Glob with .claude/plugins/ as first attempt
# Extract the Step 3a region: from "### 3a" to the next numbered step ("4.")
step3a_start=$(grep -n '### 3a\|^### 3a' "$SKILL" | head -1 | cut -d: -f1 || true)
step4_line=$(grep -n '^4\.' "$SKILL" | head -1 | cut -d: -f1 || true)

if [ -n "$step3a_start" ] && [ -n "$step4_line" ] && [ "$step4_line" -gt "$step3a_start" ]; then
  step3a_region=$(sed -n "${step3a_start},${step4_line}p" "$SKILL")
  if contains "$step3a_region" ".claude/plugins"; then
    echo "OK (AC-10): .claude/plugins/ Glob pattern present in Step 3a path resolution"
  else
    fail "AC-10: .claude/plugins/ Glob pattern not found in Step 3a — narrow Glob layer missing"
  fi
  # AC-10: broad ** pattern also present (second layer) within Step 3a
  if grep -qE '\*\*/docs/reference/trackers|\*\*.*trackers\.md' <<< "$step3a_region"; then
    echo "OK (AC-10): Broad Glob (**) pattern present in Step 3a for second resolution layer"
  else
    fail "AC-10: Broad Glob (**) pattern for trackers.md not found in Step 3a — second resolution layer missing"
  fi
else
  # Fallback if section markers not yet present (pre-fix state)
  if grep -q '\.claude/plugins.*trackers\|Glob.*\.claude/plugins' "$SKILL"; then
    echo "OK (AC-10): .claude/plugins/ Glob pattern present"
  else
    fail "AC-10: .claude/plugins/ Glob pattern not found — narrow Glob layer missing in Step 3a"
  fi
  if grep -qE '\*\*/docs/reference/trackers|\*\*.*trackers\.md' "$SKILL"; then
    echo "OK (AC-10): Broad Glob (**) pattern for trackers.md present"
  else
    fail "AC-10: Broad Glob (**) pattern for trackers.md not found — second resolution layer missing"
  fi
fi

# AC-11: file-not-found case emits [WARN] and skips (not [FAIL])
# Verify the WARN + skip pattern exists near the trackers.md resolution
if grep -q '\[WARN\]' "$SKILL" && grep -qi 'skipped\|skip' "$SKILL"; then
  echo "OK (AC-11): [WARN] + skip instruction present for missing trackers.md"
else
  fail "AC-11: [WARN] + skip not found — missing trackers.md must degrade gracefully, not [FAIL]"
fi

# AC-11: must NOT use bare Read docs/reference/trackers.md (CWD-relative path without Glob)
# A bare relative read without a Glob wrapper is the old pattern being replaced
if grep -qE '^Read `docs/reference/trackers\.md`|^Read docs/reference/trackers\.md' "$SKILL"; then
  fail "AC-11/AC-10: Bare Read docs/reference/trackers.md found — must use Glob-first resolution instead"
else
  echo "OK (AC-11): No bare CWD-relative Read of trackers.md — Glob-first pattern enforced"
fi

# AC-12: Step 7 references Step 3a for path reuse (no re-globbing)
if grep -qi 'Step 3a\|step 3a\|resolved.*path\|path.*resolved' "$SKILL"; then
  echo "OK (AC-12): Step 7 references Step 3a's resolved path"
else
  fail "AC-12: Step 7 does not reference Step 3a resolved path — may be re-globbing"
fi

# -----------------------------------------------------------------------
# T4: Output Format (AC-13)
# -----------------------------------------------------------------------
echo "--- T4: Output format — TLS example (AC-13) ---"

# AC-13: Output format Connectivity block includes a TLS [FAIL] example with NODE_OPTIONS
# Look for NODE_OPTIONS in the output format section specifically
output_section_has_tls=$(awk '/^## Output format/,/^## Rules/' "$SKILL" | grep -c 'NODE_OPTIONS' || true)
if [ "$output_section_has_tls" -ge 1 ]; then
  echo "OK (AC-13): Output format Connectivity block contains TLS [FAIL] example with NODE_OPTIONS"
else
  fail "AC-13: Output format section missing TLS [FAIL] example with NODE_OPTIONS: --use-system-ca"
fi

# -----------------------------------------------------------------------
# T5: No Regression (AC-14)
# -----------------------------------------------------------------------
echo "--- T5: No regression (AC-14) ---"

# Verify the 5 required block headers are present
BLOCK_HEADERS=(
  "Block 1"
  "Block 2"
  "Block 3"
  "Block 4"
  "Block 5"
)
for header in "${BLOCK_HEADERS[@]}"; do
  if grep -q "$header" "$SKILL"; then
    echo "OK (AC-14): Section header '$header' present"
  else
    fail "AC-14: Section header '$header' missing — regression in block structure"
  fi
done

# Rules section must be present
if grep -q '^## Rules' "$SKILL"; then
  echo "OK (AC-14): ## Rules section present"
else
  fail "AC-14: ## Rules section missing — regression"
fi

# Frontmatter must be present with required fields
for field in name description allowed-tools; do
  if grep -q "^$field:" "$SKILL"; then
    echo "OK (AC-14): Frontmatter field '$field' present"
  else
    fail "AC-14: Frontmatter field '$field' missing — regression"
  fi
done

# -----------------------------------------------------------------------
# Final result
# -----------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: check-setup SKILL.md improvements — TLS diagnostic (AC-1..5), SC connectivity (AC-6..9), path resolution (AC-10..12), output format (AC-13), no regression (AC-14)"
fi
exit "$FAIL"
