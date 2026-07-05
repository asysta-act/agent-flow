# Step 03: Scaffold Skeleton + Git Init

Generates the project skeleton into a temp directory, validates it, moves to target,
emits `.agent-flow/config.toml` and a CLAUDE.md pointer to it, initializes git, and creates tracker issues.

## 03a. Scaffolder Dispatch

Create temp directory:
```bash
SCAFFOLD_TEMP=$(mktemp -d)
```

**Pre-dispatch (COST-R4):** Read `model:` from `agents/scaffolder.md` frontmatter (value: `sonnet`). Write to state.json atomically: `scaffolder.started_at`, `scaffolder.model = "sonnet"`, `scaffolder.status = "in_progress"`, counters `0`.

Check Agent Overrides: if `{Agent Overrides path}/scaffolder.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.

You MUST invoke Task(subagent_type='agent-flow:scaffolder', model='sonnet'). DO NOT inline-execute.
Context: `spec/README.md` Tech Stack section + project description. Working directory: `$SCAFFOLD_TEMP`.
Mode indicator: scaffold-spec-first (so scaffolder generates E2E Test config + Decomposition defaults).
Scaffolder generates: all project files, `.agent-flow/config.toml` (the committed config with `[e2e_test]` + `[decomposition]` defaults), a CLAUDE.md pointer to that config, docs/ARCHITECTURE.md, Module Docs config.

**Post-dispatch (COST-R2, COST-R3):** Defensive-read `result.usage`. Write `scaffolder.completed_at`, `scaffolder.tokens_used`, `scaffolder.duration_ms`, `scaffolder.tool_uses` (default `0`). Set `scaffolder.status = "completed"`.

## 03b. Validation (max 3 retries)

After scaffolder completes, independently verify the generated skeleton:

1. **Read commands:** Read `build.build_command` and `build.test_command` from the generated `.agent-flow/config.toml` in `$SCAFFOLD_TEMP` (via `../../../core/config-reader.md`)
2. **Build check:** Run Build command in `$SCAFFOLD_TEMP`. If fails → pass error to scaffolder, increment retry counter
3. **Test check:** Run Test command in `$SCAFFOLD_TEMP`. If fails → same retry loop
4. **Lint check:** If linter configured, run it. Failure → same retry loop
5. **Config check:** Verify all 5 required `[section]`s are present in `.agent-flow/config.toml` (`[issue_tracker]`, `[source_control]`, `[pr_rules]`, `[pr_description_template]`, `[build_and_test]`)

If 3 retries exhausted (any check still failing) → delete `$SCAFFOLD_TEMP`, report which check failed + last error output, STOP.

Move skeleton to target directory (which already contains `spec/`):
```bash
cp -r $SCAFFOLD_TEMP/* ./
# Safety: $SCAFFOLD_TEMP path MUST contain /tmp or system temp path before rm -rf.
# DO NOT run rm -rf without first verifying $SCAFFOLD_TEMP is non-empty and points
# into the scaffold staging area — guards against catastrophic deletion if the
# variable is unset.
[ -n "$SCAFFOLD_TEMP" ] && [[ "$SCAFFOLD_TEMP" == *scaffold-staging* || "$SCAFFOLD_TEMP" == /tmp/* ]] && rm -rf "$SCAFFOLD_TEMP"
```

Update `state.json`: set `code_analysis.status` to `"completed"` (field reused for scaffolder phase). Atomic write.

Fire `step-completed` webhook for `scaffolder` (after state.json write succeeds):
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "${Webhook_URL}" <<EOF
{"event":"step-completed","run_id":"${run_id}","issue_id":"${run_id}","step_name":"scaffolder",
 "duration":${duration_seconds},"iteration_count":1,"timestamp":"${ISO8601_UTC}"}
EOF
```
On failure: log `[WARN] Webhook delivery failed`, continue.

## 03c. Emit `.agent-flow/config.toml` + CLAUDE.md pointer

The single source of truth for automation config is the committed `.agent-flow/config.toml`
(consumed by `../../../core/config-reader.md`). The generated project's CLAUDE.md receives only a
1-2 line **pointer** to that file — never an inline `## Automation Config` block and never any
`| Key | Value |` config rows.

**Required in-memory values from Step 01:** `tracker_type`, `tracker_instance`, `tracker_project`, `sc_remote`, `sc_base_branch`, `tracker_effective_status`, `sc_effective_status`.
DO NOT re-read the generated `.agent-flow/config.toml` for these values — it may still contain TODO markers.

Write `.agent-flow/config.toml` as TOML `[section]` tables. For services where
`{service}_effective_status` is `"ready"`, fill the resolved values automatically; for `"later"` or
`"downgraded"` services, leave a TODO comment on the affected key. Encode list- and map-valued keys
using the delimited-scalar convention from `../../../core/config-reader.md` — commas delimit lists,
`;` records + `:` key/value delimit maps. Minimum shape:

```toml
[issue_tracker]
type = "youtrack"
instance = "https://tracker.example.com"          # TODO if tracker_effective_status != "ready"
project = "PROJ"                                    # TODO if tracker_effective_status != "ready"
bug_query = "State: Open"
state_transitions = "triage: In Progress; fixed: Fixed"   # delimited-scalar map
on_start_set = "In Progress"

[source_control]
remote = "owner/repo"                               # TODO if sc_effective_status != "ready"
base_branch = "main"
branch_naming = "fix/{issue-id}"

[pr_rules]
labels = "bug, automated"                           # delimited-scalar list

[pr_description_template]
template = """
## Summary
...
"""

[build_and_test]
build_command = "..."
test_command = "..."
```

Then write the generated project's CLAUDE.md pointer (NOT an inline config table). Example pointer body:

```markdown
## Automation Config

Automation config for agent-flow lives in [`.agent-flow/config.toml`](.agent-flow/config.toml)
(read by `core/config-reader.md`). Edit that file to change tracker, source-control, PR, or
build/test settings.
```

Generate `.mcp.json.example` based on `tracker_type` (if declared). Read MCP Server Detection table from `{trackers_md_path}`. Add `.mcp.json` to `.gitignore`. Ensure `.agent-flow/config.toml` is committed (it is NOT gitignored; only the optional per-developer `.agent-flow/config.local.toml` is).

## 03d. Git Init + Commit

```bash
git init
git add .
git commit -m "feat: initial project scaffold

Stack: {language} + {framework}
Spec: {N} epics, {M} user stories
Generated by agent-flow /scaffold"
```

## 03e. Push to Remote (if SC ready)

If `sc_effective_status` is `"ready"`:
```bash
git remote add origin {sc_remote}
git push -u origin {sc_base_branch}
```
In --yolo mode: run without confirmation. On failure → WARN only, continue pipeline.

## 03f. Create Tracker Issues (Step 4e logic)

**Guard:** Skip if `tracker_effective_status != "ready"` OR `tracker_write_available == false` OR `spec/epics/` empty.

Dispatch backlog-creator agent (sonnet) via Task tool with architect decomposition output.
Apply agent override: if `{Agent Overrides path}/backlog-creator.toml` exists, append its rendered Markdown content as `## Project-Specific Instructions` per `../../../core/agent-override-injector.md`.
Receive structured issue cards. For each card: create epic + story sub-issues per tracker type.

Write back-reference comments (`<!-- {TrackerType}: {ISSUE-ID} -->`) into spec/epics/*.md.
Idempotency guard: if back-reference already present, skip creation.
On partial failure: WARN + continue; commit partial links with `git commit -m "chore: link spec epics to tracker issues"`.
Display: `Created {N}/{M} tracker issues ({S} stories, {F} story failures).`
