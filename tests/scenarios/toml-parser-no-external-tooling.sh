#!/usr/bin/env bash
# Test: toml-parser-no-external-tooling
# FC mapped: FC-04
# What it checks:
#   Neither the config-reader parsing path NOR the limits-resolution path invokes
#   tomllib / tomli / taplo / python3 for reading config.toml, config.local.toml, or
#   customization/{agent}.toml [limits]. The host is Python 3.10 (tomllib needs 3.11+),
#   so the reader must be pure bash end to end.
# Expected RED (pre-impl): this is largely a negative-absence check against the
#   REWRITTEN core/config-reader.md, which does not exist yet in its target form --
#   the file exists but the "no external tooling" / "pure-bash" language is absent.
# Expected GREEN (post-impl): core/config-reader.md contains no tomllib/tomli/taplo/
#   python3 dependency and states the parser + limits path are pure bash.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: cannot resolve REPO_ROOT via git" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
source "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

READER="core/config-reader.md"
reader_content=""; [ -f "$READER" ] && reader_content="$(cat "$READER")"
[ -f "$READER" ] || fail "$READER not found"

# Negative assertions: none of these tools may be required on the config-read path.
contains "$reader_content" "tomllib" && fail "FC-04: core/config-reader.md still references tomllib on the config-read path"
contains "$reader_content" "tomli"   && fail "FC-04: core/config-reader.md still references tomli on the config-read path"
contains "$reader_content" "taplo"   && fail "FC-04: core/config-reader.md still references taplo"

# Positive assertion: the reader documents itself as pure-bash.
contains_i "$reader_content" "pure-bash" || fail "FC-04: core/config-reader.md does not declare itself a pure-bash parser"

# The [limits] tier read must also be pure-bash and NOT delegate to toml-merge.sh (REQ-29).
contains "$reader_content" "skills/setup-agents/lib/toml-merge.sh" && fail "FC-04/FC-26: core/config-reader.md routes the [limits] read through toml-merge.sh (must stay pure-bash per design.md section 1.4)"
contains_i "$reader_content" "[limits]" || fail "FC-04: core/config-reader.md does not document reading the customization/{agent}.toml [limits] tier"

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: toml-parser-no-external-tooling -- no tomllib/tomli/taplo/toml-merge.sh dependency on the config-read or limits path"
  exit 0
fi
exit 1
