#!/usr/bin/env bash
# ===========================================================================
# Test:     release-readiness.sh
# AC:       AC-039, AC-036, AC-045, AC-052, AC-042 (REQ-039, REQ-036, REQ-045,
#           REQ-052, REQ-042) — the MAJOR v2.0.0 release contract.
#     - plugin.json version == 2.0.0; BOTH marketplace.json fields == 2.0.0;
#       CHANGELOG has a [2.0.0] entry (RED today: 1.2.0);
#     - no stale "230 scenarios" reference remains (RED today);
#     - .gitattributes pins hashed inputs eol=lf (tests/fixtures/**, *.toml, *.json);
#     - .gitignore ignores every per-run runtime artifact under .agent-flow/;
#     - License "MIT" triple + maintainer-email triple intact (must stay green).
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

# --- AC-039: version surfaces == 2.0.0 ----------------------------------------
matches_re "$(cat .claude-plugin/plugin.json)" '"version"[[:space:]]*:[[:space:]]*"2\.0\.0"' \
  || fail "version: plugin.json is not 2.0.0"
N=$(grep -cE '"version"[[:space:]]*:[[:space:]]*"2\.0\.0"' .claude-plugin/marketplace.json 2>/dev/null || true)
[ -n "$N" ] || N=0
[ "$N" -ge 2 ] || fail "version: marketplace.json must carry 2.0.0 in BOTH version fields (found $N)"
if [ -f CHANGELOG.md ]; then
  matches_re "$(cat CHANGELOG.md)" '\[2\.0\.0\]' || fail "changelog: no [2.0.0] entry"
else
  fail "changelog: CHANGELOG.md missing"
fi

# --- AC-036: no stale "230 scenarios" reference -------------------------------
for d in README.md tests/README.md docs/architecture.md docs/reference/skills.md; do
  [ -f "$d" ] || continue
  if grep -qE '230[[:space:]]+(automated[[:space:]]+)?(test[[:space:]]+)?scenarios' "$d" 2>/dev/null; then
    fail "count: stale '230 scenarios' reference still in $d"
  fi
done

# --- AC-045: .gitattributes LF pins on hashed inputs --------------------------
if [ -f .gitattributes ]; then
  GA=$(cat .gitattributes)
  matches_re "$GA" 'tests/fixtures/\*\*[[:space:]]+text[[:space:]]+eol=lf' \
    || fail "gitattributes: missing 'tests/fixtures/** text eol=lf' pin"
  matches_re "$GA" '\*\.toml[[:space:]]+text[[:space:]]+eol=lf' \
    || fail "gitattributes: missing '*.toml text eol=lf' pin"
  matches_re "$GA" '\*\.json[[:space:]]+text[[:space:]]+eol=lf' \
    || fail "gitattributes: missing '*.json text eol=lf' pin"
else
  fail "gitattributes: .gitattributes missing"
fi

# --- AC-052: per-run runtime artifacts are gitignored -------------------------
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  for art in \
      ".agent-flow/RUNID/dispatch.key" \
      ".agent-flow/RUNID/dispatch-ledger.jsonl" \
      ".agent-flow/pending-dispatch.json" \
      ".agent-flow/STRICT_DISPATCH_OFF" \
      ".agent-flow/RUNID/STRICT_DISPATCH_OFF" \
      ".agent-flow/.version-confirmed"; do
    git check-ignore -q "$art" 2>/dev/null \
      || fail "gitignore: '$art' is NOT ignored (secret/ledger/marker could be committed)"
  done
fi

# --- AC-042: License MIT triple + maintainer email triple (stay green) --------
matches_re "$(cat .claude-plugin/plugin.json)" '"license"[[:space:]]*:[[:space:]]*"MIT"' \
  || fail "invariant: plugin.json license != MIT"
[ -f LICENSE ] && { contains "$(head -n 5 LICENSE)" 'MIT' || fail "invariant: LICENSE first heading lacks MIT"; }
for f in SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md; do
  [ -f "$f" ] || continue
  contains "$(cat "$f")" 'filip.sabacky@ceosdata.com' || fail "invariant: $f missing maintainer email"
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: release-readiness — v2.0.0 in all version surfaces; no '230 scenarios'; LF pins; per-run artifacts gitignored; MIT/email intact"
  exit 0
fi
exit 1
