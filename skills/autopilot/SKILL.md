---
name: autopilot
description: Headless dispatcher that reads Bug query / Feature query from Automation Config, classifies issues, and dispatches existing skills (fix-bugs / implement-feature). Lock-file protected. For cron / batch / CI invocation.
allowed-tools: mcp__*, Bash, Read, Write, Edit, Grep, Glob, Skill, Task
disable-model-invocation: true
argument-hint: "[--dry-run]"
---

# Autopilot

Headless dispatcher skill for unattended cron / batch / CI invocation. Reads `### Issue Tracker`, `### Feature Workflow` (optional) and `### Autopilot` (optional) from `## Automation Config`, classifies issues into bugs and features, enforces a portable `mkdir`-based lock, and dispatches `agent-flow:fix-bugs` or `agent-flow:implement-feature` per issue sequentially via a headless `claude -p` child-process invocation — NOT the Skill tool, which pipeline entry-point skills block via `disable-model-invocation: true` (see Step 6, item 2, for the full rationale).

Invoke typically as:

```
claude -p "Run /agent-flow:autopilot" --dangerously-skip-permissions
```

or, for safe inspection:

```
claude -p "Run /agent-flow:autopilot --dry-run" --dangerously-skip-permissions
```

Reference: `docs/guides/autopilot.md` for operator onboarding, exit-code matrix, and cron guidance.

## Scope & Boundaries

- **Dispatcher only** — this skill never itself modifies code, writes PRs, or runs tests. Those responsibilities belong to the child skills (`fix-bugs`, `implement-feature`).
- **Process-local lock** — `.agent-flow/autopilot.lock/` guards ONE host / filesystem. Multi-host deployments MUST coordinate via DISJOINT `Bug query` / `Feature query` filters per host, or run Autopilot from exactly one host. The plugin emits an INFO line with the hostname on every successful lock acquisition (see Step 3) but does NOT automatically detect cross-host contention. See `docs/guides/autopilot.md#single-host-operation`.
- **Sequential dispatch** — issues are dispatched one at a time. No per-issue parallelism at the Autopilot layer.
- **Top-level observability only** — Autopilot itself fires NO per-iteration webhooks. Child skills fire their own `pipeline-started` / `step-completed` / `pipeline-completed` events per-issue.
- **Dry-run is a full short-circuit** — `Dry run: true` means no lock, no state.json, no webhook, no dispatch.

## Configuration

Follow `../../core/config-reader.md` for parsing `## Automation Config` from CLAUDE.md.

This skill consumes the following sections:

- **`### Issue Tracker`** (required): `Type`, `Bug query`, `State transitions`, `On start set`. The `Bug query` row is the required authoritative input; `Feature query` lives in `### Feature Workflow`.
- **`### Feature Workflow`** (optional): `Feature query`, `On start set`. Absent section triggers a `[WARN]` and bug-only mode.
- **`### Autopilot`** (optional): 7 keys below. Absent section = all keys use defaults. Autopilot still runs using `Bug query` from `### Issue Tracker`.
- **`### Error Handling`** (optional; generic section shared with `fix-bugs` / `implement-feature`): Autopilot reads ONLY `Max blocked per run` from it, and enforces that value as a CROSS-ISSUE ceiling on the dispatch loop's running `block`-outcome count (see Step 6, item 5). This is DISTINCT from `fix-bugs`' own `Max blocked per run` enforcement inside its `--batch` mode (`skills/fix-bugs/SKILL.md`), which counts blocks WITHIN one child session — that counter never accumulates across issues under Autopilot, because Autopilot dispatches exactly one issue per child session (Step 6, item 2). Default `unlimited` means Autopilot never stops the loop on block count alone. The `On block` key (default `comment`) is NOT read by Autopilot — the block comment is already posted by the child skill before it exits.

### `### Autopilot` — 7 config keys

The Autopilot section uses a `| Key | Value |` table. The 7 keys are (name is EXACT — case and whitespace significant when matching rows):

| Key | Type | Default | Semantics |
|---|---|---|---|
| `Max issues per run` | integer ≥ 1 | 1 | Total cap on issues dispatched per invocation (bugs + features combined). Default of 1 is a safety cap for first use. |
| `Lock timeout` | integer (minutes) | 120 | Age threshold after which an existing lock directory is considered stale and auto-recovered. |
| `Log file` | path | `.agent-flow/autopilot.log` | Append-only run log. Each invocation appends a timestamped summary line. Separate from the lock directory. |
| `Bug limit` | integer ≥ 0 | 0 | Per-type cap on bug dispatches. `0` = no per-type cap (only `Max issues per run` applies). |
| `Feature limit` | integer ≥ 0 | 0 | Per-type cap on feature dispatches. `0` = no per-type cap (only `Max issues per run` applies). |
| `On error` | enum: `skip` \| `stop` | `skip` | Per-issue error policy: `On error: skip` = log [WARN] and continue with next issue; `On error: stop` = abort the whole run on the first per-issue error. |
| `Dry run` | boolean | `false` | `true` = full short-circuit (no lock, no state, no webhook, no dispatch). |

