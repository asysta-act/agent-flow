# Dispatch Enforcement Guide

<!-- check-tags: what it does:validates|audits|tracks|dispatch 3-layer|three.layer|Layer 1|Layer 2 installation|install troubleshoot|debug|diagnose advisory|exit 0|non-blocking Autopilot limitation|limitation Autopilot -->

**Component:** `hooks/validate-dispatch.sh`
**Type:** Operator opt-in (NOT auto-installed)

---

## What it does

The dispatch enforcement hook validates that each agent-flow pipeline stage
populated a `dispatched_at` timestamp in `state.json` before handing off to
its subagent via the Task tool. It audits whether the 3-layer dispatch enforcement
architecture (Layer 1: imperative, Layer 2: hook, Layer 3: scenario gate) is
working end-to-end.

Concretely, the hook:

1. Fires on every PostToolUse event (after any tool completes).
2. Locates the current pipeline's `state.json` under `.agent-flow/`.
3. Checks each stage in the hardcoded `STAGES` whitelist
   (`triage`, `code_analysis`, `reproduce_browser`, `fixer_reviewer`,
   `smoke_check`, `test`, `e2e_test`, `browser_verification`,
   `acceptance_gate`, `publisher`) for presence of `dispatched_at`.
4. Appends one audit-log line per stage to `.agent-flow/dispatch-audit.log`.
5. Always exits 0 — **advisory-only, never blocking**.

The hook is intentionally non-blocking. PostToolUse hooks cannot undo a tool
that already executed, and exit 2 has no special semantics here (see
`docs/reference/hooks.md`). Blocking mode (exit 2 enforcement) is deferred to
a future release.

---

## Installation

The hook is **not auto-installed**. It is shipped in the plugin at
`hooks/validate-dispatch.sh`. Operators install it manually by adding an entry
to `~/.claude/settings.json`.

### Minimal stanza

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

Replace `/path/to/agent-flow/` with the absolute path to your plugin
installation directory. On most systems this is something like:
`~/.claude/plugins/agent-flow/hooks/validate-dispatch.sh`.

### Recommended scope

Install in `~/.claude/settings.json` (user-global) so the hook fires for
every Claude Code session including autopilot child subprocess invocations.
If you only want it for a single project, use `.claude/settings.json` in that
project root.

---

## Expected output

A passing audit run produces lines like:

```
2026-04-25T14:32:07Z triage OK
2026-04-25T14:32:07Z code_analysis OK
2026-04-25T14:32:07Z reproduce_browser OK
2026-04-25T14:32:07Z fixer_reviewer OK
2026-04-25T14:32:07Z smoke_check OK
2026-04-25T14:32:07Z test OK
2026-04-25T14:32:07Z e2e_test OK
2026-04-25T14:32:07Z browser_verification OK
2026-04-25T14:32:07Z acceptance_gate OK
2026-04-25T14:32:07Z publisher OK
```

A `MISSING` line means the stage completed without writing `dispatched_at` to
`state.json` — typically indicating a skill was run with an older agent-flow
version, or the dispatching step was skipped.

```
2026-04-25T14:32:07Z code_analysis MISSING
```

`MISSING` is advisory — pipelines continue normally regardless.

---

## Troubleshooting / diagnosis

**Hook never fires:**
- Verify the entry is in `~/.claude/settings.json` (not a project-level file
  that is overriding user-global config).
- Check `disableAllHooks` is not `true` in any settings file.
- Run `/agent-flow:check-setup` — it reports whether the hook file and
  settings.json entry are detected.

**`state.json` not found:**
- The hook exits silently if no `.agent-flow/*/state.json` is present.
  This is normal for non-pipeline sessions. Check that you are running from
  the project root (the same directory used during pipeline execution).

**Log file not created:**
- The hook creates `.agent-flow/dispatch-audit.log` automatically on first
  write. If the directory doesn't exist, the hook exits 0 without logging
  (advisory failure semantics).

---

## Known limitation: Autopilot subprocess dispatch audit gap

When autopilot dispatches pipeline subprocesses via
`claude -p "Run /agent-flow:fix-bugs ..." --dangerously-skip-permissions`,
PostToolUse hooks DO fire inside those subprocesses. However, each subprocess
writes to its own session's audit log, and **cross-run audit aggregation** (merging
per-subprocess logs into a single autopilot-session report) is on the roadmap
as "Autopilot dispatch audit parity".

The current advisory behavior is:
- Each autopilot-spawned subprocess logs independently.
- The `bypassPermissions` mode is detected and noted in the audit log.
- No cross-run summary is produced automatically.

---

## Schema reference

See `docs/reference/hooks.md` for the full PostToolUse JSON input schema,
exit code semantics, and `dispatched_at` field specification.
