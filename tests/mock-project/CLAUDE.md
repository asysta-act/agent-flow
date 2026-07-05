# Mock Project

Test project for smoke testing the agent-flow pipeline.

## Automation Config

Automation Config lives in [`.agent-flow/config.toml`](.agent-flow/config.toml) (resolved by the
plugin's pure-bash `core/config-reader.md`). Optional per-developer overrides go in the gitignored
`.agent-flow/config.local.toml`. This section is a pointer only — no inline tables.
