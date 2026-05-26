---
name: scaffold
description: Creates a new project from scratch; use 'add <component>' to extend an existing project
allowed-tools: mcp__*, Bash, Read, Write, Edit, Glob, Grep, Task
disable-model-invocation: true
argument-hint: "{add <component> | <description>} [--template <path>] [--spec <path>] [--issue <ID>] [--no-implement] [--yolo] [--step-mode] [--infra tracker:<v>,sc:<v>] [--lang <v>] [--framework <v>] [--db <v>] [--ci <v>] [--brainstorm]"
---

# Scaffold

Use the Read tool to load `skills/scaffold/data/guard-block.md` BEFORE any other instruction
in this file. The guard is load-bearing; it establishes the orchestrator role, blocks
pre-dispatch deferrals, and contains the rationalization-red-flags STOP protocol.

Input: `$ARGUMENTS` = either `add <component>` (subcommand mode) OR project description (natural language) + optional flags

## Step 0 — Subcommand dispatch

Read the first non-empty token of `$ARGUMENTS`. If it equals `add`, branch into the `add <component>` subcommand body (see `## Subcommand: add <component>` at the end of this file). Otherwise, fall through to the new-project flow (Flag Parsing section below).

```bash
read -ra ARG_TOKENS <<< "$ARGUMENTS"
FIRST_TOKEN="${ARG_TOKENS[0]:-}"

if [ "$FIRST_TOKEN" = "add" ]; then
  # Subcommand mode — extend an existing project with a single component.
  COMPONENT="${ARG_TOKENS[1]:-}"
  if [ -z "$COMPONENT" ]; then
    echo "[ERROR] Usage: /agent-flow:scaffold add <component>" >&2
    echo "Supported components: claude-md | ci | docker | tests" >&2
    exit 1
  fi
  case "$COMPONENT" in
    claude-md|ci|docker|tests) ;;
    *)
      echo "[ERROR] Unknown component: ${COMPONENT}" >&2
      echo "Supported components: claude-md | ci | docker | tests" >&2
      exit 1
      ;;
  esac
  # Branch into the Subcommand body at the END of this file (## Subcommand: add <component>).
  # The subcommand branch MUST exit after step 6 (Report) and MUST NOT fall through to the new-project flow.
fi

# Otherwise: existing new-project flow continues with Flag Parsing below.
```

The `add` subcommand is a single-shot operation and does NOT use resume detection. The new-project flow does — see the resume detection invocation immediately after Flag Parsing / Mode Resolution below.

## Flag Parsing

Parse `$ARGUMENTS` for these flags:

| Flag | Variable | Notes |
|------|----------|-------|
| `--template <path>` | `template_path` | |
| `--spec <path>` | `spec_path` | |
| `--issue <ID>` | `issue_id` | |
| `--no-implement` | `no_implement = true` | |
| `--yolo` | `GOT_YOLO = true` | B6 mode flag |
| `--step-mode` | `GOT_STEP_MODE = true` | B6 mode flag |
| `--lang <v>` | `preset_lang` | |
| `--framework <v>` | `preset_framework` | |
| `--db <v>` | `preset_db` | |
| `--ci <v>` | `preset_ci` | |
| `--brainstorm` | `brainstorm = true` | |
| `--infra <v>` | `infra_preset` | See validation below |

Remainder after removing flags = project description.

## Flag Validation

If both `--yolo` and `--step-mode` are set:
→ Error: "Flags --yolo and --step-mode are mutually exclusive. Use one or neither."

If more than one of (`--spec`, `--template`, `--issue`) provided:
→ Error: "Only one input source allowed. Use --spec, --template, or --issue."

If `--no-implement` AND any of (`--spec`, `--template`, `--issue`):
→ Error: "--no-implement skips specification phase. Remove --spec/--template/--issue or remove --no-implement."

If `--brainstorm` AND `--spec`:
→ Error: "--brainstorm is for exploring ideas. Use --spec when you already have a specification."

