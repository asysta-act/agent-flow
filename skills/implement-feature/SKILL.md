---
name: implement-feature
description: Implements a feature from the issue tracker -- spec, design, fix, review, test, publish
allowed-tools: mcp__*, Bash, Read, Write, Edit, Glob, Grep, Task
disable-model-invocation: true
argument-hint: "<ISSUE-ID> | --description \"<text>\" [--decompose] [--no-decompose] [--decompose-only] [--dry-run] [--profile <name>] [--yolo] [--step-mode] [--clarification \"<text>\"]"
---

# /implement-feature

Read and apply the mandatory execution guard defined in `skills/implement-feature/data/guard-block.md` BEFORE any other instruction in this file.

<stage_allowlist>
required: code_analysis, fixer_reviewer, test, publisher
optional: smoke_check, acceptance_gate
</stage_allowlist>

You are a THIN CONTROLLER. Implement feature `$ARGUMENTS` from the issue tracker by dispatching specialist subagents via the Task tool. NEVER inline agent logic. Read `## Automation Config` from CLAUDE.md.

## Mode flag parsing

```bash
GOT_YOLO=false ; GOT_STEP_MODE=false
[[ "$ARGUMENTS" == *"--yolo"* ]]      && GOT_YOLO=true
[[ "$ARGUMENTS" == *"--step-mode"* ]] && GOT_STEP_MODE=true
$GOT_YOLO && $GOT_STEP_MODE && { echo "[ERROR] Flags --yolo and --step-mode are mutually exclusive" >&2; exit 1; }
```

Additional flags parsed from `$ARGUMENTS`:

- `--decompose` → `decompose_mode = FORCE` ; `--no-decompose` → `DISABLED` ; neither → `AUTO`
- `--decompose-only` → `decompose_only_mode = true` (implies FORCE; mutually exclusive with `--no-decompose`)
- `--description "<text>"` → `description_mode = true`; mutually exclusive with Issue ID
- `--dry-run` → execute steps 01-02 only, display report, no side effects
- `--clarification "<text>"` → `CLARIFICATION_TEXT = "<text>"`; passed to `../../core/resume-detection.md`

Mode semantics: default = supervised autopilot (pauses only on `NEEDS_CLARIFICATION`); `--yolo` = zero gates to PR; `--step-mode` = pause after each step (`c` continue / `s` skip / `a` abort).

## Configuration

Follow `../../core/config-reader.md`. Required sections: `Issue Tracker` (Type, State transitions, On start set), `Feature Workflow` (Feature query, On start set), `Source Control` (Remote, Base branch, Branch naming), `PR Rules` (Labels), `PR Description Template`, `Build & Test` (Build, Test, Verify commands), `Retry Limits`, `Module Docs`, `Hooks`, `Custom Agents`, `Notifications`, `Decomposition`, `Error Handling`, `Agent Overrides`, `Local Deployment`, `Pipeline Profiles`. Full key list in `docs/reference/automation-config.md`.

## MCP pre-flight

Follow `../../core/mcp-preflight.md`. In `--description` + `--yolo` mode: BLOCK with context-specific error (cannot create tracker card; no interactive fallback). Otherwise STOP with setup guidance.

If the MCP server is unavailable, display: `Cannot connect to your issue tracker — MCP server unavailable. Please configure with /agent-flow:setup-mcp before retrying.`

### Step 0b: Config Validity Gate

Scan Automation Config required sections for `<!-- TODO:` and `<...>` placeholders; block if incomplete. Canonical logic mirrored in `skills/fix-bugs/SKILL.md` Step 0b.

See `../../core/mcp-body-formatting.md` for newline-handling in MCP comment bodies.

## Issue-ID validation (path-traversal defense)

```bash
if [[ ! "${ISSUE_ID}" =~ ^[A-Za-z0-9#._-]+$ || "${ISSUE_ID}" =~ ^\.+$ ]]; then
  echo "[BLOCK] Invalid issue_id: ${ISSUE_ID}" >&2; exit 1
fi
```

