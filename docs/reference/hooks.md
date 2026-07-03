# Hooks Reference

<!-- check-tags: extensib|extend|future -->

**Component:** `hooks/validate-dispatch.sh`

---

## Overview

agent-flow ships two dispatch-witness hooks:

- **`hooks/validate-dispatch-pre.sh`** — a **PreToolUse `Task` gate** (the
  gate-as-signer). It is the sole holder of the per-run key and the only
  component that can **block** a dispatch (deny-JSON + `exit 2`, which blocks
  `Task` on Claude Code ≥ 2.1.90). It resolves the in-flight dispatch from the
  top-level marker `.agent-flow/pending-dispatch.json`, applies
  match-or-pass-through, signs the HMAC witness into the gate-owned ledger, and
  ALLOWs — or DENYs.
- **`hooks/validate-dispatch.sh`** — a **PostToolUse audit** (second layer). It
  re-verifies the gate signature but **cannot block** (it runs after the tool).

See `docs/guides/dispatch-enforcement.md` for installation and operator guidance.
A one-time `Task` `tool_input`-shape probe (`hooks/probe-task-shape.sh`) records
the local build's `Task` payload shape and never blocks.

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

**Advisory vs strict:** In `hooks/validate-dispatch.sh` the `dispatched_at`
**presence audit** is always advisory (exit 0). The **dispatch-witness audit**
is strict by default — it exits 2 when any stage produces `WITNESS_MISMATCH`
during the pass, unless `AGENT_FLOW_STRICT_DISPATCH=0` makes it advisory too
(`WITNESS_MISSING` is never exit-2-worthy). Because this is a PostToolUse hook,
even the strict exit 2 cannot block the tool that already ran (see the table
above) — it surfaces the mismatch as a transcript signal rather than rolling
anything back. See `docs/guides/dispatch-enforcement.md` for the audit passes
and the `AGENT_FLOW_*` environment variables.

---

## STAGES whitelist

The hook checks exactly these stages (hardcoded, never discovered dynamically):

```
triage  code_analysis  reproduce_browser  fixer_reviewer  smoke_check
test  e2e_test  browser_verification  acceptance_gate  publisher
```

This 10-stage list is the canonical `STAGES` array in
`hooks/validate-dispatch.sh` and is kept in sync with the skill
`<stage_allowlist>` blocks and `state/schema.md` → "Applicable stages" by the
`tests/scenarios/stage-list-consistency.sh` parity check.

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

Each stage audit line has exactly three space-separated fields:

```
<ISO-8601-timestamp> <stage> <verdict>
```

`<verdict>` is one of the **presence-audit** verdicts (`OK`, `MISSING`) or the
**witness-audit** verdicts (`WITNESS_OK`, `WITNESS_MISSING`, `WITNESS_MISMATCH`).

Example:
```
2026-04-25T14:32:07Z triage OK
2026-04-25T14:32:07Z code_analysis OK
2026-04-25T14:32:07Z fixer_reviewer MISSING
2026-04-25T14:32:07Z test OK
2026-04-25T14:32:07Z publisher OK
2026-04-25T14:32:07Z triage WITNESS_OK
2026-04-25T14:32:07Z fixer_reviewer WITNESS_MISMATCH
```

`OK` — `dispatched_at` was present in the stage object.
`MISSING` — `dispatched_at` absent (advisory; pipeline continues).
`WITNESS_OK` / `WITNESS_MISSING` / `WITNESS_MISMATCH` — dispatch-witness audit
result (see `docs/guides/dispatch-enforcement.md` for the V1/V2 semantics and
the strict-by-default exit-2 gate).

In `bypassPermissions` mode the hook also appends a non-stage informational line
that does **not** follow the three-field shape:

```
<ISO-8601-timestamp> [INFO] bypassPermissions mode detected -- audit proceeds normally
```

Future log readers parse stage lines via: `awk '{print $1, $2, $3}'`. This
three-field format is a stable contract for stage lines — any future JSON
promotion will be an additive adapter, not a format replacement.

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

### PreToolUse `Task` gate registration

Register the blocking gate against the `Task` tool (this is the matcher that
makes the witness a *true* pre-dispatch block). Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/agent-flow/hooks/validate-dispatch-pre.sh"
          }
        ]
      }
    ]
  },
  "env": {
    "AGENT_FLOW_STRICT_DISPATCH": "1"
  }
}
```

Notes:
- The `matcher` MUST be the exact string `"Task"` — the gate fires only on
  `Task` dispatches and **passes through** (allows, never signs) any `Task` it
  cannot match to a fresh agent-flow marker, so parallel/non-agent-flow `Task`
  usage is never blocked.
- The `env` block is how the rollback toggle **reaches** the
  Claude-Code-spawned hook: set `AGENT_FLOW_STRICT_DISPATCH` to `"0"` here to run
  advisory (Lever 1). An in-run kill switch is the top-level flag file
  `.agent-flow/STRICT_DISPATCH_OFF` (checked before any marker/run resolution).
  Removing this matcher entirely is the hard fallback (Lever 2).
- Requires **Claude Code ≥ 2.1.90** (issue #26923: a `Task` `exit 2` was a no-op
  before v2.1.90). `/check-setup` and the first-keyed-run deny-canary assert this.

**Scope note (applies to both stanzas above).** Either hook can be registered at
user scope (`~/.claude/settings.json`), project scope (`.claude/settings.json`),
or project-local scope (`.claude/settings.local.json`). Claude Code merges a
settings tree across scopes, and **hooks COMBINE** — a hook present in any scope
fires; none overrides another. Only `"disableAllHooks": true` (set in any scope)
disables them. `/agent-flow:check-setup` scans all three scopes and detects both
the PreToolUse `Task` gate and the PostToolUse audit, reporting where each is
wired.

The optional one-time shape probe is registered the same way (PreToolUse or
PostToolUse, `matcher: "Task"`, command `hooks/probe-task-shape.sh`); it never
blocks.

---

## Extensibility

agent-flow ships one hook. Future versions may extend this directory with
additional hook scripts (e.g., `hooks/audit-tool-use.sh`, `hooks/rate-limit.sh`).
Each hook will be independently opt-in with its own installation stanza.

Roadmap: cross-run audit aggregation for autopilot dispatch parity
(see `docs/guides/dispatch-enforcement.md` "Autopilot limitation" section).
