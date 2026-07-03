# Step 11 — Publish

Dispatch `publisher` to create the PR and update the issue tracker.

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:

- `publisher.started_at`      = current ISO-8601 UTC timestamp
- `publisher.model`           = `"haiku"` (from `agents/publisher.md` frontmatter)
- `publisher.status`          = `"in_progress"`
- `publisher.agent_name`      = `"agent-flow:publisher"`
- `publisher.stage_name`      = `"publisher"`
- `publisher.dispatched_at`   = current ISO-8601 UTC timestamp
- `publisher.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template
- `publisher.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST, see "Agent Override injection" below)
- `publisher.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `publisher.dispatch_witness` = sha256("agent-flow:publisher|haiku|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness publisher agent-flow:publisher haiku <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness)
- `publisher.tokens_used` = 0, `publisher.duration_ms` = 0, `publisher.tool_uses` = 0

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single atomic
replace. Then append the rendered overlay block to the prompt and dispatch.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/publisher.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:publisher', model='haiku')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:publisher"`,
`EXPECTED_STAGE_NAME = "publisher"`.

Context for the agent:
```
EXPECTED_AGENT_NAME = agent-flow:publisher
EXPECTED_STAGE_NAME = publisher
Type = {Type from config}. Use the MCP server for {Type}.
```

## Post-dispatch state write

After dispatch, write per-stage post-dispatch fields to `.agent-flow/{ISSUE-ID}/state.json`:
- `publisher.completed_at` = current ISO-8601 UTC timestamp
- `publisher.tokens_used` = `result.usage.total_tokens` (or 0 if absent)
- `publisher.duration_ms` = `publisher.completed_at` epoch ms − `publisher.started_at` epoch ms
- `publisher.tool_uses` = `result.usage.tool_uses` (or 0 if absent)

Set `publisher.status = "completed"`, write `publisher.pr_url`, `publisher.branch`.
Follow atomic write protocol from `../../../core/state-manager.md`.

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"publisher","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.

## Post-publish hook

Follow `../../../core/post-publish-hook.md` for hook execution and webhook firing.

If Hooks → Post-publish exists:
- Run the command via Bash.
- Failure → warning only (PR already exists, cannot rollback).

## Fix Verification (optional)

Follow `../../../core/fix-verification.md` for post-merge verification.

If Build & Test → Verify exists in Automation Config:
1. Wait for PR merge (max 5 attempts, 30s interval). Not merged → warn, skip.
2. Checkout base branch and pull.
3. Run the Verify command.
4. OK → add comment: `[agent-flow] ✅ Fix verified. Verify command: {command}. Output: {first 500 chars}.`
5. FAIL → add comment, re-open issue.

After all post-publish work completes, continue to step 12 (terminal result + dispatch-audit
surfacing). Pipeline accumulator and terminal `status` write live in step 12.