If `--infra` provided:
- Single word `{ready|later}` → expand to `tracker:{value},sc:{value}`
- Named pairs `tracker:{ready|later},sc:{ready|later}` (or reversed) → parse as-is
- Old positional `{ready|later},{ready|later}` → Error: "--infra format changed. Use: --infra tracker:ready,sc:later"
- Otherwise → Error: "Invalid --infra format. Expected: --infra tracker:ready,sc:later"

If `--infra` provided AND tracker value is `later` AND `--issue` provided:
→ Error: "--issue requires tracker access. Use --infra tracker:ready,sc:{v} or remove --issue."

If no project description AND no `--spec` AND no `--template` AND no `--issue` AND not `--no-implement`:
→ Ask user for project description.

## Mode Resolution

```
if GOT_YOLO:    MODE = "yolo"
elif GOT_STEP:  MODE = "step-mode"
else:           MODE = "default"
```

`MODE` is passed as context to all step dispatches. Steps use it to gate checkpoints and prompts.

### Default mode behavior

In default mode, brainstorm triggers only for vague descriptions (heuristic: word count < 20 OR no
technical term detected; see `steps/01-mode-resolve.md` for full heuristic). Long technical
descriptions (>=20 words AND technical terms) skip brainstorm automatically. The heuristic requires
BOTH conditions: word count AND technical term presence. Two checkpoints are always visible:
- **Spec Checkpoint** after Step 02 (spec-writer loop complete)
- **Feature Plan Checkpoint** after Step 04 (architect + decomposition complete)

### --yolo mode behavior

`--yolo` enables yolo autonomous execution: no brainstorm (skip regardless of description vagueness),
no Spec checkpoint, no Feature Plan checkpoint, no user prompts; all conditional gates skipped.
Pipeline runs autonomously from description to final report with zero gates.

## Step Dispatch

Read `steps/` sub-files. Execute in order:

### --no-implement path

If `no_implement = true`: execute legacy flow (scaffolder (with stack flags) → validate → git init → push if SC ready → report). See `steps/03-scaffold.md` L1–L6 section. EXIT after L6.

### Full pipeline path

| Step | File | Description |
|------|------|-------------|
| 01 | `steps/01-mode-resolve.md` | State detection, infra declaration (0-INFRA), MCP verification (0-MCP), brainstorm |
| 02 | `steps/02-spec-write-review.md` | spec-writer ↔ spec-reviewer loop + Spec Checkpoint |
| 03 | `steps/03-scaffold.md` | scaffolder agent, validate, git init, auto-fill CLAUDE.md, push (4d), tracker issues (4e) |
| 04 | `steps/04-architect.md` | architect agent, decomposition, AC coverage, Feature Plan Checkpoint |
| 05 | `steps/05-fixer-reviewer-loop.md` | fixer ↔ reviewer per subtask/batch, NEEDS_CLARIFICATION handling |
| 06 | `steps/06-test.md` | test-engineer per subtask + full-suite sweep |
| 07 | `steps/07-spec-verify.md` | spec-reviewer --verify, post-impl tracker comments, close issues |
| 08 | `steps/08-final-report.md` | pipeline accumulator, pipeline-completed webhook, final report |

Each step receives: `MODE`, `GOT_YOLO`, `GOT_STEP_MODE`, all parsed flags and in-memory variables from prior steps.

> **See also:** `/agent-flow:scaffold validate` (the `validate` subcommand) for read-only validation of an existing project (tool contract: `Bash, Read, Glob, Grep` only).

## Resume Detection

Follow `../../core/resume-detection.md` for resume detection logic. Inputs:
- ISSUE_ID — set to the scaffold run identifier (e.g. `scaffold-{timestamp}` derived from project description hash, or operator-supplied via state directory).
- MODE=`single` (scaffold is always single-pipeline; no batch).
- GOT_YOLO, GOT_STEP_MODE — from Mode Resolution section above.
- Webhook_URL, On_events — from Automation Config Notifications section.
- CLARIFICATION_TEXT — from `--clarification "<text>"` flag if provided on resume.

Outputs: RESUME_POINT, RESTORED_CONTEXT, PIPELINE_TYPE.

