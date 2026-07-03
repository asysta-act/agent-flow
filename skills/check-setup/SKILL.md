---
name: check-setup
description: Validate Automation Config, MCP servers, and tokens
allowed-tools: mcp__*, Read, Glob, Grep, Bash
argument-hint: "[--skip-build]"
---

# Check Setup

Check the project configuration for the agent-flow pipeline. Report: what works, what is missing, what failed.

If $ARGUMENTS contains `--skip-build`, skip running build/test commands.

## Steps

### Block 1: Automation Config (structural check)

1. Read the current project's CLAUDE.md
2. Verify the existence of the `## Automation Config` section → [OK] or [FAIL]
3. Verify required sections and keys:

| Section | Required keys |
|---------|--------------|
| Issue Tracker | Type (or default youtrack), Instance, Project, Bug query, State transitions, On start set |
| Source Control | Remote, Base branch, Branch naming |
| PR Rules | Labels (Title format optional) |
| PR Description Template | (subsection present) |
| Build & Test | Build command, Test command |

### 3a. Per-tracker validation

> **Path note:** `trackers.md` lives in the plugin installation directory, not in the consuming
> project. Glob is used to handle CWD-context mismatch.

Locate `trackers.md`: Glob with pattern `.claude/plugins/**/docs/reference/trackers.md` first.
If no results, Glob with `**/docs/reference/trackers.md`. If still none, try `docs/reference/trackers.md` relative to CWD.
If multiple results, prefer the path containing `.claude/plugins/` or `agent-flow/`; if ambiguous → [WARN] "Multiple trackers.md found — using {path}."
If the file cannot be found → [WARN] "trackers.md not found — per-tracker validation skipped. Verify plugin installation." and skip the rest of Step 3a.
Find the row matching the configured Type in the Validation Rules table.

- Apply the query validation rule for that tracker to the Bug query value
- Apply the state transition format check to the State transitions value
- Apply the instance validation rule (if any) to the Instance value
- For unknown Type → [WARN] "Unknown tracker type '{Type}'. Validation skipped."

### 3b. Build & Test — Verify command (optional key)

`Verify command` is an optional key inside the required `Build & Test` section (per CLAUDE.md: it
runs after PR merge, and the issue is re-opened if it fails). It is not required for pipeline
readiness, so check it separately from the required-key table in Step 3:

- Key absent → [SKIP] "Build & Test — Verify command not configured (optional; runs after PR merge, re-opens the issue on failure)"
- Key present, non-empty, not a placeholder → [OK] "Build & Test — Verify command configured"
- Key present but empty or a placeholder (`<...>`) → [WARN] "Build & Test — Verify command is present but empty/placeholder; post-merge verification will not run"

4. For each key: verify that the value exists and is NOT a placeholder (`<...>`)
   - Present and filled → [OK]
   - Empty or placeholder → [FAIL]

5. Verify optional sections (if they exist, check the format). This is the full 18-section
   canonical list from CLAUDE.md's Automation Config reference — keep this list in sync with it:
   - Retry Limits, Module Docs, Hooks, Custom Agents, Notifications, Worktrees, E2E Test, Browser Verification, Error Handling, Feature Workflow, Decomposition, Pipeline Profiles, Metrics, Agent Overrides, Local Deployment, Sprint Planning, Autopilot, Pause Limits
   - Exists and correct format → [OK]
   - Does not exist → [SKIP] (optional)
   - Exists but incorrect format → [WARN]
   - Local Deployment (if present): Type must be `docker` or `native` → [WARN] if neither; Start command and Stop command must be non-empty → [WARN] if missing
   - Browser Verification (if present): On events must be `reproduce`, `verify`, or `reproduce, verify` → [WARN] if other; Stop command (optional) must be non-empty if present → [WARN] if empty
   - Sprint Planning (if present): Mode must be `suggest` or `apply` → [WARN] if neither; Max issues (if present) must be an integer 1–50 → [WARN] if out of range
   - Autopilot (if present): must have exactly 7 keys — Max issues per run, Lock timeout, Log file, Bug limit, Feature limit, On error, Dry run → [WARN] "Autopilot — expected exactly 7 keys, found {N}" if the count differs. Note: `Bug query` lives in Issue Tracker and `Feature query` lives in Feature Workflow — neither belongs in Autopilot, and their presence there does not count toward the 7. On error (if present) must be `skip` or `stop` → [WARN] if neither
   - Pause Limits (if present): Pause timeout must parse as `<N> hours` or `<N> days` within range 1 hour–365 days (3600s–31536000s, matching `parse_pause_timeout()` in `skills/autopilot/SKILL.md`) → [WARN] "Pause Limits — Pause timeout '{value}' is out of range or unparseable; autopilot falls back to the default (30 days)" if invalid. This is advisory only — autopilot does not abort on an invalid value, so this never escalates past [WARN]

