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

4. For each key: verify that the value exists and is NOT a placeholder (`<...>`)
   - Present and filled → [OK]
   - Empty or placeholder → [FAIL]

5. Verify optional sections (if they exist, check the format):
   - Retry Limits, Hooks, Custom Agents, Notifications, Worktrees, E2E Test, Browser Verification, Error Handling, Decomposition, Pipeline Profiles, Metrics, Feature Workflow, Local Deployment, Agent Overrides
   - Exists and correct format → [OK]
   - Does not exist → [SKIP] (optional)
   - Exists but incorrect format → [WARN]
   - Local Deployment (if present): Type must be `docker` or `native` → [WARN] if neither; Start command and Stop command must be non-empty → [WARN] if missing
   - Browser Verification (if present): On events must be `reproduce`, `verify`, or `reproduce, verify` → [WARN] if other; Stop command (optional) must be non-empty if present → [WARN] if empty

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

### Block 3: Connectivity

9. Run the Bug query from Automation Config via MCP (limit 1 result):
   - Success → [OK] with the number of bugs found
   - On failure, classify the error in this order:
     1. **TLS error** (error contains any of: UNABLE_TO_VERIFY_LEAF_SIGNATURE, CERT_UNTRUSTED,
        SELF_SIGNED_CERT, self signed certificate, certificate verify failed, ERR_TLS_,
        DEPTH_ZERO_SELF_SIGNED_CERT, unable to get local issuer certificate):
        Run a curl probe to confirm network reachability:
        - Check `which curl` — if curl is not available, skip probe and emit:
          [FAIL] "Issue tracker — TLS error detected. Add NODE_OPTIONS: --use-system-ca to .mcp.json env block. (curl not available for confirmation probe)"
        - Run: `curl -s -o /dev/null -w "%{http_code}" --max-time 5 {Instance}`
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
         - Run: `curl -s -o /dev/null -w "%{http_code}" --max-time 5 {sc_base_url}`
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

Where `$skip_build` is set to `"true"` when `--skip-build` is present in `$ARGUMENTS` (same flag used by Block 4). The 4-branch decision tree:
- `--skip-build` flag → `[SKIP] Docker - skipped (--skip-build flag)`
- No Dockerfile present → `[SKIP] Docker - no Dockerfile`
- `docker` binary not on PATH → `[SKIP] Docker - docker binary not found` (handles CI environments without Docker)
- Docker build exits 0 → `[OK] Docker - build passed` (image cleaned up with `docker rmi`)
- Docker build exits non-zero → `[FAIL] Docker - {last 3 lines of build log}`

## Output format

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

### Agent Overrides
[FAIL] Agent overrides - .toml overlays present (customization/browser-agent.toml customization/fixer.toml) but neither tomllib (Python 3.11+) nor the tomli backport is importable by python3. The injector will SILENTLY DROP these overlays. Fix: install Python 3.11+, or run 'python3 -m pip install tomli'.

