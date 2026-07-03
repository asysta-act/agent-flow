---
name: setup-agents
description: One-shot project scanner that generates smart customization/*.toml defaults per agent
allowed-tools: Bash, Read, Write, Glob, Grep
argument-hint: "[--dry-run] [--yolo] [--force]"
disable-model-invocation: true
---

# /agent-flow:setup-agents

## Purpose

One-shot project scanner that detects project type (Python, TypeScript, monorepo, test
framework, Java, Rust, .NET) and generates smart `customization/{agent}.toml` defaults
for agents in the consuming project. This is a meta-agent style one-shot tool — NOT a
continuous meta-gen architecture.

Reference: `docs/guides/setup-agents-skill.md` for full heuristic enumeration and worked examples.
TOML schema: `core/overlay/toml-overlay.md` (3-tier merge contract).

## Synopsis

```
/agent-flow:setup-agents [--dry-run] [--yolo] [--force]
```

Flags:
- (no flags): scan project, preview-diff each planned file, prompt Apply / Skip / Abort before each write.
- `--yolo`: scan and write all generated files silently (no preview prompt). Idempotent regen of `# generated:` files and first-time writes both apply without confirmation.
- `--force`: overwrite existing user-edited files (those WITHOUT `# generated:` header) after backing up to `{agent}.toml.bak-{ISO-8601-timestamp}`; still subject to preview prompt unless `--yolo` is also supplied.
- `--dry-run`: scan and print planned writes to stdout; write nothing to disk.

## Step 1 — Detect project root and override directory

Detect project root as the directory containing `CLAUDE.md`, falling back to the git
repository root (`git rev-parse --show-toplevel`), falling back to CWD.

```bash
if [ -f "CLAUDE.md" ]; then
  PROJECT_ROOT="$(pwd)"
elif git rev-parse --show-toplevel > /dev/null 2>&1; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
  PROJECT_ROOT="$(pwd)"
fi
```

Then resolve the override directory from the project's `## Automation Config` →
`### Agent Overrides` → `Path` key (default: `customization/`), matching the same key
`core/agent-override-injector.md` reads at dispatch time. This is a narrow, read-only
lookup of a single config value — it does NOT constitute general CLAUDE.md consumption
and does not conflict with the "never read CLAUDE.md" intent for project-specific *logic*
(see Constraints):

```bash
AGENT_OVERRIDES_PATH="customization/"
if [ -f "${PROJECT_ROOT}/CLAUDE.md" ]; then
  CONFIGURED_PATH=$(awk '
    /^### Agent Overrides/ { in_section=1; next }
    /^### / { in_section=0 }
    in_section && /^\| *Path *\|/ {
      line=$0
      sub(/^\| *Path *\| */, "", line)
      sub(/ *\|.*$/, "", line)
      gsub(/^[ \t`]+|[ \t`]+$/, "", line)
      print line
      exit
    }
  ' "${PROJECT_ROOT}/CLAUDE.md")
  [ -n "$CONFIGURED_PATH" ] && AGENT_OVERRIDES_PATH="$CONFIGURED_PATH"
fi
# Normalize: strip any trailing slash before joining
CUSTOMIZATION_DIR="${PROJECT_ROOT}/${AGENT_OVERRIDES_PATH%/}"
```

If the `Agent Overrides` section or `Path` key is absent, `AGENT_OVERRIDES_PATH` stays at
its default `customization/`. Every other reference to `customization/` in this document
describes that default; when a project configures a non-default `Path`, substitute
`${CUSTOMIZATION_DIR}` throughout.

Ensure the override directory exists (create if absent):

```bash
mkdir -p "${CUSTOMIZATION_DIR}"
```

## Step 2 — Project scan (heuristic detection)

Scan the project root for manifest files and framework configs. Build a detection map:

### Python project detection

Trigger files: `pyproject.toml`, `requirements.txt`, `setup.py`

```bash
PYTHON_PROJECT=false
if [ -f "${PROJECT_ROOT}/pyproject.toml" ] || \
   [ -f "${PROJECT_ROOT}/requirements.txt" ] || \
   [ -f "${PROJECT_ROOT}/setup.py" ]; then
  PYTHON_PROJECT=true
fi
```

If `mypy.ini`, `setup.cfg` (with `[mypy]` section), or `pyproject.toml` (with `[tool.mypy]`)
is present, set `MYPY_DETECTED=true` for stricter type-hint constraints.

Generates: `analyst.toml` + `fixer.toml` with Python-specific `[[constraints]]`:
- PEP 8 style compliance
- Type hints (strict if mypy detected)
- pytest as test framework

### Monorepo detection

Trigger: `pnpm-workspace.yaml`, `turbo.json`, `lerna.json`, `nx.json`, `rush.json` present
at project root, OR ≥ 2 `package.json` files at depth > 1, OR ≥ 2 `pyproject.toml` files
at depth > 1.

```bash
MONOREPO=false
for f in pnpm-workspace.yaml turbo.json lerna.json nx.json rush.json; do
  [ -f "${PROJECT_ROOT}/${f}" ] && MONOREPO=true && break
