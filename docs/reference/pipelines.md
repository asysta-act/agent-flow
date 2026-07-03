# Pipeline Reference

agent-flow orchestrates three distinct pipelines, each designed for a specific workflow: fixing bugs, implementing features, and scaffolding new projects. This document provides complete pipeline diagrams, stage tables, profile support, and error handling details.

All pipelines share common patterns:

- **Retry loops** with configurable limits (Retry Limits section in Automation Config)
- **Block/rollback** pattern for error handling (any agent can block; rollback-agent reverts git state)
- **Hook integration** at four points (Pre-fix, Post-fix, Pre-publish, Post-publish)
- **Pipeline profiles** for skipping optional stages

## Bug-Fix Pipeline

The bug-fix pipeline takes a bug from triage through fix, review, test, and publish. It is invoked by `/agent-flow:fix-bugs` (single bug or batch; optional worktrees).

```mermaid
flowchart TD
    START([Start]) --> QUERY[Query Issue Tracker]
    QUERY --> TRIAGE{Triage<br/>analyst --phase triage}
    TRIAGE -->|DUPLICATE| CLOSE[Close Issue]
    TRIAGE -->|UNCLEAR| BLOCK_T[Block Issue]
    TRIAGE -->|OK| CODE_ANALYST[Code Analysis<br/>analyst-impact]

    CODE_ANALYST --> DECOMP{Decomposition<br/>Decision}
    DECOMP -->|SINGLE_PASS| PRE_FIX
    DECOMP -->|DECOMPOSE| ARCHITECT[Architect<br/>architect]
    ARCHITECT --> SUBTASKS[Execute Subtasks<br/>sequentially]
    SUBTASKS --> INTEGRATION[Integration Test]
    INTEGRATION --> PRE_PUBLISH

    PRE_FIX[Pre-fix Hook] --> FIXER[Fix<br/>fixer]
    FIXER --> BUILD{Build}
    BUILD -->|FAIL| BUILD_RETRY{Retries<br/>left?}
    BUILD_RETRY -->|YES| FIXER
    BUILD_RETRY -->|NO| BLOCK_B[Block + Rollback]
    BUILD -->|PASS| POST_FIX[Post-fix Hook<br/>+ Custom Agent]

    POST_FIX --> REVIEWER{Review<br/>reviewer}
    REVIEWER -->|APPROVE| TEST
    REVIEWER -->|REQUEST_CHANGES| ITER{Iterations<br/>left?}
    ITER -->|YES| FIXER
    ITER -->|NO| BLOCK_R[Block + Rollback]
    REVIEWER -->|BLOCK| BLOCK_R

    TEST[Test<br/>test-engineer] --> TEST_RESULT{Tests pass?}
    TEST_RESULT -->|YES| E2E{E2E configured?}
    TEST_RESULT -->|NO| TEST_RETRY{Attempts<br/>left?}
    TEST_RETRY -->|YES| TEST
    TEST_RETRY -->|NO| BLOCK_TE[Block + Rollback]

    E2E -->|YES| E2E_TEST[E2E Test<br/>test-engineer --e2e]
    E2E -->|NO| ACCEPT_CHECK{Acceptance Gate<br/>needed?}
    E2E_TEST --> ACCEPT_CHECK

    ACCEPT_CHECK -->|"AC>=3 or cx>=M"| ACCEPT_GATE[Acceptance Gate<br/>acceptance-gate]
    ACCEPT_CHECK -->|NO| PRE_PUBLISH
    ACCEPT_GATE -->|APPROVE| PRE_PUBLISH
    ACCEPT_GATE -->|REQUEST_CHANGES| FIXER

    PRE_PUBLISH[Pre-publish Hook<br/>+ Custom Agent] --> PUBLISHER[Publish<br/>publisher]
    PUBLISHER --> POST_PUBLISH[Post-publish Hook<br/>+ Webhook]
    POST_PUBLISH --> VERIFY{Verify<br/>configured?}
    VERIFY -->|YES| VERIFY_CMD[Run Verify Command]
    VERIFY -->|NO| DONE([Done])
    VERIFY_CMD --> DONE

    style BLOCK_T fill:#EF4444,color:#fff
    style BLOCK_B fill:#EF4444,color:#fff
    style BLOCK_R fill:#EF4444,color:#fff
    style BLOCK_TE fill:#EF4444,color:#fff
    style CLOSE fill:#6B7280,color:#fff
    style DONE fill:#22C55E,color:#fff
```

