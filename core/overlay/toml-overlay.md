# toml-overlay

## Purpose

Parse `customization/{agent}.toml` overlay files in the consuming project, validate their
contents against the per-agent schema, apply 3-tier merge semantics against the plugin-default
agent prompt, and emit a provenance log entry for every agent dispatch.

---

## Contract

### When overlay is applied

During every agent dispatch (in all pipeline skills: `fix-bugs`, `implement-feature`,
`scaffold`), BEFORE the agent's Task tool invocation, the dispatching
skill MUST:

1. Resolve the overlay path: `{project_root}/customization/{agent-name}.toml`
2. If overlay exists → parse, validate, apply 3-tier merge, log provenance.
3. If no `.toml` but a legacy `{agent-name}.md` exists → reject (legacy `.md` overlay is unsupported).
4. If neither exists → log provenance with `overlay_source=none`.

**Exactly once per dispatch** — the provenance log entry is written once per agent invocation,
not once per pipeline run.

### Where TOML files live

```
{project_root}/
  customization/
    {agent-name}.toml          ← primary
    {agent-name}.md            ← legacy; unsupported (manual conversion required)
```

`{project_root}` is the directory containing `CLAUDE.md`, or the git repository root when
`CLAUDE.md` is absent.

`{agent-name}` MUST be one of the 17 canonical agent names:
`analyst`, `fixer`, `reviewer`, `test-engineer`, `acceptance-gate`, `publisher`,
`rollback-agent`, `spec-analyst`, `architect`, `scaffolder`,
`priority-engine`, `spec-writer`, `spec-reviewer`, `browser-agent`, `deployment-verifier`,
`backlog-creator`, `sprint-planner`.

---

## TOML Schema

### Per-agent overrideable keys — full enumeration

The schema below applies to **any** of the 18 agents. Agent-specific `[limits]` keys are
enumerated in the per-agent reference table further below.

```toml
# customization/{agent}.toml — universal schema for all 18 agents

# --- Tier 1: Scalar overrides ---
model = "sonnet"    # one of: opus | sonnet | haiku
                    # Plugin default per agent in agents/{agent}.md frontmatter.
                    # Overlay value wins; plugin default is discarded.

style = "rigorous"  # Short descriptor; appended to the agent's system prompt.
                    # Free-form string. Plugin default per agent frontmatter.

# --- Tier 2: Array of tables (append) ---
# Plugin-default entries appear BEFORE project additions (order preserved).
[[process_additions]]
step = "after_default"    # required; canonical anchor name from toml-overlay-syntax.md
instruction = "Check SQL injection in all DB queries."  # required; free-form string

[[process_additions]]
step = "before_publish"
instruction = "Always run `make smoke` before PR creation."

[[constraints]]
rule = "PR review messages MUST be in Czech."  # required; free-form string

[[constraints]]
rule = "Reject any PR that introduces a new dependency without package.json rationale."

# --- Tier 3: Tables (deep merge) ---
# Only the keys present in the overlay are merged; absent keys are inherited from
# the plugin default unchanged.
[limits]
max_review_iterations    = 3    # reviewer default: 5
max_diff_lines           = 80   # fixer default: 100
max_iterations           = 4    # fixer default: 5
max_test_attempts        = 5    # test-engineer default: 3
max_build_retries        = 2    # default: 3
max_spec_iterations      = 5    # default: 5
max_root_cause_iterations= 3    # default: 3
max_files_reported       = 8    # analyst default: 5
max_decomposition_depth  = 3    # architect default; agent-specific
max_pr_retries           = 3    # publisher; agent-specific
max_pages                = 10   # browser-agent; agent-specific
exploration_max_clicks   = 50   # browser-agent; agent-specific
ac_threshold             = 3    # acceptance-gate; default: 3
complexity_threshold     = "M"  # acceptance-gate; default: M
test_framework           = "pytest"  # test-engineer; free-form string

# --- [meta]: free-form table (exempt from unknown-key validation) ---
# All sub-keys are accepted without validation.
# NOT consumed by plugin dispatch logic — reserved for project-side annotations.
[meta]
priority_label = "team-priority"
team_owner     = "backend-team"
cost_center    = "PROJ-42"
```

### Per-agent overrideable key reference table