**Query keys are NOT in `### Autopilot`:** `Bug query` is read from `### Issue Tracker` (required existing key). `Feature query` is read from `### Feature Workflow` (optional existing section — absent triggers [WARN] and bug-only mode). Autopilot references them; it does not own them.

When the `### Autopilot` section is absent, Autopilot MAY still run with all 7 keys at their defaults. Operators who do NOT wish to use Autopilot should simply not invoke `/agent-flow:autopilot`.

## Process

The skill executes the following steps IN ORDER. Any STOP or exit terminates Autopilot immediately without proceeding to later steps. Lock release is governed by the trap registered in Step 2.

### Step 0: Preflight — config validation + MCP ping

1. Parse `## Automation Config` via `../../core/config-reader.md`.
2. If `## Automation Config` heading is missing → print to stderr and exit 1:
   ```
   [autopilot][ERROR] Missing Automation Config section in CLAUDE.md. See docs/guides/autopilot.md.
   ```
3. If `### Issue Tracker.Bug query` is absent → print to stderr and exit 1:
   ```
   [autopilot][ERROR] Bug query is required but not found in ### Issue Tracker. Add Bug query to your Issue Tracker config.
   ```
4. Validate `Bug query` is resolvable from `### Issue Tracker.Bug query`. This is a defensive re-check (Step 3 above should have already caught the absence).
5. MCP pre-flight ping: follow `../../core/mcp-preflight.md`. Ping the tracker MCP matching `### Issue Tracker.Type`. On failure, print to stderr and exit 3:
   ```
   [STOP] MCP unreachable — {error}
   ```
   No lock is acquired on MCP failure. No state.json is written. This is a clean, side-effect-free fail.

### Step 1: Dry-run short-circuit check

If config `Dry run: true`:

```
[DRY RUN] Autopilot dry-run mode — full short-circuit. No lock, no state, no webhook, no dispatch.
[autopilot][INFO] Dry run mode — short-circuit. No lock, no state, no webhook, no dispatch.
[autopilot][INFO] Would process: Bug query={Bug query from Issue Tracker}, Feature query={Feature query from Feature Workflow or "<absent>"}, Max issues per run={Max issues per run}, Bug limit={Bug limit}, Feature limit={Feature limit}
```

Then exit 0 immediately. NO lock acquisition, NO state.json write, NO webhook fire, NO child skill dispatch. Dry-run is a fully idempotent inspection mode safe for concurrent cron.

### Step 2: Acquire lock (mkdir-based, portable bash)

