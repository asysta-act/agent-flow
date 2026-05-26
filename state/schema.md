# State Schema Reference

This document defines the structure of `.agent-flow/{RUN-ID}/state.json`, the pipeline run state file written and updated by agent-flow commands.

> **Note:** The six per-stage usage fields (`tokens_used`, `duration_ms`, `tool_uses`, `model`, `started_at`, `completed_at`) and the top-level `pipeline` accumulator are additive additions. `schema_version` remains `"1.0"`. Older readers that do not recognize these fields will ignore them — no schema version bump is needed.

## Directory Layout

```
.agent-flow/
  {RUN-ID}/
    state.json
    pipeline.log
    reproduction-result.json     (if browser reproduction ran)
    reproduction-script.js        (if browser reproduction ran)
    verification-result.json     (if browser verification ran)
    screenshots/                 (if screenshots taken)
```

## RUN-ID Determination

| Pipeline type | RUN-ID format | Example |
|---------------|--------------|---------|
| Issue tracker pipeline | `{ISSUE-ID}_{YYYYMMDDTHHMMSSZ}` | `PROJ-42_20260418T133000Z` |
| Scaffold pipeline without issue | `scaffold-{timestamp}` | `scaffold-20260322-143000` |
| Non-tracker pipeline (analysis, strategy, content) | `build-{timestamp}` | `build-20260322-143000` |
| check-deploy | `deploy-{timestamp}` | `deploy-20260327-120000` |
| Sprint planning (`sprint-planning`) | `sprint-{YYYYMMDD-HHmmss}` | `sprint-20260413-143000` |
| Backlog creation (`backlog-creation`) | `backlog-{YYYYMMDD-HHmmss}` | `backlog-20260413-143000` |

Timestamp format: `YYYYMMDD-HHmmss` (local time of pipeline start).

## Full Schema Example

```json
{
  "schema_version": "1.0",
  "run_id": "PROJ-42_20260418T133000Z",
  "parent_run_id": null,
  "mode": "code-bugfix",
  "pipeline": {
    "total_tokens": 250700,
    "total_duration_ms": 692000,
    "total_tool_uses": 183,
    "summary_table": "| Stage | Model | Tokens | Duration | Tools |\n|---|---|---|---|---|\n| triage | sonnet | 12,500 | 45s | 8 |\n| code_analysis | sonnet | 18,200 | 62s | 12 |\n| fixer_reviewer | opus | 201,000 | 525s | 147 |\n| test | sonnet | 15,800 | 48s | 11 |\n| publisher | haiku | 3,200 | 12s | 5 |\n| **Total** |  | 250,700 | 692s | 183 |"
  },
  "status": "running",
  "plugin_version": "6.8.0",
  "started_at": "ISO-8601",
  "updated_at": "ISO-8601",
  "config": {
    "profile": "default",
    "flags": [],
    "retry_limits": {
      "fixer_iterations": 5,
      "test_attempts": 3,
      "build_retries": 3,
      "spec_iterations": 5,
      "root_cause_iterations": 3
    }
  },
  "infrastructure": {
    "tracker_status": "ready",
    "tracker_type": "gitea",
    "tracker_instance": "https://gitea.example.com",
    "tracker_project": "owner/repo",
    "sc_status": "later",
    "sc_remote": null,
    "sc_base_branch": "main"
  },
  "triage": {
    "status": "completed",
    "severity": "MEDIUM",
    "area": "auth",
    "complexity": "S",
    "acceptance_criteria": ["AC-1: ...", "AC-2: ..."],
    "reproduction_steps": null,
    "ac_source": "analyst",
    "tokens_used": 12500,
    "duration_ms": 45000,
    "tool_uses": 8,
    "model": "sonnet",
    "started_at": "2026-04-17T14:30:00Z",
    "completed_at": "2026-04-17T14:30:45Z"
  },
  "code_analysis": {
    "status": "pending",
    "risk": null,
    "affected_files": [],
    "estimated_diff_lines": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "reproduction": {
    "status": "pending",
    "script_path": null,
    "result_path": null,
    "verdict": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "fixer_reviewer": {
    "status": "pending",
    "iterations": 0,
    "max_iterations": 5,
    "last_verdict": null,
    "ac_fulfillment": {},
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "decomposition": {
    "status": "pending",
    "decision": null,
    "subtasks": [],
    "strategy": null
  },
  "test": {
    "status": "pending",
    "attempts": 0,
    "max_attempts": 3,
    "last_result": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "e2e_test": {
    "status": "pending",
    "verdict": null,
    "result_path": null,
    "attempts": 0,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "browser_verification": {
    "status": "pending",
    "result_path": null,
    "verdict": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "acceptance_gate": {
    "status": "pending",
    "verdict": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "publisher": {
    "status": "pending",
    "pr_url": null,
    "branch": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "started_at": null,
    "completed_at": null
  },
  "hooks": {
    "pre_fix": null,
    "post_fix": null,
    "pre_publish": null,
    "post_publish": null
  },
  "block": null,
  "deployment": {
    "status": "completed",
    "verdict": "HEALTHY",
    "type": "docker",
    "health_check": "http://localhost:3000/health",
    "ports": [3000, 5432],
    "started_at": "ISO-8601",
    "verified_at": "ISO-8601",
    "result_path": null,
    "tokens_used": 0,
    "duration_ms": 0,
    "tool_uses": 0,
    "model": null,
    "completed_at": null
  }
}
```

