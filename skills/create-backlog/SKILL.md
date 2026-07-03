---
name: create-backlog
description: Creates backlog epics in issue tracker from a specification document
allowed-tools: mcp__*, Bash, Read, Write, Edit, Glob, Grep, Task
argument-hint: "<spec-path> [--decompose] [--update] [--dry-run] [--yolo]"
disable-model-invocation: true
---

# Create Backlog

Input: `$ARGUMENTS` = spec path (positional) + optional flags (`--decompose`, `--update`, `--dry-run`, `--yolo`)

If `$ARGUMENTS` contains `--yolo`, activate YOLO mode: auto-approve human gates. Note: even when YOLO auto-approves the Step 3 preview confirmation (create mode) or the Step 4 Update Preview confirmation (`--update` mode), `--dry-run` still stops the pipeline before the confirmation gate is ever reached — no tracker write occurs.

## Configuration

Read Automation Config from CLAUDE.md section `## Automation Config`. Follow `../../core/config-reader.md`.

**Required:**
- Issue Tracker: Type, Instance, Project

**Optional:**
- Sprint Planning: Epic template (path to custom template file — overrides default Epic Card Template)
- Agent Overrides: Path (default: `customization/`)
- Decomposition: Max subtasks (default: 7), Create tracker subtasks (default: enabled) — both used only with `--decompose`

## Flag Parsing

Parse `$ARGUMENTS`:
- Remove `--decompose`, `--update`, `--dry-run`, `--yolo` from the arguments string
- Remainder = spec path (file or directory)
- If spec path is empty: STOP with "Usage: /agent-flow:create-backlog <spec-path> [--decompose] [--update] [--dry-run] [--yolo]"
- `--decompose` and `--update` are mutually exclusive. If both present: STOP with "Cannot use --decompose with --update."
- `--dry-run` can combine with any other flag.

## Orchestration

### 0. MCP pre-flight check

If `--dry-run`, skip MCP check (no tracker writes will occur).

Otherwise, follow `../../core/mcp-preflight.md`:
- Read Type from Automation Config (Issue Tracker section)
- Check that at least one `mcp__*` tool matching the tracker type is accessible
- If not accessible → BLOCK with:
  ```
  [agent-flow] 🔴 Pipeline Block
  Agent: create-backlog
  Step: MCP pre-flight check
  Reason: Cannot connect to your {Type} issue tracker.
  Detail: Expected tool prefix: mcp__{Type}__*. No matching tool is registered in this session.
  Recommendation: Run /agent-flow:check-setup for diagnostics, or /agent-flow:setup-mcp to configure the {Type} integration.
  ```

### 0b. State initialization

Create `.agent-flow/backlog-{YYYYMMDD-HHmmss}/` directory.
Initialize `state.json` with:
```json
{
  "schema_version": "1.0",
  "run_id": "backlog-{YYYYMMDD-HHmmss}",
  "parent_run_id": null,
  "mode": "backlog-creation",
  "pipeline": "create-backlog",
  "status": "running",
  "started_at": "{ISO-8601}",
  "updated_at": "{ISO-8601}",
  "config": {
    "profile": null,
    "flags": [],
    "retry_limits": {
      "fixer_iterations": 5,
      "test_attempts": 3,
      "build_retries": 3
    }
  },
  "backlog": {
    "spec_path": "{spec-path}",
    "epics_total": 0,
    "epics_created": 0,
    "epics_failed": 0,
    "subtasks_created": 0,
    "created_issues": []
  }
}
```
Follow atomic write protocol from `../../core/state-manager.md`.

### Step 1: Read specification

