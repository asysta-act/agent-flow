# Step 05 — Smoke Check (post-fix)

Run `build.build_command` + `build.test_command` from `.agent-flow/config.toml` to verify the codebase is sound after the
fixer-reviewer loop. This step catches regressions introduced during the fixer-reviewer iteration
that the pre-reviewer Build (inside step 04) would not have caught.

This step is NOT a Task() dispatch — it runs Bash commands directly. It is part of the orchestrator's
infrastructure (no `smoke_check` agent exists), so no `dispatch_witness` write is required.

## Pre-step state write

Before running smoke commands, write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:
- `smoke_check.started_at` = current ISO-8601 UTC timestamp
- `smoke_check.status`     = `"in_progress"`
- `smoke_check.stage_name` = `"smoke_check"`
- `smoke_check.agent_name` = `"orchestrator"` (no subagent — orchestrator-direct execution)

Follow atomic write protocol from `../../../core/state-manager.md`.

## Smoke commands

1. Run the `build.build_command` from `.agent-flow/config.toml`.
   - Failure → proceed to Block handler (step X).
     Block context: agent = `smoke-check`, step = `post-review smoke check`, detail = build error output.
2. Run the `build.test_command` from `.agent-flow/config.toml` (existing tests only — test-engineer has not run yet).
   - Failure → proceed to Block handler (step X).
     Block context: agent = `smoke-check`, step = `post-review smoke check`, detail = test error output.

## Post-step state write

On success, write:
- `smoke_check.completed_at` = current ISO-8601 UTC timestamp
- `smoke_check.duration_ms`  = completed_at epoch ms − started_at epoch ms
- `smoke_check.status`       = `"completed"`

On failure (before transitioning to Block handler), write:
- `smoke_check.status`       = `"blocked"`
- `smoke_check.last_result`  = `"FAILED"`

Follow atomic write protocol from `../../../core/state-manager.md`.

## Step-completed webhook

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"smoke_check","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.
