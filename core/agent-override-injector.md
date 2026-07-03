# Agent Override Injector

## Purpose

Load project-specific agent customizations from the configured override directory and inject
them into the agent's context as a rendered Markdown block. Enables per-project tuning
without forking the plugin.

Delegates all TOML parsing, validation, 3-tier merge, and provenance logging to
`skills/setup-agents/lib/toml-merge.sh::resolve_overlay()` (Layer 2). The injector is
Layer 3: it orchestrates the call, handles the `.md`-only short-circuit, renders the result
to Markdown, and NEVER blocks the pipeline on any failure.

---

## Input Contract

- **agent_name** (string, required): The agent's name as defined in its frontmatter
  (e.g., `reviewer`, `fixer`, `test-engineer`)
- **override_path** (string, required): Path to the override directory read from
  `## Automation Config` → `### Agent Overrides` → `Path` key (default: `customization/`)
- **defaults_json** (string, required): Plugin default JSON for this agent (passed through to
  `resolve_overlay()` as the base tier)

---

## Process

### Step 1 — Resolve overlay file via `lib/toml-merge.sh`

Read `Agent Overrides → Path` from `## Automation Config` (default: `customization/`).
Source the library and call `resolve_overlay()` with the guarded assignment form that absorbs
any non-zero return:

```bash
# Source the library (read-only — NEVER modify lib/toml-merge.sh)
source skills/setup-agents/lib/toml-merge.sh

# Read override_path from Automation Config (default: customization/)
override_path="${agent_overrides_path:-customization/}"

# Guarded call — absorbs non-zero return
additional_instructions=$(resolve_overlay "$agent_name" "$override_path" "$defaults_json") || additional_instructions=""
```

The explicit `|| additional_instructions=""` guard is mandatory. Without it,
`resolve_overlay()` running under `set -euo pipefail` (see `lib/toml-merge.sh` line 27)
would kill the parent shell on any failure. The injector NEVER blocks the pipeline on
overlay failure.

---

### Step 2 — `.md`-only short-circuit (legacy guard)

Before calling `resolve_overlay()`, check for the `.md`-only case:

```bash
toml_path="${override_path}/${agent_name}.toml"
md_path="${override_path}/${agent_name}.md"

if [ ! -f "$toml_path" ] && [ -f "$md_path" ]; then
    # .md-only: unsupported — emit [ERROR], log provenance, return empty
    echo "[ERROR] Legacy .md overlay format is not supported; manual conversion required — see docs/guides/toml-overlay-syntax.md for TOML overlay format examples." >&2
    log_overlay_provenance "$agent_name" "md_rejected" "$md_path"
    additional_instructions=""
    # DO NOT continue to Step 3 for this agent
    return 0
fi
```

This short-circuit lives EXCLUSIVELY in this injector. Step
files MUST NOT replicate this logic. The `log_overlay_provenance` call emits a provenance
line with `overlay_source=md_rejected`; this is the ONLY code path that emits `md_rejected`.

**Coexistence case** (both `.toml` AND `.md` present): `resolve_overlay()`
handles this internally — it emits an informational `[ERROR]` to stderr about the `.md` and
proceeds with the `.toml`. The injector's Step 2 guard does NOT fire (`.toml` exists), so
`resolve_overlay()` is called normally. Provenance logs `overlay_source=toml`.

---

### Step 3 — Render parsed TOML to Markdown

When `additional_instructions` (the merged JSON returned by `resolve_overlay()`) is
non-empty, render it to the following Markdown layout:

```markdown
## Project-Specific Instructions

<!-- Source: customization/{agent}.toml — rendered by agent-override-injector v9 -->

### Process additions
1. (step: {step_1}) {instruction_1}
2. (step: {step_2}) {instruction_2}
...

### Constraints
- {rule_1}
- {rule_2}
...

### Limits
- {key_1}: {value_1}
- {key_2}: {value_2}
...

### Meta
- {meta_key_1}: {meta_value_1}
- {meta_key_2}: {meta_value_2}
...
```

**Render rules:**

1. Heading is fixed: `## Project-Specific Instructions` — exact case, no trailing punctuation.
2. Source comment is mandatory: exactly one HTML
   comment line `<!-- Source: customization/{agent}.toml — rendered by agent-override-injector v9 -->`
   immediately under the heading, separated by one blank line. The em-dash is literal U+2014.
   The `{agent}` placeholder is substituted with the dispatched agent name.
