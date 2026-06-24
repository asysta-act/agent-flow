---
name: create-backlog
description: Creates backlog epics in issue tracker from a specification document
allowed-tools: mcp__*, Bash, Read, Write, Edit, Glob, Grep, Task
argument-hint: "<spec-path> [--decompose] [--update] [--dry-run] [--yolo]"
disable-model-invocation: true
---

# Create Backlog

Input: `$ARGUMENTS` = spec path (positional) + optional flags (`--decompose`, `--update`, `--dry-run`, `--yolo`)

If `$ARGUMENTS` contains `--yolo`, activate YOLO mode: auto-approve human gates. Note: Gate 3 confirmation can still be overridden by --dry-run.

## Configuration

Read Automation Config from CLAUDE.md section `## Automation Config`. Follow `../../core/config-reader.md`.

**Required:**
- Issue Tracker: Type, Instance, Project

**Optional:**
- Sprint Planning: Epic template (path to custom template file — overrides default Epic Card Template)
- Agent Overrides: Path (default: `customization/`)
- Decomposition: Max subtasks (default: 7) — used only with `--decompose`

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
- **Multiple files (space-separated or glob pattern):** Read each matched file in order.

If the path does not exist or is empty: STOP with "Specification path not found or empty: {spec-path}"

Update `state.json`: write `backlog.spec_path`. Follow atomic write protocol from `../../core/state-manager.md`.

### Step 2: Extract epics (backlog-creator agent)

You MUST invoke `Task(subagent_type='agent-flow:backlog-creator', model='sonnet')`. DO NOT inline-execute.

Context to pass:
- Specification content (all files read in Step 1, concatenated with file boundary markers)
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
SET created_issues = []  // list of {epic_index, tracker_issue_id, title}
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
5. For matched epics: update issue description via MCP (preserve title, update body with rendered Epic Card).
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
        // Gitea: use Bash curl REST API (MCP Gitea does not guarantee epic label support)
        owner = {owner from issue_tracker.project}
        repo  = {repo from issue_tracker.project}
        result = Bash(
            curl -s -X POST "{issue_tracker.instance}/api/v1/repos/{owner}/{repo}/issues"
              -H "Authorization: token $GITEA_TOKEN"
              -H "Content-Type: application/json"
              -d '{"title":"{epic.title}","body":"{epic_card_content_escaped}","labels":[]}'
        )
        // If GITEA_TOKEN is not set, fall back to:
        // result = mcp__gitea__create_issue
        //   with parameters: owner, repo, title, body
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
    ADD {epic_index: {N}, tracker_issue_id: new_id, title: epic.title} to created_issues
    success_count += 1

    // Update state.json per epic (atomic, immediate)
    UPDATE state.json: increment backlog.epics_created, append to backlog.created_issues
    Follow atomic write protocol from ../../core/state-manager.md

CATCH error:
    LOG WARN "Could not create tracker issue for epic '{epic.title}': {error}"
    failure_count += 1
    CONTINUE  // NON-BLOCKING — proceed to next epic
```

**Per-Tracker Epic Creation Parameters:**

| Tracker | MCP Tool Prefix | Title Param | Description Param | Type / Label | Notes |
|---------|----------------|-------------|-------------------|--------------|-------|
| YouTrack | `mcp__youtrack__*` | `summary` | `description` | `type: "Feature"` | Top-level issue, no parent |
| Jira | `mcp__jira__*` or `mcp__atlassian__*` | `summary` | `description` | `issuetype: "Epic"` | Fallback to "Story" if Epic type unavailable |
| Linear | `mcp__linear__*` | `title` | `description` | `labelNames: ["feature"]` | No native Epic type; use label |
| GitHub | `mcp__github__*` | `title` | `body` | `labels: ["epic"]` | Uses REST via MCP |
| Gitea | Bash curl REST or `mcp__gitea__*` | `title` | `body` | `labels: ["epic"]` | Bash preferred; MCP fallback |
| Redmine | `mcp__redmine__*` | `subject` | `description` | `tracker_id: "Feature"` | Fallback to project default tracker |

### Step 5: Display result

```
Created {success_count}/{success_count + failure_count} epic issues.
```

If `--decompose` and subtasks were created:
```
Created {subtasks_created} sub-tasks across {epic_count} epics.
```

If `failure_count > 0`:
```
({failure_count} failures. Check warnings above.)
```

Update `state.json`: set top-level `status` to `"completed"`. Follow atomic write protocol from `../../core/state-manager.md`.

### Step 6 (--decompose): Subtask decomposition

**Only executed if `--decompose` flag is present.**

Run AFTER Step 4 for each successfully created epic issue (i.e., every issue in `created_issues`).

For each epic in `created_issues`:

1. You MUST invoke `Task(subagent_type='agent-flow:architect', model='opus')`. DO NOT inline-execute.
   - Context: `Epic: {epic.title}\nSpec content:\n{epic_card_content}\nParent tracker issue: {tracker_issue_id}`
   - Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for architect overrides
   - Expected output: architectural task tree with subtasks (each subtask includes title, scope, files, estimated_lines, maps_to)

2. If architect blocks: LOG WARN "Architect blocked for epic '{epic.title}': {reason}". Continue to next epic — NON-BLOCKING.

3. From architect output, extract subtask list. For each subtask:

   Build subtask description:
   ```
   {subtask.scope}

   Addresses: {subtask.maps_to[0]}, {subtask.maps_to[1]}, ...

   Files: {subtask.files[0]}, {subtask.files[1]}, ...

   Parent issue: {tracker_issue_id}
   ```
   (Omit "Addresses:" line if `maps_to` is empty. Omit "Files:" line if `files` is empty. "Parent issue:" always present.)

4. Create sub-issues using the same per-tracker dispatch table from implement-feature Step 5a (with parent parameter pointing to the epic's `tracker_issue_id`). Follow the same accumulator pattern (NON-BLOCKING on individual subtask failures).

5. Update `state.json`: increment `backlog.subtasks_created` by the count of successfully created sub-issues. Follow atomic write protocol from `../../core/state-manager.md`.

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
- NON-BLOCKING subtask creation (`--decompose`): same rule applies to each sub-issue
- Epic issues MUST NOT have the `On start set` state transition applied (they represent planned work, not active execution)
- Language fidelity: preserve all diacritics and non-ASCII characters from spec content without escaping
- Agent Overrides: follow `../../core/agent-override-injector.md` for backlog-creator and architect invocations
- If `sprint_planning.epic_template` is set but the file is missing: WARN and use the built-in Epic Card Template — do not block
- Max 10 epics per invocation (enforced by backlog-creator agent; display note if spec contains more)
- `--dry-run` skips MCP pre-flight, skips all tracker writes, and always stops after the preview gate
- All tracker writes use the SAME MCP tool conventions as implement-feature Step 5a — no divergence from established patterns
- Block Comment Template for fatal errors:
  ```
  [agent-flow] 🔴 Pipeline Block
  Agent: create-backlog
  Step: {step where failure occurred}
  Reason: {max 2 sentences}
  Detail: {technical output}
  Recommendation: {what the human should do}
  ```
