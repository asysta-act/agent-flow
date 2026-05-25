# Mandatory Execution Guard — /fix-bugs

<!--
  Referenced from `skills/fix-bugs/SKILL.md`.
  Load-bearing orchestrator guard. Changes here are contract edits.
  Mirrors forge precedent at filip-superpowers/skills/forge/data/guard-block.md.
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
DO NOT skip a step because "the fixer already covered it" or "the test will pass."
DO NOT reason about the problem domain — subagents do that.
DO NOT bypass test-engineer, e2e_test, browser_verification, or acceptance_gate
based on intuition that they "seem optional given the project config."
DO NOT inline-execute step logic — every step is a Task() dispatch.

You are a THIN CONTROLLER. Your ONLY job is to:
1. Initialize `.agent-flow/{ISSUE_ID}/` and `state.json`
2. Read `steps/NN-*.md` files via the Read tool — they contain the dispatch logic
3. Dispatch each step's Task() call exactly as the step file specifies
4. Write atomic `state.json` updates (`dispatched_at` + `dispatch_witness` BEFORE each Task)
5. Surface dispatch-audit log anomalies in the final terminal report (step 12)

<orchestration_contract>
YOU — the top-level Claude executing /agent-flow:fix-bugs — ARE the orchestrator.
You run the pipeline directly: read state, dispatch step subagents, write
checkpoints. You never "hand the pipeline off" to another agent.

For each step you SHALL invoke the Task tool with the `subagent_type` listed in
the corresponding `steps/NN-*.md` file. Before invoking Task, you SHALL write
atomically to `.agent-flow/{ISSUE_ID}/state.json`:

  - `stages.<stage>.dispatched_at`   = <ISO-8601 UTC now>
  - `stages.<stage>.dispatch_witness` = sha256("<subagent_type>|<model>|<prompt_head_128>")
  - `stages.<stage>.agent_name`      = <subagent_type>
  - `stages.<stage>.stage_name`      = <canonical stage name>
  - `stages.<stage>.status`          = "in_progress"

`prompt_head_128` is the first 128 UTF-8-safe bytes of the prompt template
BEFORE Tier-1 variable substitution. Compute via
`core/lib/stage-invariant.sh::compute_dispatch_witness`.

You SHALL also inject `EXPECTED_AGENT_NAME=<value>` and
`EXPECTED_STAGE_NAME=<value>` as Tier-1 variables in the agent prompt so the
subagent can self-verify its dispatch invariants.

The PostToolUse hook reads these fields and emits WITNESS_OK | WITNESS_MISSING
| WITNESS_MISMATCH audit lines to `.agent-flow/dispatch-audit.log`. If a stage
record lacks `dispatch_witness`, the orchestrator silently skipped the step —
that is a CONTRACT VIOLATION that step 12 will surface in the terminal report.
</orchestration_contract>

<rationalization_red_flags>
## Rationalization Red Flags — STOP IMMEDIATELY

| Behaviour in draft response | Reality |
|-----------------------------|---------|
| Draft frames test-engineer as redundant ("fixer already wrote tests so test-engineer seems redundant") | Tests written by fixer are unit-level; test-engineer runs the full suite + may discover regressions in untouched modules. Dispatch. |
| Draft frames acceptance-gate as ceremonial ("AC obviously fulfilled from code review") | Acceptance-gate verifies AC against code+test evidence with a per-AC verdict. Reviewer cannot substitute. Dispatch or explicitly skip per the step file's condition. |
| Draft skips e2e_test because "all remaining steps are optional given project config" | Check Automation Config explicitly via `../../../core/config-reader.md`. If absent, write `e2e_test.status = "skipped"` — DO NOT leave at "pending". |
| Draft skips browser_verification with same rationale as e2e | Same handling: explicit `"skipped"` or dispatch, never `"pending"`. |
| Draft cites "pipeline is nearly done — skip to publisher" | Distance-to-completion is not a dispatch gate. The gate is the step file's config-evaluation logic. Dispatch or explicitly skip. |
| Draft jumps to publisher (step 11) after fixer-reviewer (step 04) without reading steps 05-10 | The dispatch table is the contract. Read each step file before dispatching. |
| Draft inserts an inline Task() call without first writing `dispatched_at` + `dispatch_witness` | Pre-dispatch write is MANDATORY. If you cannot write the witness, you cannot dispatch. |
| Draft pretends "PostToolUse validator will catch it" as fallback | The hook is ADVISORY by default (exit 0). It writes audit lines but does NOT block. Subagent contracts and your own state.json writes are the enforcement. |
| Draft drifts off the dispatch table mid-run (user gives narrow scope, /fix-bugs deviates to direct implementation) and then wraps up by staging + committing + pushing + opening a PR on its own | The publisher gate in SKILL.md (`Publisher (step 11) is NOT called automatically in single mode — the user decides; --yolo auto-publishes`) and the host system-prompt rule (`Only create commits when requested by the user`) BOTH still apply when you deviate. Deviating from the pipeline does NOT inherit `--yolo` semantics. Before any `git add` / `git commit` / `git push` / `gh pr create` / `mcp__gitea__create_pull_request`, STOP and ask the user. The default is "ask first," not "wrap up by publishing." |

The ONLY pre-dispatch user interaction permitted is the existing pause/resume
prompt in Step 0b (resume detection). Any other question, summary, or options
menu BEFORE the first Task dispatch is a guard violation.
</rationalization_red_flags>
</MANDATORY-EXECUTION-GUARD>
