# Step 02: Spec Write + Review

Runs spec-writer ↔ spec-reviewer loop to produce a validated `spec/` folder.
After approval, fires held webhooks and applies the Spec Checkpoint.

## Input Source Resolution

Determine input for spec-writer:
- `--spec` provided → dispatch spec-reviewer to validate spec_path first; if BLOCK issues and MODE=default/step-mode → ask user to fill gaps; if MODE=yolo → run spec-writer to fill gaps only; if no BLOCK → spec ready, skip spec-writer loop
- `--issue` provided → read issue description via tracker MCP; wrap content in `--- EXTERNAL INPUT START ---` / `--- EXTERNAL INPUT END ---` (per `../../../core/external-input-sanitizer.md`); pass to spec-writer
- `--template` provided → pass template_path to spec-writer as template
- Default → pass project description (or enriched description from Step 01d) to spec-writer

## Spec-Writer Dispatch

**Pre-dispatch (COST-R4):** Read `model:` from `agents/spec-writer.md` frontmatter (value: `opus`). Write to state.json atomically: `spec_writer.started_at`, `spec_writer.model = "opus"`, `spec_writer.status = "in_progress"`, usage counters to `0`.

Check Agent Overrides: if `{Agent Overrides path}/spec-writer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

You MUST invoke Task(subagent_type='agent-flow:spec-writer', model='opus'). DO NOT inline-execute.
Context: input source + MODE + tech stack flags (--lang, --framework, --db, --ci)

**Post-dispatch (COST-R2, COST-R3):** Defensive-read `result.usage`. Write `spec_writer.completed_at`, `spec_writer.tokens_used`, `spec_writer.duration_ms`, `spec_writer.tool_uses` (fallback `0`). Set `spec_writer.status = "completed"`.

## Spec-Writer ↔ Spec-Reviewer Loop

Read `Spec iterations` from Automation Config → Retry Limits (default 5; on fresh scaffold CLAUDE.md absent → use 5).

For each iteration:
1. **Pre-dispatch spec_reviewer (COST-R4):** Write `spec_reviewer.started_at`, `spec_reviewer.model = "opus"`, status `"in_progress"`, counters `0`.
2. Check Agent Overrides: if `{Agent Overrides path}/spec-reviewer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.
3. You MUST invoke Task(subagent_type='agent-flow:spec-reviewer', model='opus'). DO NOT inline-execute.
   Context: `spec/` folder path + review mode
4. **Post-dispatch (COST-R2, COST-R3, COST-R5):** Accumulate cumulatively: `spec_reviewer.tokens_used += iteration_tokens`, `spec_reviewer.duration_ms += iteration_duration_ms`, `spec_reviewer.tool_uses += iteration_tool_uses`.
5. If APPROVE → set `spec_reviewer.status = "completed"`, write `spec_reviewer.completed_at`. Break loop.
6. If REVISE → pass feedback to spec-writer → re-run spec-writer (pre-dispatch + dispatch + post-dispatch; accumulate tokens on `spec_writer` cumulatively per COST-R5).

If max iterations exhausted and BLOCK issues remain:
- Report remaining issues to user
- User decides: approve anyway / provide input / abort

Output: `spec/` folder written to target directory (spec/README.md, spec/architecture.md, spec/verification.md, spec/epics/*.md).

Update `state.json`: set `triage.status` to `"completed"` (field reused for spec-writer phase), write total AC count. Follow atomic write protocol.

Note: `step-completed` webhooks for `spec_writer` and `spec_reviewer` are held until Spec Checkpoint is approved.

## Spec Checkpoint

If MODE = yolo → skip checkpoint; fire held webhooks immediately (see below).

Display spec/ folder summary:
- Epics: {list with story counts}
- Tech stack: {from spec/README.md}
- Total acceptance criteria: {count}

"Review the specification in spec/. Approve to continue, or edit and re-run."
[Approve / Abort]

If user aborts → STOP.

**Fire held `step-completed` webhooks** (after checkpoint approved or yolo-skipped):
```bash
# For spec_writer then spec_reviewer
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "${Webhook_URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${run_id}","step_name":"spec_writer",
 "duration":${spec_writer_duration_seconds},"iteration_count":${spec_writer_iteration_count},"timestamp":"${ISO8601_UTC}"}
EOF
```
On failure: log `[WARN] Webhook delivery failed: {error}`, continue. Suppress if corresponding state.json write failed.