done
# Also detect by sub-package count (either ecosystem triggers monorepo mode)
SUB_PKG_COUNT=$(find "${PROJECT_ROOT}" -mindepth 2 -maxdepth 4 -name 'package.json' | wc -l)
[ "$SUB_PKG_COUNT" -ge 2 ] && MONOREPO=true
SUB_PYPROJECT_COUNT=$(find "${PROJECT_ROOT}" -mindepth 2 -maxdepth 4 -name 'pyproject.toml' | wc -l)
[ "$SUB_PYPROJECT_COUNT" -ge 2 ] && MONOREPO=true
```

Generates: `analyst.toml` with `[[process_additions]]` for multi-package impact analysis:
- On `--phase impact`, walk all top-level packages and report cross-package dependencies.
- Monorepo guidance appended to the analyst's process steps.

### TypeScript project detection

Trigger: `tsconfig.json` at project root.

Generates: `reviewer.toml` with `[[constraints]]` requiring TypeScript strict-mode compatibility.

### Test framework detection

Trigger files: `jest.config.js`, `jest.config.ts`, `jest.config.mjs`, `jest.config.cjs`,
`vitest.config.js`, `vitest.config.ts`, `vitest.config.mjs`, `pytest.ini`, `pyproject.toml`
(with `[tool.pytest.ini_options]`), `playwright.config.js`, `playwright.config.ts`.

Generates: `test-engineer.toml` with `[limits].test_framework` set to the detected framework name.

### Java / Maven / Gradle detection

Trigger: `pom.xml` or `build.gradle` at project root.

Generates: `fixer.toml` with Java-specific constraints (Maven/Gradle build awareness).

### Rust detection

Trigger: `Cargo.toml` at project root.

Generates: `fixer.toml` with Rust-specific constraints (cargo conventions, clippy awareness).

### .NET detection

Trigger: `*.csproj` or `*.sln` at project root (glob match).

Generates: `fixer.toml` with .NET-specific constraints (dotnet CLI, NuGet conventions).

## Step 3 — Build PlannedOverlays

After detection, construct the set of `PlannedOverlays`: a mapping of
`{agent-name} → {TOML content string}` for all agents where a heuristic fired.

Each generated TOML file begins with:
```
# generated: {ISO-8601-timestamp} by /setup-agents v{plugin-version}
```

`{plugin-version}` is the `version` field read (read-only) from `.claude-plugin/plugin.json`
at scan time — the installed agent-flow plugin version, NOT an overlay-schema version. This
lets a future regen detect overlays generated by an older plugin version if heuristics change.

Example header line: `# generated: 2026-04-27T10:00:00Z by /setup-agents v1.2.0`

The `# generated:` header MUST be the first line of every file written by this skill and
MUST match the regex `^# generated: [0-9TZ:-]+ by /setup-agents v[0-9]+\.[0-9]+\.[0-9]+$`
(see `tests/scenarios/setup-agents-header.sh`). This sentinel enables idempotent regen
detection (Step 4).

## Step 4 — Idempotent regen + write logic

For each agent in `PlannedOverlays`:

1. Determine target path: `${CUSTOMIZATION_DIR}/{agent}.toml`
2. **Symlink escape guard**: resolve real path before writing. Primary resolver is
   `python3 os.path.realpath()` (macOS-portable); if `python3` is unavailable, fall back to
   GNU `readlink -f` (covers Linux/Git Bash hosts lacking `python3`). If NEITHER resolver is
   available, this is NOT treated as "no symlink" — the write is refused and the agent is
   skipped, so the Constraints NEVER-rule on symlink escapes cannot be silently bypassed by
   a minimal/degraded environment:
   ```bash
   resolve_real_path() {
     if command -v python3 > /dev/null 2>&1; then
       python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null
       return
     fi
     if command -v readlink > /dev/null 2>&1 && readlink -f "$1" > /dev/null 2>&1; then
       readlink -f "$1"
       return
     fi
     return 1
   }

   TARGET_PATH="${CUSTOMIZATION_DIR}/${agent}.toml"
   if RESOLVED=$(resolve_real_path "$TARGET_PATH") && [ -n "$RESOLVED" ]; then
     CUSTOM_REAL=$(resolve_real_path "${CUSTOMIZATION_DIR}")
     case "$RESOLVED" in
       "${CUSTOM_REAL}"/*) : ;; # Safe: within the resolved override directory
       *) echo "[ERROR] Symlink escape detected: ${TARGET_PATH} -> ${RESOLVED}; refusing write" >&2; continue ;;
     esac
   else
     # Fail closed: neither python3 nor GNU readlink -f is available, so the write target
     # cannot be verified safe. WARN-and-proceed would silently violate the symlink-escape
     # NEVER-rule in Constraints, so we refuse the write instead.
     echo "[ERROR] Symlink escape detection unavailable (no python3 or GNU readlink -f found); refusing write for ${agent}.toml" >&2
     continue
   fi
   ```
