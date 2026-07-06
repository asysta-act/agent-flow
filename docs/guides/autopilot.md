# Autopilot — Operator Guide

Autopilot is the headless dispatcher skill for agent-flow. It reads your tracker queries from `## Automation Config`, classifies open issues into bugs and features, and sequentially dispatches `fix-bugs` or `implement-feature` per issue — all without human interaction.

It is designed for unattended operation: cron jobs, CI pipelines, nightly batch runs. Autopilot never modifies code or writes PRs itself; it delegates all work to child skills and surfaces aggregate results.

Source of truth for full behavior: [`skills/autopilot/SKILL.md`](../../skills/autopilot/SKILL.md). Full key reference: [`docs/reference/config.md`](../reference/config.md) — Autopilot section.

---

## What is Autopilot

Autopilot acts as a process-local, cron-safe dispatcher. On each invocation it:

1. Validates your `## Automation Config` and pings the tracker MCP.
2. Acquires an atomic `mkdir`-based lock so concurrent runs on the same host are prevented.
3. Fetches bugs via `Bug query` and features via `Feature query` (optional).
4. Dispatches each issue sequentially to `agent-flow:fix-bugs` or `agent-flow:implement-feature`.
5. Emits a summary table (issue ID, type, outcome, duration, tokens) and releases the lock.

Child skills own all pipeline state: `state.json`, PRs, test runs, and webhook events. Autopilot itself fires no per-issue webhooks and writes no `state.json`. It is a pure dispatcher at the observability layer.

---

## Configuration

Add an `[autopilot]` section to your project's `.agent-flow/config.toml`. All 7 keys are optional — the defaults are safe for first use.

**Important:** `Bug query` and `Feature query` are NOT keys in `### Autopilot`. They live in their respective existing sections:
- `Bug query` → under `### Issue Tracker` (required existing key)
- `Feature query` → under `### Feature Workflow` (optional existing section)

```markdown
### Issue Tracker
| Bug query | State: Open and type: Bug |

### Feature Workflow
| Feature query | State: Open and type: Feature |

### Autopilot

| Key | Value |
|-----|-------|
| Max issues per run | 1 |
| Lock timeout | 120 |
| Log file | .agent-flow/autopilot.log |
| Bug limit | 0 |
| Feature limit | 0 |
| On error | skip |
| Dry run | true |
```

Key reference:

| Key | Type | Default | Semantics |
|-----|------|---------|-----------|
| `Max issues per run` | integer ≥ 1 | `1` | Total cap on issues dispatched per invocation (bugs + features combined). Default of 1 is a safety cap for first use. |
| `Lock timeout` | integer (minutes) | `120` | Age threshold after which an existing lock directory is considered stale and auto-recovered. |
| `Log file` | path | `.agent-flow/autopilot.log` | Append-only run log path. Separate from the lock directory. |
| `Bug limit` | integer ≥ 0 | `0` | Per-type cap on bug dispatches. `0` = no per-type cap (only `Max issues per run` total cap applies). |
| `Feature limit` | integer ≥ 0 | `0` | Per-type cap on feature dispatches. `0` = no per-type cap (only `Max issues per run` total cap applies). |
| `On error` | enum | `skip` | `skip` = log [WARN] and continue with next issue; `stop` = abort the whole run on the first per-issue error. |
| `Dry run` | boolean | `false` | `true` = full short-circuit (no lock, no state, no webhook, no dispatch). Safe to schedule concurrently. |

`Bug query` (under `### Issue Tracker`) is the only key that must have a value for Autopilot to run. Everything else has a working default.

---

## First Run

Follow these steps before enabling unattended cron dispatch.

### Step 1 — Verify Autopilot section is present

Run the setup check:

```bash
claude -p "Run /agent-flow:check-setup" --dangerously-skip-permissions
```

Fix any reported MCP or config issues before continuing.

### Step 2 — Dry run first

Set `Dry run: true` in your `### Autopilot` config. Then run:

```bash
claude -p "Run /agent-flow:autopilot --dry-run" --dangerously-skip-permissions
```

Expected output:

```
[DRY RUN] Autopilot dry-run mode — full short-circuit. No lock, no state, no webhook, no dispatch.
[autopilot][INFO] Dry run mode — short-circuit. No lock, no state, no webhook, no dispatch.
[autopilot][INFO] Would process: Bug query=State: Open and type: Bug, Feature query=State: Open and type: Feature, Max issues per run=1, Bug limit=0, Feature limit=0
```

Verify the queries and limits look correct. No lock directory, no `state.json`, no tracker mutations occur.

### Step 3 — Verify queries return expected issues

While still in dry-run mode, open your tracker and manually run the configured `Bug query` and `Feature query`. Confirm the returned issues are the ones you want Autopilot to work on.

### Step 4 — Enable live dispatch

