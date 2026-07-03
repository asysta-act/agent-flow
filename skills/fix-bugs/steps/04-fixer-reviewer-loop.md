# Step 04 — Fixer ↔ Reviewer Loop

Run the fixer ↔ reviewer iteration loop. Follow `../../../core/fixer-reviewer-loop.md` for the iteration
protocol.

## Centralized claim-write ritual (v2.0 gate-as-signer)

Immediately before **every** `Task()` dispatch in this loop (each fixer and each
reviewer iteration), perform the centralized claim-write ritual defined once in
`../../claim-ritual.md`. The ritual mints a fresh `claim_nonce`
(`secrets.token_hex(16)`) + a monotonic `dispatch_seq`, atomically writes the
**claim-only** stage record into `state.json`, and atomically writes the
top-level per-dispatch marker `.agent-flow/pending-dispatch.json` (temp +
`os.replace`). This is the single source of truth and **supersedes** the legacy
per-iteration `dispatch_witness` / 6-arg `compute_dispatch_witness` fields below
on keyed (`schema_version "2.0"`) runs: the orchestrator writes no key and no
signed tag, and the prompt head is gate-observed ground truth, not an
orchestrator-written field.

## Pre-loop state initialization

Before the first fixer dispatch, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:
- `fixer_reviewer.started_at`      = current ISO-8601 UTC timestamp
- `fixer_reviewer.model`           = `"opus"` (both fixer and reviewer use opus — recorded as single value)
- `fixer_reviewer.status`          = `"in_progress"`
- `fixer_reviewer.agent_name`      = `"agent-flow:fixer"` (first-invocation; reviewer iterations
                                       overwrite to `"agent-flow:reviewer"` then back to fixer)
- `fixer_reviewer.stage_name`      = `"fixer_reviewer"`
- `fixer_reviewer.dispatched_at`   = current ISO-8601 UTC timestamp (updated per iteration —
                                       represents most-recent Task() dispatch within the loop)
- `fixer_reviewer.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template (per iteration)
- `fixer_reviewer.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST per iteration, see "Agent Override injection" below)
- `fixer_reviewer.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `fixer_reviewer.dispatch_witness` = sha256("agent-flow:fixer|opus|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness fixer_reviewer agent-flow:fixer opus <prompt_head_128> <overlay_source> <overlay_digest>`; updated per iteration to
   match the most-recent Task() dispatch — reviewer iterations recompute with reviewer's prompt
   head and that iteration's overlay resolution)
- `fixer_reviewer.tokens_used` = 0, `fixer_reviewer.duration_ms` = 0, `fixer_reviewer.tool_uses` = 0
  (cumulative counters, initialized at loop start — accumulated across all iterations)

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single atomic replace. Then append the rendered overlay block to the prompt and dispatch.

**Per-iteration witness update:** before each Task() call inside the loop, resolve the Agent
Override overlay FIRST, then re-write `dispatched_at`, `prompt_head_128`, `overlay_source`,
`overlay_digest`, and `dispatch_witness` to reflect that iteration's actual dispatch tuple.
`agent_name` flips between `"agent-flow:fixer"` and `"agent-flow:reviewer"` accordingly. The
cumulative counters (tokens, duration_ms, tool_uses) keep accumulating — do NOT reset.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/fixer.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Fixer dispatch

You MUST invoke `Task(subagent_type='agent-flow:fixer', model='opus')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:fixer"`,
`EXPECTED_STAGE_NAME = "fixer_reviewer"`.

Context for the agent:
```
Max build retries = {Build retries from config}.
Block Comment Template: {template from plugin CLAUDE.md}.
Acceptance criteria: {AC from triage}.
Impact report: {analyst --phase impact output for this bug}.
Reproduction result: {contents of .agent-flow/{ISSUE-ID}/reproduction-result.json or "browser-agent reproduce was skipped"}.
Pipeline history: {last 5 entries from .agent-flow/pipeline-history.md if exists, else "none"}.
EXPECTED_AGENT_NAME = agent-flow:fixer
EXPECTED_STAGE_NAME = fixer_reviewer
```

## NEEDS_DECOMPOSITION handling

