---
name: fix-bugs
description: Run the fix pipeline on a single ticket OR a batch -- auto-resumes from checkpoint if state exists
allowed-tools: mcp__*, Bash, Read, Write, Edit, Glob, Grep, Task
disable-model-invocation: true
argument-hint: "[<ISSUE-ID> | --batch <N>] [--dry-run] [--yolo] [--step-mode] [--profile <name>] [--decompose] [--no-decompose] [--clarification \"<text>\"]"
---

# /fix-bugs — Auto-fix Bug Tickets

Use the Read tool to load `skills/fix-bugs/data/guard-block.md` BEFORE any other instruction
in this file. The guard is load-bearing; it establishes the orchestrator role, blocks
pre-dispatch deferrals, and contains the rationalization-red-flags STOP protocol.

<stage_allowlist>
required: [triage, code_analysis, fixer_reviewer, smoke_check, test, publisher]
optional: [reproduce_browser, e2e_test, browser_verification, acceptance_gate]
</stage_allowlist>

You are a THIN CONTROLLER. You:
- Read state from disk (`.agent-flow/{ISSUE-ID}/state.json`)
- Follow deterministic decision logic (this document + step files)
- Dispatch fresh subagents via the Task tool (one per step)
- Write atomic state.json updates (including `dispatched_at` + `dispatch_witness` BEFORE each Task)

You do NOT:
- Reason about the bug domain (subagents do that)
- Inline-execute step logic
- Carry conversation history across steps
- Make quality judgments (reviewers do that)

## Overview

This skill runs in two modes, auto-detected from `$ARGUMENTS`:

- **Single-ticket mode** — `<ISSUE-ID>` positional → full pipeline on the named issue, in CWD (no worktree).
- **Batch mode** — `--batch <N>` (or bare integer on string trackers) → query the tracker for N bugs and dispatch the single-ticket pipeline per issue, with the existing worktree / sequential-CWD logic.

Mode is determined automatically (see Step 0a). Resume detection runs immediately after argument parsing for both modes.

## Step 0a — Argument auto-detection (tracker-type-aware)

Strip flags first, then classify the surviving positional. The first non-flag token wins as `POSITIONAL`. Mode (`single` vs `batch`) is decided AFTER all flags are consumed.

