# Step 07 — Acceptance Gate

For features, the acceptance gate condition differs by mode:

**In decomposition mode:** always run acceptance-gate for every subtask (no threshold condition).

**In single-pass mode (no decomposition):** run acceptance-gate if 3 or more acceptance criteria exist.
If fewer than 3 AC → skip to step 08 (write `state.json[stages.acceptance_gate].status = "skipped"` atomically — never leave at `pending`).

Before dispatching acceptance-gate: read `model:` frontmatter from `agents/acceptance-gate.md`. Write to
`state.json`: `acceptance_gate.started_at`, `acceptance_gate.model`, `acceptance_gate.status: "in_progress"`,
and initialize `acceptance_gate.tokens_used: 0`, `acceptance_gate.duration_ms: 0`, `acceptance_gate.tool_uses: 0`.
Follow atomic write protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

acceptance-gate binds to canonical stage `acceptance_gate` per design.md §4.2.

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$ACCEPTANCE_GATE_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness acceptance_gate agent-flow:acceptance-gate sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:acceptance-gate"
EXPECTED_STAGE_NAME="acceptance_gate"
# Merge: state.json[stages.acceptance_gate] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/acceptance-gate.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:acceptance-gate', model='sonnet'). DO NOT inline-execute.
Context: `Acceptance criteria: {AC from spec-analyst — full feature AC, not just per-subtask AC}.
Changed files: {list of files modified by fixer}.`

If REQUEST_CHANGES → back to fixer for the LAST subtask (or single-pass) with feedback.
If APPROVE → continue to step 08.

After dispatch: defensive-read `result.usage`. Write to `state.json`:
`acceptance_gate.completed_at`, `acceptance_gate.tokens_used` (fallback 0),
`acceptance_gate.duration_ms` (elapsed ms, fallback 0), `acceptance_gate.tool_uses` (fallback 0),
`acceptance_gate.status: "completed"` (or `"skipped"` if condition not met), write `acceptance_gate.verdict`.
Follow atomic write protocol from `../../../core/state-manager.md`.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds (status `"completed"` only —
not on skip), if `Webhook URL` is configured AND `step-completed` is in `On events`, fire with
`step_name: "acceptance_gate"`, `iteration_count: 1`. Advisory failure: log `[WARN]` and continue.
