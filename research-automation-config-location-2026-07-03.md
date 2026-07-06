# Research: Where Should agent-flow's Automation Config Live?

**Date:** 2026-07-03
**Branch:** `discuss/automation-config-location`
**Status:** Research complete, decision drafted — no spec/implementation yet
**Method:** 7 parallel research subagents across two rounds (official docs, ecosystem survey, community best practices, internal drift analysis, general engineering conventions) + targeted format verification

---

## 1. Question

Today, every project consuming the agent-flow plugin must paste an `## Automation Config` section (5 required + 18 optional table-based sections) directly into its own `CLAUDE.md`. Two concerns prompted this research:

1. Is embedding structured plugin config inside the consumer's CLAUDE.md a best practice for Claude Code plugins, or should the config live in a dedicated file that CLAUDE.md merely points to?
2. CLAUDE.md content flows into skills and agents ambiently — but the *effective* plugin configuration (after TOML overrides, profiles, runtime flags) can differ from what CLAUDE.md literally says. Agents should not see potentially stale/conflicting config text.

## 2. Findings

### 2.1 Official Claude Code documentation

- CLAUDE.md is explicitly **"context, not enforced configuration"** ([memory docs](https://code.claude.com/docs/en/memory.md)). Guidance: keep it to facts Claude should hold every session; move procedures and scoped rules elsewhere.
- **Subagents auto-load CLAUDE.md** at dispatch (all custom agents; only built-in Explore/Plan skip it) and this cannot be disabled or filtered ([subagents docs](https://code.claude.com/docs/en/subagents.md)). Consequence: as long as config tables sit in CLAUDE.md, every dispatched agent sees **two sources of truth simultaneously** — the resolved values the orchestrator embedded in its prompt, and the raw CLAUDE.md tables. The only way to guarantee agents don't see stale/conflicting config is to remove the values from CLAUDE.md entirely. This settles concern (2): filtering is impossible; relocation is the fix.
- The only first-party plugin-config mechanism is **`userConfig` in `plugin.json`** → stored in `settings.json` under `pluginConfigs[<plugin-id>].options` ([plugins reference](https://code.claude.com/docs/en/plugins-reference.md)). It supports **flat scalar keys only** (string/number/boolean/file/dir, enable-time prompts) — unusable for 18 structured sections with multi-line templates. Docs are otherwise **silent** on where a plugin should tell consumers to put project-level config.
- `.claude/` is documented as the git-versioned home for project-level Claude tooling config (`settings.json` committed; `*.local.*` gitignored — auto-added by Claude Code).

### 2.2 Ecosystem survey (~11 real plugins)

| Plugin | Per-project config location |
|---|---|
| code-review (anthropics) | reads CLAUDE.md as *soft prose guidelines* only — no structured contract |
| hookify (anthropics) | namespaced files in `.claude/`: `.claude/hookify.<rule>.local.md` |
| compound-engineering (EveryInc) | `.compound-engineering/config.local.yaml` (gitignored) + committed `.example.yaml`; **migrated away from** a root-level `.local.md` |
| Task Master | `.taskmaster/config.json` written by `task-master init` |
| claude-flow | `.claude/`, `.claude-flow/`, env vars |
| claude-code-spec-workflow, CCPM | everything under `.claude/` |
| Sentry, Vercel (partner plugins) | install-time only (MCP + OAuth/env), no project file |
| superpowers | stateless, no config (control case) |
| ceos-agents (same author as agent-flow) | inline CLAUDE.md tables — **not independent evidence** (same design decision made twice) |

**No surveyed plugin embeds a structured config contract in the consumer's CLAUDE.md.** No surveyed plugin uses a root-level `<plugin>.toml` either. The two real, precedented patterns for runtime per-project config: **(a)** a plugin-named dot-directory at repo root (`.taskmaster/`, `.compound-engineering/`), **(b)** plugin-namespaced files inside `.claude/`.

### 2.3 Neighboring ecosystems (unanimous)

Codex CLI: structured settings in `.codex/config.toml`, strictly separate from AGENTS.md (instructions stay instructions). Cursor: `.cursor/` dotfolder. MCP: `.mcp.json`. No ecosystem puts tool config inside the AI-instructions file.

### 2.4 Internal drift analysis (this repo, file:line evidence)

- The base skill→agent path is sound: every skill re-reads CLAUDE.md fresh (`skills/fix-bugs/SKILL.md:124`, `core/config-reader.md:5`) and embeds resolved values literally into dispatch prompts (`skills/fix-bugs/steps/04-fixer-reviewer-loop.md:47-55`).
- **Real divergence exists in the Agent Overrides channel:** `customization/fixer.toml [limits] max_build_retries` merges against the plugin default, *not* against the CLAUDE.md-resolved value (`docs/guides/toml-overlay-syntax.md:149-150`; injector renders it verbatim, `core/agent-override-injector.md:102-105`). A project can have CLAUDE.md say `Build retries = 3` while the override says `2` — both land in the same effective prompt with no reconciliation, and the orchestrator enforces the CLAUDE.md number while the agent's prompt text says otherwise.
- Runtime state not reflected in CLAUDE.md at all: active `--profile`, hook script contents, `--step-mode` → `--yolo` mid-run switch.

### 2.5 General engineering convention

Mature tools keep machine-parsed config in dedicated schema-validatable files; docs point to them (ESLint, Terraform, Cargo, Configuration-as-Code literature). Specific to AI-instruction files: consistent advice is to keep CLAUDE.md lean (~150–200 lines) and point to external files; context compaction/summarization is lossy by design — acceptable for guidance, dangerous for exact values (retry limits, webhook URLs). No writeup anywhere recommends large config tables inside CLAUDE.md.

## 3. Format comparison

| Format | Verdict | Why |
|---|---|---|
| **TOML** | ✅ chosen | Comments; `[section]` headers map 1:1 to the 18 config sections; `"""` multi-line strings fit the PR Description Template; consistent with existing `customization/*.toml` (operators learn one format); Codex `.codex/config.toml` analogy; no YAML implicit-typing footguns |
| YAML | runner-up | Most ecosystem precedent (compound-engineering); comments + block scalars; loses on plugin-internal consistency and implicit-typing footguns |
| JSON | ❌ | No comments; multi-line templates via `\n` escapes are hostile to hand-editing |
| Markdown (tables in a separate .md) | ❌ | Solves only the *location* problem; keeps every format problem (no schema validation, fragile pipe tables, model must scrape rather than parse) |
| TOON | ❌ | Built for **uniform tabular LLM data payloads**, not config: ~0% tabular eligibility for nested config (per its own docs, compact JSON beats it there); no comments (spec-intentional); Working Draft maturity; rare in LLM training data → higher misparse risk where exactness matters most. [Spec](https://github.com/toon-format/spec), [toonformat.dev](https://toonformat.dev/) |

## 4. Decision (drafted)

1. **Move all Automation Config sections to `.agent-flow/config.toml`** (committed to git). Follows the plugin-dot-directory pattern (Task Master, compound-engineering); keeps one plugin = one directory.
2. **Layering for per-developer differences** — mirror Claude Code's own `settings.json` / `settings.local.json` convention:
   - `.agent-flow/config.toml` — committed, team-shared source of truth (tracker, PR rules, build commands *must* be identical across the team).
   - `.agent-flow/config.local.toml` — optional, gitignored, merged on top (wins). For legitimately personal keys: Local Deployment ports, Worktrees base path, personal Notifications webhook, Metrics output.
   - No committed template file: config holds no secrets (tokens stay in `.mcp.json`/env), and `/onboard` generates it — the template pattern (`.mcp.json.example`) is for secret-bearing files.
3. **CLAUDE.md keeps a 1–2 line pointer only** (`## Automation Config` → "See `.agent-flow/config.toml`"). This removes the dual-source conflict inside agent contexts — the only mechanism that can, since subagent auto-load of CLAUDE.md is not filterable.
4. **Gitignore discipline:** `.agent-flow/` must switch from whole-directory ignore guidance to per-file ignores (state.json, pipeline.log, locks, `config.local.toml`…). Known git footgun: a `.agent-flow/` (trailing-slash) ignore pattern makes `!.agent-flow/config.toml` re-inclusion impossible — git does not descend into ignored directories. Therefore `/check-setup` MUST validate that `config.toml` exists **and is not gitignored** (`git check-ignore`).
5. **Migration & compatibility:** deprecation window — skills read `.agent-flow/config.toml` first, fall back to parsing legacy inline CLAUDE.md tables with a `[WARN]` from `/check-setup`; `/onboard` gains a migrate mode (extract inline tables → config.toml, rewrite CLAUDE.md to pointer). Removing the fallback later is a separate future MAJOR.
6. **Versioning:** this change is **MAJOR** per the Versioning Policy (changes the required Automation Config contract).

## 5. Open questions for the spec

- **Reconciliation rule** for `.agent-flow/config.toml` vs `customization/*.toml [limits]`: the relocation alone does not fix the two-channel limits conflict (§2.4) — precedence must be defined explicitly. Proposal: overrides win, and the orchestrator enforces the *merged* value (so prompt text and enforcement agree).
- Exact merge semantics for `config.local.toml` (per-key deep merge vs per-section replace).
- Whether `check-setup` should schema-validate config.toml (a JSON Schema for TOML via taplo, or a documented key list check).
- Doc-count drift discipline: CLAUDE.md, README, docs/reference/automation-config.md, docs/guides/installation.md, onboard/check-setup skills, and the test harness scenarios all encode the "config lives in CLAUDE.md" assumption and must move together in one release.
