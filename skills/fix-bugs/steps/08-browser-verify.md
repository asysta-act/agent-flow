# Step 08 — Browser Verification (config-gated)

Dispatch `browser-agent --phase verify` to replay the bug-reproduction flow against the fixed
code and confirm the bug is resolved at the UI level. This step is CONDITIONAL.

## Skip conditions

Skip this entire step if ANY of the following is true:
- `browser_verification_enabled = false` (Browser Verification section absent from Automation Config)
- `browser_verify = false` (`On events` in Browser Verification config does NOT contain `verify`)
- Stage `browser-agent-verify` is in the profile's Skip stages

When skipping: log `[SKIP] browser verification ({reason})`, set
`browser_verification.status = "skipped"` in state.json (NEVER leave at `"pending"`), continue to step 09.

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:

- `browser_verification.started_at`      = current ISO-8601 UTC timestamp
- `browser_verification.model`           = `"sonnet"` (from `agents/browser-agent.md` frontmatter)
- `browser_verification.status`          = `"in_progress"`
- `browser_verification.agent_name`      = `"agent-flow:browser-agent"`
- `browser_verification.stage_name`      = `"browser_verification"`
- `browser_verification.dispatched_at`   = current ISO-8601 UTC timestamp
- `browser_verification.dispatch_witness` = sha256("agent-flow:browser-agent|sonnet|<prompt_head_128>")
- `browser_verification.tokens_used` = 0, `browser_verification.duration_ms` = 0, `browser_verification.tool_uses` = 0

Follow atomic write protocol from `../../../core/state-manager.md`.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/browser-agent.toml` exists, append its rendered Markdown content to the
agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:browser-agent', model='sonnet')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:browser-agent"`,
`EXPECTED_STAGE_NAME = "browser_verification"`.

Context for the agent:
```
--phase verify.
EXPECTED_AGENT_NAME = agent-flow:browser-agent
EXPECTED_STAGE_NAME = browser_verification
Browser Verification config: {full config section — Base URL, Start command, Stop command, On events, Timeout, Max pages, Exploration, Exploration max clicks}.
Reproduction result: {contents of .agent-flow/{ISSUE-ID}/reproduction-result.json or
                       "browser-agent reproduce was skipped"}.
Fixer diff: {git diff HEAD~1}.
Acceptance criteria: {AC from triage}.
```

## Post-dispatch state write

After dispatch returns, atomically write per-stage post-dispatch fields:
- `browser_verification.completed_at` = current ISO-8601 UTC timestamp
- `browser_verification.tokens_used`  = `result.usage.total_tokens` (or 0 if absent)
- `browser_verification.duration_ms`  = completed_at epoch ms − started_at epoch ms
- `browser_verification.tool_uses`    = `result.usage.tool_uses` (or 0 if absent)

Set `browser_verification.status` to `"completed"` (or `"skipped"` if skipped earlier),
write `browser_verification.verdict`, `browser_verification.result_path`. Follow atomic write protocol.

## Verdict handling

- `VERIFIED` → log `[PASS] browser verification`, continue to step 09.
- `PARTIAL`  → log `[WARN] browser verification partial: {observations}`, continue to step 09.
              Add observations to PR comment context.
- `SKIPPED`  → log `[SKIP] browser verification ({reason})`, continue to step 09.
- `FAILED`   → return to fixer (step 04). Counts toward the same Fixer iterations limit.
              Context for fixer: "Browser verification FAILED — bug still present. Detail: {failure detail}."
              If fixer iteration limit already exhausted → proceed directly to Block handler (step X).

## Step-completed webhook

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"browser_verification","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.
