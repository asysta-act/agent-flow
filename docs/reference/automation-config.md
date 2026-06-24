# Automation Config Reference

The Automation Config is the configuration block that connects agent-flow to your project. It lives in the `## Automation Config` section of your project's CLAUDE.md file.

The **canonical specification** for all sections, keys, and defaults is in [CLAUDE.md](../../CLAUDE.md) (Config Contract section). This document provides extended examples, per-tracker guidance, validation rules, and a complete configuration example.

## Overview

Automation Config uses a table format (`| Key | Value |`) for all sections. There are 5 required sections and 18 optional sections (referenced by 17 core contracts and consumed by 17 skills). Required sections must be present for the pipeline to run. Optional sections enable additional capabilities with sensible defaults.

All skills read Automation Config at the start of execution. Skills contain zero project-specific logic — everything is driven by what you configure here.

**Quick reference:**

| Section | Required | Used By |
|---------|----------|---------|
| Issue Tracker | Yes | All pipeline skills |
| Source Control | Yes | All pipeline skills |
| PR Rules | Yes | /publish, publisher |
| PR Description Template | Yes | /publish, publisher |
| Build & Test | Yes | /fix-bugs, /implement-feature, /scaffold |
| Module Docs | No | /fix-bugs, /implement-feature |
| Retry Limits | No | /fix-bugs, /implement-feature, /scaffold |
| Hooks | No | /fix-bugs, /implement-feature |
| Custom Agents | No | /fix-bugs, /implement-feature |
| Notifications | No | /fix-bugs, /implement-feature |
| Worktrees | No | /fix-bugs |
| E2E Test | No | /fix-bugs, /implement-feature, /scaffold |
| Browser Verification | No | /fix-bugs |
| Local Deployment | No | (deployment-verifier dispatched by pipelines) |
| Sprint Planning | No | /sprint-plan, /create-backlog |
| Error Handling | No | /fix-bugs, /implement-feature |
| Feature Workflow | No | /implement-feature |
| Decomposition | No | /fix-bugs, /implement-feature, /scaffold |
| Pipeline Profiles | No | /fix-bugs, /implement-feature |
| Metrics | No | /metrics |
| Agent Overrides | No | /fix-bugs, /implement-feature |
| Autopilot | No | /autopilot |
| Pause Limits | No | /fix-bugs, /implement-feature, /scaffold, /autopilot |

## Required Sections

### Issue Tracker

Configures which issue tracker to use and how to interact with it.

| Key | Description |
|-----|-------------|
| Type | Tracker type: `youtrack`, `github`, `jira`, `linear`, `gitea`, `redmine` (default: `youtrack`) |
| Instance | Tracker URL |
| Project | Project identifier |
| Bug query | Query to find open bugs |
| State transitions | Mapping of pipeline states to tracker states |
| On start set | State to set when pipeline begins processing. The pipeline also implicitly self-assigns the issue to the MCP-authenticated user after the state transition. Per-tracker assignee tool reference is in `skills/fix-bugs/SKILL.md` Step 1. Failure mode is advisory (WARN, never blocks pipeline) per `core/status-verification.md` pattern. |

**GitHub example:**

| Key | Value |
|-----|-------|
| Type | `github` |
| Instance | `https://github.com` |
| Project | `my-org/my-repo` |
| Bug query | `is:issue is:open label:bug` |
| State transitions | `In Progress → open, For Review → open, Blocked → open label:blocked, Done → closed` |
| On start set | `In Progress` |

**YouTrack example:**

| Key | Value |
|-----|-------|
| Type | `youtrack` |
| Instance | `https://youtrack.example.com` |
| Project | `PROJ` |
| Bug query | `project: PROJ type: Bug state: Open sort by: Priority` |
| State transitions | `In Progress, For Review, Blocked, Done` |
| On start set | `In Progress` |

**Gitea example:**

| Key | Value |
|-----|-------|
| Type | `gitea` |
| Instance | `https://gitea.example.com` |
| Project | `org/repo` |
| Bug query | `type:issues state:open label:bug` |
| State transitions | `In Progress → open, For Review → open, Blocked → open label:blocked, Done → closed` |
| On start set | `In Progress` |

