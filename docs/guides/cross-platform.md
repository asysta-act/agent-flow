# Cross-Platform Test Checklist

Manual checklist for verifying the pipeline on different platforms.

## Prerequisites

- [ ] Plugin installed (`/plugin install`)
- [ ] `.mcp.json` configured with valid tokens
- [ ] `.agent-flow/config.toml` present and tracked (not gitignored)
- [ ] Test issue exists in the issue tracker

Issue tracker / source control backend MCP checks below apply to whichever backend your project's `.agent-flow/config.toml` `[issue_tracker]` table specifies (GitHub is the canonical backend for the public release; Gitea, YouTrack, Jira, Linear, and Redmine remain supported for self-hosted projects — see [mcp-configuration.md](mcp-configuration.md)).

## Windows

- [ ] `/agent-flow:check-setup` — all checks OK
- [ ] `/agent-flow:analyze-bug <TEST-ISSUE>` — triage + analysis completes
- [ ] GitHub MCP server responds (`api.githubcopilot.com/mcp/`), or Gitea MCP server (`gitea-mcp.exe`) responds if configured
- [ ] YouTrack MCP server (npx) responds
- [ ] Worktree paths work (relative path in Automation Config)

## Linux

- [ ] If using Gitea: MCP binary has `chmod +x` set and the path in `.mcp.json` follows Linux convention
- [ ] `/agent-flow:check-setup` — all checks OK
- [ ] `/agent-flow:analyze-bug <TEST-ISSUE>` — triage + analysis completes
- [ ] Worktree paths: relative format (not `C:\...`)

## macOS

- [ ] Analogous to Linux — not officially supported
- [ ] If using Gitea: MCP binary is darwin-amd64 or darwin-arm64

## Notes

- The plugin itself is platform-agnostic (pure markdown)
- Platform-specific differences are only in `.mcp.json` paths and MCP server binaries
- Worktree paths in Automation Config must be **relative** (e.g. `.worktrees/`)