### Stages

| Stage | Agent | Model | Skippable | Retries | Notes |
|-------|-------|-------|-----------|---------|-------|
| Triage | analyst --phase triage | sonnet | Yes | None | Blocks on DUPLICATE or UNCLEAR; pauses on NEEDS_CLARIFICATION |
| Code Analysis | analyst-impact | sonnet | Yes | None | Max 5 affected files |
| Decomposition | architect | opus | Auto | None | Triggered by risk/complexity heuristics |
| Create Tracker Subtasks | (skill) | N/A | N/A | None | Creates tracker sub-issues for each decomposition subtask. Skippable via config. |
| Pre-fix Hook | (user-defined) | N/A | N/A | None | Failure triggers block handler |
| Fix | fixer | opus | **No** | Build retries (default: 3) | Diff limit: 100 lines; pauses on NEEDS_CLARIFICATION; signals NEEDS_DECOMPOSITION when scope exceeds 100-line limit |
| Post-fix Hook | (user-defined) | N/A | N/A | None | Runs after successful build |
| Post-fix Agent | (custom agent) | (per agent) | N/A | None | One-shot gate; BLOCK stops pipeline |
| Review | reviewer | opus | **No** | Fixer iterations (default: 5) | Loops with fixer |
| Test | test-engineer | sonnet | Yes | Test attempts (default: 3) | Follows project test conventions |
| E2E Test | test-engineer --e2e | sonnet | Yes | 3 attempts | Requires E2E Test config or profile |
| Acceptance Gate | acceptance-gate | sonnet | Conditional | Fixer iterations (default: 5) | Runs when AC ≥ 3 or complexity ≥ M; always skipped in `--yolo` mode; REQUEST_CHANGES returns to fixer |
| Pre-publish Hook | (user-defined) | N/A | N/A | None | Failure triggers block handler |
| Pre-publish Agent | (custom agent) | (per agent) | N/A | None | One-shot gate |
| Publish | publisher | haiku | **No** | None | Creates PR, updates issue tracker |
| Post-publish Hook | (user-defined) | N/A | N/A | None | Failure is warning only |
| Verify | (skill) | N/A | N/A | None | Runs after PR merge; re-opens issue on failure |

### Hook Integration Points

| Hook | When | On Failure |
|------|------|------------|
| Pre-fix | Before fixer, after code analysis | Block + rollback |
| Post-fix | After successful build, before reviewer | Block + rollback |
| Pre-publish | After all tests pass, before publisher | Block + rollback |
| Post-publish | After PR creation | Warning only (PR already exists) |

### Worktree Mode

When the Worktrees section is configured in Automation Config, `/agent-flow:fix-bugs` processes bugs in parallel using git worktrees:

- **Batch size** controls how many bugs run concurrently (default: 3)
- **Base path** sets the worktree directory (default: `.worktrees/`)
- **Cleanup** determines whether worktrees are removed after completion (`auto` or `manual`)
- Each bug gets its own worktree with an isolated branch
- Block/rollback operates within the worktree context

Without Worktrees config, bugs are processed sequentially in the current working directory.

### Decomposition Decision

The pipeline evaluates analyst-impact output to decide between single-pass and decomposition:

- `risk == HIGH` --> DECOMPOSE
- `affected_files >= 4` --> DECOMPOSE
- `estimated_diff_lines > 60 AND affected_files >= 3` --> DECOMPOSE
- `independent_changes >= 2` --> DECOMPOSE
- Otherwise --> SINGLE_PASS

