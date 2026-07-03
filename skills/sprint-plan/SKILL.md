---
name: sprint-plan
description: Plans a sprint from backlog issues using capacity constraints and priority ranking
allowed-tools: mcp__*, Bash, Read, Glob, Grep, Task
argument-hint: "[--all] [--apply] [--dry-run] [--limit <N>] [--yolo]"
disable-model-invocation: true
---

# Sprint Plan

Input: `$ARGUMENTS` = optional flags (`--all`, `--apply`, `--dry-run`, `--limit <N>`, `--yolo`)

## Flag Parsing

Parse `$ARGUMENTS`:
- `--all`: Plan ALL sprints (release plan), not just the next one
- `--apply`: After planning, dispatch `/agent-flow:implement-feature` or `/agent-flow:fix-bugs` per selected issue
- `--dry-run`: Display plan only, no tracker writes, no execution dispatch
- `--limit <N>`: Override Max issues config value (valid range: 1–50; out of range → clamp with WARN)
- `--yolo`: Auto-approve Gate 1 and Gate 3 (Gate 2 ALWAYS blocks — even in `--yolo`)

`--yolo` does NOT imply `--apply`. Explicit `--yolo --apply` is required for full automation.
`--dry-run` overrides `--apply` (if both present, dry-run wins — no tracker writes, no execution).

## Configuration

Read Automation Config from CLAUDE.md section `## Automation Config`. Follow `../../core/config-reader.md`.

**Required:**
- Issue Tracker: Type, Instance, Project, Bug query

**Sprint Planning section** (optional — recommended; see Cold-start rules if absent):
- Sprint duration (default: `2 weeks`)
- Capacity unit (default: `story-points`)
- Team capacity (default: none)
- Velocity target (default: none)
- Sprint field (default: tracker-dependent)
- Mode (default: `suggest`) — `apply` auto-approves Gate 1 and Gate 3 (same effect as `--yolo`; Gate 2 is never affected). Does NOT trigger execution dispatch — that is controlled solely by the `--apply` CLI flag (Step 6). See Gate 1/Gate 3 Behavior and Rules below.
- Max issues (default: 20)
- Epic template (default: none)

If `### Sprint Planning` section is absent: run in suggest mode with cold-start warnings at every gate.
Do NOT block — planning still proceeds with `effective_capacity = null` (unconstrained).

**Optional:**
- Feature Workflow: Feature query (combined with Bug query for issue fetch)
- Metrics: Output (path to metrics report; default: `./reports/metrics.md`)
- Agent Overrides: Path (default: `customization/`)
- Build & Test: Build command, Test command (required only if `--apply`)

**Config validation rules:**
- `Sprint duration`: must be `1 week`, `2 weeks`, `3 weeks`, or `4 weeks`. Other values: WARN, use `2 weeks`.
- `Capacity unit`: must be `story-points` or `hours`. Other values: WARN, use `story-points`.
- `Team capacity`: must be positive integer. 0 treated as unconfigured.
- `Velocity target`: must be positive integer. If `Velocity target > Team capacity` (both set): WARN "Velocity target ({V}) exceeds Team capacity ({C}). Using Team capacity." Use Team capacity.
- `Mode`: must be `suggest` or `apply`. Other values: WARN, use `suggest`. `apply` auto-approves Gate 1 and Gate 3 (see Rules); it is unrelated to the `--apply` CLI flag, which controls execution dispatch (Step 6).
- `Max issues`: must be integer 1–50. Out of range: clamp to [1, 50] with WARN.
- `Epic template`: file path. If set but file not found: WARN, use built-in template.

## Orchestration

### Step 0: MCP pre-flight check

Follow `../../core/mcp-preflight.md`. Before any pipeline operation, verify MCP tool availability:
- Read Type from Automation Config (Issue Tracker section)
- Check that at least one `mcp__*` tool matching the tracker type is accessible
- If not accessible → STOP with: "Cannot connect to your {Type} issue tracker. Is the {Type} integration configured? Run `/agent-flow:check-setup` for diagnostics."

