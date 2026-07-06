# Requirements — Automation Config → `.agent-flow/config.toml` Hard-Cut Migration

> Run `forge-2026-07-04-001` · Phase 4 (Specification) · task type: **migration** · MAJOR change.
> Format: **EARS** (Easy Approach to Requirements Syntax), organised by the five EARS clause
> types — Ubiquitous, Event-driven, State-driven, Unwanted-behaviour, Optional.
> Every requirement has a stable `REQ-NN` id referenced by `formal-criteria.md`.

## Scope & binding decisions

This migration relocates agent-flow's Automation Config from inline Markdown tables inside the
consuming project's `CLAUDE.md` into a committed `.agent-flow/config.toml` (TOML), with an
optional gitignored `.agent-flow/config.local.toml` overlay. It is a **hard cut**: the inline
path is *removed*, not deprecated. The seven binding decisions from the Phase-4 prompt
(`.forge/phase-0-meta/prompts/spec.md` §Task Instructions) are encoded verbatim below and MUST
NOT be re-derived or softened. Research context: `discuss/automation-config-location:
research-automation-config-location-2026-07-03.md` (its §4.5 deprecation-window proposal is
**superseded** by the hard cut here; its §5 open-question #1 is **resolved** by the single-
resolution rule REQ-15).

Terminology: **allowlist** = the set of sections whose keys `config.local.toml` may override
(`Browser Verification`, `Local Deployment`). **denylist** = the enumerated, team-consistency /
security-critical subset of non-allowlisted keys that MUST be ignored-and-warned if present in
`config.local.toml`.

---

## 1. Ubiquitous requirements
*(The system shall <response> — always true, no trigger.)*

- **REQ-01 — Config location & format.** The resolved Automation Config SHALL be read from
  `.agent-flow/config.toml`, a git-**committed**, team-shared TOML file, with exactly one
  `[section]` per Automation Config section (23 total: 5 required + 18 optional). *(Decision 1)*

- **REQ-02 — CLAUDE.md is a pointer only.** The `## Automation Config` heading in a consuming
  project's `CLAUDE.md` SHALL contain only a 1–2 line pointer to `.agent-flow/config.toml` and
  SHALL NOT contain any `| Key | Value |` configuration tables. *(Decision 1)*

- **REQ-03 — Pure-bash TOML parser.** `core/config-reader.md` SHALL specify parsing of
  `.agent-flow/config.toml` using a pure-bash TOML subset (bare `[section]` headers;
  string / integer / boolean scalars; `"""` multi-line strings; `#` comments) and SHALL NOT
  require or invoke `tomllib`, `tomli`, `taplo`, `python3`, or any other external tool for that
  parse. (Host Python is 3.10; `tomllib` needs 3.11+.) *(Decision 6)*

- **REQ-04 — 1:1 lossless section mapping.** Each of the 23 Automation Config sections SHALL map
  to exactly one TOML `[section]` such that the resolved config object exposes the same
  dot-notation keys and defaults that `core/config-reader.md` exposes today (see `design.md`
  §4 migration map). No section, key, or default is dropped by the relocation. List-valued and
  map-valued keys that the scalar-only TOML subset cannot express natively — e.g.
  `issue_tracker.state_transitions` (map); `pr_rules.labels`, `notifications.on_events`,
  `browser.on_events`, `local_deployment.ports` (lists); `skip_stages` / `extra_stages` inside
  `[[pipeline_profiles]]` (lists) — SHALL be encoded as single-line delimited scalar strings
  (see `design.md` §1.1) and split by the reader back into the same list/map structure, so
  losslessness holds. *(Decision 1)*

- **REQ-05 — Config holds no secrets by contract.** `config.toml` SHALL NOT be the storage
  location for credentials (tokens remain in `.mcp.json` / environment); this invariant is
  preserved from the current contract. *(Grounding: research §4.2)*

- **REQ-06 — Single resolved-config object.** All 17 skills SHALL obtain configuration solely
  from the resolved config object produced by `core/config-reader.md` reading
  `config.toml` (+ `config.local.toml` overlay), and SHALL NOT independently re-parse an
  alternate config source. *(Decision 2, enabling)*

