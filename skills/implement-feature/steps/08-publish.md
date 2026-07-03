# Step 08 — Publish + Dispatch Audit Surface

## Pre-publish hook + custom agent

If Hooks → Pre-publish exists: run the command via Bash.
If Custom Agents → Pre-publish agent exists: run via Task tool.

## Display result + PR confirmation

Display to the user:
- Summary of changes (files, lines)
- Test results
- In yolo mode → auto-create PR (zero checkpoints, no prompt). Otherwise: "Create PR? [Y/n]"

If the user agrees (or yolo mode) → dispatch publisher.

## Publisher

Before dispatching publisher: read `model:` frontmatter from `agents/publisher.md`. Write to `state.json`:
`publisher.started_at`, `publisher.model`, `publisher.status: "in_progress"`, and initialize
`publisher.tokens_used: 0`, `publisher.duration_ms: 0`, `publisher.tool_uses: 0`. Follow atomic write
protocol from `../../../core/state-manager.md`.

### Pre-dispatch witness write

publisher binds to canonical stage `publisher` per design.md §4.2.

```bash
. core/lib/stage-invariant.sh
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$PUBLISHER_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness publisher agent-flow:publisher haiku "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
DISPATCHED_AT="$(date -u +%FT%TZ)"
EXPECTED_AGENT_NAME="agent-flow:publisher"
EXPECTED_STAGE_NAME="publisher"
# Merge: state.json[stages.publisher] = { dispatched_at, agent_name, stage_name,
#   prompt_head_128, overlay_source, overlay_digest, dispatch_witness, status="in_progress" }
#   in ONE atomic write. Then append OVERLAY_BLOCK to the prompt.
```

## Agent Override injection

Before dispatch, check Agent Overrides: follow `../../../core/agent-override-injector.md`.
If `{Agent Overrides path}/publisher.toml` exists, append its rendered Markdown content to the agent's context as `## Project-Specific Instructions`.

You MUST invoke Task(subagent_type='agent-flow:publisher', model='haiku'). DO NOT inline-execute.
- Context: `Mode: feature. Pipeline: implement-feature.` + PR Description Template, Labels, Remote,
  Base branch, changed files

After dispatch: defensive-read `result.usage`. Write to `state.json`:
`publisher.completed_at`, `publisher.tokens_used` (fallback 0), `publisher.duration_ms` (elapsed ms,
fallback 0), `publisher.tool_uses` (fallback 0), `publisher.status: "completed"`, `publisher.pr_url`,
`publisher.branch`. Follow atomic write protocol from `../../../core/state-manager.md`.

**Fire `step-completed` webhook:** After the atomic state.json write succeeds, if `Webhook URL` is configured
AND `step-completed` is in `On events`, fire with `step_name: "publisher"`, `iteration_count: 1`. Advisory
failure: log `[WARN]` and continue.

## Step 8.3: Dispatch Audit Surfacing (post-publish, before final summary)

Read `.agent-flow/dispatch-audit.log` (or absent → silent). Parse each line and classify per the
`<stage_allowlist>` block declared at the top of `skills/implement-feature/SKILL.md`:

- **ANOMALY** — stage is in REQUIRED list AND no `WITNESS_OK` audit line for this run.
- **EXPECTED_OPTIONAL_NOT_RUN** — stage is in OPTIONAL list AND no audit line (info-level, NOT anomaly).
- **OK** — `WITNESS_OK` audit line present.
- **SUPPRESSED** — stage is NOT in REQUIRED or OPTIONAL list (do not surface; this is a stage from
  another skill's pipeline).

> **Overlay binding note:** the dispatch witness now binds the resolved overlay (`overlay_source` +
> `overlay_digest`), so a dropped overlay (a `.toml` present on disk but `overlay_source != toml`)
> is enforced by the hook's V2 overlay-presence check and surfaces here as a `WITNESS_MISMATCH`
> audit line. Continue to surface such entries as anomalies via the terminal block below.

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR:-skills/implement-feature}"
ALLOWLIST_BLOCK=$(awk '/<stage_allowlist>/{f=1;next} /<\/stage_allowlist>/{exit} f' "${SKILL_DIR}/SKILL.md")
# Parser supports both line-per-stage and comma-separated forms.
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

where `<SKILL_PATH>` is the resolved path to the SKILL.md file (e.g., `skills/implement-feature/SKILL.md`).

> Note: This is a **prose-discipline contract** — it is an instruction to the orchestrator/subagent
> dispatching this step, not a runtime-enforced shell-level contract. The awk command is preserved;
> the validation and fallback behaviour are performed immediately after the awk result is available.