**Tracker write-capability probe** (for Gate 1 display only — `core/mcp-preflight.md` only verifies READ connectivity above; it has no concept of write fallback and does not produce this value):
- `MCP` — the Tier 1 MCP write tool for this tracker (see Step 5 "Tier 1: MCP sprint assignment" table) is accessible
- `Bash` — the MCP write tool is unavailable, but the Tier 2 auth environment variable for this tracker (see Step 5 "Tier 2: Bash + REST fallback" table) is set
- `Skip` — neither is available

Record the result as `tracker_tier`. This is advisory/best-effort only: the actual mechanism is re-resolved independently per issue by Step 5's own 3-tier fallback and MAY differ from this label for individual issues.

### Step 0b: State initialization

Create `.agent-flow/sprint-{YYYYMMDD-HHmmss}/` directory.
Initialize `state.json` following the schema in `state/schema.md` with:
- `status: "running"`, `mode: "sprint-planning"`, `pipeline: "sprint-plan"`
- `run_id: "sprint-{YYYYMMDD-HHmmss}"`
- `sprint.name`: null (populated after Gate 1)
- `sprint.issues`: [] (populated after Gate 1)

Follow atomic write protocol from `../../core/state-manager.md`.

### Step 0c: Velocity source determination

3-tier fallback — determine `effective_capacity` and `velocity_source`:

**Tier 1 (historical):** Check if `./reports/metrics.md` (or Metrics → Output path) exists.
- If yes and parseable: from the report's `### Pipeline Overview` table (see `skills/metrics/SKILL.md`), read `Issues attempted` (N, raw count — total_attempted) and the success rate percentage shown parenthetically on the `Issues fixed` row (`{N} ({rate}%)` — rate is `success_rate`), plus `Avg time to fix` (hours, informational only — not used in the formula below); from the report header `## Pipeline Metrics Report — {project} ({period} days)`, read `period` in days. Compute:
  ```
  issues_attempted_per_week = Issues_attempted_N / (period_days / 7)
  sprint_weeks               = numeric value of Sprint duration (1-4)
  projected_issues           = issues_attempted_per_week × sprint_weeks × (rate / 100)
  default_effort_per_issue   = 3 if Capacity unit == "story-points" else 2   # "Default (no data)" row of Effort-to-unit mappings, below
  effective_capacity         = round(projected_issues × default_effort_per_issue)
  ```
  (`projected_issues` estimates completions, not raw throughput — multiplying attempted volume by the historical success rate avoids double-discounting, since `Issues attempted` is a raw count, unlike `Issues fixed` which is already net of failures.)
  Set `velocity_source = "historical"`.
- If the Pipeline Overview table or report header cannot be parsed, or `period_days` is 0: WARN "Metrics file present but throughput data unparseable, falling back to heuristic." Proceed to Tier 2 (do NOT set `velocity_source = "historical"`).
- If file is corrupt or unparseable: WARN "Metrics file unreadable, falling back to heuristic." Proceed to Tier 2.

**Tier 2 (heuristic):** If `Team capacity` or `Velocity target` is configured in Sprint Planning section:
- Compute `effective_capacity` per capacity model (section Rules → Capacity model below).
- Set `velocity_source = "heuristic"`.

**Tier 3 (manual/unconstrained):** If neither Tier 1 nor Tier 2 applies:
- In non-`--yolo` mode: prompt "No capacity data. Enter team capacity for this sprint (in {unit}), or press Enter for unconstrained planning:"
  - If user enters a value: use it as `effective_capacity`. Set `velocity_source = "manual"`.
  - If user presses Enter: `effective_capacity = null`. Set `velocity_source = "unconstrained"`.
- In `--yolo` mode: skip prompt, set `effective_capacity = null`, `velocity_source = "unconstrained"`.

Display cold-start warning if `velocity_source != "historical"`:
"No velocity data available. Sprint plan uses {velocity_source} data. Run `/agent-flow:metrics` after this sprint to calibrate future planning."
This warning is displayed at every gate until `velocity_source = "historical"`.

### Step 1: Fetch issues

