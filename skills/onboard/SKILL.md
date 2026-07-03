---
name: onboard
description: Interactive wizard for generating Automation Config
allowed-tools: Read, Glob, Write, Edit
argument-hint: "[--fresh] [--update]"
---

# Onboard

Interactive wizard that collects parameters and generates the `## Automation Config` block.

Input: `$ARGUMENTS` = (none) | `--fresh` | `--update`

- No arguments (default): auto-detect existing config and route accordingly
- `--fresh`: force fresh mode, skip config detection
- `--update`: force update mode, error if no config exists

## Scope

Target directory = git repository root (detect via `git rev-parse --show-toplevel`).
If not in a git repo → use CWD.

- Target file: `{target_dir}/CLAUDE.md`
- NEVER read or write CLAUDE.md outside of the target directory
- NEVER traverse parent directories to find CLAUDE.md
- Before any write operation, display: `Target: {absolute_path}/CLAUDE.md — Is this correct? [Y/n/custom path]`
- If CWD is NOT git root AND a CLAUDE.md exists in a parent directory:
  "You're in a subdirectory. CLAUDE.md exists at {parent}/CLAUDE.md.
   Write here ({CWD}) or there ({parent})? [here/THERE]"

## Step 0: Detection and Routing

1. Determine the target directory per ## Scope rules above
2. Read `{target_dir}/CLAUDE.md`
2. Look for `## Automation Config` section
3. If `--fresh` in $ARGUMENTS → skip detection, go to Fresh mode (step 1)
4. If `--update` in $ARGUMENTS and no config exists → error: "No Automation Config found. Run without --update to create one."
5. Route based on detection:

| State | Action |
|-------|--------|
| No config exists | Fresh mode (step 1) |
| Config exists, current version (has Pipeline Profiles or Metrics) | Offer: "[1] Update existing config [2] Start fresh (overwrites)" |
| Config exists, old version (no Pipeline Profiles and no Metrics) | "Detected older config format. Update it manually to match the current format in `docs/reference/automation-config.md`. Continue anyway? [y/N]" |

In update mode: parse entire existing config into key→value structure per section. This provides default values throughout the wizard.

Then proceed to:
- Fresh mode → step 1
- Update mode → step U0

## Fresh Mode

### Step 1: Template Offer

- Ask: "Would you like to start from a template? I have pre-built configurations for popular stacks."
- If user says no → continue with classic wizard (step 2)
- If user says yes:
  1. Glob `examples/configs/*.md`
  2. For each file, extract the template name from the H1 heading (`# Stack Name`)
  3. Display the Available Templates table:

     | Template | Stack | Tracker |
     |----------|-------|---------|
     | (one row per file — Tracker derived from filename prefix `gitea-`, `github-`, `jira-`, `redmine-`, `youtrack-`)|

  4. Prompt user to enter a template name OR press Enter to skip
  5. If user selects a template → Read `examples/configs/{stack-name}.md` and load it as pre-filled defaults
  6. Continue with steps 2-5 for adjustments

**Empty-glob fallback:** If `examples/configs/*.md` returns zero results, skip directly to step 2 with the message: "No pre-built templates available — proceeding with classic wizard."

**Heading-extraction contract:** Every config file in `examples/configs/*.md` MUST start with `# Stack Name` as the first line (single H1). See `examples/configs/README.md` for the contract.

Greet the user: "I'll set up Automation Config for your project. I'll ask about all the parameters step by step."

### Step 2: Issue Tracker

Ask step by step:

1. Which issue tracker do you use? (youtrack / github / jira / linear / gitea / redmine)

> **Path note:** `trackers.md` lives in the plugin installation directory, not in the consuming
> project. Glob is used to handle CWD-context mismatch.

Resolve `{trackers_md_path}` once:
1. Glob `.claude/plugins/**/docs/reference/trackers.md` — if results, use first (prefer path containing `.claude/plugins/` or `agent-flow/`; if ambiguous → [WARN] "Multiple trackers.md found — using {path}.")
2. Glob `**/docs/reference/trackers.md` — use first result if step 1 found nothing
3. Use `docs/reference/trackers.md` as last resort
If not found → [WARN] "trackers.md not found — using built-in defaults for this tracker type." and use default values from knowledge.

2. Instance URL — read defaults from `{trackers_md_path}` Instance & Project Defaults table
3. Project name / key — read format from the same table
4. Bug query — read defaults from `{trackers_md_path}` Query Syntax table, substitute the project name
5. **Feature query** — "Do you also want to configure a feature query for `/implement-feature`?"
   If yes, read defaults from `{trackers_md_path}` Query Syntax table (Feature query format column).
   If user provides a Feature query → auto-include `### Feature Workflow` section in output. The Feature query key is always emitted in the `### Feature Workflow` section (where `/implement-feature` reads it from).
   If user declines → no Feature query in output.