Read the spec path provided in `$ARGUMENTS`:
- **Directory:** Glob `{spec-path}/epics/*.md` (spec-based scaffold format). If no `epics/` subdir exists, glob `{spec-path}/*.md`.
- **Single file:** Read the single file.
- **Multiple files (space-separated or glob pattern, including the `epics/*.md` and bare `*.md` directory
  globs above whenever they match more than one file):** Read each matched file in order. For each file,
  prepend a `--- FILE: {path} ---` boundary marker line (where `{path}` is the file's path as matched)
  immediately before that file's content, then concatenate all files in match order. This produces the
  "concatenated with file boundary markers" content passed to backlog-creator in Step 2 below.

If the path does not exist or is empty: STOP with "Specification path not found or empty: {spec-path}"

Update `state.json`: write `backlog.spec_path`. Follow atomic write protocol from `../../core/state-manager.md`.

### Step 2: Extract epics (backlog-creator agent)

You MUST invoke `Task(subagent_type='agent-flow:backlog-creator', model='sonnet')`. DO NOT inline-execute.

Context to pass:
- Specification content (all files read in Step 1, concatenated with `--- FILE: {path} ---` boundary
  markers as constructed in Step 1 above — one marker per source file, immediately preceding that file's
  content)
- Epic template path: `{sprint_planning.epic_template}` if configured — otherwise omit (agent uses built-in template)
- `Max epics: 10`

Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for backlog-creator overrides.

If the backlog-creator agent Blocks: display the block message and STOP.

Store from backlog-creator output:
- `epic_list`: structured list of epics (title, scope, AC, size, dependencies, verification)
- `epics_total`: count of epics in the list

Update `state.json`: write `backlog.epics_total`. Follow atomic write protocol from `../../core/state-manager.md`.

### Step 3: Human gate (preview)

Display the Backlog Summary table from backlog-creator output:

```
## Backlog Summary

| # | Epic | AC | Size | SP | Dependencies |
|---|------|----|------|----|--------------|
| 1 | {title} | {count} | {XS/S/M/L} | {points} | {deps or "none"} |
```

If `--dry-run`:
- Display individual epic cards (full Epic Card Template for each epic)
- STOP with "Dry run complete. No tracker issues created."

Prompt: "Create {N} epics in {tracker_type} tracker? [Y/n]"
If `--yolo`: auto-approve (display "[auto-approved]").
If rejected (user enters n): STOP with "Cancelled. No issues created."

### Step 4: Create tracker issues

**Accumulator pattern — NON-BLOCKING:**
```
SET success_count = 0
SET failure_count = 0
SET updated_count = 0        // --update mode only: matched epics whose description was updated
SET update_failure_count = 0 // --update mode only
SET created_issues = []  // list of {tracker_id, title, size, sp, epic_card_content}
                          // (epic_card_content is in-memory only — see Step 4 "Write to state")
```

**Update mode (`--update` flag):**

Execute the update matching algorithm (see Update Matching section below):
1. Fetch all open Feature/Epic issues from the tracker project (limit: 100)
2. For each epic in `epic_list`, compute match against existing issues using:
   - **Prefix match:** do the first 40 normalized characters match? (boolean)
   - **Token overlap:** Jaccard similarity of word-token sets >= 0.7
3. Display Update Preview table:
   ```
   ## Update Preview

   | # | Epic | Match | Tracker Issue | Similarity |
   |---|------|-------|---------------|------------|
   | 1 | {title} | MATCHED | {ID} | {score} |
   | 2 | {title} | NEW | -- | -- |

   Update {M} existing issue(s) and create {N} new issue(s)? [Y/n]
   ```
4. If `--yolo`: auto-approve. Otherwise wait for confirmation.
5. For matched epics, render `epic_card_content` from the same Epic Card Template used in Create mode below
   (or `sprint_planning.epic_template` if configured), then update the existing issue's description via MCP
   (preserve title; replace body/description with the rendered Epic Card), using the update-equivalent of
   the per-tracker calls in the Per-Tracker Epic Creation Parameters table below (`mcp__youtrack__update_issue`,
   `mcp__jira__update_issue`, `mcp__linear__update_issue`, `mcp__github__update_issue`,
   `mcp__redmine__update_issue`; Gitea via `curl -X PATCH` when `$GITEA_TOKEN` is set, else
   `mcp__gitea__update_issue` — same conditional as the Gitea create-mode dispatch below), wrapped in the
   same NON-BLOCKING TRY/CATCH pattern as Create mode:
   ```
   TRY:
       {tracker-appropriate update call} with issue id = {match.tracker_id}, description/body = {epic_card_content}
       updated_count += 1
   CATCH error:
       LOG WARN "Could not update tracker issue for epic '{epic.title}' (matched to {match.tracker_id}): {error}"
       update_failure_count += 1
       CONTINUE  // NON-BLOCKING — proceed to next matched epic
   ```
6. For unmatched epics: proceed to per-tracker creation (same as create mode below).

**Create mode (default, and for unmatched epics in update mode):**

For each epic in `epic_list` (or unmatched epics in `--update` mode):

Build the Epic Card content from the Epic Card Template:
```markdown
## {Epic Title}

**Type:** feature
**Size:** {XS|S|M|L} ({N} SP)
**Dependencies:** {comma-separated epic titles, or "none"}

### Scope
{2-3 sentences describing what needs to be built}

### Acceptance Criteria
1. {Testable criterion}
2. {Testable criterion}
3. {Testable criterion}

### Verification
- Unit: {what to test with unit tests}
- Integration: {what to test with integration tests}
- E2E: {what to test end-to-end}
```

If `sprint_planning.epic_template` is configured and the file exists: use that template instead.

**Per-tracker epic creation dispatch:**

```
TRY:
    IF tracker_type == "youtrack":
        result = mcp__youtrack__create_issue(
            project: {issue_tracker.project},
            summary: {epic.title},
            description: {epic_card_content},
            type: "Feature"
        )
        SET new_id = result.id

    ELSE IF tracker_type == "jira":
        // Attempt Epic issue type; fall back to Story if Epic unavailable
        TRY:
            result = mcp__jira__create_issue(
                project: {issue_tracker.project},
                summary: {epic.title},
                description: {epic_card_content},
                issuetype: "Epic"
            )
        CATCH issuetype_error:
            LOG WARN "Epic issue type unavailable in Jira project {issue_tracker.project}. Falling back to Story."
            result = mcp__jira__create_issue(
                project: {issue_tracker.project},
                summary: {epic.title},
                description: {epic_card_content},
                issuetype: "Story"
            )
        SET new_id = result.key

    ELSE IF tracker_type == "linear":
        result = mcp__linear__create_issue(
            teamId: {issue_tracker.project},
            title: {epic.title},
            description: {epic_card_content},
            labelNames: ["feature"]
        )
        SET new_id = result.id

    ELSE IF tracker_type == "github":
        result = mcp__github__create_issue(
            owner: {owner from issue_tracker.project},
            repo: {repo from issue_tracker.project},
            title: {epic.title},
            body: {epic_card_content},
            labels: ["epic"]
        )
        SET new_id = result.number

    ELSE IF tracker_type == "gitea":
        // Gitea: prefer Bash curl REST API (MCP Gitea does not guarantee epic label support);
        // fall back to MCP when no token is configured. Same env-var-gated pattern as
        // skills/sprint-plan/SKILL.md Tier 2 fallback ("If the required environment variable is
        // not set: skip to the next tier immediately").
        owner = {owner from issue_tracker.project}
        repo  = {repo from issue_tracker.project}
        IF $GITEA_TOKEN is set:
            result = Bash(
                curl -s -X POST "{issue_tracker.instance}/api/v1/repos/{owner}/{repo}/issues"
                  -H "Authorization: token $GITEA_TOKEN"
                  -H "Content-Type: application/json"
                  -d '{"title":"{epic.title}","body":"{epic_card_content_escaped}","labels":[]}'
            )
            SET new_id = result.number
        ELSE:
            result = mcp__gitea__create_issue(
                owner: owner,
                repo: repo,
                title: {epic.title},
                body: {epic_card_content}
            )
            SET new_id = result.number

    ELSE IF tracker_type == "redmine":
        result = mcp__redmine__create_issue(
            project_id: {issue_tracker.project},
            subject: {epic.title},
            description: {epic_card_content},
            tracker_id: "Feature"
            // If "Feature" tracker unavailable, omit tracker_id (use project default)
        )
        SET new_id = result.id

    // --- Write to state ---
    SET epic_sp = size_to_points({epic.size})  // XS=1, S=2, M=3, L=5 — same fixed mapping backlog-creator
                                                // uses internally (agents/backlog-creator.md Constraints)
    ADD {tracker_id: new_id, title: epic.title, size: epic.size, sp: epic_sp, epic_card_content: epic_card_content}
      to created_issues
    // epic_card_content is retained in-memory only (consumed by Step 5's --decompose handoff below) —
    // it is NOT part of the persisted backlog.created_issues shape written to state.json next.
    success_count += 1

    // Update state.json per epic (atomic, immediate)
    UPDATE state.json: increment backlog.epics_created;
      append {title: epic.title, tracker_id: new_id, size: epic.size, sp: epic_sp} to backlog.created_issues
      (field names match state/schema.md Backlog State Object exactly: title, tracker_id, size, sp)
    Follow atomic write protocol from ../../core/state-manager.md

CATCH error:
    LOG WARN "Could not create tracker issue for epic '{epic.title}': {error}"
    failure_count += 1

    // Update state.json per epic (atomic, immediate) — mirrors the success-path write above
    UPDATE state.json: increment backlog.epics_failed
    Follow atomic write protocol from ../../core/state-manager.md

    CONTINUE  // NON-BLOCKING — proceed to next epic
```

**Per-Tracker Epic Creation Parameters:**

| Tracker | MCP Tool Prefix | Title Param | Description Param | Type / Label | Notes |
|---------|----------------|-------------|-------------------|--------------|-------|
| YouTrack | `mcp__youtrack__*` | `summary` | `description` | `type: "Feature"` | Top-level issue, no parent |
| Jira | `mcp__jira__*` or `mcp__atlassian__*` | `summary` | `description` | `issuetype: "Epic"` | Fallback to "Story" if Epic type unavailable |
| Linear | `mcp__linear__*` | `title` | `description` | `labelNames: ["feature"]` | No native Epic type; use label |
| GitHub | `mcp__github__*` | `title` | `body` | `labels: ["epic"]` | Uses REST via MCP |
| Gitea | Bash curl REST or `mcp__gitea__*` | `title` | `body` | `labels: ["epic"]` | Bash curl when `$GITEA_TOKEN` is set; `mcp__gitea__*` fallback otherwise |
| Redmine | `mcp__redmine__*` | `subject` | `description` | `tracker_id: "Feature"` | Fallback to project default tracker |

### Step 5 (--decompose): Subtask decomposition

**Only executed if `--decompose` flag is present.** Runs immediately AFTER Step 4, BEFORE Step 6
(result display) — `backlog.subtasks_created` MUST be finalized before Step 6 reports it and before
top-level `status` is set to `"completed"`.

**Gate:** Read `Decomposition → Create tracker subtasks` from Automation Config (default: `enabled`). If
`disabled`: LOG "[SKIP] --decompose: Decomposition → Create tracker subtasks is disabled. No sub-issues
will be created for any epic." and skip this entire step (proceed to Step 6 with `subtasks_created = 0`) —
this mirrors the Triple Gate in `../../core/tracker-subtask-creator.md`, which also skips entirely
(no WARN) when the same config key is disabled.

Otherwise:
```
SET subtasks_created = 0  // running total across all epics — mirrors backlog.subtasks_created
SET epic_count = 0        // epics for which architect did not Block (i.e., were actually decomposed)
```

For each epic in `created_issues` (i.e., every epic successfully created in Step 4):

1. You MUST invoke `Task(subagent_type='agent-flow:architect', model='opus')`. DO NOT inline-execute.
   - Context: `Epic: {epic.title}\nSpec content:\n{epic.epic_card_content}\nParent tracker issue: {epic.tracker_id}`
   - Instructions: "Decompose this epic into subtasks for tracker issue creation. Max {max_subtasks}
     subtasks." (where `max_subtasks` = Automation Config → Decomposition → Max subtasks, default 7 —
     same dispatch pattern as `skills/fix-bugs/steps/02-impact.md`). Architect enforces this cap
     internally — revising the task tree or Blocking if it still exceeds the cap after revision (see
     `agents/architect.md` Constraints) — this skill does not re-implement truncation.
   - Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for architect overrides
   - Expected output: architectural task tree with subtasks (each subtask includes title, scope, files, estimated_lines, maps_to)

