# Troubleshooting

Common issues and their solutions when working with agent-flow, organized by category. For each issue, you will find the likely cause, the solution, and references to relevant documentation.

## Installation Issues

### Plugin Not Found After Install

**Symptom:** After adding the marketplace and running `/plugin install agent-flow@agent-flow`, the skills do not appear in tab-completion.

**Cause:** Claude Code may cache the plugin list and not pick up the new installation immediately.

**Solution:**
1. Restart your Claude Code session (close and reopen the terminal)
2. Verify the plugin is listed by checking tab-completion for `/agent-flow:`
3. If still not found, re-run the install command

For platform-specific installation notes and cache paths, see [Installation Guide](installation.md).

### Plugin Version Mismatch

**Symptom:** Commands behave unexpectedly or reference features that do not exist.

**Cause:** The locally installed plugin version differs from the version you expect.

**Solution:**
1. Run `/agent-flow:version-check` to compare your installed version with the latest remote version
2. If an update is available, re-install the plugin: `/plugin install agent-flow@agent-flow`
3. After updating, run `/agent-flow:check-setup` to verify compatibility

### Permission Errors on Linux/macOS

**Symptom:** Plugin installation fails with permission errors or agents cannot be dispatched.

**Cause:** File permission issues with the `.claude/` directory or plugin storage path.

**Solution:**
1. Check ownership of the `.claude/` directory: `ls -la ~/.claude/`
2. Ensure your user owns the directory: `chown -R $(whoami) ~/.claude/`
3. Verify the plugin files are readable: `ls -la ~/.claude/plugins/`

## Configuration Issues

### "No Automation Config found"

**Symptom:** Running any pipeline skill produces an error about missing Automation Config.

**Cause:** The project's CLAUDE.md is missing or does not contain the `## Automation Config` heading.

**Solution:**
1. Run `/agent-flow:onboard` to generate a complete Automation Config block interactively
2. Alternatively, run `/agent-flow:onboard` — Step 1 offers a template picker with all available pre-built config templates
3. The Automation Config must be a `##`-level heading in your project's CLAUDE.md

See [Automation Config Reference](../reference/automation-config.md) for the complete specification.

### check-setup Reports FAIL

**Symptom:** `/agent-flow:check-setup` shows one or more FAIL blocks.

**Cause and solution by FAIL type:**

**Missing required keys:**
- Ensure all 5 required sections are present: Issue Tracker, Source Control, PR Rules, PR Description Template, Build & Test
- Each section must contain all required keys (see [Automation Config Reference](../reference/automation-config.md))

**Placeholder values:**
- Replace all `<TODO>`, `<...>`, and placeholder patterns with actual values
- Common placeholders to check: Instance URL, Project key, Remote

**Wrong table format:**
- All config sections must use `| Key | Value |` tables
- Bullet-point lists (`- Key: Value`) are not accepted
- Ensure there are no extra spaces or formatting issues in table cells

**MCP server not found:**
- You need an MCP server matching your tracker Type
- For GitHub: configure a GitHub MCP server
- For YouTrack/Jira/Linear/Gitea: configure the corresponding MCP server
- See [MCP Configuration Guide](mcp-configuration.md) for setup instructions

**Build/test commands fail:**
- Run the build and test commands manually to verify they pass outside the pipeline
- Use `--skip-build` flag to skip this validation if your build requires specific environment setup
- Check that the commands in Build & Test section use the correct syntax for your project

### Agent Overrides (customization/*.toml) Not Applied

**Symptom:** You created `customization/{agent}.toml` overrides, but the agents behave as if the
overrides do not exist — added constraints, process steps, or `[limits]` are ignored. The pipeline
runs to completion with no error about the overlay.

**Cause:** The override injector parses TOML with `python3` using `tomllib` (Python 3.11+ stdlib) or
the `tomli` backport. If `python3` is missing from PATH, or neither `tomllib` nor `tomli` is
importable, parsing fails — and because the injector **never blocks the pipeline on overlay failure**,
every overlay is **silently dropped** (only an `[ERROR]` to stderr). A second, unrelated cause is the
orchestrator skipping the per-dispatch injection step entirely; the dispatch `state.json` records this
as `stages.<stage>.overlay_source` — a value of `none` next to an existing `customization/{agent}.toml`
means the overlay was not injected.