---
Result: {N} FAIL, {M} WARN — {verdict}
```

Verdict:
- No FAILs → "Configuration is complete. Pipeline is ready."
- At least one FAIL → "Pipeline CANNOT run. Fix the errors listed above."

### Block 5: Plugin Composability

13. Check installed plugins:
    - Look for plugin registry: `.claude/plugins.json`, `.claude-plugins`, or another file with plugin metadata (exact location depends on the Claude Code version — if none of these files exist → [SKIP] "Plugin registry not found — conflict detection skipped")
    - If found: read the list of installed plugins
    - For each plugin: check if it registers commands with the same base name as agent-flow commands (without namespace prefix)
    - If conflict → [WARN] "Plugin '{name}' registers command '{cmd}' which may conflict with agent-flow:{cmd}"
    - If no conflicts → [OK] "No plugin conflicts detected"

### Block 6: Dispatch Enforcement Hooks (advisory)

Dispatch enforcement is **two** hooks (see `docs/guides/dispatch-enforcement.md`):
the **PreToolUse `Task` gate** `hooks/validate-dispatch-pre.sh` (the only component
that can BLOCK a dispatch) and the **PostToolUse audit** `hooks/validate-dispatch.sh`
(advisory second layer). Both can be wired at any scope of the Claude Code settings
tree — `~/.claude/settings.json` (user), `.claude/settings.json` (project), or
`.claude/settings.local.json` (project-local) — and **hooks COMBINE across scopes**
(none overrides another; only `"disableAllHooks": true` disables them). Detecting the
wiring from `~/.claude/settings.json` ALONE is a false negative when an operator wired
it at the project or project-local scope, so this block scans the whole tree.

14. Check whether the dispatch enforcement hooks are installed:

    a. Verify the hook scripts exist in the plugin installation directory. For each of
       `hooks/validate-dispatch-pre.sh` (gate) and `hooks/validate-dispatch.sh` (audit):
       Glob with `.claude/plugins/**/hooks/{name}`; if not found, try `hooks/{name}`
       relative to CWD.
       - Found → [OK] "hooks/{name} present at {path}"
       - Not found → [ADVISORY] "hooks/{name} not found — that layer is not available"

    b. Detect whether the hooks are wired anywhere in the settings tree, using the
       shared helper `core/lib/detect-dispatch-hooks.sh`. Locate it with Glob: pattern
       `.claude/plugins/**/core/lib/detect-dispatch-hooks.sh` first, then
       `**/core/lib/detect-dispatch-hooks.sh`, then `core/lib/detect-dispatch-hooks.sh`
       relative to CWD. If located, set `$DDH_LIB` to the resolved path and run:

       ```bash
       # Block 6b: tree-aware dispatch-hook detection (advisory)
       if [ -z "${DDH_LIB:-}" ] || [ ! -f "${DDH_LIB:-}" ]; then
         echo "[ADVISORY] Dispatch hooks - detect-dispatch-hooks.sh not found; settings-tree wiring detection skipped (verify plugin installation)."
       else
         # shellcheck disable=SC1090
         . "$DDH_LIB"
         ddh_out="$(detect_dispatch_hooks "$PWD" "${HOME:-}")"
         # Pipe-free, CR-safe KEY=VALUE extractor (no `| head` -> no pipefail/SIGPIPE race).
         val() {
           local line
           while IFS= read -r line; do
             line="${line%$'\r'}"
             case "$line" in "$1="*) printf '%s' "${line#*=}"; return 0 ;; esac
           done <<EOF
$ddh_out
EOF
         }
         gate_wired=$(val GATE_WIRED);  gate_task=$(val GATE_MATCHER_TASK); gate_scopes=$(val GATE_SCOPES)
         audit_wired=$(val AUDIT_WIRED); audit_scopes=$(val AUDIT_SCOPES)
         disabled=$(val DISABLE_ALL_HOOKS); disabled_scopes=$(val DISABLE_ALL_HOOKS_SCOPES)

         # PreToolUse Task gate — the blocking component.
         if [ "$gate_wired" = "1" ] && [ "$gate_task" = "1" ]; then
           echo "[OK] Dispatch hooks - PreToolUse Task gate wired (${gate_scopes})"
         elif [ "$gate_wired" = "1" ]; then
           echo "[ADVISORY] Dispatch hooks - gate command present (${gate_scopes}) but matcher is not \"Task\" — it will NOT gate dispatches. Register it under PreToolUse with matcher \"Task\" (see docs/reference/hooks.md)."
         else
           echo "[ADVISORY] Dispatch hooks - PreToolUse Task gate not wired in any settings file (user/project/local) — dispatch enforcement is advisory only. See docs/guides/dispatch-enforcement.md to install."
         fi

         # PostToolUse audit — the advisory second layer.
         if [ "$audit_wired" = "1" ]; then
           echo "[OK] Dispatch hooks - PostToolUse audit wired (${audit_scopes})"
         else
           echo "[ADVISORY] Dispatch hooks - PostToolUse audit not wired in any settings file — see docs/guides/dispatch-enforcement.md."
         fi

         # disableAllHooks short-circuits everything above.
         if [ "$disabled" = "1" ]; then
           echo "[WARN] Dispatch hooks - \"disableAllHooks\": true set in ${disabled_scopes} — wired hooks will NOT fire until that is removed."
         fi
       fi
       # Managed/OS-level settings are not inspected by this check.
       echo "[ADVISORY] Dispatch hooks - managed/OS-level settings (Windows registry policy, macOS plist, Linux managed JSON) are not inspected; a hook wired ONLY there cannot be confirmed here."
       ```

    c. All results in this block are advisory — they NEVER contribute to the FAIL count
       or change the final verdict. (The keyed runtime preconditions that CAN fail live
       in Block 8.)

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

15. Resolve the override directory from `### Agent Overrides → Path` in Automation Config
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

