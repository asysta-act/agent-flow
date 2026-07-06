# Formal Acceptance Criteria — Automation Config → `.agent-flow/config.toml`

> Run `forge-2026-07-04-001` · Phase 4. Each criterion is **machine-checkable** by a plain-bash
> `tests/scenarios/*.sh` harness scenario using only bash builtins and git — no external tooling
> (`tomllib`/`tomli`/`taplo`/`python3` NOT required), runnable under `HARNESS_JOBS=1` sequential.
> Assertions MUST use the SIGPIPE-safe helpers in `tests/lib/assert.sh`
> (`contains` / `contains_i` / `matches_re`) — **never** `echo $VAR | grep -q`. Each criterion
> maps back to a requirement id from `requirements.md`.

Legend: **[DEDICATED]** = one of the seven mandatory top-risk criteria called out in the Phase-4
prompt.

---

**FC-01 — config.toml is the config source.** *(REQ-01, REQ-06)*
`core/config-reader.md` references `.agent-flow/config.toml` as the input it parses.
Check: `contains "$(cat core/config-reader.md)" ".agent-flow/config.toml"` is true, AND the
file's Input Contract no longer names `claude_md_content` / "CLAUDE.md" as the config source.

**FC-02 — [DEDICATED] HARD-CUT REMOVAL: no CLAUDE.md parse-into-config path.** *(REQ-16)*
No config-consuming file contains a code path that **parses** Automation Config from `CLAUDE.md`
**into the config object** (inline parse, fallback, dual-read, deprecation shim). This targets
the *parse-into-config* path only — a read that merely **detects** a legacy inline block to emit
a migrate hint (REQ-11(d) / FC-17) is explicitly carved out and NOT a violation, so FC-02 and
FC-17 are jointly satisfiable.
Check: grep the config surface — `core/config-reader.md`, `skills/*/steps/*.md`,
`skills/setup-agents/lib/*.sh`, `skills/*/SKILL.md`, and `agents/*.md` **excluding
`skills/check-setup/SKILL.md`** (whose detect-and-warn read is permitted) — for the
removal-signature patterns and assert **zero** matches: `matches_re "$contents"
'parse.*Automation Config.*table'` no match; `matches_re "$contents" 'fall ?back.*CLAUDE\.md'`
no match; `contains "$contents" "claude_md_content"` false; `config-reader.md` contains no
`overlay_source=md` and no dual-read branch. Because `agents/*.md` is now in scope, also assert
the agent-body config-read-from-CLAUDE.md signature is absent: `matches_re "$contents"
'Automation Config from .*CLAUDE\.md'` no match AND `matches_re "$contents"
'[Rr]ead.*from.*CLAUDE\.md.*Automation Config'` no match — these catch a terminal agent (e.g.
`agents/publisher.md`, `agents/test-engineer.md`) that reads its config out of `CLAUDE.md`
instead of `.agent-flow/config.toml`, the exact gap the original FC-02 grep surface could not see.
They do NOT fire on a legitimate coding-conventions read (`read CLAUDE.md and any
customization/{agent}.toml overlay`) nor on scaffolder's pointer-writing prose. For
`skills/check-setup/SKILL.md`, the only
permitted CLAUDE.md read is the legacy-block **detection** that pairs with a `/onboard --migrate`
hint (FC-17) — assert it does NOT map those tables into a config object
(`matches_re` for `parse.*Automation Config.*table` still no match there). FAIL if any surviving
parse-into-config / fallback / dual-read path is found.

**FC-03 — CLAUDE.md `## Automation Config` is pointer-only.** *(REQ-02)*
In `tests/mock-project/CLAUDE.md` (the fixture), the `## Automation Config` section contains a
pointer to `.agent-flow/config.toml` and **no** `| Key | Value |` table rows.
Check: extract the section with `awk` (heading → next `## `), then assert
`contains "$section" ".agent-flow/config.toml"` AND `matches_re "$section" '^\| .* \| .* \|'`
is **false** (no table rows).