The lock is a DIRECTORY `.agent-flow/autopilot.lock/` (NOT a file) — `mkdir` is atomic on POSIX and NTFS. A JSON file `owner.json` inside the directory records `{pid, hostname, acquired_at}`. The trap that releases the lock on EXIT is installed ONLY AFTER a successful `mkdir` (avoids the trap-race where an early-failing process would nuke a lock it never acquired). The trap verifies `pid == $$` before `rm -rf` (refuses to delete another process's lock).

**Stale detection:** if an existing lock has `acquired_at` older than `Lock timeout` minutes (default 120), the lock is considered stale and recovery re-acquires it exactly once. Stale-arithmetic primary path uses `awk mktime`; on BusyBox < 1.30 (Alpine 3.9 and earlier) `awk mktime` is not available — the fallback uses a filesystem mtime check via `find -mmin +121`.

Copy-pasteable reference (see also design.md §4.8):

```bash
# --- Portable ISO-8601 → epoch (pure bash/awk, no GNU-date -d, no BSD-date -j -f) ---
iso_to_epoch() {
  # Input: 2026-04-17T14:30:00Z → epoch seconds on stdout; empty on unparseable.
  local ts="$1"
  [ -z "$ts" ] && { echo ""; return 1; }
  local Y=${ts:0:4} M=${ts:5:2} D=${ts:8:2} h=${ts:11:2} m=${ts:14:2} s=${ts:17:2}
  case "$Y$M$D$h$m$s" in
    *[!0-9]*|"") echo ""; return 1 ;;
  esac
  # awk mktime: gawk + BusyBox ≥ 1.30 + macOS awk support it.
  awk -v Y="$Y" -v M="$M" -v D="$D" -v h="$h" -v m="$m" -v s="$s" \
    'BEGIN { print mktime(Y" "M" "D" "h" "m" "s" UTC") }'
}

# --- Lock acquisition ---
# The literal lock directory path is .agent-flow/autopilot.lock/ (created by mkdir .agent-flow/autopilot.lock below).
# We resolve it to an absolute path here so the trap is CWD-change-safe.
LOCK_DIR="$(pwd)/.agent-flow/autopilot.lock"      # ABSOLUTE path — CWD-change-safe
OWNER_PID=$$
OWNER_HOST=$(hostname)
OWNER_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOCK_TIMEOUT=${LOCK_TIMEOUT:-120}                    # minutes
LOCK_TIMEOUT_WITH_BUFFER=$((LOCK_TIMEOUT + 5))       # +5min NFS/CIFS skew buffer

write_owner_json() {
  printf '{"pid":%s,"hostname":"%s","acquired_at":"%s"}\n' \
    "$OWNER_PID" "$OWNER_HOST" "$OWNER_TIME" \
    > "$LOCK_DIR/owner.json"
}

install_trap() {
  # Verify ownership BEFORE rm -rf. Uses absolute LOCK_DIR (CWD-safe).
  # Install this function ONLY AFTER a successful mkdir of $LOCK_DIR.
  trap '
    if [ -f "'"$LOCK_DIR"'/owner.json" ]; then
      own_pid=$(grep -o "\"pid\"[[:space:]]*:[[:space:]]*[0-9]*" "'"$LOCK_DIR"'/owner.json" 2>/dev/null | grep -o "[0-9]*$")
      if [ "$own_pid" = "'"$OWNER_PID"'" ]; then
        rm -rf "'"$LOCK_DIR"'"
      fi
    fi
  ' EXIT
}

log_single_host_info() {
  # AUTOPILOT-R13: always emit INFO on lock acquire.
  echo "[autopilot][INFO] Running on host ${OWNER_HOST}. If another host is also running Autopilot against the same tracker, it MUST use a disjoint bug/feature query. See docs/guides/autopilot.md#single-host-operation." >&2
}

mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null

# Step 1: try to acquire (atomic mkdir)
if mkdir "$LOCK_DIR" 2>/dev/null; then
  write_owner_json
  install_trap                # trap registered AFTER successful acquisition ONLY
  log_single_host_info
else
  # Lock exists — check staleness
  if [ ! -f "$LOCK_DIR/owner.json" ]; then
    # Empty/malformed lock — treat as stale and recover
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      write_owner_json
      install_trap
      log_single_host_info
    else
      echo "[autopilot][ERROR] Another Autopilot run in progress (malformed lock recovery failed)" >&2
      exit 2
    fi
  else
    acquired_at=$(grep -o '"acquired_at":"[^"]*"' "$LOCK_DIR/owner.json" | cut -d'"' -f4)
    if [ -z "$acquired_at" ]; then
      # Defensive: empty or partial write → treat as stale
      rm -rf "$LOCK_DIR"
      if mkdir "$LOCK_DIR" 2>/dev/null; then
        write_owner_json
        install_trap
        log_single_host_info
      else
        echo "[autopilot][ERROR] Another Autopilot run in progress (defensive-parse recovery failed)" >&2
        exit 2
      fi
    else
      acquired_epoch=$(iso_to_epoch "$acquired_at")
      if [ -z "$acquired_epoch" ]; then
        # BusyBox fallback: awk mktime unavailable → filesystem mtime check.
        if find "$LOCK_DIR/owner.json" -mmin +121 -print 2>/dev/null | grep -q .; then
          rm -rf "$LOCK_DIR"
          if mkdir "$LOCK_DIR" 2>/dev/null; then
            write_owner_json
            install_trap
            log_single_host_info
          else
            echo "[autopilot][ERROR] Another Autopilot run in progress (BusyBox-fallback recovery race)" >&2
            exit 2
          fi
        else
          echo "[autopilot][ERROR] Another Autopilot run in progress (awk mktime unavailable; mtime age < 121min)" >&2
          exit 2
        fi
      else
        now_epoch=$(date -u +%s)
        age_min=$(( (now_epoch - acquired_epoch) / 60 ))
        if [ "$age_min" -gt "$LOCK_TIMEOUT_WITH_BUFFER" ]; then
          # Stale — recover
          rm -rf "$LOCK_DIR"
          if mkdir "$LOCK_DIR" 2>/dev/null; then
            write_owner_json
            install_trap
            log_single_host_info
          else
            echo "[autopilot][ERROR] Another Autopilot run in progress (stale recovery race)" >&2
            exit 2
          fi
        else
          own_pid_peek=$(grep -o '"pid"[[:space:]]*:[[:space:]]*[0-9]*' "$LOCK_DIR/owner.json" | grep -o '[0-9]*$')
          own_host_peek=$(grep -o '"hostname":"[^"]*"' "$LOCK_DIR/owner.json" | cut -d'"' -f4)
          echo "[autopilot][ERROR] Another Autopilot run in progress (pid=${own_pid_peek}, host=${own_host_peek}, since=${acquired_at})." >&2
          exit 2
        fi
      fi
    fi
  fi
fi
```

**Invariants** (operators MUST preserve if customizing):

1. `LOCK_DIR` is resolved to an ABSOLUTE path before the trap is installed (CWD-change-safe).
2. `trap ... EXIT` is installed ONLY AFTER a successful `mkdir` or successful stale re-acquire — never on the fast-fail path.
3. The trap verifies `owner.json.pid` matches `$$` before `rm -rf` — refuses to nuke another process's lock.
4. ISO-8601 parsing uses pure bash + awk; no GNU-date `-d`, no BSD-date `-j -f`, no Python 3 dependency. Portable to Linux, Windows Git Bash, macOS.
5. Empty or malformed `owner.json` triggers defensive stale-recovery instead of hard failure.
6. Stale threshold carries a +5 minute buffer to absorb NFS/CIFS clock skew.
7. No sidecar files are written outside `$LOCK_DIR`. Cross-host awareness is an INFO log line only (Step 3), never a persistent hint file.

### Step 3: Cross-host INFO (AUTOPILOT-R13)

On every successful lock acquisition (including stale recovery), always log to stderr:

```
[autopilot][INFO] Running on host {hostname}. If another host is also running Autopilot against the same tracker, it MUST use a disjoint bug/feature query. See docs/guides/autopilot.md#single-host-operation.
```

This is an INFORMATIONAL line only. It does NOT detect cross-host contention. The authoritative multi-host mitigation is operator-side DISJOINT-QUERY configuration (see guide). The INFO line aids log correlation only.

### Step 4: Read Bug + Feature queries

1. Read `Bug query` — required. Source: `### Issue Tracker.Bug query`. If absent, Step 0 would have already exited 1; this is a defensive re-check.
2. Read `Feature query` (optional). Source: `### Feature Workflow.Feature query`.
3. If `### Feature Workflow` section is ABSENT from Automation Config:
   ```
   [autopilot][WARN] Feature Workflow section absent — running in bug-only mode.
   ```
   Continue in bug-only mode. DO NOT block. DO NOT exit.
4. If `### Feature Workflow` exists but `Feature query` is empty AND `Feature limit > 0`:
   ```
   [autopilot][WARN] Feature limit={N} configured but no Feature query — treating as bug-only
   ```
   Continue in bug-only mode.
5. Determine the tracker MCP prefix from `### Issue Tracker.Type` (default `youtrack`; supported: `youtrack`, `github`, `jira`, `linear`, `gitea`, `redmine`).
6. Read `Pause timeout` from `### Pause Limits` (optional section; default `30 days`). Parse and validate via `parse_pause_timeout()` (defined below); store result as `PAUSE_TIMEOUT_SECONDS` for use in Step 6.

#### `parse_pause_timeout()` — POSIX-portable Pause timeout parser

Validates the operator-supplied `Pause timeout` config value. Minimum `1 hour` (3600 s), maximum `365 days` (31536000 s). On invalid input: graceful fallback to default — log `[WARN] Invalid Pause timeout '{value}'; using default 30 days` and return default 2592000 s. The pipeline MUST NOT abort on invalid input; the fallback-to-default behavior ensures continued operation.

```bash
parse_pause_timeout() {
  local raw="$1"
  local n unit unit_lower seconds
  # Strip surrounding whitespace.
  raw="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  # Match `<N> hours` or `<N> days` (positive integer N); case-insensitive unit.
  if [[ "$raw" =~ ^([0-9]+)[[:space:]]+([Hh][Oo][Uu][Rr][Ss]?|[Dd][Aa][Yy][Ss]?)$ ]]; then
    n="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    # Downcase the unit token for case-insensitive matching (handles "30 Days", "2 Hours", etc.)
    unit_lower=$(printf '%s' "$unit" | tr '[:upper:]' '[:lower:]')
    case "$unit_lower" in
      hour|hours) seconds=$(( n * 3600 )) ;;
      day|days)   seconds=$(( n * 86400 )) ;;
    esac
    # Range check: min 1 hour (3600s), max 365 days (31536000s).
    if [ "$seconds" -ge 3600 ] && [ "$seconds" -le 31536000 ]; then
      printf '%s\n' "$seconds"
      return 0
    fi
  fi
  # Invalid input — log warning and fall back to default 30 days (2592000s).
  echo "[WARN] Invalid Pause timeout '${raw}'; using default 30 days" >&2
  printf '%s\n' "2592000"
}
```

### Step 5: Two-query classification loop

1. Fetch BUGS first via `Bug query` through the tracker MCP. Apply the `Bug limit` per-type cap (default 0 = no per-type cap). Apply the `Max issues per run` total cap (default 1) as a hard ceiling across all issue types.
2. Fetch FEATURES via `Feature query` through the tracker MCP (skip if bug-only mode). Apply the `Feature limit` per-type cap (default 0 = no per-type cap). Apply remaining headroom from `Max issues per run` as ceiling.
3. Build the classification list. For each issue returned:
   - If the issue appears ONLY in `Bug query` results → classify as `bug`.
   - If the issue appears ONLY in `Feature query` results → classify as `feature`.
   - If the issue appears in BOTH queries → classify as `bug` (bug wins on overlap per roadmap rule; prevents double-dispatch).
4. Produce an ordered dispatch list: bugs first (in tracker-returned order), then features (in tracker-returned order), all de-duplicated.

### Step 5a: ISSUE_ID path-traversal validation

Tracker content (including the issue ID itself) is operator-untrusted input (see
`## Security Considerations` below). Before Step 6 constructs ANY filesystem path from a
classified issue's ID — the `state_file` lookup in Step 6 item 1a, the `mkdir` and log
redirections in Step 6 item 2 — validate every `ISSUE_ID` in the Step 5 dispatch list
using the canonical path-traversal check from `../../core/resume-detection.md` Step 1
(the single source of truth for this defense; reused verbatim, not reimplemented):

```bash
if [[ ! "${ISSUE_ID}" =~ ^[A-Za-z0-9._-]+$ || "${ISSUE_ID}" =~ ^\.+$ ]]; then
  echo "[autopilot][ERROR] Invalid issue_id from tracker query: '${ISSUE_ID}' rejected (path-traversal defense — see core/resume-detection.md Step 1). No filesystem path was constructed for this ID." >&2
  outcome="error"
  # Apply the Step 6 "outcome is error" policy (item 4) — On error: skip logs [WARN] and
  # continues with the next issue; On error: stop breaks the dispatch loop and proceeds to
  # Step 7. Either way, this ID is NEVER passed to mkdir, a state_file path, or `claude -p`.
else
  # ISSUE_ID is safe — proceed to Step 6 dispatch for this issue.
  :
fi
```

The character class forbids `/` and `\`; the second clause forbids dot-only strings
(`.`, `..`, `...`). A rejected ID counts toward the run's `error` outcome bucket in the
Step 7 summary exactly like any other per-issue dispatch error.

### Step 6: Per-issue dispatch

For each classified issue in turn, SEQUENTIALLY (one at a time):

1. Record per-issue start time (for the summary table in Step 7).
1a. **Pause-state detection:** Before dispatch, check whether the issue has an existing state.json with `status == "paused"`:

```bash
state_file=".agent-flow/${ISSUE_ID}/state.json"
if [ -f "$state_file" ]; then
  current_status=$(jq -r '.status // empty' "$state_file" 2>/dev/null)
  if [ "$current_status" = "paused" ]; then
    asked_at=$(jq -r '.clarification.asked_at // empty' "$state_file" 2>/dev/null)
    # Cross-platform ISO-8601 → epoch conversion (uses python3 fallback for BSD/macOS).
    # `date -d` is GNU-only; BSD/macOS `date -d` returns 0, causing premature auto-abort on first scan.
    # Strategy: try python3 first (universally available on modern systems), fall back gracefully.
    _iso_to_epoch_crossplatform() {
      local _ts="$1"
      local epoch=""
      if command -v python3 >/dev/null 2>&1; then
        epoch=$(python3 -c "import datetime, sys; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z', '+00:00')).timestamp()))" "$_ts" 2>/dev/null)
      else
        # Last resort: GNU date -d (Linux only; returns empty on BSD/macOS — caller handles empty).
        epoch=$(date -d "$_ts" +%s 2>/dev/null)
      fi
      # Warn when conversion fails on a non-empty input (e.g., BusyBox Alpine minimal host
      # with neither python3 nor GNU date). Pause-timeout auto-abort is silently disabled otherwise.
      if [ -z "$epoch" ] && [ -n "$_ts" ]; then
        echo "[WARN] Pause timeout calc failed: neither python3 nor GNU date available. Pause-timeout auto-abort disabled on this host. Install python3 to enable." >&2
      fi
      printf '%s\n' "$epoch"
    }
    asked_epoch=$(_iso_to_epoch_crossplatform "$asked_at")
    now_epoch=$(date +%s)
    if [ -n "$asked_epoch" ] && [ "$asked_epoch" -gt 0 ] 2>/dev/null; then
      pause_age_seconds=$(( now_epoch - asked_epoch ))
    else
      pause_age_seconds=0
    fi
    pause_timeout_seconds=$(parse_pause_timeout "${PAUSE_TIMEOUT:-30 days}")  # default 30 days
    if [ "$pause_age_seconds" -gt "$pause_timeout_seconds" ]; then
      # Timeout elapsed — promote to aborted_by_system
      jq '.status = "aborted_by_system" | .abort_reason = "clarification_timeout"' "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
      echo "[INFO] ${ISSUE_ID}: clarification timeout exceeded — transitioned to aborted_by_system"
    else
      echo "[INFO] Skipping ${ISSUE_ID}: awaiting clarification"
    fi
    continue  # skip this issue; do NOT re-dispatch
  fi
fi
```

   - If `status == "paused"` AND elapsed time since `clarification.asked_at` > `PAUSE_TIMEOUT_SECONDS`: transition state to `aborted_by_system` with `abort_reason: "clarification_timeout"` and log the timeout line, then `continue` (skip dispatch).
   - If `status == "paused"` AND elapsed time ≤ `PAUSE_TIMEOUT_SECONDS`: log `[INFO] Skipping {ISSUE_ID}: awaiting clarification` and `continue` (skip dispatch).
   - `pipeline-completed` MUST NOT fire on pause — this skip path never invokes child skills, so no `pipeline-completed` event is emitted.

2. Dispatch via Bash subprocess (resolves upstream Claude Code #26251 — pipeline skills have `disable-model-invocation: true` in their frontmatter, which blocks the Skill tool dispatch path; plain-text headless invocation via `claude -p` is the only reliable workaround):

```bash
# Ensure per-issue artifact directory exists
mkdir -p ".agent-flow/${ISSUE_ID}"

# Select target skill per classification ("bug" | "feature")
if [ "$classification" = "bug" ]; then
  TARGET_SKILL="/agent-flow:fix-bugs"
elif [ "$classification" = "feature" ]; then
  TARGET_SKILL="/agent-flow:implement-feature"
fi

# Dispatch as isolated child claude session (plain-text bypass of disable-model-invocation).
# --yolo is REQUIRED: no operator is present to answer core/resume-detection.md's
# interactive [Y/n/abort] prompt under unattended cron/CI invocation. Without it, a child
# that finds an existing non-FRESH state.json (e.g. a "running" status left behind by a
# prior crashed child for the same ISSUE_ID) would block forever on stdin. Under --yolo,
# resume-detection.md Step 6's matrix auto-resumes "running"/"aborted_by_system" states
# with no prompt, which is exactly the crash-containment behavior Autopilot needs here.
# Child session writes state.json to .agent-flow/${ISSUE_ID}/state.json per standard pipeline.
claude -p "Run ${TARGET_SKILL} ${ISSUE_ID} --yolo" \
  --dangerously-skip-permissions \
  > ".agent-flow/${ISSUE_ID}/dispatch-stdout.log" \
  2> ".agent-flow/${ISSUE_ID}/dispatch-stderr.log"
child_exit=$?
```

Rationale: per-issue child-session isolation also provides crash containment (a crashed child cannot poison the parent autopilot session) and mirrors the cron-invocation pattern exactly. `--yolo` on the dispatch is what makes that containment actually reachable — see the inline comment above. A `paused` outcome (child hit `NEEDS_CLARIFICATION` under `--yolo` with no `--clarification` answer available) still surfaces as an `error`-shaped non-zero `child_exit` per `core/resume-detection.md` Step 6's `--yolo` column ONLY when RESUMING a pre-existing paused state; Step 1a above already filters those out before dispatch, so in practice a `paused` outcome here means the pipeline paused freshly during THIS run (`child_exit == 0`, see item 3 below). Token cost: ~2-5k per child-session startup — acceptable given the isolation benefits. Re-evaluate restoring Skill-tool dispatch if Anthropic ships a selective-invocation whitelist primitive.

3. Capture per-issue outcome from `child_exit` and the child's `state.json`:

```bash
child_state_file=".agent-flow/${ISSUE_ID}/state.json"
if [ "$child_exit" -eq 0 ] && [ -f "$child_state_file" ]; then
  child_status=$(jq -r '.status // "unknown"' "$child_state_file" 2>/dev/null)
  case "$child_status" in
    completed) outcome="success" ;;
    blocked)   outcome="block" ;;
    paused)    outcome="paused" ;;   # NEEDS_CLARIFICATION — not an error; Step 1a handles on next run
    *)         outcome="error" ;;    # unexpected status or jq read failure
  esac