Use `--decompose` to force decomposition or `--no-decompose` to disable it.

## Feature Pipeline

The feature pipeline adds spec analysis and architecture design stages before the fix/review/test cycle. It is invoked by `/agent-flow:implement-feature`.

```mermaid
flowchart TD
    START([Start]) --> ISSUE[Read Issue from Tracker]
    ISSUE --> SPEC{Spec Analysis<br/>spec-analyst}
    SPEC -->|BLOCK| BLOCK_S[Block Issue]
    SPEC -->|OK| ARCHITECT[Architecture Design<br/>architect]

    ARCHITECT -->|BLOCK| BLOCK_A[Block Issue]
    ARCHITECT -->|OK| DECOMP{Decomposition<br/>Decision}

    DECOMP -->|SINGLE_PASS| SINGLE[Single-pass Execution]
    DECOMP -->|DECOMPOSE| PLAN[Show Plan + Confirm]
    PLAN -->|REJECTED| STOP([User Stopped])
    PLAN -->|APPROVED| SUBTASK_LOOP

    subgraph SUBTASK_LOOP [Per-Subtask Loop]
        direction TB
        PRE_FIX_S[Pre-fix Hook] --> FIXER_S[Fix<br/>fixer]
        FIXER_S --> POST_FIX_S[Post-fix Hook<br/>+ Custom Agent]
        POST_FIX_S --> REVIEWER_S{Review<br/>reviewer}
        REVIEWER_S -->|APPROVE| TEST_S[Test<br/>test-engineer]
        REVIEWER_S -->|REQUEST_CHANGES| FIXER_S
        TEST_S --> E2E_S{E2E?}
        E2E_S -->|YES| E2E_TEST_S[E2E Test]
        E2E_S -->|NO| ACCEPT_GATE_S[Acceptance Gate<br/>acceptance-gate]
        E2E_TEST_S --> ACCEPT_GATE_S
        ACCEPT_GATE_S -->|APPROVE| COMMIT_S[Commit Subtask]
        ACCEPT_GATE_S -->|REQUEST_CHANGES| FIXER_S
    end

    SUBTASK_LOOP --> INTEGRATION[Integration Test]
    INTEGRATION --> SQUASH{Squash?}
    SQUASH -->|YES| SQUASH_CMD[Squash Commits]
    SQUASH -->|NO| PRE_PUB
    SQUASH_CMD --> PRE_PUB

    SINGLE --> PRE_FIX_SINGLE[Pre-fix Hook] --> FIXER_SINGLE[Fix] --> POST_FIX_SINGLE[Post-fix Hook]
    POST_FIX_SINGLE --> REVIEWER_SINGLE{Review} --> TEST_SINGLE[Test] --> ACCEPT_CHECK_SINGLE{AC >= 3?}
    ACCEPT_CHECK_SINGLE -->|YES| ACCEPT_GATE_SINGLE[Acceptance Gate<br/>acceptance-gate]
    ACCEPT_CHECK_SINGLE -->|NO| PRE_PUB
    ACCEPT_GATE_SINGLE -->|APPROVE| PRE_PUB
    ACCEPT_GATE_SINGLE -->|REQUEST_CHANGES| FIXER_SINGLE

    PRE_PUB[Pre-publish Hook<br/>+ Custom Agent] --> SHOW[Show Result + Confirm]
    SHOW -->|PUBLISH| PUBLISHER[Publish<br/>publisher]
    PUBLISHER --> POST_PUB[Post-publish Hook<br/>+ Webhook]
    POST_PUB --> VERIFY{Verify?}
    VERIFY -->|YES| VERIFY_CMD[Run Verify]
    VERIFY -->|NO| DONE([Done])
    VERIFY_CMD --> DONE

    style BLOCK_S fill:#EF4444,color:#fff
    style BLOCK_A fill:#EF4444,color:#fff
    style STOP fill:#6B7280,color:#fff
    style DONE fill:#22C55E,color:#fff
```