**Solution:**
1. Verify a TOML parser is importable:
   ```bash
   if python3 -c "import tomllib" 2>/dev/null; then echo "tomllib OK (3.11+)";
   elif python3 -c "import tomli" 2>/dev/null; then echo "tomli OK";
   else echo "NO PARSER"; fi
   ```
2. If `NO PARSER`: install Python 3.11+, or on Python 3.10 run `python3 -m pip install tomli`.
3. Run `/agent-flow:check-setup` — it reports `[FAIL]` when a `.toml` overlay exists but no parser is
   importable, and `[OK]` (with the detected `python3` version) when the parser is available.
4. Confirm provenance: each dispatch appends one line to `.agent-flow/pipeline.log`, e.g.
   `agent=browser-agent overlay_source=toml overlay_path=customization/browser-agent.toml`. A line with
   `overlay_source=none` for an agent that has a `.toml` file means the overlay was not applied.
5. See [TOML Overlay Syntax Guide](toml-overlay-syntax.md) for the requirement note and
   [Installation Guide](installation.md#prerequisites) for the Python prerequisite.

### Config Migration from Older Versions

**Symptom:** check-setup reports issues with config format, or skills reference sections that do not exist in your config.

**Cause:** Your Automation Config uses an older format (v1.x or v2.x).

**Solution:**
1. Update your `## Automation Config` to match the current format documented in `docs/reference/automation-config.md`.
2. Run `/agent-flow:check-setup` to verify the migrated config

## Pipeline Issues

### Agent Blocks the Issue

**Symptom:** The pipeline stops and a block comment appears on the issue in the tracker.

**Cause:** An agent encountered an unrecoverable error. The block comment contains structured information about what happened.

**Solution:**
1. Read the block comment fields:
   - **Agent:** Which agent blocked (e.g., fixer, reviewer, test-engineer)
   - **Step:** Which pipeline step failed
   - **Reason:** Brief description of the failure
   - **Detail:** Technical output (error message, diff, test output)
   - **Recommendation:** Suggested action for the human
2. Fix the underlying issue manually based on the Recommendation
3. Re-invoke the original entry-point skill (`/agent-flow:fix-bugs <ISSUE-ID>`, `/agent-flow:implement-feature <ISSUE-ID>`, or `/agent-flow:scaffold <ISSUE-ID>`) — inline auto-resume detection (`core/resume-detection.md`) picks up the pipeline from the failure point

The rollback-agent automatically reverts git state when a block occurs from fixer, reviewer, or test-engineer. Blocks from analyst do not trigger rollback (no git changes to revert).

### Pipeline Paused — Awaiting Clarification

**Symptom:** The pipeline exits with `[INFO] Pipeline paused — awaiting clarification` and a `[agent-flow]` comment appears on the issue containing a question. There is no red block emoji — the issue is NOT in Blocked state; it is in the `paused` state. `state.json` shows `status: "paused"` and a `clarification` object with a `question` field.

**Cause:** The fixer or analyst encountered genuine ambiguity that cannot be resolved from the codebase or issue description alone (for example: an underspecified requirement, a missing environment variable, or contradictory acceptance criteria). The agent emitted a `NEEDS_CLARIFICATION` signal.

**Solution:**
1. Read the clarification question in the issue comment
2. Answer it by re-invoking the original entry-point skill with `--clarification`:
   ```
   /agent-flow:fix-bugs ISSUE-ID --clarification "your answer"
   ```
   (Use `/agent-flow:implement-feature` or `/agent-flow:scaffold` for those pipelines.) Inline auto-resume detection (`core/resume-detection.md`) picks up the paused state.
3. The pipeline resumes from where it paused — no re-analysis is performed from the beginning

**Auto-abort timeout:** If the Pause timeout elapses without a `--clarification` re-invocation (default: 30 days), autopilot transitions the issue to `aborted_by_system`. The issue is NOT closed — it remains in the tracker with an updated state comment.

**Autopilot behaviour:** Autopilot automatically skips paused issues each run. They appear in the run summary as `skipped: awaiting_clarification`.

See also: [`core/agent-states.md`](../../core/agent-states.md) for the full NEEDS_CLARIFICATION protocol, and [Autopilot Guide](autopilot.md#paused-issues) for paused-issue handling in headless mode.

### Circuit Breaker Open

**Symptom:** The log contains `[WARN] Circuit breaker open: 3 consecutive webhook failures. Suppressing remaining webhooks for this run.` Webhooks are not being delivered for the remainder of the pipeline run.

**Cause:** Three consecutive webhook delivery failures (timeout, DNS resolution failure, or 4xx/5xx HTTP response) triggered the in-memory circuit breaker. All remaining webhook calls for that pipeline run were suppressed to prevent latency accumulation.

**Impact:** Pipeline progression is never blocked — the circuit breaker is advisory only. All pipeline stages continue normally; only webhook notifications are suppressed.

**Solution:**
1. Check the `Webhook URL` value in the `### Notifications` section of your Automation Config
2. Verify the endpoint is reachable and returns 2xx for a test POST
3. Common causes: incorrect URL, expired auth token in the URL, endpoint server down
4. If the webhook endpoint is intentionally removed, delete the `Webhook URL` row from your config
5. The circuit breaker resets automatically at the start of the next pipeline run — no manual intervention required

See also: [Architecture — Webhook Reliability](../architecture.md#webhook-reliability-and-circuit-breaker) for circuit breaker design details.

### Fixer Exceeds 100-Line Diff Limit

**Symptom:** The fixer agent blocks because the fix would exceed the 100-line diff limit.

**Cause:** The required change is too large for a single-pass fix.

**Solution:**
1. Use the `--decompose` flag to force the pipeline to break the work into subtasks:
   ```
   /agent-flow:fix-bugs PROJ-42 --decompose
   ```
2. Alternatively, let the auto-decomposition heuristic handle it. The pipeline automatically decomposes when:
   - Risk is HIGH
   - Affected files >= 4
   - Estimated diff > 60 lines with >= 3 affected files
   - There are 2+ independent changes
3. If decomposition is not suitable, consider breaking the issue into smaller tickets manually

### Reviewer Loop Exhausts Iterations

**Symptom:** The pipeline blocks after the fixer and reviewer cannot agree within the maximum iteration count.

**Cause:** The fixer's changes repeatedly fail to satisfy the reviewer's criteria. This usually indicates a complex fix where the fixer keeps introducing new issues while addressing reviewer feedback.

**Solution:**
1. Read the block comment to understand what the reviewer objected to
2. Manually fix the specific issue the reviewer flagged
3. Re-invoke `/agent-flow:fix-bugs <ISSUE-ID>` to continue from the review stage (inline auto-resume detection picks up the paused state)
4. If this happens frequently, consider increasing the Fixer iterations limit in Retry Limits config

### Build or Tests Fail Repeatedly

**Symptom:** The pipeline blocks after exhausting build retries or test attempts.

**Cause:** Pre-existing build/test issues, environment mismatch, or the fix introduced a regression that the fixer cannot resolve within the retry limit.

**Solution:**
1. Run the build and test commands manually to verify they pass outside the pipeline:
   ```bash
   npm run build   # or your configured Build command
   npm test         # or your configured Test command
   ```
2. If they fail manually, fix the pre-existing issues first
3. If they pass manually but fail in the pipeline, check for environment differences (Node version, environment variables, database connectivity)
4. Check the Retry Limits configuration — increase Build retries or Test attempts if the defaults are too low for your project

### Pipeline Hangs or Times Out

**Symptom:** The pipeline appears to stop progressing with no output.

**Cause:** MCP server connectivity issues, token expiration, or a large codebase causing slow analysis.

**Solution:**
1. Check MCP server configuration and verify it is running
2. Verify tokens are valid and not expired (see [Token Configuration Guide](tokens.md))
3. Run `/agent-flow:check-setup` to test connectivity
4. If the issue tracker has many issues, consider narrowing the Bug query to reduce response size
5. For large codebases, the analyst-impact step may take longer — this is expected behavior

## Permission Issues

### Permission prompts after session resume

**Symptom:** After resuming a session with `claude -c`, Claude Code prompts for tool permissions again for every tool call.

**Cause:** Claude Code session permissions may not persist across `claude -c` resume. This is platform behavior, not a agent-flow issue.

**Solution:** Configure permanent permissions in `.claude/settings.json`:

1. Run `/agent-flow:setup-mcp` — it generates `.claude/settings.json` with appropriate permissions
2. Or manually create `.claude/settings.json` in your project root:

```json
{
  "permissions": {
    "allow": [
      "Read", "Write", "Edit", "Glob", "Grep", "Bash",
      "mcp__youtrack__*", "mcp__gitea__*"
    ]
  }
}
```

Replace `mcp__youtrack__*` and `mcp__gitea__*` with your tracker and source control MCP prefixes.

**Important:** Avoid `mcp__*` wildcard — it permits ALL MCP servers including those from other plugins. Use specific prefixes for better security.

**For worktree users:** If you use parallel processing with worktrees (`Batch size > 1`), permanent permissions are essential — each parallel task may prompt separately, multiplying permission requests.

## Platform-Specific Issues

### Windows: Path Length Limits

**Symptom:** Worktree creation fails or skills produce "path too long" errors.

**Cause:** Git worktree paths can exceed the Windows MAX_PATH limit (260 characters), especially with deep project structures and long issue IDs.

**Solution:**
1. Use shorter base paths for worktrees in your Automation Config:
   ```
   | Base path | `.wt/` |
   ```
2. Enable long path support in Windows:
   ```powershell
   git config --system core.longpaths true
   ```
3. Enable Win32 long paths via Group Policy or registry (requires admin)

See [Cross-Platform Guide](cross-platform.md) for additional Windows-specific guidance.

### Windows: Line Ending Issues

**Symptom:** Git shows unexpected changes in every file (line ending differences), or diffs contain CRLF noise.

**Cause:** Git `autocrlf` setting converts line endings, causing the fixer's changes to appear larger than they actually are.

**Solution:**
1. Add a `.gitattributes` file to your project:
   ```
   * text=auto eol=lf
   ```
2. Or configure git to not convert line endings:
   ```bash
   git config core.autocrlf false
   ```
3. After changing the setting, normalize existing files:
   ```bash
   git rm --cached -r .
   git reset --hard
   ```

### Linux: Shell Compatibility

**Symptom:** Build or test commands fail with syntax errors or "command not found" in the pipeline, but work in your terminal.

**Cause:** Some build commands assume bash-specific features (arrays, process substitution) that may not be available if the shell defaults to sh.

**Solution:**
1. Ensure bash is available: `which bash`
2. Prefix commands with `bash -c` in your Build & Test config if needed:
   ```
   | Build command | `bash -c 'npm run build'` |
   ```
3. Check that your PATH includes the necessary tool directories when running from Claude Code

## Getting Help

If you encounter an issue not covered here:

1. **Gather diagnostic information:**
   - Run `/agent-flow:version-check` and note the installed version
   - Run `/agent-flow:check-setup` and save the full output
   - Note the exact command you ran and any flags used
   - Copy the block comment from the issue tracker (if applicable)

2. **Check the pipeline stage:** Inspect `.agent-flow/{ISSUE-ID}/state.json` (`cat .agent-flow/*/state.json`) to see the current pipeline state and identify where the pipeline stopped.

3. **Review the reference docs:**
   - [Skills Reference](../reference/skills.md) for skill syntax and flags
   - [Pipeline Reference](../reference/pipelines.md) for pipeline stage details
   - [Automation Config Reference](../reference/automation-config.md) for configuration options
   - [Agent Reference](../reference/agents.md) for agent behavior and constraints

4. **Report the issue:** Open an issue in the agent-flow repository with the diagnostic information gathered above.
