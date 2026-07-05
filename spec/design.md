# Design — Automation Config → `.agent-flow/config.toml` Hard-Cut Migration

> Run `forge-2026-07-04-001` · Phase 4 (Specification). Architecture for the requirements in
> `requirements.md`. Every design element is pure-bash-implementable, needs no external tooling,
> and is checkable by a plain-bash `tests/scenarios/*.sh` harness under `HARNESS_JOBS=1`.

## 0. Overview

Today `core/config-reader.md` locates `## Automation Config` in the consumer's `CLAUDE.md` and
walks each `### {Section}` Markdown table into a dot-notation config object. Because subagents
auto-load `CLAUDE.md` unfilterably, those raw tables leak into every agent context alongside the
orchestrator's resolved values — a dual source of truth (research §2.1). The fix is relocation +
a hard cut: config moves to committed `.agent-flow/config.toml` (TOML), an optional gitignored
`.agent-flow/config.local.toml` layers per-developer overrides on top, `CLAUDE.md` keeps a
pointer only, and the inline Markdown-table parser is **removed**.

Four subsystems change:

1. **Parser** — `core/config-reader.md` becomes a pure-bash TOML reader (§1).
2. **Merge/denylist engine** — the `config.local.toml` overlay (§2).
3. **Single limits-resolution point** — one resolved value for both channels, fixing §2.4 (§3).
4. **Tooling & docs** — `/onboard --migrate`, `/scaffold`, `/check-setup`, the doc-count sync
   set, and the scenario rework (§4–§6).

---

## 1. Pure-bash TOML parser subset

### 1.1 Grammar (the only TOML the plugin accepts)

The parser recognises a deliberately small TOML subset — enough for the 23 sections and no more:

| Construct | Form | Maps to |
|---|---|---|
| Section header | `[section]` on its own line, bare snake_case name | opens a namespace |
| Array-of-tables | `[[pipeline_profiles]]` (only for Pipeline Profiles) | appends a profile record |
| String scalar | `key = "value"` | `section.key = value` |
| Integer scalar | `key = 60` | numeric |
| Boolean scalar | `key = true` / `false` | boolean |
| Multi-line string | `key = """` … lines … `"""` | verbatim block (PR Description Template) |
| Comment | `# …` to end of line (and whole-line `#`) | ignored |
| Blank line | — | ignored |

Explicitly **out of subset** (rejected/ignored with a WARN, never crashing): inline tables
`{ }`, native TOML arrays `[ a, b ]` other than the `[[…]]` array-of-tables form, dotted keys
`a.b.c = x`, datetime literals, and hex/octal/float numerics. The config surface needs none of
these; keeping them out keeps the pure-bash parser small and predictable.

### 1.1a Delimited-scalar encoding for list/map values (REQ-04 losslessness)

Several config keys are list- or map-valued, which a scalar-only subset cannot express as a
native TOML array/table. Rather than widen the parser (and its footgun surface), the migration
encodes every such value as a **single-line delimited scalar string** that the reader splits
downstream into the exact list/map structure `core/config-reader.md` exposes today. This keeps
parsing pure-bash while satisfying REQ-04 losslessness:

| Config key | Kind | Encoding | Split rule |
|---|---|---|---|
| `pr_rules.labels` | list | `labels = "bug, automated"` | split on `,`, trim each |
| `notifications.on_events` | list | `on_events = "pr-created, issue-blocked"` | split on `,`, trim |
| `browser.on_events` | list | `on_events = "verify, reproduce"` | split on `,`, trim |
| `local_deployment.ports` | list | `ports = "3000, 5432"` | split on `,`, trim |
| `issue_tracker.state_transitions` | map | `state_transitions = "triage: In Progress; fixed: Fixed"` | split on `;` → each on the first `:` → `{key: value}`, trim |
| `[[pipeline_profiles]]` `skip_stages` / `extra_stages` | list | `skip_stages = "triage, browser-agent-verify"` | split on `,`, trim |

Rules: the delimiters are `,` for lists and `;` (records) + `:` (key/value) for maps; surrounding
whitespace is trimmed; an empty string yields an empty list/map; a no-delimiter value (a value with
no delimiter) yields a single-element list. Because the stored form is a plain quoted scalar, the pure-bash parser
reads it with no array/table grammar, and the reader performs the split when materialising the
config object. The `/onboard --migrate` extractor (§4.3) emits these encoded forms from the
inline Markdown tables, and `/scaffold` (§6) emits them directly — guaranteeing round-trip.

