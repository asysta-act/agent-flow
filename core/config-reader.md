# Config Reader

## Purpose

Parse the project's committed `.agent-flow/config.toml` (plus the optional, gitignored
per-developer `.agent-flow/config.local.toml` overlay) into a dot-notation config object that
commands consume without re-parsing. The reader is a **pure-bash** TOML-subset parser — it uses
only bash builtins (`while IFS= read -r`, `case`, parameter expansion), needs **no** `python3` and
**no** external tooling, and runs identically on Linux and Windows/MSYS2.

This is a hard cut: config lives in `.agent-flow/config.toml` only. There is no inline-Markdown
config source, no dual-read, and no deprecation shim anywhere on the config-read path.

> **Reference implementation.** `core/lib/config-reader.sh` is the executable pure-bash reference
> implementation of this contract (precedent: `core/lib/stage-invariant.sh`). It exposes
> `config_parse`, `config_get`/`config_list`/`config_map`, `config_overlay_merge`, `resolve_limit`
> (the single limits-resolution point), `config_validate`, and `config_migrate`. The
> `tests/scenarios/*.sh` harness sources it to assert the behaviours below (malformed→WARN,
> denylist/allowlist, single-resolution, delimited scalars, required-section BLOCK, `/onboard
> --migrate`). This prose remains the human contract; the `.sh` is what the tests execute.

## Input Contract

- **config_toml_path** (string, required): Path to the committed `.agent-flow/config.toml` — the
  single source of truth for all required and optional sections.
- **config_local_toml_path** (string, optional): Path to the gitignored
  `.agent-flow/config.local.toml` per-developer overlay. Absent ⇒ the overlay step is a no-op and
  the resolved config equals `.agent-flow/config.toml` merged over plugin defaults.

## Expertise — pure-bash TOML subset grammar

The reader recognises a deliberately small TOML subset — enough for the 23 sections and no more:

| Construct | Form | Maps to |
|---|---|---|
| Section header | `[section]` on its own line, bare snake_case name | opens a namespace |
| Array-of-tables | `[[pipeline_profiles]]` (Pipeline Profiles only) | appends a profile record |
| String scalar | `key = "value"` | `section.key = value` |
| Integer scalar | `key = 60` | numeric |
| Boolean scalar | `key = true` / `false` | boolean |
| Multi-line string | `key = """` … lines … `"""` | verbatim block (PR Description Template) |
| Comment | `# …` to end of line (and whole-line `#`) | ignored |
| Blank line | — | ignored |

Out-of-subset constructs (inline tables `{ }`, native arrays `[ a, b ]` other than the `[[…]]`
array-of-tables form, dotted keys `a.b.c = x`, datetime/hex/octal/float literals) are **rejected or
ignored with a `[WARN]`, never crashing**.

## Process — pure-bash parse algorithm

A line-oriented state machine over the file, using only bash builtins (SIGPIPE-safe; no
`echo $x | grep`):

1. Read line by line (`while IFS= read -r line`). **Strip a trailing `\r`** (MSYS2/CRLF discipline)
   via `${line%$'\r'}`. When a path must be handed to a helper, `cygpath -w` it first on Windows.
2. If inside a `"""` block, accumulate the raw line into the current key until a line whose trimmed
   content is the closing `"""`; then store the joined block verbatim.
3. Else strip a trailing `# …` comment **only when the `#` is outside a quoted string** (so
   `on_block = "comment" # note` keeps the value `comment`); trim surrounding whitespace.
4. Blank line ⇒ continue.
5. `[[name]]` ⇒ start a new array-of-tables record under `name`.
6. `[name]` ⇒ set current section = `name` (record header seen, for required-presence checks).
7. `key = value` ⇒ classify `value`: opens `"""` ⇒ multi-line mode; `"..."` ⇒ string (strip
   quotes); `true`/`false` ⇒ bool; all-digits (optional leading `-`) ⇒ int; anything else ⇒ treat
   as a bare string **with a `[WARN]`**. Emit `section.key=value` into the config object keyed by
   dot-notation. A defensive `case` fall-through guarantees any single unparsable line degrades to a
   `[WARN]` for that key rather than throwing.
