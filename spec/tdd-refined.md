# Phase 5 Prompt — TDD (agent-flow Automation Config → .agent-flow/config.toml migration) [REFINED]

> Refined by phase-5 coordinator, invocation_id 2ba2c8e4-99d6-432f-9d4f-5df353a9cfb5, from
> `.forge/phase-4-spec/final/formal-criteria.md` (28 FC) + `design.md`. Only ANTI_PATTERNS and
> SUCCESS_CRITERIA are refined below; PERSONA, TASK_INSTRUCTIONS, and CODEBASE_CONTEXT are
> unchanged from `tdd.md` — read that file for those three sections verbatim.

## CITATION CORRECTION (apply this, overriding tdd.md's CODEBASE_CONTEXT line)

`tdd.md`'s Codebase Context cites `docs/guides/toml-overlay-syntax.md:149-150`. This is a
**stale pre-revision label**. The spec's round-2 revision (confirmed in
`.forge/phase-4-spec/final/design.md` lines 202, 233, 375, and required verbatim by FC-13's
check) corrected this to **`docs/guides/toml-overlay-syntax.md:150-157`**. Any test asserting
this citation (FC-13's pre-impl check against `design.md`) MUST use `:150-157`, never `:149-150`.

## Success Criteria — (SUCCESS_CRITERIA slot, refined)

All items from `tdd.md` SUCCESS_CRITERIA apply, PLUS the following made explicit from the 28 FC
criteria in `formal-criteria.md` (each test file should note which FC# it derives from in a
leading comment):

- Every one of the 28 FC criteria (FC-01..FC-28) has at least one corresponding scenario; the 7
  `[DEDICATED]` criteria (FC-02, FC-05, FC-09, FC-13, FC-15, FC-18, FC-19) PLUS the round-2-added
  FC-26 (pure-bash limits path, no `tomllib`, works on Python 3.10 host) each get their own
  scenario file, not folded into a generic one.
- FC-02/FC-17 distinction: the "hard-cut removal" test (FC-02) must assert zero
  parse-into-config paths OUTSIDE `skills/check-setup/SKILL.md`, while separately asserting that
  `skills/check-setup/SKILL.md`'s permitted detect-and-warn read does NOT itself map tables into
  a config object — these are two assertions in the same or paired scenarios, not one.
- FC-09 denylist test enumerates all six denylisted keys explicitly:
  `source_control.remote`, `source_control.base_branch`, `notifications.webhook_url`,
  `issue_tracker.instance`, `issue_tracker.project`, and "any `[pr_rules]` key" — not a vague
  catch-all assertion.
- FC-13/FC-26 are complementary, not duplicates: FC-13 asserts enforced==injected (both channels
  agree); FC-26 asserts the top-tier value actually applies on the real Python-3.10 host (no
  silent fallback to a lower tier). Author both.
- FC-19 test asserts the NEGATIVE (`^\.agent-flow/$` whole-dir ignore pattern must be ABSENT from
  installation.md's gitignore block) as rigorously as the positive (`config.local.toml` present,
  `config.toml` absent from the ignored block).
- FC-27 (delimited-scalar round-trip) covers three cases in one scenario: multi-element list
  (`labels = "bug, automated"`), multi-entry map (`state_transitions = "triage: In Progress;
  fixed: Fixed"`), AND the two edge cases — empty string → empty list/map, no-delimiter value →
  single-element list.
- FC-28 is a distinct scenario from FC-15: FC-15 is about `config.toml` gitignore FAIL/OK; FC-28
  is about `config.local.toml` present-but-NOT-gitignored triggering a `[WARN]` (accidental-commit
  guard), which is a WARN not a FAIL/block.
- Pre-implementation reality check: since Phase 7 (implementation) has not run, scenarios that
  need a live parser/resolver/check-setup binary should assert against the SPEC files
  (`design.md`, `core/config-reader.md` current content, `skills/check-setup/SKILL.md` current
  content) wherever `formal-criteria.md` offers a "Pre-impl:" form — and MUST currently FAIL red
  (since the current repo still has the inline-CLAUDE.md path), which is correct TDD state. Do
  not silently skip a criterion just because full behavioural testing needs Phase-7 code; write
  the pre-impl assertion form now and leave a `# TODO(phase-7)` marker only where
  `formal-criteria.md` itself distinguishes a behavioural-only check with no pre-impl fallback.

## Anti-Patterns — (ANTI_PATTERNS slot, refined)

All items from `tdd.md` ANTI_PATTERNS apply, PLUS:

- Citing `toml-overlay-syntax.md:149-150` anywhere (stale label) — always `:150-157` per the
  CITATION CORRECTION above.
- Collapsing FC-13 and FC-26 into a single scenario — they test different failure modes
  (channel-disagreement vs. silent-tier-fallback) and must remain separate, separately-named
  scenario files.
- A denylist scenario (FC-09) that tests only ONE denylisted key instead of enumerating
  representative coverage of all six categories (source_control.remote, source_control
  .base_branch, notifications.webhook_url, issue_tracker.instance, issue_tracker.project,
  pr_rules.*).
- An FC-19 scenario that only checks for the presence of `config.local.toml` in the ignore
  guidance without also asserting the ABSENCE of a bare `.agent-flow/` whole-dir ignore line and
  the absence of `config.toml` as an ignored entry.
- Marking a criterion "cannot test pre-implementation" and skipping it outright — formal-criteria.md
  provides a "Pre-impl:" spec-conformance form for nearly every behavioural criterion; use it.
- Writing a scenario whose assertion would ALSO pass against the OLD inline-CLAUDE.md system
  (i.e., an assertion so loose it doesn't actually pin the TOML-only spec) — every new scenario
  must be falsifiable against the current (pre-migration) repo state, i.e. it MUST currently fail
  red for the right reason (missing config.toml / stale reader), not skip/error for an unrelated
  reason (e.g. missing fixture file causing a bash syntax error rather than an assertion failure).
