---
name: publish
description: Creates a PR and updates issue tracker states (auto-detects mode from branch name)
allowed-tools: mcp__*, Bash, Read, Grep, Task
disable-model-invocation: true
---

# Publish

Publish current work: PR + (conditional) issue tracker state change. Read Automation Config from CLAUDE.md.

`/publish` auto-detects the publishing **mode** from the current branch name and the Automation Config `Source Control → Branch naming` template. There are three success modes (`full-publish`, `pr-only-no-id`, `pr-only-404`) and one failure mode (`FAIL`). No flags. No new config keys. The "PR-only with valid tracker reference" use case is expressed by renaming the branch to one that does not match the configured `Branch naming` prefix (e.g., `chore/refactor-foo` instead of `fix/PROJ-123-foo`).

> **Operator note (interactive-only):** `/publish is interactive-only` — it requires user confirmation flows in agent prose and may FAIL in environments without an MCP server configured (CI / cron). For headless / batch publishing, use `/agent-flow:autopilot`.

## Steps

### Step 0 — Branch parse (NEW pre-pre-flight)

This step runs BEFORE the MCP pre-flight. It determines whether the tracker is needed at all.

**0a. Resolve the current branch name.**

```bash
branch_name=$(git branch --show-current)
```

If `branch_name` is empty, the working tree is in a **detached HEAD** state. There is no active branch to push or to use as the PR source, so `/publish` cannot proceed. FAIL with a single-line INFO message and EXIT non-zero:

```
[agent-flow][INFO] Cannot determine branch (detached HEAD). /publish requires an active branch.
```

This is a pre-flight environment check — NOT a tracker-down failure — so it does NOT use the `[agent-flow] 🔴 Pipeline Block` template. No tracker comment is posted. No webhook event is fired. (Detached HEAD is treated as FAIL — exit non-zero — NOT as `pr-only-no-id`, because there is no branch to push or use as PR source.)

**0b. Read `Source Control → Branch naming` from Automation Config.**

The template uses `{issue-id}` (and optionally `{description}`) as placeholders — for example `fix/{issue-id}-{description}` or `feature/{issue-id}` (per `docs/reference/automation-config.md` Branch naming row).

If the `Branch naming` key is **ABSENT** from Automation Config:

- `issue_id = null`
- `tracker_needed = false`
- Emit a single logical line (single `echo` invocation):

  ```
  [agent-flow][INFO] No Branch naming pattern configured; PR-only mode.
  ```

- Jump directly to **Step 3** (skip Steps 0c, 0d, 1, 2). The pipeline continues with `mode = "pr-only-no-id"`.

**0c. Identify the literal prefix preceding `{issue-id}`.**

`pre_prefix` is the literal text that appears in the configured `Branch naming` template BEFORE the `{issue-id}` placeholder.

The post-`{issue-id}` delimiter character is intentionally **NOT parsed** and is **NOT used as a split boundary**. The "split at first delimiter" approach was abandoned in design revision 2 because the standard YouTrack/Jira/Linear ID format `PROJ-123` itself contains `-`, which would make "split at first `-`" yield `PROJ` instead of `PROJ-123`. Instead, the canonical extraction regex (Step 0d) understands the structure of valid issue IDs and consumes only the issue-ID portion of the residue, ignoring any trailing description segment.

Bash idiom for prefix identification:

```bash
prefix=$(echo "$branch_naming_pattern" | sed 's/{issue-id}.*//')
```

Examples:

- template `fix/{issue-id}-{description}` → `pre_prefix="fix/"`
- template `feature/{issue-id}` → `pre_prefix="feature/"`
- template `{issue-id}` → `pre_prefix=""`

**0d. Apply the canonical issue-ID extraction regex.**

If `branch_name` does **NOT** start with `pre_prefix`:

- `issue_id = null`

Otherwise, strip `pre_prefix` from the front of `branch_name` to form `residue`, then apply the canonical extraction regex against `residue`:

```
^(#?[0-9]+|[A-Za-z][A-Za-z0-9_]*-[0-9]+)
```

This regex anchors at the start of `residue` and matches **EITHER**:

- `#?[0-9]+` — numeric, optionally `#`-prefixed (github / gitea / redmine shapes: `123`, `#42`)
- `[A-Za-z][A-Za-z0-9_]*-[0-9]+` — alphanumeric project prefix + `-` + digits (youtrack / jira / linear shapes: `PROJ-123`, `ABC-456`, `ABC_DEF-789`)

