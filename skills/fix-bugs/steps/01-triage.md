# Step 01 — Triage

Dispatch `analyst --phase triage` for each bug that passed the issue-ID validation gate.

## Set issue tracker state + self-assign

Before dispatching the analyst, set the tracker state per Automation Config (`Issue Tracker → On start set`). Read `Type` for the correct MCP server.

After the status-set MCP call, follow `../../../core/status-verification.md` to verify the transition succeeded.

**Self-assign:** Immediately after a successful On start set transition, also assign the issue to the MCP-authenticated user (self) so the tracker UI accurately shows pipeline ownership. Use the tracker's assignee tool — per `Issue Tracker → Type`:

| Type | Tool | Self-assign parameter |
|------|------|-----------------------|
| `jira` | `editIssue` | `fields.assignee.accountId = "<self>"` (resolve via `getCurrentUser` if accountId not cached) |
| `youtrack` | `update_issue` | Assignee custom field set to current user |
| `linear` | `issueUpdate` mutation | `assigneeId: "me"` |
| `gitea` | `editIssue` | `assignees: ["<self>"]` |
| `github` | `addAssignees` | `assignees: ["@me"]` |
| `redmine` | `update_issue` | `assigned_to_id: "me"` (or numeric via `getCurrentUser`) |

**Self-assign failure mode is advisory** (mirror `../../../core/status-verification.md` pattern): if the assignee MCP call fails (permission denied, tool not available, network error, accountId resolution failure), log `[WARN] Self-assign skipped for {issue_id}: {error}. Pipeline continues.` and proceed. **Never block** the pipeline on assignee failure — state transition (the load-bearing operation) has already succeeded; ownership is a UX nicety, not a correctness invariant.

**Idempotency on resume:** When the pipeline resumes from `FRESH` (e.g., crash recovery, manual re-run), self-assign re-fires — re-firing self-assign is benign (assigning the same user to the same issue is a no-op at every supported tracker) and requires no special detection.

*In dry-run: skip the tracker-set + self-assign (no MCP writes).*

## Skip condition

If stage `triage` is in the profile's Skip stages → skip for each bug, record `[SKIP] triage (profile: {name})`.

## Pre-dispatch state write