**Post-resume MCP checkpoint check (scaffold-specific):**
After resume-detection returns, check for a pending MCP setup checkpoint. Derive `STATE_FILE`
the same way as `../../core/resume-detection.md` Step 2: `STATE_FILE=".agent-flow/${ISSUE_ID}/state.json"`.
Guard against missing file before reading:
```bash
STATE_FILE=".agent-flow/${ISSUE_ID}/state.json"
MCP_PENDING=""
if [ -f "$STATE_FILE" ]; then
  MCP_PENDING=$(grep -oE '"mcp_setup_pending"[[:space:]]*:[[:space:]]*(true|false)' "$STATE_FILE" \
                | grep -oE '(true|false)$' | head -1)
fi
```
If `MCP_PENDING = "true"`: override `RESUME_POINT = "0-mcp"`. Skip Step 01a and 01b (already
completed; values restored from state.json). Re-enter Step 01c (MCP Verification) only.
Clearing `mcp_setup_pending` is handled exclusively inside Step 01c (see `steps/01-mode-resolve.md`
Step 01c) — do NOT clear it here.

If `RESUME_POINT == "FRESH"`, proceed with the full new-project pipeline below. If `RESUME_POINT` is any other value, skip ahead to the corresponding scaffold step per the SCAFFOLD pipeline mapping (see `../../core/resume-detection.md` Step 6 status branch and the legacy `resume-ticket` SCAFFOLD pipeline mapping).

The `add <component>` subcommand (Step 0 dispatch above) is single-shot and does NOT invoke resume detection.

## Rules

- NEVER execute agents inline — always via Task tool (CONTRACT VIOLATION if violated)
- NEVER overwrite existing files without confirmation
- Agent Overrides: follow `../../core/agent-override-injector.md` before each agent dispatch
- Block comments in scaffold context go to stdout, not issue tracker
- Always generate skeleton into temp directory — move only after successful validation
- In-memory infra values from Step 01 (tracker_type, sc_remote, etc.) must be passed to all downstream steps — NEVER re-read CLAUDE.md for these values (may still contain TODO markers)
- When running full pipeline (not --no-implement): spec/ is the single source of truth for all downstream agents

---

## Infrastructure and MCP Setup

### Step 0-INFRA — Infrastructure Declaration

Collect infrastructure readiness before pipeline begins.

**If `--infra` flag was provided**, parse named-key pairs:
- `tracker:ready` or `tracker:later` — extract tracker preset (`tracker_preset`)
- `sc:ready` or `sc:later` — extract sc preset (`sc_preset`)

Old positional format detection: if `--infra ready,later` or similar positional `{tracker},{sc}` detected → emit: `"--infra format changed. Use: --infra tracker:ready,sc:later"`.

**If `--infra` not provided**, prompt user:

```
Infrastructure Declaration
--------------------------
Issue tracker available now?  [ready / later]
Source control remote set?    [ready / later]
```

Determine `tracker_effective_status` and `sc_effective_status` based on user answers or `--infra` values.

**Four valid combinations:**

| Tracker | SC | Downstream behavior |
|---------|-----|---------------------|
| ready | ready | Full integration — issues created, PRs pushed |
| ready | later | Issues created; no push |
| later | ready | Push only; no issue creation |
| later | later | Fully local — no tracker, no push |

**State persistence** — write to `state.json` via `../../core/state-manager.md`:

```json
{
  "infrastructure": {
    "tracker_status": "<tracker_effective_status>",
    "sc_status": "<sc_effective_status>",
    "tracker_type": "<tracker_type>",
    "sc_remote": "<sc_remote>"
  }
}
```

(`infrastructure.tracker_status` and `infrastructure.sc_status` stored for resume.)

**On resume:** If pipeline is resumed and `--infra` flag is provided with new values:
- Compare `tracker:` and `sc:` values from `--infra` against values in `state.json`.
- If same values (no changes) — skip re-verification.
- If tracker or sc value upgraded (later → ready) — re-run `0-MCP` to re-check MCP availability. Re-verification required: run Step 0-MCP again.
- If tracker or sc value downgraded (ready → later) — clear the related detail fields (`tracker_type`, `sc_remote`), set to null. Respect original choice; `later` → no action needed.
- If `--infra` not provided on resume — read persisted values from `state.json`; no re-check needed.