```bash
GOT_BATCH=false; BATCH_N=""; POSITIONAL=""; DRY_RUN=false
GOT_YOLO=false; GOT_STEP_MODE=false; GOT_DECOMPOSE=false; GOT_NO_DECOMPOSE=false
PROFILE_NAME=""; CLARIFICATION_TEXT=""
read -ra ARG_TOKENS <<< "$ARGUMENTS"
# Recognized flag tokens — used as stop-markers when reconstructing multi-word values below.
KNOWN_FLAG_RE='^(--batch|--dry-run|--yolo|--step-mode|--decompose|--no-decompose|--profile|--clarification)$'
i=0
while [ $i -lt ${#ARG_TOKENS[@]} ]; do
  tok="${ARG_TOKENS[$i]}"
  case "$tok" in
    --batch)         GOT_BATCH=true; i=$((i+1)); BATCH_N="${ARG_TOKENS[$i]}" ;;
    --dry-run)       DRY_RUN=true ;;
    --yolo)          GOT_YOLO=true ;;
    --step-mode)     GOT_STEP_MODE=true ;;
    --decompose)     GOT_DECOMPOSE=true ;;
    --no-decompose)  GOT_NO_DECOMPOSE=true ;;
    --profile)
      # `read -ra` already split the shell-quoted "<name>" into separate tokens, so a
      # multi-word profile name must be rejoined here rather than read as one array slot.
      i=$((i+1)); PROFILE_NAME=""
      while [ $i -lt ${#ARG_TOKENS[@]} ] && [[ ! "${ARG_TOKENS[$i]}" =~ $KNOWN_FLAG_RE ]]; do
        PROFILE_NAME="${PROFILE_NAME:+$PROFILE_NAME }${ARG_TOKENS[$i]}"
        i=$((i+1))
      done
      i=$((i-1)) # outer loop's `i=$((i+1))` advances past the last consumed token
      ;;
    --clarification)
      # Same reconstruction as --profile: consume tokens up to the next recognized flag
      # (or end-of-array) and rejoin with single spaces. KNOWN LIMITATION: if the answer text
      # itself contains a substring matching a recognized flag (e.g. "use --yolo instead"),
      # reconstruction stops early at that token. Prefer short, flag-free clarification text.
      i=$((i+1)); CLARIFICATION_TEXT=""
      while [ $i -lt ${#ARG_TOKENS[@]} ] && [[ ! "${ARG_TOKENS[$i]}" =~ $KNOWN_FLAG_RE ]]; do
        CLARIFICATION_TEXT="${CLARIFICATION_TEXT:+$CLARIFICATION_TEXT }${ARG_TOKENS[$i]}"
        i=$((i+1))
      done
      i=$((i-1))
      ;;
    --*) ;;
    *) [ -z "$POSITIONAL" ] && POSITIONAL="$tok" ;;
  esac
  i=$((i+1))
done

if $GOT_YOLO && $GOT_STEP_MODE; then echo "[ERROR] --yolo and --step-mode are mutually exclusive" >&2; exit 1; fi
if $GOT_DECOMPOSE && $GOT_NO_DECOMPOSE; then echo "[ERROR] --decompose and --no-decompose are mutually exclusive" >&2; exit 1; fi

# Tracker-type-aware disambiguation: read Type from CLAUDE.md Issue Tracker section.
# String trackers (youtrack|jira|linear): bare integer = batch count. Numeric trackers
# (github|gitea|redmine): bare integer = single ISSUE_ID.
if $GOT_BATCH; then
  [[ "$BATCH_N" =~ ^[1-9][0-9]*$ ]] || { echo "[ERROR] --batch requires a positive integer count, got: ${BATCH_N}" >&2; exit 1; }
  MODE="batch"; N="$BATCH_N"
elif [ -z "$POSITIONAL" ]; then
  echo "[ERROR] Usage: /agent-flow:fix-bugs <ISSUE-ID> | --batch <N>" >&2; exit 1
else
  TRACKER_TYPE="$(grep -oE '^\| Type \| [A-Za-z][A-Za-z0-9_-]+' CLAUDE.md | head -1 | awk -F'| ' '{print $3}' | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
  if [ -z "$TRACKER_TYPE" ]; then
    echo "[WARN] Tracker type not detected; assuming string-tracker semantics (youtrack)" >&2
    TRACKER_TYPE="youtrack"
  fi
  # ISSUE-ID format: ^[A-Za-z][A-Za-z0-9_-]*-[0-9]+$ — always single regardless of tracker.
  if [[ "$POSITIONAL" =~ ^[A-Za-z][A-Za-z0-9_-]*-[0-9]+$ ]]; then
    MODE="single"; ISSUE_ID="$POSITIONAL"
  elif [[ "$POSITIONAL" =~ ^[0-9]+$ ]]; then
    case "$TRACKER_TYPE" in
      github|gitea|redmine) MODE="single"; ISSUE_ID="$POSITIONAL" ;;
      youtrack|jira|linear)
        echo "[WARN] Treating bare integer '$POSITIONAL' as batch count for $TRACKER_TYPE (string-tracker)" >&2
        MODE="batch"; N="$POSITIONAL" ;;
      *)
        echo "[WARN] Treating bare integer '$POSITIONAL' as batch count for unknown tracker" >&2
        MODE="batch"; N="$POSITIONAL" ;;
    esac
  else
    MODE="single"; ISSUE_ID="$POSITIONAL"
  fi
fi
```

Legacy flat `.agent-flow/state.json` → log `[WARN]` and continue with the new per-issue path scheme.

## Step 0b — Resume detection

Follow `../../core/resume-detection.md` for resume detection logic. Inputs: `ISSUE_ID` (single) or
`BATCH_RUN_ID="batch-{timestamp}"` (batch); `MODE`, `GOT_YOLO`, `GOT_STEP_MODE`, `Webhook_URL`,
`On_events`, `CLARIFICATION_TEXT`. Outputs: `RESUME_POINT`, `RESTORED_CONTEXT`, `PIPELINE_TYPE`.

If `RESUME_POINT == "FRESH"`, proceed with Step 1 below. Otherwise skip ahead per the BUG resume
mapping in `../../core/resume-detection.md`. Batch-mode invokes per-issue resume inside the per-issue
loop, so the outer batch run does not skip ahead.

**Webhook events beyond the base 5:** this skill's own NEEDS_CLARIFICATION handling (see
steps/01-triage.md and steps/04-fixer-reviewer-loop.md) fires `pipeline-paused`, and
`../../core/resume-detection.md` Step 9 fires `pipeline-resumed` on the next resumed invocation —
both gated on `Webhook_URL` being set and the matching token present in `On events`, same as every
other webhook call site. These two tokens are additive to the 5 tokens CLAUDE.md's `### Notifications`
reference table currently enumerates (`pr-created`, `issue-blocked`, `pipeline-started`,
`step-completed`, `pipeline-completed`). Add `pipeline-paused` and `pipeline-resumed` to your
project's `On events` list to receive clarification pause/resume notifications from this pipeline.