### 1.2 Parse algorithm (pure bash — no `python3`, no `tomllib`, no `taplo`)

Line-oriented state machine over the file, using only bash builtins and `case`/parameter
expansion (SIGPIPE-safe; no `echo $x | grep`):

1. Read the file line by line (`while IFS= read -r line`). Strip a trailing `\r` (MSYS2/CRLF
   discipline) via `${line%$'\r'}`.
2. If inside a `"""` block, accumulate the raw line into the current key until a line whose
   trimmed content is the closing `"""`; then store the joined block verbatim.
3. Else strip a trailing `# …` comment *only when the `#` is outside a quoted string*; trim
   surrounding whitespace.
4. Blank line ⇒ continue.
5. `[[name]]` ⇒ start a new array-of-tables record under `name`.
6. `[name]` ⇒ set current section = `name` (record header seen, for required-presence checks).
7. `key = value` ⇒ classify `value`: opens `"""` ⇒ enter multi-line mode; `"..."` ⇒ string
   (strip quotes); `true`/`false` ⇒ bool; all-digits (optional leading `-`) ⇒ int; anything
   else ⇒ treat as bare string with a WARN. Emit `section.key=value` into the config object
   (associative array or `KEY=VALUE` line stream keyed by dot-notation).
8. After EOF: apply defaults for every unset optional key; verify required sections present
   (REQ-20).

The output contract is identical to today's reader: a dot-notation config object
(`issue_tracker.type`, `retry.fixer_iterations`, …) so downstream skills need no change to how
they *read* config — only *where* it comes from.

### 1.3 Malformed-input degradation (REQ-13 / REQ-20)

Matches config-reader's existing "never block on an optional section" contract:

- **Optional section malformed** (bad scalar, unterminated `"""`, junk header): emit
  `[WARN] <section>: <reason>; using default`, apply the documented default, keep going. Never
  crash, never abort. The parser's exit code stays 0 for optional-only faults.
- **Required section absent/empty**: BLOCK/FAIL with the standard block template (REQ-20) — the
  degradation path is optional-only.
- The parser is written so any single unparsable line degrades to a WARN for that key rather
  than throwing (defensive `case` fall-through), guaranteeing "never crash on malformed input".

### 1.4 Relationship to the existing `customization/*.toml` parser (REQ-29)

`skills/setup-agents/lib/toml-merge.sh` parses overlay TOML via `python3` + `import tomllib`
(Python 3.11+ stdlib), falling back to the third-party `tomli`. **The failure mode is precise:
`python3` *is present* on the host (3.10), but `import tomllib` *fails* (stdlib module added in
3.11) and `tomli` is absent — so `parse_toml_overlay` exits 1.** Under `set -euo pipefail`,
`resolve_overlay` then returns non-zero, and `core/agent-override-injector.md` Step 1's guarded
assignment (`… || additional_instructions=""`, injector lines 43-49) silently absorbs it to an
**empty overlay**. Net today: the top-precedence customization `[limits]` tier silently never
applies on the real 3.10 host — which would leave the §2.4 two-channel divergence in place.

Therefore this migration routes the limits read **off** `toml-merge.sh`:

1. **The limits-resolution path (§3) uses the pure-bash parser of §1.2** to read the
   `customization/{agent}.toml [limits]` tier — the same parser that reads `config.toml` /
   `config.local.toml`. It has **no** `python3` / `tomllib` / `tomli` dependency and works on
   3.10 (REQ-29).
2. **`toml-merge.sh` is NOT modified** — its `NEVER modify lib/toml-merge.sh` status
   (`core/agent-override-injector.md:36`) is preserved. It remains the parser for the *non-limits*
   overlay tiers (`model`, `style`, `[[process_additions]]`, `[[constraints]]`). Only the
   `[limits]` tier is migrated onto the pure-bash reader.
3. **The injector's `### Limits` render (lines 102-105) consumes the pure-bash single-resolved
   value** (§3.2), overriding whatever `[limits]` `toml-merge.sh` would otherwise have produced.
   Because that value is computed by the pure-bash path, the top precedence tier actually applies
   regardless of `tomllib` availability.

