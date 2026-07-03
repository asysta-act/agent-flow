# Step 10 — Pre-publish hook + custom agent

Run optional pre-publish hook (Bash command) and optional pre-publish custom agent (Task).

This step is NOT a Task() dispatch by itself — it conditionally runs a configured hook command
and/or invokes a custom agent. It is part of the orchestrator's infrastructure (no `pre_publish`
canonical stage exists), so no `dispatch_witness` write is required at this level. If a custom agent
IS invoked, that custom agent's own state record (under its own stage key) follows the standard
pre-dispatch witness protocol.

## Skip condition

If neither `Hooks → Pre-publish` nor `Custom Agents → Pre-publish agent` is configured in
Automation Config → skip this entire step, continue to step 11.

## Pre-publish Bash hook

If `Hooks → Pre-publish` is set in Automation Config:
- Run the configured command via Bash, in the project root.
- Stream stdout/stderr to `.agent-flow/{ISSUE-ID}/pre-publish-hook.log`.
- Failure (non-zero exit) → proceed to Block handler (step X).
  Block context: agent = `pre-publish-hook`, step = `pre-publish hook`, detail = last 1000 chars of log.

## Pre-publish custom agent

If `Custom Agents → Pre-publish agent` is set in Automation Config:

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`. If `{Agent Overrides path}/<custom-agent>.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

1. Read the agent definition from the path in config (e.g., `customization/agents/security-review.md`).
2. Read the agent's frontmatter to determine the model.
3. Atomically write per-stage pre-dispatch fields to `.agent-flow/{ISSUE-ID}/state.json` under the
   custom stage key (default: `pre_publish_custom`):
   - `pre_publish_custom.started_at`      = current ISO-8601 UTC timestamp
   - `pre_publish_custom.model`           = `<agent's frontmatter model>`
   - `pre_publish_custom.status`          = `"in_progress"`
   - `pre_publish_custom.agent_name`      = `<custom agent name from frontmatter>`
   - `pre_publish_custom.stage_name`      = `"pre_publish_custom"`
   - `pre_publish_custom.dispatched_at`   = current ISO-8601 UTC timestamp
   - `pre_publish_custom.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template
   - `pre_publish_custom.overlay_source`  = `toml` | `none` | `md_rejected` (resolve the Agent Override overlay FIRST)
   - `pre_publish_custom.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
   - `pre_publish_custom.dispatch_witness` = sha256("<agent_name>|<model>|<prompt_head_128>|<overlay_source>|<overlay_digest>")
     (compute via the 6-arg `compute_dispatch_witness pre_publish_custom <agent_name> <model> <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness)
4. Invoke `Task(subagent_type=<custom-agent>, model=<model>)` with the agent's full body as system prompt
   plus the standard Tier-1 variables (`EXPECTED_AGENT_NAME`, `EXPECTED_STAGE_NAME`), appending the rendered overlay block to the prompt.
5. After dispatch, write `pre_publish_custom.completed_at`, `pre_publish_custom.tokens_used`,
   `pre_publish_custom.duration_ms`, `pre_publish_custom.tool_uses`.

Outcome handling:
- Agent output begins with `BLOCK:` → proceed to Block handler (step X).
- Otherwise → continue to step 11 (publish).

## State update

Update `.agent-flow/{ISSUE-ID}/state.json`: set the appropriate sub-statuses to `"completed"` (or
`"skipped"` if a sub-step was skipped). Follow atomic write protocol from `../../../core/state-manager.md`.
