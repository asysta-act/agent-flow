# Snippet — Webhook curl invocation

The canonical curl pattern for agent-flow webhook delivery. Cite this file from any new webhook call site.

```bash
curl --proto "=http,https" --max-time 5 --retry 0 \
  -X POST -H "Content-Type: application/json" \
  --data-binary @- "${WEBHOOK_URL}" \
  > /dev/null 2>&1 || echo "[WARN] Webhook delivery failed"
```

**Mandatory flags:**
- `--proto "=http,https"` — SSRF defense; rejects file://, gopher://, etc.
- `--max-time 5` — bounds latency per call.
- `--retry 0` — no retries (advisory failure semantics; circuit breaker handles repeated failures).
- `> /dev/null 2>&1 || echo "[WARN] ..."` — advisory failure logging.

**See also:** `core/post-publish-hook.md` Section 4.2 (circuit breaker) — the curl call may be skipped if the breaker is open.

## Used by:
- `skills/fix-bugs/SKILL.md` and decomposed `skills/fix-bugs/steps/*.md` files (citation marker `<!-- @snippet:webhook-curl -->`)
- `skills/implement-feature/steps/*.md` files (citation marker `<!-- @snippet:webhook-curl -->`)
- `core/post-publish-hook.md` Section 4 enumerated event firing site (citation marker `<!-- @snippet:webhook-curl -->`)
- `core/block-handler.md` issue-blocked webhook firing site (citation marker `<!-- @snippet:webhook-curl -->`)
- `core/agent-states.md` pipeline-paused webhook firing site (citation marker `<!-- @snippet:webhook-curl -->`) — added per Devil's-Advocate Round-2 F-21

**Expected citation count:** 18 real transclusion sites, verified via `grep -rn "<!-- @snippet:webhook-curl -->" .` across the repo (count excludes this file's own 5 prose self-references above, which use the marker text in backticks rather than as a live transclusion). No test scenario in `tests/scenarios/` currently cross-checks this count against the "Used by" list below — treat it as advisory and re-run the grep above to re-verify if citation sites are added or removed.
