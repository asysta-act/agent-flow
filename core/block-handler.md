# Block Handler

## Purpose

Handle pipeline blocks: rollback git state, set issue state, post block comment, fire webhook, update state.json.

## Input Contract

| Field | Type | Notes |
|-------|------|-------|
| agent_name | string | Name of the blocking agent (e.g. `fixer`, `test-engineer`) |
| step_name | string | Pipeline step label (e.g. `"Step 6: Build"`) |
| reason | string | Max 2 sentences |
| detail | string | Technical output — error message, diff, test output |
| recommendation | string | What the human should do next |
| issue_id | string | Issue tracker ID |
| config | object | Automation Config values: Error Handling, State transitions, Notifications |

## Process

1. **Rollback:** If the blocking agent is `fixer`, `reviewer`, or `test-engineer`, or the blocking step is `smoke-check` → dispatch `agent-flow:rollback-agent` (Task tool, model: haiku). Context: `Agent: {agent_name}. Step: {step_name}. Reason: {reason}. Detail: {detail}. Recommendation: {recommendation}.` Execution context (worktree vs. CWD) is NOT passed here — rollback-agent re-derives it itself via `git worktree list` (see `agents/rollback-agent.md` Process step 2), since single-issue runs execute in CWD but batch runs may execute in a worktree per `Worktrees` config (`skills/fix-bugs/SKILL.md` Worktree / batch processing).
   Do NOT rollback on block from `analyst` — no git changes to revert.
2. **Set issue state:** Transition the issue to the Blocked state (from config → State transitions → Blocked) via the issue tracker MCP server.
   After the status-set MCP call, follow `core/status-verification.md` to verify the transition succeeded.
3. **On block action** (per config → Error Handling → On block; default: `comment`):
   - `comment`: post block comment only.
   - `close`: post block comment + close the issue.
   - Other value: interpret as a custom action; always post a block comment.
4. **Post block comment** to the issue tracker:
   ```
   [agent-flow] 🔴 Pipeline Block
   Agent: {agent_name}
   Step: {step_name}
   Reason: {reason}
   Detail: {detail_truncated_sanitized}
   Recommendation: {recommendation}
   ```
   Where `detail_truncated_sanitized` is constructed as follows before posting to the issue tracker:
   1. Apply `sanitize_block_reason()` (from `core/post-publish-hook.md` Section 5) to redact credentials from the detail string.
   2. Truncate to 100 chars: if the sanitized string exceeds 100 characters, trim to 97 characters and append `...`.
   3. The full unsanitized `detail` value is stored in `state.json` (local read only) — see Step 5 below. The issue tracker comment ONLY receives the truncated + sanitized version.

   Follow `core/mcp-body-formatting.md` when constructing the comment string.
5. **Update state.json:** set top-level `status` to `"blocked"`, write `block` object with `{agent_name, step_name, reason, detail, recommendation}`. Follow atomic write protocol from `core/state-manager.md`.
6. **Fire webhook** if config → Notifications → Webhook URL exists and `issue-blocked` is in On events. Fire this AFTER the state.json write in Step 5 completes — consistent with the State-Commit Ordering invariant in `core/post-publish-hook.md` (Section 4), the webhook stream is a projection of committed state, not an in-flight view. If the Step 5 write fails, skip this step (the webhook is suppressed, not fired):
   ```bash
   # Build the entire JSON payload structurally via jq — each variable is passed as --arg so jq
   # performs all string escaping. No inline interpolation into a quoted JSON literal.
   payload=$(jq -nc \
     --arg event "agent-flow-block" \
     --arg issue_id "${issue_id}" \
     --arg agent "${agent_name}" \
     --arg reason "${reason}" \
     --arg timestamp "${ISO8601}" \
     '{"event":$event, "issue_id":$issue_id, "agent":$agent, "reason":$reason, "timestamp":$timestamp}')

   <!-- @snippet:webhook-curl -->
   curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
     --data-binary @- "${Webhook_URL}" <<EOF
   ${payload}
   EOF
   ```
   The `reason` field is agent-generated free-form prose (max 2 sentences) and MAY contain `"`, `\`,
   or newlines that would structurally break the JSON payload. Passing `reason` to `jq -nc --arg`
   delegates all string escaping to `jq` — the resulting JSON string literal is guaranteed safe for
   embedding, with no shell-level substring trimming required (no Bash-specific substring trimming
   <!-- COUNTER-EXAMPLE: ${var:1:-1} — do NOT use; delegates escaping to jq instead -->
   or equivalent POSIX construct needed). The `--proto "=http,https"` flag restricts transport to
   HTTP/HTTPS only (blocks `file://`, `gopher://`, etc.). Advisory failure: log
   `[WARN] Webhook delivery failed: {error}` and continue pipeline. Never block on webhook delivery.

   **Why heredoc + `${payload}` is safe:** after `jq -nc` encoding, literal newlines in any input
   become the two-character escape `\n` inside the JSON string. The heredoc body is therefore a
   single logical line of JSON. The heredoc terminator `EOF` can never appear as a standalone line
   inside the body.

## Output Contract

Block is recorded. Comment posted to issue tracker. Issue state set to Blocked. Webhook fired if configured.

## Failure Handling

- Comment posting failure → log warning, continue (do NOT retry).
- Webhook failure → log warning, continue (do NOT retry).
- State transition failure → log warning, continue.
- Rollback failure → log warning, continue (partial git state — note in block comment detail).