## Mode flag semantics

- Default (neither `--yolo` nor `--step-mode`): supervised — runs all steps, including step 11
  (publish), pauses only on NEEDS_CLARIFICATION. There is no separate human publish-confirmation
  gate in default mode; the pipeline completes end-to-end unattended once dispatched.
- `--yolo`: zero gates, autonomous run to PR — auto-approve decomposition, auto-publish.
- `--step-mode`: pause after each step for human review, including a confirmation prompt before
  step 11 dispatches — mutually exclusive with `--yolo`. Use this flag when a human
  publish-review gate is desired.

## Configuration

Read from `## Automation Config` in CLAUDE.md per `../../core/config-reader.md`. Required sections:
Issue Tracker, Source Control, PR Rules, Build & Test, PR Description Template. Optional:
Retry Limits, Module Docs, Hooks, Custom Agents, Notifications, Worktrees, Decomposition,
Error Handling, Agent Overrides, Local Deployment, Browser Verification, Pipeline Profiles,
Pause Limits, E2E Test. See `docs/reference/automation-config.md` for the full key contract.

Pipeline profile parsing: follow `../../core/profile-parser.md`. Stage names eligible for skip:
`triage`, `analyst-impact`, `test-engineer`, `test-engineer-e2e`, `browser-agent-reproduce`,
`browser-agent-verify`. NEVER skip: `fixer`, `reviewer`, `publisher` (these stages CANNOT be skipped).

## Architecture freshness (advisory)

<!-- @snippet:architecture-freshness -->

Before fixer dispatch, run the canonical architecture freshness check from
`core/snippets/architecture-freshness.md`. Advisory only, non-blocking.

## Worktree / batch processing

If `MODE = batch`:
- If `Worktrees` config exists → parallel (batch_size, base_path, cleanup).
- Else → sequential CWD.
- Outer loop: query the tracker for N bugs via `Bug query` from Automation Config.
- For each ticket: write per-issue `.agent-flow/{ISSUE-ID}/state.json`, then execute the
  dispatch table below per-issue.
- "Parallel" means concurrent `Task()` dispatch of per-ticket pipelines only — per-issue
  `state.json` writes stay inside each ticket's own directory (no cross-ticket sharing, per
  `../../core/state-manager.md`). The batch-level summary below, by contrast, IS shared across
  tickets; this orchestrator (not any dispatched subagent) is its sole writer, folding each
  ticket's result in sequentially as that ticket's `Task()` call returns, via the standard
  atomic tmp+rename write. Single-writer-by-construction means no additional file-level locking
  is required for the summary file either, even under parallel worktree dispatch.
- Maintain a batch-level summary at `.agent-flow/batch-{timestamp}/state.json` with
  `pipeline_type: "bug_fix_batch"`, `processed[]`, `succeeded[]`, `blocked[]`.
- On block: increment `block_count`. If `Max blocked per run` reached → skip remaining bugs.

## Step Dispatch

Execute the steps below in order. Each row corresponds to one step file under
`skills/fix-bugs/steps/`. Use the Read tool to load each step file's full instructions
BEFORE invoking its Task() dispatch. Skipping a step requires explicit `status="skipped"`
in `state.json` — never leave a stage at `"pending"` after the step's turn passes.

| Step | File                                       | Description                                            |
|------|--------------------------------------------|--------------------------------------------------------|
| 00   | (orchestrator) MCP pre-flight + state init | Follow `../../core/mcp-preflight.md`, validate issue_id, create `.agent-flow/{ISSUE-ID}/state.json`, set tracker state per `On start set`, self-assign, create branch, fire `pipeline-started` webhook |
| 01   | steps/01-triage.md                         | analyst --phase triage                                 |
| 02   | steps/02-impact.md                         | analyst --phase impact + decomposition decision        |
| 03   | steps/03-reproduce.md                      | browser-agent --phase reproduce (config-gated)         |
| 04   | steps/04-fixer-reviewer-loop.md            | fixer ↔ reviewer iteration loop                        |
| 05   | steps/05-smoke.md                          | smoke build + test (post-fix infrastructure)           |
| 06   | steps/06-test.md                           | test-engineer                                          |
| 07   | steps/07-e2e.md                            | test-engineer --e2e (config-gated)                     |
| 08   | steps/08-browser-verify.md                 | browser-agent --phase verify (config-gated)            |
| 09   | steps/09-acceptance-gate.md                | acceptance-gate (AC ≥ 3 or complexity ≥ M)             |
| 10   | steps/10-pre-publish.md                    | pre-publish hook + custom agent                        |
| 11   | steps/11-publish.md                        | publisher + post-publish hook + fix-verification       |
| 12   | steps/12-result.md                         | terminal report + dispatch-audit surfacing             |