else
  outcome="error"
fi
```

Classification:
   - `success` — `child_exit == 0` AND `state.json.status == "completed"`.
   - `block` — `child_exit == 0` AND `state.json.status == "blocked"` (block comment already posted by child).
   - `paused` — `child_exit == 0` AND `state.json.status == "paused"` (NEEDS_CLARIFICATION; next autopilot run's Step 1a will enforce `Pause Limits` and either skip or auto-abort).
   - `error` — `child_exit != 0`, OR `state.json` missing, OR unexpected `status` value.
4. If outcome is `error`:
   - If `On error: stop` → log `[autopilot][ERROR] Dispatch returned error for {ISSUE-ID}. On error=stop — breaking dispatch loop.`, DO NOT dispatch remaining issues, proceed to Step 7 (the EXIT trap will release the lock; exit code non-zero).
   - If `On error: skip` (default) → log `[autopilot][WARN] Dispatch returned error for {ISSUE-ID}: {error message}. Continuing with next issue.`, proceed to the next issue.
5. If outcome is `block`:
   - Increment the run's `n_block` counter (the same counter reported in the Step 7 summary).
   - Log `[autopilot][INFO] Issue {ISSUE-ID} blocked by child skill. Continuing with next issue.`
   - If `### Error Handling.Max blocked per run` is configured to a finite value (not `unlimited`, the default) AND `n_block` has now reached it: log `[autopilot][WARN] Max blocked per run ({N}) reached after issue {ISSUE-ID}. Halting dispatch loop; remaining issues are left undispatched for the next run.`, DO NOT dispatch remaining issues, proceed to Step 7 (the Step 2 EXIT trap still releases the lock; exit code non-zero — same early-exit shape as `On error: stop`).
   - Otherwise proceed to the next issue.
   A per-issue `block` is not a per-issue `error` — the `Max blocked per run` ceiling is independent of, and checked in addition to, the `On error` policy.