---

### Step 0-MCP — MCP Canary Write Announcement

> **Path note:** `trackers.md` lives in the plugin installation directory, not in the consuming project. Glob is used to handle CWD-context mismatch.

Resolve `{trackers_md_path}` once:
1. Glob `.claude/plugins/**/docs/reference/trackers.md` — if results, use first (prefer path containing `.claude/plugins/` or `agent-flow/`)
2. Glob `**/docs/reference/trackers.md` — use first result if step 1 found nothing
3. Use `docs/reference/trackers.md` as last resort

If not found → [WARN] "trackers.md not found — using built-in defaults for this tracker type."

**Canary write check** — Inform user (informational, no Y/n confirmation for the canary test itself):

> Running a canary write test to verify MCP server connectivity before starting pipeline...

Check `mcp_available` (follow `../../core/mcp-detection.md`).

If `mcp_available: false`:
```
MCP server unavailable. Options:
  1. Configure now — run: /agent-flow:setup-mcp --tracker-type <type> --tracker-instance <url> --sc-remote <owner/repo>
     (Equivalent: /agent-flow:init --tracker-type <type>)
     Then restart this session and resume.
  2. Skip — continue without MCP (tracker and SC steps will be skipped).
```

After "Configure now" is chosen (interactive mode only — unreachable in `--yolo`):
1. Write to state.json (atomic, `../../core/state-manager.md`):
   `{ "mcp_setup_pending": true, "mcp_pause_step": "0-MCP", "status": "paused" }`
2. Fire `pipeline-paused` webhook if `Webhook_URL` is configured and `pipeline-paused` is in `On_events`
   (follow `../../core/post-publish-hook.md` Section 4 pattern).
3. Display checkpoint: `"STOP scaffold — restart Claude Code session and resume with /agent-flow:scaffold resume"`.

If user selects Skip: continue in local-only mode. **Standard error message:**

> Cannot connect to your issue tracker or source control. Pipeline will run in local-only mode.

Follow `../../core/mcp-preflight.md` for complete MCP pre-flight protocol.

---

## Orchestration

### Step 0 — Mode Selection (Step 0: Mode Selection)

Present user with three run modes:

| Mode | Description |
|------|-------------|
| Interactive | Default: Spec Checkpoint after Step 02, Feature Plan Checkpoint after Step 04. Brainstorm offered for vague descriptions. |
| YOLO with checkpoint | Skip brainstorm; show Spec Checkpoint and Feature Plan Checkpoint but no other pauses. |
| Full YOLO | Fully autonomous: no brainstorm, no Spec checkpoint, no Feature Plan checkpoint, no user prompts. Pipeline runs to final report with zero gates. |

Apply MODE selection to `GOT_YOLO` / `GOT_STEP_MODE` logic from Mode Resolution section.

---

### --no-implement Legacy Flow

If `no_implement = true`: execute Legacy Flow (v3.x behavior).

```
L1: Step 0-INFRA (infrastructure declaration)
L2: Step 0-MCP (MCP canary write check)
L3: stack-selector agent → tech stack selection (stack-selector is a backward-compat alias)
L4: scaffolder agent → generate skeleton with stack flags (--lang, --framework, --db, --ci)
L5: Validate (build + lint)
L5b: Push to Remote if sc_effective_status = ready
L6: Report — v3.x format
```

EXIT pipeline after L6 — do not enter spec phase (spec-writer/spec-reviewer loop).

Report includes v3.x next steps:
```
Next steps:
- Create issues in your issue tracker for each feature
- Use /agent-flow:implement-feature to implement each feature
```

---

### Step 02 — Spec Write/Review Loop

Spec iterations — run spec-writer ↔ spec-reviewer loop up to 5 iterations (Spec iterations max):

```
spec-writer → spec-reviewer → [APPROVE | REVISE → back to spec-writer]
```

Loop exits on APPROVE or when max_iterations exhausted (5 iterations max). On exhaustion → Block with reason.

Dispatch spec-writer:

```
Task(subagent_type='agent-flow:spec-writer', description='Write project specification',
     prompt='...project description, context, flags...')
```

Dispatch spec-reviewer:

```
Task(subagent_type='agent-flow:spec-reviewer', description='Review project specification',
     prompt='...spec content, iteration number...')
```

Write iteration count to `state.json` via `../../core/state-manager.md`:

```json
{ "spec": { "iteration": <N>, "status": "approved" } }
```

NEEDS_CLARIFICATION — if spec-writer raises a question during spec phase:
- Write `asked_at: $asked_at` to `state.json` clarification object (follow `../../core/state-manager.md`)
- Pause pipeline and surface question to user
- Fire `pipeline-paused` webhook if configured (follow `../../core/agent-states.md`):
  ```bash
  # Fire pipeline-paused webhook
  if [ -n "${Webhook_URL:-}" ] && printf '%s' "${On_events:-}" | grep -qF 'pipeline-paused'; then
    curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
      --arg event "pipeline-paused" \
      "$Webhook_URL"
  fi
  ```
- On answer: resume with answer injected into next spec-writer prompt

**Spec Checkpoint** (Interactive and YOLO-with-checkpoint modes): show spec summary, ask "Continue to scaffolding? [Y/n]".

---

### Step 03 — Scaffold

Dispatch scaffolder agent:

```
Task(subagent_type='agent-flow:scaffolder', description='Generate project skeleton',
     prompt='...spec path, stack flags, {trackers_md_path}, mode...')
```

Validate output (build + lint). Write state:

```json
{ "scaffold": { "status": "complete", "project_dir": "<path>" } }
```

**Step 4d — Push to Remote:** If `sc_effective_status = ready`, push to `{sc_remote}`. Read defaults from `{trackers_md_path}` Source Control table.

---

### Step 4e — Create Tracker Issues

If `tracker_effective_status = ready`, create tracker issues from `spec/epics/*.md`.
Optionally dispatch `backlog-creator` agent to organize stories into sprint-ready issues.

Read tracker defaults from `{trackers_md_path}` Instance & Project Defaults table.

**Idempotency guard:** Before creating, check if issue already exists (search by title). Skip if found — use existing issue ID. (`Idempotency guard` prevents duplicate epic creation.)

For each epic file:

1. Create an epic-level issue using epic title and description.
2. Split content on `---` delimiter to identify story sections. Parse story headings: `### Story N.M: <title>`.
   - **Zero stories** edge case: if no `### Story` headings found → skip sub-issue creation for this epic.
3. For each story, create sub-issue:
   - If tracker supports native sub-issues: create as sub-issue of epic.
     (Refer to `trackers.md` Sub-Issue Capabilities table for native sub-issues support per tracker.)
   - Fallback (GitHub/Gitea): create standalone issue with title `[{epic_title}] {story_title}`.
     Add cross-reference to epic issue in story description.
4. Write back-reference comment to `spec/epics/*.md`: `<!-- {TrackerType}: {STORY-ISSUE-ID} -->`
5. Per-story failure: WARN + continue to next story.

**Story back-reference format:** `STORY-ISSUE-ID` placeholder used in back-reference writeback comment.

Optionally dispatch `backlog-creator` to organize stories into sprint-ready issues:

```
Task(subagent_type='agent-flow:backlog-creator', description='Create tracker backlog from spec epics',
     prompt='...spec/epics path, tracker_type, trackers_md_path, {trackers_md_path}...')
```

**Accumulator pattern / Partial failure handling:** Collect epic failures. On any `WARN: Could not create tracker issue`, log and continue.

After all epics, commit:
```
chore: link spec epics to tracker issues
```

**Do NOT apply the `On start set` state transition** when creating scaffold issues (backward compat).

**Display:** `Created N tracker issues (S story failures)`.

Write to `state.json`:

```json
{ "tracker_issues": { "created": <N>, "failed": <M> } }
```

---

### Step 04 — Architect

Dispatch architect agent:

```
Task(subagent_type='agent-flow:architect', description='Create feature decomposition plan',
     prompt='...spec path, tracker_effective_status, trackers_md_path, {trackers_md_path}...')
```