2. If architect blocks: LOG WARN "Architect blocked for epic '{epic.title}': {reason}". Continue to next epic — NON-BLOCKING.

3. From architect output, extract `subtask_list`. `epic_count += 1` (this epic reached decomposition, regardless of how many individual sub-issues succeed below).

4. Delegate sub-issue creation to `../../core/tracker-subtask-creator.md` (the same contract
   `skills/implement-feature/steps/03-decomposition.md` Step 03a follows) — do NOT re-describe a divergent
   inline per-tracker loop here. Supply its Input Contract as:
   - `issue_id` = `epic.tracker_id`
   - `tracker_type` / `tracker_project` = from Automation Config Issue Tracker section
   - `tracker_effective_status` = `"ready"` (already confirmed by the Step 0 MCP pre-flight check)
   - `decomposition_decision` = `"DECOMPOSE"` (this step only runs when `--decompose` was passed and the Gate above did not skip)
   - `create_tracker_subtasks_config` = the value read in the Gate above
   - `subtask_list` = output of step 3
   - `yaml_path` = `.claude/decomposition/{epic.tracker_id}.yaml` (created fresh here for idempotency on
     re-run; no other file in this pipeline reads or writes it)
   - `state_json_path` = N/A for this pipeline — the `backlog` state object (`state/schema.md` Backlog
     State Object) has no `decomposition.subtasks[]` structure, so the dual-store state.json fallback tier
     does not apply here; rely on the YAML-first idempotency tier only. On each successful creation,
     increment `backlog.subtasks_created` in this run's `state.json` instead (see step 5 below).
   This inherits `../../core/tracker-subtask-creator.md`'s per-tracker MCP dispatch table, the Jira
   nested-sub-task guard, the GitHub/Gitea decomposition checklist, and its idempotency check —
   NON-BLOCKING on individual subtask failures, same as Step 4. `subtasks_created += {success_count
   returned by ../../core/tracker-subtask-creator.md for this epic}`.

