# Step 09 — Acceptance Gate (conditional)

Dispatch `acceptance-gate` to verify AC fulfillment with code + test evidence.
This step is CONDITIONAL — evaluate skip condition first.

## Condition

Run this step ONLY when **either** of the following is true:
- Bug has ≥ 3 acceptance criteria (from triage output), OR
- Bug complexity ≥ M (from triage output: complexity is `M` or `L`)

If condition is not met → skip to step 07, log `[SKIP] acceptance-gate (AC={count}, complexity={cx})`.

In `--yolo` mode: skip this step entirely (no acceptance-gate prompt regardless of AC count or complexity).

## Pre-dispatch hooks

If Hooks → Pre-publish exists in Automation Config:
- Run the command via Bash. Failure → Block handler (step X).

If Custom Agents → Pre-publish agent exists:
- Run as Task. BLOCK → Block handler (step X).

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:

- `acceptance_gate.started_at`      = current ISO-8601 UTC timestamp
- `acceptance_gate.model`           = `"sonnet"` (from `agents/acceptance-gate.md` frontmatter)
- `acceptance_gate.status`          = `"in_progress"`
- `acceptance_gate.agent_name`      = `"agent-flow:acceptance-gate"`
- `acceptance_gate.stage_name`      = `"acceptance_gate"`
- `acceptance_gate.dispatched_at`   = current ISO-8601 UTC timestamp
- `acceptance_gate.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template
- `acceptance_gate.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST, see "Agent Override injection" below)
- `acceptance_gate.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `acceptance_gate.dispatch_witness` = sha256("agent-flow:acceptance-gate|sonnet|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness acceptance_gate agent-flow:acceptance-gate sonnet <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness)
- `acceptance_gate.tokens_used` = 0, `acceptance_gate.duration_ms` = 0, `acceptance_gate.tool_uses` = 0

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single atomic
replace. Then append the rendered overlay block to the prompt and dispatch.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/acceptance-gate.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:acceptance-gate', model='sonnet')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:acceptance-gate"`,
`EXPECTED_STAGE_NAME = "acceptance_gate"`.

Context for the agent:
```
EXPECTED_AGENT_NAME = agent-flow:acceptance-gate
EXPECTED_STAGE_NAME = acceptance_gate
Acceptance criteria: {AC from triage}.
Changed files: {list of files modified by fixer}.
Test report: {test-engineer output from step 06}.
```

## Outcome handling

- `REQUEST_CHANGES` → return to fixer (step 04). Counts toward the same Fixer iterations limit.
- `APPROVE` → continue to step 10 (pre-publish hook).

## Post-dispatch state write

After dispatch, write per-stage post-dispatch fields to `.agent-flow/{ISSUE-ID}/state.json`:
- `acceptance_gate.completed_at` = current ISO-8601 UTC timestamp
- `acceptance_gate.tokens_used` = `result.usage.total_tokens` (or 0 if absent)
- `acceptance_gate.duration_ms` = `acceptance_gate.completed_at` epoch ms − `acceptance_gate.started_at` epoch ms
- `acceptance_gate.tool_uses` = `result.usage.tool_uses` (or 0 if absent)

Set `acceptance_gate.status` to `"completed"` (or `"skipped"` if condition not met),
write `acceptance_gate.verdict`. Follow atomic write protocol from `../../../core/state-manager.md`.

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"acceptance_gate","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.
