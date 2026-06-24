# Step 07: Spec Compliance + Post-Implementation Tracker Updates

Runs spec-reviewer in `--verify` mode to check implementation against spec,
then posts implementation comments and closes tracker issues for completed epics.

## 07a. Spec Compliance Check

Before dispatch, check Agent Overrides: if `{Agent Overrides path}/spec-reviewer.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

You MUST invoke Task(subagent_type='agent-flow:spec-reviewer', model='opus'). DO NOT inline-execute.
Context: `--verify mode. Compare spec/ against implemented codebase.`

Verdict handling:
- FAIL:
  - Display the compliance report
  - If MODE = yolo → Block ("Spec compliance failed — MISSING acceptance criteria detected")
  - If MODE = default or step-mode → display report, ask: "Some acceptance criteria are not implemented. Continue? [Y/n]"
- PASS or PARTIAL → continue to 07b

## 07b. Post Implementation Comments

**Guard:** Skip if ANY of:
- `tracker_effective_status != "ready"`
- `tracker_write_available == false`
- No back-reference comments (`<!-- {TrackerType}: ... -->`) found in `spec/epics/*.md`

If guard does not trigger:
1. Read all `spec/epics/*.md`. Extract epic issue IDs from back-reference comments.
2. Determine fully completed epics: epic is complete if NONE of its subtasks appear in blocked features list.
3. For each fully-completed epic, post comment to the epic tracker issue:
   ```
   [agent-flow] Scaffold implementation completed.
   Features: {comma-separated list of implemented subtask titles for this epic}
   Branch: {current branch name}
   Stories: {N} implemented, {B} blocked
   ```
4. On individual comment failure: `WARN: Could not post implementation comment to {issue-id}: {error}`, continue. Never block.
5. Display: `Posted implementation comments to {C}/{E} epic issues.`

## 07c. Close Tracker Issues

**Guard:** Skip if ANY of:
- `tracker_effective_status != "ready"`
- `tracker_write_available == false`
- No back-reference comments in `spec/epics/*.md`
- `State transitions` in Automation Config does not contain a `Done` mapping → display `WARN: State transitions missing 'Done'. Skipping closure.`

If guard does not trigger:
1. Read all `spec/epics/*.md`. Extract epic and story issue IDs from back-reference comments.
2. Determine which epics are fully completed (no blocked subtasks from Step 05 block handler).
3. For each fully-completed epic:
   a. Transition epic issue to Done (using `State transitions → Done` from Automation Config). Follow `../../../core/status-verification.md` to verify transition.
   b. For each story sub-issue: transition individually to Done. Verify each.
   c. If story issue already in Done state: treat as success (no warning).
   d. On failure: `WARN: Could not transition {issue_id} to Done: {error}`, continue.
4. Epics with blocked subtasks → skip; remain open for manual triage.
5. Display: `Transitioned {N}/{M} epic issues and {S} story issues to Done. {skipped} epics skipped (blocked subtasks).`
