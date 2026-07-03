# Dispatch Enforcement Guide

<!-- check-tags: what it does:validates|audits|tracks|dispatch 3-layer|three.layer|Layer 1|Layer 2 installation|install troubleshoot|debug|diagnose advisory|exit 0|non-blocking Autopilot limitation|limitation Autopilot rollback|toggle|STRICT_DISPATCH_OFF -->

**Components:** `hooks/validate-dispatch-pre.sh` (PreToolUse `Task` gate),
`hooks/validate-dispatch.sh` (PostToolUse audit)
**Type:** Operator opt-in (NOT auto-installed)

---

## Two hooks: a blocking gate and an advisory audit (finding A8)

As of v2.0.0 dispatch enforcement is **two** hooks with clearly separated roles:

- **PreToolUse `Task` gate** (`hooks/validate-dispatch-pre.sh`) — the only
  component that holds the per-run key and the only one that can **block** a
  dispatch. It verifies the in-flight `Task` payload against the orchestrator's
  CLAIM, signs an HMAC-SHA256 keyed tag into the gate-owned ledger, and on a
  verified match ALLOWs. On a mismatch it emits a deny envelope and `exit 2`,
  which blocks the dispatch **before the tool runs** (Claude Code ≥ 2.1.90).
- **PostToolUse audit** (`hooks/validate-dispatch.sh`) — a second layer that
  re-verifies the gate's ledger signature and records a verdict. It runs **after**
  the tool, so it **cannot block** (finding A8); its `exit 2` under strict mode is
  a forensic signal, not a rollback. "Fails the dispatch" language refers only to
  the PreToolUse gate.

Both hooks are pure Python (the keyed compute/verify lives in
`hooks/lib/witness_core.py`; the bash `core/lib/stage-invariant.sh` keyed path is
demoted to a parity-pinned self-test and is **not** sourced by either hook).

---

## What the PostToolUse audit does

The PostToolUse audit validates that each agent-flow pipeline stage
populated a `dispatched_at` timestamp in `state.json` before handing off to
its subagent via the Task tool, and re-verifies the gate signature.

Concretely, the audit:

1. Fires on every PostToolUse event (after any tool completes).
2. Locates the current pipeline's `state.json` under `.agent-flow/`.
3. Runs two audit passes over the hardcoded `STAGES` whitelist —
   `triage`, `code_analysis`, `reproduce_browser`, `fixer_reviewer`,
   `smoke_check`, `test`, `e2e_test`, `browser_verification`,
   `acceptance_gate`, `publisher` (10 stages):
   - **Presence audit** — checks each stage for a `dispatched_at` timestamp and
     emits one `OK` / `MISSING` line per stage.
   - **Dispatch-witness audit** — pure Python (`hooks/lib/witness_core.py`),
     dual-mode by **key-file presence**. On a keyed run (`0600 dispatch.key`
     present, `schema_version "2.0"`) it re-verifies every line of the gate-owned
     ledger `.agent-flow/{RUN-ID}/dispatch-ledger.jsonl` — recomputing the
     HMAC-SHA256 tag over the per-field sub-hashed canonical preimage and emitting
     `WITNESS_OK` / `WITNESS_MISSING` / `WITNESS_MISMATCH` / `WITNESS_UNVERIFIABLE`
     per stage; a key-present claimed stage with no matching ledger line, or a key
     lost on a progressed run, is `WITNESS_UNVERIFIABLE`. On a legacy keyless v1.0
     run it falls back to the V1 sha256 recompute + V2 overlay-presence dual-mode
     (never a false `WITNESS_MISMATCH`).
4. Appends those audit lines to `.agent-flow/dispatch-audit.log` (a **best-effort
   append-only audit log** — `<ISO-ts> <stage> <verdict>` lines only; no key, no
   tag, no preimage).
