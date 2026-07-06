# Test Checklist

## Coverage
- [ ] Happy path tested
- [ ] Error path tested
- [ ] Edge cases tested (null, empty, boundary)
- [ ] Regression test for the specific bug (reproduces original issue) — or, if the change has no testable seam, a documented untestable-seam gap (see Meaningfulness)

## Meaningfulness (a test that does not test the change is worse than no test)
- [ ] Each test would FAIL if the change were reverted / the bug reintroduced
- [ ] Each test calls the real production code path — not a re-implemented copy of the logic
- [ ] No test exercises an unchanged collaborator as a stand-in for the changed code
- [ ] No vacuous/tautological assertions (empty-stays-empty, constant==constant, mock returns its own setup)
- [ ] If the change is not reachable from any testable seam: NO hollow test written; gap + manual/E2E verification documented instead

## Quality
- [ ] Tests follow Arrange-Act-Assert pattern
- [ ] Tests are independent (no shared mutable state)
- [ ] Tests use project conventions (framework, naming, location)
- [ ] Test code uses the project's code language (localized text only in user-facing-string assertions)
- [ ] No flaky tests (no timing dependencies, no external service calls)
- [ ] `--e2e` mode only: E2E test invoked via the configured Automation Config → E2E Test → Command (not the unit Build & Test command); new e2e test files follow the configured Framework's file/naming convention

## Completeness
- [ ] All changed functions have test coverage (or a documented untestable-seam gap)
- [ ] Test names describe expected behavior
- [ ] Assertions are specific (not just "no error thrown")