8. After EOF: apply defaults for every unset optional key; verify the required sections are present.

The output object uses the same dot-notation namespace the plugin has always exposed
(`issue_tracker.type`, `retry.fixer_iterations`, …), so downstream skills need no change to *how*
they read config — only *where* it comes from (`.agent-flow/config.toml`).

## Sections — the 23 `[section]` tables

### Required sections (5)

- `[issue_tracker]` → `issue_tracker.type` (default: `youtrack`), `issue_tracker.instance`,
  `issue_tracker.project`, `issue_tracker.bug_query`, `issue_tracker.state_transitions`
  (delimited-scalar **map**), `issue_tracker.on_start_set`
- `[source_control]` → `source_control.remote`, `source_control.base_branch`,
  `source_control.branch_naming`
- `[pr_rules]` → `pr_rules.labels` (delimited-scalar **list**); `pr_rules.title_format` (optional
  key within this section; default: none → publisher uses the `{issue-id} {Mode}: {summary}` fallback)
- `[pr_description_template]` (key `template = """…"""`) → `pr_rules.description_template` (verbatim
  multi-line block)
- `[build_and_test]` → `build.build_command`, `build.test_command`, `build.verify_command` (optional)

### Optional sections (18) — missing section ⇒ use defaults

- `[retry_limits]` → `retry.fixer_iterations` (5), `retry.test_attempts` (3), `retry.build_retries`
  (3), `retry.spec_iterations` (5), `retry.root_cause_iterations` (3)
- `[module_docs]` → `module_docs.path` (none)
- `[hooks]` → `hooks.pre_fix`, `hooks.post_fix`, `hooks.pre_publish`, `hooks.post_publish` (none)
- `[custom_agents]` → `custom_agents.post_fix_agent`, `custom_agents.pre_publish_agent` (none)
- `[notifications]` → `notifications.webhook_url`, `notifications.on_events` (delimited-scalar list;
  valid events: `pr-created`, `issue-blocked`, `pipeline-started`, `step-completed`,
  `pipeline-completed`, `pipeline-paused`, `pipeline-resumed`)
- `[worktrees]` → `worktrees.batch_size`, `worktrees.base_path`, `worktrees.cleanup` (none)
- `[e2e_test]` → `e2e.framework`, `e2e.command` (none)
- `[browser_verification]` → `browser.base_url`, `browser.start_command`, `browser.stop_command`,
  `browser.on_events` (delimited-scalar list), `browser.timeout` (60), `browser.max_pages` (5),
  `browser.screenshot_storage` (`.agent-flow/{ISSUE-ID}/screenshots`), `browser.exploration`
  (disabled), `browser.exploration_max_clicks` (20)
- `[error_handling]` → `error_handling.on_block` (`comment`), `error_handling.max_blocked_per_run`
  (unlimited)
- `[feature_workflow]` → `feature.query`, `feature.on_start_set` (none)
- `[decomposition]` (Decomposition) → `decomposition.max_subtasks` (default: 7), `decomposition.fail_strategy` (default: `fail-fast`), `decomposition.commit_strategy` (default: `squash`), `decomposition.create_tracker_subtasks` (default: `enabled`)
- `[[pipeline_profiles]]` (array-of-tables) → `profiles[] = {name, skip_stages, extra_stages}`
  (`skip_stages`/`extra_stages` are delimited-scalar lists) (none)
- `[metrics]` → `metrics.output` (`stdout`), `metrics.period` (`30 days`)
- `[agent_overrides]` → `agent_overrides.path` (`customization/`)
- `[local_deployment]` → `local_deployment.type`, `local_deployment.start_command`,
  `local_deployment.stop_command`, `local_deployment.health_check_url`,
  `local_deployment.health_check_timeout` (60), `local_deployment.ports` (delimited-scalar list)
