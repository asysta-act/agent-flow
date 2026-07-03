# TOML Overlay Syntax Guide

**Version:** v1.0.0+
**Applies to:** agent-flow plugin

---

## 1. Overview

The agent-flow plugin supports structured per-agent configuration via TOML overlay files.
Instead of raw text appended to the prompt (the old `.md` format), projects create
`customization/{agent}.toml` files with precisely defined merge semantics.

**TOML overlay = structured per-agent configuration in `customization/{agent}.toml`** that
extends the plugin-default agent definition in three tiers:

1. **Scalar override** — replaces a specific value (e.g., `model`, `style`)
2. **Array append** — adds entries after the plugin-default arrays (`[[process_additions]]`, `[[constraints]]`)
3. **Table deep-merge** — merges keys in `[limits]` with plugin defaults key-by-key

The system validates TOML files strictly: unknown keys cause immediate dispatch abort with an error
message, so typos in key names are caught immediately. The `[meta]` table is the exception —
it is **free-form** and accepts any sub-keys without validation.

> **Requirement — a TOML parser must be available.** Overlay files are parsed by `python3` using
> `tomllib` (Python 3.11+ stdlib) or the `tomli` backport on older Pythons. If `python3` is missing,
> or neither `tomllib` nor `tomli` is importable, the injector **silently drops every overlay**: the
> pipeline never blocks on overlay failure (by design), so your `customization/*.toml` files are simply
> ignored with no dispatch-time error — only an `[ERROR]` to stderr. Verify with
> `python3 -c "import tomllib"` (3.11+) or `python3 -c "import tomli"`; on Python 3.10 install the
> backport via `python3 -m pip install tomli`. Run `/agent-flow:check-setup` to confirm — it reports
> `[FAIL]` when a `.toml` overlay exists but no parser is importable. See the
> [Installation Guide](installation.md#prerequisites) prerequisites for details.

---

## 2. Per-Agent Overrideable Keys Reference

The table below lists all 17 agents and their overrideable keys.
All agents share the universal schema (Tier 1 + Tier 2 + `[meta]`); Tier 3 keys in `[limits]`
are agent-specific.

| Agent | Tier 1 (scalar override) | Tier 2 (array append) | Tier 3 — `[limits]` keys |
|-------|--------------------------|-----------------------|---------------------------|
| `analyst` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_files_reported` |
| `fixer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_diff_lines`, `max_iterations` |
| `reviewer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_review_iterations` |
| `acceptance-gate` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `ac_threshold`, `complexity_threshold` |
| `test-engineer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_test_attempts`, `test_framework` |
| `publisher` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_pr_retries` |
| `rollback-agent` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `spec-analyst` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_root_cause_iterations` |
| `architect` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_decomposition_depth` |
| `scaffolder` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_spec_iterations` |
| `priority-engine` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `spec-writer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_spec_iterations` |
| `spec-reviewer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `browser-agent` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_pages`, `exploration_max_clicks` |
| `deployment-verifier` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `backlog-creator` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `sprint-planner` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |

**Shared `[limits]` keys** (semantically applicable to any agent):

| Key | Default | Description |
|-----|---------|-------------|
| `max_build_retries` | `3` | Max build step retries |
| `max_spec_iterations` | `5` | Max spec-writer ↔ spec-reviewer iterations |
| `max_root_cause_iterations` | `3` | Max root cause analysis iterations |

**`[meta]`** is free-form and available to all agents — any sub-keys are accepted without validation.

---

## 3. Three-Tier Merge Rules

### Tier 1 — Scalar Override

The plugin-default value is **replaced** by the value from the overlay file.

Supported scalar keys: `model`, `style`.

**Valid `model` values:** `opus`, `sonnet`, `haiku`.

**Example — switching reviewer to opus:**

```toml
# customization/reviewer.toml
model = "opus"
style = "security-focused"
```

Result: the `reviewer` agent will run with model `opus` instead of the plugin default.

**Example — switching publisher from haiku to sonnet:**

```toml
# customization/publisher.toml
model = "sonnet"
```

The plugin default `agents/publisher.md` declares `model: haiku`. The overlay overrides it to `sonnet`.
Effective model: `sonnet`.

### Tier 2 — Array of Tables (Append)

Overlay entries are **appended after** the plugin-default entries. Plugin-default entries always appear before project additions (order preserved).

Overlay entries are **appended after** the plugin-default entries. Order is preserved.

**Keys:** `[[process_additions]]`, `[[constraints]]`

Required sub-keys:
- `[[process_additions]]`: `step` (string), `instruction` (string)
- `[[constraints]]`: `rule` (string)

Unknown sub-keys inside these items are **rejected** (unknown-key validation).

**Example — adding a security check to reviewer:**

Plugin default `process_additions`:
```
[{step="after_default", instruction="Verify all acceptance criteria are addressed."}]
```

Overlay adds:
```toml
# customization/reviewer.toml
[[process_additions]]
step = "after_default"
instruction = "Run SAST mental-pass: SQLi, XSS, SSRF, path traversal."

[[process_additions]]
step = "before_publish"
instruction = "Confirm all new public API methods have docstrings."
```

Effective `process_additions` (3 entries, in this order):
1. `{step="after_default", instruction="Verify all acceptance criteria are addressed."}` ← plugin default
2. `{step="after_default", instruction="Run SAST mental-pass: SQLi, XSS, SSRF, path traversal."}` ← overlay
3. `{step="before_publish", instruction="Confirm all new public API methods have docstrings."}` ← overlay

### Tier 3 — Table Deep Merge

The `[limits]` table is merged key-by-key: overlay keys override the corresponding plugin-default
keys; **absent keys are inherited from the plugin default** unchanged (missing keys in the overlay
inherit their value from the plugin default).

The `[limits]` table is merged **key-by-key**: overlay keys override the corresponding plugin-default
keys; keys absent from the overlay are **inherited from the plugin default** unchanged.

**Example — reducing max iterations for reviewer:**

Plugin default `[limits]` for `reviewer`:
```
{max_review_iterations=5}
```

Overlay:
```toml
# customization/reviewer.toml
[limits]
max_review_iterations = 3
```

Effective `[limits]`: `{max_review_iterations=3}` — overlay wins.

**Example — partial override preserving the rest:**

Plugin default `[limits]` for `fixer`:
```
{max_diff_lines=100, max_iterations=5}
```

Overlay:
```toml
# customization/fixer.toml
[limits]
max_diff_lines = 60
```

Effective `[limits]`: `{max_diff_lines=60, max_iterations=5}` — `max_diff_lines` overridden,
`max_iterations` inherited from the plugin default.

### Conflict Resolution Precedence

The TOML overlay **always wins** over the plugin default on the same path. There is no
ambiguity in merge order — the schema is strictly a 2-layer stack (plugin default + project overlay).
A third user-level overlay layer is not supported.

---

## 4. TOML Examples

### 4.1 `reviewer-strict-security.toml`

```toml
# customization/reviewer.toml
# Strict security posture for any project with public-facing API.
model = "opus"

[[process_additions]]
step = "after_default"
instruction = "Run a SAST mental-pass: check for SQLi, XSS, SSRF, path traversal, secret commits."

[[constraints]]
rule = "Block any PR introducing eval(), Function(), or subprocess.shell=True."

[[constraints]]
rule = "Block any PR that adds a new env var without documenting it in docs/configuration.md."

[[constraints]]
rule = "NEVER approve a PR that changes authentication flow without explicit security test coverage."

[limits]
max_review_iterations = 7

[meta]
security_level = "strict"
team_owner = "security-team"
```

### 4.2 `fixer-no-tests.toml`

```toml
# customization/fixer.toml
# Prototype branch policy: skip test dispatch on prototype/* branches.
[[process_additions]]
step = "before_test_dispatch"
instruction = "If the current branch matches the pattern prototype/*, skip test dispatch. Only run the smoke build. Mark the PR as Draft and add the label prototype-no-tests."

[[constraints]]
rule = "On prototype/* branches, NEVER create a ready-for-review PR. Always use draft mode."

[limits]
max_diff_lines = 200
max_test_attempts = 0

[meta]
policy = "prototype-no-tests"
```

### 4.3 `analyst-monorepo.toml`

```toml
# customization/analyst.toml
# Monorepo project: expand impact analysis across all top-level packages.
style = "cross-package-aware"

[[process_additions]]
step = "after_default"
instruction = "On --phase impact, walk all top-level packages under apps/, packages/, and libs/. Report cross-package dependencies in the affected-files list. Include every consumer package that imports the changed module."

[[constraints]]
rule = "Cross-package changes MUST list every consumer package in the impact report (max 5 packages, alphabetical order)."

[limits]
max_files_reported = 8
```

### 4.4 `browser-agent-parallel.toml`

```toml
# customization/browser-agent.toml
# High-coverage browser verification for a content-heavy application.
style = "thorough"

[[process_additions]]
step = "after_default"
instruction = "On --phase verify, also navigate to /accessibility-check and validate WCAG AA contrast ratios on the changed page."

[[constraints]]
rule = "NEVER mark verification as passed if any console error appears in the browser log."

[limits]
max_pages = 20
exploration_max_clicks = 100

[meta]
coverage_target = "wcag-aa"
base_url_override = "https://staging.example.com"
```

### 4.5 `agent-with-meta-table.toml`

```toml
# customization/spec-writer.toml
# Project-side metadata annotations (not consumed by plugin dispatch logic).
model = "opus"

[[constraints]]
rule = "All acceptance criteria MUST follow the EARS format (WHEN/THEN/WHILE) with no exceptions."

[limits]
max_spec_iterations = 7

[meta]
priority_label   = "priority"
team_owner       = "architecture-team"
cost_center      = "PROJ-42"
jira_component   = "Backend-Core"
review_required  = true
arbitrary_key    = "any value is accepted here — no validation applied to [meta] sub-keys"
```

---

## 5. `[meta]` Table — Free-Form

The `[meta]` table is **free-form**: the plugin accepts it without any sub-key validation.

```toml
[meta]
priority_label = "priority"   # example key — entirely up to the project
team_owner     = "backend-team"    # example key
cost_center    = "PROJ-42"         # example key
any_key        = "any value"       # arbitrary; NOT subject to unknown-key validation
```

Keys in `[meta]` are **NOT consumed** by the plugin dispatch logic. They are intended solely
for project-side annotations (tracking, cost attribution, tooling integrations).

**`[meta]` is EXEMPT from unknown-key rejection**: while all other
top-level keys and keys inside `[limits]`, `[[process_additions]]`, `[[constraints]]` are subject to
strict-mode unknown-key validation, sub-keys inside `[meta]` are NOT subject to unknown-key
rejection and may have any names. Meta sub-keys accept arbitrary values (strings, integers,
booleans, arrays — any valid TOML value type).

This exemption allows projects to store arbitrary metadata without requiring changes to the plugin schema.

---

## 6. Validation Rules

### 6.1 TOML Syntax Errors

If an overlay file cannot be parsed (invalid TOML 1.0 syntax), the plugin:
1. Emits an `[ERROR]` log with the file path and line number (if the parser reports it — optional)
2. Aborts the agent dispatch with a non-zero exit
3. Does NOT continue with any partial merge

**Error format:**
```
[ERROR] TOML overlay validation failed for {agent}: {detail} (file: {overlay_path})
```

**Example errors:**
```
[ERROR] TOML overlay validation failed for reviewer: syntax error: unterminated string at line 3 (file: customization/reviewer.toml)
[ERROR] TOML overlay validation failed for fixer: syntax error: expected key-value separator '=' (file: customization/fixer.toml)
```

### 6.2 Unknown-Key Validation (Strict Mode)

Unknown-key rejection applies to:

| Scope | Rejection |
|-------|-----------|
| Top-level keys | Anything other than `model`, `style`, `[[process_additions]]`, `[[constraints]]`, `[limits]`, `[meta]` |
| Keys in `[limits]` | Keys not listed in the per-agent reference table (Section 2) |
| Keys in `[[process_additions]]` | Anything other than `step` and `instruction` |
| Keys in `[[constraints]]` | Anything other than `rule` |
| **Sub-keys in `[meta]`** | **EXEMPT — no validation, any keys accepted** |

**Error format:**
```
[ERROR] TOML overlay validation failed for {agent}: unknown key '{key}' (file: {overlay_path})
```

Example: a project accidentally writes `max_iterations_count` instead of `max_iterations` in `customization/fixer.toml`:
```
[ERROR] TOML overlay validation failed for fixer: unknown key 'max_iterations_count' (file: customization/fixer.toml)
```

Dispatch is aborted with exit code 1.

### 6.3 `.md` + `.toml` Coexistence

If **both** files exist for the same agent (`customization/{agent}.md` AND `customization/{agent}.toml`):
- The `.toml` file takes **precedence** (primary format)
- The `.md` file is **ignored**
- Emits: `[WARN] Legacy .md overlay ignored; .toml takes precedence`

---

## 7. Provenance Log

On every agent dispatch the plugin writes one record to `.agent-flow/pipeline.log`:

**Format:**
```
agent={name} overlay_source={toml|md|none} overlay_path={path}
```

| Field | Description |
|-------|-------------|
| `agent` | Agent name (e.g., `reviewer`) |
| `overlay_source` | `toml` — TOML overlay applied; `md` — legacy .md overlay applied; `none` — no overlay |
| `overlay_path` | Absolute or relative path to the overlay file; `(none)` for `overlay_source=none` |

**Three mandatory branches (each occurring exactly once per dispatch):**

| Scenario | Log line |
|----------|----------|
| `.toml` overlay used | `agent=reviewer overlay_source=toml overlay_path=customization/reviewer.toml` |
| `.md` legacy overlay used | `agent=reviewer overlay_source=md overlay_path=customization/reviewer.md` |
| No overlay | `agent=reviewer overlay_source=none overlay_path=(none)` |

The provenance record is written **exactly once per dispatch** — not once per pipeline run
and not once per overlay key.

**Log destination:** `.agent-flow/pipeline.log` (append mode; same file as other
pipeline log entries; rotation per `core/state-manager.md`).

### How the overlay interacts with the dispatch witness

The resolved overlay is bound into the per-stage `dispatch_witness` recorded in `state.json`:

```
dispatch_witness = sha256("<subagent_type>|<model>|<prompt_head_128>|<overlay_source>|<overlay_digest>")
```

`overlay_digest` is the sha256 of the rendered overlay block when `overlay_source=toml`, or the
literal `none` / `md_rejected` otherwise. Because the overlay is a witness input, removing a
`.toml` overlay flips `overlay_source` `toml→none` and `overlay_digest→none`, which changes the
witness — so a silently-dropped overlay is detectable.

The dispatch hook verifies the witness in two layers: **V1** recomputes it from the stored stage
fields and compares; **V2** flags a mismatch when `customization/{agent}.toml` exists on disk but
the stage recorded `overlay_source != toml`. Verification is **strict by default** —
`AGENT_FLOW_STRICT_DISPATCH` is strict unless explicitly `"0"`, and a true mismatch fails the
dispatch. In practice this means a `.toml` overlay you place under `customization/` is expected to
be applied and recorded on every dispatch for that agent.

---

## 8. Backwards Compatibility

### Legacy `.md` Overlay Support

Legacy `customization/{agent}.md` files are still parsed as raw append text:

- Each use emits a `[WARN]` log: `[WARN] Legacy .md overlay format; migrate to .toml`
- The pipeline does **not** abort due to a legacy `.md` overlay — warnings are advisory
- To convert manually: create a `customization/{agent}.toml` file with `[[process_additions]]` blocks (see Section 4 for examples)

**Coexistence rules:**

| File state | Behavior |
|------------|----------|
| `.toml` only | Uses `.toml` (primary path) |
| `.md` only | Uses `.md` with WARN (legacy path) |
| Both `.toml` and `.md` | Uses `.toml`, ignores `.md`, emits WARN |
| Neither | Provenance log `overlay_source=none`, no prompt modification |

**Legacy `.md`-only projects:** A project that only has `customization/{agent}.md` files —
without any `.toml` files — works without any migration. The plugin detects the `.md`-only overlay
path and applies the legacy append-text behavior, emitting a deprecation `[WARN]` per dispatch.

### `.md` Overlay Removal

`customization/{agent}.md` legacy overlay support may be removed in a future major version.
Projects still using `.md` overlays after that point will encounter a validation error at dispatch.
Migrate to TOML using the examples in Section 4.

---

## 9. Migration Path

To convert existing `customization/*.md` overlay files to TOML format, follow these steps manually:

1. Back up the entire `customization/` directory: `cp -r customization/ customization.bak-{timestamp}/`
2. For each `{agent}.md` file, create a corresponding `{agent}.toml` with `[[process_additions]]` blocks (see Section 4 for examples)
3. Delete or rename the original `.md` files once the TOML equivalents are in place
4. Run `/agent-flow:check-setup` to verify no overlay errors are reported

---

## Universal Schema Reference

Quick reference — full schema applicable to any of the 17 agents:

```toml
# customization/{agent}.toml — full schema (applicable to any of 18 agents)

# --- Tier 1: Scalar overrides ---
model = "sonnet"      # one of: opus | sonnet | haiku
style = "rigorous"    # short descriptor; appended to agent system prompt

# --- Tier 2: Array of tables (append after plugin defaults) ---
[[process_additions]]
step        = "after_default"     # required; canonical anchor name
instruction = "Your instruction." # required; free-form string

[[process_additions]]
step        = "before_publish"
instruction = "Run smoke before PR creation."

[[constraints]]
rule = "PR review messages MUST be in Czech."

[[constraints]]
rule = "Reject any PR that adds a dependency without package.json rationale."

# --- Tier 3: Table deep merge (only listed keys merged; rest inherited from plugin default) ---
[limits]
# Tier 3 keys vary by agent — see per-agent reference table (Section 2).
# Shared keys available to any agent where semantically applicable:
max_build_retries        = 2    # default: 3
max_spec_iterations      = 5    # default: 5
max_root_cause_iterations = 3   # default: 3

# --- [meta]: free-form table — NOT subject to unknown-key validation ---
# All sub-keys accepted; NOT consumed by plugin dispatch logic.
[meta]
priority_label = "priority"
team_owner     = "backend-team"
cost_center    = "PROJ-42"
```