6. State transitions — read defaults from `{trackers_md_path}` State Transition Syntax table. Compose the full value using comma separator: `In Progress: {format}, Blocked: {format}, For Review: {format}, Done: {format}`
   6a. **Redmine status ID resolution** (only when tracker type is `redmine`):
   - Display guidance: "Redmine requires numeric status IDs. Common defaults: 1=New, 2=In Progress, 3=Resolved, 4=Feedback, 5=Closed, 6=Rejected."
   - Display lookup instruction: "To find your instance's status IDs, run: `curl -s -H 'X-Redmine-API-Key: YOUR_KEY' https://YOUR_INSTANCE/issue_statuses.json | python3 -m json.tool`"
   - Accept 4 numeric IDs interactively (with defaults):
     - In Progress (default: 2)
     - Blocked (default: 4)
     - For Review (default: 4)
     - Done/Closed (default: 5)
   - Use entered IDs to compose State transitions in `status_id:{id}` format
   - If user presses Enter for all, use defaults from trackers.md
   - For non-Redmine trackers: skip this sub-step entirely
7. On start set — read defaults from `{trackers_md_path}` On Start Set Defaults table

### Step 3: Source Control

Ask:
- Remote hostname + owner/repo (e.g. `<your-gitea-host>/org/repo`)
- Base branch (default: `main`)
- Branch naming (default: `fix/{issue}-{short-description}`)

### Step 4: PR Rules + PR Description Template

**4a.** PR Rules:
- Labels for PR (default: `ForReview`)
- Title format (optional — press Enter to use the `{issue-id} {Mode}: {summary}` fallback). Example: `{issue-id}-{mode}-{summary}`. See `docs/reference/automation-config.md` → PR Rules → Title format for the placeholders and the English/ASCII normalization rules.

**4b.** PR Description Template:
1. Auto-generate a tracker-appropriate template with this structure:

   ```
   ## Summary
   {summary}

   ## Root Cause
   {root_cause}

   ## Changes
   {changes}

   ## Testing
   {testing}

   {tracker-specific footer}
   ```

   Tracker-specific footers — read from `{trackers_md_path}` PR Description Footer table.

2. Display the full template as preview
3. "Looks good? Or do you want to customize? (add/remove/rename sections)"
4. If customize → apply changes interactively

### Step 5: Build & Test

Ask:
- Build command (e.g. `npm run build`, `dotnet build`)
- Test command (e.g. `npm test`, `pytest`)
- Verify command (optional): "Do you have a post-merge verification command? (e.g., integration tests)"

Generated key names: `Build command`, `Test command`, `Verify command`.

### Step 6: Optional Sections

**6a.** Bundle selection:

```
Which optional sections do you want to configure?

  [1] standard (recommended) — Retry Limits, Error Handling, Pipeline Profiles, Feature Workflow
  [2] full — all 14 optional sections
  [3] minimal — Retry Limits only
  [4] custom — choose from the list
```

If user selected a Feature query in step 2, Feature Workflow is auto-included regardless of bundle choice.

**6b.** If custom → show multi-select checklist:

```
Select sections to configure (comma-separated numbers):

  [ 1] Retry Limits — max fixer/test/build retries
  [ 2] Error Handling — behavior on pipeline block
  [ 3] Pipeline Profiles — skip/add pipeline stages per task type
  [ 4] Feature Workflow — feature-specific On start set
  [ 5] Hooks — shell commands at pipeline integration points
  [ 6] Custom Agents — custom agent files at pipeline points
  [ 7] Notifications — webhook for pipeline events
  [ 8] Worktrees — parallel bug processing via git worktrees
  [ 9] E2E Test — end-to-end testing framework
  [10] Decomposition — task decomposition for complex features
  [11] Metrics — pipeline analytics configuration
  [12] Browser Verification — browser-based bug reproduction and fix verification
  [13] Module Docs — path to per-module documentation for agents
  [14] Local Deployment — start/stop local environment for testing
```

**6c.** Processing order: Pipeline Profiles first (affects entire pipeline), then remaining in list order.

**6d.** Pipeline Profiles — prominent handling:
- Offer pre-built profiles with explanation:
  - `fast`: skip triage, analyst-impact, test-engineer — "Quick fixes, skip analysis"
  - `strict`: extra test-engineer-e2e — "Full quality gate"
  - `minimal`: skip triage, analyst-impact, test-engineer, test-engineer-e2e — "Emergency hotfixes"
- User can add custom profiles
- Display profile table as preview before confirming

**6e.** Feature Workflow — when asking about "On start set":
- Show fallback: "Feature 'On start set' (default: same as Issue Tracker '{value}' — press Enter to keep)"
- This matches the fallback in `/implement-feature`

**6f.** For each remaining selected section, ask for its key values using defaults from `docs/reference/automation-config.md`:
- Retry Limits: Fixer iterations (default: 5), Test attempts (default: 3), Build retries (default: 3), Spec iterations (default: 5), Root cause iterations (default: 3)
- Error Handling: On block (default: `comment`), Max blocked per run (default: `unlimited`)
- Hooks: Pre-fix, Post-fix, Pre-publish, Post-publish (all default: none)
  - Note: these are the **pipeline integration-point** hooks. Separately, an
    optional **dispatch-enforcement** PostToolUse audit hook
    (`hooks/validate-dispatch.sh`) can be installed manually — it is opt-in and
    not configured by this wizard. See `docs/guides/dispatch-enforcement.md`.
