# Step 01 — Spec + Code Analysis

## Step 01a: Spec-analyst — specification

If stage `spec-analyst` is in the profile's Skip stages → skip, record "[SKIP] spec-analyst (profile: {name})".

Before dispatching spec-analyst: read `model:` frontmatter from `agents/spec-analyst.md`. Write to `state.json`:
`spec_analysis.started_at`, `spec_analysis.model`, `spec_analysis.status: "in_progress"`, and initialize
`spec_analysis.tokens_used: 0`, `spec_analysis.duration_ms: 0`, `spec_analysis.tool_uses: 0`. Follow atomic write
protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

Source `core/lib/stage-invariant.sh`. Resolve the Agent Override overlay (see the "Agent Override injection" section below) BEFORE computing the witness, then write the dispatch witness atomically to `state.json[stages.spec_analysis]` before invoking Task. Inject `EXPECTED_AGENT_NAME` and `EXPECTED_STAGE_NAME` as Tier-1 prompt variables so the agent self-check can cross-verify.

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$SPEC_ANALYST_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness spec_analysis agent-flow:spec-analyst sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:spec-analyst"
EXPECTED_STAGE_NAME="spec_analysis"
# Merge into state.json[stages.spec_analysis]: { dispatched_at, agent_name, stage_name,
# prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
# in ONE atomic write via ../../../core/state-manager.md. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/spec-analyst.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:spec-analyst', model='sonnet'). DO NOT inline-execute.
- Context: issue details from the issue tracker (wrapped in EXTERNAL INPUT markers per `../../../core/external-input-sanitizer.md`)
- Expected output: structured specification with acceptance criteria

If spec-analyst blocks → proceed to step X (Block handler).

Store from spec-analyst output: `acceptance_criteria` (list). Pass to all downstream agents.

After dispatch: defensive-read `result.usage`. Write to `state.json`:
`spec_analysis.completed_at`, `spec_analysis.tokens_used` (fallback 0), `spec_analysis.duration_ms` (elapsed ms,
fallback 0), `spec_analysis.tool_uses` (fallback 0), `spec_analysis.status: "completed"`. Also set
`triage.status` to `"completed"` and write spec-analyst AC list to `triage.acceptance_criteria`. On block, set
`spec_analysis.status` to `"blocked"`, write block object, set top-level `status` to `"blocked"`.
Follow atomic write protocol from `../../../core/state-manager.md`.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds, if `Webhook URL` is configured AND
`step-completed` is in `On events`, fire:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "${Webhook_URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"spec_analysis","duration":${duration_s},"iteration_count":1,"timestamp":"${ISO8601_UTC}"}
EOF
```
Advisory failure: log `[WARN] Webhook delivery failed: {error}` and continue.

## Step 01b: Analyst — codebase impact analysis

If stage `analyst-impact` is in the profile's Skip stages → skip, record "[SKIP] analyst-impact (profile: {name})".
Update `state.json`: set `code_analysis.status` to `"skipped"`. Skip the `step-completed` webhook for skipped stages.
Follow atomic write protocol from `../../../core/state-manager.md`.

Before dispatching analyst: read `model:` frontmatter from `agents/analyst.md`. Write to `state.json`:
`code_analysis.started_at`, `code_analysis.model`, `code_analysis.status: "in_progress"`, and initialize
`code_analysis.tokens_used: 0`, `code_analysis.duration_ms: 0`, `code_analysis.tool_uses: 0`. Follow atomic
write protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$ANALYST_IMPACT_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness code_analysis agent-flow:analyst sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:analyst"
EXPECTED_STAGE_NAME="code_analysis"
# Merge: state.json[stages.code_analysis] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write per ../../../core/state-manager.md. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/analyst.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:analyst', prompt='--phase impact', model='sonnet'). DO NOT inline-execute.
Context: `Mode: feature. Pipeline: implement-feature. Spec: {spec-analyst output}. Root cause iterations =
{Root cause iterations from config}. Module Docs path = {Path from Module Docs config, or "none"}.`

If analyst (impact) blocks → log warning: "[WARN] analyst (impact) blocked — proceeding to architect without impact analysis."
Do NOT stop the pipeline. Proceed to step 02.

Pass analyst output to architect (step 02) as additional context.

After dispatch: defensive-read `result.usage`. Write to `state.json`:
`code_analysis.completed_at`, `code_analysis.tokens_used` (fallback 0), `code_analysis.duration_ms` (elapsed ms,
fallback 0), `code_analysis.tool_uses` (fallback 0), `code_analysis.status: "completed"`.
Follow atomic write protocol from `../../../core/state-manager.md`.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds (status `"completed"` only), if
`Webhook URL` is configured AND `step-completed` is in `On events`, fire with `step_name: "code_analysis"`,
`iteration_count: 1`. Advisory failure: log `[WARN]` and continue. Skip if blocked or skipped.