### Stages

| Stage | Agent | Model | Skippable | Retries | Notes |
|-------|-------|-------|-----------|---------|-------|
| Spec Analysis | spec-analyst | sonnet | Yes | None | Blocks if request is too vague |
| Architecture | architect | opus | No | None | Produces task tree YAML for decomposition |
| Decomposition | (decision) | N/A | N/A | N/A | User confirms plan before execution |
| Create Tracker Subtasks | (skill) | N/A | N/A | None | Creates tracker sub-issues for each decomposition subtask. Skippable via config. |
| Fix (per subtask) | fixer | opus | **No** | Build retries (default: 3) | Each subtask scoped to 100-line diff |
| Review (per subtask) | reviewer | opus | **No** | Fixer iterations (default: 5) | Loops with fixer per subtask |
| Test (per subtask) | test-engineer | sonnet | Yes | Test attempts (default: 3) | Runs per subtask |
| Acceptance Gate | acceptance-gate | sonnet | Conditional | Fixer iterations (default: 5) | Decomposition: always runs per subtask (no threshold); single-pass: runs when AC ≥ 3, else skipped; REQUEST_CHANGES returns to fixer |
| Integration Test | (skill) | N/A | No | 3 attempts | Full test suite after all subtasks |
| Publish | publisher | haiku | **No** | None | Creates PR, updates issue tracker |

### Decomposition Details

The architect produces a task tree in YAML format:

- **Max subtasks:** Configurable (default: 7)
- **Dependencies:** Must form a DAG (directed acyclic graph); each subtask lists `depends_on`
- **Execution order:** Topological sort of the dependency graph
- **Fail strategy:** `fail-fast` (stop on first failure) or `continue` (attempt remaining subtasks)
- **Commit strategy:** `squash` (single commit) or `individual` (one commit per subtask)
- **Task tree is saved** to `.claude/decomposition/{ISSUE-ID}.yaml` for resume support
- **Per-subtask state:** After each subtask commit, `status`, `commit_hash`, and `restore_point` are updated in both the YAML file and `state.json` `decomposition.subtasks[N]`
- **Tracker sub-issues:** After decomposition plan approval, sub-issues are created in the tracker (configurable via `Create tracker subtasks`). Idempotent on resume via dual-store check.

## Scaffold Pipeline

The scaffold pipeline creates a new project from scratch. In spec-first mode (default), it generates a specification, builds the skeleton, and implements all features. It is invoked by `/agent-flow:scaffold`.

### Scaffold Pipeline (default)

