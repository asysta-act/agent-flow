---
name: version-check
description: Compares installed plugin version with the latest available; when run from the plugin's own repo (Part B), may also auto-pull the repo and auto-update the installed plugin cache
allowed-tools: Read, Bash
---

# Version Check

Check whether the installed plugin version is up to date. Works from any directory. Part A (steps 1-4) is read-only. When run from inside the plugin's own repo, Parts B-C (steps 5-8) may mutate local state: `git pull` on the repo working tree, and `claude plugin update` on the installed plugin cache — see Rules.

## Plugin Identity

| Key | Value |
|-----|-------|
| Plugin | agent-flow |
| Marketplace | agent-flow |

All steps below use `{plugin}` and `{marketplace}` from this table.

## Steps

### Part A: Installed Plugin Status (always runs)

1. Read `~/.claude/plugins/installed_plugins.json`.
   - If the file does not exist → report: "Claude Code plugin registry not found at `~/.claude/plugins/installed_plugins.json`. No plugins installed — run `/plugin install` first." and STOP.
   - If the file is empty or is not valid JSON → report: "Plugin registry at `~/.claude/plugins/installed_plugins.json` is empty or corrupt — cannot parse." and STOP.
   - Search for the plugin: find any key in `plugins` that starts with `{plugin}@`. Prefer `{plugin}@{marketplace}` if it exists; otherwise use the first match.
   - If no matching key found → report: "{plugin} plugin is not installed. Run: `/plugin install {plugin}@{marketplace}`" and STOP.
   - Read `version` and `installPath` from the matched entry. Store as `installed_version`, `install_path`, and note the actual registry key as `registry_key`.
   - If `registry_key` does not equal `{plugin}@{marketplace}` → warn: "Plugin is registered under `{registry_key}` instead of `{plugin}@{marketplace}`. Consider reinstalling: `/plugin uninstall {plugin}` then `/plugin install {plugin}@{marketplace}`"

2. Verify `install_path` exists on disk.
   - If it does not exist → warn: "Install path `{install_path}` does not exist — plugin may need reinstalling. Run: `/plugin uninstall {plugin}` then `/plugin install {plugin}@{marketplace}`". Continue to step 3.

