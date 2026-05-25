# Mandatory Execution Guard — /scaffold

<!--
  Referenced from `skills/scaffold/SKILL.md`.
  Load-bearing orchestrator guard. Changes here are contract edits.
  Mirrors precedent at skills/fix-bugs/data/guard-block.md and
  skills/implement-feature/data/guard-block.md.
-->

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
DO NOT skip a step because "the spec-writer already covered it" or "the scaffolder will pick this up."
DO NOT reason about the project domain -- subagents do that.
DO NOT bypass spec-writer, spec-reviewer, scaffolder, architect, fixer-reviewer,
test-engineer, or spec-reviewer --verify based on intuition.
DO NOT inline-execute step logic -- every step is a Task() dispatch.

You are a THIN CONTROLLER. Your ONLY job is to:
1. Initialize `.agent-flow/{PROJECT_ID}/` and `state.json`
2. Read `steps/NN-*.md` files via the Read tool -- they contain the dispatch logic
3. Dispatch each step's Task() call exactly as the step file specifies
4. Write atomic `state.json` updates (`dispatched_at` + `dispatch_witness` BEFORE each Task)
5. Surface dispatch-audit log anomalies in the final terminal report

<orchestration_contract>
YOU -- the top-level Claude executing /agent-flow:scaffold -- ARE the orchestrator.
You run the pipeline directly: read state, dispatch step subagents, write
checkpoints. You never "hand the pipeline off" to another agent.

For each step you SHALL invoke the Task tool with the `subagent_type` listed in
the corresponding `steps/NN-*.md` file. Before invoking Task, you SHALL write
atomically to `.agent-flow/{PROJECT_ID}/state.json`:

  - `stages.<stage>.dispatched_at`   = <ISO-8601 UTC now>
  - `stages.<stage>.dispatch_witness` = sha256("<subagent_type>|<model>|<prompt_head_128>")
  - `stages.<stage>.agent_name`      = <subagent_type>
  - `stages.<stage>.stage_name`      = <canonical stage name>
  - `stages.<stage>.status`          = "in_progress"

`prompt_head_128` is the first 128 UTF-8-safe bytes of the prompt template
BEFORE Tier-1 variable substitution. Compute via
`../../../core/lib/stage-invariant.sh::compute_dispatch_witness`.

You SHALL also inject `EXPECTED_AGENT_NAME=<value>` and
`EXPECTED_STAGE_NAME=<value>` as Tier-1 variables in the agent prompt so the
subagent can self-verify its dispatch invariants.

The PostToolUse hook reads these fields and emits WITNESS_OK | WITNESS_MISSING
| WITNESS_MISMATCH audit lines to `.agent-flow/dispatch-audit.log`. If a stage
record lacks `dispatch_witness`, the orchestrator silently skipped the step --
that is a CONTRACT VIOLATION that the final step will surface in the terminal report.
</orchestration_contract>

<rationalization_red_flags>
## Rationalization Red Flags -- STOP IMMEDIATELY

| Behaviour in draft response | Reality |
|-----------------------------|---------|
| Draft frames spec-reviewer as redundant ("spec-writer's output is clean") | spec-reviewer catches assumptions, contradictions, and EARS-form violations that spec-writer's draft misses. Dispatch. |
| Draft skips architect because "scope is obvious from spec" | architect produces the maps_to task tree linking subtasks to AC. Decomposition (Step 03) depends on it. Dispatch. |
| Draft frames spec-reviewer --verify as ceremonial ("we tested it manually") | spec-reviewer --verify runs the compliance check against the locked spec. Manual testing cannot substitute. Dispatch. |
| Draft skips test-engineer --e2e because "no e2e framework configured" | Read `### E2E Test` in Automation Config; if absent, write `e2e_test.status = "skipped"` -- DO NOT leave at "pending". |
| Draft jumps to final report after fixer-reviewer without running test-engineer | The dispatch table is the contract. Read each step file before dispatching. |
| Draft inserts inline Task() without writing `dispatched_at` + `dispatch_witness` | Pre-dispatch write is MANDATORY. If you cannot write the witness, you cannot dispatch. |
| Draft pretends "PostToolUse validator will catch it" as fallback | The hook is ADVISORY by default (exit 0). It emits audit lines but does NOT block. |
| Draft drifts off the dispatch table mid-run (user narrows scope, /scaffold deviates to direct file creation) and then wraps up by `git init` + staging + committing + pushing + creating tracker issues via direct `git` / `gh` / `mcp__gitea__*` / `mcp__youtrack__issue_create` calls instead of dispatching the scaffolder agent's Step 4d push and Step 4e tracker-issue creation | The scaffolder + step 03 sub-stages ARE the contract — they evaluate `sc_effective_status` and `tracker_effective_status`, populate CLAUDE.md, write tracker issues with the correct project/labels, and push only when SC is `ready`. Direct VCS / tracker calls bypass these gates, ignore the user's `ready`/`later` choices, and leave the stage with `WITNESS_MISSING`. Also: deviating from the pipeline does NOT inherit `--yolo` semantics. The host system-prompt rule (`Only create commits when requested by the user`) still applies, and the spec/feature-plan checkpoints you skipped by drifting were the user-consent gates. Before any `git init` / `git add` / `git commit` / `git push` / `gh repo create` / `gh issue create` / `mcp__gitea__create_pull_request` / `mcp__youtrack__issue_create`, STOP and ask the user — or get back on the dispatch table and run the scaffolder properly. |

The ONLY pre-dispatch user interaction permitted is the existing spec checkpoint
and feature plan checkpoint in the new-project flow. Any other question,
summary, or options menu BEFORE the first Task dispatch is a guard violation.
</rationalization_red_flags>
</MANDATORY-EXECUTION-GUARD>
