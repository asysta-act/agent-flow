# Step 02 — Architect (Design)

Before dispatching architect: read `model:` frontmatter from `agents/architect.md`. Write to `state.json`:
`architect.started_at`, `architect.model`, `architect.status: "in_progress"`, and initialize
`architect.tokens_used: 0`, `architect.duration_ms: 0`, `architect.tool_uses: 0`. Follow atomic write
protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

The architect binds to canonical stage `code_analysis` per design.md §4.2 (feature/scaffold mode). Source `core/lib/stage-invariant.sh`. Resolve the Agent Override overlay (see the "Agent Override injection" section below) BEFORE computing the witness, then write the witness fields atomically before Task dispatch. Inject `EXPECTED_AGENT_NAME` and `EXPECTED_STAGE_NAME` as Tier-1 prompt variables.

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$ARCHITECT_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness code_analysis agent-flow:architect opus "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:architect"
EXPECTED_STAGE_NAME="code_analysis"
# Merge: state.json[stages.code_analysis] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/architect.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:architect', model='opus'). DO NOT inline-execute.
- Context: specification from spec-analyst + analyst impact analysis (if available) + access to code +
  `Module Docs path = {Path from Module Docs config, or "none"}.`
- Expected output: architectural design + task tree (YAML)

If architect blocks → proceed to step X (Block handler).

After dispatch: defensive-read `result.usage`. Write to `state.json`:
`architect.completed_at`, `architect.tokens_used` (fallback 0), `architect.duration_ms` (elapsed ms, fallback 0),
`architect.tool_uses` (fallback 0), `architect.status: "completed"`. Also set `code_analysis.status` to
`"completed"` (field reused for architect output, only if not already set by step 01b). On architect block,
set `architect.status` to `"blocked"`, `code_analysis.status` to `"blocked"` (if not already set), write block
object, set top-level `status` to `"blocked"`. Follow atomic write protocol from `../../../core/state-manager.md`.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds, if `Webhook URL` is configured AND
`step-completed` is in `On events`, fire with `step_name: "architect"`, `iteration_count: 1`. Advisory failure:
log `[WARN]` and continue.