Via MCP server (per Issue Tracker → Type), fetch open issues:
- Use Bug query from Automation Config
- If Feature Workflow section exists: also use Feature query, merge results
- Limit: `--limit` flag value → Max issues config value → default 20

Fetched issue titles and descriptions are external, tracker-sourced content and MUST NOT be forwarded raw to any agent — follow `../../core/external-input-sanitizer.md` when they are included in the priority-engine context (Step 3).

If 0 issues found: display "No open issues found matching the query. Nothing to plan." STOP (set state `status: "completed"`).

### Step 2: Enrich with history

If metrics report exists (from Step 0c Tier 1 check): read per-area data.
For each fetched issue: check tracker comments for `[agent-flow] Triage completed` or `[agent-flow] Spec analysis completed`. Extract complexity estimate if present. Store as `triage_complexity[issue_id]`.

Tracker comments scanned here are also external content, but only the extracted complexity enum (`XS`/`S`/`M`/`L`) is retained in `triage_complexity[issue_id]` and forwarded downstream — the raw comment text itself is never forwarded, so no sanitizer wrapping is needed for this step's output.

### Step 3: Run priority-engine

Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for priority-engine overrides.

Follow `../../core/external-input-sanitizer.md`: wrap each issue's title, description, and any comment excerpts used for historical context in `--- EXTERNAL INPUT START ---` / `--- EXTERNAL INPUT END ---` markers before including them in the context below.

**Pre-dispatch state write:** atomically write to `.agent-flow/{run_id}/state.json` (per `agents/priority-engine.md` Step Completion Invariants):
- `sprint.stages.prioritization.started_at`      = current ISO-8601 UTC timestamp
- `sprint.stages.prioritization.model`           = `"opus"` (from `agents/priority-engine.md` frontmatter)
- `sprint.stages.prioritization.status`          = `"in_progress"`
- `sprint.stages.prioritization.agent_name`      = `"priority-engine"`
- `sprint.stages.prioritization.stage_name`      = `"prioritization"`
- `sprint.stages.prioritization.dispatched_at`   = current ISO-8601 UTC timestamp
- `sprint.stages.prioritization.dispatch_witness` = sha256("agent-flow:priority-engine|opus|<prompt_head_128>")
  (compute via `core/lib/stage-invariant.sh::compute_dispatch_witness`; prompt_head_128 is the
   first 128 UTF-8-safe bytes of the un-expanded prompt template, BEFORE Tier-1 variable injection)
- `sprint.stages.prioritization.tokens_used` = 0, `.duration_ms` = 0, `.tool_uses` = 0 (safe defaults)

Follow atomic write protocol from `../../core/state-manager.md`. All fields written in a single atomic replace.

