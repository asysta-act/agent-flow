---
name: analyze-bug
description: Analyzes a specific bug from the issue tracker (analysis only, no code changes)
allowed-tools: mcp__*, Read, Glob, Grep, Task
argument-hint: "<ISSUE-ID>"
---

# Analyze Bug

Analyze bug $ARGUMENTS. Read config from `.agent-flow/config.toml` (resolved by `../../core/config-reader.md`).

This is a stateless, single-shot analysis surface, not a resumable pipeline: it never creates or updates `.agent-flow/{ISSUE-ID}/state.json` (that path is reserved for `/agent-flow:fix-bugs` runs on the same issue, and reused by its resume-detection). Before each analyst dispatch below, it writes only the minimal pre-dispatch fields the analyst's Step Completion Invariants require (`dispatched_at`, `dispatch_witness`, `status`, `stage_name`, `agent_name`) to a dedicated ephemeral file, `.agent-flow/{ISSUE-ID}/analyze-bug-state.json`, using the "orchestrator-injected state path" allowance in `agents/analyst.md`'s Step Completion Invariants. This stub carries no `pipeline`/`config`/`infrastructure` accumulator fields (contrast `state/schema.md`) and is never read by resume-detection.

### 0. MCP pre-flight check

Before any pipeline operation, verify MCP tool availability:
- Read `issue_tracker.type` from `.agent-flow/config.toml`
- Check that at least one `mcp__*` tool matching the tracker type is accessible
- If not accessible → STOP with: "Cannot connect to your {Type} issue tracker. Is the {Type} integration configured? Run `/agent-flow:check-setup` for diagnostics."

## Steps

1. If `$ARGUMENTS` is empty, display: "Usage: /agent-flow:analyze-bug <ISSUE-ID>" and stop.
2. Verify that `.agent-flow/config.toml` exists and contains an `[issue_tracker]` section. If not, report an error and stop.
3. Read issue content (title, description, comments) from the issue tracker via MCP. When passing this content to any agent, follow `../../core/external-input-sanitizer.md`: wrap each piece of external content in `--- EXTERNAL INPUT START ---` / `--- EXTERNAL INPUT END ---` markers.
   Before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for analyst overrides.
   Before dispatching, write pre-dispatch fields to `.agent-flow/{ISSUE-ID}/analyze-bug-state.json`:
   - `triage.dispatched_at` = current ISO-8601 UTC timestamp
   - `triage.model` = `"sonnet"`
   - `triage.status` = `"in_progress"`
   - `triage.agent_name` = `"agent-flow:analyst"`
   - `triage.stage_name` = `"triage"`
   - `triage.dispatch_witness` = sha256("agent-flow:analyst|sonnet|<prompt_head_128>") (compute via `core/lib/stage-invariant.sh::compute_dispatch_witness`; `prompt_head_128` is the first 128 UTF-8-safe bytes of the un-expanded prompt template, BEFORE Tier-1 variable expansion)

   Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:analyst"`, `EXPECTED_STAGE_NAME = "triage"`, `STATE_PATH = ".agent-flow/{ISSUE-ID}/analyze-bug-state.json"`. `STATE_PATH` is the orchestrator-injected state path referenced by `agents/analyst.md`'s Step Completion Invariants — it tells the dispatched analyst to read/verify invariants 1-3 against this skill's ephemeral stub instead of the literal default `.agent-flow/{ISSUE-ID}/state.json`.

   You MUST invoke `Task(subagent_type='agent-flow:analyst', model='sonnet')` with `--phase triage` on bug $ARGUMENTS. DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

   The analyst posts its own triage checkpoint comment to the issue tracker automatically, as part of its Process (see `agents/analyst.md` Process — Phase: triage, step 11 for the exact format). Do not duplicate that format string here with a separate instruction — an earlier, differently-worded copy of it in this file is what let the two versions drift out of sync.
3a. If triage output contains `## NEEDS_CLARIFICATION` (interactive surface — no persisted/resumable pipeline state; the step 3 ephemeral state stub above is dispatch-witness bookkeeping only, not a resume checkpoint):
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
4. If triage OK: before dispatch, check Agent Overrides: follow `../../core/agent-override-injector.md` for analyst overrides.
   Before dispatching, write pre-dispatch fields to `.agent-flow/{ISSUE-ID}/analyze-bug-state.json` (overwriting the step 3 stub):
   - `code_analysis.dispatched_at` = current ISO-8601 UTC timestamp
   - `code_analysis.model` = `"sonnet"`
   - `code_analysis.status` = `"in_progress"`
   - `code_analysis.agent_name` = `"agent-flow:analyst"`
   - `code_analysis.stage_name` = `"code_analysis"`
   - `code_analysis.dispatch_witness` = sha256("agent-flow:analyst|sonnet|<prompt_head_128>") (recomputed for this phase's prompt via `core/lib/stage-invariant.sh::compute_dispatch_witness`)

   Inject Tier-1 variables: `EXPECTED_AGENT_NAME = "agent-flow:analyst"`, `EXPECTED_STAGE_NAME = "code_analysis"`, `STATE_PATH = ".agent-flow/{ISSUE-ID}/analyze-bug-state.json"`. `STATE_PATH` is the orchestrator-injected state path referenced by `agents/analyst.md`'s Step Completion Invariants — it tells the dispatched analyst to read/verify invariants 1-3 against this skill's ephemeral stub instead of the literal default `.agent-flow/{ISSUE-ID}/state.json`.

   You MUST invoke `Task(subagent_type='agent-flow:analyst', model='sonnet')` with `--phase impact`. DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator.

   Context for the agent:
   ```
   --phase impact. Module Docs path = {Path from Module Docs config, or "none"}.
   Triage output: {full step-3 triage output for this bug}.
   EXPECTED_AGENT_NAME = agent-flow:analyst
   EXPECTED_STAGE_NAME = code_analysis
   STATE_PATH = .agent-flow/{ISSUE-ID}/analyze-bug-state.json
   ```
   (the `EXPECTED_AGENT_NAME`/`EXPECTED_STAGE_NAME` lines match the pattern used by `skills/fix-bugs/steps/02-impact.md`; `STATE_PATH` is additional here because analyze-bug dispatches against `analyze-bug-state.json` rather than fix-bugs' literal default `.agent-flow/{ISSUE-ID}/state.json`, so fix-bugs has no need to inject it.)
5. Display results (triage + impact report)

No code changes, no issue tracker state changes, no resumable pipeline state — the ephemeral dispatch-witness stub written in steps 3/4 is ordinary dispatch bookkeeping, not a pipeline checkpoint. Analysis only.