If fixer output contains `## NEEDS_DECOMPOSITION`:
1. Authoritative revert: `git checkout . && git clean -fd` (safety net — fixer's self-revert is best-effort)
2. If `decompose_mode = DISABLED` → Block handler (step X)
3. If this bug has already been decomposed once → Block handler (step X)
4. Run architect for decomposition, continue with subtask execution
5. After subtask execution: skip to step 07-publish

## NEEDS_CLARIFICATION detection (fixer)

If fixer output contains `## NEEDS_CLARIFICATION`:

```bash
STATE=".agent-flow/${ISSUE_ID}/state.json"
RAW_QUESTION=$(grep -iE -A1 "^question:" "$FIXER_OUTPUT" | head -1 | sed -E 's/^[Qq]uestion: //')
RAW_CONTEXT=$(grep -iE -A1 "^context:" "$FIXER_OUTPUT" | head -1 | sed -E 's/^[Cc]ontext: //' || echo "")
QUESTION="$RAW_QUESTION"
CONTEXT="$RAW_CONTEXT"

# Per-run cap = 3
CONSUMED=$(jq -r '.clarification.clarifications_consumed // 0' "$STATE")
if [ "$CONSUMED" -ge 3 ]; then
  echo "[BLOCK] Exceeded max clarifications (3 per run)" >&2
  continue
fi

# Per-iteration cap = 1
LAST_ITER=$(jq -r '.clarification.last_clarification_iteration // null' "$STATE")
CURRENT_ITER=$(jq -r '.fixer_reviewer.iterations // 0' "$STATE")
if [ "$LAST_ITER" = "$CURRENT_ITER" ]; then
  echo "[BLOCK] Clarification limit per iteration exceeded" >&2
  continue
fi

ASKED_AT="$(date -u +%FT%TZ)"
jq --arg q "$QUESTION" --arg c "$CONTEXT" --arg agent "fixer" \
  --arg asked_at "$ASKED_AT" \
  --argjson iter "$CURRENT_ITER" \
  '.status = "paused" | .clarification = {question: $q, asked_by_agent: $agent, asked_at_step: "fixer", asked_at_iteration: $iter, asked_at: $asked_at, context: $c, answer: null, clarifications_consumed: ((.clarification.clarifications_consumed // 0) + 1), last_clarification_iteration: $iter}' \
  "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

if [ -n "${Webhook_URL:-}" ] && printf '%s' "${On_events:-}" | grep -qF 'pipeline-paused'; then
  jq -nc \
    --arg event "pipeline-paused" \
    --arg run_id "${RUN_ID}" \
    --arg issue_id "${ISSUE_ID}" \
    --arg paused_at "${ASKED_AT}" \
    --arg question "$(printf '%s' "$RAW_QUESTION" | sanitize_block_reason)" \
    --arg asked_by_agent "fixer" \
    --arg asked_at_step "fixer" \
    --argjson iteration "${CURRENT_ITER:-0}" \
    '{event: $event, run_id: $run_id, issue_id: $issue_id, paused_at: $paused_at,
      clarification: {question: $question, asked_by_agent: $asked_by_agent, asked_at_step: $asked_at_step},
      iteration: $iteration}' \
  | curl --proto "=http,https" --max-time 5 --retry 0 \
      -X POST -H "Content-Type: application/json" \
      --data-binary @- "${Webhook_URL}" \
      > /dev/null 2>&1 || echo "[WARN] Webhook delivery failed"
fi

echo "[INFO] Pipeline paused for ${ISSUE_ID} — re-invoke /agent-flow:fix-bugs ${ISSUE_ID} --clarification \"<answer>\" to resume."
continue
```

## Build (post-fixer)

Run the Build command from Automation Config. Retry limit = Build retries from config.
Failure after exhausting retries → proceed to Block handler (step X).

## Post-fix hooks

If Hooks → Post-fix exists:
- Run the command via Bash. Failure → Block handler (step X).

If Custom Agents → Post-fix agent exists:
- Read agent definition from the configured file. Run as Task with the agent's model.
- BLOCK from custom agent → Block handler (step X).

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/reviewer.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Reviewer dispatch

Before invoking reviewer: resolve the reviewer's Agent Override overlay FIRST, then re-write
`fixer_reviewer.dispatched_at`, `fixer_reviewer.prompt_head_128`, `fixer_reviewer.overlay_source`,
`fixer_reviewer.overlay_digest`, `fixer_reviewer.dispatch_witness`
(sha256("agent-flow:reviewer|opus|<prompt_head_128>|<overlay_source>|<overlay_digest>") with the
reviewer prompt head and reviewer overlay), and `fixer_reviewer.agent_name = "agent-flow:reviewer"`.
Follow atomic write protocol.

You MUST invoke `Task(subagent_type='agent-flow:reviewer', model='opus')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:reviewer"`,
`EXPECTED_STAGE_NAME = "fixer_reviewer"`.

Context for the agent:
```
Max fixer iterations = {Fixer iterations from config}.
Acceptance criteria: {AC from triage}.
Reviewer history: {last 10 entries from .agent-flow/pipeline-history.md if exists, else "none"}.
EXPECTED_AGENT_NAME = agent-flow:reviewer
EXPECTED_STAGE_NAME = fixer_reviewer
```

Fixer ↔ reviewer loop: max {Fixer iterations} iterations.
REQUEST_CHANGES → back to fixer. Iterations exhausted → Block handler (step X).

## Smoke check (post-review)

Run Build command and Test command from Automation Config after the loop completes:
1. Run Build command. Failure → Block handler (step X).
2. Run Test command (existing tests only). Failure → Block handler (step X).

## Cumulative usage tracking

After each fixer or reviewer invocation within the loop, cumulatively accumulate usage into
`.agent-flow/{ISSUE-ID}/state.json` per `../../../core/state-manager.md` "Fixer-Reviewer Cumulative Write":
- `fixer_reviewer.tokens_used` += `result.usage.total_tokens` (or 0 if absent)
- `fixer_reviewer.duration_ms` += iteration duration ms
- `fixer_reviewer.tool_uses` += `result.usage.tool_uses` (or 0 if absent)

After each iteration, also update: increment `fixer_reviewer.iterations`, set
`fixer_reviewer.last_verdict`, update `fixer_reviewer.ac_fulfillment`, set
`fixer_reviewer.status` to `"in_progress"`. On APPROVE: set `fixer_reviewer.status = "completed"`.
On block/exhaustion: set `fixer_reviewer.status = "blocked"`. Follow atomic write protocol.

## Post-loop state write + webhook

On APPROVE (loop complete), write `fixer_reviewer.completed_at` = current ISO-8601 UTC timestamp.
On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"fixer_reviewer","duration":${duration_seconds},"iteration_count":${iteration_count},"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.
`step-completed` fires ONCE for the entire loop (not per iteration).