- `[sprint_planning]` (Sprint Planning) → `sprint_planning.sprint_duration` (`2 weeks`), `sprint_planning.capacity_unit`
  (`story-points`), `sprint_planning.team_capacity`, `sprint_planning.velocity_target`,
  `sprint_planning.sprint_field` (tracker-dependent), `sprint_planning.mode` (`suggest`),
  `sprint_planning.max_issues` (20), `sprint_planning.epic_template`
- `[autopilot]` (Autopilot) — the 7 autopilot keys → `autopilot.max_issues_per_run` (1), `autopilot.lock_timeout` (120),
  `autopilot.log_file` (`.agent-flow/autopilot.log`), `autopilot.bug_limit` (0),
  `autopilot.feature_limit` (0), `autopilot.on_error` (`skip`), `autopilot.dry_run` (`false`).
  NOTE: `bug_query` resolves from `[issue_tracker]` and `feature_query` from `[feature_workflow]`;
  neither is an `[autopilot]` key.
- `[pause_limits]` → `pause_limits.pause_timeout` (`30 days`; valid range 1 hour–365 days; malformed
  values fall back to the default with a `[WARN]` rather than blocking)

Total: **5 required + 18 optional = 23** `[section]`s.

## Delimited-scalar encoding for list/map keys

Because the pure-bash subset has no native array/table grammar, list- and map-valued keys are stored
as single-line **delimited** scalar strings that the reader splits when materialising the object:

| Config key | Kind | Encoding | Split rule |
|---|---|---|---|
| `pr_rules.labels` | list | `labels = "bug, automated"` | split on `,`, trim each |
| `notifications.on_events` | list | `on_events = "pr-created, issue-blocked"` | split on `,`, trim |
| `browser.on_events` | list | `on_events = "verify, reproduce"` | split on `,`, trim |
| `local_deployment.ports` | list | `ports = "3000, 5432"` | split on `,`, trim |
| `issue_tracker.state_transitions` | map | `state_transitions = "triage: In Progress; fixed: Fixed"` | split on `;` → each on first `:` → `{key: value}`, trim |
| `[[pipeline_profiles]]` `skip_stages`/`extra_stages` | list | `skip_stages = "triage, browser-agent-verify"` | split on `,`, trim |

Rules: `,` delimits lists; `;` (records) + `:` (key/value) delimit maps; surrounding whitespace is
trimmed; an **empty string** yields an empty list/map; a value with **no delimiter** yields a
single-element list.

## `config.local.toml` overlay — deep merge, allowlist, denylist

`.agent-flow/config.local.toml` is optional and gitignored. When present it is applied as a per-key
**deep merge** on top of `.agent-flow/config.toml`: the overlay key wins; omitted keys are inherited
unchanged. **Absent overlay ⇒ no-op** (resolved config byte-identical to `config.toml` over defaults).

The merge is **allowlist**-driven. Only keys in these two sections are eligible to be overridden by
`config.local.toml` (per-developer by design):

- `[browser_verification]` (per-dev base URL, ports, screenshot path)
- `[local_deployment]` (per-dev ports, start/stop commands, health URL)

Any key **outside** the allowlist is ignored (never applied) and emits exactly one `[WARN]`.

> **Scope — this general overlay allowlist is SEPARATE from the limits-resolution chain.**
> This section describes the **general, full-section per-developer overlay merge**; its allowlist is
> exactly `{browser_verification, local_deployment}` (whole-section per-dev overrides), gated by the
> denylist below. It is a **distinct mechanism** from the dedicated limits-resolution function (see
> "Single limits-resolution point"). Consequently a `[retry_limits]` (limit) key placed in
> `config.local.toml` is **not** eligible for *this* general overlay — it is ignored + `[WARN]`ed
> here — **yet** `config.local.toml` MAY still contribute a limit **value** through the dedicated
> single-resolution function's explicit precedence chain (the §2.4 fix; intentional). There is no
> contradiction: the general overlay governs whole-section per-dev overrides; the limits chain
> governs individual `[retry_limits]` keys via its own precedence. The two never evaluate the same
> key through the same gate.

