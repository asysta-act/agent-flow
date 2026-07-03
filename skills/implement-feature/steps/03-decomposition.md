# Step 03 — Decomposition Decision + Subtask Creation

## Decomposition decision

If `decompose_mode = DISABLED` → single-pass (skip to step 04 directly).
Update `state.json`: set `decomposition.status` to `"completed"`, `decomposition.decision` to `"SINGLE_PASS"`,
`decomposition.strategy` to `null`. Follow atomic write protocol from `../../../core/state-manager.md`.

If `decompose_mode = FORCE` or `decompose_mode = AUTO` and architect indicates decomposition:

**Validate task tree.** Follow `../../../core/decomposition-heuristics.md`:
1. Check for cycles: go through all subtasks, find root (depends_on empty).
   If no root → cycle → Block.
2. Topological sort: repeatedly find subtasks whose all dependencies are processed.
   If unprocessed remain → cycle → Block.
3. Check max_subtasks limit.
4. Check: each subtask has title, scope, files, estimated_lines, acceptance_criteria.

**AC coverage check:**
1. Collect all acceptance criteria from spec-analyst output (the parent AC list)
2. Collect all `maps_to` references from all subtasks in the task tree
3. Compute the set difference: parent_AC - mapped_AC
4. If any parent AC is unmapped:
   - Display warning: "The following acceptance criteria are not covered by any subtask:"
   - List the unmapped AC
   - If mode is yolo → Block ("Incomplete decomposition — unmapped AC detected")
   - Otherwise → ask user: "Continue anyway? The unmapped criteria will not be explicitly addressed. [Y/n]"

AC matching algorithm:
- Each `maps_to` entry uses format `AC-{N}: {text}` where N is the 1-based index in the parent AC list
- Coverage check: collect all N values from all subtasks' `maps_to` fields, verify that every integer
  from 1 to {total parent AC count} appears at least once
- Text after `AC-N:` is informational (for human readability) — matching is by index only
- If a `maps_to` entry cannot be parsed (no `AC-{N}:` prefix) → treat as warning, not error

**Display decomposition plan:**
```
## Decomposition Plan — {ISSUE-ID}

| # | Subtask | Files | ~Lines | Depends on |
|---|---------|-------|--------|------------|
| 1 | ... | ... | ~N | — |
| 2 | ... | ... | ~N | 1 |

Strategy: sequential | Total: ~N lines
Continue? [Y/n]
```

**Decomposition Approval checkpoint (default mode):** In default mode, display the plan and wait for
confirmation. If the user declines → stop. In yolo mode → auto-approve (no checkpoint, no prompt).

**Save task tree:** Create `.claude/decomposition/` if it does not exist (`mkdir -p .claude/decomposition/`).
Write the full task tree (including all subtask fields and runtime fields `status: "pending"`,
`commit_hash: null`, `restore_point: null`, `tracker_issue_id: null`) to
`.claude/decomposition/{ISSUE-ID}.yaml`.

Update `state.json`: set `decomposition.status` to `"completed"`, write `decomposition.decision`
(`"DECOMPOSE"` or `"SINGLE_PASS"`), `decomposition.strategy`, `decomposition.subtasks` list.
Follow atomic write protocol from `../../../core/state-manager.md`.

If `decompose_mode = AUTO` and decomposition is not indicated → single-pass (step 04 directly).
Update `state.json`: set `decomposition.status` to `"completed"`, `decomposition.decision` to
`"SINGLE_PASS"`, `decomposition.strategy` to `null`. Follow atomic write protocol from
`../../../core/state-manager.md`.

### Pre-dispatch witness write

Step 03 has no required agent dispatch — the decomposition decision is a heuristic evaluation (no Task call). Write to `state.json[stages.decomposition]` directly:

```bash
. core/lib/stage-invariant.sh
DISPATCHED_AT="$(date -u +%FT%TZ)"
# state.json[stages.decomposition] = {
#   dispatched_at, stage_name: "decomposition", agent_name: null,
#   prompt_head_128: null, overlay_source: null, overlay_digest: null,
#   dispatch_witness: null, status: "in_progress"
# } atomically. On heuristic completion, set status="completed" and write
# decomposition.decision = "DECOMPOSE" | "SINGLE_PASS".
```

If the optional `backlog-creator` dispatch fires (Step 03a backlog mode), resolve the Agent Override overlay FIRST, then compute a witness for stage `backlog_creation` per design.md §4.2:

```bash
# (1) Resolve overlay first: OVERLAY_SOURCE in {toml,none,md_rejected}, OVERLAY_BLOCK = rendered block.
OVERLAY_DIGEST="$(compute_overlay_digest "$OVERLAY_SOURCE" "$OVERLAY_BLOCK")"
PROMPT_HEAD_128="$(printf '%s' "$BACKLOG_CREATOR_PROMPT_TEMPLATE" | head -c 128)"
DISPATCH_WITNESS="$(compute_dispatch_witness backlog_creation agent-flow:backlog-creator sonnet "$PROMPT_HEAD_128" "$OVERLAY_SOURCE" "$OVERLAY_DIGEST")"
EXPECTED_AGENT_NAME="agent-flow:backlog-creator"
EXPECTED_STAGE_NAME="backlog_creation"
# Merge prompt_head_128, overlay_source, overlay_digest, dispatch_witness into the stage block
# in ONE atomic write, then append OVERLAY_BLOCK to the prompt.
```

## Step 03a: Create tracker subtasks

Follow `../../../core/tracker-subtask-creator.md`. Follow `../../../core/mcp-body-formatting.md` when constructing
multi-line MCP tool parameters.

Required in-memory values: `ISSUE_ID`, `tracker_type`, `tracker_project`, `tracker_effective_status`,
`decomposition_decision`, `create_tracker_subtasks_config`, subtask list, YAML path
(`.claude/decomposition/{ISSUE-ID}.yaml`), state.json path (`.agent-flow/{ISSUE-ID}/state.json`).

## Step 03b: --decompose-only exit

If `decompose_only_mode = true`:
1. Display decomposition result table (the same table shown during plan approval above)
2. Output: "Decomposition complete. {N} subtasks created in tracker. Run
   `/agent-flow:implement-feature {ISSUE-ID}` to begin implementation."
3. Update `state.json`: set top-level `status: "completed"`, `decomposition.status: "completed"`.
   Follow atomic write protocol from `../../../core/state-manager.md`.
4. EXIT — do not proceed to step 04 or beyond.