## Top-Level Field Definitions

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `schema_version` | string | Yes | `"1.0"` | Schema version. Always `"1.0"` for this specification. Enables future schema evolution. |
| `run_id` | string | Yes | — | Unique identifier for this pipeline run. See RUN-ID Determination above. |
| `parent_run_id` | string or null | No | `null` | Run ID of the parent pipeline that spawned this run. Set when scaffold creates sub-runs for feature implementation. |
| `mode` | string | Yes | — | One of: `code-bugfix`, `code-feature`, `code-project`, `analysis`, `strategy`, `content`. |
| `pipeline` | object or null | No | `null` | Top-level cost accumulator written once at pipeline end. See Pipeline Accumulator Fields below. |
| `status` | string | Yes | `"running"` | Pipeline run status. Enum: `"running"`, `"completed"`, `"blocked"`, `"failed"`, `"paused"`, `"aborted_by_system"`. `"paused"` means the pipeline is waiting for human clarification; `"aborted_by_system"` means the pipeline was automatically terminated (see `abort_reason`). |
| `abort_reason` | string or null | No | `null` | Machine-readable reason for `"aborted_by_system"` termination. Field key: `"abort_reason"`. Currently defined value: `"clarification_timeout"` (set by autopilot discovery scan when pause timeout elapses since `clarification.asked_at`). Null for all other terminal statuses. |
| `started_at` | ISO 8601 string | Yes | — | When the pipeline run started. |
| `updated_at` | ISO 8601 string | Yes | — | Timestamp of the last state file write. |
| `plugin_version` | string or null | No | `null` | Plugin version from `.claude-plugin/plugin.json` at pipeline start. |
| `config` | object | Yes | — | Active configuration for this run. |
| `config.profile` | string or null | Yes | `null` | Active pipeline profile name, or null if none. |
| `config.flags` | string[] | Yes | `[]` | CLI flags passed to the command (e.g., `["--yolo"]`). |
| `config.retry_limits` | object | Yes | — | Active retry limits (resolved from Automation Config or defaults). |
| `config.retry_limits.fixer_iterations` | integer | Yes | `5` | Max fixer-reviewer loop iterations. |
| `config.retry_limits.test_attempts` | integer | Yes | `3` | Max test-engineer retry attempts. |
| `config.retry_limits.build_retries` | integer | Yes | `3` | Max build retry attempts. |
| `config.retry_limits.spec_iterations` | integer | Yes | `5` | Max spec-writer↔spec-reviewer loop iterations. |
| `config.retry_limits.root_cause_iterations` | integer | Yes | `3` | Max root cause analysis iterations. |
| `infrastructure` | object or null | No | `null` | Infrastructure declarations from scaffold Step 0-INFRA. Persists tracker and SC readiness for resume. Only populated by scaffold pipeline. |
| `infrastructure.tracker_status` | string or null | No | `null` | Tracker readiness: `"ready"`, `"later"`, or `"downgraded"`. |
| `infrastructure.tracker_type` | string or null | No | `null` | Declared tracker type (youtrack/github/jira/linear/gitea/redmine). |
| `infrastructure.tracker_instance` | string or null | No | `null` | Declared tracker instance URL. |
| `infrastructure.tracker_project` | string or null | No | `null` | Declared tracker project key. |
| `infrastructure.sc_status` | string or null | No | `null` | SC readiness: `"ready"`, `"later"`, or `"downgraded"`. |
| `infrastructure.sc_remote` | string or null | No | `null` | Declared SC remote (owner/repo format). |
| `infrastructure.sc_base_branch` | string | No | `"main"` | Declared base branch. |
| `triage` | object | Yes | — | Triage-analyst phase state. |
| `triage.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `triage.severity` | string or null | No | `null` | Bug severity: `HIGH`, `MEDIUM`, or `LOW`. |
| `triage.area` | string or null | No | `null` | Affected system area (free text). |
| `triage.complexity` | string or null | No | `null` | Complexity estimate: `XS`, `S`, `M`, or `L`. |
| `triage.acceptance_criteria` | string[] | No | `[]` | Full AC text items, preserved for resume. |
| `triage.reproduction_steps` | string or null | No | `null` | Reproduction steps for UI-related bugs. |
| `triage.ac_source` | string or null | No | `null` | Origin of acceptance criteria: `"analyst"` (bug-fix pipeline), `"spec-analyst"` (feature pipeline), `"spec-writer"` (scaffold pipeline), or `null` (not yet determined). Used by downstream agents (reviewer, acceptance-gate) to locate the authoritative AC list. |
| `code_analysis` | object | Yes | — | Code-analyst phase state. |
| `code_analysis.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `code_analysis.risk` | string or null | No | `null` | Change risk: `LOW`, `MEDIUM`, or `HIGH`. |
| `code_analysis.affected_files` | string[] | No | `[]` | Paths of affected files identified by analyst. |
| `code_analysis.estimated_diff_lines` | integer or null | No | `null` | Estimated lines changed. |
| `reproduction` | object | Yes | — | Reproducer-agent phase state. |
| `reproduction.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `reproduction.script_path` | string or null | No | `null` | Path to the generated reproduction script. |
| `reproduction.result_path` | string or null | No | `null` | Path to the reproduction result JSON file. |
| `reproduction.verdict` | string or null | No | `null` | Reproduction outcome: `REPRODUCED`, `NOT_REPRODUCED`, or `INCONCLUSIVE`. |
| `fixer_reviewer` | object | Yes | — | Fixer-reviewer loop state. |
| `fixer_reviewer.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `fixer_reviewer.iterations` | integer | Yes | `0` | Number of completed fixer-reviewer iterations. |
| `fixer_reviewer.max_iterations` | integer | Yes | `5` | Maximum allowed iterations (from retry limits). |
| `fixer_reviewer.last_verdict` | string or null | No | `null` | Most recent reviewer verdict: `APPROVED` or `REQUEST_CHANGES`. |
| `fixer_reviewer.ac_fulfillment` | object | No | `{}` | Per-AC fulfillment map from the most recent reviewer pass (keys: `"AC-N"`, values: `"FULFILLED"`, `"PARTIALLY"`, or `"NOT ADDRESSED"`). |
| `decomposition` | object | Yes | — | Decomposition decision state. |
| `decomposition.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `decomposition.decision` | string or null | No | `null` | `DECOMPOSE` or `SINGLE_PASS`. |
| `decomposition.subtasks` | object[] | No | `[]` | List of subtask objects (mirrors decomposition YAML). See Subtask Object Fields below. |
| `decomposition.strategy` | string or null | No | `null` | Commit strategy: `squash` or `per-subtask`. |

### Subtask Object Fields

Each entry in `decomposition.subtasks[]` has the following structure:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | string | Yes | — | Subtask identifier from architect task tree (e.g., `"subtask-1"`). |
| `title` | string | Yes | — | Human-readable subtask title. |
| `status` | string | Yes | `"pending"` | Subtask execution status: `pending`, `in_progress`, `completed`, `failed`, `blocked`. |
| `commit_hash` | string or null | No | `null` | Git SHA of the commit created after successful subtask execution. Null while pending. |
| `restore_point` | string or null | No | `null` | Git SHA before subtask execution started (HEAD~1 or branch creation point for first subtask). Used for per-subtask rollback. |
| `depends_on` | string[] | No | `[]` | IDs of prerequisite subtasks that must complete before this one starts. |
| `scope` | string | No | `null` | Description of the subtask's scope from architect output. |
| `files` | string[] | No | `[]` | List of file paths this subtask will modify. |
| `estimated_lines` | integer or null | No | `null` | Estimated lines changed by this subtask. |
| `acceptance_criteria` | string[] | No | `[]` | Per-subtask acceptance criteria from architect decomposition. |
| `maps_to` | string[] | No | `[]` | Parent AC references in format `AC-{N}: {text}`, linking subtask to parent acceptance criteria by index. |
| `tracker_issue_id` | string or null | No | `null` | Tracker issue ID created for this subtask (e.g., `"PROJ-45"` for YouTrack/Jira, `"#123"` for GitHub/Gitea). Populated by "Create tracker subtasks" step. Used as idempotency guard on resume. |

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `test` | object | Yes | — | Test-engineer phase state. |
| `test.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `test.attempts` | integer | Yes | `0` | Number of completed test attempts. |
| `test.max_attempts` | integer | Yes | `3` | Maximum allowed attempts (from retry limits). |
| `test.last_result` | string or null | No | `null` | Most recent test outcome: `PASSED` or `FAILED`. |
| `e2e_test` | object | Yes | — | E2E-test-engineer phase state. |
| `e2e_test.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `e2e_test.verdict` | string or null | No | `null` | E2E test outcome: `PASSED` or `FAILED`. |
| `e2e_test.result_path` | string or null | No | `null` | Path to the E2E test result file (if stored). |
| `e2e_test.attempts` | integer | No | `0` | Number of E2E test attempts executed. |
| `browser_verification` | object | Yes | — | Browser-verifier phase state. |
| `browser_verification.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `browser_verification.result_path` | string or null | No | `null` | Path to the verification result JSON file. |
| `browser_verification.verdict` | string or null | No | `null` | Verification outcome: `PASS`, `FAIL`, or `INCONCLUSIVE`. |
| `acceptance_gate` | object | Yes | — | Acceptance-gate phase state. |
| `acceptance_gate.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `acceptance_gate.verdict` | string or null | No | `null` | Gate verdict: `PASS` or `FAIL`. |
| `publisher` | object | Yes | — | Publisher phase state. |
| `publisher.status` | string | Yes | `"pending"` | Phase status. See Step Status Enum. |
| `publisher.pr_url` | string or null | No | `null` | URL of the created pull request. |
| `publisher.branch` | string or null | No | `null` | Name of the branch created for the PR. |
| `hooks` | object | Yes | — | Hook execution status. |
| `hooks.pre_fix` | string or null | No | `null` | Pre-fix hook status: `completed`, `failed`, or null (not run). |
| `hooks.post_fix` | string or null | No | `null` | Post-fix hook status: `completed`, `failed`, or null (not run). |
| `hooks.pre_publish` | string or null | No | `null` | Pre-publish hook status: `completed`, `failed`, or null (not run). |
| `hooks.post_publish` | string or null | No | `null` | Post-publish hook status: `completed`, `failed`, or null (not run). |
| `block` | object or null | Yes | `null` | If the pipeline was blocked: `{agent, step, reason, detail, recommendation}`. Null when not blocked. |
| `clarification` | object or null | No | `null` | Present when an agent has emitted `## NEEDS_CLARIFICATION`. Null when not paused or after answered via `resume-ticket --clarification`. See Clarification Object Fields below. |
| `deployment` | object or null | No | `null` | Deployment verification state. Populated by deployment-verifier agent when /check-deploy runs. Contains verdict, type, health_url, ports, timestamps, and result file path. |

