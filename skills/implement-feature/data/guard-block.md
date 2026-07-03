# Mandatory Execution Guard — /implement-feature

Referenced from `skills/implement-feature/SKILL.md`. Load-bearing orchestrator
guard. Changes here are contract edits — Phase 7 implementation MUST preserve
XML tag names, the THIN CONTROLLER identifier, the dispatched_at + overlay +
dispatch_witness pre-dispatch write contract, and ALL red-flag rows.

<PREFLIGHT>
## PRE-FLIGHT PROBE -- DO THIS BEFORE READING ANY OTHER SECTION.

Before evaluating the orchestration contract below, you MUST verify the plugin
install integrity. Execute this Bash probe; the PROBE path is depth-correct
relative to this guard-block.md file's own directory (`skills/{name}/data/`,
which is depth-3 from plugin root, so 3 up-levels are required):

```bash
PROBE="../../../core/mcp-preflight.md"
if [ ! -r "$PROBE" ]; then
  echo "ABORT: plugin-root not resolved -- core/ sibling of skills/ not found at $PROBE. Check plugin install integrity." >&2
  exit 2
fi
```

If the probe fails, ABORT the pipeline with exit code 2 and the canonical
message above. DO NOT silently fall back to "I'll work from SKILL.md + step
files directly." Silent degradation is the failure mode this guard
exists to prevent.

**Path-format note (B3 documentary clarifier -- informational, not executable):**
All `core/<file>.md` references in this skill use relative paths from the file's
directory: `../core/` for `agents/*.md`, `../../core/` for `skills/*/SKILL.md`,
and `../../../core/` for `skills/*/{steps,data}/*.md`. The canonical layout is
`core/` as sibling of `skills/` at plugin root.
</PREFLIGHT>

<MANDATORY-EXECUTION-GUARD>
## YOU MUST EXECUTE THE PIPELINE. NO EXCEPTIONS.

DO NOT answer the user's question directly.
DO NOT skip a step because "the spec-analyst already wrote AC" or "the test will pass".
DO NOT reason about the feature domain — subagents do that.
DO NOT bypass spec-analyst, architect, test-engineer, or acceptance-gate based
on intuition that they "seem optional given the project config".

You are a THIN CONTROLLER. Your ONLY job is to:
1. Initialize `.agent-flow/{ISSUE_ID}/` and `state.json`
2. Read `steps/*.md` files via the Read tool — they contain the dispatch logic
3. Resolve + inject Agent Overrides BEFORE each Task — run the injector from
   `../../../core/agent-override-injector.md` for the step's `subagent_type`, append the
   rendered `## Project-Specific Instructions` block to the agent prompt, and record
   `stages.<stage>.overlay_source` + `overlay_digest` in `state.json`. NOT optional, NOT
   skippable: it is part of the same pre-dispatch ritual as the witness write. The overlay is
   now bound INTO the witness, so a skipped injection no longer hides — but `overlay_source`
   remains the explicit signal that a `customization/<agent>.toml` actually reached the prompt.
4. Compute `dispatch_witness` WITH the resolved overlay inputs, then write atomic state.json
   updates (dispatched_at + overlay fields + dispatch_witness BEFORE each Task)
5. Dispatch each step's Task() call exactly as the step file specifies
6. Surface dispatch-audit log anomalies in the final terminal report

<orchestration_contract>
YOU — the top-level Claude executing `/implement-feature` — ARE the orchestrator.
You run the pipeline directly: read state, dispatch step subagents, write
checkpoints. You never "hand the pipeline off" to another agent.

