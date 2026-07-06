# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in agent-flow, please **do not** open a public issue.

**Primary contact:** Report privately by email to **filip.sabacky@ceosdata.com**

Include: a description of the vulnerability, steps to reproduce, and potential impact.

**Alternative:** Use [GitHub Security Advisories](https://github.com/asysta-act/agent-flow/security/advisories/new) to report confidentially through GitHub's native vulnerability reporting.

**Response SLA:** We aim to acknowledge reports within 5 business days and provide a fix, public mitigation guidance, or a coordinated-disclosure timeline extension by mutual agreement.

## Known Limitations

### Advisory-only enforcement — no technical backstop for agent NEVER-constraints

Agent definitions in `agents/*.md` carry hard `NEVER` rules (e.g. publisher's
"NEVER push to main/development directly — always create a PR", "NEVER force
push"). These are prompt-level instructions to the agent, not code-enforced
guarantees. The plugin ships exactly one hook, `hooks/validate-dispatch.sh`
(PostToolUse), and it is:

- **Opt-in** — not auto-installed; operators must add it to
  `~/.claude/settings.json` (see `docs/guides/dispatch-enforcement.md`).
- **Advisory-only even when installed** — PostToolUse fires *after* a tool has
  already executed, so it cannot block or undo a direct push, a force push, or
  any other destructive action. It always exits 0.

In short: nothing in the shipped plugin technically prevents a compromised or
misbehaving agent turn from pushing directly to a protected branch.

**Operator guidance:** treat prompt-level `NEVER` constraints as
defense-in-depth, not as the primary control. MUST enable server-side branch
protection (required PR review + required status checks, no direct pushes,
no force pushes) on `main`/`development` for any repository this plugin is
pointed at. This is the actual enforcement boundary — the plugin's own
guardrails are advisory only.

### Webhook URL — operator trust required

The `Webhook URL` value in `### Notifications` (Automation Config) is dispatched via `curl`
without scheme or host validation beyond `--proto "=http,https"`. A malicious PR that injects
a slow-responding `Webhook URL` could trigger the circuit-breaker (3 consecutive failures,
then suppression for the run).

**Operator guidance:**
- Treat `Webhook URL` changes in PRs as security-relevant and review them carefully.
- Prefer setting `Webhook URL` only in trusted, controlled environments.
- Cross-run circuit persistence and URL allowlist enforcement are planned for a future release.

For the full technical description, see `CLAUDE.md` under "Webhook Payloads".

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest published release (see `version` in `.claude-plugin/plugin.json`, currently 1.2.x) | ✅ Yes |
| All earlier releases | ❌ No |

agent-flow follows the Versioning Policy in `CLAUDE.md` (SemVer). Only the latest published release receives security fixes — there is no backport policy for older MAJOR/MINOR lines. Security fixes ship as a PATCH release per that policy.