- **REQ-29 — Pure-bash limits-resolution path (no `tomllib` dependency).** The entire limits
  single-resolution path of REQ-08 — including reading the top-precedence
  `customization/{agent}.toml [limits]` tier — SHALL be implemented in pure bash using the same
  pure-bash TOML parser as REQ-03, with **no** hard dependency on `python3`, `tomllib`, or
  `tomli`, so it resolves correctly on the Python 3.10 host. It SHALL NOT route the `[limits]`
  read through `skills/setup-agents/lib/toml-merge.sh` (whose `import tomllib` fails on 3.10 and
  would silently yield an empty overlay, reintroducing the §2.4 two-channel divergence). The
  injector's `### Limits` render SHALL consume this pure-bash single-resolved value. *(Decision
  4; devil's-advocate M1)*

---

## 2. Event-driven requirements
*(**When** <trigger>, the system shall <response>.)*

- **REQ-07 — config.local overlay merge.** **When** `.agent-flow/config.local.toml` exists,
  the config reader SHALL apply it as a **per-key deep merge** on top of `config.toml`
  (overlay key wins; absent keys inherited), applying **only** keys belonging to the allowlist
  sections `Browser Verification` (`[browser_verification]`) and `Local Deployment`
  (`[local_deployment]`). *(Decision 3)*

- **REQ-08 — Limits single-resolution point.** **When** any retry/loop limit is needed, the
  orchestrator SHALL resolve it **once** through the precedence chain
  `plugin default < config.toml < config.local.toml < customization/{agent}.toml [limits]`,
  and SHALL use that single resolved value for **both** loop enforcement **and** agent-prompt
  injection. This supersedes the two-channel behaviour at
  `docs/guides/toml-overlay-syntax.md:150-157` (Tier-3 `[limits]` merge) and
  `core/agent-override-injector.md:102-105` (the `### Limits` render) — the §2.4 bug. The
  resolution SHALL be pure-bash per REQ-29 so the top tier actually applies on the 3.10 host.
  *(Decision 4)*

- **REQ-09 — `/onboard --migrate`.** **When** `/onboard` is invoked with `--migrate` and a
  legacy inline `## Automation Config` table block exists in `CLAUDE.md`, the skill SHALL
  perform a one-time migration: extract the inline tables into `.agent-flow/config.toml`
  (lossless per REQ-04) and rewrite the `CLAUDE.md` `## Automation Config` section down to the
  1–2 line pointer (REQ-02). *(Decision 5)*

- **REQ-10 — `/scaffold` emits config.toml.** **When** `/scaffold` generates a new project, it
  SHALL write `.agent-flow/config.toml` directly and SHALL NOT emit an inline
  `## Automation Config` table block into the generated `CLAUDE.md`. *(Decision 5)*

- **REQ-11 — `/check-setup` validation.** **When** `/check-setup` runs, it SHALL verify that
  (a) `.agent-flow/config.toml` exists; (b) it is **not** gitignored, tested via
  `git check-ignore`; (c) its keys match the documented key list — unknown key ⇒ `[WARN]`,
  missing **required** section/key ⇒ `[FAIL]`; (d) if a legacy inline `## Automation Config`
  table block is still present in `CLAUDE.md`, it SHALL emit a hint to run `/onboard --migrate`;
  and (e) if `.agent-flow/config.local.toml` is present and **not** gitignored (accidental-commit
  guard), it SHALL emit a `[WARN]` (verified via `git check-ignore`). *(Decision 5)*

- **REQ-12 — Migration is local & side-effect-free.** **When** `/onboard --migrate` runs, it
  SHALL write only git-tracked working-tree files (`CLAUDE.md`, `.agent-flow/config.toml`) and
  SHALL make no off-machine side effect (no webhook, email, or API call).
  *(Non-normative note: because both artefacts are git-tracked, the operation is reversible via
  VCS. Grounding: Phase-0 security eval.)*