Layered on top of the allowlist is an explicit, enumerated **denylist** — team-consistency /
security-critical keys that MUST NOT be personally overridden even if someone tries. Each present
denylisted key is never applied and emits one `[WARN]` naming it:

- `source_control.remote` — team must target one repo
- `source_control.base_branch` — team must share the base branch
- `notifications.webhook_url` — prevents personal-URL leakage / SSRF surface
- `issue_tracker.instance` — team must query one tracker
- `issue_tracker.project` — team must query one project
- **all** `[pr_rules]` keys (labels, title_format, …) — the PR contract is team-uniform

A single function evaluates each incoming `config.local.toml` key against
`(is-allowlisted? AND NOT-denylisted?)`; only keys passing both are merged. Applied overrides (INFO)
and rejections (WARN) are logged to `.agent-flow/pipeline.log` for `check-setup` / audits.

## Single limits-resolution point

Retry/iteration limits are resolved **exactly once** by one pure-bash resolution function, through
this precedence chain (lowest → highest):

```
plugin default < config.toml < config.local.toml < customization/{agent}.toml [limits]
```

This chain is **authoritative for `[retry_limits]` (limit) keys** and is a **separate, dedicated
mechanism** from the general `config.local.toml` overlay allowlist above. `config.local.toml`
appearing as a tier here is **intentional** (the §2.4 fix): a developer's `config.local.toml`
`[retry_limits]` value contributes to a limit through *this* function, even though the general
whole-section overlay allowlist (`{browser_verification, local_deployment}`) does not admit
`[retry_limits]` as a full-section per-dev override. The reference implementation is
`core/lib/config-reader.sh` (`resolve_limit`); its precedence tests are
`tests/scenarios/limits-precedence-chain.sh` (including the config.local-only tier case) and
`tests/scenarios/limits-single-resolution*.sh`.

The single resolved value feeds **both** channels — the orchestrator's **loop enforcement**
(fixer↔reviewer, test attempts, build retries, spec iterations, root-cause iterations) **and** the
**prompt injection** rendered by `core/agent-override-injector.md`'s `### Limits` block. Neither
channel recomputes independently, so the enforced value always equals the injected value.

This resolution reads **all four tiers — including the top `customization/{agent}.toml` `[limits]`
tier — via this same pure-bash parser**. It does **not** delegate the `[limits]` read to the
setup-agents overlay merge library (`toml-merge.sh`), which depends on a Python TOML parser module
that is unavailable on the Python 3.10 host and would silently yield an empty overlay — reintroducing
the two-channel divergence. `toml-merge.sh` is unmodified and still parses the non-limits overlay
tiers (`model`, `style`, `[[process_additions]]`, `[[constraints]]`); only the `[limits]` tier is
read pure-bash here.

## Output Contract

A config object with all parsed values and defaults applied. Commands reference keys using
dot-notation (e.g., `issue_tracker.type`, `retry.fixer_iterations`, `agent_overrides.path`).

## Failure Handling

- **Optional section malformed** (garbage scalar, unterminated `"""`, junk `[header]`): emit
  `[WARN] <section>: <reason>; using default`, apply that section's documented default, and **keep
  going — exit 0, never crash**. This TOML-specific degradation matches the reader's existing
  "never block on an optional section" contract.
- **Required section absent or empty** — degradation is optional-only, so a missing required
  `[section]` is a hard BLOCK/FAIL using the standard Block Comment Template:
  ```
  [agent-flow] 🔴 Pipeline Block
  Agent: config-reader
  Step: config parsing
  Reason: .agent-flow/config.toml is missing one or more required sections.
  Detail: List the missing required [section]s (e.g. [issue_tracker]).
  Recommendation: Add the required section(s) to .agent-flow/config.toml, or run /agent-flow:onboard --migrate if you still have a legacy inline config.
  ```
- **`.agent-flow/config.toml` not found:** BLOCK with the same template, Reason naming the absent file.