3. Determine the latest available version from remote.
   - **Determine the remote URL to query.** Try these sources in order (first success wins), and store the resolved value in the shell variable `remote_url`:
     1. If CWD is a git repo AND Part B will activate (`.claude-plugin/plugin.json` exists with matching `name`) → use `git remote get-url origin` from CWD. This is the most reliable source (uses the developer's configured SSH/HTTPS auth).
     2. Otherwise → read `{install_path}/.claude-plugin/plugin.json` and extract the `repository` field.
     3. If neither source yields a URL → report: "Remote version check skipped — no remote URL available." Skip to step 4 (show installed version only).
   - Before running the remote call, check whether the URL is a placeholder. This check applies to source-2 only (plugin.json `repository`); source-1 (user `git remote`) is trusted by definition.
     ```bash
     # RFC 2606 reserved TLD fast-fail:
     # source-2 only; covers both scheme:// URLs (https, ssh, git) and SCP-style SSH
     # (user@host:path, no scheme) — source-1 (user `git remote`) is not checked.
     # Extract hostname from URL, then match (test|example|invalid|localhost) as last DNS label
     # or as the bare host. Path-anchored matching avoids false positives where a reserved
     # label appears in a path component (e.g. github.com/foo.invalid/bar).
     # Match alternation kept inline for harness compatibility: (test|example|invalid|localhost)
     if echo "$remote_url" | grep -qE '^[A-Za-z][A-Za-z0-9+.-]*://'; then
       # scheme://[user@]host[:port]/path
       host=$(echo "$remote_url" | sed -E 's|^[A-Za-z][A-Za-z0-9+.-]*://([^/]+).*|\1|' | sed -E 's|^[^@]+@||' | sed -E 's|:[0-9]+$||')
     elif echo "$remote_url" | grep -qE '^[^/@[:space:]]+@[^:/[:space:]]+:'; then
       # SCP-style: user@host:path (no scheme), e.g. git@github.com:owner/repo.git
       host=$(echo "$remote_url" | sed -E 's|^[^@]+@([^:]+):.*|\1|')
     else
       host=""
     fi
     host="${host%.}"  # strip RFC 1034 trailing dot
     last_label=$(echo "$host" | awk -F. '{print $NF}')
     if [ -z "$host" ] \
        || [ "$last_label" = "test" ] || [ "$last_label" = "example" ] || [ "$last_label" = "invalid" ] || [ "$last_label" = "localhost" ] \
        || [ "$host" = "test" ] || [ "$host" = "example" ] || [ "$host" = "invalid" ] || [ "$host" = "localhost" ]; then
       echo "Remote version check skipped — plugin.json \`repository\` field is a placeholder or its host could not be confidently determined. Set it to a real URL."
       exit 0
     fi
     ```
     Fail closed: if the URL matches neither the scheme-style nor SCP-style pattern, `host` is left empty and the guard above treats it as a placeholder (skips the remote check) rather than falling through to an unvalidated `ls-remote` call. The boundary anchor `(/|:|$)` is implicit in the hostname-extract step — the host is delimited by `/` or end-of-string after the scheme, so the URL parser handles boundary detection.
   - Run, with `remote_url` always double-quoted since it may originate from an attacker-influenced `repository` field in plugin.json:
     ```bash
     timeout 10 git ls-remote --tags "$remote_url" 'refs/tags/v*' 2>/dev/null | grep -v '\^{}' | sort -t/ -k3 -V | tail -1
     ```
     If `timeout` is not available, omit it and run `git ls-remote` directly.
   - If the command fails (network error, SSL error, auth failure, timeout) → report: "Cannot reach remote repository. Showing installed version only." Skip to step 4.
   - If the output is empty (no tags, or no tags matching `v*`) → report: "No version tags found on remote repository. Showing installed version only." Skip to step 4.
   - Extract the version string from the tag reference (e.g., `refs/tags/v5.5.1` → `5.5.1`). Store as `remote_version`.

4. Compare and display.
   - If `remote_version` is not available (skipped in step 3) → display: "{plugin} {installed_version} (installed) — remote version unknown" and proceed to Part B.
   - Compare `installed_version` and `remote_version` as semantic versions: split each on `.` and compare each component (major, minor, patch) as integers — NOT as strings. To determine which version is smaller, use:
     ```bash
     printf '%s\n' "$installed_version" "$remote_version" | sort -V | head -1
     ```
     If the result equals `$installed_version` and `$installed_version` != `$remote_version`, then `remote_version` is newer.
   - **Up to date:** `installed_version` == `remote_version` → "{plugin} {installed_version} — up to date"
   - **Update available:** `installed_version` < `remote_version` → "{plugin} {installed_version} → {remote_version} — update available. Run: `/plugin uninstall {plugin}` then `/plugin install {plugin}@{marketplace}`"
   - **Locally newer:** `installed_version` > `remote_version` → "{plugin} {installed_version} > {remote_version} — installed version is newer than remote"

### Part B: Repo Comparison (conditional — only when CWD is the plugin's own repo)

5. Check if `.claude-plugin/plugin.json` exists in the current working directory.
   - If not present → skip Part B silently (not in any plugin repo).
   - If present → read the `name` field from it.
   - If `name` does not equal `{plugin}` → skip Part B silently (CWD is a different plugin's repo).
   - If `name` equals `{plugin}` → read `version` from the same file. Store as `repo_version`.

6. If `remote_version` is available and `repo_version` < `remote_version`: auto-pull.
   - Run `git pull` to update the repo to the latest remote version.
   - If `git pull` fails (merge conflict, dirty working tree, etc.) → warn: "git pull failed — repo stays at {repo_version}." and continue with the current `repo_version`.
   - If `git pull` succeeds → re-read `version` from `.claude-plugin/plugin.json` and update `repo_version`.

7. Compare `repo_version` with `installed_version`.
   - Use the same semantic version comparison as step 4.
   - **Match:** "Repo version matches installed plugin ({repo_version})" → skip Part C.
   - **Repo is newer:** "Repo is {repo_version} but installed plugin is {installed_version}" → proceed to Part C (auto-update).
   - **Repo is older:** "Repo is {repo_version} but installed plugin is {installed_version} — repo is behind installed version" → skip Part C.

### Part C: Auto-Update Cache (conditional — only when Part B detects repo is newer)

8. Update the installed plugin cache via CLI commands.
   - Extract the marketplace name from `{registry_key}` — it is the part after the `@` (e.g. `agent-flow@my-fork` → marketplace is `my-fork`). Store as `{actual_marketplace}`.
   - Run the marketplace update followed by the plugin update:
     ```bash
     claude plugin marketplace update {actual_marketplace}
     claude plugin update "{registry_key}" --scope user
     ```
   - If update succeeds → report: "Plugin cache updated: {installed_version} → {repo_version}. Run `/reload-plugins` to apply, or changes take effect on the next Claude Code session."
   - If update fails with EBUSY/locked file error → report: "IDE has files locked. Close Visual Studio (or other IDE), then re-run this command."
   - If update fails for other reasons → report the error and fall back to: "Auto-update failed. Run manually: `/plugin uninstall {plugin}` then `/plugin install {plugin}@{marketplace}`"

## Rules

- Part A (steps 1-4) works from ANY directory — no repo or project dependency
- Part B (steps 5-7) only activates when CWD contains `.claude-plugin/plugin.json` whose `name` field matches the Plugin Identity. Step 6 auto-pulls if repo is behind remote.
- Part C (step 8) only activates when Part B detects repo is newer than installed — auto-syncs the plugin cache
- Part A is read-only. Part B may run `git pull` on the local repo working tree (step 6). Part C may update the installed plugin cache via `claude plugin update` (step 8), only when Part B detects the repo version is ahead of the installed version
- The authoritative source for the installed version is `~/.claude/plugins/installed_plugins.json`, NOT the cache directory structure
- The remote URL is never hardcoded in this file — it is always resolved dynamically via the step 3 source order (`git remote get-url origin` preferred; falling back to the `repository` field in `{install_path}/.claude-plugin/plugin.json`)
- When any step fails or data is unavailable, report clearly what was skipped and why, then continue with what is available — never halt silently
