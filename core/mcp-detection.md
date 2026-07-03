# MCP Detection

## Purpose

Determine the expected MCP package and tool prefix for a given tracker or SC type, then verify accessibility and connectivity. Single source of truth for MCP detection logic — prevents duplication between commands that need MCP verification.

Referenced by: `skills/scaffold/SKILL.md` (Step 0-MCP), `skills/check-setup/SKILL.md` (Block 3, Steps 9-10).

## Input Contract

- **tracker_type** (string, required): Issue tracker type from config: `youtrack`, `github`, `jira`, `linear`, `gitea`, `redmine`
- **tracker_instance** (string, optional): Instance URL — used for connectivity check context
- **tracker_project** (string, optional): Project key — used for read connectivity test
- **service_type** (string, required): `"tracker"` or `"sc"` — determines which connectivity test to run
- **check_write** (boolean, optional, default: false): If true, perform canary-write check after successful read check

## Process

> **Path note:** `trackers.md` (MCP Server Detection table) lives in the plugin installation
> directory, not in the consuming project. The calling skill must resolve the path via Glob before
> invoking this contract. The inline table in Process step 1 below is a static built-in fallback
> for callers that cannot Glob (e.g., callers that flow through `core/mcp-preflight.md`).

1. **Look up MCP package and tool prefix** from the MCP Server Detection table in `docs/reference/trackers.md`:

| Tracker type | Transport | Endpoint / Package | Tool prefix |
|-------------|-----------|-------------------|-------------|
| youtrack | HTTP | `https://<INSTANCE>.youtrack.cloud/mcp` | `mcp__youtrack__*` |
| github | HTTP | `https://api.githubcopilot.com/mcp/` | `mcp__github__*` |
| jira | HTTP | `https://mcp.atlassian.com/v1/mcp` | `mcp__jira__*` or `mcp__atlassian__*` |
| linear | HTTP | `https://mcp.linear.app/mcp` | `mcp__linear__*` |
| gitea | stdio (binary) | `gitea-mcp` binary | `mcp__gitea__*` |
| redmine | stdio (uvx) | `uvx --from mcp-redmine==2026.01.13.152335 mcp-redmine` | `mcp__redmine__*` |
| (unknown) | — | — | `mcp__{tracker_type}__*` (best-effort) |

**YouTrack community fallback (legacy on-prem <2026.1):** `@vitalyostanin/youtrack-mcp` via npx — use only when user explicitly selects the pre-2026.1 on-prem path.

2. **Check tool accessibility.** Scan available tools for at least one tool matching the prefix.

3. **If tool found — verify read connectivity:**
   - If `service_type` is `"tracker"`: attempt to list 1 issue from the declared project (or list projects if no project specified)
   - If `service_type` is `"sc"`: attempt to verify the declared remote exists
   - If connectivity fails: set `mcp_available = false`, capture error

4. **If `check_write` is true AND read check passed (tracker only):**
   - First, check if a stale canary exists: search for open issues with title starting with `[agent-flow] canary`. If found, delete it before creating a new one (prevents canary spam from prior failed cleanups).
   - Create a canary item: issue/card with title `[agent-flow] canary — safe to delete`
   - If create succeeds: delete the canary item immediately. Set `write_available = true`, `write_cleanup_failed = false`.
   - If create fails: set `write_available = false`, `write_cleanup_failed = false`. Do NOT block — write failure is advisory.
   - If delete fails after successful create: set `write_available = true` (write demonstrably works), `write_cleanup_failed = true`. Log warning.

## Output Contract

- **mcp_available** (boolean): `true` if MCP tool is accessible and read connectivity succeeds
- **write_available** (boolean or null): `true` if canary-write succeeded (create + delete both OK), `false` if create failed, `null` if not tested (`check_write` was false)
- **write_cleanup_failed** (boolean): `true` if canary was created but deletion failed (write works, but a stale canary item exists). `false` otherwise.
- **package_name** (string): Expected MCP package name from lookup table
- **tool_prefix** (string): Expected tool prefix pattern
- **error** (string or null): Error message if `mcp_available` is false, null otherwise
- **error_type** (string or null): Classification of the error when `mcp_available` is false.
  Values: `"tls"` (certificate/TLS error), `"auth"` (authentication failure, 401/403),
  `"not_found"` (404 or DNS resolution failure), `"timeout"` (connection timeout or refused),
  `"unknown"` (unclassified error). `null` when `mcp_available` is true.
  See Failure Handling > Classification Reference for classification logic.
- **write_error** (string or null): Error message if `write_available` is false or `write_cleanup_failed` is true, null otherwise

## Failure Handling

- **No matching MCP tool found:** Return `mcp_available: false`, `error: "No MCP tool matching prefix {tool_prefix} found in current session"`, `error_type: "unknown"`. Caller decides whether to block or downgrade.
- **Read connectivity fails:** Return `mcp_available: false`, `error: "{error message from failed test call}"`, `error_type: {classified per Classification Reference below}`. Caller decides action.
- **Write canary create fails:** Return `mcp_available: true`, `write_available: false`, `write_error: "{error from canary create}"`, `error_type: null`. Caller decides action (warn, downgrade, or ignore).
- **Write canary delete fails (create succeeded):** Return `mcp_available: true`, `write_available: true`, `write_cleanup_failed: true`, `write_error: "Canary item created but not deleted — manual cleanup needed"`, `error_type: null`. Write access demonstrably works; the cleanup failure is advisory.
- **Unknown tracker type:** Attempt detection with derived prefix `mcp__{tracker_type}__*`. Return `mcp_available: false` only if tool is actually missing — never block on unknown type alone.

### Classification Reference

Classify the error string in priority order (first match wins):

| Priority | error_type | Trigger patterns |
|----------|-----------|-----------------|
| 1 | `"tls"` | UNABLE_TO_VERIFY_LEAF_SIGNATURE, CERT_UNTRUSTED, SELF_SIGNED_CERT, self signed certificate, certificate verify failed, ERR_TLS_, DEPTH_ZERO_SELF_SIGNED_CERT, unable to get local issuer certificate |
| 2 | `"auth"` | 401, 403, unauthorized, forbidden, invalid token, authentication |
| 3 | `"not_found"` | 404, not_found, not found, ENOTFOUND, EAI_AGAIN |
| 4 | `"timeout"` | timeout, ETIMEDOUT, ECONNREFUSED, ECONNRESET |
| 5 | `"unknown"` | All remaining errors |

Note: `ECONNREFUSED` is classified under `"timeout"` (not `"not_found"`) because the server address resolved but the connection was refused — the remediation is "verify the server is running and the port is correct", which aligns with timeout/unreachable guidance. `ENOTFOUND` and `EAI_AGAIN` are classified under `"not_found"` because these are DNS resolution failures — the hostname does not resolve.

This Classification Reference table is the canonical single source for these trigger-pattern lists.
`skills/check-setup/SKILL.md` Steps 9-10 mirror the `"tls"` and `"auth"` rows above (adapted to also
gate a curl confirmation probe) rather than the reverse — if a pattern is added or changed here,
mirror the change into both copies in `skills/check-setup/SKILL.md`.
