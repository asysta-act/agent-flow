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

**Render rules (per design.md Section 2):**

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

### Step 5 — Record `overlay_source` / `override_path` in the CLAIM (the gate signs `overlay_digest`)

`overlay_digest` is **GATE-OBSERVED ground truth** (PR #15, REQ-031/A5) — the same model as
`prompt_head_128`. It is the `sha256` of the **RAW, LF-normalized `.toml` file bytes** at
`override_path/<short>.toml` (**not** the rendered Markdown block), and **only the PreToolUse
gate computes it**: the gate reads the on-disk `.toml` once and SIGNS that digest
(`hooks/lib/witness_overlay.py::recompute_overlay_digest`, the one LF-normalizing authority). The
orchestrator does **NOT** compute, normalize, or commit `overlay_digest` into the CLAIM — so an
LF/CRLF-naive producer digest can never diverge from the gate's value and false-DENY every
overlay dispatch on Windows. There is **no producer-claim-vs-gate digest compare**.

Under the gate-as-signer model the witness itself is **no longer a `state.json` field**: the
orchestrator writes only the CLAIM (`overlay_source`, `override_path`, plus `subagent_type`,
`model`, `claim_nonce`, `dispatch_seq`, `status`, `dispatched_at`) and **holds no key**; the gate
is the sole signer and records the keyed HMAC tag — together with its own recomputed
`overlay_digest` — in the gate-owned ledger (`.agent-flow/{RUN-ID}/dispatch-ledger.jsonl`). The
injector runs UPSTREAM of the claim write, and the orchestrator follows this ordering per stage:

1. **Run the Agent Override Injector** (Steps 1–4) → resolves the overlay, yielding
   `overlay_source` (`toml` | `none` | `md_rejected`), the resolved `override_path`, and the
   rendered Markdown block (the block is appended to the prompt; it is NOT what is hashed).
2. **Do NOT record `overlay_digest`.** The gate derives it as ground truth:
   - `overlay_source=toml` → the gate signs the `sha256` of the RAW LF-normalized bytes of
     `override_path/<short>.toml` (read from disk at intercept).
   - `overlay_source=none` / `md_rejected` → the gate signs the literal source token.
   (The bash `core/lib/stage-invariant.sh::compute_overlay_digest` helper is LEGACY v1.0 ONLY and
   is retained for the demoted `--self-test`; it is never on the keyed compared path.)
3. **Persist the resolved `override_path`** (REQ-032/A6) in the CLAIM so the Claude-Code-spawned
   gate — which never inherits the skill's `AGENT_FLOW_OVERRIDE_PATH` env — reads it from
   `state.json` and looks up the correct `.toml`.
4. **ONE atomic state.json CLAIM write** for the stage block: `dispatched_at`,
   `status:"in_progress"`, `subagent_type`, `model`, `stage_name`, `overlay_source`,
   `override_path`, `claim_nonce`, `dispatch_seq` — **no key, no tag, NO `overlay_digest`, and NO
   `prompt_head_128`** (the gate observes the post-expansion head and recomputes the overlay
   digest, signing both as ground truth — neither is an orchestrator-committed/compared field).
5. **Append the rendered overlay block** to the prompt (Step 4 concatenation), write the
   per-dispatch marker, then invoke `Task(...)`.

Dropping a TOML overlay flips the CLAIM's `overlay_source` `toml`→`none` (a structural field the
gate binds), and a one-byte body edit changes the gate's SIGNED digest — caught by the PostToolUse
audit re-verifying the signed ledger digest against the on-disk `.toml`. Honest bound: the digest
records **WHICH overlay (by content) was applied** and gives **detection of out-of-key tampering**
— any party WITHOUT the run's per-run key cannot mint or silently alter a passing witness. It does
**NOT** provide producer-unforgeability: a same-OS-user process can read the key and forge. That
residual is the same-trust-domain limit documented in `state/schema.md`.

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

### `overlay_source` is a CLAIM field; `overlay_digest` is gate-observed ground truth

Beyond the provenance log line, the injector's resolution result feeds the dispatch witness:

- **`overlay_source`** — a CLAIM field; the `state.json` enum is exactly `toml` | `none` |
  `md_rejected` (`md` is a provenance-log-only historical value, never written to the state field).
- **`overlay_digest`** (REDEFINED, REQ-031/A5) — **NOT a CLAIM field.** The gate computes it as
  ground truth: the 64-hex `sha256` of the **RAW LF-normalized `.toml` file bytes** at
  `override_path/<short>.toml` for `toml`, else the literal `none` / `md_rejected`. It is **no
  longer** the digest of the rendered Markdown block, and the orchestrator does **not** commit it.

`overlay_source`, `override_path`, `subagent_type`, and `model` are CLAIM fields, deterministically
reproducible on disk so the orchestrator and the gate resolve the same values. `overlay_digest` and
`prompt_head_128` are **gate-observed**: the gate computes and signs them from the on-disk `.toml`
and the intercepted prompt, with **no producer-claim-vs-gate compare** (eliminating the Windows/CRLF
false-DENY surface). All are sub-hashed fields of the gate's keyed canonical preimage
(`subagent_type|model|prompt_head_128|overlay_source|overlay_digest|stage|run_id|claim_nonce`,
each field individually `sha256`'d then `|`-joined, then HMAC-keyed). The signed tag — and the
gate's recomputed `overlay_digest` — live in the gate-owned ledger, not `state.json`. The witness
therefore records **WHICH overlay (by content digest)** was applied at dispatch — detection of
out-of-key tampering, not producer-unforgeability (a same-OS-user process can still forge). See
`state/schema.md` for field definitions and the honest threat-model delta.

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