Decompose spec into subtasks. Each subtask maps to `maps_to: AC-{N}: {text}`.

**Feature Plan Checkpoint** (Interactive and YOLO-with-checkpoint modes): show decomposition, ask "Begin feature implementation? [Y/n]".

---

### Step 05 — Feature Implementation Loop

For each subtask in decomposition, run fixer ↔ reviewer loop:

```
Task(subagent_type='agent-flow:fixer', description='Implement feature subtask N',
     prompt='...subtask description, AC, spec path...',
     model='opus')
```

```
Task(subagent_type='agent-flow:reviewer', description='Review implementation for subtask N',
     prompt='...diff, AC, fixer output...',
     model='opus')
```

Follow `../../core/fixer-reviewer-loop.md` for iteration logic (max 5 iterations per subtask).

NEEDS_CLARIFICATION during implementation — if fixer raises a question:
- Write `asked_at: $asked_at` to `state.json` clarification object
- Pause pipeline, surface question to user
- On answer: resume fixer with answer injected

Write state per subtask:

```json
{ "fixer_reviewer": { "status": "approved", "iterations": <N>, "subtask": "<id>" } }
```

---

### Step 06 — Tests

Dispatch test-engineer:

```
Task(subagent_type='agent-flow:test-engineer', description='Run tests for scaffold pipeline',
     prompt='...project dir, test command, spec path...')
```

Write state:

```json
{ "test": { "status": "passed", "subtask": "<id>" } }
```

---

### Step 07 — Spec Compliance

Run spec-reviewer in `--verify` mode to check implementation against spec.

```
Task(subagent_type='agent-flow:spec-reviewer', description='Verify implementation against spec',
     prompt='...spec path, implementation summary, --verify mode...')
```

---

### Step 8: E2E Tests

Run test-engineer E2E suite:

```
Task(subagent_type='agent-flow:test-engineer', description='Run E2E test suite',
     prompt='...e2e framework, command, project dir...',
     model='sonnet')
```

---

### Step 8b: Close Tracker Issues

If `tracker_effective_status = ready`, close all epic and story tracker issues.

Read `On start set` Done mapping from `{trackers_md_path}` State Transition Syntax table.

If state transitions config does not include a 'Done' mapping:
→ [WARN] "State transitions config does not include a 'Done' mapping — issues left open."

For each epic issue:
- Check if any subtasks are in blocked features list. If blocked → skip with message `skipped (blocked subtasks)`.
- Transition epic issue to Done state.
- Close each story sub-issue individually for ALL tracker types (no cascade assumption).

Per-issue failure WARN: `Could not transition issue {ID} to Done: {reason}`.