### Block 2: MCP servers (presence and connectivity)

6. Read `.mcp.json` in the project root:
   - Found → [OK]
   - NOT found in CWD → search parent directories (up to git root or 3 levels):
     - Found at {path} → [WARN] ".mcp.json found at {path}, but Claude Code loads from CWD ({cwd}). Copy or symlink it here."
     - Not found anywhere → [FAIL] "No .mcp.json found. Run /agent-flow:setup-mcp to create one."

7. Compare MCP servers with Automation Config:
   - Issue tracker MCP: reuse the trackers.md path resolved in Step 3a (do not Glob again).
     Read the MCP Server Detection table. Find the row matching Type.
     Search .mcp.json server names/URLs for the listed keywords.
     If trackers.md was unavailable in Step 3a → [WARN] "trackers.md not found — MCP server keyword match skipped."
   - If match → [OK] "Issue tracker MCP: {server_name} ({type})"
   - If no match → [FAIL] "No MCP server configured for tracker type '{type}'. Run /agent-flow:setup-mcp to set it up."
   - Source control MCP: match server names/URLs with Remote from config
   - If match → [OK]
   - If no match → [FAIL] "No MCP server configured for source control '{remote}'"

8. Verify that tokens in `.mcp.json` are not empty or placeholders → [OK] or [FAIL]
   - If tracker Type is `gitea` AND `.mcp.json` contains a `command` field referencing `forgejo-mcp`: emit `[WARN] forgejo-mcp detected in .mcp.json for Type: gitea — re-run /agent-flow:setup-mcp to install gitea-mcp.`
     Rationale: `forgejo-mcp` is a third-party MCP server that also targets Gitea-compatible
     instances (Forgejo is a Gitea fork), so it's an easy substitution mistake for a `Type: gitea`
     project. `/agent-flow:setup-mcp` always installs the dedicated `gitea-mcp` binary for this
     tracker type (see `docs/reference/trackers.md`'s MCP Server Detection table) — a `forgejo-mcp`
     command here is a non-standard substitute, not the expected binary, even though it may work.

### Block 3: Connectivity

> **Pattern source:** `../../core/mcp-detection.md`'s Classification Reference table is the canonical
> single source for the TLS/auth/not-found/timeout trigger-pattern lists used across the plugin.
> The TLS and auth pattern lists in Steps 9 and 10 below mirror that table's `"tls"` and `"auth"`
> rows (adapted here to also gate the curl confirmation probe). If a pattern is added or changed,
> update `../../core/mcp-detection.md` first and mirror the change into both copies below.

9. Run the Bug query from Automation Config via MCP (limit 1 result):
   - Success → [OK] with the number of bugs found
   - On failure, classify the error in this order:
     1. **TLS error** (error contains any of: UNABLE_TO_VERIFY_LEAF_SIGNATURE, CERT_UNTRUSTED,
        SELF_SIGNED_CERT, self signed certificate, certificate verify failed, ERR_TLS_,
        DEPTH_ZERO_SELF_SIGNED_CERT, unable to get local issuer certificate):
        Run a curl probe to confirm network reachability:
        - Check `which curl` — if curl is not available, skip probe and emit:
          [FAIL] "Issue tracker — TLS error detected. Add NODE_OPTIONS: --use-system-ca to .mcp.json env block. (curl not available for confirmation probe)"
        - Run: `curl -s -o /dev/null -w "%{http_code}" --proto "=http,https" --max-time 5 "{Instance}"`
        - curl exit 0 and HTTP code != 000 →
          [FAIL] "Issue tracker — server reachable but MCP connection failed (likely TLS) — add NODE_OPTIONS: --use-system-ca to the env block in .mcp.json"
        - curl exit non-zero or HTTP code 000 →
          [FAIL] "Issue tracker — connection failed (TLS or network). If using a private CA, try NODE_OPTIONS: --use-system-ca. If server is remote, verify URL."
     2. **Auth error** (error contains: 401, 403, unauthorized, forbidden, invalid token, authentication) →
        [FAIL] "Issue tracker — authentication failed — check your token in .mcp.json"
     3. **Any other error** →
        [FAIL] "Issue tracker — server not reachable — verify the server is running and URL is correct. If using a private CA (self-signed or corporate PKI), also try NODE_OPTIONS: --use-system-ca."
10. Verify source control connectivity: fetch metadata for the configured Remote (owner/repo) via MCP
    - Use MCP to fetch repository metadata for the Remote value from Automation Config
    - Success → [OK] "Source control — {owner/repo} reachable"
    - On failure, classify the error in this order:
      1. **TLS error** (error contains any of: UNABLE_TO_VERIFY_LEAF_SIGNATURE, CERT_UNTRUSTED,
         SELF_SIGNED_CERT, self signed certificate, certificate verify failed, ERR_TLS_,
         DEPTH_ZERO_SELF_SIGNED_CERT, unable to get local issuer certificate):
         Derive {sc_base_url}: scan the SC MCP server entry in .mcp.json for a URL-like value
         in the `env` block (first value starting with `https://` or `http://`). If no URL found,
         check if the server command/package matches a well-known host (server-github → https://github.com,
         server-gitlab → https://gitlab.com). If neither yields a URL, skip the curl probe.
         If {sc_base_url} was derived, run a curl probe:
         - Check `which curl` — if curl is not available, skip probe and emit:
           [FAIL] "Source control — TLS error detected. Add NODE_OPTIONS: --use-system-ca to .mcp.json env block. (curl not available for confirmation probe)"
         - Run: `curl -s -o /dev/null -w "%{http_code}" --proto "=http,https" --max-time 5 "{sc_base_url}"`
         - curl exit 0 and HTTP code != 000 →
           [FAIL] "Source control — server reachable but MCP connection failed (likely TLS) — add NODE_OPTIONS: --use-system-ca to the env block in .mcp.json"
         - curl exit non-zero or HTTP code 000 →
           [FAIL] "Source control — connection failed (TLS or network). If using a private CA, try NODE_OPTIONS: --use-system-ca. If server is remote, verify URL."
         If {sc_base_url} could not be derived (skip probe):
           [FAIL] "Source control — TLS error detected. If using a private CA (self-signed or corporate PKI), add NODE_OPTIONS: --use-system-ca to the env block in .mcp.json."
      2. **Auth error** (401/403) →
         [FAIL] "Source control — authentication failed. Token needs repository:read scope (Gitea), repo scope (GitHub), or read_repository scope (GitLab)."
      3. **Not found** (404) →
         [FAIL] "Source control — repository {owner/repo} not found. Verify Remote in Automation Config."
      4. **Tool not found** (MCP server lacks repository metadata method) →
         [WARN] "Source control MCP: repository existence check not supported — skipping."
      5. **Any other error** →
         [FAIL] "Source control — MCP server not reachable. Verify server URL and token in .mcp.json. If using a private CA (self-signed or corporate PKI), also try NODE_OPTIONS: --use-system-ca."

### Block 4: Build & Test (optional)

11. If `--skip-build` is NOT in $ARGUMENTS:
    - Run Build command → [OK] or [FAIL]
    - Run Test command → [OK] or [FAIL]
12. If `--skip-build` IS in $ARGUMENTS → [SKIP]

### Block 4b: Docker dry-build (optional)

13. Docker dry-build check:

```bash
# Block 4b: Docker dry-build (optional)
if [ -n "$skip_build" ] && [ "$skip_build" = "true" ]; then
  echo "[SKIP] Docker - skipped (--skip-build flag)"
elif [ ! -f Dockerfile ]; then
  echo "[SKIP] Docker - no Dockerfile"
elif ! command -v docker >/dev/null 2>&1; then
  echo "[SKIP] Docker - docker binary not found"
else
  # NOTE: --skip-build flag handled at top of block (skips Docker check identically to other build steps)
  if docker build --no-cache -t check-setup-test . > /tmp/check-setup-docker.log 2>&1; then
    echo "[OK] Docker - build passed"
    docker rmi check-setup-test >/dev/null 2>&1 || true
  else
    err=$(tail -3 /tmp/check-setup-docker.log | tr '\n' ' ')
    echo "[FAIL] Docker - $err"
  fi
fi
```

Where `$skip_build` is set to `"true"` when `--skip-build` is present in `$ARGUMENTS` (same flag used by Block 4). The 5-branch decision tree:
- `--skip-build` flag → `[SKIP] Docker - skipped (--skip-build flag)`
- No Dockerfile present → `[SKIP] Docker - no Dockerfile`
- `docker` binary not on PATH → `[SKIP] Docker - docker binary not found` (handles CI environments without Docker)
- Docker build exits 0 → `[OK] Docker - build passed` (image cleaned up with `docker rmi`)
- Docker build exits non-zero → `[FAIL] Docker - {last 3 lines of build log}`

## Output format

> The template below is populated from all Blocks in this file, including Blocks 5–7 (Plugin
> Composability, Dispatch Enforcement Hook, Agent Overrides) and the Deprecated config detection
> pass, which are defined further below. `[ADVISORY]` lines (Block 6 only) and `[SKIP]` lines never
> count toward the `{N} FAIL, {M} WARN` totals in the Result line.

```
## Setup report — {Remote from Automation Config}

### Automation Config
[OK]   ## Automation Config found in CLAUDE.md
[OK]   Issue Tracker — all keys filled (Type: {type})
[OK]   Source Control — all keys filled
[FAIL] PR Description Template — section missing
[FAIL] Build & Test — Test command is empty

### MCP servers
[OK]   .mcp.json found
[OK]   Issue tracker MCP server configured ({instance})
[FAIL] Source control MCP server not found for remote {owner/repo}

### Connectivity
[OK]   Issue tracker — connection OK, project {PROJECT} found, X bugs
[FAIL] Issue tracker — server reachable but MCP connection failed (likely TLS) — add NODE_OPTIONS: --use-system-ca to the env block in .mcp.json
[FAIL] Source control — authentication failed. Token needs repository:read scope.

### Build & Test
[SKIP] Skipped (--skip-build)

### Docker
[SKIP] Docker - no Dockerfile

### Plugin Composability
[OK]   No plugin conflicts detected

### Dispatch Enforcement Hook
[ADVISORY] PostToolUse hook not configured — dispatch enforcement is opt-in. See docs/guides/dispatch-enforcement.md to install.
[ADVISORY] Agent NEVER-constraints (e.g. publisher's 'NEVER push to main') are prompt-level only and are NOT technically enforced by this plugin even when the hook is installed. Enable server-side branch protection as the actual enforcement boundary. See SECURITY.md — Known Limitations.

### Agent Overrides
[FAIL] Agent overrides - .toml overlays present (customization/browser-agent.toml customization/fixer.toml) but neither tomllib (Python 3.11+) nor the tomli backport is importable by python3. The injector will SILENTLY DROP these overlays. Fix: install Python 3.11+, or run 'python3 -m pip install tomli'.

### Deprecated config
[WARN] Deprecated config section detected: ### Extra labels
       Move any labels into ### PR Rules → Labels (which fully supports the use case). See CHANGELOG.md.

---
Result: {N} FAIL, {M} WARN — {verdict}
```

Verdict:
- No FAILs → "Configuration is complete. Pipeline is ready."
- At least one FAIL → "Pipeline CANNOT run. Fix the errors listed above."

### Block 5: Plugin Composability

14. Check installed plugins:
    - Look for plugin registry: `.claude/plugins.json`, `.claude-plugins`, or another file with plugin metadata (exact location depends on the Claude Code version — if none of these files exist → [SKIP] "Plugin registry not found — conflict detection skipped")
    - If found: read the list of installed plugins
    - For each plugin: check if it registers commands with the same base name as agent-flow commands (without namespace prefix)
    - If conflict → [WARN] "Plugin '{name}' registers command '{cmd}' which may conflict with agent-flow:{cmd}"
    - If no conflicts → [OK] "No plugin conflicts detected"

### Block 6: Dispatch Enforcement Hook (advisory)

This block only checks whether the opt-in `hooks/validate-dispatch.sh` audit hook is wired up —
that hook is itself advisory-only (PostToolUse fires after the fact, so it cannot block a direct
push, a force push, or any other destructive action; see `docs/guides/dispatch-enforcement.md`).
Wiring the hook does NOT technically enforce any agent's `NEVER` constraints (e.g. publisher's
"NEVER push to main/development directly"). Regardless of the a/b result below, this block always
surfaces that broader risk and the actual enforcement boundary in step c, per
`SECURITY.md` → "Known Limitations" → "Advisory-only enforcement — no technical backstop for
agent NEVER-constraints".

15. Check whether the dispatch enforcement hook is installed:
    a. Verify that `hooks/validate-dispatch.sh` exists in the plugin installation directory.
       - Glob with `.claude/plugins/**/hooks/validate-dispatch.sh`; if not found, try `hooks/validate-dispatch.sh` relative to CWD.
       - Found → [OK] "hooks/validate-dispatch.sh present at {path}"
       - Not found → [ADVISORY] "hooks/validate-dispatch.sh not found — dispatch audit not available"
    b. Check whether `~/.claude/settings.json` contains a PostToolUse hook entry referencing `validate-dispatch`.
       - Read `~/.claude/settings.json` (if accessible).
       - Found entry referencing `validate-dispatch` → [OK] "PostToolUse hook wired in ~/.claude/settings.json"
       - Not found or file unreadable → [ADVISORY] "PostToolUse hook not configured — dispatch enforcement is opt-in. See docs/guides/dispatch-enforcement.md to install."
    c. Always emit, regardless of a/b results → [ADVISORY] "Agent NEVER-constraints (e.g. publisher's
       'NEVER push to main') are prompt-level only and are NOT technically enforced by this plugin
       even when the hook above is installed — PostToolUse is advisory and fires after the action
       already happened. The actual enforcement boundary is server-side branch protection (required
       PR review, required status checks, no direct/force pushes) on any branch this plugin is
       pointed at. See SECURITY.md → 'Known Limitations' for the full explanation."
    d. All results in this block are advisory — they NEVER contribute to the FAIL count or change the final verdict.

