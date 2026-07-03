# Skills Reference

This reference covers all 17 skills in the agent-flow plugin. All 17 agent-flow skills are listed with syntax, descriptions, flags, and usage examples. Skills are the orchestration layer of the plugin — they define WHAT to do, while agents define HOW to do it (17 agents reference 17 core contracts).

## Conventions

- All skills are namespaced: `/agent-flow:<skill>`
- Skills read Automation Config from the consuming project's CLAUDE.md
- Skills dispatch agents via Claude Code's Task tool
- Skills contain zero project-specific logic — all configuration comes from Automation Config
- Publisher is never called automatically — the user decides when to publish
- Resume is automatic. To resume a paused pipeline, re-invoke the entry-point skill (`/fix-bugs`, `/implement-feature`, or `/scaffold`). To answer a NEEDS_CLARIFICATION question, add `--clarification "<answer>"` to the re-invocation.

## Skill Index

| Category | Skill | Description |
|----------|-------|-------------|
| Bug-Fix | [/analyze-bug](#analyze-bug) | Analyzes a specific bug (no code changes) |
| Bug-Fix | [/autopilot](#autopilot) | Headless dispatcher for cron / batch / CI — reads queries, classifies issues, dispatches fix-bugs / implement-feature |
| Bug-Fix | [/fix-bugs](#fix-bugs) | Analyzes and fixes issues — single ticket (\<ISSUE-ID\>) or batch (--batch \<N\>) |
| Feature | [/implement-feature](#implement-feature) | Implements a feature end-to-end |
| Scaffold | [/scaffold](#scaffold) | Creates a new project from scratch; use 'add \<component\>' to extend an existing project |
| Publishing | [/publish](#publish) | Creates a PR and updates issue tracker |
| Config | [/onboard](#onboard) | Interactive wizard for generating config |
| Config | [/setup-mcp](#setup-mcp) | Configures developer environment (MCP, permissions) |
| Config | [/check-setup](#check-setup) | Validates config, MCP, and connectivity |
| Config | [/setup-agents](#setup-agents) | One-shot project scanner that generates smart customization/*.toml defaults per agent |
| Monitoring | [/metrics](#metrics) | Pipeline analytics report |
| Planning | [/prioritize](#prioritize) | AI-powered backlog prioritization |
| Planning | [/create-backlog](#create-backlog) | Creates backlog epics in issue tracker from a specification document |
| Planning | [/sprint-plan](#sprint-plan) | Plans a sprint from backlog issues using capacity constraints and priority ranking |
| Versioning | [/version-check](#version-check) | Compares installed vs latest version |
| Versioning | [/changelog](#changelog) | Generates changelog from merged PRs |
| Discussion | [/discuss](#discuss) | Multi-agent discussion on a topic (freeform text; not tracker-aware) |

---

## Bug-Fix Skills

### /analyze-bug

> Analyzes a specific bug from the issue tracker (analysis only, no code changes).

**Syntax:**

```
/agent-flow:analyze-bug <ISSUE-ID>
```

**Arguments:**
- `<ISSUE-ID>` — Required. Ticket ID in the issue tracker.

**What it does:** Runs analyst (--phase triage) and analyst (--phase impact) on a specific bug. Produces a triage analysis and impact report without making any code changes, git operations, or issue tracker state updates. Useful for understanding a bug before deciding to fix it.

**Example:**

```
/agent-flow:analyze-bug PROJ-42
```

**Related skills:** [/fix-bugs](#fix-bugs)

---

### /autopilot

> Headless dispatcher for unattended cron / batch / CI invocation — reads Bug query / Feature query from Automation Config, classifies issues, and dispatches fix-bugs / implement-feature. Lock-file protected.

**Syntax:**

```
/agent-flow:autopilot [--dry-run]
```

**Flags:**
- `--dry-run` — Full short-circuit: print what would be processed, no lock, no dispatch, no state writes

**What it does:** Reads `### Issue Tracker`, `### Feature Workflow` (optional), and `### Autopilot` (optional) from `## Automation Config`, fetches issues via the tracker MCP, classifies them as bugs or features, and dispatches `fix-bugs` or `implement-feature` per issue sequentially via a headless `claude -p` child-process invocation — NOT the Skill tool, since pipeline entry-point skills block the Skill tool dispatch path via `disable-model-invocation: true`. Acquires a portable `mkdir`-based lock (`.agent-flow/autopilot.lock/`) to prevent concurrent runs on the same host. Produces a summary table with outcome, duration, and token usage per issue. Typically invoked headlessly:

```bash
claude -p "Run /agent-flow:autopilot" --dangerously-skip-permissions
```

**Exit codes:** `0` = all dispatched, `1` = preflight/config failure, `2` = lock held, `3` = MCP unreachable.

**Example:**

```
/agent-flow:autopilot --dry-run
```

**Related skills:** [/fix-bugs](#fix-bugs), [/implement-feature](#implement-feature), [/check-setup](#check-setup)

---

### /fix-bugs

> Analyzes and fixes issues — single ticket (\<ISSUE-ID\>) or batch (--batch \<N\>).

**Syntax:**

```
/agent-flow:fix-bugs <ISSUE-ID> [--dry-run] [--decompose | --no-decompose] [--profile <name>] [--yolo | --step-mode] [--clarification "<answer>"]
/agent-flow:fix-bugs --batch <N> [--dry-run] [--decompose | --no-decompose] [--profile <name>] [--yolo | --step-mode]
```

**Arguments:**
- `<ISSUE-ID>` — Single-ticket mode. Ticket ID in the issue tracker (e.g., `PROJ-42`, or numeric ID on github/gitea/redmine).
- `--batch <N>` — Batch mode. Number of bugs to process from the Bug query.

**Argument auto-detection:** Bare-integer arguments are interpreted as ISSUE-ID on numeric trackers (github/gitea/redmine) and as batch count on string trackers (youtrack/jira/linear). On string trackers, a disambiguation warning is emitted. Use `--batch <N>` explicitly for unambiguous batch invocation (recommended in scripts/CI).

**Flags:**
- `--dry-run` — Run triage and code analysis only, no side effects
- `--decompose` — Force decomposition into subtasks
- `--no-decompose` — Disable decomposition (always single-pass)
- `--profile <name>` — Apply a pipeline profile from Automation Config
- `--yolo` — Skip all confirmations, auto-approve and auto-publish (mutually exclusive with `--step-mode`)
- `--step-mode` — Pause after every pipeline step for manual review before continuing (mutually exclusive with `--yolo`)
- `--clarification "<answer>"` — Provide the human answer to a paused-pipeline NEEDS_CLARIFICATION question and resume from the paused point. Single-ticket mode only.

**What it does:** Runs the full bug-fix pipeline. In single-ticket mode, processes one issue end-to-end (triage → code analysis → fix → review → test → publish). In batch mode (`--batch <N>`), queries the issue tracker using the Bug query from Automation Config and processes up to N bugs through the full pipeline; supports parallel processing via worktrees when the Worktrees section is configured. On every invocation, automatically detects in-progress pipelines for the target ISSUE-ID via `.agent-flow/{ISSUE-ID}/state.json` and prompts to resume.

**Examples:**

```
/agent-flow:fix-bugs PROJ-42 --dry-run
/agent-flow:fix-bugs --batch 5 --profile fast
/agent-flow:fix-bugs PROJ-42 --clarification "Use option B"
```

**Related skills:** [/analyze-bug](#analyze-bug), [/prioritize](#prioritize)

---

## Feature Skills

### /implement-feature

> Implements a feature from the issue tracker — spec, design, fix, review, test, publish.

**Syntax:**

```
/agent-flow:implement-feature <ISSUE-ID> [--dry-run] [--decompose | --no-decompose | --decompose-only] [--profile <name>] [--yolo | --step-mode] [--clarification "<text>"]
/agent-flow:implement-feature --description "<text>" [--dry-run] [--decompose | --no-decompose | --decompose-only] [--profile <name>] [--yolo | --step-mode]
```

**Arguments:**
- `<ISSUE-ID>` — Feature issue ID in the tracker. Mutually exclusive with `--description`.
- `--description "<text>"` — Alternate invocation mode: describe the feature inline instead of reading it from a tracker issue. Mutually exclusive with `<ISSUE-ID>`.

**Flags:**
- `--dry-run` — Run spec analysis and architecture design only, no side effects
- `--decompose` — Force decomposition into subtasks
- `--no-decompose` — Disable decomposition (single-pass); mutually exclusive with `--decompose-only`
- `--decompose-only` — Exit after tracker subtask creation, without implementing the subtasks (implies `--decompose`; mutually exclusive with `--no-decompose`)
- `--profile <name>` — Apply a pipeline profile from Automation Config
- `--yolo` — Skip all confirmations, auto-approve decomposition and auto-publish (mutually exclusive with `--step-mode`)
- `--step-mode` — Pause after every pipeline step for manual review before continuing (mutually exclusive with `--yolo`)
- `--clarification "<text>"` — Provide the human answer to a paused-pipeline NEEDS_CLARIFICATION question and resume from the paused point.

**What it does:** Runs the full feature pipeline: spec-analyst extracts requirements, architect designs the solution and optionally decomposes it into subtasks, then fixer/reviewer/test-engineer execute each subtask. The user confirms the decomposition plan before execution starts. After all subtasks pass, the result is presented for publishing. When decomposition is active, creates corresponding tracker sub-issues under the parent issue before executing subtasks (configurable via `Create tracker subtasks` in Decomposition config). With `--decompose-only`, the pipeline exits right after subtask creation and never dispatches fixer/reviewer/test-engineer.

**Example:**

```
/agent-flow:implement-feature PROJ-50 --decompose
/agent-flow:implement-feature --description "Add CSV export to the reports page" --dry-run
/agent-flow:implement-feature PROJ-50 --decompose-only
/agent-flow:implement-feature PROJ-50 --clarification "Use option B"
```

**Related skills:** [/fix-bugs](#fix-bugs), [/scaffold](#scaffold)

---

## Scaffold Skills

### /scaffold

> Creates a new project from scratch. Modes: default (brainstorm-if-vague + 2 checkpoints) / `--yolo` (autonomous, no confirmation gates) / `--step-mode` (pause after each pipeline step).

**Syntax:**

```
/agent-flow:scaffold <description> [--template <path>] [--spec <path>] [--issue <ID>] [--no-implement] [--yolo | --step-mode] [--lang <language>] [--framework <framework>] [--db <database>] [--ci <provider>]
```

**Arguments:**
- `<description>` — Required (unless --spec, --template, or --issue provided). Natural language description of the project.

**Flags:**
- `--template <path>` — Use a custom specification template
- `--spec <path>` — Use a ready specification (skip spec-writer, spec-reviewer validates)
- `--issue <ID>` — Read project description from issue tracker card
- `--no-implement` — Skeleton only, no specification or feature implementation (v3.x behavior)
- `--yolo` — Skip all confirmation gates, run fully autonomously (mutually exclusive with `--step-mode`)
- `--step-mode` — Pause after every pipeline step for manual review (mutually exclusive with `--yolo`)
- `--lang <language>` — Preset language (e.g., `python`, `typescript`)
- `--framework <framework>` — Preset framework (e.g., `fastapi`, `express`)
- `--db <database>` — Preset database (e.g., `postgresql`, `mongodb`)
- `--ci <provider>` — Preset CI provider (e.g., `github`, `gitea`)

**Input source flags** (`--spec`, `--template`, `--issue`) are mutually exclusive. Tech stack flags (`--lang`, `--framework`, `--db`, `--ci`) are compatible with all input sources.

**What it does:** Scaffolds a new project end-to-end. In **default mode**, spec-writer generates a project specification (with optional brainstorm phase when description is vague), a spec-reviewer quality gate runs, scaffolder generates the skeleton with auto-configured CLAUDE.md, and the feature pipeline (architect → fixer/reviewer/test-engineer) implements all features from the spec. Two human confirmation checkpoints: after spec and after the feature plan (architect/decomposition). With **`--yolo`**, all confirmation gates are skipped and the pipeline runs autonomously. With **`--step-mode`**, execution pauses after every step for manual review before continuing. After git init, the scaffold pushes to the declared remote (Step 4d) and creates tracker issues from spec epics (Step 4e) when infrastructure is ready. The `--issue` flag auto-detects tracker availability. With `--no-implement`, falls back to skeleton-only behavior: scaffolder (with stack flags) → skeleton → push (if SC ready).

**Example:**

```
/agent-flow:scaffold "REST API for user management with auth and roles" --lang python
```

**Note:** Use `--no-implement` for v3.x skeleton-only behavior without specification or feature implementation.

**Adding components to an existing project:** Use `/agent-flow:scaffold add <component>` (subcommand of `/scaffold`) where `<component>` is one of `claude-md`, `ci`, `docker`, `tests`. For example, `/agent-flow:scaffold add ci` adds a CI workflow file to the current project. Unknown components produce `[ERROR] Unknown component: {NAME}` and exit 1.

**Related skills:** [/check-setup](#check-setup), [/implement-feature](#implement-feature)

---

## Publishing Skills

### /publish

> Creates a PR and, only in full-publish mode, updates issue tracker state.

**Syntax:**

```
/agent-flow:publish
```

**What it does:** Auto-detects the publish **mode** from the current branch name against `Source Control → Branch naming` in Automation Config, then dispatches the `publisher` agent to create a PR with the full template and apply labels. There are three success modes and one failure mode:

| Mode | When | Tracker updated? |
|------|------|-------------------|
| `full-publish` | Branch encodes an issue ID that exists in the tracker | Yes — state set per `State transitions`, PR-link comment posted |
| `pr-only-no-id` | No `Branch naming` configured, or the branch doesn't match the pattern | No |
| `pr-only-404` | Branch encodes an issue ID, but the tracker returns not-found for it | No (PR is still created; a WARN is logged) |
| `FAIL` | Tracker unreachable (auth/TLS/timeout/unknown error), or detached HEAD | No PR is created; exits non-zero |

The issue tracker is only written to in `full-publish` mode — the other two success modes create the PR alone, with no tracker state change or comment. This is the same publish step (including its optional Pre-publish/Post-publish hooks and custom agents) that runs at the end of fix-bugs and implement-feature, exposed as a standalone skill.

`/publish` is interactive-only — it requires the confirmation flows built into the dispatched agent's prose and may FAIL in headless environments (CI/cron) with no MCP server configured. For headless/batch publishing use [/autopilot](#autopilot) instead.

**Example:**

```
/agent-flow:publish
```

**Related skills:** [/fix-bugs](#fix-bugs), [/autopilot](#autopilot)

---

## Configuration Skills

### /onboard

> Interactive wizard for generating Automation Config.

**Syntax:**

```
/agent-flow:onboard [--fresh] [--update]
```

**Flags:**
- `--fresh` — Force fresh mode: skip existing-config detection and start the wizard from scratch
- `--update` — Force update mode: walk through the existing config and change only what you select. Errors if no `## Automation Config` section exists yet

**What it does:** Launches an interactive wizard that asks about your project setup: issue tracker type, instance URL, project key, source control remote, build/test commands, and more. Generates a complete Automation Config block that can be added to your project's CLAUDE.md. Supports all 6 tracker types (YouTrack, GitHub, Jira, Linear, Gitea, Redmine). With no flags, it auto-detects whether a config already exists and routes to fresh or update mode accordingly.

**Example:**

```
/agent-flow:onboard
/agent-flow:onboard --update
```

**Related skills:** [/setup-mcp](#setup-mcp), [/check-setup](#check-setup)

---

### /setup-mcp

> Configures developer environment — MCP servers, tokens, and permissions.

**Syntax:**

```
/agent-flow:setup-mcp
/agent-flow:setup-mcp --update
/agent-flow:setup-mcp --tracker-type <type> [--tracker-instance <url>] [--sc-remote <owner/repo>]
```

**Flags:**
- `--update` — Update existing configuration, preserving non-agent-flow servers
- `--tracker-type <type>` — Override tracker type. Bypasses CLAUDE.md read.
- `--tracker-instance <url>` — Override tracker instance URL. Defaults to type-specific default.
- `--sc-remote <owner/repo>` — Override SC remote. Omit for tracker-only setup.

| Aspect | Detail |
|--------|--------|
| Input | (none), `--update`, or CLI override flags |
| Output | `.mcp.json`, `.mcp.json.example`, `.claude/settings.json` |
| Destructive | Yes (writes files) |
| MCP required | Yes (for connectivity validation) |

**What it does:** Sets up the developer environment for agent-flow. Reads your Automation Config to determine which MCP servers and tokens are needed, guides you through token collection, generates `.mcp.json` with proper server configuration, and optionally sets up tool permissions in `.claude/settings.json`. Creates `.mcp.json.example` for team sharing (without secrets).

When CLI override flags are provided (`--tracker-type`, `--tracker-instance`, `--sc-remote`), setup-mcp bypasses the Automation Config read entirely. This enables setup-mcp to run before CLAUDE.md exists — for example, during scaffold when the project has no configuration yet.

**Examples:**

```
/agent-flow:setup-mcp
```

```
/agent-flow:setup-mcp --tracker-type gitea --tracker-instance https://git.example.com --sc-remote myorg/myproject
```

**Related skills:** [/onboard](#onboard), [/check-setup](#check-setup)

---

### /check-setup

> Validate Automation Config, MCP servers, and tokens.

**Syntax:**

```
/agent-flow:check-setup [--skip-build]
```

**Flags:**
- `--skip-build` — Skip the build and test command validation

**What it does:** Performs a comprehensive validation of your agent-flow setup. Checks that all required Automation Config sections and keys are present, values are not placeholders, table format is correct, MCP servers matching the tracker type are available, and build/test commands execute successfully. Reports pass/fail for each validation block with actionable fix suggestions. Additional blocks beyond the core config/MCP/connectivity/build-test checks:

- **Docker dry-build** — if a `Dockerfile` exists and `docker` is on PATH (and `--skip-build` was not passed), runs `docker build --no-cache` as a smoke test and reports `[OK]`/`[FAIL]` (with the last 3 log lines on failure), or `[SKIP]` when there's no `Dockerfile`, `docker` isn't installed, or `--skip-build` was passed.
- **Plugin Composability** — scans installed plugins for command-name conflicts with agent-flow's unprefixed command names and warns per conflicting plugin/command pair.
- **Dispatch Enforcement Hook** — advisory-only check for whether `hooks/validate-dispatch.sh` is present and wired into `~/.claude/settings.json` as a `PostToolUse` hook; results here never affect the FAIL count or verdict.
- **Agent Overrides (TOML validation)** — verifies a TOML parser (`tomllib`/`tomli`) is importable by `python3` (overlays are silently dropped by the override injector otherwise) and, when available, parses and validates every `customization/{agent}.toml` overlay end-to-end, reporting per-file `[OK]`/`[FAIL]`.
- **Deprecated config detection** — scans CLAUDE.md for deprecated Automation Config sections (e.g. `### Extra labels`) and emits a `[WARN]` with a migration pointer; this never changes the exit code.

**Example:**

```
/agent-flow:check-setup --skip-build
```

**Related skills:** [/onboard](#onboard)

---

### /setup-agents

> One-shot project scanner that generates smart customization/*.toml defaults per agent.

**Syntax:**

```
/agent-flow:setup-agents [--dry-run] [--yolo] [--force]
```

**Flags:**
- `--dry-run` — Preview the generated `.toml` files without writing them
- `--yolo` — Write files without asking for confirmation
- `--force` — Overwrite existing `.toml` files (default: skip files that don't have `# generated:` header, preserving manual edits)

**What it does:** Scans the consuming project to detect project type (Python, TypeScript, monorepo, Java, Rust, .NET, test framework) and generates smart `customization/{agent}.toml` default overlays for each applicable agent. Generated files include a `# generated: agent-flow setup-agents` header that marks them as safe to overwrite on subsequent runs. Files without this header (manually edited or created) are never overwritten unless `--force` is used. After scan, displays a preview diff of all files to be created or updated, then asks for confirmation (unless `--yolo`).

TOML overlay syntax and the 3-tier merge contract are documented in `core/overlay/toml-overlay.md`. Full heuristic enumeration and worked examples: `docs/guides/setup-agents-skill.md`.

**Example:**

```
/agent-flow:setup-agents --dry-run
/agent-flow:setup-agents --yolo
```

**Related skills:** [/onboard](#onboard), [/check-setup](#check-setup)

---

## Monitoring Skills

### /metrics

> Pipeline analytics report — success rates, per-agent effectiveness.

**Syntax:**

```
/agent-flow:metrics [--period <N>] [--output <path>] [--format <md|json|html>]
```

**Flags:**
- `--period <N>` — Analysis period in days (default: 30)
- `--output <path>` — Output file path (default: stdout; for `--format html` with no `--output`, defaults to `./metrics.html`)
- `--format <md|json|html>` — Output format: markdown, JSON, or a self-contained HTML dashboard (default: md, with an interactive save prompt when the flag is omitted entirely — see below)

**What it does:** Generates a pipeline analytics report covering success rates, per-agent effectiveness, common failure patterns, and trend data. Analyzes `[agent-flow]` comments and PR history to compute metrics. Useful for identifying bottleneck agents and tuning retry limits.

**HTML dashboard (`--format html`):** Generates a self-contained HTML file (inline CSS/JS, no external requests) with a header, a Pipeline Overview (Active/Blocked/Completed cards), a sortable Issue Table, a Blocked Issues panel, a Recent Activity timeline, statistics (success rate, throughput, block distribution), and threshold-based Recommendations. All tracker-sourced fields (issue title, state, stage, agent, PR link, block reason/recommendation, timeline content) are HTML-escaped before interpolation, and PR links are additionally validated (only `https?://` or bare `#N` values are rendered as `<a href>`; anything else — e.g. a `javascript:` scheme — is rendered as plain escaped text) to prevent XSS from crafted tracker content. Written to `--output` if given, otherwise `./metrics.html`.

**Interactive save prompt:** When `/agent-flow:metrics` is invoked with no `--format` flag at all, the markdown report is rendered and displayed first, then the skill asks `Save output? [1] No [2] JSON → stdout [3] HTML → ./metrics.html` and acts on the response (any unrecognized input is treated as "No"). Supplying `--format` explicitly skips this prompt entirely. Autopilot never invokes `/metrics`, so this interactive prompt is never reached from unattended/headless runs.

**Pipeline history file:** `.agent-flow/pipeline-history.md` is an append-only run log written after every pipeline completion. It contains metadata only — fields: `run_id`, `date`, `pipeline`, `outcome`, `complexity`, `duration_s`, `agents_touched`, `block_agent`, `block_step`, `block_reason` (sanitized via 18-pattern credential redaction including bare-keyword variables). `/metrics` itself reads this file as an optional, supplementary fast-path cross-check (Step 2a): for entries within `--period`, it reads `outcome`, `complexity`, and `duration_s` directly (no regex against comment prose), and uses `agents_touched`/`block_agent`/`block_step` to cross-check per-agent invocation counts and block-stage bucketing. The file retains only the last 50 runs, so `/metrics` treats it as a supplement, never a replacement, for tracker-comment parsing and state.json — when the same run appears in more than one source, `/metrics` prefers state.json, then pipeline-history.md, then the tracker comment. Separately, the fixer agent reads the last 5 entries and the reviewer agent reads the last 10 entries at Step 1 to inform their decisions — see `docs/reference/agents.md` for that usage. Full contract: see `core/post-publish-hook.md` Section 5. For `.gitignore` guidance see [docs/guides/installation.md § Pipeline State and .gitignore](../guides/installation.md#4-pipeline-state-and-gitignore).

**Example:**

```
/agent-flow:metrics --period 14 --format json --output metrics.json
/agent-flow:metrics --format html
/agent-flow:metrics
```

**Related skills:** [/fix-bugs](#fix-bugs)

---

## Planning Skills

### /prioritize

> Analyzes backlog and suggests fix order using AI prioritization.

**Syntax:**

```
/agent-flow:prioritize [--limit <N>] [--output <path>]
```

**Flags:**
- `--limit <N>` — Maximum number of issues to analyze (default: 50)
- `--output <path>` — Output file path (default: stdout)

**What it does:** Dispatches the priority-engine agent to analyze the issue backlog and produce a ranked prioritization. Issues are scored using the formula `(Impact x 2 + Risk x 1.5) / Effort + dependency_bonus` and grouped into P0/P1/P2 tiers. Includes a dependency graph and batch recommendation for the highest-priority issues.

**Example:**

```
/agent-flow:prioritize --limit 20 --output priority-report.md
```

**Related skills:** [/fix-bugs](#fix-bugs), [/metrics](#metrics)

---

### /create-backlog

> Creates backlog epics in issue tracker from a specification document

**Syntax:** `/agent-flow:create-backlog <spec-path> [flags]`

**Arguments:**
- `<spec-path>` — Path to spec file, spec/ folder, or multiple files

**Flags:**
- `--decompose` — After epic creation, dispatch architect for subtask decomposition
- `--update` — Match existing tracker issues by title, update instead of create
- `--dry-run` — Display epic preview without creating tracker issues
- `--yolo` — Auto-approve human confirmation gates

**What it does:**
1. Reads specification files and dispatches backlog-creator agent
2. Displays epic preview table (title, AC count, size, dependencies)
3. Creates epic issues in tracker after human confirmation
4. Optionally decomposes epics into subtasks via architect agent

**Example:**

```
/agent-flow:create-backlog spec/
/agent-flow:create-backlog spec/epics/auth.md --update
/agent-flow:create-backlog spec/ --decompose --yolo
```

**Related skills:** [/sprint-plan](#sprint-plan), [/implement-feature](#implement-feature), [/prioritize](#prioritize)

---

### /sprint-plan

> Plans a sprint from backlog issues using capacity constraints and priority ranking

**Syntax:** `/agent-flow:sprint-plan [flags]`

**Flags:**
- `--all` — Plan all sprints (release plan), not just the next one
- `--apply` — After planning, dispatch /fix-bugs (for bug-type issues) or /implement-feature (for feature-type issues) per selected issue
- `--dry-run` — Display plan without tracker writes
- `--limit <N>` — Override max issues to consider (default: 20)
- `--yolo` — Auto-approve Gates 1 and 3 (Gate 2 always blocks)

**What it does:**
1. Fetches open issues from tracker
2. Dispatches priority-engine for ranking (P0/P1/P2 tiers)
3. Dispatches sprint-planner for capacity-constrained selection
4. Three human gates: capacity confirmation, AC coverage check, final approval
5. Assigns selected issues to sprint in tracker
6. Optionally dispatches implementation pipeline per issue

**Example:**

```
/agent-flow:sprint-plan
/agent-flow:sprint-plan --all
/agent-flow:sprint-plan --apply --yolo
/agent-flow:sprint-plan --dry-run --limit 10
```

**Related skills:** [/create-backlog](#create-backlog), [/prioritize](#prioritize), [/implement-feature](#implement-feature)

---

## Versioning Skills

### /version-check

> Compares installed plugin version with latest available.

**Syntax:**

```
/agent-flow:version-check
```

**What it does:** Works from any directory. Reads the installed plugin version from `~/.claude/plugins/installed_plugins.json` and compares it with the latest version tag on the remote repository. Reports whether an update is available. When run from the plugin's own repo directory, also compares the repo version with the installed version — and, if the repo is behind remote, runs `git pull` to update it, then, if the repo is ahead of the installed plugin, runs `claude plugin marketplace update` and `claude plugin update` to sync the installed plugin cache. These two steps mutate local state (the repo working tree and the plugin cache); they only trigger when run from inside the plugin's own repo. Provides clear reinstall instructions when versions are stale.

**Example:**

```
/agent-flow:version-check
```

**Related skills:** [/changelog](#changelog)

---

### /changelog

> Automatic changelog generation from merged PRs.

**Syntax:**

```
/agent-flow:changelog
```

**What it does:** Scans commits since the last git tag (merged PRs via source control MCP, or the linear commit history as a fallback for squash/fast-forward merge workflows), categorizes each entry by its Conventional Commits prefix into Keep a Changelog sections (Added, Fixed, Changed), and generates a CHANGELOG.md entry for a version confirmed with the user. Uses PR titles — falling back to the raw commit subject when a PR cannot be resolved — to produce changelog entries.

**Example:**

```
/agent-flow:changelog
```

**Related skills:** [/version-check](#version-check)

---

## Discussion Skills

### /discuss

> Multi-agent discussion — explores a freeform topic with multiple agent perspectives.

**Syntax:**

```
/agent-flow:discuss <topic> [--agents <list>]
```

**Arguments:**
- `<topic>` — Required. Freeform topic or question text. Always treated as literal text — `/discuss` never queries the issue tracker or resolves issue IDs, even if the topic string happens to look like one (there is no tracker MCP tool in this skill's `allowed-tools`).

**Flags:**
- `--agents <list>` — Comma-separated agent names to participate (e.g. `--agents reviewer,architect`). Validated against `agents/*.md`; an unknown name stops the discussion before any dispatch with `Unknown agent: {name}. Valid agents: {list}.`. Duplicate names are deduped (case-sensitive, first occurrence kept). Default when omitted: `reviewer,fixer,architect`. Max 3 agents per discussion — if more than 3 remain after dedupe, only the first 3 (in the given order) are used, and the skill tells you which were dropped.

**What it does:** Facilitates a structured multi-agent discussion on a given topic. Multiple agents contribute their perspective (e.g., reviewer raises concerns, architect proposes approaches, fixer weighs implementation tradeoffs) — read-only, no code changes, no tracker writes. Useful for exploring complex decisions, reviewing tradeoffs, or getting multi-perspective analysis before committing to an approach.

**Example:**

```
/agent-flow:discuss "Should we migrate the auth module to JWT?"
/agent-flow:discuss "Should we migrate the auth module to JWT?" --agents reviewer,architect
```

**Related skills:** [/analyze-bug](#analyze-bug)

