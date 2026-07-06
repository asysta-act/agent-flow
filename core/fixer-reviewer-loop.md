# Fixer-Reviewer Loop

## Purpose

Iterative fixer↔reviewer loop with configurable limits and acceptance criteria checking.

## Input Contract

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| context | string | required | Mode-dependent input (discriminated union): **Bug-fix mode** — bug report + AC + analyst impact output; **Feature/scaffold mode** — spec-analyst output + AC + architect task tree. The `Mode:` prefix in context determines which variant. |
| max_iterations | integer | 5 | From Retry Limits → Fixer iterations |
| acceptance_criteria | list | [] | AC list from analyst triage output |
| agent_override_path | string | `customization/` | Path for per-agent override files |
| state_run_id | string | required | Used for state.json writes |

## Process

1. Check if `{agent_override_path}/fixer.md` exists. If yes, append its content to fixer context as `## Project-Specific Instructions\n{content}`.
2. You MUST invoke Task(subagent_type='agent-flow:fixer', model='opus'). DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator. Pass context + any previous reviewer feedback.
3. If fixer output contains `## NEEDS_DECOMPOSITION` → return `NEEDS_DECOMPOSITION` immediately. Only allowed once per ticket; caller enforces the limit.
4. Run Build command (max Build retries attempts). Failure → return `BLOCKED` with build error as detail.
5. Check if `{agent_override_path}/reviewer.md` exists. If yes, append its content to reviewer context.
6. You MUST invoke Task(subagent_type='agent-flow:reviewer', model='opus'). DO NOT inline-execute. Inline execution is a CONTRACT VIOLATION detected by the PostToolUse validator. Pass fixer's changes + AC list.
7. If reviewer outputs `APPROVE` (with AC Fulfillment section) → update state.json, return `APPROVED` with AC fulfillment report.
8. If `iteration count + 1 >= max_iterations` → update state.json, return `BLOCKED` with last reviewer critique as detail. (The `+1` accounts for the round just completed — `iteration count` is not incremented until step 9, so checking the raw counter here would let one extra round run past the configured limit.)
9. Pass reviewer critique back to fixer as additional context, increment iteration counter, go to step 1.
10. After each iteration, update state.json atomically (see `core/state-manager.md` atomic write protocol): increment `fixer_reviewer.iterations`, set `fixer_reviewer.last_verdict`, update `fixer_reviewer.ac_fulfillment` from reviewer AC Fulfillment section, set `fixer_reviewer.status` to `"in_progress"`, and accumulate usage fields: `fixer_reviewer.tokens_used += iteration_tokens_used`, `fixer_reviewer.duration_ms += iteration_duration_ms`, `fixer_reviewer.tool_uses += iteration_tool_uses`. These cumulative writes ensure that if the pipeline crashes mid-loop, the state.json reflects the token cost of all completed iterations and can be used for cost reporting on resume.

## Output Contract

| Result | Payload |
|--------|---------|
| `APPROVED` | AC fulfillment report (per-AC verdict: FULFILLED / PARTIALLY / NOT ADDRESSED) |
| `BLOCKED` | Last reviewer critique or build error; iteration count |
| `NEEDS_DECOMPOSITION` | Fixer's decomposition rationale (passed through) |

On `APPROVED`: set `fixer_reviewer.status` to `"completed"` in state.json.
On `BLOCKED`: set `fixer_reviewer.status` to `"blocked"`, write `block` object in state.json.

## Failure Handling

- `BLOCKED` → caller invokes `core/block-handler.md`.
- `NEEDS_DECOMPOSITION` → returned to caller; caller handles decomposition logic (see `core/decomposition-heuristics.md`). Callers: `skills/fix-bugs/SKILL.md` step 4 (revert + re-decompose per-bug, max 1), `skills/implement-feature/SKILL.md` step 6b (block current subtask or block issue in single-pass).
- Build failure counts as a BLOCKED result, not a fixer iteration.
