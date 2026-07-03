# Decomposition Heuristics

## Purpose

Determine whether a ticket should be decomposed into subtasks before the fixer-reviewer loop begins.

> **Scope note:** The `decompose_flag` decision process (Input Contract + Process sections below — evaluating analyst impact thresholds) applies to the bug-fix pipeline only. The feature pipeline reaches its DECOMPOSE/SINGLE_PASS decision differently (architect-driven, see implement-feature step 3 / `skills/implement-feature/steps/03-decomposition.md`). The **Task Tree Validation** algorithm (below) is shared by both pipelines: once either pipeline has a task tree (from architect dispatch), both `skills/fix-bugs/steps/02-impact.md` and `skills/implement-feature/steps/03-decomposition.md` validate it using the same algorithm.

## Input Contract

| Field | Type | Notes |
|-------|------|-------|
| decompose_flag | enum | `FORCE` / `DISABLED` / `AUTO` — from `--decompose` / `--no-decompose` flags |
| code_analyst_output | object | Fields: `risk` (LOW/MEDIUM/HIGH), `affected_files` (integer), `estimated_diff_lines` (integer), `independent_changes` (integer) |

Flag parsing from `$ARGUMENTS`:
- `--decompose` (without `--no-decompose`) → `FORCE`
- `--no-decompose` → `DISABLED`
- Neither → `AUTO`

## Process

1. If `decompose_flag = DISABLED` → return `SINGLE_PASS`.
2. If `decompose_flag = FORCE` → return `DECOMPOSE`.
3. If `decompose_flag = AUTO`: evaluate analyst impact output against thresholds (any match → DECOMPOSE):
   - `risk == HIGH`
   - `affected_files >= 4`
   - `estimated_diff_lines > 60 AND affected_files >= 3`
   - `independent_changes >= 2`
   - No threshold met → return `SINGLE_PASS`.

## Output Contract

| Result | Meaning |
|--------|---------|
| `DECOMPOSE` | Run architect agent, build task tree, execute per-subtask (see `skills/fix-bugs/SKILL.md` decomposition steps) |
| `SINGLE_PASS` | Skip decomposition, proceed directly to pre-fix hook and fixer-reviewer loop |

## Task Tree Validation (shared: bug-fix + feature pipelines)

Once a task tree exists — regardless of which pipeline produced it, or whether the DECOMPOSE decision came
from the impact-threshold Process above (bug-fix) or from the architect (feature) — validate it before
displaying the decomposition plan for approval:

1. **Check for cycles.** Walk all subtasks and find the root(s) (subtasks with an empty `depends_on`). If no
   root exists → cycle detected → Block.
2. **Topological sort.** Repeatedly select subtasks whose dependencies have all already been processed. If
   any subtasks remain unprocessed once no further progress can be made → cycle detected → Block.
3. **Check `max_subtasks` limit.** Compare the task tree size against `decomposition.max_subtasks` (default 7
   — see `Decomposition` section of Automation Config). Over the limit → apply the configured `fail_strategy`
   (default `fail-fast`).
4. **Check field completeness.** Each subtask must have `title`, `scope`, `files`, `estimated_lines` and (feature
   pipeline only) `maps_to` acceptance-criteria references. Missing required fields → Block.

Callers: `skills/fix-bugs/steps/02-impact.md` ("Validate task tree") and
`skills/implement-feature/steps/03-decomposition.md` ("Validate task tree") both invoke this algorithm.

## Failure Handling

- Missing or incomplete `code_analyst_output` fields → treat missing numeric fields as 0, missing `risk` as LOW → default to `SINGLE_PASS` (safe fallback).
- If `decompose_flag` is unrecognised → treat as `AUTO`.