### Block 7: Agent Overrides (TOML overlay parsing)

The override injector (`../../core/agent-override-injector.md`) parses `customization/{agent}.toml`
overlays via `python3` — `tomllib` (Python 3.11+ stdlib) or the `tomli` backport on older Pythons.
If that parser is unavailable, `parse_toml_overlay` returns non-zero, `resolve_overlay` fails, and
the injector's mandatory guarded assignment (`|| additional_instructions=""`) absorbs the error and
dispatches the agent with the **bare prompt**. This failure is **silent** — the pipeline never
blocks on overlay failure by design — so a project can carry `.toml` overlays that never actually
apply, and nothing surfaces it. This block catches that exact condition. The same silent drop also
happens on TOML syntax errors and unknown-key validation failures, so present-but-unparseable
overlays are validated end-to-end too.

16. Resolve the override directory from `### Agent Overrides → Path` in Automation Config
    (default `customization/`). Set `$override_path` to the resolved value and run the probe:

```bash
# Block 7: Agent override (TOML) parsing prerequisite
override_path="${agent_overrides_path:-customization}"
override_path="${override_path%/}"

if [ ! -d "$override_path" ]; then
  echo "[SKIP] Agent overrides - '$override_path/' not present"
else
  toml_files=$(find "$override_path" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | sort)
  if [ -z "$toml_files" ]; then
    echo "[SKIP] Agent overrides - no .toml overlays in '$override_path/'"
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "[FAIL] Agent overrides - .toml overlays present but python3 is not on PATH. The override injector parses TOML with python3 and will SILENTLY DROP every overlay (the pipeline never blocks on overlay failure). Fix: install Python 3.11+ (tomllib), or Python 3.10 plus 'python3 -m pip install tomli'."
  elif python3 -c "import tomllib" >/dev/null 2>&1 || python3 -c "import tomli" >/dev/null 2>&1; then
    pyver=$(python3 -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>/dev/null)
    echo "[OK] Agent overrides - TOML parser available (python3 ${pyver}); $(echo "$toml_files" | grep -c .) overlay file(s) found"
  else
    files=$(echo "$toml_files" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    echo "[FAIL] Agent overrides - .toml overlays present (${files}) but neither tomllib (Python 3.11+) nor the tomli backport is importable by python3. The injector will SILENTLY DROP these overlays — configured per-agent customizations are NOT applied. Fix: install Python 3.11+, or run 'python3 -m pip install tomli'."
  fi
fi
```

