# Code Review Checklist

## Correctness
- [ ] Fix addresses root cause, not symptoms
- [ ] All affected code paths covered
- [ ] No new bugs introduced

## Security
- [ ] No injection vulnerabilities (SQL, command, XSS)
- [ ] No auth bypass
- [ ] No information leakage
- [ ] No insecure defaults

## Quality
- [ ] Follows project coding conventions
- [ ] Comments and identifiers use the project's code language; localized text only in user-facing strings
- [ ] No unnecessary changes or refactoring
- [ ] Diff is minimal and focused
- [ ] No performance regressions (N+1, blocking calls)

## Test meaningfulness (any test in the diff)
- [ ] Test would FAIL if the change were reverted (has real regression value)
- [ ] Test calls the real production code — not a re-implemented copy of the logic
- [ ] Test exercises the changed code, not an unchanged collaborator standing in for it
- [ ] Assertions are non-vacuous (not empty-stays-empty, constant==constant, or mock-returns-its-own-setup)
- [ ] "Regression test" labels are accurate (the test actually tests the change)

## Edge Cases
- [ ] Null/undefined inputs handled
- [ ] Empty collections handled
- [ ] Boundary values handled (zero, negative, overflow)
- [ ] Error paths tested
- [ ] Concurrent access safe (if applicable)

## Integration
- [ ] Backwards compatible (no public API changes without approval)
- [ ] Existing callers not broken
- [ ] Dependencies stable and compatible