| Agent | Scalar (Tier 1) | Array (Tier 2) | Table keys in `[limits]` (Tier 3) |
|-------|-----------------|----------------|-----------------------------------|
| `analyst` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_files_reported` |
| `fixer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_diff_lines`, `max_iterations` |
| `reviewer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_review_iterations` |
| `test-engineer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_test_attempts`, `test_framework` |
| `acceptance-gate` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `ac_threshold`, `complexity_threshold` |
| `publisher` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_pr_retries` |
| `spec-analyst` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_root_cause_iterations` |
| `architect` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_decomposition_depth` |
| `scaffolder` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_spec_iterations` |
| `browser-agent` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_pages`, `exploration_max_clicks` |
| `rollback-agent` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `priority-engine` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `spec-writer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | `max_spec_iterations` |
| `spec-reviewer` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `deployment-verifier` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `backlog-creator` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |
| `sprint-planner` | `model`, `style` | `[[process_additions]]`, `[[constraints]]` | (none agent-specific) |

All agents accept `[meta]` as a free-form table. `max_build_retries` and `max_spec_iterations`
are global-limit keys available to any agent where they are semantically applicable.

---

## 3-Tier Merge Rules

### Tier 1 — Scalar override

- Keys: `model`, `style`
- Rule: TOML overlay value **replaces** the plugin-default value entirely.
- Plugin default is read from the agent's `agents/{agent}.md` YAML frontmatter.
- Example: plugin default `model: opus`, overlay `model = "sonnet"` → effective `model: sonnet`.

### Tier 2 — Array of tables (append)

- Keys: `[[process_additions]]`, `[[constraints]]`
- Rule: plugin-default array entries appear **BEFORE** project additions (order preserved).
  TOML overlay entries are **appended after** the defaults, never prepended or interspersed.
- Each `[[process_additions]]` entry requires keys: `step` (string) and `instruction` (string).
- Each `[[constraints]]` entry requires key: `rule` (string).
- Additional keys inside these entries are subject to unknown-key validation.
- Example (append ordering):
  - Plugin default: `process_additions` = `[{step="after_default", instruction="AC verification"}]`
  - Overlay adds: `[{step="after_default", instruction="SQLi check"}, {step="before_publish", instruction="smoke test"}]`
  - Effective: 3 entries — AC verification → SQLi check → smoke test (plugin defaults first).

### Tier 3 — Table deep merge

- Keys: `[limits]`
- Rule: key-by-key union. TOML overlay keys **override** the corresponding plugin-default key
  at the same path. **Absent keys are inherited from the plugin default** unchanged.
- Recursive into nested tables if any.
- Example:
  - Plugin default `[limits]`: `{max_review_iterations=5, max_diff_lines=100}`
  - Overlay `[limits]`: `{max_review_iterations=3}` (no `max_diff_lines`)
  - Effective `[limits]`: `{max_review_iterations=3, max_diff_lines=100}`
- `[meta]` is NOT subject to deep-merge validation. All sub-keys are accepted.

### Conflict resolution / precedence

**TOML overlay always wins over plugin default** at the same path. There is no "merge order"
ambiguity because the schema is a single 2-layer stack (plugin default + project overlay).
User-level overlays (3-layer stack) are deferred to a future version.

---

## Validation

### Syntax error

WHEN the TOML file fails to parse (invalid TOML 1.0 syntax), the plugin SHALL:
1. Emit `[ERROR] TOML overlay validation failed for {agent}: syntax error in {file_path}` (with
   line number if the chosen parser reports one — line number is **optional**).
2. Halt agent dispatch (non-zero exit).
3. NOT proceed with any partial merge.

Error format: `[ERROR] TOML overlay validation failed for {agent}: {detail} (file: {overlay_path})`

Example error for unterminated string `model = "sonnet` (no closing quote):
```
[ERROR] TOML overlay validation failed for reviewer: syntax error: unterminated string at line 1 (file: customization/reviewer.toml)
```

### Unknown-key validation (strict mode)

Unknown-key rejection applies to:
- All top-level keys (any key other than `model`, `style`, `[[process_additions]]`,
  `[[constraints]]`, `[limits]`, `[meta]`)
- Keys inside `[limits]` not in the per-agent reference table
- Keys inside `[[process_additions]]` entries other than `step` and `instruction`
- Keys inside `[[constraints]]` entries other than `rule`

**`[meta]` sub-keys are EXEMPT from unknown-key rejection** (free-form table, any sub-key
accepted without validation).

Error format: `[ERROR] TOML overlay validation failed for {agent}: unknown key '{key}' (file: {overlay_path})`

The error message MUST include the **offending key name** so the operator can immediately
identify and fix the offending entry. Dispatch is halted with non-zero exit (exit code 1) on
any unknown-key violation.

### `.md` + `.toml` coexistence

WHEN both `customization/{agent}.md` AND `customization/{agent}.toml` exist (hard error):
- Refuse the dispatch path.
- Emit: `[ERROR] Legacy .md overlay format is not supported; remove customization/{agent}.md (TOML takes precedence). See docs/guides/toml-overlay-syntax.md for manual conversion steps.` (to
  `pipeline.log` and stderr) and exit non-zero.

### Legacy `.md`-only fallback — unsupported

WHEN only `customization/{agent}.md` exists (no `.toml`):
- Refuse the dispatch path (the `.md` legacy fallback is unsupported).
- Emit: `[ERROR] Legacy .md overlay format is not supported; convert .md to .toml manually (see docs/guides/toml-overlay-syntax.md).` and exit non-zero.

---

## Provenance Log

**Format** (one line per agent dispatch, written to `.agent-flow/pipeline.log`):

```
agent={name} overlay_source={toml|md|none} overlay_path={path}
```

| Field | Description |
|-------|-------------|
| `agent` | Agent name (e.g., `reviewer`) |
| `overlay_source` | `toml` — TOML overlay applied; `md` — legacy .md overlay applied; `none` — no overlay |
| `overlay_path` | Absolute or project-relative path to the overlay file; `(none)` when `overlay_source=none` |

