# Hooks Reference

<!-- check-tags: extensib|extend|future -->

**Component:** `hooks/validate-dispatch.sh`

---

## Overview

agent-flow ships one PostToolUse hook: `hooks/validate-dispatch.sh`.
It performs an advisory dispatch-enforcement audit. See
`docs/guides/dispatch-enforcement.md` for installation and operator guidance.

---

## Hook trigger conditions

PostToolUse fires immediately after a tool completes successfully. It covers
all tool types: built-in (`Bash`, `Edit`, `Write`, `Read`, `Glob`, `Grep`),
agent tools, and MCP tools.

The `matcher` field controls which tools trigger the hook:
- Omitted or `"*"` — fires on all PostToolUse events
- Exact string or `|`-separated list — e.g. `"Bash"`, `"Write|Edit"`

**Key difference from PreToolUse:** PostToolUse cannot block tool execution
because the tool has already completed. Exit code 2 has NO blocking effect
here (see Exit Code Semantics below).

---

## JSON input schema (stdin)

The hook receives one line of JSON on stdin:

```json
{
  "session_id":      "string — unique Claude Code session identifier",
  "transcript_path": "string — absolute path to JSONL transcript file",
  "cwd":             "string — working directory at invocation time",
  "permission_mode": "string — default | plan | acceptEdits | auto | dontAsk | bypassPermissions",
  "hook_event_name": "string — literal 'PostToolUse'",
  "tool_name":       "string — e.g. 'Bash', 'Write', 'mcp__memory__create_entities'",
  "tool_input":      "object — varies by tool",
  "tool_response":   "object — varies by tool",
  "tool_use_id":     "string — Anthropic tool call ID",
  "agent_id":        "string (optional) — only in subagent context",
  "agent_type":      "string (optional) — e.g. 'Explore' or custom agent name"
}
```

The `permission_mode` field is `"bypassPermissions"` when autopilot dispatches
child subprocesses with `--dangerously-skip-permissions`. The audit hook
detects this and notes it in the audit log.

---

## Exit code semantics

| Exit Code | Behavior |
|-----------|----------|
| **0** | Success. Execution continues normally. |
| **1** | Non-blocking error. Stderr shown in transcript. Execution continues. |
| **2** | Non-blocking error. **CANNOT block** — tool already executed. Same handling as exit 1. |
| **Other** | Non-blocking error. Same handling as exit 1. |

**Advisory mode:** `hooks/validate-dispatch.sh` always exits 0.
PostToolUse hooks cannot enforce blocking regardless. Future versions
may graduate to exit 2 to signal advisory violations back to Claude via
stdout decision control output, but this remains non-blocking at the tool level.

---

## STAGES whitelist

The hook checks exactly these stages (hardcoded, never discovered dynamically):

```
triage  code_analysis  reproduce_browser  fixer_reviewer  smoke_check
test  e2e_test  browser_verification  acceptance_gate  publisher
```

---

## `dispatched_at` field

An optional additive field on every stage object in
`state.json`. See `state/schema.md` "Stage metadata (additive)"
for the full field specification.

Pipeline orchestrators write `dispatched_at` immediately before Task tool
dispatch for each stage. Its presence indicates the stage went through the
current dispatch path.

---

## Audit log format

File: `.agent-flow/dispatch-audit.log` (append-only, plain text)

Each line has exactly three space-separated fields:

```
<ISO-8601-timestamp> <stage> <OK|MISSING>
```

Example:
```
2026-04-25T14:32:07Z triage OK
2026-04-25T14:32:07Z code_analysis OK
2026-04-25T14:32:07Z reproduce_browser OK
2026-04-25T14:32:07Z fixer_reviewer MISSING
2026-04-25T14:32:07Z smoke_check OK
2026-04-25T14:32:07Z test OK
2026-04-25T14:32:07Z e2e_test OK
2026-04-25T14:32:07Z browser_verification OK
2026-04-25T14:32:07Z acceptance_gate OK
2026-04-25T14:32:07Z publisher OK
```

`OK` — `dispatched_at` was present in the stage object.
`MISSING` — `dispatched_at` absent (advisory; pipeline continues).

Future log readers parse via: `awk '{print $1, $2, $3}'`. This three-field
format is a stable contract — any future JSON promotion will be an
additive adapter, not a format replacement.

---

## Installation stanza

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/agent-flow/hooks/validate-dispatch.sh"
          }
        ]
      }
    ]
  }
}
```

See `docs/guides/dispatch-enforcement.md` for full installation instructions.

---

## Extensibility

agent-flow ships one hook. Future versions may extend this directory with
additional hook scripts (e.g., `hooks/audit-tool-use.sh`, `hooks/rate-limit.sh`).
Each hook will be independently opt-in with its own installation stanza.

Roadmap: cross-run audit aggregation for autopilot dispatch parity
(see `docs/guides/dispatch-enforcement.md` "Autopilot limitation" section).
