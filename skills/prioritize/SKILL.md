---
name: prioritize
description: Analyzes backlog and suggests fix order using AI prioritization
allowed-tools: mcp__*, Read, Glob, Grep, Task
argument-hint: "[--limit <N>] [--output <path>]"
---

# Prioritize

Input: `$ARGUMENTS` = optional `--limit <N>` (default: 20), `--output <path>` (default: stdout)

## Configuration

Read Automation Config from CLAUDE.md section `## Automation Config`:
- Issue Tracker: Type, Instance, Project, Bug query
- Optional: Feature Workflow → Feature query
- Optional: Metrics → for historical data

### 0. MCP pre-flight check

Before any pipeline operation, verify MCP tool availability:
- Read Type from Automation Config (Issue Tracker section)
- Check that at least one `mcp__*` tool matching the tracker type is accessible
- If not accessible → STOP with: "Cannot connect to your {Type} issue tracker. Is the {Type} integration configured? Run `/agent-flow:check-setup` for diagnostics."

## Orchestration

### 1. Fetch issues

Via MCP server (per Issue Tracker → Type), fetch open issues (Bug query + Feature query). Limit = `--limit` flag.

### 2. Enrich with history

If a metrics report exists (`./reports/metrics.md` or Metrics → Output from config), read per-area failure patterns and success rates.

### 3. Run priority-engine

Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for priority-engine overrides.
You MUST invoke `Task(subagent_type='agent-flow:priority-engine', model='opus')`. DO NOT inline-execute.
Context: list of issues + historical data (if available).

If priority-engine fails or returns an error, display: "Prioritization failed: {reason}" and stop.

### 4. Output

Display the agent's result. If `--output` is specified → write to file.

## Rules

- Read-only — no changes to the issue tracker
- If no issues found → "No open issues found matching the query"
- Data is read via MCP servers