Bash idiom:

```bash
if [[ "$residue" =~ ^(#?[0-9]+|[A-Za-z][A-Za-z0-9_]*-[0-9]+) ]]; then
  issue_id="${BASH_REMATCH[1]}"
else
  issue_id=""
fi
```

The first match is the `issue_id`. Any trailing characters in `residue` (e.g. `-fix-crash` after `PROJ-123`) are description text and are discarded. If the regex does not match (e.g. residue starts with non-issue-ID-shaped text), set `issue_id = null`.

**Path-traversal defense (defensive).** The canonical regex never matches a dot-only residue by construction, but as a defense-in-depth check, after extraction, if `issue_id` matches `^\.+$` (one-or-more dots only), set `issue_id = null`.

**Coverage by tracker (all 6 supported types):**

| Tracker | Issue ID shape | Example | Regex branch matched |
|---------|----------------|---------|----------------------|
| youtrack | uppercase prefix + `-` + digits | `PROJ-123` | `[A-Za-z][A-Za-z0-9_]*-[0-9]+` |
| jira | uppercase prefix + `-` + digits | `ABC-456` | `[A-Za-z][A-Za-z0-9_]*-[0-9]+` |
| linear | uppercase prefix + `-` + digits | `ENG-789` | `[A-Za-z][A-Za-z0-9_]*-[0-9]+` |
| github | numeric (optionally `#`-prefixed) | `123` / `#42` | `#?[0-9]+` |
| gitea | numeric (optionally `#`-prefixed) | `123` / `#42` | `#?[0-9]+` |
| redmine | numeric (optionally `#`-prefixed) | `42` / `#42` | `#?[0-9]+` |

**Worked examples (all 6 — these are the canonical reference cases):**

1. `branch="fix/PROJ-123-fix-crash"`, template `"fix/{issue-id}-{description}"`
   - `pre_prefix="fix/"`
   - `residue="PROJ-123-fix-crash"`
   - regex matches `PROJ-123` → `issue_id="PROJ-123"`
   - trailing `-fix-crash` is description, discarded

2. `branch="feature/PROJ-456"`, template `"feature/{issue-id}"`
   - `pre_prefix="feature/"`
   - `residue="PROJ-456"`
   - regex matches `PROJ-456` → `issue_id="PROJ-456"`

3. `branch="chore/refactor-foo"`, template `"fix/{issue-id}-{description}"`
   - branch does **NOT** start with `"fix/"` → `issue_id=null`

4. `branch="fix/123-numeric-id"`, template `"fix/{issue-id}-{description}"` (github / gitea / redmine)
   - `pre_prefix="fix/"`
   - `residue="123-numeric-id"`
   - regex matches `123` (numeric branch) → `issue_id="123"`

5. `branch="fix/#42-fix"`, template `"fix/{issue-id}-{description}"` (github hash-prefixed)
   - `pre_prefix="fix/"`
   - `residue="#42-fix"`
   - regex matches `#42` → `issue_id="#42"`

6. `branch="feature/ABC_DEF-789"`, template `"feature/{issue-id}"` (youtrack with underscore in project key)
   - `pre_prefix="feature/"`
   - `residue="ABC_DEF-789"`
   - regex matches `ABC_DEF-789` → `issue_id="ABC_DEF-789"`

**0e. Set `tracker_needed` and branch on the outcome.**

```
tracker_needed = (issue_id != null)
```

If `tracker_needed == false`:

- `mode = "pr-only-no-id"`
- Emit a single logical line (single `echo` invocation, single `\n`):

  ```
  [agent-flow][INFO] Branch '{branch_name}' does not match the configured Branch naming pattern. Creating PR without tracker contact.
  ```

- Skip directly to **Step 3** (skip Steps 1, 2). A non-matching branch is probably intentional (the user named it `chore/refactor-foo`); the message is INFO-level so it does not look alarming.

Otherwise (`tracker_needed == true`), proceed to **Step 1**.

### Step 1 — MCP pre-flight (RENAMED from former Step 0; GATED on `tracker_needed == true`)

This step ONLY runs when `tracker_needed == true`. PR-only modes never hit it.