5. Exit code: the **presence audit is always advisory (exit 0)**. The
   **witness audit is strict by default** — it exits 2 when any stage produces
   `WITNESS_MISMATCH` or `WITNESS_UNVERIFIABLE`, unless advisory
   (`AGENT_FLOW_STRICT_DISPATCH=0` or a `STRICT_DISPATCH_OFF` flag file).

Even under strict mode the audit's exit 2 is non-blocking in practice: PostToolUse
hooks fire *after* the tool has already executed, so exit 2 cannot undo it (finding
A8; see `docs/reference/hooks.md` → Exit code semantics). The audit surfaces the
mismatch as a forensic signal in the transcript; the real block is the PreToolUse
gate. `WITNESS_MISSING` is never strict-fatal — legitimately skipped stages and
stages with absent witness inputs produce `MISSING`, not `MISMATCH`.

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
installation directory.

> **⚠️ The plugin path is version-pinned — do not hardcode it blindly.**
> Installed plugins live under a version-stamped cache directory, e.g.:
>
> ```
> ~/.claude/plugins/cache/agent-flow/agent-flow/<version>/hooks/validate-dispatch.sh
> ```
>
> The `<version>` segment changes on every plugin upgrade, so an absolute path
> pinned to one version **silently stops resolving** after an update — the file
> at the old path no longer exists.
>
> **Find the current path** before pasting it into `settings.json`:
>
> ```bash
> # list every installed version's hook…
> ls -d ~/.claude/plugins/cache/agent-flow/agent-flow/*/hooks/validate-dispatch.sh
> # …or resolve the newest one:
> ls -d ~/.claude/plugins/cache/agent-flow/agent-flow/*/hooks/validate-dispatch.sh | sort | tail -1
> ```
>
> **A wrong path produces no error signal.** The hook fails open: PostToolUse
> hooks are non-blocking, so Claude Code treats an unresolvable hook command as
> a silent no-op — the audit never runs and `.agent-flow/dispatch-audit.log` is
> never written, with nothing reported. Re-check the path after every plugin
> upgrade, and run `/agent-flow:check-setup` to confirm the wiring is still
> detected.

### Recommended scope

Install in `~/.claude/settings.json` (user-global) so the hook fires for
every Claude Code session including autopilot child subprocess invocations.

Project `.claude/settings.json` and project-local
`.claude/settings.local.json` are equally valid scopes. Claude Code merges a
settings tree across scopes, and **hooks COMBINE** — a `PreToolUse`/`PostToolUse`
hook registered in any scope fires; none overrides another. (Only
`"disableAllHooks": true`, set in any scope, turns hooks off.) So you can wire the
gate user-global, per-project, or project-local — or in several scopes at once
without conflict. The user-global scope is still recommended because it is the
only one that reaches autopilot child subprocesses.
`/agent-flow:check-setup` detects the hook at any of these scopes.

---

## Expected output

Each invocation appends two groups of lines. The **presence audit** emits one
`OK` / `MISSING` line per stage:

```
2026-04-25T14:32:07Z triage OK
2026-04-25T14:32:07Z code_analysis OK
2026-04-25T14:32:07Z fixer_reviewer OK
2026-04-25T14:32:07Z test OK
2026-04-25T14:32:07Z publisher OK
```

A `MISSING` line means the stage completed without writing `dispatched_at` to
`state.json` — typically indicating a skill was run with an older agent-flow
version, or the dispatching step was skipped.

```
2026-04-25T14:32:07Z code_analysis MISSING
```

`MISSING` is advisory — pipelines continue normally regardless.

The **witness audit** then emits one `WITNESS_*` line per stage:

```
2026-04-25T14:32:07Z triage WITNESS_OK
2026-04-25T14:32:07Z code_analysis WITNESS_MISSING
2026-04-25T14:32:07Z fixer_reviewer WITNESS_MISMATCH
```

- `WITNESS_OK` — V1 recompute matches the stored `dispatch_witness` **and** V2
  finds no unapplied overlay.
- `WITNESS_MISSING` — a required witness input is absent/null, the stage was
  legitimately skipped (`status: "skipped"`), or no sha256 tool is available.
  Never strict-fatal.
