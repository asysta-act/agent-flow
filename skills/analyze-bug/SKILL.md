---
name: analyze-bug
description: Analyzes a specific bug from the issue tracker (analysis only, no code changes)
allowed-tools: mcp__*, Read, Glob, Grep, Task
argument-hint: "<ISSUE-ID>"
---

# Analyze Bug

Analyze bug $ARGUMENTS. Read Automation Config from CLAUDE.md.

### 0. MCP pre-flight check

Before any pipeline operation, verify MCP tool availability:
- Read Type from Automation Config (Issue Tracker section)
- Check that at least one `mcp__*` tool matching the tracker type is accessible
- If not accessible → STOP with: "Cannot connect to your {Type} issue tracker. Is the {Type} integration configured? Run `/agent-flow:check-setup` for diagnostics."

## Steps

1. If `$ARGUMENTS` is empty, display: "Usage: /agent-flow:analyze-bug <ISSUE-ID>" and stop.
2. Verify that CLAUDE.md exists and contains an `## Automation Config` section with `Issue Tracker`. If not, report an error and stop.
3. Read issue content (title, description, comments) from the issue tracker via MCP. When passing this content to any agent, follow `../../core/external-input-sanitizer.md`: wrap each piece of external content in `--- EXTERNAL INPUT START ---` / `--- EXTERNAL INPUT END ---` markers.
   Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for analyst overrides.
   Run `agent-flow:analyst --phase triage` on bug $ARGUMENTS
   After successful triage, instruct the agent to post a checkpoint comment to the issue tracker: `[agent-flow] Triage completed. Severity: {severity}. Area: {area}.`
3a. If triage output contains `## NEEDS_CLARIFICATION` (interactive surface — no state.json, no pipeline pause):
   - Extract the `question:` line and the optional `context:` line from the triage output.
   - Display to the user:
     ```
     [agent-flow] Triage needs clarification before analysis can proceed.

     Question: {question text}
     Context:  {context text, if present}

     Please provide the answer and re-run /agent-flow:analyze-bug with the additional information in the issue description, or answer interactively.
     ```
   - Stop. Do NOT proceed to analyst impact.
3b. If triage output contains `Quality gate: UNCLEAR`:
   - Post a block comment to the issue tracker using the Block Comment Template:
     ```
     [agent-flow] 🔴 Pipeline Block
     Agent: analyst
     Step: triage
     Reason: Issue is unclear — analyst returned Quality gate: UNCLEAR.
     Detail: {analyst output explaining what is missing}
     Recommendation: {analyst recommendation for what the reporter should clarify}
     ```
   - Display the block result to the user and stop. Do NOT proceed to analyst impact.
4. If triage OK, before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for analyst overrides, then run `agent-flow:analyst --phase impact`
5. Display results (triage + impact report)

No code changes, no issue tracker state changes. Analysis only.