### Clarification Object Fields

`clarification` (top-level, optional)

Parallel to the `block` object. Present only when an agent has emitted `## NEEDS_CLARIFICATION`. Cleared (set to `null`) when answered via `resume-ticket --clarification`.

```json
"clarification": {
  "question": "string (max 280 chars)",
  "asked_by_agent": "fixer | analyst",
  "asked_at_step": "string (canonical stage name)",
  "asked_at_iteration": "integer or null",
  "asked_at": "ISO 8601 string (UTC, written at detection)",
  "context": "string (optional, max 500 chars)",
  "answer": "string or null",
  "clarifications_consumed": "integer (run total, max 3, hard cap)",
  "last_clarification_iteration": "integer or null (most recent fixer iteration that emitted NEEDS_CLARIFICATION)"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `clarification.question` | string (max 280 chars) | The question the agent needs answered before continuing. |
| `clarification.asked_by_agent` | string | Agent that emitted NEEDS_CLARIFICATION: `"fixer"` or `"analyst"`. |
| `clarification.asked_at_step` | string | Canonical stage name from the skill orchestrator (e.g., `"fixer_reviewer"`, `"triage"`). |
| `clarification.asked_at_iteration` | integer or null | Current fixer iteration at the time of the clarification, or `null` when emitted during triage. |
| `clarification.asked_at` | ISO 8601 string | UTC timestamp of when the clarification was detected and persisted (written by skill orchestrator at detection time, format `YYYY-MM-DDTHH:MM:SSZ`). Read by autopilot's pause-state detection to compute `pause_age_seconds = now − asked_at` against the configured pause timeout. MUST be written at every detection site; absence causes autopilot to compute the full epoch as the pause age and prematurely abort the issue. |
| `clarification.context` | string or null | Optional additional context provided by the agent (max 500 chars). `null` when absent. |
| `clarification.answer` | string or null | Human-provided answer, written by `resume-ticket --clarification`. `null` until answered. |
| `clarification.clarifications_consumed` | integer | Running total of clarifications consumed this run (max 3). Incremented EXACTLY ONCE per clarification round-trip — at NEEDS_CLARIFICATION detection by the skill orchestrator, BEFORE transitioning to `paused`. The increment-side-of-truth lives in skill orchestrators (fix-bugs, implement-feature, scaffold). Hard cap enforced by skill orchestrators. |
| `clarification.last_clarification_iteration` | integer or null | Fixer iteration index of the most recent NEEDS_CLARIFICATION emission. Used by per-iteration cap check. `null` when no fixer iteration has emitted a clarification yet. |

DoS caps enforced by skill orchestrators (see `core/agent-states.md` Section 2):
- `clarifications_consumed >= 3` AND new NEEDS_CLARIFICATION emitted → transition to `block` with reason `"exceeded max clarifications (3 per run)"`.
- `last_clarification_iteration == current iteration` AND new NEEDS_CLARIFICATION emitted in same iteration → transition to `block` with reason `"clarification limit per iteration exceeded"`.

### Sensitive field exclusion contract

`block.detail` MAY include source code excerpts, stack traces, and credentials embedded in error messages. This is a HARD CONTRACT — every channel where `block.detail` may surface is enumerated below with explicit `INCLUDE` / `EXCLUDE` status. Future maintainers adding new channels MUST update this table.

| Channel | Status | Rationale |
|---------|--------|-----------|
| `/metrics --format json` output | EXCLUDE | `top_reasons[].reason` uses `block.reason` only (sanitized 2-sentence summary). `block.detail` never serialized. |
| `.agent-flow/pipeline-history.md` | EXCLUDE | `block_reason` row uses `block.reason` only, additionally filtered through `sanitize_block_reason()` (18-pattern POSIX-portable redaction; see `core/post-publish-hook.md` Section 5). |
| `pipeline-completed` webhook payload | EXCLUDE | Payload `block` object includes `reason` only. `detail` never included. |
| `issue-blocked` (`agent-flow-block`) webhook payload | EXCLUDE | Payload `block` object includes `reason` only. `detail` never included. |
| `pipeline-paused` webhook payload | EXCLUDE | Payload includes `clarification.question` (sanitized) only. `block.detail` never relevant for pause; full exclusion. |
| Issue tracker block COMMENT (`core/block-handler.md`) | INCLUDE — first 100 chars only, redacted | Human-readable debugging requires SOME detail. Posts `Detail: {first 100 chars of block.detail filtered through sanitize_block_reason()}`. Full unredacted detail available only via local `state.json` read. |
| `state.json` on disk (`.agent-flow/{run-id}/state.json`) | INCLUDE — full text, operator-controlled location | Operator-controlled local file; not transmitted. Operators in multi-user environments SHOULD treat `.agent-flow/` as sensitive (advisory). |
| Future analytics/export skills | EXCLUDE — default | Any new consumer MUST update this table when introduced. Default posture is EXCLUDE unless explicitly justified. |

Violations are caught by test scenarios in `tests/scenarios/` that inject sensitive values into `block.detail` and assert they do NOT appear in JSON output, pipeline-history.md, or block-handler comment posts.

### Pipeline Accumulator Fields

Written once at pipeline end (before terminal status write).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pipeline.total_tokens` | integer | `0` | Sum of `tokens_used` across all completed stages. |
| `pipeline.total_duration_ms` | integer | `0` | Sum of `duration_ms` across all completed stages. |
| `pipeline.total_tool_uses` | integer | `0` | Sum of `tool_uses` across all completed stages. |
| `pipeline.summary_table` | string | `null` | Markdown table string for human display. Bounded by COST-R10: max 20 data rows and 4000 characters; when the limit is exceeded, truncation is row-wise (never mid-row) and a truncation notice row `| ... | (truncated, N more stages in pipeline.log) | ... |` is appended immediately before the `Total` row. Consumers SHOULD derive their own tables from the structured fields above rather than parsing this string; the markdown layout may evolve without a schema_version bump. |

