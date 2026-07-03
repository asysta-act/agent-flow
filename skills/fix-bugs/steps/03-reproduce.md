# Step 03 — Browser Reproduction (conditional)

Dispatch `browser-agent --phase reproduce`. This step is CONDITIONAL — evaluate skip conditions first.

## Skip conditions

Skip this entire step if ANY of the following is true:
- `browser_verification_enabled = false` (Browser Verification section absent from Automation Config)
- `browser_reproduce = false` (`On events` in Browser Verification config does NOT contain `reproduce`)
- Stage `browser-agent-reproduce` is in the profile's Skip stages

When skipping: log `[SKIP] browser reproduction ({reason})`, update state, continue to step 04.

Also skip if step 02 resulted in decomposition + subtask execution path (those subtasks handle their
own reproduction context internally).

## Pre-dispatch hook (pre-fix hook)

Before dispatching browser-agent: run Pre-fix hook if configured.

If Hooks → Pre-fix exists in Automation Config:
- Run the command via Bash in the context of the given bug.
- Failure → Block (issue comment per Block Comment Template, continue with next bug).

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:
- `reproduction.started_at`      = current ISO-8601 UTC timestamp
- `reproduction.model`           = `"sonnet"` (from `agents/browser-agent.md` frontmatter)
- `reproduction.status`          = `"in_progress"`
- `reproduction.agent_name`      = `"agent-flow:browser-agent"`
- `reproduction.stage_name`      = `"reproduce_browser"`
- `reproduction.dispatched_at`   = current ISO-8601 UTC timestamp
- `reproduction.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template
- `reproduction.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST, see "Agent Override injection" below)
- `reproduction.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `reproduction.dispatch_witness` = sha256("agent-flow:browser-agent|sonnet|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness reproduce_browser agent-flow:browser-agent sonnet <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness)
- `reproduction.tokens_used` = 0, `reproduction.duration_ms` = 0, `reproduction.tool_uses` = 0

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single atomic replace. Then append the rendered overlay block to the prompt and dispatch.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/browser-agent.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:browser-agent', model='sonnet')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:browser-agent"`,
`EXPECTED_STAGE_NAME = "reproduce_browser"`.

Context for the agent:
```
--phase reproduce.
EXPECTED_AGENT_NAME = agent-flow:browser-agent
EXPECTED_STAGE_NAME = reproduce_browser
Issue: {issue ID and title}.
Bug description: {issue description}.
Triage output: {full triage output including reproduction_steps if present}.
Impact report: {analyst --phase impact output}.
Browser Verification config: Base URL = {Base URL}, Start command = {Start command or "none"},
  Stop command = {Stop command or "none"}, Timeout = {Timeout}, Screenshot storage = {Screenshot storage}.
```

## Post-dispatch state write

After dispatch, write per-stage post-dispatch fields to `.agent-flow/{ISSUE-ID}/state.json`:
- `reproduction.completed_at` = current ISO-8601 UTC timestamp
- `reproduction.tokens_used` = `result.usage.total_tokens` (or 0 if absent)
- `reproduction.duration_ms` = `reproduction.completed_at` epoch ms − `reproduction.started_at` epoch ms
- `reproduction.tool_uses` = `result.usage.tool_uses` (or 0 if absent)

Follow atomic write protocol from `../../../core/state-manager.md`.

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"reproduction","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.

## Outcome handling

- `status: skipped` → log `[SKIP] browser reproduction ({reason})`, continue pipeline.
- `status: not_reproduced` → log `[INFO] browser reproduction: could not reproduce bug`, continue pipeline.
- `status: reproduced` → log `[INFO] browser reproduction: bug reproduced. Evidence attached for fixer.`
  Store full `.agent-flow/{ISSUE-ID}/reproduction-result.json` content for fixer context in step 04.

NEVER block on any browser-agent reproduce outcome.

## State update (end of step)

Update `.agent-flow/{ISSUE-ID}/state.json`: set `reproduction.status` to `"completed"` (or `"skipped"`
if skipped), write `reproduction.verdict`, `reproduction.result_path`. Follow atomic write protocol
from `../../../core/state-manager.md`.