16. If the probe reported `[OK]` (parser available) AND at least one overlay exists, validate each
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

### Block 8: Keyed Dispatch Witness Prerequisites (PR #15)

The gate-as-signer dispatch witness (`hooks/validate-dispatch-pre.sh` PreToolUse gate +
`hooks/validate-dispatch.sh` PostToolUse audit) is **pure Python stdlib** (`hmac`, `hashlib`,
`secrets`) — there is **no bash HMAC fallback**. The PreToolUse gate can only **BLOCK** a bad
dispatch (deny + `exit 2`) on **Claude Code >= 2.1.90** (issue #26923: `Task` exit-2 was a no-op
before that). This block asserts those preconditions so the marquee guarantee is not mere
documentation.

17. Run the prerequisite probes:

```bash
# Block 8: keyed dispatch witness prerequisites

# (1) Python 3 stdlib — the keyed HMAC gate + audit are pure Python (stdlib only; NO bash fallback).
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys,hmac,hashlib,secrets' >/dev/null 2>&1; then
  echo "[OK] Dispatch witness - Python 3 stdlib (hmac, hashlib, secrets) importable"
elif command -v python >/dev/null 2>&1 && python -c 'import sys,hmac,hashlib,secrets' >/dev/null 2>&1; then
  echo "[OK] Dispatch witness - Python 3 stdlib (hmac, hashlib, secrets) importable (python)"
else
  echo "[FAIL] Dispatch witness - no runnable Python 3 with stdlib hmac/hashlib/secrets on PATH. The PreToolUse gate and PostToolUse audit are pure Python (stdlib only); there is NO bash HMAC fallback. Fix: install Python 3 on PATH."
fi

# (2) TOML parser for agent-overlay model resolution (tomllib >= 3.11, OR the tomli backport on 3.10.x).
if python3 -c 'import tomllib' >/dev/null 2>&1 || python3 -c 'import tomli' >/dev/null 2>&1; then
  echo "[OK] Dispatch witness - TOML overlay parser available (tomllib or tomli) for shared model resolution"
else
  echo "[WARN] Dispatch witness - no TOML parser (tomllib on Python 3.11+, or the tomli backport on 3.10.x). Overlay model resolution is then SKIPPED identically on both gate and orchestrator (frontmatter/claim model is bound). Install Python 3.11+ or run 'python3 -m pip install tomli' to bind overlay model overrides."
fi

# (3) Claude Code >= 2.1.90 — the LOAD-BEARING precondition for the PreToolUse 'true block'.
cc_ver=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -z "$cc_ver" ]; then
  echo "[WARN] Dispatch witness - could not parse 'claude --version'. The PreToolUse gate needs Claude Code >= 2.1.90 to BLOCK a failing dispatch (older clients silently degrade to PostToolUse-advisory). Verify your version manually."
else
  cc_major=${cc_ver%%.*}; cc_rest=${cc_ver#*.}; cc_minor=${cc_rest%%.*}; cc_patch=${cc_rest##*.}
  if [ "$cc_major" -gt 2 ] \
     || { [ "$cc_major" -eq 2 ] && [ "$cc_minor" -gt 1 ]; } \
     || { [ "$cc_major" -eq 2 ] && [ "$cc_minor" -eq 1 ] && [ "$cc_patch" -ge 90 ]; }; then
    echo "[OK] Dispatch witness - Claude Code ${cc_ver} (>= 2.1.90; PreToolUse gate can block)"
  else
    echo "[FAIL] Dispatch witness - Claude Code ${cc_ver} < 2.1.90. The PreToolUse Task gate CANNOT block (deny + exit 2 is a no-op before 2.1.90, issue #26923); dispatch enforcement silently degrades to PostToolUse-advisory. Fix: upgrade Claude Code to >= 2.1.90."
  fi
fi
```