### Stage metadata (additive)

#### `stages.{stage}.dispatched_at`

- **Type:** ISO-8601 UTC timestamp (string)
- **Purpose:** Populated when a pipeline stage dispatches its subagent via Task tool. Consumed by PostToolUse hook `hooks/validate-dispatch.sh` for dispatch enforcement audit.
- **Absence:** field MAY be absent for stages completed in older pipeline runs. The PostToolUse hook treats absence as MISSING (audit-log line), NEVER as a pipeline failure.
- **Added by:** orchestrator, immediately before Task tool dispatch.

Applies to all stages in the hardcoded `STAGES` whitelist (10 entries): `triage`, `code_analysis`, `reproduce_browser`, `fixer_reviewer`, `smoke_check`, `test`, `e2e_test`, `browser_verification`, `acceptance_gate`, `publisher`.

#### `stages.{stage}.dispatch_witness`

- **Type:** string (lowercase hex sha256, exactly 64 characters; pattern `^[0-9a-f]{64}$`)
- **Purpose:** Cryptographic receipt of the Task() dispatch parameters, computed before Task tool invocation. Consumed by PostToolUse hook `hooks/validate-dispatch.sh` via `core/lib/stage-invariant.sh::check_dispatch_witness` for runtime dispatch enforcement audit.
- **Absence:** field MAY be absent for stages completed in older pipeline runs or for stages legitimately skipped (legitimate skips write `status: "skipped"` separately). The PostToolUse hook treats absence as `WITNESS_MISSING` (audit-log line), NEVER as a pipeline failure unless `CEOS_STRICT_DISPATCH=1` is set (in which case `WITNESS_MISMATCH` - not MISSING - causes exit 2).
- **Added by:** orchestrator, immediately before Task tool dispatch, in the same atomic state.json write as `dispatched_at`, `agent_name`, `stage_name`, and `status = "in_progress"`.
- **Canonicalization:** `sha256("<subagent_type>|<model>|<prompt_head_128>")` where:
  - `subagent_type` = the Task tool's `subagent_type` argument (e.g., `agent-flow:test-engineer`).
  - `model` = the agent's `model:` frontmatter field (e.g., `sonnet`, `opus`, `haiku`).
  - `prompt_head_128` = the first 128 UTF-8-safe bytes of the prompt template string BEFORE Tier-1 variable substitution (i.e., with `${VAR}` placeholders un-expanded). UTF-8 safety means the truncation boundary aligns with the last whole codepoint within the 128-byte budget.
