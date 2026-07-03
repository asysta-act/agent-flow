# Step 04 — Fixer-Reviewer Loop (Subtask Execution)

## Centralized claim-write ritual (v2.0 gate-as-signer)

Immediately before **every** `Task()` dispatch in this loop, perform the
centralized claim-write ritual defined once in `../../claim-ritual.md`. The
ritual mints a fresh `claim_nonce` (`secrets.token_hex(16)`) + a monotonic
`dispatch_seq`, atomically writes the **claim-only** stage record into
`state.json`, and atomically writes the top-level per-dispatch marker
`.agent-flow/pending-dispatch.json` (temp + `os.replace`). This is the single
source of truth and **supersedes** the legacy `dispatch_witness` /
`compute_dispatch_witness` fields on keyed (`schema_version "2.0"`) runs: the
orchestrator writes no key and no signed tag, and the prompt head is
gate-observed ground truth, not an orchestrator-written field.

**Single-pass (without decomposition):** Execute steps 04a–04e once for the entire feature.

**Decomposition (sequential mode):** For each subtask in topological order:
- Verify that all depends_on have status "completed". If not → skip (waiting).
- Build context for fixer: entire decomposition plan + summary of previous subtasks
  (what changed, why, diff summary) + current subtask (scope, files, acceptance criteria).

## 04a. Pre-fix hook

If Hooks → Pre-fix exists: run the command via Bash.

## 04b. Fixer

Before the first fixer dispatch: read `model:` frontmatter from `agents/fixer.md`. Write to `state.json`:
`fixer_reviewer.started_at`, `fixer_reviewer.model: "opus"`, `fixer_reviewer.status: "in_progress"`, and
initialize `fixer_reviewer.tokens_used: 0`, `fixer_reviewer.duration_ms: 0`, `fixer_reviewer.tool_uses: 0`.
Follow atomic write protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

Both fixer and reviewer bind to canonical stage `fixer_reviewer` per design.md §4.2 (shared in the iteration loop). Source `core/lib/stage-invariant.sh`. For EACH fixer or reviewer dispatch, resolve the Agent Override overlay FIRST (each iteration has its own prompt AND its own overlay resolution — therefore its own witness), then recompute the witness. Inject `EXPECTED_AGENT_NAME` and `EXPECTED_STAGE_NAME` as Tier-1 prompt variables.

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$FIXER_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness fixer_reviewer agent-flow:fixer opus "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:fixer"   # agent-flow:reviewer for the reviewer dispatch
EXPECTED_STAGE_NAME="fixer_reviewer"
# Merge: state.json[stages.fixer_reviewer] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
# On every iteration, OVERWRITE these fields (including overlay_source/overlay_digest) with the
# current iteration's values.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/fixer.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:fixer', model='opus'). DO NOT inline-execute.
- Context: `Mode: feature. Pipeline: implement-feature.` + architectural design + subtask scope + acceptance criteria
- After completion: run Build command

After each fixer dispatch: defensive-read `result.usage`. Cumulatively accumulate into `fixer_reviewer` stage:
```
fixer_reviewer.tokens_used  += iteration_tokens_used
fixer_reviewer.duration_ms  += iteration_duration_ms
fixer_reviewer.tool_uses    += iteration_tool_uses
```
Write the accumulated values atomically to `state.json`. Follow atomic write protocol from `../../../core/state-manager.md`.

If fixer output contains `## NEEDS_DECOMPOSITION`:
- In decomposition mode: Block the current subtask with reason "Subtask scope exceeds fixer capacity."
  Move to next subtask. Invoke block-handler with `agent = fixer`.
- In single-pass mode: Block the issue with reason "Feature scope exceeds single-pass fixer capacity.
  Consider re-running with --decompose flag." Invoke block-handler with `agent = fixer`.

**NEEDS_CLARIFICATION detection (after fixer dispatch):** If fixer output contains `## NEEDS_CLARIFICATION`,
follow the full NEEDS_CLARIFICATION protocol in `../../../core/agent-states.md` Section 2:
- Enforce per-run cap (3) and per-iteration cap (1)
- Persist clarification object to `state.json` with `status: "paused"`
- Include `asked_at` ISO 8601 UTC timestamp (autopilot reads this for pause age)
- Fire `pipeline-paused` webhook if configured
- Exit 0 with message "[INFO] Pipeline paused — re-invoke /agent-flow:implement-feature <ISSUE-ID> --clarification \"<answer>\" to resume."

If build fails → fixer fixes it (max Build retries attempts). If build still fails → proceed to step X.

## 04c. Post-fix hook + custom agent

If Hooks → Post-fix exists: run the command via Bash.
If Custom Agents → Post-fix agent exists: run via Task tool.

## 04d. Reviewer

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/reviewer.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:reviewer', model='opus'). DO NOT inline-execute.
- Context: `Mode: feature. Pipeline: implement-feature.` + diff from fixer + acceptance criteria from spec-analyst

Follow `../../../core/fixer-reviewer-loop.md`:
- If reviewer returns APPROVE → continue.
- If reviewer returns REQUEST_CHANGES → back to fixer (04b) with feedback.
- Max Fixer iterations cycles of fixer↔reviewer. If exceeded → step X.

After each reviewer dispatch: defensive-read `result.usage`. Cumulatively accumulate into `fixer_reviewer` stage
(same running totals as fixer). Write atomically. Follow atomic write protocol from `../../../core/state-manager.md`.

After each fixer-reviewer iteration, update `state.json`: increment `fixer_reviewer.iterations`, set
`fixer_reviewer.last_verdict`, update `fixer_reviewer.ac_fulfillment`. On APPROVE, write
`fixer_reviewer.completed_at`, set `fixer_reviewer.status` to `"completed"`. On block/exhaustion, set
`fixer_reviewer.status` to `"blocked"`, write block object. Follow atomic write protocol.

**Fire `step-completed` webhook (on APPROVE or block — once per stage, not per iteration):** After the atomic
state.json write of the final verdict, if `Webhook URL` is configured AND `step-completed` is in `On events`,
fire with `step_name: "fixer_reviewer"`, `iteration_count: {total iterations}`. Advisory failure: log `[WARN]`
and continue. Fires once per top-level stage — never once per iteration.

## 04e. Smoke check (build + test)

After fixer↔reviewer approval, verify the codebase still builds and existing tests pass.

1. Read `Build command` and `Test command` from Automation Config.
2. Run Build command via Bash. If it fails → Block handler (step X) with
   `agent = smoke-check, Step = 04e, Reason = Build command failed after fixer↔reviewer approval`.
3. Run Test command via Bash. If it fails → Block handler (step X) with
   `agent = smoke-check, Step = 04e, Reason = Existing tests failed after fixer↔reviewer approval`.
4. Both pass → continue to step 05.

## 04f. Commit subtask (decomposition only)

```bash
git add -A
git commit -m "feat({subtask-id}): {subtask-title}"
```

Update the current subtask entry in `.claude/decomposition/{ISSUE-ID}.yaml`:
- Set `status` to `"completed"`
- Set `commit_hash` to the new commit SHA
- Set `restore_point` to the commit SHA before this subtask (HEAD~1 or branch creation point for first subtask)

Update `state.json`: find the matching subtask in `decomposition.subtasks`, set its `status` to `"completed"`
and `commit_hash` to the new commit SHA. Follow atomic write protocol from `../../../core/state-manager.md`.
