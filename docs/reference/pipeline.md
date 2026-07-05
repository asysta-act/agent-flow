# Pipeline Reference

This document describes the internal pipeline architecture: how SKILL.md files are
decomposed into steps, how override resolution works, the mode flag framework (`--yolo` / default /
`--step-mode`), and how Pipeline Profiles map stage names. For high-level pipeline
diagrams (flow chart, stage tables) see `docs/reference/pipelines.md`. This page is a
machine-readable reference for integrators and contributors.

---

## Pipeline Overview

agent-flow provides three pipelines. Each is invoked by one or more skills and uses a common
steps decomposition layout.

| Pipeline | Entry skill(s) | Purpose | When to use |
|----------|---------------|---------|-------------|
| `fix-bugs` | `/agent-flow:fix-bugs` | Triage, analyze, fix, review, test, and publish N bugs from the issue tracker | Existing bugs in the tracker; batch or single issue |
| `implement-feature` | `/agent-flow:implement-feature` | Spec, architect, optionally decompose, fix, review, test, and publish a feature from the tracker | Feature issues; supports decomposition into subtasks |
| `scaffold` | `/agent-flow:scaffold` | Create a new project from scratch: spec, stack selection, skeleton, implement all epics, test, verify, report | New project bootstrapping |

All three pipelines share:
- Mode flag framework (`--yolo` / default / `--step-mode`) — see [Mode flag dispatch](#mode-flag-dispatch)
- Step override resolution via `customization/steps/{skill}/` — see [Step override resolution](#step-override-resolution) *(planned for v1.2)*
- Pipeline Profiles named-phase `Skip stages` syntax — see [Named-phase Skip stages syntax](#named-phase-skip-stages-syntax)
- Hooks at fixed points (pre-fix, post-fix, pre-publish, post-publish) — see [Hooks](#hooks)
- `state.json` persistence per run via `core/state-manager.md`

---

## Entry SKILL.md responsibilities

Each pipeline has an **entry SKILL.md** (e.g., `skills/fix-bugs/SKILL.md`). This file is
responsible for:

1. **Argument parsing** — extract issue IDs, `--yolo`, `--step-mode`, `--profile`, `--dry-run`,
   and other pipeline-specific flags. Mode flag parsing MUST follow the explicit-boolean pattern
   (see [Mode flag dispatch](#mode-flag-dispatch)).
2. **Configuration loading** — read `.agent-flow/config.toml` via
   `core/config-reader.md` + `core/mcp-preflight.md` + `core/profile-parser.md`.
3. **Issue-ID validation** (for tracker-based pipelines) — path-traversal defense:
   ```bash
   if [[ ! "${ISSUE_ID}" =~ ^[A-Za-z0-9#._-]+$ ]] || [[ "${ISSUE_ID}" =~ ^\.+$ ]]; then
     echo "[BLOCK] Invalid issue_id: ${ISSUE_ID}" >&2; continue
   fi
   ```
4. **Step dispatch loop** — iterate over the ordered step files, resolve overrides, execute each
   step's instructions, write `last_completed_step` to `state.json` after each step fully
   completes (atomic per `core/state-manager.md`).
5. **`--step-mode` prompt** — after each step in `--step-mode`, present the `[step-mode]` prompt
   (see [Mode flag dispatch](#mode-flag-dispatch)).
6. **Block handling** — follow `core/block-handler.md`. On block: fire `pipeline-completed` with
   `outcome:failed`; continue with next issue (or abort run if `Max blocked per run` reached).
7. **Summary output** — after all issues processed, display result table and fire
   `pipeline-complete` webhook if configured.

The entry SKILL.md is intentionally short (~100 lines). All per-step business logic lives in the
`steps/` directory.

---

## Step file responsibilities

Step files live at `skills/{skill}/steps/{NN-name}.md`. Each step file is responsible for
exactly one pipeline phase. Conventions:

- **Filename format:** `{NN}-{descriptive-name}.md` where `NN` is a zero-padded two-digit
  integer (`01`, `02`, ..., `08`). The descriptive name uses lowercase hyphenated words.
- **No YAML frontmatter** — step files are plain markdown. The entry SKILL.md frontmatter
  controls the entire pipeline's tool access and model invocation settings.
- **Self-contained** — each step file describes its skip conditions, pre-dispatch state writes,
  agent dispatch (via `Task` tool), post-dispatch state writes, outcome handling, and
  NEEDS_CLARIFICATION detection where applicable.
- **Agent dispatch contract** — steps MUST invoke agents via `Task(subagent_type='{agent-name}')`.
  Inline execution without Task dispatch is a CONTRACT VIOLATION detected by the PostToolUse
  validator hook.
- **State atomicity** — every step writes `state.json` fields both before (pre-dispatch) and
  after (post-dispatch) the agent Task call, following `core/state-manager.md` atomic write
  protocol. `last_completed_step` in the entry SKILL.md is written ONLY after the step fully
  completes, ensuring SIGTERM before write causes the step to re-execute on resume.
- **Webhook emission** — steps fire `step-completed` webhook after the post-dispatch state
  write if Notifications are configured (see `core/post-publish-hook.md`).

Example step file path:

```
skills/fix-bugs/steps/04-fixer-reviewer-loop.md
```

Override path for the same step (project-level):

```
customization/steps/fix-bugs/04-fixer-reviewer-loop.md
```

---

## Step override resolution

> **Step file override: planned for v1.2.** Not active in v1.0.

**Resolution algorithm (per step, per pipeline run):**

```bash
STEP_NAME="NN-name"   # e.g. "04-fixer-reviewer-loop"
SKILL_DIR="skills/fix-bugs/steps"
PROJECT_OVERRIDE="customization/steps/fix-bugs"

STEP_FILE="${SKILL_DIR}/${STEP_NAME}.md"

if [ -f "${PROJECT_OVERRIDE}/${STEP_NAME}.md" ]; then
  STEP_FILE="${PROJECT_OVERRIDE}/${STEP_NAME}.md"
  echo "[INFO] Step override active: fix-bugs/${STEP_NAME} from project customization"
else
  # Near-miss detection
  NEAR=$(find "${PROJECT_OVERRIDE}/" -maxdepth 1 -name "*.md" 2>/dev/null | while IFS= read -r f; do
    b="$(basename "$f")"
    norm_b="$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    norm_s="$(printf '%s' "${STEP_NAME}.md" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    nb="$(printf '%s' "$norm_b" | sed 's/^0*//')"
    ns="$(printf '%s' "$norm_s" | sed 's/^0*//')"
    if [ "$norm_b" = "$norm_s" ] || [ "$nb" = "$ns" ]; then printf '%s' "$b"; fi
  done)
  if [ -n "$NEAR" ]; then
    echo "[WARN] Possible misnamed step override: ${NEAR} — did you mean ${STEP_NAME}.md?"
  fi
fi

# Execute instructions from $STEP_FILE
```

**Rules:**

1. Override is **replace-only**: the project override file fully replaces the plugin default step.
   No partial patching, no before/after insertion.
2. Filename match is **exact**: `{NN-name}.md` (case-sensitive, hyphen-separated). A mismatched
   filename silently falls through to the plugin default.
3. Near-miss detection emits a `[WARN]` log for common normalization errors (uppercase, underscore
   vs hyphen, missing leading zero). The pipeline does NOT abort — it falls through to the plugin
   default and warns.
4. Override files MUST be plain markdown (no YAML frontmatter required).
5. Logging: exactly one `[INFO] Step override active: {skill}/{step-name} from project
   customization` message per overridden step per dispatch.
6. Override location: `{project_root}/customization/steps/{skill}/{NN-name}.md` where
   `{project_root}` is the directory containing `CLAUDE.md`.

---

## Mode flag dispatch

All three entry SKILL.md files implement identical mode flag parsing using the
**explicit-boolean pattern** (design.md §5.1):

```bash
GOT_YOLO=false
GOT_STEP_MODE=false
MODE="default"

for arg in "$@"; do
  case "$arg" in
    --yolo)      GOT_YOLO=true;      MODE="yolo"      ;;
    --step-mode) GOT_STEP_MODE=true; MODE="step-mode" ;;
  esac
done

if [ "$GOT_YOLO" = "true" ] && [ "$GOT_STEP_MODE" = "true" ]; then
  echo "[ERROR] Flags --yolo and --step-mode are mutually exclusive" >&2
  exit 2
fi
# $MODE is now one of: "default" | "yolo" | "step-mode"
```

The explicit-boolean pattern is required (not naive last-wins) because `--step-mode --yolo` must
produce a hard `[ERROR]` with exit code 2, not silently resolve to `MODE=yolo`.

### Mode semantics per pipeline

| Mode | fix-bugs | implement-feature | scaffold |
|------|-----------------------|-------------------|---------|
| `default` | Autonomous to PR; NEEDS_CLARIFICATION pauses | Spec Checkpoint (step 01), Decomposition Approval (step 03), PR confirmation (step 08) | 2 checkpoints (spec + feature plan); brainstorm if description is vague |
| `--yolo` | Zero gates, zero prompts; fully autonomous to PR | Zero checkpoints; auto-approve decomposition, spec, PR | Zero gates, no brainstorm; fully autonomous to final report |
| `--step-mode` | Per-step `[c/s/a]` prompt after each of 12 steps | Per-step `[c/s/a]` prompt after each of 8 steps | Per-step `[c/s/a]` prompt after each of 8 steps |

Flags are mutually exclusive across all three pipelines (exit code 2 on conflict).

### `--step-mode` prompt template

After each step completes (except in `--yolo` mode), the skill emits:

```
[step-mode] Step {NN}/{total} completed: {step-name}
Next step: {next-step-name}
Continue / Skip remaining gates / Abort? [c/s/a]:
```

| Input | Effect |
|-------|--------|
| `c` / `continue` (case-insensitive) | Proceed to next step |
| `s` / `skip` (case-insensitive) | Switch `MODE` to `yolo` for all remaining steps; log `[INFO] step-mode escape: switched to yolo for remaining steps` |
| `a` / `abort` (case-insensitive) | Halt; write `state.json`: `outcome=paused, pause_reason=step_mode_abort, last_completed_step={NN-name}, paused_at={ISO8601}`; exit 0 |
| empty input | Re-prompt (no default; prevents accidental Enter-skip) |
| any other | Re-prompt with "Invalid input; expected c, s, or a" |

A step-mode abort is resumable by re-invoking the original entry-point skill with the issue ID
(e.g. `/agent-flow:fix-bugs {ID}`). The inline auto-resume contract (`core/resume-detection.md`)
reads `pause_reason=step_mode_abort` and resumes from `last_completed_step + 1`.

---

## Named-phase Skip stages syntax

Pipeline Profiles (`### Pipeline Profiles` in Automation Config) allow skipping optional stages:

```
### Pipeline Profiles

| Profile | Skip stages | Extra stages |
|---------|-------------|--------------|
| fast    | analyst-impact, test-engineer-e2e | |
| triage-only | analyst-impact, browser-agent-reproduce, browser-agent-verify, test-engineer-e2e, acceptance-gate | |
```

**Mandatory stages** (CANNOT be skipped): `fixer`, `reviewer`, `publisher`.

**Valid skip stage names:**

| Stage name | Agent dispatched | Notes |
|------------|-----------------|-------|
| `triage` | `analyst --phase triage` | fix-bugs only |
| `analyst-triage` | `analyst --phase triage` | Alias for `triage` |
| `analyst-impact` | `analyst --phase impact` | |
| `browser-agent-reproduce` | `browser-agent --phase reproduce` | |
| `browser-agent-verify` | `browser-agent --phase verify` | |
| `test-engineer-e2e` | `test-engineer --e2e=true` | |
| `acceptance-gate` | `acceptance-gate` | |
| `spec-analyst` | `spec-analyst` | implement-feature only |

Alternatively, use the step-file name form directly (preferred for precision):

```
Skip stages: 03-reproduce, 06-acceptance-gate
```

---

## Per-pipeline step reference

### fix-bugs (12 steps)

Entry: `skills/fix-bugs/SKILL.md`  
Steps directory: `skills/fix-bugs/steps/`  
Override directory: `customization/steps/fix-bugs/` *(planned for v1.2 — not active in v1.0)*

> **Step file override: planned for v1.2.** Not active in v1.0.

| Step file | Stage name | Agent dispatched | Conditional? |
|-----------|-----------|-----------------|-------------|
| `01-triage.md` | triage | `analyst --phase triage` | Skippable via profile |
| `02-impact.md` | analyst-impact | `analyst --phase impact` | Skippable via profile |
| `03-reproduce.md` | browser-agent-reproduce | `browser-agent --phase reproduce` | Conditional (Browser Verification config required); skippable via profile |
| `04-fixer-reviewer-loop.md` | fixer / reviewer | `fixer`, `reviewer` | NOT skippable |
| `05-smoke.md` | smoke | — (build + test via Bash) | No |
| `06-test.md` | test-engineer | `test-engineer` | No |
| `07-e2e.md` | test-engineer-e2e | `test-engineer --e2e=true` | Conditional (E2E Test config required); skippable via profile |
| `08-browser-verify.md` | browser-agent-verify | `browser-agent --phase verify` | Conditional (Browser Verification config required); skippable via profile |
| `09-acceptance-gate.md` | acceptance-gate | `acceptance-gate` | Conditional (AC ≥ 3 OR complexity ≥ M); skippable via profile |
| `10-pre-publish.md` | pre-publish | Pre-publish hook + custom agent | Conditional (only if configured) |
| `11-publish.md` | publisher | `publisher` | NOT skippable |
| `12-result.md` | result | — (summary + dispatch-audit surfacing) | No |

### implement-feature (8 steps)

Entry: `skills/implement-feature/SKILL.md`  
Steps directory: `skills/implement-feature/steps/`  
Override directory: `customization/steps/implement-feature/` *(planned for v1.2 — not active in v1.0)*

> **Step file override: planned for v1.2.** Not active in v1.0.

| Step file | Stage name | Agent dispatched | Conditional? |
|-----------|-----------|-----------------|-------------|
| `01-spec.md` | spec-analyst | `spec-analyst` | Spec checkpoint in default mode |
| `02-architect.md` | architect | `architect` | No |
| `03-decomposition.md` | decomposition | Internal decision logic | Depends on decomposition trigger |
| `04-fixer-reviewer-loop.md` | fixer / reviewer | `fixer`, `reviewer` | NOT skippable |
| `05-smoke.md` | smoke | — (build + test via Bash) | No |
| `06-test.md` | test-engineer | `test-engineer` | No |
| `07-acceptance-gate.md` | acceptance-gate | `acceptance-gate` | Always in decomposition; skipped in single-pass |
| `08-publish.md` | publisher | `publisher` | NOT skippable |

### scaffold (8 steps)

Entry: `skills/scaffold/SKILL.md`  
Steps directory: `skills/scaffold/steps/`  
Override directory: `customization/steps/scaffold/` *(planned for v1.2 — not active in v1.0)*

> **Step file override: planned for v1.2.** Not active in v1.0.

| Step file | Stage name | Agent dispatched | Notes |
|-----------|-----------|-----------------|-------|
| `01-mode-resolve.md` | mode-resolve | Internal | Resolves mode, infra, brainstorm trigger |
| `02-spec-write-review.md` | spec-write-review | `spec-writer`, `spec-reviewer` | Spec checkpoint in default mode |
| `03-scaffold.md` | scaffold | `scaffolder` | Generates skeleton + git init |
| `04-architect.md` | architect | `architect` | Feature plan checkpoint in default mode |
| `05-fixer-reviewer-loop.md` | fixer / reviewer | `fixer`, `reviewer` | NOT skippable |
| `06-test.md` | test-engineer | `test-engineer` | No |
| `07-spec-verify.md` | spec-verify | `spec-reviewer --verify` | Spec compliance check |
| `08-final-report.md` | final-report | Internal | Fires `pipeline-completed` webhook |

### fix-bugs default mode — conditional gate notes

In fix-bugs default mode (no `--yolo`, no `--step-mode`), the pipeline is autonomous to PR but
includes conditional gates. The `fix-bugs` default mode acceptance gate (`09-acceptance-gate.md`)
is conditional: it triggers when `AC >= 3 OR complexity >= M`. Below that threshold the acceptance
gate is skipped and the pipeline proceeds directly to publish. The `conditional gate` threshold
is encoded in `skills/fix-bugs/steps/09-acceptance-gate.md`.

### implement-feature default mode — checkpoints

In implement-feature default mode, the pipeline includes human-visible checkpoints. The
`implement-feature default` pipeline shows a **spec checkpoint** (step 01) for operator review
after spec generation and a **Decomposition Approval** (step 03) checkpoint when decomposition
is triggered. The `spec checkpoint implement` gate in step 01 allows the operator to review the
spec before architect work begins. These checkpoints are omitted in `--yolo` mode.

---

## State management

Pipeline state is persisted to `.agent-flow/{RUN-ID}/state.json` via `core/state-manager.md`.
See `state/schema.md` for the full schema.

### State top-level keys (`schema_version` stays `"1.0"`)

| Key | Type | Description |
|-----|------|-------------|
| `analyst_triage_completed_at` | ISO 8601 string or null | When `analyst --phase triage` completed |
| `analyst_impact_completed_at` | ISO 8601 string or null | When `analyst --phase impact` completed |
| `test_engineer_e2e_invoked` | boolean | `true` when `test-engineer --e2e=true` was dispatched |
| `test_engineer_e2e_completed_at` | ISO 8601 string or null | When `test-engineer --e2e=true` completed |
| `browser_agent_reproduce_completed_at` | ISO 8601 string or null | When `browser-agent --phase reproduce` completed |
| `browser_agent_verify_completed_at` | ISO 8601 string or null | When `browser-agent --phase verify` completed |

### Step-mode abort state

When user aborts with `a` in `--step-mode`, the following fields are written:

```json
{
  "outcome": "paused",
  "pause_reason": "step_mode_abort",
  "last_completed_step": "04-fixer-reviewer-loop",
  "paused_at": "2026-04-27T10:30:00Z"
}
```

Re-invoking the original entry-point skill (`/agent-flow:fix-bugs {ID}`,
`/agent-flow:implement-feature {ID}`, or `/agent-flow:scaffold {ID}`) triggers inline
auto-resume detection (`core/resume-detection.md`) which reads
`pause_reason == "step_mode_abort"` and continues from `last_completed_step + 1` with the mode
flag provided at resume time (default / `--yolo` / `--step-mode`).

`last_completed_step` is written to `state.json` ONLY after the step fully completes (atomic).
A SIGTERM before the write causes the step to re-execute on resume.

---

## Hooks

Hooks are per-stage extensibility points defined in the project's `## Automation Config` under
`### Hooks`. They are **skill-orchestrated, not agent-frontmatter** — the plugin permission
constraint prohibits `hooks:`, `mcpServers:`, and `permissionMode:` keys in agent frontmatter
(platform-blocked by Claude Code). Hooks are invoked at the skill level using `Bash` tool calls.

**Four hook points (all pipelines):**

| Hook | When it fires | Automation Config key |
|------|--------------|----------------------|
| Pre-fix | Before `fixer` dispatch (after code analysis) | `Pre-fix` |
| Post-fix | After `fixer` + `reviewer` approve, before test | `Post-fix` |
| Pre-publish | After tests pass, before `publisher` dispatch | `Pre-publish` |
| Post-publish | After PR created, before pipeline end | `Post-publish` |

Hooks are Bash commands or script paths. Custom agents (`Post-fix agent`, `Pre-publish agent`) may
be configured in `### Custom Agents` and are invoked at the corresponding hook point by the skill
using `Task`.

Example `### Hooks` config block:

```
### Hooks

| Key | Value |
|-----|-------|
| Pre-fix | make lint |
| Post-fix | make smoke |
| Pre-publish | |
| Post-publish | scripts/notify-deploy.sh |
```

Hook failure is **blocking** by default (non-zero exit blocks the pipeline). For advisory-only
hooks, prefix with `|| true`.

**Exception — Post-publish is warning-only by design.** By the time Post-publish fires, the PR
already exists, so there is nothing left to roll back. A non-zero exit from the `Post-publish`
hook (or a BLOCK from the `Post-publish agent`) logs `[WARN] Post-publish hook failed: {error}`
and the pipeline continues to completion — it never blocks or rolls back. See
`docs/reference/pipelines.md` for full hook semantics and `core/post-publish-hook.md` for the
authoritative Post-publish failure-handling and webhook delivery contract.