**Redmine example:**

| Key | Value |
|-----|-------|
| Type | `redmine` |
| Instance | `https://redmine.example.com` |
| Project | `my-project` |
| Bug query | `project_id=my-project&status_id=open&tracker_id=1` |
| State transitions | `In Progress: status:In Progress, Blocked: status:Blocked, For Review: status:For Review, Done: status:Closed` |
| On start set | `status:In Progress` |

### Source Control

Configures git branch management and remote repository.

| Key | Value (example) |
|-----|-------|
| Remote | `my-org/my-repo` |
| Base branch | `main` |
| Branch naming | `fix/{issue-id}-{description}` |

The `{issue-id}` and `{description}` placeholders are replaced at runtime. Description is derived from the issue title (lowercased, spaces replaced with hyphens). The description MUST be **English, ASCII-only, no diacritics** — if the issue title is in another language, translate it to English first and transliterate any diacritics to ASCII (`é`→`e`, `č`→`c`, …).

### PR Rules

Configures labels applied to pull requests and the format of the PR title.

| Key | Value (example) |
|-----|-------|
| Labels | `bug, automated` |
| Title format | `{issue-id}-{mode}-{summary}` |

**Title format** controls how the publisher builds the PR title. Placeholders:

| Placeholder | Replaced with |
|-------------|---------------|
| `{issue-id}` | The issue tracker ID (e.g. `PROJ-123`) |
| `{mode}` | The pipeline mode keyword — a fixed value the publisher substitutes, not operator-defined: `Fix` (bug-fix), `Feat` (feature), `Scaffold` (scaffold) |
| `{summary}` | The issue summary |

Normalization rules applied to the rendered title:

- **No spaces** — every space is replaced with a hyphen (`-`).
- **No square brackets** around the issue ID, **no colons**.
- **English only, no diacritics** — the title MUST be in English using plain ASCII letters. If the issue summary is in another language (e.g. Czech), translate it to English first, then transliterate any remaining diacritics to ASCII (`é`→`e`, `č`→`c`, `ř`→`r`, `ů`→`u`, …). Diacritics must NEVER appear in the title.

Example: issue `PROJ-123` (feature) with the Czech summary "vylepšit zobrazení celé akce v Log Importu" → translate to English first ("improve the whole-action view in Log Import"), then render → `PROJ-123-Feat-improve-the-whole-action-view-in-Log-Import`.

If `Title format` is omitted, the publisher falls back to `{issue-id} {Mode}: {summary}` (issue ID, mode keyword, and summary) — the same English/ASCII-only summary rules apply, but the brackets-and-colon shape of this fallback is the one exception to the "no colons" normalization above.

### PR Description Template

A multi-line template used by the publisher agent when creating pull requests. This is a separate subsection within Automation Config.

Example:

```markdown
### PR Description Template

## Summary
{summary}

## Root Cause
{root_cause}

## Changes
{changes}

## Testing
{testing}

## Issue
{issue_link}
```

### Build & Test

Configures the commands used to build, test, and verify the project.

| Key | Value (example) |
|-----|-------|
| Build command | `npm run build` |
| Test command | `npm test` |
| Verify command | `npm run e2e:prod` |

The Verify command is optional. When present, it runs after PR merge. If verification fails, the issue is re-opened via State transitions.

## Optional Sections

### Module Docs

Points agents to per-module documentation files. When configured, analyst and architect read the corresponding module docs before analysis or design.

| Key | Default | Description |
|-----|---------|-------------|
| Path | (none) | Root directory containing module documentation files |

Agents identify the affected module from triage or specification and look for a matching documentation file under the configured path. If no matching file is found, agents proceed without module documentation.

Example:

| Key | Value |
|-----|-------|
| Path | `docs/modules` |

### Retry Limits

Controls how many times agents retry before blocking.