**FC-04 — Pure-bash parser: no external tooling in the config-read OR limits-resolution path.** *(REQ-03, REQ-29)*
Neither the config-reader parsing path nor the limits-resolution path invokes `tomllib` /
`tomli` / `taplo` / `python3` for reading `config.toml`, `config.local.toml`, or
`customization/{agent}.toml [limits]`.
Check: `contains "$(cat core/config-reader.md)" "tomllib"` is **false**; same for `taplo` and
for a hard `python3` requirement in the config-read path. `contains_i "$(cat core/config-reader.md)" "pure-bash"` (or an equivalent bare-`[section]`/scalar parse spec) is true. Additionally the
limits-resolution path (the file(s) that read the `[limits]` tier — per design §3.2/§1.4,
`core/config-reader.md`, not `skills/setup-agents/lib/toml-merge.sh`) contains no `tomllib` /
`tomli` / `python3` dependency. (Dedicated behavioural guard: FC-26.)

**FC-05 — [DEDICATED] TOML parser: malformed optional input ⇒ WARN + default, never crash.** *(REQ-13)*
Given a `config.toml` with a valid required set plus a **malformed optional** section (e.g.
unterminated `"""`, or a garbage scalar in `[metrics]`), the parser exits 0, emits a `[WARN]`
naming the section, and applies that section's default.
Check (behavioural, once a parse helper exists) OR (spec-conformance, pre-impl): the reader spec
states optional-malformed ⇒ `[WARN]` + default + no-crash. Assert
`contains "$out" "[WARN]"` AND the exit code is `0` AND the defaulted value is present.
Distinguish from FC-21 (required-section absence ⇒ FAIL).

**FC-06 — 23 `[section]`s: 5 required + 18 optional.** *(REQ-01, REQ-04)*
The reworked `counts-invariants.sh` asserts the config surface documents exactly 23 sections
(5 required + 18 optional) mapped to `[section]`s.
Check: count required-section table rows == 5 and optional-section rows == 18 in
`docs/reference/automation-config.md` (retargeted), and the sum == 23. Uses `grep -c` on the
section tables via a SIGPIPE-safe capture, then integer comparison.

**FC-07 — Required sections present.** *(REQ-04, REQ-20)*
The migration map covers each of `Issue Tracker`, `Source Control`, `PR Rules`,
`PR Description Template`, `Build & Test`.
Check: for each name, `contains "$(cat design.md)" "$name"` AND the mock `config.toml` fixture
contains the corresponding `[section]` header (`[issue_tracker]`, `[source_control]`,
`[pr_rules]`, `[pr_description_template]`, `[build_and_test]`).

**FC-08 — Multi-line PR Description Template via `"""`.** *(REQ-23)*
The mock `config.toml` stores the PR Description Template as a TOML `"""` multi-line string under
`[pr_description_template]`.
Check: `contains "$(cat tests/mock-project/.agent-flow/config.toml)" '"""'` is true and appears
under the `[pr_description_template]` table.

**FC-09 — [DEDICATED] DENYLIST: denylisted key in config.local.toml is ignored + WARNed.** *(REQ-14)*
For each denylisted key placed in a test `config.local.toml` — `source_control.remote`,
`source_control.base_branch`, `notifications.webhook_url`, `issue_tracker.instance`,
`issue_tracker.project`, and any `[pr_rules]` key — the resolved config retains the
`config.toml` value (override NOT applied) and a `[WARN]` naming the key is emitted.
Check (behavioural): resolve config with a config.local.toml that sets each denylisted key to a
sentinel; assert `contains "$resolved" "<config.toml value>"` AND
`contains "$resolved" "<sentinel>"` is **false**, AND `contains "$warns" "$key"` is true — per
key. Pre-impl form: assert `design.md` §2.3 enumerates all six denylist entries (not a vague
"sensitive keys" phrase): `contains "$(cat design.md)" "source_control.remote"`, `…base_branch`,
`notifications.webhook_url`, `issue_tracker.instance`, `issue_tracker.project`, and an "all of
PR Rules" clause.

**FC-10 — Allowlist: Browser Verification / Local Deployment overrides apply.** *(REQ-07)*
A `config.local.toml` overriding a `[browser_verification]` or `[local_deployment]` key changes
the resolved value.
Check (behavioural): set `browser.base_url` in config.local.toml to a sentinel; assert
`contains "$resolved" "$sentinel"` is true. Pre-impl: `design.md` §2.2 names exactly these two
allowlist sections.

