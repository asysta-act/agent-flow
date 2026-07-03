# Step 12 — Terminal Result + Dispatch-Audit Surfacing

Compute pipeline accumulator, emit the per-issue summary table, surface dispatch-audit anomalies,
and fire the terminal `pipeline-completed` webhook.

This step is NOT a Task() dispatch — it is the orchestrator's terminal infrastructure.

## Step 12.1: Pipeline accumulator

Before writing terminal `status = "completed"` (or `"blocked"`/`"failed"`), compute and write to
`.agent-flow/{ISSUE-ID}/state.json` atomically per `../../../core/state-manager.md` "Pipeline Accumulator Write":

- `pipeline.total_tokens`     = sum of `{stage}.tokens_used` for all completed stages
- `pipeline.total_duration_ms` = sum of `{stage}.duration_ms` for all completed stages
- `pipeline.total_tool_uses`  = sum of `{stage}.tool_uses` for all completed stages
- `pipeline.summary_table`    = markdown table with one row per completed stage
  (columns: `| Stage | Model | Tokens | Duration | Tools |` plus `Total` footer row).
  Apply COST-R10 truncation: if rows > 20 OR total string length > 4000 chars, truncate row-wise
  (never mid-row) and append `| ... | (truncated, N more stages in pipeline.log) | ... |` immediately
  before the `Total` row.

Set top-level `status` to `"completed"` (success path), `"blocked"` (block path), or `"failed"`
(catastrophic fall-through — see Step Z below). Follow atomic write protocol.

## Step 12.2: Emit summary table to stdout

After state.json commit, echo `pipeline.summary_table` to stdout so the user sees the per-stage
cost breakdown inline.

## Step 12.3: Dispatch-Audit Surfacing (WITNESS_MISSING terminal block)

Read `.agent-flow/dispatch-audit.log` (top-level path, NOT under
`{ISSUE-ID}/`). For this run's stages, classify each entry against the per-skill
`<stage_allowlist>` parsed from this skill's parent SKILL.md (`skills/fix-bugs/SKILL.md`).

The per-skill `stage_allowlist` for fix-bugs is:
- **required:** `triage`, `code_analysis`, `fixer_reviewer`, `smoke_check`, `test`, `publisher`
- **optional:** `reproduce_browser`, `e2e_test`, `browser_verification`, `acceptance_gate`

Parse the allow-list from the parent `skills/fix-bugs/SKILL.md` `<stage_allowlist>` ... `</stage_allowlist>`
block at file-position L11-14. Use awk or grep-block-extract:

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR:-skills/fix-bugs}"
ALLOWLIST_BLOCK=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' "${SKILL_DIR}/SKILL.md")
# Parse required + optional stages from the YAML-like body of the block.
```

**Parser hardening (prose-discipline contract):** After executing the awk extraction
above, validate that `ALLOWLIST_BLOCK` contains at least one `required:` line. If the extracted
block is empty, contains no `required:` line, or contains no `optional:` line (i.e., the
`<stage_allowlist>` block was malformed or missing its closing tag), emit the following WARN line
to stderr and proceed with **allow-all-stages semantics** (no filter applied — treat all audit
entries as potentially relevant):

```
[WARN] malformed <stage_allowlist> block in <SKILL_PATH>; falling back to allow-all-stages
```

where `<SKILL_PATH>` is the resolved path to the SKILL.md file (e.g., `skills/fix-bugs/SKILL.md`).

> Note: This is a **prose-discipline contract** — it is an instruction to the orchestrator/subagent
> dispatching this step, not a runtime-enforced shell-level contract. The awk command is preserved;
> the validation and fallback behaviour are performed immediately after the awk result is available.

For each WITNESS_MISSING entry in `.agent-flow/dispatch-audit.log` for this run:

| Stage in allow-list | Classification | Terminal-block treatment |
|---------------------|----------------|--------------------------|
| In `required` list  | **ANOMALY** — orchestrator silently skipped a required step | Render as the anomaly block (default-on, no env-var gate). User-visible warning. |
| In `optional` list AND stage's config-gating evaluated to "off" | EXPECTED_OPTIONAL_NOT_RUN | Render as info block (low-noise — explains why the stage didn't run). |
| In `optional` list AND stage's config-gating evaluated to "on" | **ANOMALY** | Render as anomaly block. |
| NOT in allow-list (hook STAGES superset entries — e.g., implement-feature-only stages bleeding in) | SUPPRESSED | Do NOT render. Not part of this pipeline's expected dispatch set. |

For WITNESS_MISMATCH entries: always render as ANOMALY. The witness now binds the resolved overlay
(`overlay_source` + `overlay_digest`), so a mismatch means either witness-field tampering/corruption
(hook V1 recompute failed) OR a dropped overlay — a `.toml` overlay present on disk but
`overlay_source != toml` (hook V2 overlay-presence check). Both are now enforced by the PostToolUse
hook; continue to surface them here in the terminal report.

For WITNESS_OK entries: never render (no action needed).

If `.agent-flow/dispatch-audit.log` does not exist: render a small info note "(no dispatch-audit
records — first invocation, or hook is disabled)" and continue. NEVER fail the terminal report on
missing audit log.

### Anomaly block render template

```
+============================================================+
| DISPATCH-AUDIT ANOMALY (run_id: {run_id})                  |
| Issue: {issue_id}                                          |
| Pipeline: fix-bugs                                         |
+============================================================+
| Stage              | Verdict          | Allow-list status   |
|--------------------|------------------|---------------------|
| {stage_name_1}     | WITNESS_MISSING  | required (ANOMALY) |
| {stage_name_2}     | WITNESS_MISMATCH | optional (ANOMALY) |
+------------------------------------------------------------+
| For investigation: cat .agent-flow/dispatch-audit.log     |
| Recommended: re-run /agent-flow:fix-bugs {issue_id}       |
|              with --step-mode to verify each dispatch.     |
+============================================================+
```

## Step 12.3b: Overlay-Drop Surfacing (silently-dropped override surfacing)

The `dispatch_witness` is computed from the RAW prompt template; the Agent Override overlay is
appended AFTER, so a silently-dropped overlay is INVISIBLE to the witness audit (Step 12.3 cannot
catch it). The `stages.<stage>.overlay_source` field is the only signal that the injector ran.
This sub-step surfaces the mismatch where a `customization/<agent>.toml` exists for a stage's
agent but the recorded `overlay_source` shows the overlay was NOT applied.

Resolve the override directory from `### Agent Overrides → Path` in Automation Config (default
`customization/`). For each stage block in `.agent-flow/{ISSUE-ID}/state.json` `stages.<stage>`:

1. Read `stages.<stage>.overlay_source`. If it is absent (legacy run) or equals `toml`, skip the
   stage (no anomaly — overlay applied, or no assertion recorded).
2. Derive the agent file basename: read `stages.<stage>.agent_name` and strip the `agent-flow:`
   namespace prefix (e.g. `agent-flow:fixer` → `fixer`).
3. Classify by the `overlay_source` value — each is an **OVERLAY DROP ANOMALY** but with a
   different trigger (do NOT gate both on `.toml` existence):
   - `md_rejected` → **always** an anomaly. This value is emitted only when `<basename>.md` exists
     while `<basename>.toml` does NOT, so checking for `.toml` here would always be false and hide
     it. A legacy `.md` overlay is present but unsupported (the `.toml` form is required). Record
     `<stage>`, `<agent_name>`, `md_rejected`, and the rejected `{Agent Overrides path}/<basename>.md`
     path for the render block below.
   - `none` → an anomaly **only if** `{Agent Overrides path}/<basename>.toml` EXISTS: a
     project-configured overlay was present on disk but `overlay_source` proves it never reached the
     dispatched prompt (the injector absorbed a parse/validation failure). Record `<stage>`,
     `<agent_name>`, `none`, and the resolved `.toml` path. If no `<basename>.toml` exists, this is a
     legitimate `none` (no overlay configured) — skip, no anomaly.

If no stage produced a mismatch, render nothing (clean — consistent with the WITNESS_OK convention
in Step 12.3). NEVER fail the terminal report on overlay drops — this surfacing is advisory only,
exactly like the witness surfacing above.

### Overlay-drop block render template

```
+============================================================+
| OVERLAY-DROP ANOMALY (run_id: {run_id})                    |
| Issue: {issue_id}                                          |
| Pipeline: fix-bugs                                         |
| A configured customization/<agent>.toml overlay existed    |
| but overlay_source proves it was silently dropped.         |
+============================================================+
| Stage              | Agent            | overlay_source      |
|--------------------|------------------|---------------------|
| {stage_name_1}     | {agent_name_1}   | none                |
| {stage_name_2}     | {agent_name_2}   | md_rejected         |
+------------------------------------------------------------+
| Dropped overlay file(s):                                   |
|   {Agent Overrides path}/{basename_1}.toml  (none)         |
|   {Agent Overrides path}/{basename_2}.md    (md_rejected)  |
| Recommended: re-run with --step-mode and confirm the       |
|   injector applied each customization/<agent>.toml; rename  |
|   any legacy customization/<agent>.md to .toml.            |
+============================================================+
```

## Step 12.4: pipeline-completed webhook

After all state writes and terminal output, fire `pipeline-completed` if Notifications → Webhook URL
exists and `pipeline-completed` is in On events:
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "{Webhook URL}" <<EOF
{"event":"pipeline-completed","run_id":"${run_id}","issue_id":"${issue_id}","status":"completed","outcome":"success","duration":${total_duration_seconds},"pr_url":"${pr_url}","timestamp":"${ISO8601}"}
EOF
```
On block: fire with `"outcome":"blocked"` and `"pr_url":null` after terminal block state is committed.
On catastrophic fall-through (Step Z): fire with `"outcome":"failed"` and `"pr_url":null`.
Webhook failure → log `[WARN] Webhook delivery failed: {error}`, continue.

<!-- @snippet:pipeline-completion -->
### Step Z: Catastrophic exit handler (outcome: failed, per-bug)

If the per-bug pipeline reaches the end of all expected steps and the per-issue `state.json`
`status` field is still `"running"` (no terminal `completed`/`blocked`/`paused` transition
committed), the skill MUST attempt to fire `pipeline-completed` with `outcome: "failed"` and
`pr_url: null`, and write `{"status":"failed","outcome":"failed"}` atomically to state.json.

**Limitation:** `outcome: "failed"` covers logical fall-through only — does NOT fire on process
death (OOM, SIGKILL, API timeout). Those leave state.json in `running` indefinitely until external
intervention. A future heartbeat / watchdog would be required for true crash detection.