| Key | Default | Description |
|-----|---------|-------------|
| Fixer iterations | 5 | Max fixer/reviewer loop iterations |
| Test attempts | 3 | Max test-engineer retry attempts |
| Build retries | 3 | Max build command retries |
| Spec iterations | 5 | Max spec-writer / spec-reviewer loop iterations |
| Root cause iterations | 3 | Max root cause sanity check iterations (analyst --phase impact) |

### Hooks

Shell commands executed at pipeline integration points.

| Key | Default | Description |
|-----|---------|-------------|
| Pre-fix | (none) | Runs before fixer |
| Post-fix | (none) | Runs after successful build |
| Pre-publish | (none) | Runs after tests pass |
| Post-publish | (none) | Runs after PR creation (failure = warning only) |

Example:

| Key | Value |
|-----|-------|
| Pre-fix | `npm run lint:check` |
| Post-fix | `npm run format` |
| Pre-publish | `npm run audit` |

### Custom Agents

Paths to custom agent definition files that run at specific pipeline points.

| Key | Default | Description |
|-----|---------|-------------|
| Post-fix agent | (none) | Agent file path, runs after post-fix hook |
| Pre-publish agent | (none) | Agent file path, runs after pre-publish hook |

Example:

| Key | Value |
|-----|-------|
| Post-fix agent | `.claude/agents/security-scanner.md` |

See [Custom Agents Guide](../guides/custom-agents.md) for details on writing custom agents.

### Notifications

Webhook configuration for pipeline events.

| Key | Default | Description |
|-----|---------|-------------|
| Webhook URL | (none) | HTTP endpoint for event notifications |
| On events | (none) | Comma-separated list: `pr-created`, `issue-blocked`, `pipeline-started`, `step-completed`, `pipeline-completed`, `pipeline-paused`, `pipeline-resumed` |

### Worktrees

Enables parallel bug processing via git worktrees (used by `/agent-flow:fix-bugs`).

| Key | Default | Description |
|-----|---------|-------------|
| Batch size | 3 | Bugs processed in parallel |
| Base path | `.worktrees/` | Worktree directory |
| Cleanup | `auto` | `auto` removes worktrees after use; `manual` keeps them |

### E2E Test

Enables end-to-end testing via the test-engineer agent (`--e2e` flag).

| Key | Default | Description |
|-----|---------|-------------|
| Framework | (none) | E2E framework name (e.g., `playwright`, `cypress`) |
| Command | (none) | Command to run E2E tests |

### Browser Verification

Optional. Enables browser-based bug reproduction (before fixer) and verification (after tests). Requires Playwright installed in the consuming project (`npm install playwright`).

| Key | Description | Default |
|-----|-------------|---------|
| Base URL | The URL of the running application | (required) |
| Start command | Command to start the dev server, if not already running | (none) |
| Stop command | Command to stop the app the agent started. If unset, the agent falls back to `pkill -f` on the `Start command` pattern (POSIX only) | (none) |
| On events | Comma-separated: `reproduce`, `verify`, or `reproduce, verify` | reproduce, verify |
| Timeout | Seconds before browser operation is abandoned | 60 |
| Max pages | Max pages to check in scoped verification (Sub-phase A) | 5 |
| Screenshot storage | Path where screenshots are saved | .claude/screenshots |
| Exploration | Enable guided exploration in Sub-phase B: `enabled` or `disabled` | disabled |
| Exploration max clicks | Max clicks during guided exploration (Sub-phase B) | 20 |

**Example:**
```markdown
## Browser Verification

| Key | Value |
|-----|-------|
| Base URL | http://localhost:3000 |
| Start command | npm run dev |
| Stop command | npm run stop |
| On events | reproduce, verify |
| Timeout | 60 |
| Max pages | 5 |
| Screenshot storage | .claude/screenshots |
| Exploration | enabled |
| Exploration max clicks | 20 |
```

**Interaction with `E2E Test`:** `E2E Test` generates scripted test code artifacts (test files checked into the repo). `Browser Verification` interacts with the live browser at runtime (no test files generated). Both can be configured independently.

