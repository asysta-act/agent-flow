# Roadmap

agent-flow is a Claude Code plugin that automates bug-fix, feature, and scaffold
workflows — from issue tracker to merged PR — using a pipeline of specialized AI agents.

---

## v2.1.0 — Planned

### Direct Mode (tracker-free)
Use a text prompt, file, or TODO comment as the input instead of an issue tracker.
Enables `--no-pr` mode for local-only commits and teams without a tracker setup.

### Per-skill prerequisites
Lazy validation of required CLI tools (gh, jq, docker) before a pipeline starts,
with a clear "missing X, install with Y" message instead of a mid-run failure.

---

## v2.2.0 — Planned

### Step File Overrides
Replace any individual pipeline step with a project-specific version by placing a file at
`customization/steps/{skill}/{NN}-{name}.md`. The plugin will use your version instead of
the default, enabling deep pipeline customization without forking the plugin.

---

## Backlog (designed, not yet scheduled)

| Feature | What it enables |
|---------|----------------|
| **Monorepo support** | Per-package configs, selective test running |
| **Automated changelog** | Rich changelogs generated from pipeline execution data |
| **Dependency vulnerability scanning** | npm audit / pip-audit / trivy as an optional pipeline stage |
| **Performance regression testing** | Benchmark before/after a fix, surface regressions automatically |

---

## Post-release housekeeping (v1.0.0)

Skill / agent / contract counts after the v1.0.0 public release: **17 skills (down from 18 pre-release)**, **17 agents (unchanged)**, **17 core (unchanged)**. The skill reduction reflects removal of internal-only tooling; agent and contract surfaces are stable.

---

## Vision (longer term)

| Item | Description |
|------|-------------|
| **Multi-IDE support** | Cursor, Windsurf, Kiro — via a converter layer |
| **Module ecosystem** | Third-party agent bundles and a public registry |
