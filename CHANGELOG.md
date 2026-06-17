# Changelog

All notable changes to agent-flow will be documented in this file.

## [1.1.0] — 2026-06-17

### Added

- **PR Rules: `Title format` optional key** — operators can now control the PR title shape via Automation Config using the placeholders `{issue-id}`, `{mode}`, and `{summary}`, with English/ASCII-only normalization (no spaces, no brackets, no colons, diacritics transliterated). When the key is omitted, the publisher falls back to `{issue-id} {Mode}: {summary}`. Parsed by `core/config-reader.md` as `pr_rules.title_format`, prompted by `/onboard`, documented in `docs/reference/automation-config.md`, and surfaced in all `examples/configs/*` templates.
- **publisher: PR-ownership defenses (Steps 6a/6b)** — the publisher now reads the new PR's `number`/`url` only from the create call's own response (Step 6a; a missing/`null`/error payload is a FAILED create that Blocks — never `previous + 1` guessing), and before any post-create mutation it verifies `pr.head.ref == current_branch` AND `pr.base.ref == base_branch`, treating a missing field as a mismatch and Blocking fail-closed (Step 6b). Two matching `NEVER` constraints were added. Prevents the publisher from PATCHing/DELETEing an unrelated PR after a malformed create-response.

### Changed

- **publisher: PR title is now config-driven** — the hardcoded mode-dependent title (`[PROJ-123] Fix: …`) is replaced by the `Title format` rule plus the `{issue-id} {Mode}: {summary}` fallback. The bracketed `[ISSUE-ID]` form remains only in git commit messages (Step 4), which are explicitly scoped as independent of the PR title. Consumers parsing the old `^\[ISSUE-ID\]` PR-title shape should update.
- **Source Control / PR Rules: English + ASCII-only identifiers** — branch descriptions and PR titles MUST be English and ASCII-only; non-English source text is translated first and any remaining diacritics transliterated.

## [1.0.3] — 2026-05-26

### Fixed

- **guard-block: missing `mcp__github__create_pull_request` in drift-guard rows** — all three rows
  (`fix-bugs`, `implement-feature`, `scaffold`) listed only `mcp__gitea__create_pull_request` in the
  `Before any…` enumeration; GitHub is the primary SC remote yet its PR-creation tool was absent,
  creating an exhaustiveness illusion that let a drifted model proceed unchecked.
- **guard-block: pre-publish hook (step 10) omitted from fix-bugs drift-guard row** — the Reality
  column mentioned only the post-publish hook; step 10 (pre-publish hook + custom agent) is also
  bypassed by direct VCS calls and is the higher-stakes gate.
- **guard-block: user-consent gates sentence missing from fix-bugs row** — `implement-feature` and
  `scaffold` rows both named the consent gates that were bypassed; `fix-bugs` was silent, making it
  the weakest guard of the three. Added "the triage pause and pre-publish checkpoints you skipped by
  drifting were the user-consent gates."
- **guard-block: ambiguous `or` path in all three drift-guard rows** — "STOP and ask the user — or
  get back on the dispatch table" let a drifted LLM interpret the `or` branch as a silent
  course-correction that requires no user interaction. Replaced with a single unambiguous imperative:
  "STOP and ask the user for explicit authorization — do not proceed with any VCS action without it."
- **guard-block: inconsistent trigger phrasing in scaffold row** — "user narrows scope" unified to
  "user gives narrow scope" for consistency with the other two files.

## [1.0.2] — 2026-05-26

### Fixed

- **scaffold: MCP restart loses pipeline state** — when scaffold's 0-MCP step detected a missing
  MCP server and the user chose "Configure now", no checkpoint was written before the STOP message,
  and the shared resume-detection phase-scan had no scaffold stage names in its regex, causing
  `RESUME_POINT = FRESH` on re-invocation. Fix: write
  `{ "mcp_setup_pending": true, "mcp_pause_step": "0-MCP", "status": "paused" }` to state.json
  atomically before emitting STOP (including `"status": "paused"` so resume-detection, webhooks, and
  autopilot Pause timeout all recognise the paused state correctly); fire `pipeline-paused` webhook;
  add a scaffold-specific post-resume check in `SKILL.md` that detects `mcp_setup_pending: true` and
  overrides `RESUME_POINT = "0-mcp"`, skipping 0-INFRA (already completed) and re-entering only
  0-MCP. "Skip" path now also explicitly clears the marker. New fields documented in
  `state/schema.md`. New harness scenario: `tests/scenarios/scaffold-mcp-pending-resume.sh`.

## [1.0.1] — 2026-05-15

### Fixed

- **CI: marketplace.json missing `"license": "MIT"`** — restored field that was incidentally dropped during a source-type refactor (was failing `cross-file-invariants` test)
- **CI flake: `backlog-creator-agent` and `scaffolder-e2e-batch` on Linux** — root cause was `producer | grep -q PATTERN` interacting with `set -o pipefail`: `grep -q` exits on first match and closes its stdin, the upstream `echo`/`sed` then receives SIGPIPE → exit 141 → `pipefail` propagates → `|| fail` triggers despite a successful match

### Added

- `tests/lib/assert.sh` — SIGPIPE-safe assertion helpers (`contains`, `contains_i`, `matches_re`) using bash builtins (`case`, `[[ ... =~ ]]`) instead of pipelines. New scenarios should prefer these helpers over `echo "$VAR" | grep -q PATTERN`.

### Infrastructure

- Branch protection enabled on `main`: required PR, required `Harness suite` status check, required up-to-date branches, no force-push, no deletions, includes administrators

## [1.0.0] — 2026-05-14

### Initial Public Release

agent-flow is a Claude Code plugin that automates software development workflows —
bug fixes, feature implementation, and project scaffolding — from issue tracker
to merged PR, using a pipeline of specialized AI agents.

### What's included

**17 skills (slash commands):**
`/analyze-bug`, `/autopilot`, `/changelog`, `/check-setup`, `/create-backlog`,
`/discuss`, `/fix-bugs`, `/implement-feature`, `/metrics`, `/onboard`,
`/prioritize`, `/publish`, `/scaffold`, `/setup-agents`, `/setup-mcp`,
`/sprint-plan`, `/version-check`

**17 agents:**
`acceptance-gate`, `analyst`, `architect`, `backlog-creator`, `browser-agent`,
`deployment-verifier`, `fixer`, `priority-engine`, `publisher`, `reviewer`,
`rollback-agent`, `scaffolder`, `spec-analyst`, `spec-reviewer`, `spec-writer`,
`sprint-planner`, `test-engineer`

**3 pipeline types:**
- Bug-fix: issue tracker → triage → fix → review → test → PR
- Feature: spec → architecture → implementation → review → test → PR
- Scaffold: description → spec → code → test → git init

**Key capabilities:**
- Configurable via `## Automation Config` in your project's CLAUDE.md
- Supports YouTrack, GitHub Issues, Jira, Linear, Gitea, Redmine
- Agent Overrides for per-project customization
- Pipeline profiles, hooks, browser verification, decomposition
- Autopilot mode for batch processing