## Pipeline profile parsing

Follow `../../core/profile-parser.md`. Valid stage names: `spec-analyst`, `analyst-impact`, `test-engineer`, `test-engineer-e2e`. NEVER skip: `fixer`, `reviewer`, `publisher`.

## Resume detection

Follow `../../core/resume-detection.md`. Inputs: `ISSUE_ID`, `MODE`, `GOT_YOLO`, `GOT_STEP_MODE`, `Webhook_URL`, `On_events`, `CLARIFICATION_TEXT`. Outputs: `RESUME_POINT`, `RESTORED_CONTEXT`, `PIPELINE_TYPE`.

If `RESUME_POINT == "FRESH"`, run the dispatch table below from step 01. Otherwise jump to the corresponding step per the FEATURE pipeline mapping in `../../core/resume-detection.md` Step 6.

## Init (state + run_id + start webhook)

After resume detection (when `RESUME_POINT == "FRESH"`):

1. Create `.agent-flow/{ISSUE_ID}/` and initialize `state.json` via `../../core/state-manager.md` — top-level `status = "running"`, `pipeline = "implement-feature"`, `mode = "feature"`, empty `stages = {}` map, `run_id = <uuid>`.
2. Check out the working branch per `Branch naming` in `Source Control` config.
3. Fire `pipeline-started` webhook if configured (see `../../core/agent-states.md`).
4. Apply `Issue Tracker → On start set` transition to the issue (state + implicit self-assign — same protocol as `skills/fix-bugs/SKILL.md` Step 1).

## Step dispatch

Use the Read tool to load each step file below in order. Each step file specifies the subagent to dispatch, the prompt template, the pre-dispatch overlay resolution (Agent Override Injector → `overlay_source` + rendered block), the pre-dispatch atomic state.json write (`dispatched_at`, `agent_name`, `stage_name`, `prompt_head_128`, `overlay_source`, `overlay_digest`, `dispatch_witness`, `status="in_progress"` per `core/lib/stage-invariant.sh`), and the post-dispatch state finalization. The overlay is resolved BEFORE the witness so the receipt binds the overlay actually applied. Step files own ALL dispatch logic; this controller only sequences and merges output.

| # | Step file | Stage (state.json) | Subagent | Model |
|---|-----------|--------------------|----------|-------|
| 01 | `skills/implement-feature/steps/01-spec.md` | `spec_analysis` + `code_analysis` | `spec-analyst`, then `analyst --phase impact` | sonnet |
| 02 | `skills/implement-feature/steps/02-architect.md` | `code_analysis` (architect output) | `architect` | opus |
| 03 | `skills/implement-feature/steps/03-decomposition.md` | `decomposition` | (no dispatch — heuristic + tracker subtask creation; may dispatch `backlog-creator`) | sonnet (if dispatched) |
| 04 | `skills/implement-feature/steps/04-fixer-reviewer-loop.md` | `fixer_reviewer` | `fixer` ↔ `reviewer` loop | opus |
| 05 | `skills/implement-feature/steps/05-smoke.md` | `smoke_check` | (no dispatch — Build + Test commands) | n/a |
| 06 | `skills/implement-feature/steps/06-test.md` | `test` (+ optional `e2e_test`) | `test-engineer` (and `test-engineer --e2e`) | sonnet |
| 07 | `skills/implement-feature/steps/07-acceptance-gate.md` | `acceptance_gate` | `acceptance-gate` (conditional) | sonnet |
| 08 | `skills/implement-feature/steps/08-publish.md` | `publisher` | `publisher` + terminal dispatch-audit surface | haiku |

Use the Read tool to load `skills/implement-feature/steps/01-spec.md` and execute it before step 02; repeat for each row of the table in order. Each step file's pre-dispatch write block consumes the canonical stage name listed in column 3 (binds to the 6-arg `core/lib/stage-invariant.sh::compute_dispatch_witness STAGE SUBAGENT_TYPE MODEL PROMPT_HEAD_128 OVERLAY_SOURCE OVERLAY_DIGEST`, with `overlay_digest` produced by `compute_overlay_digest`).

