# Getting Started with agent-flow

agent-flow is a Claude Code plugin that automates bug-fix workflows, feature implementation, and project scaffolding. It takes an issue from your tracker, analyzes it, fixes it, reviews the fix, writes tests, and creates a pull request — all orchestrated by slash commands.

In this tutorial, you will install the plugin, configure it for your project, validate the setup, and run your first automated bug fix. By the end, you will have a working pipeline that can process issues from your tracker.

## Prerequisites

Before you begin, make sure you have:

- **Claude Code CLI** installed and working. You should be able to start a Claude Code session from your terminal.
- **Git** installed and configured with your credentials.
- **A running project** with source code in a git repository.
- **Python 3.11+** — *only if you plan to use `customization/*.toml` agent overrides.* Overlay files are parsed by `python3` via `tomllib` (Python 3.11+ stdlib) or the `tomli` backport (`pip install tomli` on Python 3.10). Without a parser, the override injector **silently drops every overlay** — customizations are ignored with no dispatch-time error. `/agent-flow:check-setup` flags this. Skip if you don't use TOML overlays.
- **An issue tracker** with at least one open bug. Supported trackers:
  - YouTrack
  - GitHub Issues
  - Jira
  - Linear
  - Gitea
  - Redmine
- **MCP servers** configured for your issue tracker and source control. agent-flow communicates with external systems exclusively through MCP (Model Context Protocol) servers. See [MCP Configuration Guide](guides/mcp-configuration.md) for setup instructions.

## Step 1: Install the Plugin

Install agent-flow via the CLI:

```bash
claude plugin marketplace add <path-to-repo>  # e.g. C:/gitea_agent-flow
claude plugin install agent-flow@agent-flow
```

To verify the installation succeeded, type `/agent-flow:` and press Tab. You should see a list of available commands starting with the `agent-flow:` prefix.

If the commands do not appear after installation, restart your Claude Code session (close and reopen the terminal). For platform-specific installation notes, see [Installation Guide](guides/installation.md).

## Step 2: Configure Your Project

Navigate to your project directory and run the onboarding wizard:

```
/agent-flow:onboard
```

The wizard will ask you about your project setup:

1. **Issue tracker type** — Select your tracker (youtrack, github, jira, linear, gitea, or redmine)
2. **Instance URL** — The URL of your tracker instance (e.g., `https://github.com`)
3. **Project identifier** — Your project key or repository path (e.g., `my-org/my-repo`)
4. **Bug query** — The query to find open bugs in your tracker
5. **Source control** — Remote repository, base branch, and branch naming pattern
6. **Build and test commands** — The commands to build and test your project
7. **PR configuration** — Labels and description template for pull requests

The wizard generates an `## Automation Config` block with all required sections. It will offer to add this block to your project's CLAUDE.md. If your project does not have a CLAUDE.md yet, the wizard creates one.

Here is a minimal example of what the generated config looks like:

```markdown
## Automation Config

### Issue Tracker

| Key | Value |
|-----|-------|
| Type | `github` |
| Instance | `https://github.com` |
| Project | `my-org/my-repo` |
| Bug query | `is:issue is:open label:bug` |
| State transitions | `In Progress → open, For Review → open, Blocked → open label:blocked, Done → closed` |
| On start set | `In Progress` |

### Source Control

| Key | Value |
|-----|-------|
| Remote | `my-org/my-repo` |
| Base branch | `main` |
| Branch naming | `fix/{issue-id}-{description}` |

### PR Rules

| Key | Value |
|-----|-------|
| Labels | `bug, automated` |

### PR Description Template

## Summary
{summary}

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
```

For the complete list of configuration options (including optional sections like Retry Limits, Hooks, and Pipeline Profiles), see [Automation Config Reference](reference/automation-config.md).

## Step 2b: Configure Developer Environment

After setting up Automation Config, configure MCP servers and tool permissions:

```
/agent-flow:setup-mcp
```

The setup-mcp wizard will:

1. **Detect your tracker and source control** from Automation Config
2. **Guide token setup** — which tokens you need and where to get them
3. **Generate `.mcp.json`** — MCP server configuration for your tracker and source control
4. **Configure permissions** — tool auto-approval in `.claude/settings.json` to avoid repeated prompts

You can re-run `/agent-flow:setup-mcp --update` anytime to update your setup. For manual MCP configuration, see [MCP Configuration Guide](guides/mcp-configuration.md).

## Step 3: Validate the Setup

Run the setup validator to confirm everything is configured correctly:

```
/agent-flow:check-setup
```

The validator checks five categories:

1. **Automation Config** — All required sections and keys are present, no placeholder values, table format is correct
2. **MCP Servers** — An MCP server matching your tracker type is available
3. **Connectivity** — The MCP server can reach your issue tracker and source control
4. **Build & Test** — Your build and test commands execute successfully
5. **Plugin Composability** — No command name conflicts with other installed plugins

A successful report looks like this:

```
## Setup Validation Report