3. `### Process additions` renders as a numbered list: `(step: {step}) {instruction}` per entry.
4. `### Constraints` renders as a bulleted list of literal `{rule}` values.
5. `### Limits` renders as a bulleted list of `{key}: {value}` pairs (merged-JSON order).
6. `### Meta` renders as a bulleted list of `{meta_key}: {meta_value}` pairs.
7. **Tier-1 scalars (`model`, `style`) DO NOT render here.** They affect dispatch model
   selection elsewhere.
8. **Empty subsection elision**: a subsection with zero entries MUST be omitted entirely.
9. **Block emptiness**: if ALL subsections are empty, the injector returns an empty string,
   NOT a heading-only block.

---

### Step 4 — Append rendered block to dispatched prompt

The rendered Markdown block is appended to the agent's base prompt as the last section,
immediately before the `Task(...)` invocation. The dispatching step file (the caller) is
responsible for the actual prompt concatenation:

```
{base_agent_prompt}

{rendered_markdown_block}
```

The append is verbatim — no transformation, no escaping. If `additional_instructions` is
empty (no overlay, or overlay failure absorbed), the base prompt is used unchanged.

---

## Output Contract

On every dispatch the injector emits exactly ONE provenance log line via
`log_overlay_provenance` (from `lib/toml-merge.sh`) with one of 4 source values:

| `overlay_source` | Emitted by | Condition |
|-----------------|-----------|-----------|
| `toml` | `resolve_overlay()` (lib) | `.toml` overlay loaded and merged |
| `md` | `resolve_overlay()` (lib) | Reserved for backward-compat in lib; structurally unreachable because the injector short-circuits before calling `resolve_overlay()` on `.md`-only paths |
| `none` | `resolve_overlay()` (lib) | No overlay file exists for this agent |
| `md_rejected` | injector (Step 2) | `.md` exists, `.toml` does NOT exist; legacy `.md` overlay is unsupported |

The injector emits only `toml`, `none`, or `md_rejected` itself; `md` is handled
internally by lib but is unreachable via this injector's call path.

Format: `agent={name} overlay_source={toml|md|none|md_rejected} overlay_path={path|(none)}`

Append-mode target: `.agent-flow/pipeline.log` (relative to project root / CWD).

**Exactly one line per agent dispatch** — calling `resolve_overlay()` automatically logs
once for the `toml`/`md`/`none` branches. The injector adds one explicit
`log_overlay_provenance` call ONLY on the `md_rejected` short-circuit (where
`resolve_overlay()` was not called). DO NOT add a second `log_overlay_provenance` call after
`resolve_overlay()` returns — this would produce duplicate lines.

---

## Failure Handling

All 6 enumerated failure modes are handled by `resolve_overlay()` returning non-zero. The
injector absorbs the non-zero return via the guarded assignment in Step 1 and returns empty
`additional_instructions`. The pipeline continues with the bare agent prompt. The injector
does NOT emit a second `[WARN]` — Layer 2's `[ERROR]` to stderr is sufficient.

| Failure mode | Layer 2 behavior | Injector behavior |
|-------------|-----------------|-------------------|
| `python3` absent | `[ERROR]` to stderr; return non-zero | Absorbed; `additional_instructions=""` |
| TOML parse error | `[ERROR]` to stderr; return non-zero | Absorbed; `additional_instructions=""` |
| File unreadable (permissions / I/O) | `[ERROR]` to stderr; return non-zero | Absorbed; `additional_instructions=""` |
| Unknown-key validation failure | `[ERROR]` to stderr; return non-zero | Absorbed; `additional_instructions=""` |
| Permission error on customization directory | `[ERROR]` to stderr; return non-zero | Absorbed; `additional_instructions=""` |
| Malformed JSON from `parse_toml_overlay` | `[ERROR]` to stderr; return non-zero | Absorbed; `additional_instructions=""` |

---

## Constraints

- NEVER modify `agents/*.md` (public agent contract — PATCH classification depends on this).
- NEVER modify `skills/setup-agents/lib/toml-merge.sh` (Layer 2 is off-limits per
  anti-pattern #3).
- NEVER block the pipeline on overlay failure. The guarded
  assignment form from Step 1 is mandatory.
- NEVER emit a second `[WARN]` from the injector when Layer 2 has already emitted `[ERROR]`.
- NEVER replicate the `.md`-only short-circuit into step files.
  This short-circuit lives EXCLUSIVELY in this file.
- NEVER hardcode `customization/` as the override path in step files. Always use the
  `{Agent Overrides path}` placeholder resolved from Automation Config at dispatch time.
- NEVER create new `core/*.md` files (count must remain 17).