Optional and conditional stages (`smoke_check` step 05, `acceptance_gate` step 07, `e2e_test` inside step 06) MUST write an explicit `status = "skipped"` to `state.json` when their config-gate evaluates negatively — never leave the stage at `pending` (alarm-fatigue protection: the terminal report in step 08 distinguishes WITNESS_MISSING on an OPTIONAL stage as `EXPECTED_OPTIONAL_NOT_RUN`, not an anomaly).

The orchestrator MUST inject `EXPECTED_AGENT_NAME` and `EXPECTED_STAGE_NAME` as Tier-1 prompt variables on every dispatch so subagents can cross-verify their `## Step Completion Invariants` section against state.json.

## Default mode checkpoints

In default mode (no `--yolo`, no `--step-mode`):

- **Spec Checkpoint** after step 01: display spec + AC summary; ask the user to confirm or revise before architect runs.
- **Decomposition Approval** checkpoint after step 02: show architect task tree + AC coverage; user approves before fixer loop starts.

`--yolo` skips both checkpoints and runs fully autonomous to PR. `--step-mode` prompts `[step-mode] Step NN/08 completed. Continue? [c/s/a]` after every step — see `../../core/resume-detection.md` for `a` (abort) handling.

## Decomposition specifics

Full decomposition logic — AC coverage check, task-tree validation, tracker subtask creation, `--decompose-only` exit — lives in `skills/implement-feature/steps/03-decomposition.md`. The controller never inlines decomposition heuristics.

## --dry-run path

If `$ARGUMENTS` contains `--dry-run`: execute steps 01 and 02 only, display the spec summary + architect task tree, then EXIT without dispatching fixer/reviewer/test/publisher. No tracker writes, no git commits, no PR.

## Agent overrides + step-mode prompt

Before EVERY Task dispatch, follow `../../core/agent-override-injector.md` for TOML override loading and prompt injection (handled inside each step file — the controller never re-implements override loading).

After each step completes, if `$GOT_STEP_MODE == true`: pause and display step-result summary, prompt `[step-mode] Step NN/08 completed. Continue? [c/s/a]`. `c` = continue; `s` = skip next step (write `status = "skipped"` to next stage's state.json record before resuming); `a` = abort (write `status = "paused"` and `last_completed_step` to state.json; exit 0; resume by re-invoking `/agent-flow:implement-feature <ISSUE-ID>`).

**Near-miss WARN**: if a file exists at `customization/steps/implement-feature/{NN}-*.md` that does NOT match any of the 8 canonical step filenames, log `[WARN] Unrecognized step override file: {filename}` and continue.

## Block handler

Follow `../../core/block-handler.md`. On `fixer` / `reviewer` / `test-engineer` block → dispatch `rollback-agent` (haiku) to revert git state. Block comment format: `[agent-flow]` prefix per CLAUDE.md "Block Comment Template". Write to state.json: `status = "blocked"`, `outcome = "failed"`, `block = {...}` per `../../core/state-manager.md` atomic write protocol. Pipeline halts cleanly with `exit 0` (graceful block).

## Architecture freshness check (advisory)

Advisory pre-architect warning — does not block dispatch:

```bash
last_commit=$(git log -1 --format="%H" -- docs/architecture.md 2>/dev/null)
if [ -n "$last_commit" ]; then
  commits_since=$(git rev-list HEAD ^"$last_commit" --count 2>/dev/null || echo 0)
  [ "$commits_since" -ge 25 ] && echo "[WARN] docs/architecture.md has not been updated in ${commits_since} commits (threshold: 25)."
fi
```

## Step detail files

All eight step files live in `skills/implement-feature/steps/`. Each owns its full dispatch prose, pre-dispatch witness write, post-dispatch state finalization, and webhook firing. This controller is structurally bound by the `<stage_allowlist>` block above — Area D terminal surfacing in step 08 reads that block to classify audit-log anomalies.
