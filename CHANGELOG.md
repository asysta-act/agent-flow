# Changelog

All notable changes to agent-flow will be documented in this file.

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