- Read `Type` from Automation Config (`Issue Tracker` section).
- Verify that at least one `mcp__*` tool matching the tracker type is accessible.
- If not accessible → emit the FAIL block per the **FAIL tier** template below (with `error_type = "unknown"` if classification cannot be made more specific) and EXIT non-zero.

### Step 2 — Tracker lookup (GATED on `tracker_needed == true`)

This step ONLY runs when `tracker_needed == true`. It verifies that `issue_id` actually exists in the tracker and decides between `full-publish`, `pr-only-404`, and `FAIL`.

a. Read `tracker_type` from Automation Config (default: `youtrack`).

b. Locate the single-issue fetch tool via prefix-scan per `../../core/mcp-detection.md:28-34` and `../../core/mcp-detection.md:36` ("Scan available tools for at least one tool matching the prefix"). **Do NOT hardcode tool names** — pick the `get_issue`-shaped tool from `mcp__{tracker_type}__*`.

c. Call the discovered tool with `issue_id`.

d. Classify the outcome per the closed 5-bucket enum at `../../core/mcp-detection.md:58-87` — `{tls, auth, not_found, timeout, unknown}` — and branch on it:

| Outcome | `mode` | UX channel | Continue? |
|---|---|---|---|
| Issue returned with valid summary | `"full-publish"` | INFO log: `[agent-flow][INFO] Issue {issue_id} found in {tracker_type}. Publishing PR + tracker update.` | yes → Step 3 |
| `error_type == "not_found"` | `"pr-only-404"` | **404 WARN tier** (single line, NOT block channel) | yes → Step 3 |
| `error_type ∈ {"timeout", "auth", "tls", "unknown"}` | FAIL | **FAIL tier** block | no — EXIT non-zero |

**"Prefix has tools but no `get_issue`-shaped tool found"** (R3 mitigation) → classify as `error_type = "unknown"` → FAIL.

### Step 3 — Common pre-publish (mode-independent except FAIL)

a. Verify the current branch has commits above the base branch:

```bash
git log {base_branch}..HEAD --oneline
```

If zero commits → STOP with INFO: `No changes to publish — branch has no commits above {base_branch}.`

b. Check whether an open PR already exists for the current branch. If yes → STOP with INFO: `PR already exists: {PR URL}.`

### Step 4 — Read Type from Automation Config (UNCHANGED)

Read `Type` from Automation Config → `Issue Tracker` (default: `youtrack`).

### Step 5 — Dispatch publisher agent (haiku, Task)

Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for publisher overrides.
You MUST invoke `Task(subagent_type='agent-flow:publisher', model='haiku')`. DO NOT inline-execute. The agent will commit, push, and create the PR.

Context:

```
Type = {Type from config}. Use MCP server for {Type}.
mode = {mode}.
issue_id = {issue_id or 'none'}.
```

### Step 6 — Tracker state + comment (CONDITIONAL on mode)

- IF `mode == "full-publish"`:
  - Issue tracker: set state per Automation Config (`Issue Tracker → State transitions → For Review`).
  - Post a comment in the issue tracker with the PR link.
- ELSE (mode in `{"pr-only-no-id", "pr-only-404"}`):
  - Skip both. Log: `[agent-flow][INFO] PR-only mode ({mode}); tracker not updated.`

### Step 7 — Webhook (UNCHANGED shape; `issue_id` empty in PR-only modes)

If `Notifications → Webhook URL` exists and `pr-created` is in `On events`:

```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  -d '{"event":"pr-created","issue_id":"{issue}","pr_url":"{url}","timestamp":"{ISO8601}"}' \
  "{Webhook URL}"
```

The `pr-created` event fires in **all non-FAIL modes**. The `issue_id` field is the empty string when `mode in {"pr-only-no-id", "pr-only-404"}` — this is the forward-compatible payload contract; consumers MUST parse leniently. Failure → warning only, must not stop publish.

### Step 8 — Publish Report (publisher agent owns the `Tracker:` row)

The `publisher` agent emits the Publish Report. The agent's report MUST include a `Tracker:` row in **exactly one** of these three forms (defined and enforced in `agents/publisher.md` §82-87 — this skill prose references the contract but does not generate the report):