---

## 3. State-driven requirements
*(**While** <state>, the system shall <response>.)*

- **REQ-13 — Malformed optional input degrades, never crashes.** **While** parsing an optional
  section that is malformed (bad header, unparsable scalar, unterminated `"""`), the config
  reader SHALL emit a `[WARN]` naming the section and fall back to that section's default,
  and SHALL NOT crash or abort the pipeline — matching config-reader's existing "never block on
  an optional section" contract. *(Decision 6)*

- **REQ-14 — Denylist protection.** **While** a denylisted key is present in
  `config.local.toml`, the reader SHALL ignore it (never apply its value) and SHALL emit a
  `[WARN]`. The denylist is exactly: Source Control `Remote` (`source_control.remote`) and
  `Base branch` (`source_control.base_branch`); Notifications `Webhook URL`
  (`notifications.webhook_url`); Issue Tracker `Instance` (`issue_tracker.instance`) and
  `Project` (`issue_tracker.project`); and **all** of PR Rules (`[pr_rules]` — every key).
  *(Decision 3)*

- **REQ-15 — Precedence stability.** **While** both `config.local.toml` and a
  `customization/{agent}.toml [limits]` entry set the same limit, the customization overlay
  SHALL win (top of the REQ-08 chain), and the orchestrator SHALL enforce and inject that same
  single value. *(Decision 4; resolves research §5 open-question #1.)*

- **REQ-21 — Absent overlay is a no-op.** **While** no `.agent-flow/config.local.toml` file is
  present, the resolved config SHALL equal `config.toml` merged over plugin defaults, unchanged.
  *(Decision 3)*

---

## 4. Unwanted-behaviour requirements
*(**If** <unwanted trigger>, **then** the system shall <response>. — includes the hard-cut removal.)*

- **REQ-16 — HARD-CUT REMOVAL of the inline path.** **If** any plugin code path parses
  Automation Config from `CLAUDE.md` into the config object — a Markdown-table parser, an inline
  fallback, a dual-format / dual-read, or a deprecation shim — in `core/config-reader.md` or
  anywhere else, **then** that is a defect and SHALL be removed; the shipped plugin SHALL contain
  no such path. Phrased machine-checkably: no config-consuming file contains a path that
  **parses** `## Automation Config` tables from `CLAUDE.md` into a config object. (A read that
  merely *detects* a legacy inline block to emit a migrate hint — REQ-11(d) — is NOT such a path
  and is explicitly permitted.) *(Decision 2 — this is ONE MAJOR change.)*

- **REQ-17 — Non-allowlisted overlay keys are discarded.** **If** `config.local.toml` contains
  a key outside the allowlist (`Browser Verification`, `Local Deployment`) — whether or not it
  is on the enumerated denylist — **then** that key SHALL be ignored (its value never applied to
  the resolved config) and a `[WARN]` SHALL be emitted. *(Decision 3)*

- **REQ-18 — No `/migrate-config` command.** **If** a command definition named `/migrate-config`
  (or `/agent-flow:migrate-config`) exists anywhere in the plugin, **then** that is a defect and
  SHALL be removed; migration lives exclusively under `/onboard --migrate`. *(Decision 5;
  scenario `check-setup-no-migrate-config.sh`.)*

- **REQ-19 — No whole-directory `.agent-flow/` ignore.** **If** the `.gitignore` guidance or any
  project fixture would ignore the whole `.agent-flow/` directory (a trailing-slash pattern
  `.agent-flow/`), **then** that SHALL be treated as forbidden: `config.toml` MUST remain
  git-tracked, ignored only via **per-file** entries for genuinely local files (state.json,
  pipeline.log, locks, and `config.local.toml`). A whole-directory ignore is the trailing-slash
  footgun that would silently drop the tracked `config.toml`. *(Decision 7)*

- **REQ-20 — Required-section absence still FAILs.** **If** a **required** section
  (`Issue Tracker`, `Source Control`, `PR Rules`, `PR Description Template`, `Build & Test`) is
  absent or empty in `config.toml`, **then** the reader SHALL BLOCK/FAIL (as today), rather than
  silently defaulting — the WARN-and-default degradation (REQ-13) applies to *optional* sections
  only. *(Decision 6; preserves current failure contract.)*

---

## 5. Optional-feature requirements
*(**Where** <feature is included>, the system shall <response>.)*

- **REQ-22 — customization `[limits]` participation.** **Where** a
  `customization/{agent}.toml` file provides a `[limits]` table, its values SHALL be the highest-
  precedence layer of the REQ-08 single resolution and SHALL feed both channels identically.
  *(Decision 4)*

- **REQ-23 — Multi-line template round-trip.** **Where** the `PR Description Template` section
  contains multi-line text, it SHALL be stored as a TOML `"""` multi-line string under
  `[pr_description_template]` (key `template`) and SHALL round-trip losslessly into
  `pr_rules.description_template` in the resolved config. *(Decision 1 + 6)*

---

## 6. Housekeeping / release requirements

- **REQ-24 — Doc-count-drift sync set.** The following docs encode the "config lives in
  CLAUDE.md" assumption and SHALL be updated together in the same change:
  `CLAUDE.md`, `README.md`, `docs/reference/automation-config.md`,
  `docs/guides/installation.md`, `docs/architecture.md`. `installation.md`'s `.gitignore`
  guidance (currently per-file `.agent-flow/*` entries around lines 86-89) SHALL add
  `config.local.toml` as a per-file ignore while keeping `config.toml` tracked (REQ-19).
  *(Decision 7 + doc-count discipline)*

- **REQ-25 — Fixtures migrate to TOML.** `tests/mock-project/CLAUDE.md` (pointer + a
  `.agent-flow/config.toml`) and `tests/harness/fixtures/automation-config.md` SHALL be migrated
  from inline Markdown tables to the TOML form so the harness exercises the new contract.
  *(Grounding: Phase-0 §4)*

- **REQ-26 — Scenarios reworked, not deleted.** The existing scenarios that assert the old
  location SHALL be **retargeted** (not removed): `counts-invariants.sh` assertion #5,
  `config-reader-sections.sh`, `config-required-keys.sh`, `check-setup-*`, `scaffold-*`,
  `doc-count-sync.sh`. Five **new** scenario families SHALL be added (see `design.md` §5).
  *(Grounding: Phase-0 §4)*

- **REQ-27 — Version-neutral MAJOR release.** The change is **MAJOR** (breaking Automation Config
  contract). The source PR SHALL target `release/v2.0.0` and SHALL be **version-neutral**: it
  SHALL NOT edit `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, or
  `CHANGELOG.md` (the single bump is finalised on the integration branch). *(Constraint)*

- **REQ-28 — Spec committed to the repo.** The completed spec (these three files, or a `spec/`
  folder / docs file derived from them) SHALL ultimately be committed into the repository — not
  left only in the gitignored `.forge/` tree — as the completion phase enforces. *(Constraint)*

---

### Requirement → binding-decision coverage matrix

| Binding decision | Requirements |
|---|---|
| 1 — Location & format; pointer | REQ-01, REQ-02, REQ-04, REQ-23 |
| 2 — Hard cut (removal) | REQ-06, **REQ-16** |
| 3 — config.local allowlist + denylist | REQ-07, **REQ-14**, REQ-17, REQ-21 |
| 4 — Limits single resolution (§2.4) | **REQ-08**, REQ-15, REQ-22, **REQ-29** (pure-bash limits path) |
| 5 — Tooling (`--migrate`, scaffold, check-setup; no `/migrate-config`) | REQ-09, REQ-10, REQ-11, REQ-12, **REQ-18** |
| 6 — Pure-bash TOML parser; degrade | REQ-03, REQ-13, REQ-20 |
| 7 — gitignore discipline | **REQ-19**, REQ-24 |
| Release / housekeeping | REQ-05, REQ-24, REQ-25, REQ-26, REQ-27, REQ-28 |
