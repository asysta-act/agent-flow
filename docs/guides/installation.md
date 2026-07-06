# Installing agent-flow

Step by step: from a clean slate to a working pipeline.

## Prerequisites

| What | How to verify |
|------|---------------|
| Claude Code CLI | `claude --version` |
| Git | `git --version` + `git config --global user.email` |
| Access to your Git server (SSH or HTTPS) | See section below |
| Python 3.11+ — **only if** you use `customization/*.toml` agent overrides | `python3 -c "import tomllib"` (3.11+) **or** `python3 -c "import tomli"` (3.10 + `pip install tomli`) |

> **Agent overrides need a TOML parser.** Per-agent customization files (`customization/{agent}.toml`)
> are parsed by `python3` using `tomllib` (Python 3.11+ stdlib) or the `tomli` backport. If neither is
> importable, the override injector **silently drops every overlay** — your customizations are ignored
> and the pipeline does **not** block or warn at dispatch time. Install Python 3.11+, or on Python 3.10
> run `python3 -m pip install tomli`. `/agent-flow:check-setup` verifies this and reports `[FAIL]` if a
> `.toml` overlay exists but no parser is available. You can skip this entirely if you do not use TOML overlays.

## 1. Plugin Repository Access

The plugin is hosted on your Git server (e.g., `<your-git-host>`). If it's a public repository, no
authentication is required just to add the marketplace and install the plugin (see step 2). You only
need direct Git access if you're cloning the plugin's own repository (e.g. to inspect the source,
contribute, or install from a private fork/mirror):

### Option A: SSH (recommended)

1. Generate an SSH key (if you don't have one):
   ```bash
   ssh-keygen -t ed25519 -C "your@email.com"
   ```
2. Add the public key to your Git host: **Settings → SSH/GPG Keys → Add Key**
3. Configure `~/.ssh/config`:
   ```
   Host <your-git-host>
     HostName <your-git-host>
     User git
     IdentityFile ~/.ssh/id_ed25519
   ```
4. Verify: `git ls-remote git@<your-git-host>:<owner>/<repo>.git`

### Option B: HTTPS

1. Generate a Personal Access Token for your Git host (see [tokens.md](tokens.md))
2. Verify: `git ls-remote https://<TOKEN>@<your-git-host>/<owner>/<repo>.git`

> **This is about installing the plugin itself.** Your *consuming project* — the repo the pipeline operates on — can use a different issue tracker / source control backend (GitHub, Gitea, YouTrack, Jira, Linear, Redmine; see `### Issue Tracker` in `## Automation Config`) than whatever host the plugin itself is fetched from. The public agent-flow release supports GitHub as its own canonical hosting platform (per `CLAUDE.md`); Gitea and the other backends above remain supported as *consuming-project* Automation Config targets regardless of where you installed the plugin from — see the Gitea setup notes in [mcp-configuration.md](mcp-configuration.md) and [tokens.md](tokens.md) if that's your project's backend.

## 2. Plugin Installation

```bash
claude plugin marketplace add <owner>/<repo>  # or a local path, e.g. C:/git_agent-flow
claude plugin install agent-flow@agent-flow
```

Verify: enter `/agent-flow:` and check that skills appear (tab-complete).

### Updating the Plugin

The marketplace cache does not update automatically. After a new version is released:

```bash
cd ~/.claude/plugins/marketplaces/agent-flow && git fetch origin && git pull origin main
rm -rf ~/.claude/plugins/cache/agent-flow/
```

Then restart your Claude Code session.

## 3. Project Setup

After installing the plugin, you need to configure your specific project:

1. Create `.mcp.json` in the project root — see [mcp-configuration.md](mcp-configuration.md)
2. Create `.agent-flow/config.toml` in the project root — this committed, tracked file holds all Automation Config; see the example in the plugin README. Optionally add a gitignored `.agent-flow/config.local.toml` per-developer overlay for local-only overrides.
3. Verify: `/agent-flow:check-setup`

## 4. Pipeline State and .gitignore

The plugin writes runtime state files to `.agent-flow/` in your project root. These files are local to each pipeline run and should generally not be committed.

**Recommended `.gitignore` entries:**

```
.agent-flow/autopilot.lock/
.agent-flow/state.json
.agent-flow/pipeline.log
.agent-flow/autopilot.log
.agent-flow/config.local.toml
```

**`pipeline-history.md` — operator choice:**

`.agent-flow/pipeline-history.md` is an append-only run log that accumulates cross-run block patterns and outcomes. Operators have two options:

- **Gitignore it (default):** Add `.agent-flow/pipeline-history.md` to `.gitignore` to keep it local. Suitable for single-developer or ephemeral CI environments.
- **Commit it (shared learning):** Omit it from `.gitignore` to commit and share cross-pipeline learning across team members. If you commit this file, note that `block_reason` values are redacted via `sanitize_block_reason()` (18-pattern credential scrubbing including bare-keyword variables), but you should still review the file for any sensitive operational details before committing.

## Platform Notes

### Windows (primary)

The procedure described above is for Windows. Paths use `~/` notation (Git Bash / WSL).

**gitea-mcp note (only if your project's Issue Tracker / Source Control backend is Gitea):** The `/agent-flow:setup-mcp` skill automatically downloads and installs `gitea-mcp` from [gitea.com/gitea/gitea-mcp](https://gitea.com/gitea/gitea-mcp/releases). If the download fails, it falls back to `go install gitea.com/gitea/gitea-mcp@latest`. Ensure Go is installed (`go version`) as a fallback option. Install Go from [go.dev/dl](https://go.dev/dl/) if needed. If your project uses GitHub instead, `setup-mcp` configures the GitHub MCP server — see [mcp-configuration.md](mcp-configuration.md).

### Linux

- SSH configuration is identical
- If your project's backend is Gitea: download the linux-amd64 archive `gitea-mcp-linux-amd64.tar.gz` from [gitea.com/gitea/gitea-mcp/releases](https://gitea.com/gitea/gitea-mcp/releases), extract with `tar xf`, save binary as `~/.claude/bin/gitea-mcp`, set `chmod +x`
- In `.mcp.json` use the Linux path to the binary
- Details in [cross-platform.md](cross-platform.md)

### macOS

Not explicitly supported, but likely functional (analogous to Linux).

## Known Limitations

### Slash command collision with Claude Code builtins

The short form `/init` collides with Claude Code's built-in slash command. Use the namespaced form instead:

- `/agent-flow:setup-mcp`

The namespaced form `/agent-flow:*` is unambiguous. See CHANGELOG.md for full migration notes.