- `Tracker: Updated → For Review` — emitted when `mode == "full-publish"`
- `Tracker: Skipped — issue ID '{issue_id}' not found in {tracker_type}` — emitted when `mode == "pr-only-404"`
- `Tracker: Skipped — no issue ID in branch name` — emitted when `mode == "pr-only-no-id"`

### Step 9 — Display result (UNCHANGED)

Display the result (PR URL + issue tracker state, per the publisher agent's Publish Report).

---

## Failure UX templates

### FAIL tier (`error_type ∈ {timeout, auth, tls, unknown}`)

This template matches the `CLAUDE.md` "Block Comment Template" format. The `Skill:` field (not `Agent:`) is used for skill-level blocks. The format is machine-parseable by webhook consumers.

```
[agent-flow] 🔴 Pipeline Block
Skill: /agent-flow:publish
Step: Tracker auto-detect (Step 2)
Reason: Cannot connect to your {tracker_type} issue tracker — cannot verify whether '{issue_id}' exists.
Detail: {error_type} error from {tracker_type} MCP: {error_message}
Recommendation:
  1. Run `/agent-flow:check-setup` to diagnose tracker connectivity.
  2. If you intentionally want a PR with no tracker update, rename your
     branch to one that does NOT start with the configured Branch naming
     prefix (e.g., from "fix/PROJ-123-foo" to "chore/PROJ-123-foo"),
     then re-run /publish. Auto-detect will fall through to PR-only mode.
  3. If the tracker is intentionally offline, create the PR manually:
     git push -u origin {branch} && gh pr create
     (or your tracker UI's equivalent)
  4. Once the tracker is reachable, re-run `/agent-flow:publish`.
```

After emitting this block, EXIT non-zero. (`/agent-flow:check-setup` is the diagnostic skill; `/agent-flow:setup-mcp` is the configuration wizard.)

### 404 WARN tier (`error_type == "not_found"`)

Emit as a **single `echo` invocation** (one logical line, single trailing `\n`). Stdout, NOT the block channel. Pipeline continues with `mode = "pr-only-404"`:

```
[agent-flow][WARN] Branch '{branch}' contains issue ID pattern '{issue_id}' but no matching ticket was found in {tracker_type}. Creating PR without tracker update.
```

The displayed wrapping above is a Markdown rendering artifact only — the implementation MUST emit this as ONE logical line (one `echo` call, no mid-line newlines).

### No-issue-id INFO tier (already emitted in Step 0e)

Single logical line, single `echo` call. INFO level. A non-matching branch is probably intentional (user named it `chore/refactor-foo`); the message must not look alarming. Pipeline continues with `mode = "pr-only-no-id"`:

```
[agent-flow][INFO] Branch '{branch}' does not match the configured Branch naming pattern. Creating PR without tracker contact.
```

### Missing Branch naming INFO tier (already emitted in Step 0b)

Single logical line. Pipeline continues with `mode = "pr-only-no-id"`. Skips MCP pre-flight entirely:

```
[agent-flow][INFO] No Branch naming pattern configured; PR-only mode.
```

### Detached HEAD FAIL tier (already emitted in Step 0a)

Single logical line. Exits non-zero. NOT a Block Comment Template message — this is a pre-flight environment check, not a tracker-down failure. No tracker comment, no webhook event:

```
[agent-flow][INFO] Cannot determine branch (detached HEAD). /publish requires an active branch.
```

---

## Citations

- `../../core/mcp-detection.md:28-34` — tracker prefix table (no hardcoded tool names)
- `../../core/mcp-detection.md:36` — "Scan available tools for at least one tool matching the prefix"
- `../../core/mcp-detection.md:58-87` — error classification (5-bucket enum + Classification Reference table)
- `skills/fix-bugs/SKILL.md` — issue-id regex `^[A-Za-z0-9#._-]+$` + dot-only rejection (the canonical extraction regex used here is a stricter superset)
- `docs/reference/automation-config.md` — Branch naming template (`fix/{issue-id}-{description}`)
- `agents/publisher.md` §82-87 — Publish Report format (the `Tracker:` row contract)

## Headless / batch publishing

`/publish` is interactive-only. For headless / batch publishing (cron, CI, Task Scheduler), use `/agent-flow:autopilot` instead — it dispatches `/fix-bugs` or `/implement-feature` for each tracker-discovered issue, and those pipelines invoke `publisher` non-interactively from a known-tracker-backed context.