Change `Dry run: false` (or remove the key entirely — the default is `false`). Run once interactively to observe the first dispatch:

```bash
claude -p "Run /agent-flow:autopilot" --dangerously-skip-permissions
```

Review the summary table at the end. Each row shows outcome (`success`, `block`, or `error`) and token usage (when available from the child skill's `state.json`).

### Step 5 — Move to cron

Once you are satisfied with live dispatch, schedule the job (see next section).

---

## Running from Cron

### Recommended crontab line

```cron
0 2 * * * cd /path/to/your/project && claude -p "Run /agent-flow:autopilot" --dangerously-skip-permissions >> /var/log/autopilot.log 2>&1 || echo "[autopilot] exit=$?" >> /var/log/autopilot.log
```

This runs Autopilot every night at 02:00, appends stdout and stderr to a log file, and records non-zero exits in the same file.

### Environment variables

`claude` must be on the cron user's `PATH`. Add an explicit `PATH` line if needed:

```cron
PATH=/usr/local/bin:/usr/bin:/bin
CLAUDE_API_KEY=<your-api-key>
0 2 * * * cd /path/to/your/project && claude -p "Run /agent-flow:autopilot" --dangerously-skip-permissions >> /var/log/autopilot.log 2>&1
```

### Capturing exit codes

Autopilot uses structured exit codes (see Error Handling section below). The `|| echo` pattern above captures non-zero exits. For production, consider:

```bash
set -o pipefail
claude -p "Run /agent-flow:autopilot" --dangerously-skip-permissions
EXIT=$?
if [ $EXIT -ne 0 ]; then
  echo "[autopilot] exit=$EXIT at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /var/log/autopilot.log
fi
```

---

## Single-Host Operation

> **Important:** Autopilot's lock is process-local — it guards only one host and one filesystem. It provides no coordination across multiple hosts running against the same tracker.

### Default recommendation: one host only

The simplest safe configuration is to run Autopilot from exactly **one cron host**. The `mkdir`-based lock prevents concurrent runs on that host; no further coordination is needed.

### If you must run from multiple hosts

When multi-host dispatch is unavoidable (e.g., different teams owning different tracker projects on separate machines), you MUST configure **disjoint queries** so each host works on a non-overlapping set of issues.

Example: two hosts, each responsible for issues assigned to a different bot user:

**Host A — `CLAUDE.md` (relevant sections):**

```markdown
### Issue Tracker
| Bug query | State: Open and type: Bug and assignee: bot-host-a |

### Feature Workflow
| Feature query | State: Open and type: Feature and assignee: bot-host-a |

### Autopilot
| Max issues per run | 10 |
```

**Host B — `CLAUDE.md` (relevant sections):**

```markdown
### Issue Tracker
| Bug query | State: Open and type: Bug and assignee: bot-host-b |

### Feature Workflow
| Feature query | State: Open and type: Feature and assignee: bot-host-b |

### Autopilot
| Max issues per run | 10 |
```

With disjoint queries, Host A and Host B never fetch the same issue. There is no double-dispatch risk.

Other disjoint axes to consider:

- By subsystem/component label: `component: payments` vs `component: auth`
- By priority tier: `priority: Critical or High` vs `priority: Normal or Low`
- By project key: `project: BILLING` vs `project: INFRA`

### Cross-host INFO line

On every successful lock acquisition, Autopilot logs:

```
[autopilot][INFO] Running on host build-server-01. If another host is also running Autopilot against the same tracker, it MUST use a disjoint bug/feature query. See docs/guides/autopilot.md#single-host-operation.
```

This line is informational. It does **not** detect cross-host contention — it aids log correlation only. The authoritative mitigation is operator-side disjoint-query configuration.

---

## Multi-Host Coordination

If you run Autopilot from multiple hosts (e.g., 2-cron split for high-volume teams), Autopilot supports **disjoint queries only** — each cron config MUST query a non-overlapping subset of issues. Example with two hosts:

- Host A `Bug query`: `priority:high state:open`
- Host B `Bug query`: `priority:medium,low state:open`

The operator is responsible for query disjointness. Two hosts running an overlapping query may both pick up the same issue, race on the same branch, and produce conflicting PRs. There is no cross-host lock to detect this.

Distributed locking (flock, external coordinator) is on the roadmap.

---

## Observability

Autopilot itself fires no webhooks. Webhook events are fired by the **child skills** (`fix-bugs`, `implement-feature`) per dispatched issue.

### Events fired per issue

| Event | When fired |
|-------|------------|
| `pipeline-started` | Immediately after `state.json` init, before the first agent dispatch |
| `step-completed` | After each pipeline stage (triage, fixer_reviewer, test, publisher, etc.) |
| `pipeline-completed` | At the terminal state write (success, blocked, or failed) |

### Payload fields

**`pipeline-started`**

```json
{
  "event": "pipeline-started",
  "run_id": "PROJ-42_20260417T143000Z",
  "issue_id": "PROJ-42",
  "pipeline": "fix-bugs",
  "timestamp": "2026-04-17T14:30:00Z"
}
```

**`step-completed`**

```json
{
  "event": "step-completed",
  "run_id": "PROJ-42_20260417T143000Z",
  "issue_id": "PROJ-42",
  "step_name": "fixer_reviewer",
  "duration": 525,
  "iteration_count": 3,
  "timestamp": "2026-04-17T14:40:00Z"
}
```

`duration` is whole seconds. `iteration_count` is 1 for non-loop stages. `step_name` uses canonical stage names (see [`docs/reference/skills.md`](../reference/skills.md)).

**`pipeline-completed`**

```json
{
  "event": "pipeline-completed",
  "run_id": "PROJ-42_20260417T143000Z",
  "issue_id": "PROJ-42",
  "status": "completed",
  "outcome": "success",
  "duration": 692,
  "pr_url": "https://gitea.example.com/owner/repo/pulls/99",
  "timestamp": "2026-04-17T14:42:00Z"
}
```

`outcome` is one of: `success`, `blocked`, `failed`. `pr_url` is `null` when no PR was created.

Configure the webhook endpoint under `### Notifications` in your `## Automation Config`:

```markdown
### Notifications

| Key | Value |
|-----|-------|
| Webhook URL | https://your-observability-host/webhook |
| On events | pipeline-started, step-completed, pipeline-completed |
```

Webhook payloads are forward-compatible — additive fields may appear in future MINOR versions. Use lenient JSON parsing (ignore unknown fields). The `Webhook URL` value is dispatched via `curl` without scheme/host validation; restrict it to trusted internal endpoints.

**Payload field safety:** Field values embedded into webhook payloads must be safe for JSON
string encoding. The `issue_id` and `run_id` fields are constrained by an allowlist
(`[A-Za-z0-9#_-]`) at skill entry and are guaranteed free of JSON-hostile characters. The `pr_url`
field in `pipeline-completed` events must be a valid percent-encoded URL (as returned by the SCM
MCP tool) — do not construct it from raw user input. If you write a custom post-publish hook that
embeds agent output (e.g., `reason` text from a block event) into a webhook payload, construct the
payload with `jq -n --arg <field> "${value}" '{<field>:$<field>, ...}'` so that `jq` performs all
string escaping for you. Do NOT interpolate variables directly into a single-quoted JSON literal
or a heredoc that contains raw `"${var}"` substitutions for free-form text fields.

---

## Error Handling

### `On error: skip` (default)

When a child skill returns a non-zero exit code, Autopilot logs a `[WARN]` and continues with the next issue:

```
[autopilot][WARN] Dispatch returned error for PROJ-42: {error message}. Continuing with next issue.
```

The final summary table still shows `error` in the Outcome column for that issue.

### `On error: stop`

The dispatch loop breaks on the first error:

```
[autopilot][ERROR] Dispatch returned error for PROJ-42. On error=stop — breaking dispatch loop.
```

Remaining issues are not dispatched. The lock is released via the EXIT trap. Exit code is non-zero.

### MCP failure

If the tracker MCP is unreachable at Step 0 (preflight), Autopilot exits immediately with code 3 — **before** acquiring the lock:

```
[STOP] MCP unreachable — {error}
```

No lock is acquired, no state is written. The next cron cycle will retry.

### Lock already held

If another Autopilot process holds the lock (and the lock is not stale), Autopilot exits with code 2:

```
[autopilot][ERROR] Another Autopilot run in progress (pid=12345, host=build-server-01, since=2026-04-17T14:30:00Z).
```

### Exit code matrix

| Exit | Meaning | Lock acquired? |
|------|---------|----------------|
| `0` | All issues dispatched (or dry run, or empty queue) | Yes (released) / No (dry-run) |
| `1` | Preflight failure — missing `Bug query` in `### Issue Tracker` | No |
| `2` | Lock held by another run | No |
| `3` | MCP unreachable | No |
| other non-zero | Dispatch loop broke due to `On error: stop` | Yes (released) |

---

## Troubleshooting

### Lock file stuck

**Symptom:** `[autopilot][ERROR] Another Autopilot run in progress` even though no process appears to be running.

**Cause:** The previous Autopilot process was killed before the EXIT trap could release the lock directory.

**Auto-recovery:** Autopilot auto-recovers stale locks older than 120 minutes. If the lock file is older than 120 minutes (plus a 5-minute NFS/CIFS skew buffer), the next run re-acquires it automatically.

**Manual recovery:** After confirming no live Autopilot process exists on the host:

```bash
rm -rf .agent-flow/autopilot.lock/
```

Check `owner.json` first to identify the owning PID and host before removing:

```bash
cat .agent-flow/autopilot.lock/owner.json
```

### `owner.json` corruption

If `owner.json` exists but is empty or partially written, Autopilot treats it as stale and attempts defensive recovery (re-acquires the lock). A warning is logged but the run continues. This is not fatal.

### BusyBox awk fallback (Alpine 3.9 and earlier)

On minimal Alpine images with BusyBox < 1.30, `awk mktime` is not available. Autopilot falls back to a filesystem mtime check: if `owner.json` was last modified more than 121 minutes ago, the lock is considered stale. This check uses:

```bash
find .agent-flow/autopilot.lock/owner.json -mmin +121 -print
```

Required for the BusyBox fallback path: bash ≥ 4.0, standard `find` with `-mmin`. No GNU-date or Python 3 dependency.

On all other platforms (Linux with gawk, macOS, Windows Git Bash via MSYS coreutils), the primary `awk mktime` path is used.

### `[STOP] MCP unreachable`

Run `/agent-flow:check-setup` to diagnose the tracker MCP configuration. Autopilot does not retry MCP pings — the next cron invocation will re-attempt.

### `Feature Workflow section absent` warning

```
[autopilot][WARN] Feature Workflow section absent — running in bug-only mode.
```

This is expected for bug-only projects. No action needed. Add `### Feature Workflow` to your Automation Config only if you want Autopilot to dispatch features.

### `Feature limit configured but no Feature query`

```
[autopilot][WARN] Feature limit=5 configured but no Feature query — treating as bug-only
```

Either remove `Feature limit` from `### Autopilot`, or add `Feature query` to `### Feature Workflow`.

---

## Paused Issues

When a fixer agent cannot proceed without human input (e.g., an ambiguous requirement), it transitions the issue to `status: paused` in `state.json` and records a `clarification.asked_at` timestamp. Autopilot handles paused issues as follows:

### Skip behavior (awaiting clarification)

On each Autopilot run, a paused issue is **skipped** — it is not re-dispatched. Autopilot logs:

```
[INFO] Skipping PROJ-42: awaiting clarification
```

The issue remains paused until a human answers the clarification question (by re-invoking the original entry-point skill with `--clarification "answer"`, e.g. `/agent-flow:fix-bugs PROJ-42 --clarification "answer"`; auto-resume detection is handled inline by `core/resume-detection.md`) or until the `Pause timeout` elapses.

### Auto-abort on timeout

If the time elapsed since `clarification.asked_at` exceeds the configured `Pause timeout` (default `30 days`), Autopilot transitions the issue to `status: aborted_by_system` with `abort_reason: "clarification_timeout"` and logs:

```
[INFO] PROJ-42: clarification timeout exceeded — transitioned to aborted_by_system
```

The issue is then excluded from future Autopilot runs (it no longer matches the `status: paused` guard, and `aborted_by_system` is typically outside the `Bug query` filter). No `pipeline-completed` event fires on pause — `pipeline-paused` is the dedicated webhook event for this transition.

### Configuring Pause timeout

Add a `### Pause Limits` section to your `## Automation Config`:

```markdown
### Pause Limits

| Key | Value |
|-----|-------|
| Pause timeout | 30 days |
```

Accepted values: `<N> hours` or `<N> days` where N is a positive integer. Minimum: `1 hour`. Maximum: `365 days`. Invalid values fall back to `30 days` with a `[WARN]` log line.

| Value | Resulting timeout |
|-------|-------------------|
| `1 hour` | 1 hour (minimum allowed) |
| `7 days` | 7 days |
| `30 days` | 30 days (default) |
| `365 days` | 365 days (maximum allowed) |

### pipeline-paused webhook event

If `pipeline-paused` is added to `On events` in your `### Notifications` config, a webhook fires each time an issue transitions to `paused`. The payload includes `paused_at`, the clarification question (sanitized), the requesting agent, and the fixer iteration number. See `core/post-publish-hook.md` Section 4 (`pipeline-paused`) for the full payload shape.

---

## Webhook Reliability

Webhook delivery failures (HTTP timeout, DNS error, 4xx/5xx) emit `[WARN] Webhook delivery failed` log lines. To prevent latency runaway from a dead endpoint, agent-flow implements an **in-memory per-run circuit breaker** that opens after 3 consecutive failures and suppresses remaining webhooks for that run only.

**Operator action:** monitor pipeline logs for repeated `[WARN] Circuit breaker open` lines. Repeated openings across runs indicate either (a) a misconfigured `Webhook URL` in Automation Config or (b) a covert-channel DoS via a malicious `Webhook URL` PR change. For multi-contributor environments, treat CLAUDE.md `Webhook URL` PR changes as security-relevant and review carefully.