**FC-11 — Non-allowlisted overlay key ignored + WARNed.** *(REQ-17)*
A `config.local.toml` key outside the general full-section overlay allowlist — using a
non-limit section key such as `[metrics]` `output` — is not applied and emits a `[WARN]`. (A
non-limit key is chosen deliberately: `[retry_limits]` keys are governed by the SEPARATE
limits-resolution chain, which intentionally lets `config.local.toml` contribute limit values, so
using a limit key here would contradict FC-14. See `core/config-reader.md` §overlay scope note.)
Check (behavioural): override `metrics.output` in config.local.toml; assert resolved
value == config.toml value AND `contains "$warns" "metrics.output"`.

**FC-12 — Absent overlay is a no-op.** *(REQ-21)*
With no `config.local.toml`, resolved config equals `config.toml` over plugin defaults.
Check (behavioural): resolve with and without an (empty/absent) overlay; assert the two resolved
objects are byte-identical.

**FC-13 — [DEDICATED] SINGLE-RESOLUTION: one limits value feeds BOTH channels (§2.4 guard).** *(REQ-08, REQ-15, REQ-22)*
For a limit set in `config.toml` and overridden in `customization/{agent}.toml [limits]`, the
value the orchestrator **enforces** in the loop equals the value **injected** into the agent
prompt.
Check (behavioural): construct config.toml `build_retries = 3` and `customization/fixer.toml`
`[limits] max_build_retries = 2`; resolve; assert `enforced == injected == 2` (top of chain
wins). Pre-impl: assert `design.md` §3.2 states one resolution function feeds both loop
enforcement and prompt injection, AND names the two superseded sites
`docs/guides/toml-overlay-syntax.md:150-157` and `core/agent-override-injector.md:102-105`:
`contains "$(cat design.md)" "toml-overlay-syntax.md:150-157"` AND
`contains "$(cat design.md)" "agent-override-injector.md:102-105"`.

**FC-14 — Limits precedence chain honoured.** *(REQ-08, REQ-15)*
Resolution order is `plugin default < config.toml < config.local.toml < customization/{agent}.toml [limits]`.
Check: assert the chain appears in the spec. Because `requirements.md` REQ-08 renders it
single-spaced while `design.md` §3.2 renders it inside a code block with padded spaces
(`  <  `), the check targets the single-spaced form in `requirements.md`:
`contains "$(cat requirements.md)" "plugin default < config.toml < config.local.toml < customization/{agent}.toml [limits]"` is true. (Whitespace-tolerant alternative, if checking
`design.md`: `matches_re "$(cat design.md)" 'plugin default[[:space:]]+<[[:space:]]+config\.toml[[:space:]]+<[[:space:]]+config\.local\.toml[[:space:]]+<[[:space:]]+customization/\{agent\}\.toml \[limits\]'`.) Plus: the behavioural resolution matches for a layered fixture.

**FC-15 — [DEDICATED] `/check-setup` gitignore detection via `git check-ignore` (both paths).** *(REQ-11, REQ-19)*
`check-setup` FAILs when `.agent-flow/config.toml` is gitignored and passes when it is tracked.
Check (behavioural, in a temp git repo): (a) add `.agent-flow/config.toml` to `.gitignore`;
assert `git check-ignore .agent-flow/config.toml` exits 0 and check-setup reports `[FAIL]`.
(b) remove the ignore; assert `git check-ignore` exits 1 (not ignored) and check-setup reports
`[OK]`. Pre-impl: `contains "$(cat skills/check-setup/SKILL.md)" "git check-ignore"`.

**FC-16 — `/check-setup` key-list: unknown ⇒ WARN, missing required ⇒ FAIL.** *(REQ-11)*
Check (behavioural): a `config.toml` with an unknown key yields `[WARN]` (exit 0-equivalent for
that check); a `config.toml` missing a required section yields `[FAIL]`.
Assert `contains "$out_unknown" "[WARN]"` and `contains "$out_missing" "[FAIL]"`.

**FC-17 — `/check-setup` hints `/onboard --migrate` on legacy inline config.** *(REQ-11)*
When a legacy `## Automation Config` table block is present in CLAUDE.md, check-setup outputs a
hint to run `/onboard --migrate`.
Check: `contains "$(cat skills/check-setup/SKILL.md)" "/onboard --migrate"` is true.