5. Update `state.json`: increment `backlog.subtasks_created` by the count of sub-issues successfully
   created for this epic in sub-step 4 above (atomic write per epic, immediately after sub-step 4 completes
   for that epic — the running `subtasks_created` and `epic_count` variables from sub-steps 3-4 are what
   Step 6 displays once this loop finishes). Follow atomic write protocol from `../../core/state-manager.md`.

### Step 6: Display result

Runs after Step 4 (create mode) and Step 5 (`--decompose`, if present) both complete — all counts below
are final by this point.

```
Created {success_count}/{success_count + failure_count} epic issues.
```

If `--update` mode and at least one epic was matched:
```
Updated {updated_count}/{updated_count + update_failure_count} epic issues.
```

If `--decompose` (Step 5 ran and was not skipped by its Gate):
```
Created {subtasks_created} sub-tasks across {epic_count} epics.
```

If `failure_count > 0`:
```
({failure_count} creation failures. Check warnings above.)
```

If `update_failure_count > 0`:
```
({update_failure_count} update failures. Check warnings above.)
```

Update `state.json`: set top-level `status` to `"completed"`. Follow atomic write protocol from `../../core/state-manager.md`.

**Update mode (--update) matching algorithm:**

```
Normalize title: lowercase, strip leading/trailing whitespace, collapse multiple spaces.

For each epic in epic_list:
  For each open tracker issue:
    prefix_match  = (normalized_epic_title[:40] == normalized_issue_title[:40])
    jaccard       = |token_intersection| / |token_union|   // tokens = split on whitespace+punctuation
    match         = prefix_match OR jaccard >= 0.7
  IF exactly one match: pair epic <-> issue
  IF multiple matches: select highest Jaccard. If tied, select most recently updated. WARN.
  IF no match: add to unmatched_epics list.
```