For each step you SHALL invoke the Task tool with the `subagent_type` listed in the corresponding
step file. Before invoking Task, you SHALL write atomically to `state.json` under
`stages.<stage>`:
- `dispatched_at`   = ISO-8601 UTC now
- `dispatch_witness` = sha256("<subagent_type>|<model>|<prompt_head_128>") via
  `core/lib/stage-invariant.sh::compute_dispatch_witness`
- `agent_name`      = `<subagent_type>`
- `stage_name`      = `<canonical stage name>` (per the step file)
- `status`          = `"in_progress"`

You SHALL also inject `EXPECTED_AGENT_NAME` and `EXPECTED_STAGE_NAME` as Tier-1 variables in the
agent prompt.

## Step override resolution (Agent Overrides)

Before each Task dispatch, apply Agent Overrides per `../../core/agent-override-injector.md` (.toml
primary). Applies to both single and batch mode.

**Step file override (not yet implemented):** replacing individual step files via
`customization/steps/fix-bugs/{NN}-{name}.md` is not currently supported by any shipped version.
See TOML overlay documentation for current customization options.

## `--step-mode` prompt

After each step completes (before dispatching the next), if `$GOT_STEP_MODE=true`:
pause and display step result summary, present
`[step-mode] Step {NN}/12 completed: {step-name}` and prompt
`Continue / Skip remaining gates / Abort? [c/s/a]:` (re-prompt on empty input).

State machine:
- `c` / `continue` → proceed to next step.
- `s` / `skip`     → switch MODE to yolo for remaining steps; log
  `[INFO] step-mode escape: switched to yolo for remaining steps`.
- `a` / `abort`    → write `state.json` (`pause_reason=step_mode_abort`,
  `last_completed_step`, `outcome=paused`, `paused_at=ISO8601`) then exit 0
  (graceful pause — not an error exit).

## Dry-run mode

If `--dry-run` is active: run only Step 00 (without tracker writes), 01 (triage),
and 02 (impact), then emit a dry-run report (severity, area, risk, affected files,
complexity, AC count) and exit. No side effects, no PR, no state mutations to the tracker.

## Block handler (step X)

When any step blocks the pipeline (see `../../core/mcp-body-formatting.md` for the MCP comment-body formatting contract — applies to every tracker comment this pipeline posts):
1. Follow `../../core/block-handler.md` for the block protocol (comment template, tracker write).
2. Step 12's pipeline accumulator runs (`pipeline.total_tokens`, summary table).
3. Set top-level `status = "blocked"`, write `block` object atomically to state.json.
4. On block from fixer/reviewer/test-engineer: dispatch the rollback-agent per
   `../../core/block-handler.md` rollback section (Task tool, haiku model, witness write
   + EXPECTED_* variables — same dispatch contract as every step file).
5. Step 12 fires `pipeline-completed` with `"outcome":"blocked"`, `"pr_url":null`.
6. Batch mode: increment `block_count`; if `Max blocked per run` reached, skip remaining bugs.

## Summary (batch mode)

After all bugs processed (batch only): emit a structured table
(Bug ID / Summary / Status / PR / Block reason) plus
`{N_fixed} fixed, {N_blocked} blocked, {N_dup} duplicates` and a token-usage estimate.

## Rules

- Single mode: work in CWD — no worktrees.
- Batch mode: worktree behavior follows the Worktrees config (parallel) or sequential CWD.
- Publisher (step 11) runs automatically at the end of every non-paused, non-blocked run — this
  is true in default mode as well as `--yolo` (see "## Mode flag semantics"). To gate publish on
  a human decision, invoke with `--step-mode`.
- Block Comment Template is passed to agents as context instructions.
- Retry limits are passed to agents as context instructions.
- Hooks fire before/after their respective agent steps, NOT inside the reviewer loop.
- Custom agents are one-shot gates.
- Follow `../../core/agent-override-injector.md` for loading project-specific agent customizations.
- On error → Block handler + inform the user.

For step-level dispatch detail, pre/post-state writes, hook invocations, NEEDS_CLARIFICATION
handling, decomposition orchestration, and webhook payloads, refer to the individual files
listed in the Step Dispatch table above.