Read back-reference comments from `spec/epics/*.md` to find issue IDs. Parse `<!-- {TrackerType}: {STORY-ISSUE-ID} -->` back-reference comments in spec/epics/*.md.

Guard: check `tracker_effective_status` before attempting any tracker calls. If `tracker_effective_status != ready` — skip this step; no back-reference needed.

Display: `Transitioned N issues to Done. M skipped (blocked subtasks).`

---

### Step 9: Final Report

Summarize scaffold pipeline run:

```
Scaffold complete.
- Spec: spec/ directory (README.md, architecture.md, verification.md, epics/*.md)
- Project: <project_dir>
- issues closed: <N>
- Subtasks implemented: <N>
- Branch: <branch>
```

Write final state to `state.json`:

```json
{ "pipeline": { "status": "complete", "outcome": "success" } }
```

---

### Step Z — outcome:failed Handling

If any unrecoverable error occurs (repeated test failures, block from reviewer, scaffolder failure, spec loop exhaustion):

1. Write outcome to `state.json`:
   ```json
   { "pipeline": { "status": "failed", "outcome:failed": true, "blocked_at": "<step>" } }
   ```
2. Output Block Comment to stdout:
   ```
   [agent-flow] 🔴 Pipeline Block
   Agent: scaffold
   Step: <step>
   Reason: <max 2 sentences>
   Detail: <error output>
   Recommendation: <what user should do>
   ```
3. Halt pipeline. Do NOT continue to next step.

---

## Agent Dispatch Reference

All agents dispatched via Task tool only. Model assignments per `../../core/agent-override-injector.md`:

| Agent | Model | Dispatch Form |
|-------|-------|---------------|
| spec-writer | opus | `Task(subagent_type='agent-flow:spec-writer', ...)` |
| spec-reviewer | opus | `Task(subagent_type='agent-flow:spec-reviewer', ...)` |
| scaffolder | sonnet | `Task(subagent_type='agent-flow:scaffolder', ...)` |
| architect | opus | `Task(subagent_type='agent-flow:architect', ...)` |
| fixer | opus | `Task(subagent_type='agent-flow:fixer', model='opus', ...)` |
| reviewer | opus | `Task(subagent_type='agent-flow:reviewer', model='opus', ...)` |
| test-engineer | sonnet | `Task(subagent_type='agent-flow:test-engineer', ...)` |
| backlog-creator | sonnet | `Task(subagent_type='agent-flow:backlog-creator', ...)` |

---

## Subcommand: add <component>

Activated when the first token of `$ARGUMENTS` is `add` (see Step 0 — Subcommand dispatch at the top of this file). Adds a single component (`claude-md` | `ci` | `docker` | `tests`) to an existing project. Single-shot — no resume detection, no spec phase, no architect, no fixer/reviewer loop.

Input: `$COMPONENT` = component name validated by Step 0 dispatch (one of `claude-md` | `ci` | `docker` | `tests`).

### Supported components

| Component | What it generates | Agent |
|-----------|-------------------|-------|
| `claude-md` | CLAUDE.md with Automation Config | scaffolder |
| `ci` | CI/CD config (.gitea/workflows/ or .github/workflows/) | scaffolder |
| `docker` | Dockerfile + .dockerignore + docker-compose.yml | scaffolder |
| `tests` | Test setup (test config + 1 smoke test) | scaffolder |

### 0. MCP pre-flight check

Before any pipeline operation, verify MCP tool availability:
- Read Type from Automation Config (Issue Tracker section)
- Check that at least one `mcp__*` tool matching the tracker type is accessible
- If not accessible → STOP with: "Cannot connect to your {Type} issue tracker. Is the {Type} integration configured? Run `/agent-flow:check-setup` for diagnostics."

### Orchestration

#### 1. Argument validation

The Step 0 dispatch already validated `$COMPONENT` against the supported list (`claude-md` | `ci` | `docker` | `tests`). If reached here, `$COMPONENT` is one of the valid values.

#### 2. Auto-detect tech stack

Detect the existing tech stack from project files:
- `pyproject.toml` / `setup.py` → Python
- `package.json` → Node.js/TypeScript
- `go.mod` → Go
- `Cargo.toml` → Rust
- `*.csproj` / `*.sln` → .NET
- `pom.xml` / `build.gradle` → Java

If detection fails → ask the user.

Detect framework from imports and dependencies:
- FastAPI, Flask, Django (Python)
- Express, Nest, Next.js (Node.js)
- Gin, Echo, Fiber (Go)

#### 3. Confirmation

Display: "Detected stack: {language} + {framework}. Generating {component}. Continue? [Y/n]"

#### 4. Generation

You MUST invoke `Task(subagent_type='agent-flow:scaffolder', model='sonnet')`. DO NOT inline-execute.
- Context: detected stack + requested component (`$COMPONENT`)
- Scaffolder generates ONLY the requested component

#### 5. Validation

Verify that newly generated files did not break the build:
- Run build command (if it exists in CLAUDE.md or from auto-detect)
- Run test command (if it exists)
- If Build/Test command does not exist, at least verify syntactic validity of generated configuration files (JSON/YAML parsing).

#### 6. Report

Display the list of generated files and next steps.

EXIT after step 6. The subcommand branch MUST NOT fall through to the new-project flow.

### Subcommand Rules

- Never overwrite existing files without confirmation
- For `claude-md`: if CLAUDE.md already exists → ask whether to overwrite or merge
- Auto-detect looks in root first, then one level of subdirectories
- If multiple matches (mixed-language repo) → ask the user for the primary stack
