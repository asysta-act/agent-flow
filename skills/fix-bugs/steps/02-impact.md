# Step 02 — Impact Analysis

Dispatch `analyst --phase impact` for each bug that passed triage (OK status).

## Skip condition

If stage `analyst-impact` is in the profile's Skip stages → skip for each bug, record
`[SKIP] analyst-impact (profile: {name})`.

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:
- `code_analysis.started_at`      = current ISO-8601 UTC timestamp
- `code_analysis.model`           = `"sonnet"` (from `agents/analyst.md` frontmatter)
- `code_analysis.status`          = `"in_progress"`
- `code_analysis.agent_name`      = `"agent-flow:analyst"`
- `code_analysis.stage_name`      = `"code_analysis"`
- `code_analysis.dispatched_at`   = current ISO-8601 UTC timestamp
- `code_analysis.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template
- `code_analysis.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST, see "Agent Override injection" below)
- `code_analysis.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `code_analysis.dispatch_witness` = sha256("agent-flow:analyst|sonnet|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness code_analysis agent-flow:analyst sonnet <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness)
- `code_analysis.tokens_used` = 0, `code_analysis.duration_ms` = 0, `code_analysis.tool_uses` = 0

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single atomic replace. Then append the rendered overlay block to the prompt and dispatch.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/analyst.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:analyst', model='sonnet')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:analyst"`,
`EXPECTED_STAGE_NAME = "code_analysis"`.

Context for the agent:
```
--phase impact. Root cause iterations = {Root cause iterations from config}.
Module Docs path = {Path from Module Docs config, or "none"}.
Triage output: {full triage output for this bug}.
EXPECTED_AGENT_NAME = agent-flow:analyst
EXPECTED_STAGE_NAME = code_analysis
```

## Post-dispatch state write

After dispatch, write per-stage post-dispatch fields to `.agent-flow/{ISSUE-ID}/state.json`:
- `code_analysis.completed_at` = current ISO-8601 UTC timestamp
- `code_analysis.tokens_used` = `result.usage.total_tokens` (or 0 if absent)
- `code_analysis.duration_ms` = `code_analysis.completed_at` epoch ms − `code_analysis.started_at` epoch ms
- `code_analysis.tool_uses` = `result.usage.tool_uses` (or 0 if absent)

Follow atomic write protocol from `../../../core/state-manager.md`.

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"code_analysis","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.

## Outcome handling

If the impact report contains `root cause confirmed: NO` → proceed to Block handler (step X) with
recommendation: "Root cause not confirmed by analyst. See partial report for details. Recommend human
investigation."

*If dry-run → stop here, proceed to Dry-run report.*

## Decompose flag parsing

Parse `$ARGUMENTS` for decompose flags:
- `--decompose` (without `--no-decompose`): `decompose_mode = FORCE`
- `--no-decompose`: `decompose_mode = DISABLED`
- Neither: `decompose_mode = AUTO`

## Decomposition decision (per-bug)

Follow `../../../core/decomposition-heuristics.md` to determine DECOMPOSE vs SINGLE_PASS.

If `decompose_mode = DISABLED` → skip to step 03/pre-fix.
Update `state.json`: set `decomposition.status` to `"completed"`, `decomposition.decision` to
`"SINGLE_PASS"`, `decomposition.strategy` to `null`. Follow atomic write protocol from
`../../../core/state-manager.md`.

If `decompose_mode = FORCE` or `decompose_mode = AUTO`:

Evaluate the analyst output:
- `risk == HIGH` → DECOMPOSE
- `affected_files >= 4` → DECOMPOSE
- `estimated_diff_lines > 60 AND affected_files >= 3` → DECOMPOSE
- `independent_changes >= 2` → DECOMPOSE
- Otherwise and `decompose_mode = AUTO` → SINGLE_PASS (skip to step 03/pre-fix)
- Otherwise and `decompose_mode = FORCE` → DECOMPOSE

If DECOMPOSE:

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/architect.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

- You MUST invoke `Task(subagent_type='agent-flow:architect', model='opus')`. DO NOT inline-execute.
  Context: analyst impact report + issue details + `Module Docs path = {Path or "none"}`.
  Instructions: "Decompose this bug into subtasks. Max {max_subtasks} subtasks."
  Output: task tree (YAML).
- Validate task tree (see implement-feature step 3).
- Display plan and wait for confirmation.
- Write task tree to `.claude/decomposition/{ISSUE-ID}.yaml`.
- Update `state.json`: set `decomposition.status = "completed"`, write `decomposition.decision`,
  `decomposition.strategy`, `decomposition.subtasks` list. Follow atomic write protocol.
- Run subtask execution (see `../../../core/decomposition-heuristics.md`). After subtask execution completes,
  skip to step 07-publish.

## State update (end of step)

Update `.agent-flow/{ISSUE-ID}/state.json`: set `code_analysis.status` to `"completed"`,
write `code_analysis.risk`, `code_analysis.affected_files`,
`code_analysis.estimated_diff_lines`. Follow atomic write protocol from `../../../core/state-manager.md`.