5a. If outcome is `paused` → log `[autopilot][INFO] Issue {ISSUE-ID} paused awaiting clarification. Continuing with next issue.`, proceed to the next issue. A per-issue `paused` is not a per-issue `error`; Step 1a on the next autopilot run will enforce `Pause Limits`.
6. If outcome is `success` → log `[autopilot][INFO] Issue {ISSUE-ID} completed ({pipeline}). Duration={D}s.`, proceed to the next issue.

**Important:** Autopilot itself does NOT fire webhooks per issue. The child `fix-bugs` / `implement-feature` skills fire their own `pipeline-started` / `step-completed` / `pipeline-completed` events (see `../../core/post-publish-hook.md` Section 4). Autopilot is a pure dispatcher at the observability layer.

### Step 7: Final summary

After all issues are processed (or after an `On error: stop` break, or after a `Max blocked per run` break — see Step 6 item 5):

1. Emit a markdown summary table to stdout:

   ```markdown
   ## Autopilot summary

   | Issue ID | Type    | Outcome  | Duration | Tokens  |
   |----------|---------|----------|----------|---------|
   | PROJ-42  | bug     | success  | 412s     | 198,200 |
   | PROJ-43  | bug     | block    | 58s      | 31,400  |
   | PROJ-57  | feature | success  | 903s     | 401,500 |
   | PROJ-61  | bug     | paused   | 71s      | 22,900  |
   | ...      | ...     | ...      | ...      | ...     |

   **Totals:** {N_bugs} bugs, {N_features} features, {N_success} success, {N_block} blocked, {N_paused} paused, {N_error} errored. Wall-clock: {total_duration}s. Tokens (measured when available): {total_tokens}.
   ```

   `Tokens` column is read from the per-issue `state.json.pipeline.total_tokens` after each child dispatch completes. If absent (child exited without writing a completed pipeline accumulator), the column reads `—`. The `paused` outcome row (see Step 6 item 3) is counted separately from `block` — it is NOT a failure; the next Autopilot run's Step 1a will re-evaluate it against `Pause Limits`.