No config-reading path (config.toml, config.local.toml, or the `[limits]` tier) may hard-fail on
a missing `tomllib`/`tomli`. *(The broader fact that `toml-merge.sh` also silently drops the
non-limits overlay tiers on 3.10 is a pre-existing adjacent defect; this migration's declared
scope fixes it only for the limits tier — the correctness-critical §2.4 channel. TDD/PLAN may
elect to widen the pure-bash reader to the other tiers, but that is not required by these
requirements.)*

---

## 2. `config.local.toml` deep-merge / denylist engine

### 2.1 Merge semantics (REQ-07, REQ-21)

`config.local.toml` is optional and gitignored. When present it is applied as a **per-key deep
merge** on top of `config.toml`: for each key the overlay provides, the overlay value wins; keys
the overlay omits are inherited from `config.toml` unchanged. Absent overlay ⇒ resolved config
== `config.toml` over plugin defaults (no-op).

### 2.2 Allowlist gate (REQ-07, REQ-17)

The merge is **allowlist-driven**. Only keys belonging to these two sections are eligible to be
overridden by `config.local.toml`:

| Allowlisted section | TOML table | Rationale (per closed PR #11 per-dev semantics) |
|---|---|---|
| Browser Verification | `[browser_verification]` | per-dev base URL, ports, screenshot path |
| Local Deployment | `[local_deployment]` | per-dev ports, start/stop commands, health URL |

Any `config.local.toml` key **outside** these two sections is ignored (value never applied) and
a `[WARN]` is emitted (REQ-17). This is the general rule; the denylist below is the enumerated,
must-test subset of it.

### 2.3 Denylist — explicit, enumerated (REQ-14)

These keys are team-consistency / security critical. If present in `config.local.toml` they MUST
be ignored (never applied) and warned — a personal override here would silently diverge the team
or leak a personal secret:

| Denylisted key | Config path | Why protected |
|---|---|---|
| Source Control → Remote | `source_control.remote` | team must target one repo |
| Source Control → Base branch | `source_control.base_branch` | team must share the base branch |
| Notifications → Webhook URL | `notifications.webhook_url` | prevents personal-URL leakage / SSRF surface |
| Issue Tracker → Instance | `issue_tracker.instance` | team must query one tracker |
| Issue Tracker → Project | `issue_tracker.project` | team must query one project |
| PR Rules → **all keys** | `[pr_rules]` (labels, title_format, …) | PR contract is team-uniform |

Engine behaviour: a single function evaluates each incoming `config.local.toml` key against
`(is-allowlisted? AND NOT-denylisted?)`. Only keys passing both are merged; every rejected key
emits exactly one `[WARN] config.local.toml: '<key>' is not overridable (…); ignored`. The
denylist is enumerated in code/data (not a vague "sensitive keys" match) so a scenario can assert
each entry individually.

### 2.4 Provenance

Each applied override and each rejection is logged (WARN for rejections; INFO for applied
overrides) to `.agent-flow/pipeline.log`, consistent with existing `log_overlay_provenance`
behaviour, so `check-setup`/audits can see what the local overlay changed.

---

## 3. The SINGLE limits-resolution point (fixes §2.4)

### 3.1 The bug being fixed

Today the customization `[limits]` overlay merges against the **plugin default**, not the
config-resolved value (`docs/guides/toml-overlay-syntax.md:150-157`, the Tier-3 `[limits]`
key-by-key merge wording; the injector renders the overlay verbatim at
`core/agent-override-injector.md:102-105`). Result: a project can set
`Build retries = 3` in config while `customization/fixer.toml` says `2`, and **both** land in
the effective prompt with no reconciliation — the orchestrator enforces one number while the
agent's injected prompt text states another. Two channels, two values.

### 3.2 The fix — resolve once, feed both channels (REQ-08, REQ-15, REQ-22)

Introduce **one** resolution function the orchestrator calls before dispatch. It computes each
limit exactly once through this precedence chain (lowest → highest):

```
plugin default  <  config.toml  <  config.local.toml  <  customization/{agent}.toml [limits]
```

This resolution function is **pure bash** (REQ-29): it reads all four tiers — including the
top `customization/{agent}.toml [limits]` tier — via the §1.2 parser, with **no** `python3` /
`tomllib` / `tomli` dependency, so it computes the correct value on the 3.10 host. It does **not**
route the `[limits]` read through `skills/setup-agents/lib/toml-merge.sh` (see §1.4 for why that
path silently drops on 3.10 and how `toml-merge.sh`'s NEVER-modify status is preserved).

The single resolved value is then used for **both**:

- **loop enforcement** — the orchestrator's retry/iteration guards (fixer↔reviewer, test
  attempts, build retries, spec iterations, root-cause iterations); and
- **prompt injection** — the value rendered into the agent prompt by
  `core/agent-override-injector.md` (`### Limits` block, lines 102-105).

Both channels read the **same** resolved value; neither recomputes independently. This is the
named supersession of the two §2.4 sites — the design MUST update both
`docs/guides/toml-overlay-syntax.md:150-157` (Tier-3 `[limits]` merge now merges against the
config-resolved value, not the raw plugin default) and
`core/agent-override-injector.md:102-105` (the `### Limits` render consumes the single resolved,
pure-bash value).

### 3.3 Invariant

For any limit `L`, agent `A`, and project state: `enforced(L,A) == injected(L,A)`. This equality
is the §2.4 regression guard and gets its own dedicated acceptance criterion (FC in
`formal-criteria.md`).

---

## 4. The 23-section → `[section]` migration map

Convention: **TOML table** = snake_case of the section title; **resolved dot-namespace** = the
exact namespace `core/config-reader.md` exposes today (so downstream reads are unchanged, REQ-04).
The only table whose name differs from its resolved namespace is `PR Description Template`
(stored under `[pr_description_template]`, resolved into `pr_rules.description_template`).

### 4.1 Required sections (5)

| # | Section title | TOML table | Resolved keys (dot-namespace) |
|---|---|---|---|
| 1 | Issue Tracker | `[issue_tracker]` | `issue_tracker.type` (default `youtrack`), `.instance`, `.project`, `.bug_query`, `.state_transitions` (map), `.on_start_set` |
| 2 | Source Control | `[source_control]` | `source_control.remote`, `.base_branch`, `.branch_naming` |
| 3 | PR Rules | `[pr_rules]` | `pr_rules.labels`, `pr_rules.title_format` (optional) |
| 4 | PR Description Template | `[pr_description_template]` (key `template = """…"""`) | `pr_rules.description_template` |
| 5 | Build & Test | `[build_and_test]` | `build.build_command`, `build.test_command`, `build.verify_command` (optional) |

### 4.2 Optional sections (18)

| # | Section title | TOML table | Resolved keys (dot-namespace) |
|---|---|---|---|
| 6 | Retry Limits | `[retry_limits]` | `retry.fixer_iterations` (5), `.test_attempts` (3), `.build_retries` (3), `.spec_iterations` (5), `.root_cause_iterations` (3) |
| 7 | Module Docs | `[module_docs]` | `module_docs.path` (none) |
| 8 | Hooks | `[hooks]` | `hooks.pre_fix`, `.post_fix`, `.pre_publish`, `.post_publish` (none) |
| 9 | Custom Agents | `[custom_agents]` | `custom_agents.post_fix_agent`, `.pre_publish_agent` (none) |
| 10 | Notifications | `[notifications]` | `notifications.webhook_url`, `notifications.on_events` (none) |
| 11 | Worktrees | `[worktrees]` | `worktrees.batch_size`, `.base_path`, `.cleanup` (none) |
| 12 | E2E Test | `[e2e_test]` | `e2e.framework`, `e2e.command` (none) |
| 13 | Browser Verification | `[browser_verification]` | `browser.base_url`, `.start_command`, `.stop_command`, `.on_events`, `.timeout` (60), `.max_pages` (5), `.screenshot_storage`, `.exploration` (disabled), `.exploration_max_clicks` (20) |
| 14 | Error Handling | `[error_handling]` | `error_handling.on_block` (comment), `.max_blocked_per_run` (unlimited) |
| 15 | Feature Workflow | `[feature_workflow]` | `feature.query`, `feature.on_start_set` (none) |
| 16 | Decomposition | `[decomposition]` | `decomposition.max_subtasks` (7), `.fail_strategy` (fail-fast), `.commit_strategy` (squash), `.create_tracker_subtasks` (enabled) |
| 17 | Pipeline Profiles | `[[pipeline_profiles]]` (array-of-tables) | `profiles[] = {name, skip_stages, extra_stages}` (none) |
| 18 | Metrics | `[metrics]` | `metrics.output` (stdout), `metrics.period` (30 days) |
| 19 | Agent Overrides | `[agent_overrides]` | `agent_overrides.path` (`customization/`) |
| 20 | Local Deployment | `[local_deployment]` | `local_deployment.type`, `.start_command`, `.stop_command`, `.health_check_url`, `.health_check_timeout` (60), `.ports` |
| 21 | Sprint Planning | `[sprint_planning]` | `sprint_planning.sprint_duration` (2 weeks), `.capacity_unit` (story-points), `.team_capacity`, `.velocity_target`, `.sprint_field`, `.mode` (suggest), `.max_issues` (20), `.epic_template` |
| 22 | Autopilot | `[autopilot]` | `autopilot.max_issues_per_run` (1), `.lock_timeout` (120), `.log_file` (`.agent-flow/autopilot.log`), `.bug_limit` (0), `.feature_limit` (0), `.on_error` (skip), `.dry_run` (false) |
| 23 | Pause Limits | `[pause_limits]` | `pause_limits.pause_timeout` (30 days) |

Total: **5 required + 18 optional = 23** `[section]`s. `Autopilot`'s `Bug query` /
`Feature query` are NOT keys here — they resolve from `[issue_tracker]` and `[feature_workflow]`
respectively (unchanged semantics).

### 4.3 `/onboard --migrate` extraction (REQ-09)

One-time transform, per §4.1–§4.2 map, run against a legacy `CLAUDE.md`:
1. Locate `## Automation Config` … up to the next `##`.
2. For each `### {Section}` table, emit the corresponding `[section]` block into
   `.agent-flow/config.toml`, converting `| Key | Value |` rows to `key = value` (typed:
   quoted strings; bare ints/bools; `"""` for the PR Description Template body; array-of-tables
   for Pipeline Profiles; delimited-scalar encoding per §1.1a for list/map keys).
3. Rewrite the `## Automation Config` section in `CLAUDE.md` down to the 1–2 line pointer
   (REQ-02).
4. Idempotent: if `config.toml` already exists, warn and require explicit overwrite rather than
   clobbering.
5. **Malformed / partial input (robustness, m5).** If the inline block is malformed or missing
   required sections (broken pipe tables, absent `### Issue Tracker`, etc.), `--migrate` SHALL
   emit a `[WARN]` listing each section it could not extract, SHALL NOT silently drop a
   section, and SHALL NOT leave a half-written `config.toml` that would fail `/check-setup`.
   Concretely: it either (a) aborts before writing `config.toml` when any **required** section is
   unextractable — leaving `CLAUDE.md` untouched — reporting exactly what to fix; or (b) when only
   *optional* sections are malformed, writes the cleanly-extracted sections and reports the
   skipped optional ones for manual completion. It never rewrites `CLAUDE.md` to the pointer
   unless a valid, check-setup-passing `config.toml` was produced (so the config is never lost).

---

## 5. Docs & scenario impact

### 5.1 Doc-count-drift sync set (REQ-24)

Update together in the same change:

| File | Change |
|---|---|
| `CLAUDE.md` | `## Automation Config` → pointer; the 18-optional / 23-section prose retargets to `config.toml` `[section]`s |
| `README.md` | config-location language → `.agent-flow/config.toml` |
| `docs/reference/automation-config.md` | full section reference retargets to TOML `[section]`s |
| `docs/guides/installation.md` | step "Add `## Automation Config` to CLAUDE.md" → "create `.agent-flow/config.toml`"; **gitignore block (lines 86-89) adds `config.local.toml` per-file, keeps `config.toml` tracked, NEVER a whole-dir `.agent-flow/` ignore (REQ-19)** |
| `docs/architecture.md` | config-flow description → read from `config.toml` |

### 5.2 Fixtures to migrate (REQ-25)

- `tests/mock-project/CLAUDE.md` → pointer + a sibling `.agent-flow/config.toml`.
- `tests/harness/fixtures/automation-config.md` → TOML form.

### 5.3 Scenarios to REWORK (retarget, do NOT delete — REQ-26)

| Scenario | Rework |
|---|---|
| `counts-invariants.sh` (assertion #5) | count 23 `[section]`s in `config.toml` (or the 18 optional under the doc reference), instead of 18 H3 sub-sections under `## Automation Config` in CLAUDE.md |
| `config-reader-sections.sh` | cross-check optional section names against `config.toml` `[section]`s / config-reader keys, not CLAUDE.md tables |
| `config-required-keys.sh` | assert the 5 required sections' keys are consumed, sourced from `config.toml` |
| `check-setup-*` | assert new validations (exists / not-gitignored / key-list / migrate hint) |
| `scaffold-*` | assert scaffold emits `config.toml`, not inline tables |
| `doc-count-sync.sh` | keep the 17/17 skill/core counts; extend location language to `config.toml` where it asserts config location |

Already-present forward-looking scenarios to keep green: `check-setup-no-migrate-config.sh`
(REQ-18), `toml-merge-no-md-fallback.sh` (no `.md` fallback / no `migrate-config`).

### 5.4 Five NEW scenario families (REQ-26)

1. **TOML parsing** — `[section]` headers, string/int/bool scalars, `"""` multi-line, `#`
   comments parse correctly; delimited-scalar list/map keys round-trip (§1.1a); malformed
   optional input ⇒ WARN + default, never crash (REQ-03, REQ-04, REQ-13).
2. **config.local deep-merge + denylist** — allowlisted override applies; each denylisted key
   ignored+warned; non-allowlisted key ignored+warned; absent overlay = no-op (REQ-07, REQ-14,
   REQ-17, REQ-21).
3. **Limits single-resolution (§2.4 regression guard)** — one resolved value drives both loop
   enforcement and prompt injection; precedence chain honoured; resolution path is pure-bash
   (no `python3`/`tomllib`, works on 3.10) (REQ-08, REQ-15, REQ-22, REQ-29).
4. **check-setup gitignore detection** — `git check-ignore` FAIL path (config.toml ignored) and
   OK path (config.toml tracked); plus config.local.toml-not-gitignored WARN guard (REQ-11,
   REQ-19).
5. **onboard --migrate** — inline tables → `config.toml` (lossless) + `CLAUDE.md` rewritten to
   pointer; malformed/partial input handled (no half-written config, WARN per unextracted
   section); and the hard-cut removal guard (no CLAUDE.md parse-into-config path survives)
   (REQ-09, REQ-16).

---

## 6. Tooling changes summary

| Tool | Change | Req |
|---|---|---|
| `core/config-reader.md` | rewritten: pure-bash TOML reader of `.agent-flow/config.toml` (+ overlay); **all** Markdown-table / CLAUDE.md-read paths removed; hosts the pure-bash limits-resolution path incl. the `customization/{agent}.toml [limits]` read | REQ-03, REQ-16, REQ-29 |
| `core/agent-override-injector.md` | `### Limits` render consumes the single resolved, pure-bash value (not raw plugin default); Step-1 delegation to `toml-merge.sh` unchanged for non-limits tiers | REQ-08, REQ-29 |
| `skills/setup-agents/lib/toml-merge.sh` | **NOT modified** (NEVER-modify preserved); no longer on the `[limits]` critical path — limits are resolved pure-bash | REQ-29 |
| `docs/guides/toml-overlay-syntax.md` | Tier-3 `[limits]` (lines 150-157) merges against config-resolved value | REQ-08 |
| `skills/onboard/SKILL.md` | gains `--migrate` (§4.3, incl. malformed/partial handling); generated output is `config.toml`, not inline tables | REQ-09 |
| `skills/scaffold/**` | emits `.agent-flow/config.toml` directly (delimited-scalar list/map encoding per §1.1a) | REQ-10 |
| `skills/check-setup/SKILL.md` | exists / not-gitignored (`git check-ignore`) / key-list (unknown→WARN, missing-required→FAIL) / legacy-inline → `/onboard --migrate` hint / config.local.toml-not-gitignored → WARN; MUST NOT mention `/migrate-config` | REQ-11, REQ-18 |
| `docs/guides/installation.md` | gitignore = per-file (add `config.local.toml`), never whole-dir `.agent-flow/` | REQ-19, REQ-24 |

### 6.1 Non-goals / constraints honoured

- **No** inline-CLAUDE.md fallback, dual-read, or deprecation window (hard cut — REQ-16).
- **No** `tomllib` / `tomli` / `taplo` / external tool for config parsing (pure bash — REQ-03).
- **No** `/migrate-config` command — migration is only `/onboard --migrate` (REQ-18).
- Source PR is **version-neutral** onto `release/v2.0.0` (no `plugin.json` /
  `marketplace.json` / `CHANGELOG` edits); MAJOR classification finalised on the integration
  branch (REQ-27).
- Windows/MSYS2 discipline: pure-bash parser strips trailing `\r`; scenarios run
  `HARNESS_JOBS=1` sequential; SIGPIPE-safe assert helpers only.