- **Stability guarantee:** the witness is stable across resume cycles (the same template renders to the same witness regardless of how many times the stage is resumed).
- **Applicable stages:** `triage`, `code_analysis`, `reproduce_browser`, `fixer_reviewer`, `smoke_check`, `test`, `e2e_test`, `browser_verification`, `acceptance_gate`, `publisher` (the 10-stage STAGES whitelist in `hooks/validate-dispatch.sh:22`).
- **Schema version impact:** `schema_version` REMAINS `"1.0"`. This field is additive — additive fields do NOT bump schema_version.

#### `stages.{stage}.agent_name`

- **Type:** string (Task subagent_type, e.g., `"agent-flow:fixer"`, `"agent-flow:test-engineer"`)
- **Purpose:** Cross-check anchor for L3 agent self-verification. The agent reads this field at runtime and compares it against the prompt-injected `EXPECTED_AGENT_NAME` variable to verify dispatch integrity.
- **Absence:** field MAY be absent in state.json blocks for stages completed in older pipeline runs. Agent self-check treats absence as a Block condition (Reason: `completion_invariant_violated:agent_name_absent`).
- **Added by:** orchestrator, in the same atomic state.json write as `dispatched_at` and `dispatch_witness`, immediately before Task() dispatch.
- **Companion prompt variable:** the orchestrator separately injects `EXPECTED_AGENT_NAME=<this value>` as a Tier-1 prompt template variable so the agent has an orchestrator-supplied reference value to compare against (non-vacuity).
- **Used by:** all 17 agents via the `## Step Completion Invariants` section; PostToolUse hook does NOT consume this field directly.
- **Schema version impact:** `schema_version` REMAINS `"1.0"`. Additive.

#### `stages.{stage}.stage_name`

- **Type:** string (canonical stage name from the 10-stage list - `"triage"`, `"code_analysis"`, `"reproduce_browser"`, `"fixer_reviewer"`, `"smoke_check"`, `"test"`, `"e2e_test"`, `"browser_verification"`, `"acceptance_gate"`, `"publisher"`)
- **Purpose:** Cross-check anchor for L3 agent self-verification. The agent reads this field at runtime and compares it against the prompt-injected `EXPECTED_STAGE_NAME` variable to verify dispatch integrity.
- **Redundancy with stages map key:** yes - the value matches the parent key in the `stages.<stage>` map. The redundancy is deliberate: a misbehaving orchestrator that constructs the parent key as `"foo"` but writes `stage_name = "bar"` inside that block produces an internal inconsistency the agent's check catches.
- **Absence:** field MAY be absent in state.json blocks for stages completed in older pipeline runs. Agent self-check treats absence as a Block condition (Reason: `completion_invariant_violated:stage_name_absent`).
- **Added by:** orchestrator, in the same atomic state.json write as `dispatched_at`, `dispatch_witness`, and `agent_name`, immediately before Task() dispatch.
- **Companion prompt variable:** the orchestrator separately injects `EXPECTED_STAGE_NAME=<this value>` as a Tier-1 prompt template variable.
- **Used by:** all 17 agents via the `## Step Completion Invariants` section.
- **Schema version impact:** `schema_version` REMAINS `"1.0"`. Additive.