2. Append the run summary to `$LOG_FILE` (the `Log file` config key, default `.agent-flow/autopilot.log`). One line per Autopilot invocation in the format:
   ```
   {ISO8601}|{run_id}|{issues_processed}|{n_success}|{n_block}|{n_paused}|{n_error}|{total_tokens}|{total_duration_ms}
   ```
   Where `run_id` is the Autopilot invocation ID (`autopilot-{YYYYMMDDTHHMMSSZ}`), `issues_processed` is the count of issues dispatched, `n_paused` is the count of `paused` outcomes (Step 6 item 3), and `total_tokens` is the sum of per-issue `state.json.pipeline.total_tokens` (or `0` when not available). On write failure: log `[autopilot][WARN] Log file not writable: {error}` and continue — log failure never blocks the exit path.
3. Lock release is AUTOMATIC via the trap registered in Step 2 (EXIT handler). Operators MUST NOT manually `rm -rf` the lock directory from inside this skill.
4. Exit codes:
   - `0` — all issues dispatched (some may have `block`, `paused`, or recoverable `error` outcomes; `On error: skip`).
   - `1` — preflight config validation failed (Step 0 — missing Bug query in Issue Tracker).
   - `2` — lock held by another run (fresh or stale-recovery failure).
   - `3` — MCP unreachable at Step 0 (no lock was acquired).
   - non-zero (other) — dispatch loop broke early due to `On error: stop` OR `Error Handling.Max blocked per run` reached (Step 6 item 5).