**Graceful degradation:** If Playwright is not installed, the app is not running and no `Start command` is set, or the section is absent — both phases are silently skipped. The pipeline never blocks due to browser infrastructure being unavailable.

**Stopping the app:** When the agent starts the app itself (via `Start command`), it stops it again when it finishes (after reproduction or verification). It runs `Stop command` if configured; otherwise it falls back to `pkill -f` on the `Start command` pattern. Set `Stop command` when running on a non-POSIX host (no `pkill`) or when the `Start command` is a launcher that exits before the app it spawned (so the pattern would no longer match the running process). If the app is already running when the agent checks `Base URL`, the agent neither starts nor stops it.

**Recommended `.gitignore` entries for consuming projects:**
```
.claude/reproduction-result.json
.claude/verification-result.json
.claude/reproduction-script.js
.claude/verifier-script.js
.claude/screenshots/
```

### Local Deployment

Optional. Configures local deployment health checks. The `deployment-verifier` agent is dispatched directly by pipeline skills (`/fix-bugs`, `/implement-feature`, `/scaffold`) when this section is present.

| Key | Description | Default |
|-----|-------------|---------|
| Type | Deployment type: `docker` or `native` | `native` |
| Start command | Command to start the application or services | (none) |
| Stop command | Command to stop the application or services | (none) |
| Health check URL | URL to poll until the app responds (HTTP 200) | (none) |
| Health check timeout | Seconds before health check is abandoned | 30 |
| Ports | Comma-separated ports to verify are open (e.g., `3000, 5432`) | (none) |

**Example:**
```markdown
## Local Deployment

| Key | Value |
|-----|-------|
| Type | docker |
| Start command | docker compose up -d |
| Stop command | docker compose down |
| Health check URL | http://localhost:3000/health |
| Health check timeout | 60 |
| Ports | 3000, 5432 |
```

### Error Handling

Controls behavior when an agent blocks an issue.

| Key | Default | Description |
|-----|---------|-------------|
| On block | `comment` | `comment` = post comment, `close` = post comment + close issue |
| Max blocked per run | `unlimited` | Stop batch processing after N blocks |

### Feature Workflow

Configuration for the feature pipeline (`/agent-flow:implement-feature`).

| Key | Default | Description |
|-----|---------|-------------|
| Feature query | (none) | Query to find feature issues in the tracker |
| On start set | (none) | State to set when feature processing begins |

### Decomposition

Controls task decomposition behavior for complex bugs and features.

| Key | Default | Description |
|-----|---------|-------------|
| Max subtasks | 7 | Maximum subtasks the architect can create |
| Fail strategy | `fail-fast` | `fail-fast` stops on first failure; `continue` attempts remaining |
| Commit strategy | `squash` | `squash` = one commit; `individual` = one commit per subtask |
| Create tracker subtasks | `enabled` | Create sub-issues in the tracker for each decomposition subtask. Values: `enabled`, `disabled`. When enabled, a new step creates tracker issues after decomposition plan approval. Requires `tracker_effective_status == "ready"`. |

### Pipeline Profiles