3. **Existing file handling**:
   - **File absent**: proceed to preview prompt (Step 3a), then write.
   - **File exists, first line matches `^# generated: `**: eligible for idempotent regen.
     Proceed to preview prompt (Step 3a), then write.
   - **File exists, first line does NOT match `^# generated: `**: user-edited file.
     - Without `--force`: emit `[WARN] User-edited overlay ${CUSTOMIZATION_DIR}/${agent}.toml preserved; pass --force to overwrite` and SKIP (no preview prompt — no write is planned).
     - With `--force`: backup existing file to `${CUSTOMIZATION_DIR}/${agent}.toml.bak-${TIMESTAMP}` (where TIMESTAMP is ISO-8601 format, e.g. `2026-04-27T103000Z`), then proceed to preview prompt (Step 3a), then write.

**Step 3a — Preview prompt** (UNLESS `--yolo`):

Display a diff-style preview of the planned content vs existing content (if any):

```
[setup-agents] Planned write: ${CUSTOMIZATION_DIR}/{agent}.toml
--- existing (or /dev/null if new)
+++ planned
{diff lines}

Apply / Skip this agent / Abort? [a/s/q]:
```

- `a` (Apply): write the file.
- `s` (Skip this agent): skip this file, continue to next.
- `q` (Abort): halt /setup-agents; no further writes.

With `--yolo`: skip prompt; apply all writes silently.

Scope isolation: NEVER modify files outside the resolved override directory
(`${CUSTOMIZATION_DIR}`, default `customization/`). NEVER modify `agents/`, `skills/`,
`docs/`, `plugin.json`, or any other project or plugin source files. NEVER write
`CLAUDE.md` (see Constraints for the one narrow, read-only exception). All writes are
restricted to `${CUSTOMIZATION_DIR}/`.

### Legacy `.md` overlay coexistence

When scanning the resolved override directory (`${CUSTOMIZATION_DIR}`, default
`customization/`), `/setup-agents` may encounter legacy `.md` overlay files
(unsupported — hard error):

- **Only legacy `.md` exists**: emit `[ERROR] Legacy .md overlay format is not supported for {agent}; manual conversion required — see docs/guides/toml-overlay-syntax.md for TOML overlay format examples.` and refuse to proceed.
- **Both legacy `.md` and `.toml` exist**: emit `[ERROR] Legacy .md overlay found alongside {agent}.toml; remove the .md file (TOML takes precedence). See docs/guides/toml-overlay-syntax.md.` and refuse to proceed.
- **Only `.toml` exists**: normal path, no warning.

## Step 5 — TOML output content

Each generated TOML file is minimal, idiomatic, and documented inline.

### Python project — `analyst.toml`

```toml
# generated: {ISO-8601} by /setup-agents v{plugin-version}
# Python project detected via: pyproject.toml / requirements.txt / setup.py

[[constraints]]
rule = "All code analysis reports must reference PEP 8 compliance status."

[[constraints]]
rule = "Report import structure issues (circular imports, unused imports)."
```

### Python project — `fixer.toml`

```toml
# generated: {ISO-8601} by /setup-agents v{plugin-version}
# Python project detected. Mypy detected: {true|false}

[[constraints]]
rule = "All new code must be PEP 8 compliant (max line length 88 for Black-compatible projects, 79 otherwise)."

[[constraints]]
rule = "Use type hints on all new public functions and methods."
# (emitted only when MYPY_DETECTED=true)
```

### Python project — `test-engineer.toml` (when pytest.ini detected)

```toml
# generated: {ISO-8601} by /setup-agents v{plugin-version}
# Test framework detected: pytest

[limits]
test_framework = "pytest"
```

### Monorepo — `analyst.toml`

```toml
# generated: {ISO-8601} by /setup-agents v{plugin-version}
# Monorepo detected via: {trigger-file or >=2 sub-packages}

[[process_additions]]
step = "after_default"
instruction = "On --phase impact, walk all top-level packages (apps/*, packages/*, libs/*) and report cross-package dependencies in the affected-files list. Include a 'Cross-package impact' subsection in the report."

[[process_additions]]
step = "after_default"
instruction = "For multi-package changes, list each affected package separately with its own impact summary."
```