## Exit Code Matrix

| Exit | Meaning | Lock acquired? | State written? |
|------|---------|----------------|----------------|
| 0    | All issues dispatched, or Dry run, or empty queue | Yes (released) / No (dry-run) | Per-issue by child skills (or no if dry-run) |
| 1    | Preflight failure (missing Bug query in Issue Tracker) | No | No |
| 2    | Lock held by another run | No | No |
| 3    | MCP ping failed — tracker unreachable | No | No |
| >0 (other) | Dispatch loop broke early due to `On error: stop` OR `Max blocked per run` reached | Yes (released) | Per-issue up to the breaking dispatch |

Operators configuring cron SHOULD capture exit codes: cron `MAILTO` + `set -o pipefail` + appending `|| echo "[autopilot] exit=$?" >> /var/log/autopilot.log` is the recommended minimum harvest pattern.

## Cross-Host Operation

Multi-host deployments against the SAME tracker are NOT coordinated by Autopilot's process-local lock. The plugin mitigation is OPERATOR-SIDE DISJOINT-QUERY configuration:

- **Preferred:** run Autopilot from exactly ONE cron host.
- **If unavoidable:** configure per-host DISJOINT `Bug query` / `Feature query` filters, for example:
  - Host A: `Bug query: State: Open and assignee: bot-host-a`
  - Host B: `Bug query: State: Open and assignee: bot-host-b`

