# Testing agent-flow

Test suite for verifying pipeline logic. Contains a mock MCP server, test runner, and 264 automated scenarios.

## Structure

```
tests/
├── mock-project/          ← Mock project with Automation Config
│   ├── CLAUDE.md          ← Complete Automation Config
│   ├── app.py             ← Python code with two intentional bugs
│   └── tests/test_app.py  ← Tests for mock code
├── scenarios/             ← 264 test scenarios (bash scripts)
│   ├── happy-path.sh      ← Full pipeline end-to-end
│   ├── triage-block.sh    ← Triage-analyst detects duplicate → Block
│   ├── fixer-retry.sh     ← Fixer exhausts retry limit → Block + rollback
│   ├── reviewer-reject.sh ← Reviewer rejects fix → fixer iterates
│   ├── test-fail.sh       ← Test-engineer fails → Block after limit
│   ├── publish-success.sh ← Publisher creates PR and updates tracker
│   ├── profile-skip.sh    ← Pipeline Profiles — skip stages
│   ├── verify-fail.sh     ← Fix Verification fails → issue re-opened
│   ├── scaffold-spec-happy-path.sh    ← Scaffold spec-first full pipeline
│   ├── scaffold-spec-no-implement.sh  ← --no-implement mode (skips spec phase)
│   ├── scaffold-spec-loop.sh          ← Spec-writer/reviewer loop
│   ├── scaffold-spec-input-conflicts.sh ← Flag validation
│   └── pipeline-consistency.sh        ← Cross-command consistency checks
├── harness/               ← Test infrastructure
│   ├── fixtures/          ← Mock data (issues.json, automation-config.md)
│   ├── mock-mcp-server.sh ← Mock MCP server
│   └── run-tests.sh       ← Test runner
└── README.md              ← This file
```

## Mock project

`tests/mock-project/` contains:
- `CLAUDE.md` — complete Automation Config with all sections
- `app.py` — Python code with two intentional bugs
- `tests/test_app.py` — tests that fail on buggy code and pass after fix

## Test scenarios

The table below shows a representative sample of scenarios — it is **not** an exhaustive list. The full suite contains 264 scenarios in `tests/scenarios/`.

| Scenario (examples) | File | Verifies |
|---------------------|------|----------|
| Happy path | `happy-path.sh` | Full pipeline: triage → analyst (impact) → fixer → reviewer → test-engineer → publisher |
| Triage block | `triage-block.sh` | Triage-analyst detects duplicate → Block |
| Fixer retry | `fixer-retry.sh` | Fixer exhausts retry limit → Block + rollback |
| Reviewer reject | `reviewer-reject.sh` | Reviewer rejects fix → fixer iterates |
| Test fail | `test-fail.sh` | Test-engineer fails → Block after limit |
| Publish success | `publish-success.sh` | Publisher creates PR and updates tracker |
| Profile skip | `profile-skip.sh` | Pipeline Profiles — skip stages |
| Verify fail | `verify-fail.sh` | Fix Verification fails → issue re-opened |
| Scaffold spec-first happy path | `scaffold-spec-happy-path.sh` | Spec-first scaffold pipeline: spec → skeleton → features → report |
| Scaffold no-implement | `scaffold-spec-no-implement.sh` | --no-implement skips spec phase |
| Scaffold spec loop | `scaffold-spec-loop.sh` | spec-writer/spec-reviewer iteration loop mechanics |
| Scaffold input conflicts | `scaffold-spec-input-conflicts.sh` | Mutually exclusive flag validation |
| Pipeline consistency | `pipeline-consistency.sh` | Cross-command pattern consistency (block format, git add, retries, safety) |

## Running

```bash
# All scenarios
./tests/harness/run-tests.sh

# Single scenario
./tests/harness/run-tests.sh happy-path

# Control parallelism (defaults to nproc, fallback 4)
HARNESS_JOBS=4 ./tests/harness/run-tests.sh
```

**Run the full suite before every push and confirm `Fail: 0`.** CI runs the same
suite as a backstop, not as the first gate — a green subset run locally can still
let a cross-cutting scenario fail in CI.

### Windows (MSYS2 / Git Bash)

The harness forks one bash process per scenario via `xargs -P`. Windows does not
reap those children when the parent dies, so on this platform:

- **Always run sequentially:** `HARNESS_JOBS=1 ./tests/harness/run-tests.sh`
- **Never start a second run** while one is still active.
- **Never kill a running harness.** Let it finish — killing it strands every forked
  bash subprocess as a zombie, and after a few killed runs the process table fills
  with thousands of `bash.exe` entries that grind the machine to a halt. If you must
  abort, recover with `Get-Process bash | Stop-Process -Force` (PowerShell), repeated
  until the count drops.

## Writing scenarios

See [CONTRIBUTING.md](../CONTRIBUTING.md#functional-test-scenarios--security-expectations)
for the scenario review checklist. In particular, assert substrings against shell
variables with the `tests/lib/assert.sh` helpers (`contains`, `contains_i`,
`matches_re`) rather than `echo "$VAR" | grep -q` — the latter flakes under
`pipefail` via SIGPIPE on Linux CI.

## Important

- Tests use a mock MCP server — no real instances required
- Mock MCP returns pre-prepared responses for each scenario
- CI: GitHub Actions workflow runs tests on push