You MUST invoke `Task(subagent_type='agent-flow:priority-engine', model='opus')`. DO NOT inline-execute.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "priority-engine"`, `EXPECTED_STAGE_NAME = "prioritization"`.

Context: list of issues (sanitizer-wrapped per above) + historical data (if available) + triage complexity map + `EXPECTED_AGENT_NAME` + `EXPECTED_STAGE_NAME`.

**Post-dispatch state write:** after the agent returns, atomically write:
- `sprint.stages.prioritization.completed_at` = current ISO-8601 UTC timestamp
- `sprint.stages.prioritization.status`       = `"completed"` (or `"blocked"` — see failure handling below)
- `sprint.stages.prioritization.tokens_used`  = `result.usage.total_tokens` (or 0 if absent)
- `sprint.stages.prioritization.duration_ms`  = `completed_at` epoch ms − `started_at` epoch ms
- `sprint.stages.prioritization.tool_uses`    = `result.usage.tool_uses` (or 0 if absent)

Follow atomic write protocol from `../../core/state-manager.md`.

If priority-engine fails, returns an error, or Blocks (including a Step Completion Invariant violation): set `sprint.stages.prioritization.status = "blocked"` and BLOCK with:
```
[agent-flow] 🔴 Pipeline Block
Agent: priority-engine
Step: Step 3 (Priority ranking)
Reason: Priority-engine agent failed.
Detail: {error output}
Recommendation: Check agent logs. Run /agent-flow:prioritize standalone to diagnose.
```

### Step 4: Run sprint-planner

Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for sprint-planner overrides.

**Pre-dispatch state write:** atomically write to `.agent-flow/{run_id}/state.json` (per `agents/sprint-planner.md` Step Completion Invariants):
- `sprint.stages.sprint_planning.started_at`      = current ISO-8601 UTC timestamp
- `sprint.stages.sprint_planning.model`           = `"sonnet"` (from `agents/sprint-planner.md` frontmatter)
- `sprint.stages.sprint_planning.status`          = `"in_progress"`
- `sprint.stages.sprint_planning.agent_name`      = `"sprint-planner"`
- `sprint.stages.sprint_planning.stage_name`      = `"sprint_planning"`
- `sprint.stages.sprint_planning.dispatched_at`   = current ISO-8601 UTC timestamp
- `sprint.stages.sprint_planning.dispatch_witness` = sha256("agent-flow:sprint-planner|sonnet|<prompt_head_128>")
  (compute via `core/lib/stage-invariant.sh::compute_dispatch_witness`; prompt_head_128 is the
   first 128 UTF-8-safe bytes of the un-expanded prompt template, BEFORE Tier-1 variable injection)
- `sprint.stages.sprint_planning.tokens_used` = 0, `.duration_ms` = 0, `.tool_uses` = 0 (safe defaults)

Follow atomic write protocol from `../../core/state-manager.md`. All fields written in a single atomic replace.

You MUST invoke `Task(subagent_type='agent-flow:sprint-planner', model='sonnet')`. DO NOT inline-execute.

Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "sprint-planner"`, `EXPECTED_STAGE_NAME = "sprint_planning"`.

Context:
- Priority-engine output (full ranked list: P0/P1/P2 tiers) — already agent-produced structured markdown, not raw external content; no sanitizer wrapping needed
- Sprint Planning config values: sprint_duration, capacity_unit, effective_capacity, velocity_source
- Triage complexity map (from Step 2 — extracted enum values only)
- `--all` flag presence (if set, sprint-planner generates multi-sprint release plan)
- `EXPECTED_AGENT_NAME`, `EXPECTED_STAGE_NAME`

**Post-dispatch state write:** after the agent returns, atomically write:
- `sprint.stages.sprint_planning.completed_at` = current ISO-8601 UTC timestamp
- `sprint.stages.sprint_planning.status`       = `"completed"` (or `"blocked"` — see below)
- `sprint.stages.sprint_planning.tokens_used`  = `result.usage.total_tokens` (or 0 if absent)
- `sprint.stages.sprint_planning.duration_ms`  = `completed_at` epoch ms − `started_at` epoch ms
- `sprint.stages.sprint_planning.tool_uses`    = `result.usage.tool_uses` (or 0 if absent)

Follow atomic write protocol from `../../core/state-manager.md`.

If sprint-planner fails or Blocks (including a Step Completion Invariant violation): set `sprint.stages.sprint_planning.status = "blocked"` and BLOCK pipeline with sprint-planner's block detail.

### Gate 1: Capacity Confirmation

Display the full sprint-planner output table.

If `velocity_source != "historical"`: display cold-start warning (see Step 0c).

Display prompt:
```
Sprint plan uses {used}/{effective_capacity or "∞"} {unit}. {N} issues selected, {M} overflow.
Tracker assignment: {tracker_tier} ({tracker_type})
Execution: {suggest only | --apply}

Accept this sprint plan? [Y/n]
```

Behavior:
- `--yolo` OR Sprint Planning `Mode: apply`: auto-approve, display "[auto-approved]"
- User enters Y or presses Enter: proceed to Gate 2
- User enters n: STOP with "Sprint planning cancelled." Set state `status: "completed"` (clean exit).

Update `state.json`: write sprint issue list with effort scores, `effective_capacity`, `velocity_source`.
Follow atomic write protocol from `../../core/state-manager.md`.

