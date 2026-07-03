# Step 06 — Test Engineer + E2E

## Integration step (decomposition only)

After all subtasks complete:
1. Run the full test suite (Test command)
2. If it fails → debug and fix (max 3 attempts)
3. If it cannot be fixed → Block

If Commit strategy = squash:
```bash
git reset --soft {first_subtask_restore_point}
git commit -m "feat: {feature-title}"
```

## 06a. Test-engineer

If stage `test-engineer` is in the profile's Skip stages → skip, record "[SKIP] test-engineer (profile: {name})".
Update `state.json`: set `test.status` to `"skipped"`. Skip the `step-completed` webhook for skipped stages.
Follow atomic write protocol from `../../../core/state-manager.md`.

Before dispatching test-engineer: read `model:` frontmatter from `agents/test-engineer.md`. Write to `state.json`:
`test.started_at`, `test.model`, `test.status: "in_progress"`, and initialize `test.tokens_used: 0`,
`test.duration_ms: 0`, `test.tool_uses: 0`. Follow atomic write protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

test-engineer binds to canonical stage `test` per design.md §4.2 (default; `e2e_test` when `--e2e` flag).

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$TEST_ENGINEER_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness test agent-flow:test-engineer sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:test-engineer"
EXPECTED_STAGE_NAME="test"
# Merge: state.json[stages.test] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/test-engineer.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:test-engineer', model='sonnet'). DO NOT inline-execute.
- Context: `Mode: feature. Pipeline: implement-feature.` + changed files, acceptance criteria
- After completion: run Test command

If tests fail → test-engineer fixes them (max Test attempts attempts). If still failing → step X.

After dispatch: defensive-read `result.usage`. Write to `state.json`:
`test.completed_at`, `test.tokens_used` (fallback 0), `test.duration_ms` (elapsed ms, fallback 0),
`test.tool_uses` (fallback 0), `test.status: "completed"` (or `"blocked"` on failure), increment
`test.attempts`, set `test.last_result`. Follow atomic write protocol from `../../../core/state-manager.md`.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds (status `"completed"` only), if
`Webhook URL` is configured AND `step-completed` is in `On events`, fire with `step_name: "test"`,
`iteration_count: {test.attempts}`. Advisory failure: log `[WARN]` and continue.

## 06b. Deployment guard (pre-E2E)

If `local_deployment_configured = false` → skip.
If stage `test-engineer-e2e` is in the profile's Skip stages → skip.
If the E2E Test section is absent AND `test-engineer-e2e` is NOT in the profile's `Extra stages` → skip.
(No `step-completed` webhook for skipped stages.)

Before dispatching deployment-verifier: read `model:` frontmatter from `agents/deployment-verifier.md`.
Write to `state.json`: `deployment.started_at`, `deployment.model`, `deployment.status: "in_progress"`,
and initialize `deployment.tokens_used: 0`, `deployment.duration_ms: 0`, `deployment.tool_uses: 0`.
Follow atomic write protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

deployment-verifier binds to canonical stage `deployment` per design.md §4.2.

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$DEPLOYMENT_VERIFIER_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness deployment agent-flow:deployment-verifier sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:deployment-verifier"
EXPECTED_STAGE_NAME="deployment"
# Merge into state.json[stages.deployment] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/deployment-verifier.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:deployment-verifier', model='sonnet'). DO NOT inline-execute.
Context: `Action: start. Local Deployment config: Type = {Type}, Start command = {Start command},
Stop command = {Stop command}, Health check URL = {Health check URL}, Health check timeout = {Health check timeout},
Ports = {Ports}. Run directory: .agent-flow/{ISSUE-ID}/`

Verdict handling:
- `HEALTHY` or `SKIPPED` → continue to step 06c (E2E test)
- `UNHEALTHY`, `PORT_CONFLICT`, `START_FAILED` → proceed to step X (Block handler)

After dispatch: write `deployment.*` state fields. Follow atomic write protocol from `../../../core/state-manager.md`.

## 06c. E2E test (optional — NOT in implement-feature stage_allowlist)

> **Note:** `e2e_test` is NOT in the `<stage_allowlist>` for `/implement-feature` (see `skills/implement-feature/SKILL.md`). The terminal report in step 08 will SUPPRESS any `e2e_test WITNESS_MISSING` audit line from the implement-feature pipeline output (BLOCKER-2 alarm-fatigue fix). E2E execution is still supported via Pipeline Profile `Extra stages = test-engineer-e2e`, but it is not a surfaced anomaly when absent.

If stage `test-engineer-e2e` is in the profile's Skip stages → skip, record "[SKIP] test-engineer-e2e". Skip
the `step-completed` webhook for skipped stages.

If the E2E Test section exists in Automation Config OR the profile's `Extra stages` contains `test-engineer-e2e`:

Before dispatching test-engineer with --e2e flag: write `e2e_test.started_at`, `e2e_test.model`,
`e2e_test.status: "in_progress"`, and initialize `e2e_test.tokens_used: 0`, `e2e_test.duration_ms: 0`,
`e2e_test.tool_uses: 0`. Follow atomic write protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$TEST_ENGINEER_E2E_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness e2e_test agent-flow:test-engineer sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:test-engineer"
EXPECTED_STAGE_NAME="e2e_test"
# Merge into state.json[stages.e2e_test] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
```

You MUST invoke Task(subagent_type='agent-flow:test-engineer', prompt='--e2e', model='sonnet'). DO NOT inline-execute.
- Context: `Mode: feature. Pipeline: implement-feature.`

After dispatch: defensive-read `result.usage`. Write to `state.json`: `e2e_test.completed_at`,
`e2e_test.tokens_used` (fallback 0), `e2e_test.duration_ms` (elapsed ms, fallback 0),
`e2e_test.tool_uses` (fallback 0), `e2e_test.status: "completed"`. Follow atomic write protocol.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds, if `Webhook URL` is configured AND
`step-completed` is in `On events`, fire with `step_name: "e2e_test"`, `iteration_count: 1`. Advisory failure:
log `[WARN]` and continue.