- Custom Agents: Post-fix agent, Pre-publish agent (all default: none)
- Notifications: Webhook URL, On events (all default: none)
- Worktrees: Batch size (default: 3), Base path (default: `.worktrees/`), Cleanup (default: `auto`)
- E2E Test: Framework, Command (all default: none)
- Browser Verification: "Do you want to configure browser-based reproduction/verification? [y/N]" — if yes: Base URL (default: `http://localhost:3000`), Start command (default: none), Stop command (default: none), On events (default: `reproduce, verify` — must be `reproduce`, `verify`, or `reproduce, verify`), Timeout (default: `30`), Max pages (default: `5`)
- Decomposition: Max subtasks (default: 7), Fail strategy (default: `fail-fast`), Commit strategy (default: `squash`)
- Metrics: Output (default: `stdout`), Period (default: `30 days`)
- Module Docs: Path (default: none)
- Local Deployment: "Do you want to configure local deployment? [y/N]" — if yes: Type (default: `docker`), Start command (default: `docker compose up -d`), Stop command (default: `docker compose down`), Health check URL (default: `http://localhost:3000/health`), Health check timeout (default: `60`), Ports (default: none)

### Step 7: Generate Automation Config

Generate the Automation Config block from collected answers.

Language rules:
1. All keys in English — exactly per `docs/reference/automation-config.md`
2. All identifier values in English (State transitions, Branch naming, Labels, Profile names)
3. User-provided values preserved as-is (URLs, project names, commands)
4. Table format always (`| Key | Value |`) — never bullet-point lists
5. PR Description Template section headings always in English

### Step 8: Output Options

**Fresh mode:**
- Option 1 (default): Print the block to chat — the user copies it manually
- Option 2: Write directly into CLAUDE.md
  - If `## Automation Config` already exists → warn and offer overwrite or cancel
  - If it does not exist → create CLAUDE.md in the target directory, append config
  - Display absolute path before writing: "Will write to: {absolute_path}/CLAUDE.md"

**Update mode:**
- Display diff (before → after, only changed sections)
- Option 1 (default): Write changes to CLAUDE.md
- Option 2: Print to chat only

Safety: Never delete existing sections/keys that the wizard does not recognize. Preserve custom additions.

### Step 9: Closing Message

```
Automation Config generated successfully.

Next steps:
1. Run /agent-flow:check-setup to validate your configuration
2. Run /agent-flow:setup-mcp to configure MCP servers and permissions
3. Try /agent-flow:analyze-bug <issue-id> to test the bug pipeline
```

If Feature query was configured, add:
```
4. Try /agent-flow:implement-feature <issue-id> to test the feature pipeline
```

Always end with:
```
Note: agent-flow uses semantic versioning. See Versioning Policy in the plugin's CLAUDE.md.

Tip: You can use tab-completion (`/agent-flow<tab>`) to discover commands, or describe what you want in natural language — the skill router will find the right command.
```

## Update Mode

### Step U0: Overview Display

Show a summary of the existing config:

```
Detected existing Automation Config:

  Issue Tracker: {type} @ {instance} — {project}
  Source Control: {remote} — {base branch}
  PR Rules: Labels = {labels}; Title format = {title_format or '(fallback)'}
  Build & Test: {build command} / {test command}
  Optional: {list of present optional sections}
  Missing optional: {list of absent optional sections}

  [1] Update existing config (go through sections, change what you need)
  [2] Add missing optional sections
  [3] Start fresh (overwrites everything)
```

### Step U1: Section-by-section update

For each existing section:
1. Display current values as table
2. "Any changes? (press Enter to keep, or type new values)"
3. If no changes → skip to next section
4. If changes → record new values

Include all sections: Issue Tracker, Source Control, PR Rules, PR Description Template, Build & Test, and all present optional sections.

### Step U2: Add missing sections

After going through existing sections:
- Show only sections not yet in config as a multi-select list
- For each selected section → ask for values (same questions as fresh mode step 6)

### Step U3: Diff and confirm

- Show before/after diff for changed sections only
- "Apply changes to {absolute_path}/CLAUDE.md? [Y/n]"
- Write to the target directory CLAUDE.md after confirmation
- Then show the closing message (step 9)

## Rules

- All wizard text (questions, prompts, explanations) in English
- All generated output (Automation Config block) in English
- Do not validate answers — validation belongs in `/check-setup`
- Offer defaults, but the user can change them
- Skip optional sections if the user says no
- Output always in table format (`| Key | Value |`)
- Feature query is always emitted in `### Feature Workflow` section, never in Issue Tracker
- In update mode: never delete sections/keys the wizard does not recognize
- Cancellation is safe: no changes are written until step 8 (fresh) or U3 (update)