17. If the probe reported `[OK]` (parser available) AND at least one overlay exists, validate each
    overlay end-to-end so syntax errors and unknown-key violations — which also drop the overlay
    silently — are caught. Locate the parser library with Glob: pattern
    `.claude/plugins/**/skills/setup-agents/lib/toml-merge.sh` first, then
    `**/skills/setup-agents/lib/toml-merge.sh`, then `skills/setup-agents/lib/toml-merge.sh`
    relative to CWD. If located, source it. **Note:** `toml-merge.sh` runs `set -euo pipefail`,
    which propagates into the check-setup shell, so call its functions in guarded form — capture
    stdout into a variable and branch on the exit status — otherwise a parse/validation failure
    would abort the whole probe instead of being reported as a per-file `[FAIL]`. For each
    `customization/{agent}.toml` file (where `{agent}` is the filename without the `.toml`
    extension) run `if json=$(parse_toml_overlay "$f") && validate_overlay_keys "$json" "{agent}" "$f"; then`
    … `else` … `fi` and emit:
    - Parses and validates → [OK] "Agent overrides - {agent}.toml parses and validates"
    - Fails → [FAIL] "Agent overrides - {agent}.toml is present but fails to parse/validate; the
      injector will drop it silently. Detail: {stderr from the lib}"
    - If `toml-merge.sh` cannot be located → [WARN] "Agent overrides - parser library not found;
      per-file validation skipped (parser-availability check only)."

All `[FAIL]` results in this block **count toward the final FAIL verdict** — a present-but-unparseable
overlay means a configured customization is silently not being applied, which is a setup defect. A
clean project with no overlays yields `[SKIP]` and never affects the verdict.

## Deprecated config detection

After all primary checks complete, scan for deprecated config sections and emit advisories. These do NOT change the exit code — they're warnings only.

```bash
# Deprecated section detector
if grep -q '^### Extra labels' "$CLAUDE_MD" 2>/dev/null; then
  echo "[WARN] Deprecated config section detected: ### Extra labels"
  echo "       Move any labels into ### PR Rules → Labels"
  echo "       (which fully supports the use case). See CHANGELOG.md."
fi
```

This warning does NOT change the exit code (no `exit 1`, no `FAIL`, no `fail()`, no `return 1`). It is purely advisory.

## Rules

- Read-only — never write to CLAUDE.md or the issue tracker
- Connectivity: read-only MCP queries only
- Placeholder detection: pattern `<...>` in values = FAIL
- Safe for repeated execution