Autopilot emits `[autopilot][INFO] Running on host {hostname}` on every successful lock acquisition (Step 3). Log aggregators can correlate per-host autopilot activity; however, the plugin does NOT automatically detect cross-host contention. See `docs/guides/autopilot.md#single-host-operation` for onboarding and troubleshooting.

Tracker-level distributed lock is NOT_IN_SCOPE for the current release.

**Multi-host coordination via disjoint queries is the supported pattern.** Distributed lock (e.g., flock advisory lock, external coordinator like etcd/redis/consul) is deferred pending operator demand and a portability test matrix (local FS + NFS + SMB + S3FUSE tiers). Half-implemented locks are MORE dangerous than disjoint queries — they create silent duplicate-execution failure modes.

## Dry-Run Example

```bash
$ claude -p "Run /agent-flow:autopilot --dry-run" --dangerously-skip-permissions
[DRY RUN] Autopilot dry-run mode — full short-circuit. No lock, no state, no webhook, no dispatch.
[autopilot][INFO] Dry run mode — short-circuit. No lock, no state, no webhook, no dispatch.
[autopilot][INFO] Would process: Bug query=State: Open and type: Bug, Feature query=State: Open and type: Feature, Max issues per run=1, Bug limit=0, Feature limit=0
```

Dry-run is safe to schedule in parallel with a live Autopilot run because it touches NO shared state.

## Troubleshooting

- **`[autopilot][ERROR] Another Autopilot run in progress`** → check `.agent-flow/autopilot.lock/owner.json` for the owning PID and host. If the owning process is gone but the lock is less than the effective stale threshold (the configured `Lock timeout` value plus a 5-minute NFS/CIFS clock-skew buffer; default: 125 min on primary path, 121 min on BusyBox fallback), wait for stale auto-recovery or manually `rm -rf .agent-flow/autopilot.lock/` (only after verifying no live process).
- **`[STOP] MCP unreachable`** → run `/agent-flow:check-setup` to diagnose tracker MCP configuration. Autopilot does NOT retry MCP pings; next cron cycle will re-attempt.
- **`[autopilot][WARN] Feature Workflow section absent`** → expected for bug-only projects; no action needed.
- **`[autopilot][WARN] Feature limit=N configured but no Feature query`** → either remove `Feature limit` from `### Autopilot` or add `Feature query` to `### Feature Workflow`.

## Security Considerations

**`--dangerously-skip-permissions` blast radius:** The canonical Autopilot invocation passes `--dangerously-skip-permissions` to `claude -p`. This flag disables Claude's interactive permission prompts for file writes, tool dispatch, and bash command execution, granting Autopilot (and all child skills it dispatches) unrestricted permission for the entire run.

**Containment guidance for operators:**
- Run Autopilot as a **dedicated low-privilege OS user** with filesystem access scoped to the project directory.
- Consider wrapping the invocation in a container or chroot to limit blast radius to the project tree.
- **Audit `Bug query` and `Feature query`** — issue content (title, description, comments) is fed to opus-powered fixer agents that then run bash commands and write files. A poisoned issue in the tracker can influence agent behavior under `--dangerously-skip-permissions`.
- Restrict network egress from the Autopilot host if the tracker is internal; this limits exfiltration risk from compromised issue content.
- **Issue IDs are also tracker-sourced and untrusted** — the same poisoned-tracker threat model applies to the ID field, not just title/description/comments. Step 5a rejects any classified `ISSUE_ID` that fails the canonical `^[A-Za-z0-9._-]+$` check from `core/resume-detection.md` Step 1 BEFORE it is used to build `.agent-flow/${ISSUE_ID}/...` paths, closing the path-traversal vector a crafted issue ID (e.g. `../../etc`) would otherwise open.

SSRF defenses for the `Webhook URL` config key (e.g., blocking `file://`/`gopher://` schemes) are deferred to a future release. See `docs/reference/config.md` Notifications section for current operator-trust guidance.

## Rules

- NEVER modify code directly — Autopilot is a dispatcher only.
- NEVER fire webhooks at the Autopilot layer — child skills own their own lifecycle events.
- NEVER acquire the lock in dry-run mode.
- NEVER write state.json at the Autopilot layer — per-issue state is owned by child skills.
- NEVER remove another process's lock directory — the trap verifies `pid == $$` before `rm -rf`.
- NEVER silently ignore a missing `### Feature Workflow` section — always emit `[WARN]` before falling back to bug-only mode.
- NEVER construct a `.agent-flow/${ISSUE_ID}/...` path (state file, `mkdir`, dispatch logs) for an `ISSUE_ID` that has not passed the Step 5a path-traversal check.
- NEVER dispatch a child skill without `--yolo` — an unattended cron/CI invocation has no operator to answer `core/resume-detection.md`'s interactive prompt.
- ALWAYS use the EXACT log prefixes: `[autopilot][INFO]`, `[autopilot][WARN]`, `[autopilot][ERROR]`, `[STOP]` (for MCP unreachable at Step 0).
- ALWAYS reference `docs/guides/autopilot.md#single-host-operation` in the cross-host INFO line (Step 3) and in error recovery guidance.