### Gate 2: Unmapped AC Warning

For each issue in the Selected Issues table:
1. Check if `triage_complexity[issue_id]` exists (from Step 2 enrichment)
2. If not: AC count = 0 (no triage/spec analysis found)
3. If yes: extract AC count from the triage/spec comment
4. If AC count < 2: add to `unmapped_ac_list`

If `unmapped_ac_list` is non-empty:
- Display:
  ```
  WARNING: The following issues have insufficient acceptance criteria for quality implementation:

  | Issue | AC Count | Concern |
  |-------|----------|---------|
  | {ID}  | {N}      | {No triage/spec analysis found | Only {N} AC — may produce incomplete implementation} |

  Issues without sufficient AC may produce lower-quality implementations.
  Consider running /agent-flow:analyze-bug or /agent-flow:implement-feature --dry-run on these issues first.

  Continue with sprint? [Y/n]
  ```
- This gate BLOCKS even in `--yolo` mode or Sprint Planning `Mode: apply`. Display warning and prompt regardless.
- User enters Y: proceed to Gate 3
- User enters n: STOP with "Sprint planning cancelled due to AC concerns." Set state `status: "completed"`.

### Gate 3: Final Confirmation

If `--dry-run`: display plan summary and STOP before tracker writes:
"Dry run complete. No tracker writes performed." Set state `status: "completed"`.

Display:
```
Ready to start sprint:
- Sprint: {sprint_name}
- Issues: {N}
- Total effort: {total_points} {unit}
- Tracker writes: {sprint assignment via {tracker_tier} ({tracker_type}) | skipped (--dry-run)}
- Execution: {suggest only (use --apply to auto-execute) | auto-execute (--apply)}

Proceed? [Y/n]
```

Behavior:
- `--yolo` OR Sprint Planning `Mode: apply`: auto-approve, display "[auto-approved]"
- User enters Y or presses Enter: proceed to Step 5
- User enters n: STOP with "Sprint planning cancelled before tracker writes." Set state `status: "completed"`.

Update `state.json`: mark `status` as `"approved"`. Follow atomic write protocol from `../../core/state-manager.md`.

### Step 5: Sprint assignment

Generate `sprint_name`: `Sprint {YYYY}-W{WW}` (current year, current ISO week number, zero-padded).

**Name-to-ID resolution (pre-loop):** For trackers requiring internal IDs (Jira, Linear, GitHub, Gitea, Redmine), resolve sprint/milestone/cycle name to tracker-internal identifier ONCE before the assignment loop. Cache the resolved ID.
- If resolution fails (no match found): WARN "Sprint/milestone '{sprint_name}' not found in {tracker_type}. Create it manually and re-run." Skip all assignments for this tracker (NON-BLOCKING). Continue to Step 6.
- If multiple matches: use exact string match. If still ambiguous: use most recently created entry and WARN "Multiple sprints matching '{sprint_name}' found. Using most recent: {selected_id}."

**Jira pre-check:** Detect Scrum vs Kanban board. If Kanban: skip sprint operations entirely, display "Kanban board detected — sprint assignment skipped. Sprint plan is still generated." NON-BLOCKING.

For each selected issue, execute sprint assignment using 3-tier fallback:

#### Tier 1: MCP sprint assignment

| Tracker | MCP Tool | Parameters | Notes |
|---------|----------|------------|-------|
| YouTrack | `mcp__youtrack__update_issue` or equivalent | `issueId: {ID}`, `field: {Sprint field from config or "Sprint"}`, `value: {sprint_name}` | Sprint field name from config (default: `Sprint`) |
| Jira | `mcp__jira__add_issues_to_sprint` or equivalent | `sprintId: {resolved_id}`, `issues: [{ID}]` | Pre-check: board.type must be "scrum". If Kanban: skip. |
| Linear | `mcp__linear__update_issue` or equivalent | `issueId: {ID}`, `cycleId: {resolved_uuid}` | Requires name-to-UUID resolution via `list_cycles` |
| GitHub | `mcp__github__update_issue` or equivalent | `owner: {owner}`, `repo: {repo}`, `issue_number: {N}`, `milestone: {resolved_number}` | Requires milestone name-to-number resolution |
| Gitea | Skip to Tier 2 | -- | Gitea MCP sprint assignment unverified; go directly to Tier 2 |
| Redmine | `mcp__redmine__update_issue` or equivalent | `issue_id: {ID}`, `fixed_version_id: {resolved_id}` | Always Version, no Agile Plugin detection. Requires version name-to-ID resolution. |