For each step you SHALL invoke the Task tool with the `subagent_type` listed in
the corresponding `steps/{NN}-*.md` file. Before invoking Task, you SHALL, in this
ORDER: (1) run the Agent Override Injector (`../../../core/agent-override-injector.md`) to
resolve `overlay_source` (`toml` | `none` | `md_rejected`) and its rendered overlay
block; (2) compute `overlay_digest` via
`core/lib/stage-invariant.sh::compute_overlay_digest`; (3) compute
`dispatch_witness` WITH the overlay inputs; (4) write atomically (ONE write) to
`state.json`:
  - `stages.<stage>.dispatched_at`     = `<ISO-8601 UTC now>`
  - `stages.<stage>.agent_name`        = `agent-flow:<agent>`
  - `stages.<stage>.stage_name`        = `<stage>` (canonical, matches map key)
  - `stages.<stage>.prompt_head_128`   = `<first 128 UTF-8-safe bytes of the raw prompt template>`
  - `stages.<stage>.overlay_source`    = `<toml | none | md_rejected>`
  - `stages.<stage>.overlay_digest`    = `<sha256 hex of rendered block | "none" | "md_rejected">`
  - `stages.<stage>.dispatch_witness`  = sha256("<subagent_type>|<model>|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  - `stages.<stage>.status`            = `"in_progress"`

Then (5) append the rendered overlay block to the prompt and invoke Task.

`overlay_source` above is the injector's result — you cannot write it truthfully without having
run the injector, and it is now bound into the witness. The injector NEVER blocks (a missing/failed
overlay yields `overlay_source=none` + the bare prompt), but it MUST run on every dispatch: a
`customization/<subagent_type>.toml` that exists but never reaches the prompt is a CONTRACT VIOLATION.

`prompt_head_128` is the first 128 UTF-8-safe bytes of the prompt template
BEFORE Tier-1 variable substitution (ISSUE_ID, AC, BRANCH_NAME, etc.).
`overlay_digest` is `none`/`md_rejected` for those overlay sources, else the
sha256 hex of the rendered overlay block. Compute the witness via the 6-arg
`core/lib/stage-invariant.sh::compute_dispatch_witness STAGE SUBAGENT_TYPE MODEL
PROMPT_HEAD_128 OVERLAY_SOURCE OVERLAY_DIGEST` — the overlay is resolved BEFORE
the witness so the receipt binds the overlay actually applied. The orchestrator
SHALL ALSO inject `EXPECTED_AGENT_NAME` and `EXPECTED_STAGE_NAME` as Tier-1
prompt variables so the agent's `## Step Completion Invariants` self-check can
cross-verify the state.json record.

The PostToolUse hook reads these fields and emits `WITNESS_OK` /
`WITNESS_MISSING` / `WITNESS_MISMATCH` audit lines to
`.agent-flow/dispatch-audit.log`. If a stage record lacks `dispatch_witness`,
the orchestrator silently skipped the step — that is a CONTRACT VIOLATION.
</orchestration_contract>

<rationalization_red_flags>
## Rationalization Red Flags — STOP IMMEDIATELY

| Behavior in draft response | Reality |
|----------------------------|---------|
| Draft frames `spec-analyst` as redundant ("AC are already in the issue body") | spec-analyst extracts AC into the canonical EARS-like form, writes them back to the tracker, and emits the `acceptance_criteria` array all downstream agents consume. Reviewer cannot substitute. Dispatch. |
| Draft frames `architect` as ceremonial ("scope is tiny — just write the code") | architect produces the task tree with `maps_to` AC traceability. Decomposition decision (Step 03) depends on its output. Skipping it leaves AC coverage unchecked. Dispatch. |
| Draft skips `decomposition` because "this feature is obviously single-pass" | The decomposition heuristic is config-gated AND data-driven — read `decompose_mode` and architect output via `../../../core/decomposition-heuristics.md`. Write `decomposition.decision = "SINGLE_PASS"` explicitly. Never leave the stage at "pending". |
| Draft frames `test-engineer` as redundant ("fixer already wrote tests") | Tests written by fixer are unit-level for the diff; test-engineer runs the full suite and may find regressions in untouched modules. Dispatch. |
| Draft skips `acceptance_gate` because "single-pass with AC<3 — config says skip" | The AC<3 threshold is evaluated by `steps/07-acceptance-gate.md`, NOT in this controller. Read the step file, let it decide, and write `acceptance_gate.status = "skipped"` explicitly if the threshold is not met. Decomposition mode ALWAYS runs the gate. |
| Draft jumps to `publisher` after fixer-reviewer loop without reading `steps/06-test.md` | The dispatch table is the contract. Read each step file before dispatching. |
| Draft cites "pipeline is nearly done" as justification | Distance-to-completion is not a dispatch gate. The gate is the step file's config-evaluation logic. Dispatch or explicitly skip. |
| Draft inserts an inline `Task()` call without first resolving the overlay and writing `dispatched_at` + overlay fields + `dispatch_witness` | Pre-dispatch overlay resolution + write is MANDATORY. If you cannot write the witness, you cannot dispatch. |
| Draft dispatches an agent without first resolving `customization/<agent>.toml` (the step file's "Agent Override injection" section), treating it as a skippable sub-heading | The override injector runs on EVERY dispatch — fixer, reviewer, browser-agent, test-engineer, analyst, publisher, all of them. The overlay is now bound into the `dispatch_witness` (via `overlay_source` + `overlay_digest`), and `stages.<stage>.overlay_source` is the explicit proof-of-execution: write it, which forces you to have run the injector. If a `customization/<agent>.toml` exists and its rendered `## Project-Specific Instructions` block is not in the dispatched prompt, the project's configuration was silently ignored. STOP and run the injector before dispatching. |
| Draft pretends "PostToolUse validator will catch it" as fallback | The hook is ADVISORY by default (exit 0). It emits audit lines but does NOT block. Subagent contracts and your own state.json writes are the enforcement. |
| Draft drifts off the dispatch table mid-run (user gives narrow scope, /implement-feature deviates to direct implementation) and then wraps up by staging + committing + pushing + opening a PR via direct `git` / `gh` / `mcp__gitea__create_pull_request` calls instead of dispatching the publisher agent at step 08 | The publisher agent IS the contract — it applies the PR labels (per `PR Rules` in Automation Config), uses the PR description template, writes the tracker traceability comment, and triggers the post-publish hook. Direct VCS calls bypass all of this AND leave step 08 with `WITNESS_MISSING`. Also: deviating from the pipeline does NOT inherit `--yolo` semantics — `--yolo` only authorizes the registered dispatch table (publisher step 08), not arbitrary direct VCS/MCP actions. The host system-prompt rule (`Only create commits when requested by the user`) still applies, and the spec/decomposition checkpoints you skipped by drifting were the user-consent gates. Before any `git add` / `git commit` / `git push` / `gh pr create` / `mcp__gitea__create_pull_request` / `mcp__github__create_pull_request`, STOP and ask the user for explicit authorization — do not proceed with any VCS action without it. |

The ONLY pre-dispatch user interaction permitted is the existing pause/resume
prompt in `../../../core/resume-detection.md`. Any other question, summary, or options
menu BEFORE the first Task dispatch is a guard violation.
</rationalization_red_flags>
</MANDATORY-EXECUTION-GUARD>