```mermaid
flowchart TD
    START([Start]) --> DETECT{Detect<br/>Directory State}
    DETECT -->|Empty| INFRA_DECL[Infrastructure Declaration<br/><i>tracker · source control</i>]
    DETECT -->|Has project, no CLAUDE.md| SUGGEST_ADD["Suggest /scaffold add"]
    DETECT -->|Has CLAUDE.md| SUGGEST_FEATURE["Suggest /implement-feature"]
    DETECT -->|Uncommitted changes| WARN[Warn User]

    INFRA_DECL --> MCP_CHECK[MCP Verification]
    MCP_CHECK --> MODE{Mode<br/>Selection}

    MODE -->|Interactive| SPEC_INTERACTIVE[Spec Phase<br/>Interactive Q&A]
    MODE -->|YOLO checkpoint| SPEC_YOLO[Spec Phase<br/>Autonomous]
    MODE -->|Full YOLO| SPEC_FULL[Spec Phase<br/>Autonomous]

    SPEC_INTERACTIVE --> SPEC_LOOP{spec-writer ↔<br/>spec-reviewer}
    SPEC_YOLO --> SPEC_LOOP
    SPEC_FULL --> SPEC_LOOP

    SPEC_LOOP -->|APPROVE| CHECKPOINT_SPEC{Spec<br/>Checkpoint}
    SPEC_LOOP -->|MAX ITER| USER_DECIDE[User Decides]

    CHECKPOINT_SPEC -->|Skip in Full YOLO| SCAFFOLD
    CHECKPOINT_SPEC -->|Approve| SCAFFOLD
    CHECKPOINT_SPEC -->|Abort| STOP([Stopped])

    SCAFFOLD[Generate Skeleton<br/>scaffolder] --> VALIDATE{Validate<br/>Build + Test + Lint}
    VALIDATE -->|PASS| GIT_INIT[Git Init + Auto-Config]
    VALIDATE -->|FAIL| RETRY_S{Retries?}
    RETRY_S -->|YES| SCAFFOLD
    RETRY_S -->|NO| FAIL_REPORT([Report Failure])

    GIT_INIT --> PUSH[Push to Remote<br/><i>if SC ready</i>]
    GIT_INIT --> CREATE_ISSUES[Create Tracker Issues<br/><i>if tracker ready, not Full YOLO</i>]
    PUSH --> ARCHITECT[Architecture<br/>architect]
    CREATE_ISSUES --> ARCHITECT
    ARCHITECT --> CHECKPOINT_PLAN{Feature Plan<br/>Checkpoint}

    CHECKPOINT_PLAN -->|Skip in Full YOLO| IMPL
    CHECKPOINT_PLAN -->|Approve| IMPL
    CHECKPOINT_PLAN -->|Abort| STOP

    subgraph IMPL [Feature Implementation Loop]
        direction TB
        FIXER[Fix<br/>fixer] --> REVIEWER{Review<br/>reviewer}
        REVIEWER -->|APPROVE| TEST[Test<br/>test-engineer]
        REVIEWER -->|REQUEST_CHANGES| FIXER
        TEST --> COMMIT[Commit Subtask]
    end

    IMPL --> BATCH_TEST{Batch Tests<br/>Pass?}
    BATCH_TEST -->|YES| E2E[E2E Tests<br/>test-engineer --e2e]
    BATCH_TEST -->|NO| FIXER_REPAIR[Fixer Repairs]

    E2E --> REPORT([Final Report])

    style FAIL_REPORT fill:#EF4444,color:#fff
    style REPORT fill:#22C55E,color:#fff
    style STOP fill:#6B7280,color:#fff
    style SUGGEST_ADD fill:#F59E0B,color:#000
    style SUGGEST_FEATURE fill:#F59E0B,color:#000
    style WARN fill:#F59E0B,color:#000
    style INFRA_DECL fill:#f0f4ff,stroke:#4a6cf7
    style MCP_CHECK fill:#f0f4ff,stroke:#4a6cf7
```

### Stages

| Step | Stage | Agent | Model | Notes |
|------|-------|-------|-------|-------|
| 0-INFRA | Infrastructure Declaration | (skill) | N/A | Collects tracker/SC intent; always runs (even Full YOLO) |
| 0-MCP | MCP Verification | (skill) | N/A | Verifies MCP for declared "ready" services; auto-downgrades in Full YOLO |
| 0 | Mode Selection | (skill) | N/A | Interactive / YOLO with checkpoint / Full YOLO |
| 1 | Specification | spec-writer ↔ spec-reviewer | opus | Loop up to Spec iterations (default 5) |
| 2 | Spec Checkpoint | (skill) | N/A | Skip in Full YOLO; user approves or aborts |
| 3 | Skeleton Generation | scaffolder | sonnet | Reads tech stack from spec/README.md; generates E2E Test + Decomposition config |
| 4 | Git Init + Auto-Config | (skill) | N/A | Commits spec/ + skeleton; auto-fills CLAUDE.md from 0-INFRA; generates .mcp.json.example |
| 4d | Push to Remote | (skill) | N/A | If SC ready; WARN on failure |
| 4e | Create Tracker Issues | (skill) | N/A | If tracker ready, not Full YOLO; accumulator pattern for partial failure |
| 5 | Architecture | architect | opus | Decomposes epics into dependency-aware batches |
| 6 | Feature Plan Checkpoint | (skill) | N/A | Skip in Full YOLO; user approves batch plan |
| 7 | Feature Implementation | fixer ↔ reviewer + test-engineer | opus/sonnet | Per-subtask loop with block handler + rollback |
| 8 | E2E Tests | test-engineer --e2e | sonnet | Covers critical user flows from spec |
| 9 | Final Report | (skill) | N/A | Summary with infrastructure status, features, tests, next steps |