Edge cases:
- Empty tracker (0 open issues): all epics are unmatched, behave as create mode.
- Closed/resolved issues: not included in fetch (filtered by open state only).
- Title changed significantly: no match, new issue created.

## Rules

- NON-BLOCKING epic creation: a single epic failure NEVER stops the batch; accumulate counts and continue
- NON-BLOCKING epic update (`--update`, matched epics): same rule applies to each description update
- NON-BLOCKING subtask creation (`--decompose`): same rule applies to each sub-issue
- Epic issues MUST NOT have the `On start set` state transition applied (they represent planned work, not active execution)
- Language fidelity: preserve all diacritics and non-ASCII characters from spec content without escaping
- Agent Overrides: follow `../../core/agent-override-injector.md` for backlog-creator and architect invocations
- If `sprint_planning.epic_template` is set but the file is missing: WARN and use the built-in Epic Card Template — do not block
- Max 10 epics per invocation (enforced by backlog-creator agent; display note if spec contains more)
- `--dry-run` skips MCP pre-flight, skips all tracker writes, and always stops after the preview gate
- Epic tracker writes (Step 4) follow the Per-Tracker Epic Creation Parameters table above; subtask
  tracker writes (`--decompose`, Step 5) follow `../../core/tracker-subtask-creator.md` — neither step
  re-describes a divergent inline dispatch loop
- Block Comment Template for fatal errors:
  ```
  [agent-flow] 🔴 Pipeline Block
  Agent: create-backlog
  Step: {step where failure occurred}
  Reason: {max 2 sentences}
  Detail: {technical output}
  Recommendation: {what the human should do}
  ```
