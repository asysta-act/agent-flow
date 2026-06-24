# Step 06: Test Engineer

Runs test-engineer agent to write and validate tests for all implemented subtasks.
Executed per subtask within the batch loop (called from Step 05 per-subtask context),
and once more as a full-suite sweep after all batches complete.

## Per-Subtask Test Dispatch

**Pre-dispatch test (COST-R4, first attempt per subtask only):** Write to state.json:
`test.started_at`, `test.model = "sonnet"`, `test.status = "in_progress"`, counters `0`.

Check Agent Overrides: if `{Agent Overrides path}/test-engineer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

You MUST invoke Task(subagent_type='agent-flow:test-engineer', model='sonnet'). DO NOT inline-execute.
Context: changed files + acceptance_criteria + `Max test attempts = {Test attempts from CLAUDE.md, default 3}`.

After completion: run Test command from generated CLAUDE.md.

**Post-dispatch (COST-R2, COST-R3):** Defensive-read `result.usage`. Accumulate cumulatively across retry attempts:
`test.tokens_used += iteration_tokens`, `test.duration_ms += iteration_duration_ms`, `test.tool_uses += iteration_tool_uses`.

If tests fail → test-engineer fixes (max Test attempts, default 3). If still failing → Block handler (Step 05).

Update state.json: set `test.status = "completed"` (or `"blocked"`), write `test.completed_at`, increment `test.attempts`, set `test.last_result`. Atomic write.

Fire `step-completed` for `test` (after state.json write of `test.status: completed`):
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "${Webhook_URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${run_id}","step_name":"test",
 "duration":${duration_seconds},"iteration_count":${test_attempts},"timestamp":"${ISO8601_UTC}"}
EOF
```
On failure: log `[WARN] Webhook delivery failed`, continue.

## E2E Test (optional — if E2E Test section configured)

**Deployment guard (if Local Deployment section configured):**

**Pre-dispatch deployment (COST-R4):** Write `deployment.started_at`, `deployment.model = "sonnet"`, `deployment.status = "in_progress"`, counters `0`.

Check Agent Overrides: if `{Agent Overrides path}/deployment-verifier.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

You MUST invoke Task(subagent_type='agent-flow:deployment-verifier', model='sonnet'). DO NOT inline-execute.
Context: `Action: start. Local Deployment config: Type={Type}, Start={Start command}, Stop={Stop command},
Health check URL={URL}, Timeout={timeout}, Ports={Ports}. Run directory: .agent-flow/scaffold/`

**Post-dispatch:** Defensive-read `result.usage`. Write `deployment.completed_at`, tokens, duration, tool_uses. Set `deployment.status = "completed"`.

Verdict:
- `HEALTHY` or `SKIPPED` → proceed to e2e dispatch
- Any failure → `[WARN] Deployment guard failed ({verdict}). E2E tests skipped.` Skip e2e dispatch.

If Local Deployment section absent: `[WARN] Local Deployment not configured. Skipping deployment guard.`

**E2E test dispatch:**

**Pre-dispatch e2e_test (COST-R4):** Write `e2e_test.started_at`, `e2e_test.model = "sonnet"`, `e2e_test.status = "in_progress"`, counters `0`.

Check Agent Overrides: if `{Agent Overrides path}/test-engineer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md` (test-engineer handles `--e2e` flag).

You MUST invoke Task(subagent_type='agent-flow:test-engineer', model='sonnet'). DO NOT inline-execute.
Pass `--e2e` flag. Context: `spec/verification.md` test strategy + list of implemented features + AC.

**Post-dispatch:** Defensive-read `result.usage`. Write `e2e_test.completed_at`, tokens, duration, tool_uses. Set `e2e_test.status = "completed"`.

If e2e tests fail → fixer repairs → re-run (test-engineer handles retries internally).
If still failing → report as warning (do not block — features already committed).

Fire `step-completed` for `e2e_test` after state.json write.

```bash
git add -A
git commit -m "test: add E2E tests"
```

If no E2E Test config section → skip E2E dispatch entirely.