### Legacy Mode (--no-implement)

With `--no-implement`, the scaffold pipeline falls back to v3.x behavior: scaffold (internal tech-stack selection step) → scaffolder → validate → git init → report. No specification phase, no feature implementation.

| Stage | Agent | Model | Notes |
|-------|-------|-------|-------|
| Directory Detection | (skill) | N/A | Guards against overwriting existing projects |
| Stack Selection | (scaffold internal step) | N/A | Picks one option per category from skill-supplied flags (`--lang`, `--framework`, `--db`, `--ci`); no separate agent dispatch |
| Skeleton Generation | scaffolder | sonnet | Writes to temp directory; includes CLAUDE.md with Automation Config |
| Validation | (skill) | N/A | Build + test + lint + CLAUDE.md structure check; max 3 retries |
| Copy to Target | (skill) | N/A | Copies validated skeleton to target directory |
| Git Init | (skill) | N/A | `git init` + initial commit |

## Autopilot Pipeline

The Autopilot pipeline is a headless dispatcher for unattended cron / batch / CI invocation. It reads issue queries from Automation Config, classifies issues, and dispatches the existing `/agent-flow:fix-bugs` (bugs) and `/agent-flow:implement-feature` (features) skills sequentially. It is invoked by `/agent-flow:autopilot`.

```
Preflight ──► Dry-run check ──► Lock (.agent-flow/autopilot.lock/) ──► Read queries
    │                                                                          │
    ▼                                                                          ▼
[exit on config/MCP error]                                            Classify issues
                                                                   (bugs first; bug wins on overlap)
                                                                              │
                                                                              ▼
                                                                    Dispatch sequentially
                                                              fix-bugs (bug) | implement-feature (feature)
                                                                              │
                                                                              ▼
                                                                   Summary table ──► Release lock
```

### Key Properties

| Property | Detail |
|----------|--------|
| Dispatch order | Bugs first (in tracker order), then features; if an issue matches both queries, it is classified as bug |
| Lock mechanism | Directory-based: `mkdir .agent-flow/autopilot.lock/` (atomic on POSIX and NTFS); stale threshold 120 minutes |
| Observability | Child skills (`fix-bugs`, `implement-feature`) fire events per issue: `pipeline-started`, `step-completed`, `pipeline-completed`. Block events fire as `issue-blocked`. When configured, also fires `pipeline-paused` per paused transition. Autopilot itself fires no per-issue webhooks. |
| Dry-run | Full short-circuit — no lock, no state, no webhook, no dispatch; safe for concurrent cron |
| Concurrency | Sequential dispatch only; one issue at a time |
| Multi-host | Process-local lock only; multi-host deployments must use disjoint `Bug query` / `Feature query` filters per host |

### Exit Codes

| Exit | Meaning |
|------|---------|
| 0 | All issues dispatched (or dry-run, or empty queue) |
| 1 | Preflight failure (missing config, missing Bug query) |
| 2 | Lock held by another run |
| 3 | MCP ping failed — tracker unreachable |
| >0 (other) | Dispatch loop broke due to `On error: stop` config |

## Pipeline Profiles

Pipeline profiles allow you to customize which stages run for different use cases. Profiles are defined in the `Pipeline Profiles` section of Automation Config and apply to `/agent-flow:fix-bugs` and `/agent-flow:implement-feature`.