The `claude --version` parse is the **load-bearing primary**: a parseable version `< 2.1.90` is a
hard `[FAIL]`; an unparseable version is a `[WARN]` (cannot prove the precondition either way). No
bash HMAC fallback is ever added — Python stdlib is a hard requirement.

18. **First-keyed-run deny-canary handshake (once per machine).** This converts the version
    precondition from documentation into a checked assertion: the gate recognizes the reserved
    sentinel `subagent_type` `agent-flow:__deny_canary__` and **unconditionally DENIES** it, so a
    real block proves the running client honors PreToolUse `deny` + `exit 2`.

    - If `.agent-flow/.version-confirmed` already exists → `[SKIP] Dispatch witness - deny-canary
      handshake already confirmed on this machine`.
    - Otherwise dispatch ONE inert canary:
      `Task(subagent_type="agent-flow:__deny_canary__", description="agent-flow version handshake (inert)", prompt="inert — version handshake, do no work")`.
      The payload is deliberately inert, so even if it launches on a `< 2.1.90` client (where the
      gate's deny is a no-op) it does no work.
      - The dispatch was **BLOCKED** (the gate denied it) → `[OK] Dispatch witness - deny-canary
        blocked; Claude Code honors the PreToolUse true block` and record the once-per-machine
        marker (the ONLY file this skill writes — a runtime handshake marker, not config):

        ```bash
        mkdir -p .agent-flow 2>/dev/null
        date -u '+%Y-%m-%dT%H:%M:%SZ' > .agent-flow/.version-confirmed 2>/dev/null \
          && echo "[OK] Dispatch witness - recorded .agent-flow/.version-confirmed"
        ```

      - The canary **LAUNCHED** (was not blocked) → `[FAIL] Dispatch witness - deny-canary was NOT
        blocked: this Claude Code client is < 2.1.90 (the PreToolUse gate's deny is a no-op).
        Dispatch enforcement is advisory only until you upgrade to >= 2.1.90.` Do NOT record the
        marker.

All `[FAIL]` results in Block 8 **count toward the final FAIL verdict** — a missing Python stdlib
or a `< 2.1.90` client means the keyed gate cannot enforce. `[WARN]` results are advisory.

19. **Key-loss recovery (advisory note).** If a keyed run reports `WITNESS_UNVERIFIABLE` because
    its per-run `.agent-flow/{RUN-ID}/dispatch.key` was lost on a progressed run (≥1 completed
    stage or a non-empty ledger), this is **fail-closed by design** — the gate NEVER
    auto-regenerates the key on a progressed run (that would re-open the `f-c570b4` forge).
    Recovery is an **explicit operator choice**, not automatic: either archive/remove the affected
    run directory `.agent-flow/{RUN-ID}/` to rebaseline with a fresh keyed run (the bootstrap
    mints a new key only on a genuinely fresh run — zero completed stages + empty ledger), OR set
    `AGENT_FLOW_STRICT_DISPATCH=0` to continue advisory-only meanwhile. Full procedure: the
    **Key-loss recovery (operator runbook)** in `state/schema.md`. Emit `[ADVISORY]` and print the
    one-line summary; this note **never** contributes to the FAIL count.

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
