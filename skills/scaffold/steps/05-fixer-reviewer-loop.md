# Step 05: Fixer ↔ Reviewer Loop

Implements all epics/subtasks in batches. For each batch, runs fixer ↔ reviewer loop
per subtask, handles NEEDS_CLARIFICATION, and commits after batch completion.

## Centralized claim-write ritual (v2.0 gate-as-signer)

Scaffold is **NOT** exempt from the dispatch witness (this closes the documented
0-witness scaffold gap). Immediately before **every** `Task()` dispatch in this
skill (spec-writer, scaffolder, architect, fixer, reviewer, test-engineer),
perform the centralized claim-write ritual defined once in `../../claim-ritual.md`.
The ritual mints a fresh `claim_nonce` (`secrets.token_hex(16)`) + a monotonic
`dispatch_seq`, atomically writes the **claim-only** stage record into
`state.json`, and atomically writes the top-level per-dispatch marker
`.agent-flow/pending-dispatch.json` (temp + `os.replace`). The orchestrator
writes no key and no signed tag; the prompt head is gate-observed ground truth,
not an orchestrator-written field.

Note: Hooks (Pre-fix, Post-fix, Pre-publish, Post-publish) are NOT executed during scaffold
because the project is being created from scratch — no existing CI, linter config, or external
integration to hook into.

## Per-Batch Loop

For each batch in order:
  For each subtask in batch (respecting depends_on order):

    Build fixer context:
    - Full decomposition plan (all batches, all subtasks)
    - Summary of previously completed subtasks (what changed, diff summary)
    - Current subtask scope, files, acceptance_criteria, maps_to
    - spec/ folder available for reference

    ### 05a. Fixer

    **Pre-dispatch fixer_reviewer (COST-R4, first iteration per subtask only):** Write to state.json:
    `fixer_reviewer.started_at`, `fixer_reviewer.model = "opus"`, `fixer_reviewer.status = "in_progress"`, counters `0`.

    Check Agent Overrides: if `{Agent Overrides path}/fixer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

    You MUST invoke Task(subagent_type='agent-flow:fixer', model='opus'). DO NOT inline-execute.
    Context: subtask scope + acceptance_criteria + architecture design + `Max build retries = {Build retries from CLAUDE.md, default 3}`.

    After completion: run Build command from generated CLAUDE.md.

    **Post-dispatch (COST-R2, COST-R3, COST-R5):** Accumulate cumulatively:
    `fixer_reviewer.tokens_used += iteration_tokens`, `fixer_reviewer.duration_ms += iteration_duration_ms`, `fixer_reviewer.tool_uses += iteration_tool_uses`.

    If build fails → fixer fixes (max Build retries from CLAUDE.md, default 3). If still fails → Block handler.

    **NEEDS_CLARIFICATION detection (after fixer dispatch):** If fixer output contains `## NEEDS_CLARIFICATION`:
    ```bash
    RAW_QUESTION=$(grep -iE -A1 "^question:" "$FIXER_OUTPUT" | head -1 | sed -E 's/^[Qq]uestion: //')
    RAW_CONTEXT=$(grep -iE -A1 "^context:" "$FIXER_OUTPUT" | head -1 | sed -E 's/^[Cc]ontext: //' || echo "")
    CONSUMED=$(jq -r '.clarification.clarifications_consumed // 0' state.json)
    if [ "$CONSUMED" -ge 3 ]; then
      echo "[BLOCK] Exceeded max clarifications (3 per run)" >&2; exit 1
    fi
    LAST_ITER=$(jq -r '.clarification.last_clarification_iteration // null' state.json)
    CURRENT_ITER=$(jq -r '.fixer_reviewer.iterations // 0' state.json)
    if [ "$LAST_ITER" = "$CURRENT_ITER" ]; then
      echo "[BLOCK] Clarification limit per iteration exceeded" >&2; exit 1
    fi
    ASKED_AT="$(date -u +%FT%TZ)"
    jq --arg q "$RAW_QUESTION" --arg c "$RAW_CONTEXT" --arg asked_at "$ASKED_AT" \
      --argjson iter "$CURRENT_ITER" \
      '.status = "paused" | .clarification = {question: $q, asked_by_agent: "fixer", asked_at_step: "scaffold-fixer",
       asked_at_iteration: $iter, asked_at: $asked_at, context: $c, answer: null,
       clarifications_consumed: ((.clarification.clarifications_consumed // 0) + 1),
       last_clarification_iteration: $iter}' \
      state.json > state.json.tmp && mv state.json.tmp state.json
    echo "[INFO] Pipeline paused — re-invoke /agent-flow:scaffold --clarification \"<answer>\" to resume."
    exit 0
    ```
    Fire `pipeline-paused` webhook if configured (per `../../../core/agent-states.md` Section 2 firing site).

    ### 05b. Reviewer

    Check Agent Overrides: if `{Agent Overrides path}/reviewer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

    You MUST invoke Task(subagent_type='agent-flow:reviewer', model='opus'). DO NOT inline-execute.
    Context: diff from fixer + acceptance_criteria + `Max fixer iterations = {Fixer iterations from CLAUDE.md, default 5}`.
    Follow `../../../core/fixer-reviewer-loop.md`.

    **Post-dispatch (COST-R2, COST-R3, COST-R5):** Accumulate cumulatively on `fixer_reviewer.*`.

    If APPROVE → continue to 05c.
    If REQUEST_CHANGES → back to fixer with feedback (max Fixer iterations, default 5).
    If BLOCK or max iterations exhausted → Block handler.

    After each iteration: update state.json — increment `fixer_reviewer.iterations`, set `fixer_reviewer.last_verdict`.
    On APPROVE: set `fixer_reviewer.status = "completed"`, write `fixer_reviewer.completed_at`.
    On block: set `fixer_reviewer.status = "blocked"`.

    Fire `step-completed` for `fixer_reviewer` after APPROVE + state.json write:
    ```bash
    curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
      --data-binary @- "${Webhook_URL}" <<EOF
    {"event":"step-completed","run_id":"${run_id}","issue_id":"${run_id}","step_name":"fixer_reviewer",
     "duration":${duration_seconds},"iteration_count":${iteration_count},"timestamp":"${ISO8601_UTC}"}
    EOF
    ```

    ### 05c. Commit Subtask

    ```bash
    git add -A
    git commit -m "feat({subtask-id}): {subtask-title}"
    ```

    ### Block Handler (from 05a, 05b)

    Follow `../../../core/block-handler.md`.
    1. You MUST invoke Task(subagent_type='agent-flow:rollback-agent', model='haiku'). Context: "No issue tracker context — skip issue tracker updates." Revert to last successful commit.
    2. Report block to stdout (Block Comment Template format).
    3. Update state.json: set `status = "blocked"`, write `block` object. Atomic write.
    4. If fail-fast → write pipeline accumulator (COST-R6), fire `pipeline-completed` with `outcome: "blocked"`, STOP → jump to Step 08.
    5. If continue strategy → skip subtask, proceed to next in batch.

  **After each batch:** Run full test suite (Test command from CLAUDE.md).
  If failure → fixer repairs (max Build retries). If still failing → STOP → jump to Step 08 (report).
