#!/bin/bash
# Covers: AC-2 (core-contract count = 17, UNCHANGED; maxdepth-1 only, excludes core/aliases/)
# AC-2 and AC-CT-004 (count-core-contracts.sh) assert the identical fact (core/ top-level
# .md count == 17). Per CONTRIBUTING.md rule 9 (no duplicate coverage for an existing AC id),
# the find|wc -l assertion lives in one place only — count-core-contracts.sh — and this
# scenario delegates to it instead of re-implementing the same grep logic.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

exec bash "$REPO_ROOT/tests/scenarios/count-core-contracts.sh"