If Tier 1 MCP call fails (tool unavailable or call error): fall through to Tier 2.

#### Tier 2: Bash + REST fallback

Only attempted if Tier 1 fails (MCP tool not available or MCP call returns error).
If the required environment variable is not set: skip to Tier 3 immediately. Never prompt for tokens mid-pipeline.

| Tracker | Command Pattern | Auth Environment Variable |
|---------|----------------|--------------------------|
| YouTrack | `curl -X POST {instance}/api/issues/{ID} -H "Authorization: Bearer $YOUTRACK_TOKEN" -H "Content-Type: application/json" -d '{"customFields":[{"name":"{sprint_field}","$type":"SingleEnumIssueCustomField","value":{"name":"{sprint_name}"}}]}'` | `YOUTRACK_TOKEN` |
| Jira | `curl -X POST {instance}/rest/agile/1.0/sprint/{resolved_id}/issue -u "$JIRA_USER:$JIRA_TOKEN" -H "Content-Type: application/json" -d '{"issues":["{ID}"]}'` | `JIRA_USER`, `JIRA_TOKEN` |
| Linear | `curl -X POST https://api.linear.app/graphql -H "Authorization: $LINEAR_TOKEN" -H "Content-Type: application/json" -d '{"query":"mutation { issueUpdate(id: \"{ID}\", input: {cycleId: \"{resolved_uuid}\"}) { success } }"}'` | `LINEAR_TOKEN` |
| GitHub | `curl -X PATCH https://api.github.com/repos/{owner}/{repo}/issues/{issue_number} -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d '{"milestone": {resolved_number}}'` | `GITHUB_TOKEN` |
| Gitea | `curl -X PATCH {instance}/api/v1/repos/{owner}/{repo}/issues/{issue_number} -H "Authorization: token $GITEA_TOKEN" -H "Content-Type: application/json" -d '{"milestone": {resolved_id}}'` | `GITEA_TOKEN` |
| Redmine | `curl -X PUT {instance}/issues/{ID}.json -H "X-Redmine-API-Key: $REDMINE_TOKEN" -H "Content-Type: application/json" -d '{"issue":{"fixed_version_id":{resolved_id}}}'` | `REDMINE_TOKEN` |

#### Tier 3: Skip + Warn

Display: "Could not assign {ID} to {sprint_name} in {tracker_type}. Assign manually in your tracker."
Set `sprint_assigned: false` for this issue. Continue to next issue.

**All assignment failures are NON-BLOCKING.** On any tier failure: log WARN, set `sprint_assigned: false`, continue.

After all assignments: display "Assigned {success}/{total} issues to {sprint_name}."

Update `state.json` per issue: write `sprint_assigned` (true/false). Follow atomic write protocol from `../../core/state-manager.md`.

### Step 6: Execution dispatch (`--apply` only)

If `--apply` is NOT present: display suggested commands and STOP:
```
Sprint planned. To implement:
/agent-flow:implement-feature {ID-1}
/agent-flow:implement-feature {ID-2}
...
/agent-flow:fix-bugs {BUG-ID-1}
```

If `--apply` is present: for each selected issue in dependency order:
1. Determine type: if issue labels/type contain "bug" → dispatch `/agent-flow:fix-bugs {ID}`; otherwise → dispatch `/agent-flow:implement-feature {ID}`
2. Wait for child pipeline completion before starting dependent issues
3. On child pipeline block: mark dependent issues as blocked too; log WARN; continue with non-dependent issues
4. Update `state.json` per child: write `child_run_id`, issue `status`, increment `completed_issues` or `blocked_issues`