### Skippable Stages

| Stage | Skippable | Pipeline(s) |
|-------|-----------|-------------|
| triage | Yes | Bug-fix |
| analyst-impact | Yes | Bug-fix |
| spec-analyst | Yes | Feature |
| test-engineer | Yes | Bug-fix, Feature |
| test-engineer-e2e | Yes | Bug-fix, Feature |
| fixer | **No** | All |
| reviewer | **No** | All |
| publisher | **No** | All |

### Example Profiles

| Profile | Skip stages | Extra stages | Use case |
|---------|-------------|--------------|----------|
| fast | triage, analyst-impact, test-engineer | (none) | Quick fixes where analysis is already done |
| strict | (none) | test-engineer-e2e | Maximum quality gate with E2E tests |
| minimal | triage, analyst-impact, test-engineer, test-engineer-e2e | (none) | Hotfix with minimum overhead |

Usage: `/agent-flow:fix-bugs PROJ-42 --profile fast`

## Error Handling

### Block/Rollback Pattern

When any agent encounters an unrecoverable error, it triggers a **block**:

1. The **rollback-agent** (haiku) reverts git state to the pre-fix checkpoint
2. The issue state is set to **Blocked** in the issue tracker
3. A **Block comment** is posted to the issue with structured fields

Block comments follow this format:

```
[agent-flow] Pipeline Block
Agent: {agent name}
Step: {pipeline step where failure occurred}
Reason: {max 2 sentences}
Detail: {technical output — error message, diff, test output}
Recommendation: {what the human should do}
```

The `[agent-flow]` prefix enables machine-parseable detection by the inline auto-resume contract (`core/resume-detection.md`) used by all pipeline entry-point skills (`fix-bugs`, `implement-feature`, `scaffold`).

### Rollback Behavior by Agent

| Blocked By | Rollback? | Reason |
|------------|-----------|--------|
| analyst (--phase triage) | No | No git changes to revert |
| analyst (--phase impact) | No | No git changes to revert |
| fixer | Yes | Reverts code changes |
| reviewer | Yes | Reverts code changes from fixer |
| test-engineer | Yes | Reverts test and code changes |
| test-engineer (--e2e) | Yes | Reverts E2E test changes |
| Build failure | Yes | Reverts broken code changes |
| Hook failure | Yes | Reverts code changes |
| Custom agent | Yes | Reverts code changes |

### Error Handling Config

The Error Handling section in Automation Config controls block behavior:

- **On block:** `comment` (default) posts a comment, `close` posts a comment and closes the issue
- **Max blocked per run:** Limits how many issues can block before the batch stops (default: `unlimited`)

## Dry-Run Mode

The `--dry-run` flag runs analysis stages only with no side effects. No issue tracker state changes, no git operations, no worktrees.

For bug-fix pipelines, dry-run executes triage and code analysis, then produces a report:

```
## Dry-Run Report — PROJ-42

**Triage:** OK
**Severity:** HIGH
**Area:** auth/login
**Affected files:** src/auth/login.ts, src/auth/validators.ts
**Risk:** MEDIUM
**Est. complexity:** S

No changes made. To run the fix, use `/agent-flow:fix-bugs PROJ-42` (without --dry-run).
```

For batch processing with `/agent-flow:fix-bugs`, the report includes a summary table with complexity estimates and resource projections.

## Fix Verification

When the `Verify` command is configured in the Build & Test section of Automation Config, the pipeline runs a post-merge verification step:

1. After the PR is created, the pipeline waits for the PR to be merged (max 5 attempts, 30s interval)
2. Once merged, it checks out the base branch and pulls
3. Runs the Verify command
4. **On success:** Posts a verification comment to the issue
5. **On failure:** Posts a failure comment and re-opens the issue via state transition

This ensures that the fix works correctly in the context of the target branch after merge, catching integration issues that unit tests might miss.
