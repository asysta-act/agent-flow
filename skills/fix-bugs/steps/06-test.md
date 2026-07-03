# Step 06 — Test-engineer

Dispatch `test-engineer` to write new tests covering the fix and run the full suite.

## Skip condition

If stage `test-engineer` is in the profile's Skip stages → skip, record `[SKIP] test-engineer (profile: {name})`.

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:

- `test.started_at`      = current ISO-8601 UTC timestamp
- `test.model`           = `"sonnet"` (from `agents/test-engineer.md` frontmatter)
- `test.status`          = `"in_progress"`
- `test.agent_name`      = `"agent-flow:test-engineer"`
- `test.stage_name`      = `"test"`
- `test.dispatched_at`   = current ISO-8601 UTC timestamp
- `test.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template (BEFORE Tier-1 variable injection of EXPECTED_AGENT_NAME / EXPECTED_STAGE_NAME / Max test attempts)
- `test.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST, see "Agent Override injection" below)
- `test.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `test.dispatch_witness` = sha256("agent-flow:test-engineer|sonnet|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness test agent-flow:test-engineer sonnet <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness)
- `test.tokens_used`     = 0, `test.duration_ms` = 0, `test.tool_uses` = 0

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single
atomic replace. Then append the rendered overlay block to the prompt and dispatch.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/test-engineer.toml` exists, append its rendered Markdown content to the
agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:test-engineer', model='sonnet')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject the following Tier-1 variables into the prompt template:
- `EXPECTED_AGENT_NAME = "agent-flow:test-engineer"`
- `EXPECTED_STAGE_NAME = "test"`

Context for the agent:
```
Max test attempts = {Test attempts from config}.
EXPECTED_AGENT_NAME = agent-flow:test-engineer
EXPECTED_STAGE_NAME = test
```

Loop: max {Test attempts} attempts. Attempts exhausted → Block handler (step X).

## Post-dispatch state write

After dispatch returns, atomically write per-stage post-dispatch fields:
- `test.completed_at` = current ISO-8601 UTC timestamp
- `test.tokens_used`  = `result.usage.total_tokens` (or 0 if absent)
- `test.duration_ms`  = `test.completed_at` epoch ms − `test.started_at` epoch ms
- `test.tool_uses`    = `result.usage.tool_uses` (or 0 if absent)

Set `test.status` to `"completed"` (or `"blocked"` on failure), increment `test.attempts`,
set `test.last_result` to `"PASSED"` or `"FAILED"`. Follow atomic write protocol.

## Step-completed webhook

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"test","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.