#### Threat model (dispatch witness - honest acknowledgment)

The `dispatch_witness` field is a **dispatch RECEIPT, not a cryptographic ATTESTATION**. The threat model is explicit about three properties:

1. **Witness attests "orchestrator WROTE the witness," not "subagent RAN."** All three witness inputs (`subagent_type`, `model`, `prompt_head_128`) are public - anyone with read access to the repo can compute the expected witness. An orchestrator that silently skips Task() can ALSO write the correct witness to state.json with no Task() invocation, producing WITNESS_OK indistinguishable from a real dispatch.
2. **Defense relies on COMBINATION** of L2 (witness presence) + L1 (thin-controller prose forces the orchestrator's mental model toward the dispatch table) + L4 (terminal surface for residual anomalies). No single layer is sufficient against an adversarial or hallucinating orchestrator.
3. **Pre-dispatch write + crash window:** if the orchestrator writes both `dispatched_at` and `dispatch_witness` atomically then crashes before Task(), the witness is present but the subagent never ran. Hook reports WITNESS_OK. Resume detection treats `dispatched_at` + `status="in_progress"` as "agent was dispatched but didn't complete" and may resume from the next stage. This is a known limitation; mitigation relies on L1 (thin-controller minimizes the window) and L4 (resumed run will surface the inconsistency in the audit log).

Future hardening (deferred): a post-dispatch witness-confirmation written by the subagent (rather than by the orchestrator) would attest subagent execution. The current design explicitly accepts the receipt-not-attestation tradeoff.

**Witness compatibility on prompt edits:** witness changes are EXPECTED on prompt template edits and are NOT a contract violation. Harness fixtures (`tests/fixtures/witness/state-*.json`) MUST be refreshed alongside any prompt-template change.

### Per-Stage Usage Fields

Applied additively to every stage object. All pre-existing stage fields remain unchanged.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tokens_used` | integer | `0` | Token count consumed by this stage's agent dispatch. Sourced from `result.usage.total_tokens` (or equivalent discovered field). Written as `0` when `result.usage` is null or absent. |
| `duration_ms` | integer | `0` | Wall-clock duration of the agent dispatch in milliseconds. Written as `0` when absent. |
| `tool_uses` | integer | `0` | Number of tool invocations by the agent during this stage. Written as `0` when absent. |
| `model` | string or null | `null` | Model used by the dispatched agent (e.g., `"sonnet"`, `"opus"`, `"haiku"`). Derived from the `model:` frontmatter field of `agents/{agent-name}.md` at dispatch time. |
| `started_at` | ISO 8601 string or null | `null` | Timestamp written before agent dispatch (when stage transitions to `in_progress`). |
| `completed_at` | ISO 8601 string or null | `null` | Timestamp written after agent dispatch completes (when stage transitions to `completed` or `failed`). |

### Fixer-Reviewer Cumulative Semantics

`fixer_reviewer.tokens_used`, `fixer_reviewer.duration_ms`, and `fixer_reviewer.tool_uses` are **cumulative across all iterations**, not per-iteration snapshots. After iteration N completes, these fields hold the running sum of all N iterations combined (e.g., after 3 iterations: `tokens_used = iter1 + iter2 + iter3`). No per-iteration breakdown array is stored in state.json — that granularity is available in `pipeline.log` via `fixer_iteration` events.

### Deployment Object Fields

| Field | Type | Description |
|-------|------|-------------|
| `deployment.status` | string | Deployment phase status. Subset of Step Status Enum: `pending`, `in_progress`, `completed`, `failed` |
| `deployment.verdict` | string | Overall deployment verdict: `HEALTHY`, `UNHEALTHY`, `PORT_CONFLICT`, `START_FAILED`, or `SKIPPED` |
| `deployment.type` | string | `docker` or `native` |
| `deployment.health_check` | string | Health check URL that was polled for readiness |
| `deployment.health_url` | string | Alias for health_check (backward compatibility) |
| `deployment.ports` | array of int | Ports used by the deployment |
| `deployment.started_at` | string | ISO 8601 timestamp of service start |
| `deployment.verified_at` | string | ISO 8601 timestamp of health check pass |
| `deployment.result_path` | string | Path to detailed result JSON |

### Reading older state.json files

All six per-stage usage fields and the top-level `pipeline` accumulator are **optional**. A state.json that lacks these fields is valid. Consumers MUST default absent usage fields to `0` (integers) or `null` (strings/objects). The `pipeline` object, when absent, is treated as `{total_tokens: 0, total_duration_ms: 0, total_tool_uses: 0, summary_table: null}`. `/metrics` treats any state.json where `pipeline.total_tokens` is absent as ESTIMATED and applies heuristic constants rather than summing zero.

### Sprint State Object

Used when `mode` is `sprint-planning` (pipeline: `sprint-plan`). The `sprint` object replaces the per-phase objects (triage, fixer_reviewer, etc.) that are not applicable to this mode.

```json
{
  "mode": "sprint-planning",
  "sprint": {
    "name": "Sprint 2026-W16",
    "duration": "2 weeks",
    "effective_capacity": 40,
    "capacity_unit": "story-points",
    "velocity_source": "heuristic",
    "issues": [
      {
        "issue_id": "AUTH-1",
        "tier": "P0",
        "effort_points": 5,
        "type": "feature",
        "sprint_assigned": true,
        "child_run_id": null,
        "status": "selected"
      }
    ],
    "completed_issues": [],
    "blocked_issues": []
  }
}
```

#### Sprint Object Fields

| Field | Type | Description |
|-------|------|-------------|
| `sprint.name` | string | Human-readable sprint name (e.g., `"Sprint 2026-W16"`). |
| `sprint.duration` | string | Sprint length (e.g., `"2 weeks"`). |
| `sprint.effective_capacity` | integer | Total capacity available for this sprint in `capacity_unit`. |
| `sprint.capacity_unit` | string | Unit for capacity and effort: `"story-points"` or `"hours"`. |
| `sprint.velocity_source` | string | How capacity was determined: `"historical"`, `"heuristic"`, or `"manual"`. |
| `sprint.issues` | object[] | Ordered list of issues selected or evaluated for the sprint. |
| `sprint.issues[].issue_id` | string | Tracker issue ID (e.g., `"AUTH-1"`). |
| `sprint.issues[].tier` | string | Priority tier from priority-engine: `"P0"`, `"P1"`, `"P2"`, or `"P3"`. |
| `sprint.issues[].effort_points` | integer | Effort estimate in `capacity_unit`. |
| `sprint.issues[].type` | string | Issue type: `"bug"`, `"feature"`, or `"task"`. |
| `sprint.issues[].sprint_assigned` | boolean | Whether this issue was assigned to the sprint. |
| `sprint.issues[].child_run_id` | string or null | RUN-ID of the child pipeline spawned for this issue. Null until execution starts. |
| `sprint.issues[].status` | string | Issue execution status: `"selected"`, `"pending"`, `"in_progress"`, `"completed"`, `"blocked"`, `"skipped"`. |
| `sprint.completed_issues` | array | Issues that have finished execution (subset of `issues`). |
| `sprint.blocked_issues` | array | Issues that were blocked during execution (subset of `issues`). |

### Backlog State Object

Used when `mode` is `backlog-creation` (pipeline: `create-backlog`). The `backlog` object replaces the per-phase objects that are not applicable to this mode.

```json
{
  "mode": "backlog-creation",
  "backlog": {
    "spec_path": "spec/",
    "epics_total": 4,
    "epics_created": 3,
    "epics_failed": 1,
    "subtasks_created": 0,
    "created_issues": [
      {"title": "Epic 1", "tracker_id": "AUTH-1", "size": "M", "sp": 3}
    ]
  }
}
```

#### Backlog Object Fields

| Field | Type | Description |
|-------|------|-------------|
| `backlog.spec_path` | string | Path to the specification directory used as the source (e.g., `"spec/"`). |
| `backlog.epics_total` | integer | Total number of epics parsed from the specification. |
| `backlog.epics_created` | integer | Number of tracker issues successfully created so far. |
| `backlog.epics_failed` | integer | Number of epics that failed to create a tracker issue. |
| `backlog.subtasks_created` | integer | Total number of subtask tracker issues created (0 if subtask creation not enabled). |
| `backlog.created_issues` | object[] | List of successfully created tracker issues. |
| `backlog.created_issues[].title` | string | Epic title as written in the specification. |
| `backlog.created_issues[].tracker_id` | string | Tracker issue ID assigned to this epic (e.g., `"AUTH-1"`). |
| `backlog.created_issues[].size` | string | T-shirt size estimate: `"XS"`, `"S"`, `"M"`, `"L"`, or `"XL"`. |
| `backlog.created_issues[].sp` | integer | Story points assigned to this issue. |

## Merged-Agent Additive Keys

> **Note:** The following keys correspond to the merged agents in the current agent consolidation (18 agents). All keys are optional and additive. `schema_version` remains `"1.0"`. Older readers that do not recognise these fields will ignore them — no schema version bump is required.

### Top-level additive fields

| Key | Type | Description |
|-----|------|-------------|
| `analyst_triage_completed_at` | ISO 8601 string or null | Timestamp when `analyst --phase triage` completed. Null until triage phase finishes. |
| `analyst_impact_completed_at` | ISO 8601 string or null | Timestamp when `analyst --phase impact` completed. Null until impact phase finishes. |
| `test_engineer_e2e_invoked` | boolean | `true` when test-engineer was dispatched with `--e2e=true`; `false` otherwise. Written at test-engineer dispatch. |
| `test_engineer_e2e_completed_at` | ISO 8601 string or null | Timestamp when `test-engineer --e2e=true` completed. Null if `--e2e` was not invoked. |
| `browser_agent_verify_completed_at` | ISO 8601 string or null | Timestamp when `browser-agent --phase verify` completed. Null if not invoked. |

### Example

```json
{
  "schema_version": "1.0",

  "analyst_triage_completed_at": "2026-04-27T10:05:00Z",
  "analyst_impact_completed_at": "2026-04-27T10:08:00Z",
  "test_engineer_e2e_invoked": false,
  "test_engineer_e2e_completed_at": null,
  "browser_agent_reproduce_completed_at": null,
  "browser_agent_verify_completed_at": null
}
```

### Scaffold MCP pending keys (additive, scaffold pipeline only)

When the scaffold skill's 0-MCP step is interrupted because the user chose "Configure now" to set
up a missing MCP server, the orchestrator writes the following top-level keys atomically (written
BEFORE displaying the STOP message). These keys are cleared (set to `false` / removed) once Step
01c reaches its natural end — i.e., all declared-ready services have either passed the MCP check
or been downgraded/skipped:

| Field | Type | Description |
|-------|------|-------------|
| `mcp_setup_pending` | boolean | `true` while the pipeline is paused awaiting MCP configuration. Set to `false` once 0-MCP completes (pass, skip, or downgrade). Never present in bug-fix or implement-feature state files. |
| `mcp_pause_step` | string | Name of the step where the pause occurred — always `"0-MCP"` for this sentinel. Distinct from `paused_at` (ISO 8601 timestamp) to avoid schema collision. |
| `status` | string | Set to `"paused"` at the same atomic write. Resume-detection Step 6 routes `"paused"` to the interactive resume prompt; autopilot Pause timeout applies. |

**Clearing protocol:** The clear write (`mcp_setup_pending: false`) is the exclusive responsibility
of Step 01c in `skills/scaffold/steps/01-mode-resolve.md`. The SKILL.md Resume Detection section
does NOT clear the marker — it only reads it.

---

### Step-mode abort keys (additive)

When the user aborts with `a` in `--step-mode`, skill orchestrators write the following top-level keys atomically (written ONLY AFTER the in-progress step has completed — never mid-step; a SIGTERM before the write leaves these keys absent, causing resume-detection to re-execute the interrupted step from scratch):

| Field | Type | Description |
|-------|------|-------------|
| `outcome` | string | Set to `"paused"` — graceful pause (exit 0), not an error. |
| `pause_reason` | string | Set to `"step_mode_abort"` — machine-readable signal consumed by resume-detection. |
| `last_completed_step` | string | Step name that completed before the abort (e.g., `"04-fixer-reviewer-loop"`). Resume continues from `last_completed_step + 1`. |
| `paused_at` | ISO 8601 string | UTC timestamp when the abort was detected. |

`last_completed_step` is written to `state.json` ONLY after the step fully completes (write-after-complete atomicity). A SIGTERM or interrupt before the write causes `last_completed_step` to remain at the previous value — the in-flight step is NOT recorded as done and will be re-executed on resume.

## Step Status Enum

All `status` fields within phase objects use the following values:

| Value | Meaning |
|-------|---------|
| `pending` | Phase has not started yet. |
| `in_progress` | Phase is currently executing. |
| `completed` | Phase finished successfully. |
| `failed` | Phase encountered an unrecoverable error. |
| `skipped` | Phase was intentionally bypassed (profile, config, or condition). |
| `blocked` | Phase blocked the pipeline; see top-level `block` field for details. |
| `awaiting_clarification` | Phase is paused, waiting for human clarification via `resume-ticket --clarification`. Pipeline top-level `status` is `paused` while any phase is in this state. |
| `not_applicable` | Phase does not apply to this pipeline mode or configuration. |

## Atomic Write Protocol

State file writes follow this protocol to prevent corruption: (1) Serialize to JSON. (2) Write to `.agent-flow/{RUN-ID}/state.json.tmp`. (3) Rename atomically to `state.json`. (4) On rename failure: retry once after 100 ms. (5) On second failure: log to `pipeline.log` and continue (state loss is non-fatal). The temp file is always in the same directory to ensure an atomic same-filesystem rename.

## Event Log Format (pipeline.log)

`pipeline.log` is an append-only JSONL file — one JSON object per line, no trailing comma, newline-terminated. Every event carries a `ts` (ISO 8601 timestamp) and an `event` field.

**Example entries:**

```jsonl
{"ts":"2026-03-22T14:30:00Z","event":"pipeline_start","run_id":"PROJ-123_20260322T143000Z","mode":"code-bugfix","pipeline":"fix-ticket"}
{"ts":"2026-03-22T14:30:05Z","event":"phase_start","phase":"triage","agent":"analyst"}
{"ts":"2026-03-22T14:31:20Z","event":"phase_complete","phase":"triage","agent":"analyst","duration_s":75}
{"ts":"2026-03-22T14:31:21Z","event":"phase_start","phase":"code_analysis","agent":"analyst"}
{"ts":"2026-03-22T14:32:00Z","event":"phase_complete","phase":"code_analysis","agent":"analyst","duration_s":39}
{"ts":"2026-03-22T14:32:01Z","event":"fixer_iteration","iteration":1,"verdict":"REQUEST_CHANGES"}
{"ts":"2026-03-22T14:35:00Z","event":"fixer_iteration","iteration":2,"verdict":"APPROVED"}
{"ts":"2026-03-22T14:40:00Z","event":"pipeline_complete","run_id":"PROJ-123_20260322T143000Z","status":"completed","pr_url":"https://github.com/owner/repo/pull/99"}
```

**Event type reference:**

| Event | Required extra fields | When emitted |
|-------|-----------------------|--------------|
| `pipeline_start` | `run_id`, `mode`, `pipeline` | Pipeline begins (first write). |
| `pipeline_complete` | `run_id`, `status`, `pr_url` (if applicable) | Pipeline ends for any reason. |
| `phase_start` | `phase`, `agent` | A phase begins execution. |
| `phase_complete` | `phase`, `agent`, `duration_s` | A phase finishes successfully. |
| `phase_skip` | `phase`, `reason` | A phase is skipped (profile, config, or condition). |
| `phase_fail` | `phase`, `agent`, `error` | A phase fails unrecoverably. |
| `fixer_iteration` | `iteration`, `verdict` | Each completed fixer-reviewer loop iteration. Per-iteration token granularity for fixer_reviewer is available here (not in state.json). |
| `block` | `agent`, `step`, `reason` | Pipeline is blocked by an agent. |