Update `state.json`: set top-level `status` to `"completed"`. Follow atomic write protocol from `../../core/state-manager.md`.

### Step 7: `--all` mode (release plan)

If `--all` is set and overflow issues remain after Step 5:
- Advance sprint_name by the configured Sprint duration in weeks (`D` = Sprint duration in weeks, default 2 — e.g. `1 week` → D=1, `2 weeks` → D=2), incrementing the ISO week by D and handling year boundary
- Repeat Steps 4–6 for remaining overflow issues, allocating them into subsequent sprints
- Continue until all issues are allocated or Max issues * 10 guard limit is reached (prevent infinite loop)

Append release summary after all sprints:
```
### Release Summary
| Sprint | Issues | {unit} | Notable |
|--------|--------|--------|---------|
| Sprint {YYYY}-W{WW} | {N} | {total} {unit} | {P0 issues or "--"} |
| Sprint {YYYY}-W{WW+D} | {N} | {total} {unit} | -- |
| Sprint {YYYY}-W{WW+2D} | {N} | {total} {unit} | -- |
...
```
(`D` = Sprint duration in weeks, default 2; each subsequent row advances by D weeks from the previous row — e.g. with the default 2-week duration, `W{WW+2}`, `W{WW+4}`, ...)

## Rules

- sprint_assign is ALWAYS NON-BLOCKING — failure → WARN, continue, never block pipeline
- priority-engine ranking is AUTHORITATIVE — sprint-planner NEVER re-ranks issues
- priority-engine is invoked ONCE per sprint-plan run — never re-invoked within same invocation
- Sprint name format: `Sprint {YYYY}-W{WW}` (ISO 8601 week, zero-padded, e.g. `Sprint 2026-W16`)
- No sprint creation — assign to existing sprints/milestones only. If target does not exist: WARN and skip assignment (NON-BLOCKING)
- Gate 2 ALWAYS blocks regardless of `--yolo` or Sprint Planning `Mode: apply` — insufficient AC is a quality signal that cannot be bypassed
- Sprint Planning `Mode: apply` auto-approves Gate 1 and Gate 3 (identical effect to `--yolo`) but is otherwise independent of it — the two may be combined or used alone. `Mode: apply` never bypasses Gate 2 and never triggers Step 6 execution dispatch by itself; dispatch requires the explicit `--apply` CLI flag regardless of `Mode`
- `--dry-run` wins over `--apply` when both are present
- `--yolo --apply` is the only path to fully automated sprint dispatch (`Mode: apply` alone still requires the `--apply` CLI flag to reach Step 6)
- Cold-start warning is displayed at every gate when `velocity_source != "historical"`
- Agent Overrides: follow `../../core/agent-override-injector.md` before every Task dispatch
- Jira Kanban detection: if board type is Kanban → skip all sprint assignment operations; plan is still generated and displayed

### Capacity model

```
IF Team capacity AND Velocity target both configured:
    IF Velocity target > Team capacity:
        WARN "Velocity target exceeds Team capacity. Using Team capacity."
        effective_capacity = Team capacity
    ELSE:
        effective_capacity = min(Team capacity, Velocity target)
ELSE IF only Team capacity configured:
    effective_capacity = Team capacity
ELSE IF only Velocity target configured:
    effective_capacity = Velocity target
ELSE:
    effective_capacity = null  (unconstrained — top-N by priority)
```

### Effort-to-unit mappings (fixed, used by sprint-planner)

Triage complexity takes precedence over priority-engine Effort score.

| Source | XS / 1 | S / 2 | M / 3 | L / 4 | 5 |
|--------|--------|-------|-------|-------|---|
| Triage complexity → SP | 1 | 2 | 3 | 5 | — |
| Triage complexity → Hours | 2 | 4 | 8 | 16 | — |
| Priority-engine Effort → SP | 1 | 2 | 3 | 5 | 8 |
| Priority-engine Effort → Hours | 0.5 | 1 | 2 | 4 | 8 |
| Default (no data) | 3 SP or 2h | — | — | — | — |
