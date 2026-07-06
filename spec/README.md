# Specification — Automation Config → `.agent-flow/config.toml` Hard-Cut Migration

This tracked `spec/` folder is the committed single source of truth for the migration that relocates
agent-flow's Automation Config out of the consumer's `CLAUDE.md` inline Markdown tables into a
committed `.agent-flow/config.toml` (plus an optional gitignored `.agent-flow/config.local.toml`
per-developer overlay), parsed by a pure-bash TOML reader (`core/config-reader.md`).

It is committed (not left only in the gitignored `.forge/` pipeline workspace) so the test harness
and future contributors can read it without the pipeline artifacts present.

| File | Contents |
|---|---|
| [requirements.md](requirements.md) | EARS-format requirements (REQ-01 … REQ-30) |
| [design.md](design.md) | Architecture: pure-bash TOML parser, config.local overlay/allowlist/denylist, single limits-resolution point, 23-section migration map |
| [formal-criteria.md](formal-criteria.md) | Machine-checkable acceptance criteria (FC-01 … FC-28) |
| [tdd-refined.md](tdd-refined.md) | TDD refinement notes (incl. the `toml-overlay-syntax.md:149-150` → `:150-157` citation correction) |

Scenarios under `tests/scenarios/` reference these committed paths (`spec/design.md`,
`spec/requirements.md`, `spec/formal-criteria.md`, `spec/tdd-refined.md`).