If ANOMALY count > 0, render:
```
[agent-flow] Dispatch audit anomalies detected:
  Stage: {stage_name}  Status: WITNESS_MISSING  Severity: REQUIRED
  ...
For investigation: cat .agent-flow/dispatch-audit.log
```

If only EXPECTED_OPTIONAL_NOT_RUN entries (and OK entries), render NO block (clean run).
If `.agent-flow/dispatch-audit.log` does not exist: silent (NEVER fail the terminal report).

## Step 8.4: Overlay-Drop Surfacing (silently-dropped override surfacing)

The `dispatch_witness` is computed from the RAW prompt template; the Agent Override overlay is
appended AFTER, so a silently-dropped overlay is INVISIBLE to the witness audit (Step 8.3 cannot
catch it). The `stages.<stage>.overlay_source` field is the only signal that the injector ran.
This sub-step surfaces the mismatch where a `customization/<agent>.toml` exists for a stage's
agent but the recorded `overlay_source` shows the overlay was NOT applied.

Resolve the override directory from `### Agent Overrides → Path` in Automation Config (default
`customization/`). For each stage block in `state.json` `stages.<stage>`:

1. Read `stages.<stage>.overlay_source`. If absent (legacy run) or equal to `toml`, skip (no anomaly).
2. Derive the agent file basename from `stages.<stage>.agent_name` by stripping the `agent-flow:`
   namespace prefix (e.g. `agent-flow:fixer` → `fixer`).
3. Classify by value — each is an **OVERLAY DROP ANOMALY** with a different trigger (do NOT gate
   both on `.toml` existence):
   - `md_rejected` → **always** an anomaly. It is emitted only when `<basename>.md` exists while
     `<basename>.toml` does NOT, so a `.toml` check would always hide it. A legacy `.md` overlay is
     present but unsupported (the `.toml` form is required). Dropped file: `<basename>.md`.
   - `none` → an anomaly **only if** `{Agent Overrides path}/<basename>.toml` EXISTS (the injector
     absorbed a parse/validation failure on a present overlay). Otherwise it is a legitimate `none`
     (no overlay configured) — skip. Dropped file: `<basename>.toml`.

If any mismatch exists, render:
```
[agent-flow] Overlay-drop anomalies detected (configured override silently dropped):
  Stage: {stage_name}  Agent: {agent_name}  overlay_source: {none|md_rejected}  Dropped: {Agent Overrides path}/{basename}.{toml|md}
  ...
Recommended: re-run /agent-flow:implement-feature with --step-mode and confirm each customization/<agent>.toml is applied (rename any legacy customization/<agent>.md to .toml).
```
If no stage produced a mismatch, render NO block (clean run — consistent with Step 8.3). NEVER fail
the terminal report on overlay drops — advisory surfacing only, exactly like the dispatch-audit block.

## Pipeline completion

**Pipeline accumulator (COST-R6):** Before writing the terminal `status`, compute and write to `state.json`:
```
pipeline.total_tokens      = sum({stage}.tokens_used   for all completed stages)
pipeline.total_duration_ms = sum({stage}.duration_ms   for all completed stages)
pipeline.total_tool_uses   = sum({stage}.tool_uses      for all completed stages)
pipeline.summary_table     = markdown table (bounded: ≤20 rows, ≤4000 chars; truncate with notice row before Total)
```
Then write top-level `status: "completed"`. Follow atomic write protocol from `../../../core/state-manager.md`.

**Echo `pipeline.summary_table` to stdout.**

<!-- @snippet:pipeline-completion -->
**Fire `pipeline-completed` webhook:**
<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "${Webhook_URL}" <<EOF
{"event":"pipeline-completed","run_id":"${run_id}","issue_id":"${issue_id}","status":"completed","outcome":"success","duration":${total_duration_s},"pr_url":"${pr_url}","timestamp":"${ISO8601_UTC}"}
EOF
```
Advisory failure: log `[WARN] Webhook delivery failed: {error}` and continue.

## Post-publish hook + webhook

Follow `../../../core/post-publish-hook.md` for hook execution and webhook firing.

## Feature Verification (optional)

Follow `../../../core/fix-verification.md`. If Build & Test → Verify exists in Automation Config:
1. Wait for PR merge (query via MCP server, max 5 attempts with 30s interval).
   If PR not merged after 5 attempts → display warning and exit.
2. Checkout base branch and pull: `git checkout {base_branch} && git pull`
3. Run the Verify command from Automation Config.
4. If OK → add a success comment to the issue.
5. If FAIL → add a failure comment, re-open issue if State transitions supports it, display to user.