Before dispatching, atomically write per-stage pre-dispatch fields to
`.agent-flow/{ISSUE-ID}/state.json`:
- `triage.started_at`      = current ISO-8601 UTC timestamp
- `triage.model`           = `"sonnet"` (from `agents/analyst.md` frontmatter)
- `triage.status`          = `"in_progress"`
- `triage.agent_name`      = `"agent-flow:analyst"`
- `triage.stage_name`      = `"triage"`
- `triage.dispatched_at`   = current ISO-8601 UTC timestamp
- `triage.prompt_head_128` = first 128 UTF-8-safe bytes of the un-expanded prompt template (BEFORE Tier-1 variable injection)
- `triage.overlay_source`  = `toml` | `none` | `md_rejected` (from the Agent Override Injector — resolve it FIRST, see "Agent Override injection" below)
- `triage.overlay_digest`  = sha256 hex of the rendered overlay block (`toml`), else literal `none` / `md_rejected` (via `compute_overlay_digest`)
- `triage.dispatch_witness` = sha256("agent-flow:analyst|sonnet|<prompt_head_128>|<overlay_source>|<overlay_digest>")
  (compute via the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness triage agent-flow:analyst sonnet <prompt_head_128> <overlay_source> <overlay_digest>`; the overlay is resolved BEFORE the witness so the receipt binds the overlay actually applied)
- `triage.tokens_used` = 0, `triage.duration_ms` = 0, `triage.tool_uses` = 0 (safe defaults)

Follow atomic write protocol from `../../../core/state-manager.md`. All fields written in a single atomic replace. Then append the rendered overlay block to the prompt and dispatch.

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/analyst.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

## Dispatch

You MUST invoke `Task(subagent_type='agent-flow:analyst', model='sonnet')`.
DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:analyst"`,
`EXPECTED_STAGE_NAME = "triage"`.

Context for the agent:
```
--phase triage. Type = {Type from config}. Use the MCP server for {Type}.
EXPECTED_AGENT_NAME = agent-flow:analyst
EXPECTED_STAGE_NAME = triage
```

When passing issue tracker content (title, description, comments) to the agent, follow
`../../../core/external-input-sanitizer.md`: wrap each piece of external content in
`--- EXTERNAL INPUT START ---` / `--- EXTERNAL INPUT END ---` markers.

## Post-dispatch state write

After dispatch, write per-stage post-dispatch fields to `.agent-flow/{ISSUE-ID}/state.json`:
- `triage.completed_at` = current ISO-8601 UTC timestamp
- `triage.tokens_used` = `result.usage.total_tokens` (or 0 if absent — defensive fallback)
- `triage.duration_ms` = `triage.completed_at` epoch ms − `triage.started_at` epoch ms
- `triage.tool_uses` = `result.usage.tool_uses` (or 0 if absent)

Follow atomic write protocol from `../../../core/state-manager.md`.

On successful state commit, if Notifications → Webhook URL exists and `step-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${issue_id}","step_name":"triage","duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601}"}
EOF
```
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.

## Outcome handling

- Duplicates → close, record as DUPLICATE, continue with next bug.
- `Quality gate: UNCLEAR` → Block using Block Comment Template, then continue with next bug:
  ```
  [agent-flow] 🔴 Pipeline Block
  Agent: analyst
  Step: triage
  Reason: Issue is unclear — analyst returned Quality gate: UNCLEAR.
  Detail: {analyst output explaining what is missing}
  Recommendation: {analyst recommendation for what the reporter should clarify}
  ```
  In dry-run mode: record as UNCLEAR only, do NOT write to the issue tracker.
- OK → continue to step 02.

Store from triage output: `acceptance_criteria` (list), `complexity` (XS/S/M/L).
These are passed to all downstream agents as context.

## NEEDS_CLARIFICATION detection

If triage output contains `## NEEDS_CLARIFICATION`:

```bash
STATE=".agent-flow/${ISSUE_ID}/state.json"
# Case-insensitive grep matches both "Question:" and "question:" (legacy)
RAW_QUESTION=$(grep -iE -A1 "^question:" "$TRIAGE_OUTPUT" | head -1 | sed -E 's/^[Qq]uestion: //')
RAW_CONTEXT=$(grep -iE -A1 "^context:" "$TRIAGE_OUTPUT" | head -1 | sed -E 's/^[Cc]ontext: //' || echo "")
QUESTION="$RAW_QUESTION"
CONTEXT="$RAW_CONTEXT"

# Per-run cap = 3
CONSUMED=$(jq -r '.clarification.clarifications_consumed // 0' "$STATE")
if [ "$CONSUMED" -ge 3 ]; then
  echo "[BLOCK] Exceeded max clarifications (3 per run)" >&2
  continue
fi

# Per-iteration cap = 1 (triage iteration = 0)
LAST_ITER=$(jq -r '.clarification.last_clarification_iteration // null' "$STATE")
CURRENT_ITER=$(jq -r '.fixer_reviewer.iterations // 0' "$STATE")
if [ "$LAST_ITER" = "$CURRENT_ITER" ]; then
  echo "[BLOCK] Clarification limit per iteration exceeded" >&2
  continue
fi

ASKED_AT="$(date -u +%FT%TZ)"
jq --arg q "$QUESTION" --arg c "$CONTEXT" --arg agent "analyst" \
  --arg asked_at "$ASKED_AT" \
  --argjson iter "$CURRENT_ITER" \
  '.status = "paused" | .clarification = {question: $q, asked_by_agent: $agent, asked_at_step: "triage", asked_at_iteration: $iter, asked_at: $asked_at, context: $c, answer: null, clarifications_consumed: ((.clarification.clarifications_consumed // 0) + 1), last_clarification_iteration: $iter}' \
  "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

# Fire pipeline-paused webhook (see ../../../core/agent-states.md Section 2)
if [ -n "${Webhook_URL:-}" ] && printf '%s' "${On_events:-}" | grep -qF 'pipeline-paused'; then
  jq -nc \
    --arg event "pipeline-paused" \
    --arg run_id "${RUN_ID}" \
    --arg issue_id "${ISSUE_ID}" \
    --arg paused_at "${ASKED_AT}" \
    --arg question "$(printf '%s' "$RAW_QUESTION" | sanitize_block_reason)" \
    --arg asked_by_agent "analyst" \
    --arg asked_at_step "triage" \
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

## State update (end of step)

Update `.agent-flow/{ISSUE-ID}/state.json`: set `triage.status` to `"completed"` (or `"blocked"` for
duplicate/unclear), write `triage.acceptance_criteria`, `triage.complexity`, `triage.severity`,
`triage.area`. Follow atomic write protocol from `../../../core/state-manager.md`.