**Three branches via `resolve_overlay()` plus one `md_rejected` injector-emitted branch (exactly once per dispatch):**

`resolve_overlay()` in `lib/toml-merge.sh` emits 3 branches automatically via `log_overlay_provenance()`:

| Scenario | `overlay_source` value | Log line |
|----------|------------------------|----------|
| `.toml` overlay used | `toml` | `agent=reviewer overlay_source=toml overlay_path=customization/reviewer.toml` |
| `.md` legacy overlay used | `md` | `agent=reviewer overlay_source=md overlay_path=customization/reviewer.md` |
| No overlay | `none` | `agent=reviewer overlay_source=none overlay_path=(none)` |

A 4th branch — `md_rejected` — is emitted by `core/agent-override-injector.md` (Layer 3) when the
`.md`-only short-circuit fires BEFORE `resolve_overlay()` is called (legacy `.md`-only case;
the legacy `.md` overlay is unsupported). The injector calls
`log_overlay_provenance "$agent_name" "md_rejected" "$md_path"` explicitly on that branch. The
`md_rejected` value MUST NOT be emitted in any other code path.

| Scenario | `overlay_source` value | Emitted by |
|----------|------------------------|------------|
| `.toml` overlay applied | `toml` | `resolve_overlay()` (lib) |
| `.md` legacy overlay (historical) | `md` | `resolve_overlay()` (lib) |
| No overlay file found | `none` | `resolve_overlay()` (lib) |
| `.md`-only short-circuit | `md_rejected` | injector (`core/agent-override-injector.md`) |

The provenance log entry is written **exactly once per dispatch** (once per agent invocation,
not once per pipeline run or per overlay key).

**Log destination**: `.agent-flow/pipeline.log` (append mode; same file as other pipeline log
entries; see `core/state-manager.md` for log rotation policy).

### Overlay binding into the dispatch witness

The resolved overlay is now bound into the per-stage `dispatch_witness`, which is
`sha256("<subagent_type>|<model>|<prompt_head_128>|<overlay_source>|<overlay_digest>")`. The
`overlay_digest` is the sha256 of the rendered overlay Markdown block when `overlay_source=toml`,
or the literal `none` / `md_rejected` for those branches. Because the overlay provenance and
digest are witness inputs, dropping a `.toml` overlay flips `overlay_source` `toml→none` and
`overlay_digest→none`, changing the witness — so the omission is detectable.

The dispatch hook (`hooks/validate-dispatch.sh` via
`core/lib/stage-invariant.sh::check_dispatch_witness`) verifies in two layers: **V1** recomputes
the witness from the stored fields and compares it to `dispatch_witness`; **V2** checks overlay
presence — if `customization/{agent}.toml` exists on disk but the stage recorded
`overlay_source != toml`, that is a `WITNESS_MISMATCH` (the dropped-overlay case). Verification is
**strict by default**: `AGENT_FLOW_STRICT_DISPATCH` is strict unless explicitly set to `"0"`, and a
true mismatch exits the hook with code 2, failing the dispatch.

### Layer architecture note (Layer 2 vs. Layer 3)

The "Halt agent dispatch (non-zero exit)" language in the Validation section above refers to
**Layer 2 function-level non-zero return** from `resolve_overlay()` (inside `lib/toml-merge.sh`),
NOT to a Layer 3 pipeline abort.

The calling skill's `core/agent-override-injector.md` operates at **Layer 3** and MUST absorb
that non-zero return via the explicit guarded assignment form:

```
additional_instructions=$(resolve_overlay "$agent_name" "$override_path" "$defaults_json") || additional_instructions=""
```

This guard ensures the pipeline NEVER blocks on overlay failure. Layer 2 emits its `[ERROR]` to
stderr; Layer 3 absorbs the non-zero return, sets `additional_instructions` to empty, and
continues dispatch with the bare agent prompt. No second `[WARN]` is emitted at Layer 3.

Summary:
- **Layer 2** (`lib/toml-merge.sh::resolve_overlay()`) — returns non-zero to signal failure.
- **Layer 3** (`core/agent-override-injector.md`) — ABSORBS that non-zero return; pipeline NEVER
  blocks on overlay failure.

---

## Backwards Compatibility

### Legacy `.md` overlay removal

- `customization/{agent}.md` legacy overlay support has been **removed**.
- Manual `.md` → `.toml` conversion is documented in `docs/guides/toml-overlay-syntax.md`.
- Any consuming project still using `.md` overlays will encounter a validation error at dispatch time.

---

## Implementation Reference (advisory)

The reference implementation lives at `skills/setup-agents/lib/toml-merge.sh`.
It uses `python3 tomllib` (Python 3.11+ stdlib) as the TOML parser, with a graceful error
on missing `python3`. The spec does NOT mandate a specific parser; any
TOML 1.0 compliant parser is acceptable.

See also: `docs/guides/toml-overlay-syntax.md` (user-facing syntax guide with worked examples).