### TypeScript project — `reviewer.toml`

```toml
# generated: {ISO-8601} by /setup-agents v{plugin-version}
# TypeScript project detected via: tsconfig.json

[[constraints]]
rule = "All reviewed code must be compatible with TypeScript strict mode (strictNullChecks, noImplicitAny)."

[[constraints]]
rule = "Flag any use of 'any' type without explicit justification comment."
```

### Test framework — `test-engineer.toml` (jest/vitest/playwright)

```toml
# generated: {ISO-8601} by /setup-agents v{plugin-version}
# Test framework detected: {framework-name}

[limits]
test_framework = "{framework-name}"
```

## Step 6 — Summary report

After all agents processed, print a summary table:

```
[setup-agents] Summary
Agent              | Action  | Reason
-------------------|---------|----------------------------------------
analyst            | Write   | Python project + monorepo heuristics
fixer              | Write   | Python project heuristic
reviewer           | Skip    | User-edited overlay preserved
test-engineer      | Write   | pytest detected
```

Print count: `{N} files written, {M} skipped.`

## Constraints

- NEVER modify files outside the resolved override directory (`${CUSTOMIZATION_DIR}`,
  default `customization/`). All writes restricted to that directory.
- NEVER modify `agents/`, `skills/`, `docs/`, or any plugin source files.
- NEVER write to CLAUDE.md of the consuming project. The ONLY permitted read of CLAUDE.md
  is the single `## Automation Config` → `### Agent Overrides` → `Path` key (Step 1), used
  exclusively to resolve the override directory and project root; no other Automation Config
  section is read or acted upon, and no project-specific logic is derived from it.
- NEVER follow symbolic links for write operations when the link target lies outside
  `${CUSTOMIZATION_DIR}`. If the realpath resolution mechanism itself is unavailable (see
  Step 4 point 2), fail closed — skip the write with `[ERROR]` — rather than proceeding
  with an unverified write.
- Every generated file MUST begin with `# generated: {ISO-8601} by /setup-agents v{plugin-version}` on line 1.
- The `--force` flag MUST create a `.bak-{ISO-8601-timestamp}` backup before overwriting.
- Preview prompt MUST be shown before every write UNLESS `--yolo` is supplied.
- All 17 agents may have customization templates (analyst, fixer, reviewer, test-engineer,
  acceptance-gate, publisher, rollback-agent, spec-analyst, architect,
  scaffolder, priority-engine, spec-writer, spec-reviewer, browser-agent,
  deployment-verifier, backlog-creator, sprint-planner). Note: rollback-agent is invoked by
  fix-bugs when a block occurs — it reverts git state and posts a block comment
  to the issue tracker.
- Use POSIX-portable bash (`#!/usr/bin/env bash`, no GNU-only extensions); compatible with
  bash 3.2 and Git Bash (Windows).
- Use `python3 os.path.realpath()` as the primary symlink resolution mechanism (macOS
  portability; GNU `readlink -f` is unavailable on macOS bash 3.2 without GNU coreutils).
  When `python3` is absent, fall back to `readlink -f` (covers Linux/Git Bash hosts without
  `python3`); if neither resolves, fail closed per the symlink-escape constraint above —
  never skip the check silently.
- Before writing, self-validate generated TOML content with
  `skills/setup-agents/lib/toml-merge.sh::parse_toml_overlay()` +
  `validate_overlay_keys()` (the library exposes parse/validate/merge/provenance helpers
  only — it has no dedicated "write" function, so this skill performs the file write itself
  via its normal `Write` tool after validation passes).

## Error Reporting

`/setup-agents` is a local, one-shot scanner with no issue-tracker or MCP binding (see
`allowed-tools` in the frontmatter — `Bash, Read, Write, Glob, Grep` only). It never posts
anywhere; unlike `fix-bugs`/`implement-feature`/`scaffold`, there is no resumable pipeline
state and no `[agent-flow] 🔴 Pipeline Block` tracker comment. On failure it prints a plain
stderr message to the terminal for the human running the command:

```
[setup-agents] [ERROR] {step where failure occurred}: {reason, max 2 sentences}
Detail: {error output}
Recommendation: {what the human should do — e.g., check python3/readlink availability, verify symlink, pass --force}
```

Per-agent failures (symlink escape, legacy `.md` overlay conflict, TOML write error) do NOT
halt the whole run — that agent is skipped (reflected as `Skip` in the Step 6 summary table)
and the scan continues with the next agent. Only a hard failure with no viable path forward
(e.g., project root undetectable, override directory cannot be created) aborts the entire
skill with a non-zero exit and the `[ERROR]` message above.
