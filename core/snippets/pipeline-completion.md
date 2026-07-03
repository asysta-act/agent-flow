# Snippet — Terminal pipeline-completed payload

Canonical payload pattern for the `pipeline-completed` webhook event fired at terminal pipeline outcomes. Cite this file from each Step Z catastrophic-exit handler.

```bash
# Fired ONLY at terminal outcomes: success, blocked, failed.
# Does NOT fire on paused — see core/agent-states.md and pipeline-paused webhook event.
jq -nc \
  --arg event "pipeline-completed" \
  --arg run_id "${RUN_ID}" \
  --arg issue_id "${ISSUE_ID}" \
  --arg outcome "${OUTCOME}" \
  --arg pr_url "${PR_URL:-}" \
  --arg completed_at "$(date -u +%FT%TZ)" \
  '{
    event: $event,
    run_id: $run_id,
    issue_id: $issue_id,
    outcome: $outcome,
    pr_url: ($pr_url | select(length > 0)),
    completed_at: $completed_at
  }' \
| curl --proto "=http,https" --max-time 5 --retry 0 \
    -X POST -H "Content-Type: application/json" \
    --data-binary @- "${WEBHOOK_URL}" \
    > /dev/null 2>&1 || echo "[WARN] Webhook delivery failed"
```

**`outcome` enum:** one of `"success"`, `"blocked"`, `"failed"`.

**`outcome: "failed"` limitation:** covers logical fall-through ONLY — does NOT fire on process death (OOM, Claude API timeout, SIGKILL). True crash detection requires architecture-level work (heartbeat, external watchdog) deferred to a future release.

**`pr_url`:** nullable. `null` for `outcome: "blocked"` or `outcome: "failed"`; populated for `outcome: "success"`.

## Used by:
- `skills/fix-bugs/steps/12-result.md:174` (citation marker `<!-- @snippet:pipeline-completion -->`)
- `skills/implement-feature/steps/08-publish.md:148` (citation marker `<!-- @snippet:pipeline-completion -->`)