Named configurations that skip or add stages. See [Pipeline Profiles](#pipeline-profiles-1) section below.

| Key | Description |
|-----|-------------|
| Profile | Profile name |
| Skip stages | Comma-separated stages to skip |
| Extra stages | Comma-separated stages to add |

### Metrics

Controls metrics output for `/agent-flow:metrics`.

| Key | Default | Description |
|-----|---------|-------------|
| Output | `stdout` | Output destination |
| Period | `30 days` | Default analysis period |

### Sprint Planning

Configuration for the `/agent-flow:sprint-plan` and `/agent-flow:create-backlog` skills.

| Key | Default | Description |
|-----|---------|-------------|
| Sprint duration | `2 weeks` | Length of a sprint used when suggesting issue batches |
| Capacity unit | `story-points` | Unit used for team capacity calculations: `story-points` or `hours` |
| Team capacity | (none) | Total team capacity per sprint in the configured capacity unit |
| Velocity target | (none) | Historical velocity used to calibrate sprint suggestions |
| Sprint field | (tracker-dependent) | Custom field name in the tracker used to assign issues to sprints |
| Mode | `suggest` | `suggest` = propose plan for approval; `apply` = assign issues immediately |
| Max issues | `20` | Maximum number of issues to include in a single sprint plan |
| Epic template | (none) | Template issue ID or name used as a model when creating new epics |

**Example:**
```markdown
### Sprint Planning

| Key | Value |
|-----|-------|
| Sprint duration | 2 weeks |
| Capacity unit | story-points |
| Team capacity | 40 |
| Velocity target | 35 |
| Mode | suggest |
| Max issues | 15 |
```

### Agent Overrides

Optional directory with per-agent customization files. For each agent, create a file `{path}/{agent-name}.toml` with additional instructions. Contents are merged into the agent's prompt as `## Project-Specific Instructions`. Files that do not match any agent name are ignored.

| Key | Default | Description |
|-----|---------|-------------|
| Path | `customization/` | Directory containing per-agent override markdown files |

**Example:**
```markdown
### Agent Overrides

| Key | Value |
|-----|-------|
| Path | customization/ |
```

Create `customization/reviewer.toml` to add project-specific reviewer instructions, `customization/fixer.toml` for fixer instructions, and so on. See [Custom Agents Guide](../guides/custom-agents.md) for details.

**TOML overlay format (preferred):** The preferred override format is a TOML file at `{path}/{agent-name}.toml` instead of `{agent-name}.md`. The `.md` format is a deprecated alias — it still works but emits `[WARN] Deprecated override format: {file}. Migrate to .toml.` Use `/agent-flow:setup-agents` to auto-generate TOML stubs with smart defaults. See [TOML overlay syntax guide](../guides/toml-overlay-syntax.md) for the full schema, 3-tier merge rules, and worked examples.

**TOML merge tiers (summary):** Tier 1 — scalar overrides (`model`, `style`): overlay value replaces plugin default from agent frontmatter. Tier 2 — array of tables (`[[process_additions]]`, `[[constraints]]`): overlay entries appended after plugin defaults (order preserved). Tier 3 — deep merge (`[limits]`): overlay keys override corresponding plugin-default keys; absent keys are inherited unchanged. The `[meta]` free-form table accepts arbitrary annotation keys without schema validation and is not consumed by dispatch logic.

**TOML overlay example:**
```toml
# customization/reviewer.toml
model = "opus"
style = "rigorous"

[[process_additions]]
step = "after_default"
instruction = "Always check for SQL injection in all database queries."

[[constraints]]
rule = "Reject any diff that introduces raw string interpolation into SQL."

[limits]
max_review_iterations = 3

[meta]
author = "security-team"
added = "2026-04-27"
```

**Encoding project coding conventions (e.g. comment / identifier language).** Project-specific rules about *how code is written* — most commonly the natural language used for code comments and identifiers — belong in these per-agent overlays (and/or as a project-convention note in your CLAUDE.md), NOT hardcoded in the plugin's agent definitions. The code-generating agents (`fixer`, `test-engineer`, `scaffolder`) read their overlay before writing code, and the `reviewer` enforces it as a convention check (and rejects violations).

Worked example — a project whose UI is Czech but whose code must stay English (English comments + identifiers; Czech only in user-facing strings):

```toml
# customization/fixer.toml  — repeat in test-engineer.toml, scaffolder.toml, and reviewer.toml
[[constraints]]
rule = "Write all code comments and identifiers in English. Czech (or any national language) is allowed ONLY in user-facing string literals and resource files — never in comments or identifier names."
```

Because there is no single global overlay, repeat the rule in each code-generating agent's overlay (so it is never produced) **and** in `reviewer.toml` (so any violation is flagged). Alternatively, state it once as a project-convention note in your CLAUDE.md — every agent reads CLAUDE.md, and the reviewer enforces the code-language convention as part of its standard `Conventions` review item. (This is free-form project prose, not a dedicated Automation Config section.)

## Plugin Permission Architecture

agent-flow plugin agents do **NOT** support `hooks:`, `mcpServers:`, or `permissionMode:` keys in YAML frontmatter — the Claude Code platform ignores these fields for security reasons when set at agent level. **Hooks are skill-orchestrated, not agent-frontmatter** (hooks are skill-orchestrated, not agent-frontmatter) — pipeline hooks are configured at **PROJECT level** via the `### Hooks` section in your project's CLAUDE.md, NOT in any agent's YAML frontmatter.

<!-- COUNTER-EXAMPLE: Do NOT add these keys to agent frontmatter — they are silently ignored by the platform.
---
name: my-agent
description: Example agent
model: sonnet
hooks:
  - type: pre-tool-use
    command: echo "this is ignored"
mcpServers:
  my-server:
    command: npx
    args: ["-y", "some-mcp-server"]
permissionMode: acceptEdits
---
END COUNTER-EXAMPLE -->

**What works instead:**

| Goal | Correct approach |
|------|-----------------|
| Run a shell command before/after pipeline stages | `### Hooks` in project CLAUDE.md (`Pre-fix`, `Post-fix`, `Pre-publish`, `Post-publish`) |
| Add MCP servers for the project | Project-level `.claude/settings.json` `mcpServers` key |
| Set permission mode | Project-level `.claude/settings.json` `permissionMode` key |
| Add agent-specific instructions | `customization/{agent}.toml` via `### Agent Overrides` |

Existing project-level `### Hooks` config sections continue to work unchanged — no migration required. See [hooks documentation](hooks.md) for available hook points.

## Mode Flags

Pipeline-level mode flags are passed to `/agent-flow:fix-bugs`, `/agent-flow:implement-feature`, and `/agent-flow:scaffold` at invocation time — they are **not config keys** and do not belong in `## Automation Config`. Three modes are available:

| Flag | Description |
|------|-------------|
| `--yolo` | Skip all confirmation prompts; run end-to-end without pausing |
| *(default)* | Standard interactive mode — pauses at key gates for human review |
| `--step-mode` | Pause after every agent step for granular human oversight |

Mode flags interact with `### Pipeline Profiles`: a profile's `Skip stages` list is applied regardless of mode flag. `--yolo` additionally suppresses all NEEDS_CLARIFICATION pause events.

### Autopilot

Enables unattended continuous processing via `/agent-flow:autopilot`. All 7 keys have defaults — the section may be omitted entirely.

**NOTE on query keys:** `Bug query` and `Feature query` are NOT Autopilot-section keys. They are read from `### Issue Tracker` and `### Feature Workflow` respectively. Autopilot only references them.

| Key | Default | Description |
|-----|---------|-------------|
| Max issues per run | `1` | Total cap on issues dispatched per invocation (bugs + features combined) |
| Lock timeout | `120` | Age threshold in minutes after which an existing lock is considered stale and auto-recovered |
| Log file | `.agent-flow/autopilot.log` | Path to the append-only run log |
| Bug limit | `0` | Per-type cap on bug dispatches; `0` = no per-type cap |
| Feature limit | `0` | Per-type cap on feature dispatches; `0` = no per-type cap |
| On error | `skip` | `skip` = log [WARN] and continue; `stop` = abort the whole run on the first per-issue error |
| Dry run | `false` | `true` = no lock, no state, no webhooks, no dispatch — preview only |

**Example:**
```markdown
### Autopilot

| Key | Value |
|-----|-------|
| Max issues per run | 1 |
| Lock timeout | 120 |
| Log file | .agent-flow/autopilot.log |
| Bug limit | 0 |
| Feature limit | 0 |
| On error | skip |
| Dry run | false |
```

See [Autopilot Guide](../guides/autopilot.md) for behavior details, scheduling, and multi-host coordination.

### Pause Limits

Controls how long a pipeline waits in the `paused` state before being aborted. A pipeline enters the paused state when an agent emits a `NEEDS_CLARIFICATION` signal and is waiting for a human response via re-invocation of the original entry-point skill with `--clarification "answer"` (e.g. `/agent-flow:fix-bugs PROJ-42 --clarification "answer"`; auto-resume is detected inline by `core/resume-detection.md`).

| Key | Default | Description |
|-----|---------|-------------|
| Pause timeout | `30 days` | Time before a paused pipeline is auto-aborted (min: 1 hour, max: 365 days; invalid input → WARN + fallback to default) |

**Example:**
```markdown
### Pause Limits

| Key | Value |
|-----|-------|
| Pause timeout | 30 days |
```

See [Agent States](../../core/agent-states.md) for the full NEEDS_CLARIFICATION lifecycle and pause state transitions.

## Validation Rules

The `/agent-flow:check-setup` skill validates your Automation Config. Here is what it checks:

1. **Required sections present:** All 5 required sections (Issue Tracker, Source Control, PR Rules, PR Description Template, Build & Test) must exist
2. **Required keys present:** Each required section must contain all its required keys
3. **No placeholder values:** Keys must not contain `<TODO>`, `<...>`, or other placeholder patterns
4. **Table format:** All sections must use `| Key | Value |` tables, not bullet-point lists
5. **Tracker-specific validation:** Query syntax and state transition format are checked against the configured tracker Type
6. **MCP server presence:** An MCP server matching the tracker Type must be available
7. **Build/test commands:** Build and test commands execute successfully (unless `--skip-build`)
8. **Plugin composability:** Checks for skill name conflicts with other installed plugins

## Pipeline Profiles

Profiles allow you to customize which stages run. They are defined as rows in a table within the Pipeline Profiles subsection. The plugin uses **named-phase identifiers** for consolidated agents:

```markdown
### Pipeline Profiles

| Profile | Skip stages | Extra stages |
|---------|-------------|--------------|
| fast | analyst-triage, analyst-impact, test-engineer | (none) |
| strict | (none) | test-engineer-e2e |
| hotfix | analyst-triage, analyst-impact, test-engineer, test-engineer-e2e | (none) |
```

**Named-phase identifiers:**

| Named-phase ID | Agent + flag | Description |
|----------------|-------------|-------------|
| `analyst-triage` | `analyst --phase triage` | Bug/feature triage |
| `analyst-impact` | `analyst --phase impact` | Code impact analysis |
| `test-engineer-e2e` | `test-engineer --e2e` | E2E test pass |
| `browser-agent-reproduce` | `browser-agent --phase reproduce` | Browser reproduction |
| `browser-agent-verify` | `browser-agent --phase verify` | Browser verification |

**Non-skippable stages (mandatory):** fixer, reviewer, publisher

Profiles apply to `/agent-flow:fix-bugs` and `/agent-flow:implement-feature` via the `--profile <name>` flag.

## Migration

If your project uses an older Automation Config format, update it manually to match the current section structure documented in this file. For version history and what changed between major versions, see the [CHANGELOG](../../CHANGELOG.md).

## Automation Config

Canonical reference for the 23 Automation Config sections (5 required + 18 optional). Section ordering and key names must match between this file and the consumer project's CLAUDE.md (per `tests/scenarios/counts-invariants.sh`).

### Retry Limits

Keys + defaults: Fixer iterations (5), Test attempts (3), Build retries (3), Spec iterations (5), Root cause iterations (3).

### Module Docs

Keys: Path. Default (none).

### Hooks

Keys: Pre-fix, Post-fix, Pre-publish, Post-publish. Default (none).

### Custom Agents

Keys: Post-fix agent, Pre-publish agent. Default (none).

### Notifications

Keys: Webhook URL, On events (`pr-created`, `issue-blocked`, `pipeline-started`, `step-completed`, `pipeline-completed`). Default (none).

### Worktrees

Keys: Batch size, Base path, Cleanup. Default (none).

### E2E Test

Keys: Framework, Command. Default (none).

### Browser Verification

Keys: Base URL, Start command, Stop command, On events, Timeout, Max pages, Screenshot storage, Exploration, Exploration max clicks. Default (none).

### Error Handling

Keys + defaults: On block (comment), Max blocked per run (unlimited).

### Feature Workflow

Keys: Feature query, On start set. Default (none).

### Decomposition

Keys + defaults: Max subtasks (7), Fail strategy (fail-fast), Commit strategy (squash), Create tracker subtasks (enabled).

### Pipeline Profiles

Keys: Profile, Skip stages, Extra stages. Default (none). Applies to fix-bugs and implement-feature. Non-skippable: fixer, reviewer, publisher.

### Metrics

Keys + defaults: Output (stdout), Period (30 days).

### Agent Overrides

Keys + default: Path (customization/). Per-agent customization files appended as `## Project-Specific Instructions` to agent prompts.

### Local Deployment

Keys: Type, Start command, Stop command, Health check URL, Health check timeout, Ports. Default (none).

### Sprint Planning

Keys + defaults: Sprint duration (2 weeks), Capacity unit (story-points), Team capacity (none), Velocity target (none), Sprint field (tracker-dependent), Mode (suggest), Max issues (20), Epic template (none).

### Autopilot

Exactly 7 keys: Max issues per run (1), Lock timeout (120), Log file (.agent-flow/autopilot.log), Bug limit (0), Feature limit (0), On error (skip), Dry run (false). `Bug query` is read from `### Issue Tracker`; `Feature query` from `### Feature Workflow`.

### Pause Limits

Keys + defaults: Pause timeout (30 days). Valid range 1 hour - 365 days; invalid values fall back to default with `[WARN]` log.

## Complete Example

A full Automation Config for a GitHub + Node.js project:

```markdown
## Automation Config

### Issue Tracker

| Key | Value |
|-----|-------|
| Type | `github` |
| Instance | `https://github.com` |
| Project | `acme-corp/web-app` |
| Bug query | `is:issue is:open label:bug sort:created-desc` |
| State transitions | `In Progress → open, For Review → open, Blocked → open label:blocked, Done → closed` |
| On start set | `In Progress` |

### Source Control

| Key | Value |
|-----|-------|
| Remote | `acme-corp/web-app` |
| Base branch | `main` |
| Branch naming | `fix/{issue-id}-{description}` |

### PR Rules

| Key | Value |
|-----|-------|
| Labels | `bug, automated` |
| Title format | `{issue-id}-{mode}-{summary}` |

### PR Description Template

## Summary
{summary}

## Root Cause
{root_cause}

## Changes
{changes}

## Testing
{testing}

## Issue
Closes #{issue_id}

### Build & Test

| Key | Value |
|-----|-------|
| Build command | `npm run build` |
| Test command | `npm test` |
| Verify command | `npm run test:integration` |

### Retry Limits

| Key | Value |
|-----|-------|
| Fixer iterations | `5` |
| Test attempts | `3` |
| Build retries | `3` |
| Spec iterations | `5` |
| Root cause iterations | `3` |

### Hooks

| Key | Value |
|-----|-------|
| Pre-fix | `npm run lint:check` |
| Post-fix | `npx prettier --write .` |

### E2E Test

| Key | Value |
|-----|-------|
| Framework | `playwright` |
| Command | `npx playwright test` |

### Feature Workflow

| Key | Value |
|-----|-------|
| Feature query | `is:issue is:open label:enhancement sort:created-desc` |
| On start set | `In Progress` |

### Pipeline Profiles

| Profile | Skip stages | Extra stages |
|---------|-------------|--------------|
| fast | analyst-triage, analyst-impact, test-engineer | (none) |
| strict | (none) | test-engineer-e2e |

<!-- ### Autopilot (optional)
| Key | Value |
|-----|-------|
| Max issues per run | 1 |
| Lock timeout | 120 |
| Log file | .agent-flow/autopilot.log |
| Bug limit | 0 |
| Feature limit | 0 |
| On error | skip |
| Dry run | false |

### Pause Limits (optional)
| Key | Value |
|-----|-------|
| Pause timeout | 30 days |
-->
```