**FC-18 — [DEDICATED] No `/migrate-config` command.** *(REQ-18)*
No `/migrate-config` (or `/agent-flow:migrate-config`) command exists anywhere.
Check: there is no `skills/migrate-config/` directory, AND
`matches_re "$(cat skills/check-setup/SKILL.md)" '/(agent-flow:)?migrate-config'` is **false**,
AND the same holds for `skills/setup-agents/lib/toml-merge.sh` (existing scenarios
`check-setup-no-migrate-config.sh` + `toml-merge-no-md-fallback.sh` stay green).

**FC-19 — [DEDICATED] Whole-dir `.agent-flow/` ignore forbidden; config.toml tracked via per-file ignore.** *(REQ-19)*
`docs/guides/installation.md` gitignore guidance uses **per-file** entries and does NOT ignore
the whole `.agent-flow/` directory; it adds `config.local.toml` and never lists `config.toml`.
Check: in the installation.md gitignore block, `matches_re "$block" '^\.agent-flow/$'` is
**false** (no bare trailing-slash whole-dir ignore); `contains "$block" "config.local.toml"` is
true; `contains "$block" "config.toml"` (as an ignored entry) is **false**. Behavioural: in a
temp repo seeded with the guidance, `git check-ignore .agent-flow/config.toml` exits 1 (tracked).

**FC-20 — `/onboard --migrate` extracts inline → config.toml + rewrites CLAUDE.md to pointer.** *(REQ-09)*
Check: `contains "$(cat skills/onboard/SKILL.md)" "--migrate"` is true; the skill spec states it
writes `.agent-flow/config.toml` and rewrites `## Automation Config` to a pointer. Behavioural:
run the migrate transform on a fixture CLAUDE.md; assert a `config.toml` is produced with the
mapped `[section]`s AND the fixture's `## Automation Config` section afterward contains the
pointer and no table rows.

**FC-21 — Required-section absence still FAILs (degradation is optional-only).** *(REQ-20)*
A `config.toml` missing a required section causes the reader to BLOCK/FAIL (not silently
default).
Check (behavioural): parse a config.toml lacking `[issue_tracker]`; assert non-zero/BLOCK and
`contains "$out" "[agent-flow]"` block template. Complements FC-05.

**FC-22 — `/scaffold` emits config.toml, not inline tables.** *(REQ-10)*
Check: `contains "$(cat skills/scaffold/steps/03-scaffold.md)" ".agent-flow/config.toml"` (or
the scaffold step that writes config) is true, AND the scaffold no longer emits a
`## Automation Config` table block into the generated CLAUDE.md (assert the generated-CLAUDE.md
template contains a pointer, no `| Key | Value |` rows).

**FC-23 — Doc-count-drift sync set updated together.** *(REQ-24)*
All five docs reference the new config location.
Check: for each of `CLAUDE.md`, `README.md`, `docs/reference/automation-config.md`,
`docs/guides/installation.md`, `docs/architecture.md`,
`contains "$(cat $f)" ".agent-flow/config.toml"` is true.

**FC-24 — Fixtures migrated to TOML.** *(REQ-25)*
`tests/mock-project/.agent-flow/config.toml` exists (`[ -f ]`), and
`tests/harness/fixtures/automation-config.md` is either replaced by a `.toml` form or contains
TOML `[section]` content rather than `| Key | Value |` tables.
Check: file existence + `contains`/absence-of-table-rows assertions.

**FC-25 — Version-neutral source PR.** *(REQ-27)*
The source change does not edit release-bump files.
Check (in CI/harness against the diff): the changeset touches none of
`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`.
`matches_re "$(git diff --name-only <base>..HEAD)" 'plugin\.json|marketplace\.json|CHANGELOG\.md'`
is **false**.