[PASS] Automation Config — All required sections present, all keys valid
[PASS] MCP Servers — github MCP server found and responding
[PASS] Connectivity — Issue tracker reachable, source control reachable
[PASS] Build & Test — Build: OK, Test: OK (14/14 pass)
[PASS] Plugin Composability — No command name conflicts detected

Result: All checks passed. Ready to use agent-flow.
```

If any check fails, the report includes specific guidance on what to fix. Use `--skip-build` if your build requires a specific environment that is not available in your current session:

```
/agent-flow:check-setup --skip-build
```

See [Troubleshooting Guide](guides/troubleshooting.md) for solutions to common check-setup failures.

## Step 4: Fix Your First Bug

Choose an open bug from your tracker and run the fix-bugs command:

```
/agent-flow:fix-bugs PROJ-42
```

Replace `PROJ-42` with your actual issue ID. The pipeline progresses through these stages:

1. **Triage** — The analyst (--phase triage) reads the bug report, checks for duplicates, and produces a structured analysis. If the bug is unclear or a duplicate, it blocks early.

2. **Code Analysis** — The analyst (--phase impact) maps the impact zone: root cause location, affected files (max 5), callers at risk, test coverage, and risk level.

3. **Fix** — The fixer agent implements the fix (diff limited to 100 lines). It runs the build command to verify the fix compiles.

4. **Review** — The reviewer agent checks the fix for correctness, security issues, and code quality. If it requests changes, the fixer iterates (up to 5 iterations by default).

5. **Test** — The test-engineer writes new tests covering the fix and runs the full test suite.

6. **Result** — The pipeline presents the result and asks if you want to publish. If you confirm, the publisher creates a PR and updates the issue tracker state.

For a safe preview without any side effects, use the `--dry-run` flag:

```
/agent-flow:fix-bugs PROJ-42 --dry-run
```

Dry-run mode runs only the triage and code analysis stages, then produces a report with severity, affected files, risk level, and estimated complexity. No git changes, no issue tracker updates.

## Step 5: Implement Your First Feature

agent-flow also supports feature implementation. Choose an open feature request and run:

```
/agent-flow:implement-feature PROJ-50
```

The feature pipeline differs from bug-fix in two key ways:

1. **Spec Analysis** instead of triage — The spec-analyst extracts acceptance criteria, scope boundaries, and dependencies from the feature request.

2. **Architecture Design** — The architect designs the technical solution and optionally decomposes it into subtasks. For features that affect multiple files or require a specific implementation order, the architect produces a task tree with dependencies.

If the feature is decomposed into subtasks, you will see the plan and be asked to confirm before execution starts. Each subtask then goes through the full fix/review/test cycle independently.

For more details on the feature pipeline, including decomposition settings and subtask execution, see [Pipeline Reference](reference/pipelines.md).

## Next Steps

You now have a working agent-flow setup. Here are the recommended next steps:

- **[Architecture](architecture.md)** — Understand the design philosophy, model selection rationale, and how skills and agents interact.

- **[Skills Reference](reference/skills.md)** — Explore all **17** skills with syntax, flags, and usage examples. Key skills to try next:
  - `/agent-flow:fix-bugs 3` — Fix multiple bugs in batch
  - `/agent-flow:prioritize` — AI-powered backlog prioritization
  - `/agent-flow:metrics` — Visual overview of pipeline activity

- **[Custom Agents](guides/custom-agents.md)** — Extend the pipeline with your own agents for security scanning, compliance checks, or documentation generation.

- **[Troubleshooting](guides/troubleshooting.md)** — Solutions for common issues with installation, configuration, and pipeline execution.

- **[Automation Config Reference](reference/automation-config.md)** — Fine-tune your setup with optional sections like Retry Limits, Hooks, Worktrees, Pipeline Profiles, and E2E Testing.