- `WITNESS_MISMATCH` — V1 recompute ≠ stored witness, the stored witness is
  malformed, or V2 detects an available `<override>/<agent>.toml` overlay that
  the stage did not record (`overlay_source != toml`). Under strict mode
  (the default) a single `WITNESS_MISMATCH` makes the hook exit 2.

When `bypassPermissions` mode is detected (autopilot child subprocesses), an
extra informational line is also appended:

```
2026-04-25T14:32:07Z [INFO] bypassPermissions mode detected -- audit proceeds normally
```

---

## Environment variables

Both hooks read these (clean-break `AGENT_FLOW_` prefix):

| Variable | Effect |
|----------|--------|
| `AGENT_FLOW_STRICT_DISPATCH` | Strict (gate denies; audit exits 2 on `WITNESS_MISMATCH`/`WITNESS_UNVERIFIABLE`) unless set to `0` (advisory). The presence audit is always advisory regardless. |
| `AGENT_FLOW_DISPATCH_KEY_FILE` | Override the per-run key-file PATH (never the value; default: `dispatch.key` sibling of `state.json`). |
| `AGENT_FLOW_LEDGER` | Override the gate-owned ledger path (default `.agent-flow/{RUN-ID}/dispatch-ledger.jsonl`). |
| `AGENT_FLOW_MARKER_TTL` | Gate marker freshness window in seconds (default 120). |
| `AGENT_FLOW_AUDIT_LOG` | Override the audit-log path (default `.agent-flow/dispatch-audit.log`). |
| `AGENT_FLOW_STATE_JSON` | Override the `state.json` path (audit only; default: newest `.agent-flow/*/state.json`). |
| `AGENT_FLOW_OVERRIDE_PATH` | Overlay override dir of last resort; the gate/audit prefer the per-stage `override_path` persisted in `state.json` (the Claude-Code-spawned hook never inherits the skill's env). |

---

## Rollback runbook (advisory toggle)

Dispatch enforcement is **strict by default**. Because the gate is spawned by
Claude Code and inherits no skill shell env, a bare `export
AGENT_FLOW_STRICT_DISPATCH=0` in a project file the *skills* source does NOT reach
the hook. Use these levers instead:

**Lever 1 — advisory mode (downgrade DENY → allow, both hooks keep recording):**

1. **`env` block in `.claude/settings.json`** (the persistent lever) — Claude Code
   injects it into hook process env at session start:
   ```json
   { "env": { "AGENT_FLOW_STRICT_DISPATCH": "0" } }
   ```
2. **Top-level flag file** `.agent-flow/STRICT_DISPATCH_OFF` (the reliable in-run
   lever) — checked by the gate **first**, before any marker/run resolution, so it
   works even when marker/run resolution is the failing component:
   ```bash
   touch .agent-flow/STRICT_DISPATCH_OFF
   ```
   A narrower per-run flag `.agent-flow/{RUN-ID}/STRICT_DISPATCH_OFF` scopes the
   downgrade to one run (resolved from the marker run dir).

**Lever 2 — hard fallback (disable the gate entirely):** remove the PreToolUse
`Task` matcher entry from `settings.json`. With the matcher gone the gate never
fires and no dispatch is blocked.

---

## Troubleshooting / diagnosis

**Hook never fires:**
- Verify the entry exists in at least one settings scope. It may live in any of
  `~/.claude/settings.json` (user-global), project `.claude/settings.json`, or
  project-local `.claude/settings.local.json` — these scopes COMBINE, so a hook
  in any one of them fires and none overrides another. There is no need for the
  entry to be in the user-global file specifically.
- Check `disableAllHooks` is not `true` in any settings scope — that is the only
  setting that turns hooks off.
- Run `/agent-flow:check-setup` — it scans all three scopes (user + project +
  project-local) and reports, per scope, whether the PreToolUse `Task` gate and
  the PostToolUse audit are detected.

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