**FC-26 — [DEDICATED] Pure-bash limits-resolution path (works on Python 3.10; no `tomllib`).** *(REQ-29, REQ-08)*
The limits single-resolution path — including the `customization/{agent}.toml [limits]` read —
has no `python3` / `tomllib` / `tomli` dependency and does NOT route the `[limits]` read through
`skills/setup-agents/lib/toml-merge.sh`.
Check (grep): the file(s) implementing limits resolution (per design §3.2/§1.4 this is
`core/config-reader.md`, not `toml-merge.sh`) contain no `tomllib` / `tomli` / `python3` on the
limits path; `contains "$(cat core/config-reader.md)" "tomllib"` is **false**; and
`core/config-reader.md` states the `[limits]` tier is read by the pure-bash parser
(`contains_i` for "pure-bash" + "[limits]"). Check (behavioural, §2.4 host-regression guard):
with `customization/fixer.toml [limits] max_build_retries = 2` over `config.toml build_retries =
3`, run the resolution in an environment where `import tomllib` is unavailable (simulating 3.10);
assert the resolved+injected value is `2` (top tier applied) — i.e. the value does NOT silently
fall back to `3`/empty. Complements FC-13 (which asserts enforce==inject); FC-26 asserts the top
tier actually applies on the real host.

**FC-27 — List/map keys round-trip via delimited-scalar encoding.** *(REQ-04)*
List/map-valued keys survive the TOML round-trip using the §1.1a delimited-scalar encoding.
Check: `design.md` §1.1a documents the encoding — `contains "$(cat design.md)"
"state_transitions"` and `contains "$(cat design.md)" "delimited"` are true. Behavioural: a
`config.toml` with `labels = "bug, automated"` and `state_transitions = "triage: In Progress;
fixed: Fixed"` resolves to a 2-element `pr_rules.labels` list and a 2-entry
`issue_tracker.state_transitions` map (assert both elements/pairs present via `contains` on the
resolved object). Empty string ⇒ empty list/map; no-delimiter value ⇒ single-element list.

**FC-28 — check-setup WARNs if config.local.toml is present but NOT gitignored.** *(REQ-11)*
Accidental-commit guard, complementary to FC-15.
Check: `contains "$(cat skills/check-setup/SKILL.md)" "config.local.toml"` is true AND the
skill spec pairs it with a `git check-ignore` + `[WARN]`. Behavioural (temp git repo): with a
tracked (non-ignored) `.agent-flow/config.local.toml`, `git check-ignore` exits 1 and check-setup
emits `[WARN]`; with it gitignored, no such WARN.

---

## Coverage summary

- **Total criteria: 28** (≥ 15 required). ✔
- **Seven mandatory [DEDICATED] criteria present:** FC-02 (hard-cut removal), FC-05 (TOML
  malformed → WARN+default, never crash), FC-09 (denylist ignored+warned), FC-13 (limits
  single-resolution / §2.4 guard), FC-15 (check-setup `git check-ignore` both paths), FC-18
  (`/migrate-config` absent), FC-19 (whole-dir `.agent-flow/` ignore forbidden; config.toml
  tracked via per-file ignore). ✔
- **PLUS the new pure-bash-limits dedicated criterion (revision M1b):** FC-26 (limits-resolution
  path is pure-bash, no `tomllib`, top tier actually applies on the Python 3.10 host — the §2.4
  host-regression guard). ✔
- **Every criterion maps to ≥1 REQ id** and is assertable with pure bash + `git` under
  `HARNESS_JOBS=1` using the SIGPIPE-safe `assert.sh` helpers. ✔

### Criterion → requirement map

| FC | REQ(s) | FC | REQ(s) |
|----|--------|----|--------|
| FC-01 | REQ-01, REQ-06 | FC-15 | REQ-11, REQ-19 |
| FC-02 | REQ-16 | FC-16 | REQ-11 |
| FC-03 | REQ-02 | FC-17 | REQ-11 |
| FC-04 | REQ-03, REQ-29 | FC-18 | REQ-18 |
| FC-05 | REQ-13 | FC-19 | REQ-19 |
| FC-06 | REQ-01, REQ-04 | FC-20 | REQ-09 |
| FC-07 | REQ-04, REQ-20 | FC-21 | REQ-20 |
| FC-08 | REQ-23 | FC-22 | REQ-10 |
| FC-09 | REQ-14 | FC-23 | REQ-24 |
| FC-10 | REQ-07 | FC-24 | REQ-25 |
| FC-11 | REQ-17 | FC-25 | REQ-27 |
| FC-12 | REQ-21 | FC-26 | REQ-29, REQ-08 |
| FC-13 | REQ-08, REQ-15, REQ-22 | FC-27 | REQ-04 |
| FC-14 | REQ-08, REQ-15 | FC-28 | REQ-11 |
